/// What you listened to on the phone, song by song with how long, for the listening stats and Rewind:
/// minutes, top songs and artists, the hours you listen at, your streaks, the artists new to you. A song counts when it played for
/// half a minute (or half of it, for a short one), like Spotify counts a stream. Kept in plays.json,
/// the last 20 000 plays.
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import 'model.dart';
import 'store.dart';

const _file = 'plays.json';
const _most = 20000;

class Play {
  const Play(this.track, this.at, this.seconds);

  final Track track;

  /// When it started (unix seconds) and how long it was heard.
  final int at;
  final int seconds;

  DateTime get when => DateTime.fromMillisecondsSinceEpoch(at * 1000);

  Map<String, Object?> toJson() => {
        's': track.src,
        'r': track.ref,
        't': track.title,
        'a': track.artist,
        'i': track.art,
        'd': track.dur,
        'w': at,
        'h': seconds,
      };

  static Play? fromJson(Object? j) {
    if (j is! Map || j['s'] is! String || j['r'] is! String) return null;
    final t = Track(
      src: j['s'] as String,
      ref: j['r'] as String,
      title: '${j['t'] ?? ''}',
      artist: '${j['a'] ?? ''}',
      art: '${j['i'] ?? ''}',
      dur: j['d'] is int ? j['d'] as int : 0,
    );
    return Play(t, j['w'] is int ? j['w'] as int : 0, j['h'] is int ? j['h'] as int : 0);
  }
}

/// Numbers for a stretch of time.
class Stats {
  Stats(this.plays);

  final List<Play> plays;

  int get seconds => plays.fold(0, (s, p) => s + p.seconds);
  int get minutes => seconds ~/ 60;

  /// Songs by how often they played (ties: by time), with the count.
  List<(Track, int)> get songs {
    final count = <String, int>{}, time = <String, int>{}, track = <String, Track>{};
    for (final p in plays) {
      count[p.track.id] = (count[p.track.id] ?? 0) + 1;
      time[p.track.id] = (time[p.track.id] ?? 0) + p.seconds;
      track[p.track.id] = p.track;
    }
    final ids = count.keys.toList()
      ..sort((a, b) => count[b] != count[a] ? count[b]!.compareTo(count[a]!) : time[b]!.compareTo(time[a]!));
    return [for (final id in ids) (track[id]!, count[id]!)];
  }

  /// Artists by minutes listened, with the minutes (a song by several counts for the first).
  List<(String, int)> get artists {
    final time = <String, int>{};
    for (final p in plays) {
      final a = firstArtist(p.track.artist);
      if (a.isEmpty) continue;
      time[a] = (time[a] ?? 0) + p.seconds;
    }
    final names = time.keys.toList()..sort((a, b) => time[b]!.compareTo(time[a]!));
    return [for (final n in names) (n, (time[n]! / 60).round())];
  }

  /// Minutes listened in each hour of the day.
  List<int> get hours {
    final out = List<int>.filled(24, 0);
    for (final p in plays) {
      out[p.when.hour] += p.seconds;
    }
    return [for (final s in out) (s / 60).round()];
  }

  /// Days with music in them.
  int get days => {for (final p in plays) _day(p.when)}.length;

  int get distinctSongs => {for (final p in plays) p.track.id}.length;

  int get distinctArtists => artists.length;

  /// Minutes in each month, January first (for a year's Rewind).
  List<int> get months {
    final out = List<int>.filled(12, 0);
    for (final p in plays) {
      out[p.when.month - 1] += p.seconds;
    }
    return [for (final s in out) (s / 60).round()];
  }

  /// The most days in a row with music in them.
  int get longestStreak {
    final days = {for (final p in plays) DateTime(p.when.year, p.when.month, p.when.day)}.toList()..sort();
    var best = 0, run = 0;
    DateTime? last;
    for (final d in days) {
      // a day apart, also over a clock change (23 or 25 hours)
      run = last != null && (d.difference(last).inHours / 24).round() == 1 ? run + 1 : 1;
      best = max(best, run);
      last = d;
    }
    return best;
  }

  /// The hour you listen most at, or -1.
  int get peakHour {
    final h = hours;
    var best = -1, most = 0;
    for (var k = 0; k < 24; k++) {
      if (h[k] > most) {
        most = h[k];
        best = k;
      }
    }
    return best;
  }
}

String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// The first of a song's artists ("A, B & C feat. D" is A's).
String firstArtist(String artists) => artists.split(RegExp(r',| & | feat\. ')).first.trim();

class History extends ChangeNotifier {
  final List<Play> plays = [];
  late final _save = LaterSave(_file, () => [for (final p in plays) p.toJson()], delay: const Duration(seconds: 5));

  Future<void> load() async {
    final j = await Store.the.read(_file);
    if (j is List) {
      for (final x in j) {
        final p = Play.fromJson(x);
        if (p != null) plays.add(p);
      }
    }
  }

  /// A song was heard for [seconds] (from its start at [started]): it counts if that was long enough.
  void heard(Track t, int seconds, DateTime started) {
    final enough = min(30, t.dur > 0 ? max(10, t.dur ~/ 2) : 30);
    if (seconds < enough || t.src == 'local') return;
    plays.add(Play(t, started.millisecondsSinceEpoch ~/ 1000, seconds));
    if (plays.length > _most) plays.removeRange(0, plays.length - _most);
    _save.soon();
    notifyListeners();
  }

  Stats between(DateTime from, DateTime to) {
    final a = from.millisecondsSinceEpoch ~/ 1000, b = to.millisecondsSinceEpoch ~/ 1000;
    return Stats([
      for (final p in plays)
        if (p.at >= a && p.at < b) p,
    ]);
  }

  Stats get all => Stats(plays);

  /// Artists first heard (on this phone) between [from] and [to], the most heard first.
  List<String> newArtists(DateTime from, DateTime to) {
    final start = from.millisecondsSinceEpoch ~/ 1000;
    final before = {
      for (final p in plays)
        if (p.at < start) firstArtist(p.track.artist),
    };
    return [
      for (final (name, _) in between(from, to).artists)
        if (!before.contains(name)) name,
    ];
  }

  /// Days in a row with music, up to today (or yesterday, when today has none yet).
  int get streak {
    final days = {for (final p in plays) _day(p.when)};
    var d = DateTime.now();
    if (!days.contains(_day(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(_day(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Songs played most often lately that aren't the very last ones: "On repeat".
  List<Track> onRepeat({int days = 30, int want = 30}) {
    final s = between(DateTime.now().subtract(Duration(days: days)), DateTime.now().add(const Duration(minutes: 1)));
    return [
      for (final (t, n) in s.songs)
        if (n >= 2) t,
    ].take(want).toList();
  }

  Future<void> flush() => _save.now();
}
