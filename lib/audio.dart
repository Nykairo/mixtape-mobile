/// The music: a queue of songs played by just_audio inside audio_service's service, so it keeps going
/// with the screen off and shows in the notification, on the lock screen and on the home screen widget.
///
/// YouTube songs don't have an address that lasts: the address is looked up when a song is about to
/// play (Links), and the song's bytes come through [YouTubeSource], which looks it up again when YouTube
/// lets it run out and carries on where the connection broke, the way the desktop's relay does.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:mixtape_native/mixtape_native.dart';

import 'model.dart';
import 'store.dart';
import 'youtube.dart';

const _sessionFile = 'session.json';

int _seconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

// ---------------------------------------------------------------- where songs stream from

/// A song's audio address, good until [expires] (unix seconds).
class Link {
  Link(this.url, this.agent, this.mime, this.length, this.expires, int bitrate)
      // the extractor says kbit/s, sometimes bit/s; either way bytes per second come out
      : bytesPerSecond = max(16000, (bitrate > 0 && bitrate < 10000 ? bitrate * 1000 : bitrate) ~/ 8);

  final Uri url;
  final String agent;
  final String mime;
  final int length;
  final int expires;
  final int bytesPerSecond;

  bool get fresh => expires - _seconds() > 300;
}

/// Looks up and remembers where songs stream from, and the songs YouTube calls like them.
class Links {
  static final _links = <String, Link>{};
  static final _asking = <String, Future<Link>>{};
  static final _related = <String, List<Track>>{};

  /// Why a song wouldn't play, by YouTube id: age, region, private, members, busy, gone, network, trouble.
  static final trouble = <String, String>{};

  static Future<Link> get(String id, {bool fresh = false}) {
    final have = _links[id];
    if (!fresh && have != null && have.fresh) return Future.value(have);
    return _asking[id] ??= _look(id).whenComplete(() {
      _asking.remove(id);
    });
  }

  /// Looks a song up ahead of time, so it starts at once when its turn comes. Quietly.
  static void warm(Track t) {
    if (t.src == 'yt') get(t.ref).ignore();
  }

  static List<Track> related(String id) => _related[id] ?? const [];

  static Future<Link> _look(String id) async {
    try {
      final m = await YouTube.resolve(id);
      final link = Link(Uri.parse('${m['url']}'), '${m['agent'] ?? ''}', '${m['mime'] ?? 'audio/mp4'}',
          _int(m['length']), _int(m['expires']), _int(m['bitrate']));
      _links[id] = link;
      final rel = m['related'];
      if (rel is List) {
        _related[id] = [
          for (final x in rel)
            if (x is Map) Track.fromYouTube(Map<String, Object?>.from(x)),
        ];
      }
      trouble.remove(id);
      while (_links.length > 80) {
        _links.remove(_links.keys.first);
      }
      while (_related.length > 80) {
        _related.remove(_related.keys.first);
      }
      return link;
    } on YouTubeError catch (e) {
      trouble[id] = e.why;
      rethrow;
    }
  }

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? -1);
}

/// A YouTube song's bytes for the player, through just_audio's little server on the phone itself.
/// It asks YouTube for a piece at a time; a piece that breaks off is asked for again from where it
/// broke, and an address YouTube stopped taking is looked up again, so the player never notices.
/// It reads ahead a few minutes of music and then only a little faster than the music plays, so a
/// long song never piles up in memory.
// ignore: experimental_member_use
class YouTubeSource extends StreamAudioSource {
  YouTubeSource(this.track, this.client) : super(tag: track.id);

  final Track track;
  final http.Client client;
  int _size = -1;

