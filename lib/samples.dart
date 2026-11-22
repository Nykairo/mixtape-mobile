/// Samples: songs you don't know yet, each from its best half minute (the part people replay the most),
/// flicked through one after another like on TikTok. The computer's Samples page, for the phone. When a
/// half minute is over, the page flicks on to the next one by itself and the two run into each other.
///
/// Samples has its own two players: one plays, the other has the next song loaded already, so a flick
/// starts it at once (and the two can blend); the best parts and addresses of the few after that are
/// looked up meanwhile. The music that was on waits, and carries on when you leave Samples.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'audio.dart';
import 'heat.dart';
import 'model.dart';
import 'music.dart';
import 'video.dart';

class Sample {
  Sample(this.track);

  final Track track;

  /// Where its best part starts, in seconds (null until looked up).
  double? start;
}

class Samples extends ChangeNotifier {
  Samples({required this.seeds, required this.known, required this.unwanted, this.batches});

  /// One artist's Samples, like on the computer's artist pages: their popular songs first, then the
  /// rest of what they made, then songs from their radio.
  factory Samples.artist(ArtistPage a, {required bool Function(Track) unwanted}) {
    final records = [
      for (final shelf in a.shelves)
        for (final i in shelf.items)
          if (i.kind == Kind.album) i.id,
    ];
    final seed = a.radioSeed.isNotEmpty ? a.radioSeed : (a.songs.isEmpty ? '' : a.songs.first.ref);
    return Samples(
      seeds: () => const [],
      known: () => const {},
      unwanted: unwanted,
      batches: (round) async => switch (round) {
        0 => a.songs,
        1 => [
            for (final page in await Future.wait([
              for (final id in records.take(8)) Music.list(id).then<ListPage?>((p) => p, onError: (Object _) => null),
            ]))
              ...?page?.songs,
          ],
        2 => seed.isEmpty ? const <Track>[] : (await Music.next(seed, playlist: a.radio)).songs,
        _ => const <Track>[],
      },
    );
  }

  /// Songs to start from (liked and played lately), songs not to offer (known already), and songs the
  /// person isn't interested in.
  final List<Track> Function() seeds;
  final Set<String> Function() known;
  final bool Function(Track) unwanted;

  /// Where an artist's Samples get their songs from, a batch a round; null for the usual feed.
  final Future<List<Track>> Function(int round)? batches;
  int _round = 0;

  static const length = 30.0;

  final List<Sample> items = [];
  final _seen = <String>{};
  bool loading = false;
  String? trouble;

  final _client = http.Client();
  final _players = [
    AudioPlayer(useProxyForRequestHeaders: false, audioLoadConfiguration: quickStart),
    AudioPlayer(useProxyForRequestHeaders: false, audioLoadConfiguration: quickStart),
  ];
  final _loaded = <String?>[null, null]; // the song each player has (or is getting)
  final _loading = <Future<void>?>[null, null];
  int _on = 0; // which player plays
  int index = -1; // the sample that plays
  bool paused = false;
  StreamSubscription<Duration>? _loop;
  final _fades = <Timer?>[null, null]; // a player's volume on its way up or down
  final _fadeEnds = <Completer<void>?>[null, null];

  /// Asked to flick on to the sample at the given place when the one that plays is over: true when the
  /// page does it (its [show] then lets the two run into each other). Null while no page shows the feed.
  bool Function(int)? flickTo;
  int? _coming; // the sample that comes by itself, asked for at the end of the one before

  /// One sample into the next when it comes by itself, and on a flick.
  static const _blend = Duration(milliseconds: 1800);
  static const _snap = Duration(milliseconds: 240);

  /// How long before the end of its half minute the page flicks on (half of that goes by before the next
  /// sample starts, as the page turns).
  static const _lead = Duration(milliseconds: 700);

  /// How far into its half minute the sample that plays is (0 to 1).
  final progress = ValueNotifier<double>(0);

  AudioPlayer get player => _players[_on];

