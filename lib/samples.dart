/// Samples: songs you don't know yet, each from its best half minute (the part people replay the most),
/// flicked through one after another like on TikTok. The computer's Samples page, for the phone.
///
/// Samples has its own two players: one plays, the other has the next song loaded already, so a flick
/// starts it at once. The music that was on waits, and carries on when you leave Samples.
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
  Samples({required this.seeds, required this.known, required this.unwanted});

  /// Songs to start from (liked and played lately), songs not to offer (known already), and songs the
  /// person isn't interested in.
  final List<Track> Function() seeds;
  final Set<String> Function() known;
  final bool Function(Track) unwanted;

  static const length = 30.0;

  final List<Sample> items = [];
  final _seen = <String>{};
  bool loading = false;
  String? trouble;

  final _client = http.Client();
  final _players = [AudioPlayer(useProxyForRequestHeaders: false), AudioPlayer(useProxyForRequestHeaders: false)];
  final _loaded = <String?>[null, null];
  int _on = 0; // which player plays
  int index = -1; // the sample that plays
  bool paused = false;
  StreamSubscription<Duration>? _loop;

  AudioPlayer get player => _players[_on];

  /// More songs at the end of the feed: radio from a couple of songs you like, one song per artist.
  Future<void> more() async {
    if (loading) return;
    loading = true;
    trouble = null;
    notifyListeners();
    try {
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

  Future<void> _load(int player, Sample s) async {
    final at = await _startOf(s);
    _loaded[player] = s.track.id;
    try {
      await _players[player].setAudioSource(YouTubeSource(s.track, _client),
          initialPosition: Duration(milliseconds: (at * 1000).round()), preload: true);
    } on Object {
      _loaded[player] = null;
    }
  }

  /// Plays the sample at [k] (from its best part, round and round), with the next one loading meanwhile.
  Future<void> show(int k) async {
    if (k < 0 || k >= items.length) return;
    index = k;
    paused = false;
    notifyListeners();
    final s = items[k];
    final other = 1 - _on;
    await player.pause();
    if (_loaded[other] == s.track.id) {
      _on = other;
    } else if (_loaded[_on] != s.track.id) {
      await _load(_on, s);
    }
    if (index != k) return; // flicked on meanwhile
    final start = Duration(milliseconds: ((s.start ?? 0) * 1000).round());
    final end = start + const Duration(seconds: 30);
    await _loop?.cancel();
    _loop = player.positionStream.listen((pos) {
      if (pos >= end) player.seek(start).ignore();
    });
    await player.seek(start);
    unawaited(player.play().catchError((Object _) {}));
    if (k + 1 >= items.length - 3) unawaited(more());
    if (k + 1 < items.length) unawaited(_load(1 - _on, items[k + 1]));
  }

  void toggle() {
    if (index < 0) return;
    paused = !paused;
    if (paused) {
      player.pause().ignore();
    } else {
      unawaited(player.play().catchError((Object _) {}));
    }
    notifyListeners();
  }

  /// Leaving Samples: both players let go of their songs.
  Future<void> stop() async {
    await _loop?.cancel();
    _loop = null;
    for (var k = 0; k < 2; k++) {
      await _players[k].stop();
      _loaded[k] = null;
    }
    paused = true;
  }

  @override
  void dispose() {
    _loop?.cancel();
    for (final p in _players) {
      p.dispose();
    }
    _client.close();
    super.dispose();
  }
}