  static const _piece = 1 << 20; // a megabyte: about a minute of music, asked for at a time
  static const _ahead = 3 << 20; // read right away, before the pace kicks in

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final link = await Links.get(track.ref);
    if (_size <= 0) _size = link.length > 0 ? link.length : await _sizeOf(link);
    final from = start ?? 0;
    final to = min(end ?? _size, _size);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _size,
      contentLength: max(0, to - from),
      offset: from,
      contentType: link.mime.split(';').first.trim(),
      stream: _bytes(from, to),
    );
  }

  /// The song's size, from the first byte's answer, when the lookup didn't say it.
  Future<int> _sizeOf(Link link) async {
    final req = http.Request('GET', link.url)
      ..headers['Range'] = 'bytes=0-0'
      ..headers['User-Agent'] = link.agent;
    final res = await client.send(req).timeout(const Duration(seconds: 12));
    await res.stream.drain<void>();
    final range = res.headers['content-range'] ?? '';
    final total = int.tryParse(range.split('/').last) ?? -1;
    if (total <= 0) throw const HttpException('no size');
    return total;
  }

  Stream<List<int>> _bytes(int from, int to) async* {
    var at = from;
    var refused = 0;
    var broken = 0;
    final clock = Stopwatch()..start();
    while (at < to) {
      final link = await Links.get(track.ref, fresh: refused > 0);
      // three times as fast as it plays is plenty to stay ahead, and keeps the phone's memory free
      final allowed = _ahead + clock.elapsedMilliseconds * link.bytesPerSecond * 3 ~/ 1000;
      if (at - from > allowed) {
        final wait = (at - from - allowed) * 1000 ~/ (link.bytesPerSecond * 3);
        await Future<void>.delayed(Duration(milliseconds: min(wait, 20000)));
      }
      final last = min(to, at + _piece) - 1;
      http.StreamedResponse res;
      try {
        final req = http.Request('GET', link.url)
          ..headers['Range'] = 'bytes=$at-$last'
          ..headers['User-Agent'] = link.agent;
        res = await client.send(req).timeout(const Duration(seconds: 15));
      } on Object {
        if (++broken > 6) rethrow; // the network is gone for a while: the player hears of it
        await Future<void>.delayed(_backoff(broken));
        continue;
      }
      if (res.statusCode == 403 || res.statusCode == 410) {
        await res.stream.drain<void>().catchError((Object _) {});
        if (++refused > 3) throw HttpException('YouTube refused ${track.ref} (${res.statusCode})');
        continue; // the address ran out: a fresh one, and on from the same byte
      }
      if (res.statusCode == 416) {
        await res.stream.drain<void>().catchError((Object _) {});
        return; // the song ended sooner than it said
      }
      if (res.statusCode != 206 && res.statusCode != 200) {
        await res.stream.drain<void>().catchError((Object _) {});
        if (++broken > 6) throw HttpException('YouTube answered ${res.statusCode}');
        await Future<void>.delayed(_backoff(broken));
        continue;
      }
      var skip = res.statusCode == 200 ? at : 0; // a whole file where a piece was asked for
      try {
        await for (var chunk in res.stream.timeout(const Duration(seconds: 15))) {
          if (skip > 0) {
            if (chunk.length <= skip) {
              skip -= chunk.length;
              continue;
            }
            chunk = chunk.sublist(skip);
            skip = 0;
          }
          if (at + chunk.length > to) chunk = chunk.sublist(0, to - at);
          at += chunk.length;
          refused = 0;
          broken = 0;
          yield chunk;
          if (at >= to) return;
        }
      } on Object {
        if (++broken > 6) rethrow;
        await Future<void>.delayed(_backoff(broken));
      }
    }
  }

  static Duration _backoff(int tries) => Duration(milliseconds: min(5000, 400 * tries * tries));
}

// ---------------------------------------------------------------- the player

/// The order shuffle plays the queue in. Unlike just_audio's own, songs that come in go where they were
/// meant to: "Play next" right after the song that plays, "Add to queue" at the very end.
class QueueOrder extends ShuffleOrder {
  final _random = Random();

  @override
  final List<int> indices = [];

  /// Set while "Play next" puts a song in: the song that plays now (its index in the queue).
  int? after;

  @override
  void shuffle({int? initialIndex}) {
    indices.shuffle(_random);
    if (initialIndex != null && indices.remove(initialIndex)) indices.insert(0, initialIndex);
  }

  @override
  void insert(int index, int count) {
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
    final fresh = List.generate(count, (k) => index + k);
    final now = after;
    final at = now == null ? -1 : indices.indexOf(now >= index ? now + count : now);
    if (at < 0) {
      indices.addAll(fresh);
    } else {
      indices.insertAll(at + 1, fresh);
    }
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    indices.removeWhere((i) => i >= start && i < end);
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) indices[i] -= count;
    }
  }

  @override
  void clear() => indices.clear();
}

/// What the app shows about the queue: the songs in the order they play, and which one plays.
class QueueView {
  const QueueView(this.songs, this.index);

  final List<Track> songs;
  final int index;

  Track? get current => index >= 0 && index < songs.length ? songs[index] : null;
}

class MixtapeAudio extends BaseAudioHandler with QueueHandler, SeekHandler {
  MixtapeAudio() {
    _ready = _start();
  }

  final _player = AudioPlayer(useProxyForRequestHeaders: false);
  final _order = QueueOrder();
  final _client = http.Client();
  late final Future<void> _ready;

  /// The songs, in the order they were put in (shuffle plays them in another order, see [view]).
  final List<Track> _songs = [];