  /// More songs at the end of the feed: radio from a couple of songs you like, one song per artist.
  Future<void> more() async {
    if (loading) return;
    loading = true;
    trouble = null;
    notifyListeners();
    try {
      final next = batches;
      if (next != null) {
        var added = 0;
        while (added == 0 && _round < 3) {
          for (final t in await next(_round++)) {
            if (t.src == 'yt' && t.dur >= 45 && t.dur <= 900 && !unwanted(t) && _seen.add(t.id)) {
              items.add(Sample(t));
              added++;
            }
          }
        }
        if (items.isEmpty) trouble = 'No songs of theirs turned up. Try again in a moment.';
        return;
      }
      final from = [
        for (final t in seeds())
          if (t.src == 'yt') t,
      ]..shuffle();
      final pool = <Track>[];
      for (final seed in from.take(2)) {
        pool.addAll((await Music.next(seed.ref)).songs);
      }
      if (pool.length < 10) {
        // nothing to start from yet: what's big right now, from YouTube Music's home page
        final home = await Music.home();
        for (final shelf in home.shelves) {
          final list = shelf.items.where((i) => i.kind == Kind.playlist).toList();
          if (list.isEmpty) continue;
          pool.addAll((await Music.list(list[Random().nextInt(list.length)].id)).songs);
          break;
        }
      }
      pool.shuffle();
      final skip = known();
      final artists = <String>{};
      var added = 0;
      for (final t in pool) {
        final who = t.artist.split(',').first.toLowerCase();
        if (t.dur < 60 || t.dur > 600 || skip.contains(t.id) || unwanted(t) || !_seen.add(t.id) || !artists.add(who)) {
          continue;
        }
        items.add(Sample(t));
        if (++added >= 16) break;
      }
      if (added == 0 && items.isEmpty) trouble = 'No new songs turned up. Like a few songs and try again.';
    } on Object {
      trouble = "Samples couldn't reach YouTube Music. Check the internet connection.";
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Where a sample's best part starts, looked up once.
  Future<double> _startOf(Sample s) async {
    final have = s.start;
    if (have != null) return have;
    Heat heat = const [];
    try {
      heat = await Videos.curve(s.track.ref);
    } on Object {
      heat = const [];
    }
    return s.start = bestPart(heat, s.track.dur.toDouble(), length: length);
  }

  /// Gives a player a sample, from its best part. Said at once (so a flick meanwhile knows it's on its
  /// way), done when the song is loaded; asked again for the same song, it's the same wait.
  Future<void> _load(int player, Sample s) {
    if (_loaded[player] == s.track.id) return _loading[player] ?? Future.value();
    _loaded[player] = s.track.id;
    return _loading[player] = _put(player, s);
  }

  Future<void> _put(int player, Sample s) async {
    final at = await _startOf(s);
    if (_loaded[player] != s.track.id) return; // it got another song meanwhile
    try {
      await _players[player].setAudioSource(YouTubeSource(s.track, _client),
          initialPosition: Duration(milliseconds: (at * 1000).round()), preload: true);
    } on Object {
      if (_loaded[player] == s.track.id) _loaded[player] = null;
    }
  }

  /// Plays the sample at [k] from its best part, the one before going quiet meanwhile (slowly when this
  /// one came by itself, so they run into each other). The next one loads in the other player, and the
  /// few after it are looked up.
  Future<void> show(int k) async {
    if (k < 0 || k >= items.length) return;
    final s = items[k];
    final was = _on;
    final blend = _coming == k ? _blend : _snap;
    _coming = null;
    index = k;
    paused = false;
    progress.value = 0;
    if (_loaded[1 - _on] == s.track.id) _on = 1 - _on; // loaded ahead (or on its way): it takes over
    notifyListeners();
    await _loop?.cancel();
    _loop = null;
    if (was != _on) {
      unawaited(_fade(was, 0, blend));
    } else {
      _stopFade(was); // the same player gets the new song
      await _players[was].pause();
    }
    await _load(_on, s); // nothing to wait for when it's loaded already
    if (index != k) return; // flicked on meanwhile
    final p = player;
    final start = Duration(milliseconds: ((s.start ?? 0) * 1000).round());
    _loop = p.positionStream.listen((pos) => _heard(k, pos, start));
    // a player that loaded ahead waits at the start already; one that played it before goes back
    if ((p.position - start).abs() > const Duration(milliseconds: 400)) await p.seek(start);
    if (index != k) return;
    _stopFade(_on);
    await p.setVolume(0);
    unawaited(p.play().catchError((Object _) {}));
    unawaited(_fade(_on, 1, blend));
    if (k + 1 >= items.length - 3) unawaited(more());
    if (k + 1 < items.length) {
      final other = 1 - _on, next = items[k + 1];
      // the other player may still be fading out the one before: the next one goes in when it's quiet
      unawaited(() async {
        await _settled(other);
        if (index == k) await _load(other, next);
      }());
    }
    for (final later in items.skip(k + 2).take(3)) {
      _startOf(later).ignore();
      Links.warm(later.track);
    }
  }

  /// The sample at [k] as it plays: the bar follows it, and a little before its half minute is over
  /// the page is asked to flick on. The last one there is (or one no page can flick on from) goes round.
  void _heard(int k, Duration pos, Duration start) {
    progress.value = ((pos - start).inMilliseconds / (length * 1000)).clamp(0.0, 1.0);
    final end = start + Duration(milliseconds: (length * 1000).round());
    if (index != k || paused) return;
    if (_coming != null) {
      // the page didn't turn after all (a finger held it): this one goes round again
      if (pos >= end + const Duration(seconds: 4)) {
        _coming = null;
        player.seek(start).ignore();
      }
      return;
    }
    if (pos < end - _lead) return;
    if (k + 1 < items.length && (flickTo?.call(k + 1) ?? false)) {
      _coming = k + 1;
    } else if (pos >= end) {
      player.seek(start).ignore();
    }
  }

  /// Turns player [k]'s volume to [to] over [over], evenly loud on the way (the two together sound as
  /// loud as one). Down to nothing, it pauses.
  Future<void> _fade(int k, double to, Duration over) {
    _stopFade(k);
    final p = _players[k];
    final from = p.volume;
    final steps = max(1, over.inMilliseconds ~/ 40);
    final end = _fadeEnds[k] = Completer<void>();
    _fades[k] = Timer.periodic(const Duration(milliseconds: 40), (t) {
      final f = min(1.0, t.tick / steps);
      final curve = to > from ? sin(f * pi / 2) : 1 - cos(f * pi / 2);
      p.setVolume(from + (to - from) * curve).ignore();
      if (f < 1) return;
      if (to == 0) p.pause().ignore();
      _stopFade(k);
    });
    return end.future;
  }

  void _stopFade(int k) {
    _fades[k]?.cancel();
    _fades[k] = null;
    final end = _fadeEnds[k];
    _fadeEnds[k] = null;
    if (end != null && !end.isCompleted) end.complete();
  }

  /// Done when player [k] is quiet: at once when it isn't fading.
  Future<void> _settled(int k) => _fadeEnds[k]?.future ?? Future.value();

  void toggle() {
    if (index < 0) return;
    paused = !paused;
    if (paused) {
      // the one before may still be fading out: both go quiet, and this one comes back at full volume
      for (var k = 0; k < 2; k++) {
        _stopFade(k);
        _players[k].pause().ignore();
      }
      player.setVolume(1).ignore();
    } else {
      unawaited(player.play().catchError((Object _) {}));
    }
    notifyListeners();
  }

  /// Leaving Samples: both players let go of their songs.
  Future<void> stop() async {
    await _loop?.cancel();
    _loop = null;
    _coming = null;
    for (var k = 0; k < 2; k++) {
      _stopFade(k);
      _loaded[k] = null;
      _loading[k] = null;
      await _players[k].stop();
    }
    paused = true;
    progress.value = 0;
  }

  @override
  void dispose() {
    _loop?.cancel();
    _stopFade(0);
    _stopFade(1);
    progress.dispose();
    for (final p in _players) {
      p.dispose();
    }
    _client.close();
    super.dispose();
  }
}
