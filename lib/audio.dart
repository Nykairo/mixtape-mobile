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

import 'blend.dart';
import 'downloads.dart';
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

  Map<String, Object?> toJson() =>
      {'url': '$url', 'agent': agent, 'mime': mime, 'length': length, 'expires': expires, 'bps': bytesPerSecond};

  static Link? fromJson(Map<Object?, Object?> j) {
    final url = Uri.tryParse('${j['url'] ?? ''}');
    if (url == null || !url.hasScheme) return null;
    int n(Object? v) => v is int ? v : -1;
    return Link(url, '${j['agent'] ?? ''}', '${j['mime'] ?? 'audio/mp4'}', n(j['length']), n(j['expires']), n(j['bps']) * 8);
  }
}

/// Looks up and remembers where songs stream from, and the songs YouTube calls like them.
class Links {
  static final _links = <String, Link>{};
  static final _asking = <String, Future<Link>>{};
  static final _related = <String, List<Track>>{};

  /// Why a song wouldn't play, by YouTube id: age, region, private, members, busy, gone, network, trouble.
  static final trouble = <String, String>{};

  static final _keep = LaterSave('links.json', () => {
        for (final e in _links.entries)
          if (e.value.expires - _seconds() > 1800) e.key: e.value.toJson(),
      });

  /// The addresses kept from the last time Mixtape ran (they hold for a few hours), so the first song
  /// after the start plays at once. One YouTube no longer takes is simply asked for anew.
  static Future<void> load() async {
    final j = await Store.the.read('links.json');
    if (j is! Map) return;
    for (final e in j.entries) {
      final v = e.value;
      final link = v is Map ? Link.fromJson(v) : null;
      if (link != null && link.fresh) _links.putIfAbsent('${e.key}', () => link);
    }
  }

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

  /// Songs like this one: what came with its address, or else asked for (a radio from it), and kept.
  static Future<List<Track>> relatedOf(String id) async {
    final have = _related[id];
    if (have != null && have.isNotEmpty) return have;
    final found = [for (final m in await YouTube.related(id)) Track.fromYouTube(m)];
    _related[id] = found;
    while (_related.length > 80) {
      _related.remove(_related.keys.first);
    }
    return found;
  }

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
      _keep.soon();
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

/// The first seconds of the song that comes next, read while this one plays, so that skipping to it
/// starts the moment the key is pressed (the computer does the same). Two songs at most, a few hundred
/// kilobytes each; YouTubeSource sends them out first and goes on from YouTube after them.
class Heads {
  static const size = 384 << 10; // about twenty seconds of music
  static final _kept = <String, ({Uint8List bytes, int length, String mime})>{};
  static final _reading = <String, Future<void>>{};

  /// A song's first bytes, when they're here and from the same file the address leads to.
  static Uint8List? of(String id, Link link) {
    final h = _kept[id];
    return h != null && h.length == link.length && h.mime == link.mime ? h.bytes : null;
  }

  /// Reads the start of a song into memory, quietly. Once per song.
  static Future<void> read(Track t, http.Client client) {
    if (t.src != 'yt' || _kept.containsKey(t.ref)) return Future.value();
    return _reading[t.ref] ??= _read(t.ref, client).whenComplete(() => _reading.remove(t.ref));
  }