  /// The app's own news: things to tell the person (a song that won't play, say).
  final notices = StreamController<String>.broadcast();

  /// Keeps the music going with songs like the last one when the queue runs out.
  bool autoplay = true;

  /// Called with each song that starts, for the library's "played lately".
  void Function(Track)? onPlayed;

  /// Where the music comes from, for "Playing from" ('Liked songs', a tape's name, 'Search'...), and
  /// the tape's own name when it's a tape, so the big player can show that cassette.
  String from = '';
  String fromTape = '';

  Timer? _keep;
  String _lastStarted = '';
  int _retries = 0;
  bool _filling = false;

  Track? get current {
    final i = _player.currentIndex;
    return i != null && i >= 0 && i < _songs.length ? _songs[i] : null;
  }

  AudioPlayer get player => _player;

  Stream<Duration> get position => _player.positionStream;

  /// The queue as it plays (shuffled when shuffle is on), and where in it the music is.
  QueueView get view {
    final s = _player.sequenceState;
    final i = _player.currentIndex ?? -1;
    if (_songs.isEmpty || i < 0) return QueueView(List.unmodifiable(_songs), i);
    final order = _player.shuffleModeEnabled ? s.shuffleIndices : List.generate(_songs.length, (k) => k);
    final songs = [
      for (final k in order)
        if (k < _songs.length) _songs[k],
    ];
    return QueueView(songs, order.indexOf(i));
  }

  Stream<QueueView> get views => _player.sequenceStateStream.map((_) => view);

  Future<void> _start() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _player.playbackEventStream.listen(_broadcast);
    _player.errorStream.listen(_failed);
    _player.currentIndexStream.listen(_moved);
    _player.shuffleModeEnabledStream.listen((_) => _broadcast(_player.playbackEvent));
    _player.loopModeStream.listen((_) => _broadcast(_player.playbackEvent));
    _player.playingStream.listen((playing) {
      _keepSaving(playing);
      _widget();
      if (!playing) _saveSession();
    });
    await _restore();
  }

  // ------------------------------------------------------------ the queue

  AudioSource _source(Track t) =>
      t.src == 'yt' ? YouTubeSource(t, _client) : AudioSource.uri(Uri.parse(t.ref), tag: t.id);

  MediaItem _item(Track t) => MediaItem(
        id: t.id,
        title: t.title.isEmpty ? 'Untitled' : t.title,
        artist: t.artist,
        album: t.album.isEmpty ? null : t.album,
        duration: t.dur > 0 ? Duration(seconds: t.dur) : null,
        artUri: t.artAt(544).isEmpty ? null : Uri.tryParse(t.artAt(544)),
      );

  /// Plays these songs from [start] (songs that can't play on a phone are left out).
  Future<void> playSongs(List<Track> songs,
      {int start = 0, bool shuffle = false, Duration? at, String from = '', String tape = ''}) async {
    await _ready;
    this.from = from;
    fromTape = tape;
    final pick = songs.isEmpty ? null : songs[start.clamp(0, songs.length - 1)];
    final list = [
      for (final t in songs)
        if (t.playable) t,
    ];
    if (list.isEmpty) {
      notices.add("Those songs don't play on a phone (they're files on a computer).");
      return;
    }
    var first = pick == null ? 0 : list.indexOf(pick);
    if (first < 0) first = 0;
    if (shuffle) first = Random().nextInt(list.length);
    Links.warm(list[first]);
    _retries = 0;
    await _setSongs(list, first, at ?? Duration.zero, preload: false);
    if (shuffle != _player.shuffleModeEnabled) await _player.setShuffleModeEnabled(shuffle);
    if (shuffle) await _player.shuffle();
    _go();
  }

  Future<void> _setSongs(List<Track> list, int index, Duration at, {bool preload = true}) async {
    _songs
      ..clear()
      ..addAll(list);
    queue.add([for (final t in list) _item(t)]);
    try {
      await _player.setAudioSources([for (final t in list) _source(t)],
          initialIndex: index, initialPosition: at, preload: preload, shuffleOrder: _order);
    } on PlayerInterruptedException {
      // another queue came in meanwhile
    } on PlayerException {
      // errorStream has it too, and _failed takes it from there
    }
  }

  /// Starts the music. Not waited for: just_audio's play() returns only when the music pauses.
  void _go() => unawaited(_player.play().catchError((Object _) {}));

  /// Puts a song right after the one playing.
  Future<void> playNext(Track t) async {
    await _ready;
    if (!t.playable) return;
    if (_songs.isEmpty) return playSongs([t]);
    final now = _player.currentIndex ?? -1;
    final at = now + 1;
    _songs.insert(at, t);
    queue.add([for (final s in _songs) _item(s)]);
    _order.after = now; // and in shuffle's order too, right after the song that plays
    try {
      await _player.insertAudioSource(at, _source(t));
    } finally {
      _order.after = null;
    }
  }

  /// Puts songs at the end of the queue.
  Future<void> addSongs(List<Track> songs) async {
    await _ready;
    final list = [
      for (final t in songs)
        if (t.playable) t,
    ];
    if (list.isEmpty) return;
    if (_songs.isEmpty) return playSongs(list);
    _songs.addAll(list);
    queue.add([for (final s in _songs) _item(s)]);
    await _player.addAudioSources([for (final t in list) _source(t)]);
  }

  /// Takes a song out of the queue, by its place in [view].
  Future<void> removeShown(int shown) async {
    final order = _player.shuffleModeEnabled ? _player.sequenceState.shuffleIndices : null;
    final k = order == null ? shown : (shown < order.length ? order[shown] : -1);
    if (k < 0 || k >= _songs.length || k == _player.currentIndex) return;
    _songs.removeAt(k);
    queue.add([for (final s in _songs) _item(s)]);
    await _player.removeAudioSourceAt(k);
  }

  /// Plays the song at its place in [view].
  Future<void> playShown(int shown) async {
    final order = _player.shuffleModeEnabled ? _player.sequenceState.shuffleIndices : null;
    final k = order == null ? shown : (shown < order.length ? order[shown] : -1);
    if (k >= 0) await skipToQueueItem(k);
  }

  void _moved(int? index) {
    final t = current;
    if (t == null) return;
    mediaItem.add(_item(t));
    _widget();
    if (t.id != _lastStarted) {
      _lastStarted = t.id;
      _retries = 0;
      onPlayed?.call(t);
      _saveSession();
    }
    final view = this.view;
    if (view.index + 1 < view.songs.length) {
      Links.warm(view.songs[view.index + 1]); // the next one's address, ready when it's its turn
    } else {
      _keepGoing(t);
    }
  }

  /// The last song of the queue plays: songs like it go on after it (like the radio on the computer).
  Future<void> _keepGoing(Track last) async {
    if (!autoplay || _filling || _player.loopMode != LoopMode.off || last.src != 'yt') return;
    _filling = true;
    try {
      var like = Links.related(last.ref);
      if (like.isEmpty) {
        await Links.get(last.ref);
        like = Links.related(last.ref);
      }
      final have = {for (final t in _songs) t.id};
      final fresh = [
        for (final t in like)
          if (t.ref.isNotEmpty && have.add(t.id)) t,
      ].take(10).toList();
      if (fresh.isNotEmpty && current?.id == last.id) await addSongs(fresh);
    } on Object {
      // no songs like it right now: the queue just ends
    } finally {
      _filling = false;
    }
  }

  // ------------------------------------------------------------ what the system shows

  void _broadcast(PlaybackEvent event) {
    final playing = _player.playing;
    if (_player.processingState == ProcessingState.ready) _retries = 0; // it plays: trouble is over
    final queueIndex = event.currentIndex;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: queueIndex,
      shuffleMode: _player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[_player.loopMode]!,
    ));
  }

  /// A song wouldn't load. A song YouTube won't give is skipped with a word about it; when it's the
  /// network, the same song is tried again a little later, from where it was.
  void _failed(Object e, [StackTrace? st]) {
    final t = current;
    if (t == null) return;
    final why = Links.trouble[t.ref];
    if (why != null && why != 'network' && why != 'busy') {
      notices.add('Skipped ${t.title}: ${_words[why] ?? _words['trouble']}');
      if (_player.hasNext) {
        _player.seekToNext().then((_) => _go()).catchError((Object _) {});
      }
      return;
    }
    if (_retries >= 6) {
      notices.add("${t.title} won't load right now. Check the internet connection.");
      _retries = 0;
      _player.pause().ignore();
      return;
    }
    _retries++;
    final at = _player.position;
    final index = _player.currentIndex ?? 0;
    final wasPlaying = _player.playing;
    Future<void>.delayed(Duration(seconds: 2 * _retries), () async {
      if (current?.id != t.id) return;
      await _setSongs(List.of(_songs), index, at, preload: false);
      if (wasPlaying) _go();
    });
  }

  static const _words = {
    'age': 'YouTube wants a signed-in adult for it.',
    'region': "it isn't available in this country.",
    'private': "it's private.",
    'members': "it's for channel members only.",
    'gone': 'it was taken down.',
    'busy': 'YouTube asks to slow down for a moment.',
    'trouble': "YouTube wouldn't give it.",
  };

  // ------------------------------------------------------------ the keys (notification, lock screen, headset)

  @override
  Future<void> play() async {
    await _ready;
    if (_songs.isNotEmpty) _go();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    } else {
      final t = current;
      if (t != null) await _keepGoing(t);
      if (_player.hasNext) await _player.seekToNext();
    }
  }

  /// Back: to the start of the song, or to the one before when it only just began.
  @override
  Future<void> skipToPrevious() async {
    if (_player.position > const Duration(seconds: 4) || !_player.hasPrevious) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;
    await _player.seek(Duration.zero, index: index);
    _go();
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final on = shuffleMode != AudioServiceShuffleMode.none;
    if (on) await _player.shuffle();
    await _player.setShuffleModeEnabled(on);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) => _player.setLoopMode(const {
        AudioServiceRepeatMode.none: LoopMode.off,
        AudioServiceRepeatMode.one: LoopMode.one,
        AudioServiceRepeatMode.all: LoopMode.all,
        AudioServiceRepeatMode.group: LoopMode.all,
      }[repeatMode]!);

  @override
  Future<void> stop() async {
    await _saveSession();
    await _player.stop();
    await _widget();
    await super.stop();
  }

  /// The app was swiped away: music that plays keeps playing; paused, the service goes too.
  @override
  Future<void> onTaskRemoved() async {
    if (!_player.playing) await stop();
  }

  // ------------------------------------------------------------ coming back where it was

  Future<void> _restore() async {
    final j = await Store.the.read(_sessionFile);
    if (j is! Map) return;
    final songs = [
      for (final x in j['songs'] is List ? j['songs'] as List : const [])
        if (Track.fromJson(x) case final Track t)
          if (t.playable) t,
    ];
    if (songs.isEmpty) return;
    final index = (j['index'] is int ? j['index'] as int : 0).clamp(0, songs.length - 1);
    final at = Duration(milliseconds: j['position'] is int ? j['position'] as int : 0);
    _lastStarted = songs[index].id; // it played already; coming back doesn't count it again
    from = '${j['from'] ?? ''}';
    fromTape = '${j['from_tape'] ?? ''}';
    mediaItem.add(_item(songs[index]));
    if (j['shuffle'] == true) await _player.setShuffleModeEnabled(true);
    final loop = j['loop'];
    if (loop is int && loop >= 0 && loop < LoopMode.values.length) await _player.setLoopMode(LoopMode.values[loop]);
    // loaded and waiting, so Play starts it at once (the song's address is looked up right away);
    // not waited for, so the keys work while it loads
    Links.warm(songs[index]);
    unawaited(_setSongs(songs, index, at, preload: true));
  }

  Future<void> _saveSession() async {
    if (_songs.isEmpty) return;
    try {
      await Store.the.write(_sessionFile, {
        'songs': [for (final t in _songs.take(500)) t.toJson()],
        'index': _player.currentIndex ?? 0,
        'position': _player.position.inMilliseconds,
        'shuffle': _player.shuffleModeEnabled,
        'loop': _player.loopMode.index,
        'from': from,
        'from_tape': fromTape,
      });
    } on FileSystemException {
      // a full phone: next time
    }
  }

  void _keepSaving(bool playing) {
    _keep?.cancel();
    _keep = playing ? Timer.periodic(const Duration(seconds: 15), (_) => _saveSession()) : null;
  }

  Future<void> saveNow() => _saveSession();

  // ------------------------------------------------------------ the home screen widget

  String _widgetArtFor = '';

  Future<void> _widget() async {
    final t = current;
    if (t == null) return;
    var art = '';
    final cover = t.artAt(300);
    final file = Store.the.file('widget_cover.jpg');
    if (cover.isNotEmpty) {
      if (_widgetArtFor != t.id) {
        try {
          final res = await _client.get(Uri.parse(cover)).timeout(const Duration(seconds: 10));
          if (res.statusCode == 200 && res.bodyBytes.length < 2000000) {
            await file.writeAsBytes(res.bodyBytes, flush: true);
            _widgetArtFor = t.id;
          }
        } on Object {
          _widgetArtFor = '';
        }
      }
      if (_widgetArtFor == t.id) art = file.path;
    }
    if (current?.id != t.id) return; // another song meanwhile; its own call draws it
    await MixtapeNative.widget(title: t.title, artist: t.artist, playing: _player.playing, art: art);
  }

  @visibleForTesting
  List<Track> get songs => List.unmodifiable(_songs);
}