  static Future<void> _read(String id, http.Client client) async {
    try {
      final link = await Links.get(id);
      if (link.length <= 0) return; // a size it didn't say: no telling the file is the same later
      final req = http.Request('GET', link.url)
        ..headers['Range'] = 'bytes=0-${min(link.length, size) - 1}'
        ..headers['User-Agent'] = link.agent;
      final res = await client.send(req).timeout(const Duration(seconds: 15));
      if (res.statusCode != 206) {
        await res.stream.drain<void>().catchError((Object _) {});
        return;
      }
      final bytes = await res.stream.toBytes().timeout(const Duration(seconds: 30));
      _kept[id] = (bytes: bytes, length: link.length, mime: link.mime);
      while (_kept.length > 2) {
        _kept.remove(_kept.keys.first);
      }
    } on Object {
      // then it starts the usual way, from YouTube
    }
  }
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
    if (_size <= 0) _size = await size();
    final from = start ?? 0;
    final to = min(end ?? _size, _size);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _size,
      contentLength: max(0, to - from),
      offset: from,
      contentType: link.mime.split(';').first.trim(),
      stream: bytes(from, to),
    );
  }

  /// How many bytes the song has.
  Future<int> size() async {
    if (_size > 0) return _size;
    final link = await Links.get(track.ref);
    return _size = link.length > 0 ? link.length : await _sizeOf(link);
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

  /// The song's bytes from [from] up to [to]. [paced]: a few minutes ahead and then only a little faster
  /// than the music plays (for playing); without, as fast as they come (for saving it offline).
  Stream<List<int>> bytes(int from, int to, {bool paced = true}) async* {
    var at = from;
    var refused = 0;
    var broken = 0;
    final clock = Stopwatch()..start();
    // the start read ahead (Heads) goes out at once; YouTube carries on after it
    final head = Heads.of(track.ref, await Links.get(track.ref));
    if (head != null && at < head.length) {
      final end = min(to, head.length);
      yield Uint8List.sublistView(head, at, end);
      at = end;
    }
    while (at < to) {
      final link = await Links.get(track.ref, fresh: refused > 0);
      // three times as fast as it plays is plenty to stay ahead, and keeps the phone's memory free
      final allowed = _ahead + clock.elapsedMilliseconds * link.bytesPerSecond * 3 ~/ 1000;
      if (paced && at - from > allowed) {
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

/// How much of a song Android's player wants before it starts: under a second instead of two and a half
/// (the bytes come from the phone itself, through YouTubeSource, so they rarely run dry), and a little
/// more after it ran dry once.
const quickStart = AudioLoadConfiguration(
  androidLoadControl: AndroidLoadControl(
    bufferForPlaybackDuration: Duration(milliseconds: 800),
    bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
  ),
);

class MixtapeAudio extends BaseAudioHandler with QueueHandler, SeekHandler {
  MixtapeAudio() {
    _ready = _start();
  }

  final _player = AudioPlayer(useProxyForRequestHeaders: false, audioLoadConfiguration: quickStart);
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

  /// Called when a song stops being the one that plays, with how long it was heard, for the stats.
  void Function(Track t, int seconds, DateTime started)? onHeard;

  /// Songs the person isn't interested in: the music that keeps going leaves them out.
  bool Function(Track)? unwanted;

  /// While listening along or in a room, the keys go there instead (together.dart): true when taken.
  bool Function(String key, [Duration? at])? steer;

  /// The music card's own keys next to play (settings.dart's cardKeyNames, Android 13 and newer show
  /// two), and what they need from the library: whether a song is liked, liking it, not wanting it.
  List<String> cardKeys = const ['like', 'shuffle'];
  bool Function(Track)? isLiked;
  bool Function(Track)? toggleLike;
  void Function(Track)? hideSong;
  String _cardShown = '';

  /// Where the music comes from, for "Playing from" ('Liked songs', a tape's name, 'Search'...), and
  /// the tape's own name when it's a tape, so the big player can show that cassette.
  String from = '';
  String fromTape = '';

  Timer? _keep;
  Timer? _sleep;
  String _lastStarted = '';
  Track? _heard;
  DateTime _heardFrom = DateTime.now();
  final _heardClock = Stopwatch();
  int _retries = 0;
  bool _filling = false;

  Track? get current {
    final i = _player.currentIndex;
    return i != null && i >= 0 && i < _songs.length ? _songs[i] : null;
  }

  AudioPlayer get player => _player;

  /// Done once the player is set up and the last session is back.
  Future<void> get ready => _ready;

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
    sleepNews.stream.listen((_) => refreshCard());
    _player.playingStream.listen((playing) {
      _keepSaving(playing);
      if (!playing) _endBlend(); // a call or a headset pulled out: the end of the last song goes quiet too
      if (playing) {
        _heardClock.start();
      } else {
        _heardClock.stop();
        _saveSession();
      }
    });
    _player.positionStream.listen(_nearTheEnd);
    await _restore();
  }

  // ------------------------------------------------------------ the queue

  AudioSource _source(Track t) {
    final saved = Downloads.the.fileOf(t);
    if (saved != null) return AudioSource.file(saved, tag: t.id); // on the phone: no internet needed
    if (t.fromPhone && t.ref.startsWith('/')) return AudioSource.file(t.ref, tag: t.id); // an iPhone's copy
    return t.src == 'yt' ? YouTubeSource(t, _client) : AudioSource.uri(Uri.parse(t.ref), tag: t.id);
  }

  MediaItem _item(Track t) => MediaItem(
        id: t.id,
        title: t.title.isEmpty ? 'Untitled' : t.title,
        artist: t.artist,
        album: t.album.isEmpty ? null : t.album,
        duration: t.dur > 0 ? Duration(seconds: t.dur) : null,
        // big enough for the cover behind the whole music card
        artUri: _artUri(t.artAt(720)),
      );

  /// A cover on the internet, or (a phone file's own) in a file here.
  static Uri? _artUri(String art) => art.isEmpty ? null : (art.startsWith('/') ? Uri.file(art) : Uri.tryParse(art));

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
    _endBlend();
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

  /// Listening along or in a room (together.dart): this song, from this spot, playing or not, at this
  /// speed. The queue is the one song; a jump only when it drifted more than a moment apart.
  Future<void> followSong(Track t, Duration at, {required bool playing, double rate = 1, String from = ''}) async {
    await _ready;
    this.from = from;
    fromTape = '';
    if (current?.id != t.id) {
      Links.warm(t);
      _retries = 0;
      await _setSongs([t], 0, at, preload: true);
    } else if ((_player.position - at).abs() > const Duration(milliseconds: 1500)) {
      await _player.seek(at);
    }
    if ((_player.speed - rate).abs() > 0.01) await _player.setSpeed(rate);
    if (playing && !_player.playing) {
      _go();
    } else if (!playing && _player.playing) {
      await _player.pause();
    }
  }

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

  /// Moves a song in the queue, from one place in [view] to another (not while shuffle is on: the
  /// shuffled order is its own).
  Future<void> moveShown(int from, int to) async {
    if (_player.shuffleModeEnabled || from == to || from < 0 || from >= _songs.length || to < 0 || to >= _songs.length) {
      return;
    }
    final t = _songs.removeAt(from);
    _songs.insert(to, t);
    queue.add([for (final s in _songs) _item(s)]);
    await _player.moveAudioSource(from, to);
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
    if (t.id != _lastStarted) {
      _lastStarted = t.id;
      _retries = 0;
      _countHeard(t);
      onPlayed?.call(t);
      _saveSession();
      if (sleepAtEnd && _player.playing) {
        // the song the sleep timer waited for ended a moment ago: this one waits at its start
        _player.pause().then((_) => _player.seek(Duration.zero)).ignore();
        _asleep();
      }
    }
    final view = this.view;
    if (view.index + 1 < view.songs.length) {
      final next = view.songs[view.index + 1];
      Links.warm(next); // the next one's address, ready when it's its turn
      // and, once this one plays, its first seconds: skipping to it starts at once
      if (Downloads.the.fileOf(next) == null) {
        Timer(const Duration(seconds: 4), () {
          if (current?.id == t.id && _player.playing) Heads.read(next, _client).ignore();
        });
      }
    } else {
      _keepGoing(t);
    }
  }

  /// The last song of the queue plays: songs like it go on after it (like the radio on the computer).
  Future<void> _keepGoing(Track last) async {
    if (!autoplay || steer != null || _filling || _player.loopMode != LoopMode.off || last.src != 'yt') return;
    _filling = true;
    try {
      final like = await Links.relatedOf(last.ref);
      final have = {for (final t in _songs) t.id};
      final skip = unwanted;
      final fresh = [
        for (final t in like)
          if (t.ref.isNotEmpty && (skip == null || !skip(t)) && have.add(t.id)) t,
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
    final own = _cardKeys();
    _cardShown = own.map((k) => k.androidIcon).join(' ');
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        ...own,
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

  /// The music card's own keys, as they stand for the song that plays: the ones picked in the settings
  /// (a phone's own file can't be liked or waved off, so those stay away for it). A podcast gets a jump
  /// back and one ahead instead, the way podcast apps have them.
  List<MediaControl> _cardKeys() {
    final t = current;
    if (t == null) return const [];
    if (t.src == 'pod') {
      return [_key('back', 'Back 10 seconds', 'card_back_10'), _key('ahead', 'Ahead 30 seconds', 'card_ahead_30')];
    }
    return [
      for (final k in cardKeys)
        if (_cardKey(k, t) case final key?) key,
    ];
  }

  MediaControl? _cardKey(String k, Track t) {
    final liked = isLiked;
    return switch (k) {
      'like' when !t.fromPhone && liked != null =>
        liked(t) ? _key('like', 'Liked', 'card_liked') : _key('like', 'Like', 'card_like'),
      'shuffle' => _player.shuffleModeEnabled
          ? _key('shuffle', 'Shuffle is on', 'card_shuffle_on')
          : _key('shuffle', 'Shuffle', 'card_shuffle'),
      'repeat' => switch (_player.loopMode) {
          LoopMode.off => _key('repeat', 'Repeat', 'card_repeat'),
          LoopMode.all => _key('repeat', 'Repeats the queue', 'card_repeat_all'),
          LoopMode.one => _key('repeat', 'Repeats this song', 'card_repeat_one'),
        },
      'hide' when !t.fromPhone && hideSong != null => _key('hide', 'Not for me', 'card_not_for_me'),
      'sleep' => sleepAt != null || sleepAtEnd
          ? _key('sleep', 'Sleep timer is on', 'card_sleep_on')
          : _key('sleep', 'Stop after this song', 'card_sleep'),
      _ => null,
    };
  }

  static MediaControl _key(String name, String label, String icon) =>
      MediaControl.custom(androidIcon: 'drawable/$icon', label: label, name: name);

  /// The music card again, when one of its keys looks different now (a song liked in the app, say).
  void refreshCard() {
    if (_cardKeys().map((k) => k.androidIcon).join(' ') != _cardShown) _broadcast(_player.playbackEvent);
  }

  /// A key of the music card was pressed (see [_cardKeys]).
  @override
  Future<dynamic> customAction(String name, [Map<String, dynamic>? extras]) async {
    final t = current;
    if (t == null) return;
    switch (name) {
      case 'like':
        toggleLike?.call(t);
      case 'shuffle':
        if (steer?.call('shuffle') ?? false) return;
        await setShuffleMode(_player.shuffleModeEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);
      case 'repeat':
        if (steer?.call('repeat') ?? false) return;
        await _player.setLoopMode(switch (_player.loopMode) {
          LoopMode.off => LoopMode.all,
          LoopMode.all => LoopMode.one,
          LoopMode.one => LoopMode.off,
        });
      case 'hide':
        hideSong?.call(t);
        await skipToNext();
      case 'sleep':
        if (sleepAt != null || sleepAtEnd) {
          sleepOff();
        } else {
          sleepAfterSong();
        }
      case 'back':
        final back = _player.position - const Duration(seconds: 10);
        await seek(back < Duration.zero ? Duration.zero : back);
      case 'ahead':
        final ahead = _player.position + const Duration(seconds: 30);
        final end = _player.duration;
        await seek(end != null && ahead > end ? end : ahead);
    }
    refreshCard();
  }

  /// A song wouldn't load. A song YouTube won't give is skipped with a word about it; when it's the
  /// network, the same song is tried again a little later, from where it was.
  void _failed(Object e, [StackTrace? st]) {
    final t = current;
    if (t == null) return;
    if (t.fromPhone) {
      // no internet to wait for: the file is gone, or in a format the phone can't play
      notices.add("Skipped ${t.title}: the phone can't open that file.");
      if (_player.hasNext) _player.seekToNext().then((_) => _go()).catchError((Object _) {});
      return;
    }
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
    if (steer?.call('play') ?? false) return;
    if (_songs.isNotEmpty) _go();
  }

  @override
  Future<void> pause() async {
    if (steer?.call('pause') ?? false) return;
    _endBlend();
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    if (steer?.call('seek', position) ?? false) return;
    _endBlend();
    await _player.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (steer?.call('speed', Duration(milliseconds: (speed * 1000).round())) ?? false) return;
    await _player.setSpeed(speed);
    _broadcast(_player.playbackEvent);
  }

  @override
  Future<void> skipToNext() async {
    if (steer?.call('next') ?? false) return;
    _endBlend();
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
    if (steer?.call('previous') ?? false) return;
    _endBlend();
    if (_player.position > const Duration(seconds: 4) || !_player.hasPrevious) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _songs.length) return;
    _endBlend();
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
    _endBlend();
    _countHeard(null);
    await _saveSession();
    await _player.stop();
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
    final kept = [
      for (final x in j['songs'] is List ? j['songs'] as List : const []) Track.fromJson(x),
    ];
    final was = j['index'] is int ? j['index'] as int : 0;
    var at = Duration(milliseconds: j['position'] is int ? j['position'] as int : 0);
    // a file the files app handed over can't be opened again after a restart: it stays out, and the
    // song it was at becomes the next one, from its start
    final songs = <Track>[];
    var before = 0;
    var lost = false;
    for (var k = 0; k < kept.length; k++) {
      final t = kept[k];
      if (t != null && t.playable && !t.fromPhone) {
        songs.add(t);
      } else if (k < was) {
        before++;
      } else if (k == was) {
        lost = true;
        at = Duration.zero;
      }
    }
    if (songs.isEmpty) return;
    final index = (was - before).clamp(0, songs.length - 1);
    if (!lost) _lastStarted = songs[index].id; // it played already; coming back doesn't count it again
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

  // ------------------------------------------------------------ the stats

  /// The song that played until now is reported with how long it was heard, and [next] starts counting.
  void _countHeard(Track? next) {
    final was = _heard;
    if (was != null) {
      final secs = (_heardClock.elapsedMilliseconds * _player.speed / 1000).round();
      if (secs > 0) onHeard?.call(was, secs, _heardFrom);
    }
    _heard = next;
    _heardFrom = DateTime.now();
    _heardClock.reset();
    if (_player.playing) _heardClock.start();
  }

  // ------------------------------------------------------------ the sleep timer

  /// When the music stops by itself (null: no timer), or [sleepAtEnd]: at the end of the song that plays.
  DateTime? sleepAt;
  bool sleepAtEnd = false;
  final sleepNews = StreamController<void>.broadcast();

  void sleepIn(Duration d) {
    _sleep?.cancel();
    sleepAtEnd = false;
    sleepAt = DateTime.now().add(d);
    _sleep = Timer(d, _fallAsleep);
    sleepNews.add(null);
  }

  void sleepAfterSong() {
    _sleep?.cancel();
    sleepAt = null;
    sleepAtEnd = true;
    sleepNews.add(null);
  }

  void sleepOff() => _asleep();

  void _asleep() {
    _sleep?.cancel();
    sleepAt = null;
    sleepAtEnd = false;
    sleepNews.add(null);
  }

  /// The music fades out over a few seconds and pauses.
  Future<void> _fallAsleep() async {
    _asleep();
    _endBlend();
    for (var k = 10; k >= 0 && _player.playing; k--) {
      await _player.setVolume(k / 10);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    await _player.pause();
    await _player.setVolume(1);
  }

  /// The end of the song the sleep timer waits for: paused right there, the next song ready.
  void _nearTheEnd(Duration pos) {
    _lookAhead(pos);
    if (!sleepAtEnd || !_player.playing) return;
    final total = _player.duration;
    if (total == null || total.inMilliseconds < 1000) return;
    if (pos >= total - const Duration(milliseconds: 400)) {
      _asleep();
      _player.pause().then((_) async {
        if (_player.hasNext) await _player.seekToNext();
      }).ignore();
    }
  }

  // ------------------------------------------------------------ one song into the next

  /// How long two songs overlap when one runs into the next (zero: not at all) and the shape of it
  /// (blend.dart), and whether two songs that follow each other on one album run into each other the
  /// way they were made, without a blend. A skip always cuts: a phone can't get a song's end back
  /// quickly enough from the internet to blend it.
  Duration crossfade = Duration.zero;
  String fadeShape = 'smooth';
  bool albumsWhole = true;

  /// The song that ends plays out on this one while the next one comes in on the player. Made the first
  /// time a blend needs it, gone again when crossfade is switched off.
  AudioPlayer? _tail;
  String _tailFor = ''; // the song (and its length) the tail waits at the end of
  bool _tailReady = false;
  Timer? _blendAt; // the moment the blend starts
  Timer? _blend; // the blend itself, a step every 40 ms

  void setCrossfade(double seconds, {String? shape, bool? albums}) {
    crossfade = Duration(milliseconds: (fadeSecondsOf(seconds) * 1000).round());
    if (shape != null) fadeShape = fadeShapeOf(shape);
    if (albums != null) albumsWhole = albums;
    if (crossfade == Duration.zero) {
      _endBlend();
      final tail = _tail;
      _tail = null;
      _tailFor = '';
      _tailReady = false;
      tail?.dispose().ignore();
    }
  }

  /// The song after this one, in the order the queue plays.
  Track? get upNext {
    final v = view;
    return v.index >= 0 && v.index + 1 < v.songs.length ? v.songs[v.index + 1] : null;
  }

  /// Near the end of a song that runs into the next: its end waits on the tail, already loaded, and
  /// the blend is timed to the moment.
  void _lookAhead(Duration pos) {
    if (crossfade == Duration.zero || _blend != null || !_player.playing || steer != null || sleepAtEnd) return;
    final total = _player.duration;
    final t = current;
    final next = upNext;
    if (total == null || t == null || next == null || _player.loopMode == LoopMode.one) return;
    if (total < crossfade * 3 || (albumsWhole && t.album.isNotEmpty && t.album == next.album && t.artist == next.artist)) {
      return; // a short song, or the next one is the album's next: one after the other, as made
    }
    final left = total - pos;
    if (left > crossfade + const Duration(seconds: 8) || left < crossfade - const Duration(milliseconds: 400)) return;
    final key = '${t.id}:${total.inMilliseconds}';
    if (_tailFor != key) {
      _tailFor = key;
      _blendAt?.cancel();
      _blendAt = null;
      unawaited(_readyTail(t, total - crossfade, key));
      return;
    }
    if (_tailReady && _blendAt == null) {
      final wait = (left - crossfade) * (1 / _player.speed);
      _blendAt = Timer(wait.isNegative ? Duration.zero : wait, () => _startBlend(key));
    }
  }

  Future<void> _readyTail(Track t, Duration from, String key) async {
    _tailReady = false;
    final tail = _tail ??= AudioPlayer(
        useProxyForRequestHeaders: false,
        handleAudioSessionActivation: false,
        handleInterruptions: false,
        audioLoadConfiguration: quickStart);
    try {
      await tail.setVolume(0);
      await tail.setSpeed(_player.speed);
      await tail.setAudioSource(_source(t), initialPosition: from);
      _tailReady = _tailFor == key;
    } on Object {
      _tailReady = false; // no tail this time: the song ends and the next one starts the usual way
    }
  }

  Future<void> _startBlend(String key) async {
    _blendAt = null;
    final tail = _tail;
    final total = _player.duration;
    if (tail == null || !_tailReady || _tailFor != key || !_player.playing || total == null || _blend != null) return;
    final left = total - _player.position;
    // a jump in the song meanwhile: the next look ahead times it again
    if (left > crossfade + const Duration(milliseconds: 700) || left < const Duration(milliseconds: 300)) return;
    _tailReady = false;
    final shape = fadeShape;
    final speed = _player.speed;
    // the end plays on the tail from here, at the volume the song had; the player goes on to the next
    // song, silent at first, and the two cross over the rest of the song's time
    await tail.setVolume(1);
    unawaited(tail.play().catchError((Object _) {}));
    await _player.setVolume(0);
    await _player.seekToNext();
    final clock = Stopwatch()..start();
    final length = left.inMilliseconds / speed;
    _blend = Timer.periodic(const Duration(milliseconds: 40), (_) {
      final f = clock.elapsedMilliseconds / length;
      final (out, into) = blendGains(shape, f);
      tail.setVolume(out).ignore();
      _player.setVolume(into).ignore();
      if (f >= 1) _endBlend();
    });
  }

  /// The blend is over, or a key cut it short: the tail stops and the player is at full volume.
  void _endBlend() {
    _blendAt?.cancel();
    _blendAt = null;
    final running = _blend;
    if (running == null) return;
    running.cancel();
    _blend = null;
    _tailFor = '';
    _tailReady = false;
    _player.setVolume(1).ignore();
    _tail?.stop().ignore();
  }

  @visibleForTesting
  List<Track> get songs => List.unmodifiable(_songs);
}
