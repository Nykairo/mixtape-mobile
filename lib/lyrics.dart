/// The words of the song that plays: synced when they can be (each line lights up as it's sung, a tap on
/// one jumps there), plain otherwise. From lrclib (free and open, the computer's first choice too), then
/// YouTube Music's own (synced from Musixmatch for many songs), then plain words from either.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'jsonwalk.dart';
import 'model.dart';
import 'music.dart';
import 'youtube.dart';

class Lyrics {
  const Lyrics(this.lines, {this.times = const [], this.source = ''});

  final List<String> lines;

  /// When each line starts, in milliseconds (empty for plain words).
  final List<int> times;
  final String source;

  bool get synced => times.isNotEmpty;

  /// The line sung at [ms], -1 before the first.
  int lineAt(int ms) {
    var lo = 0, hi = times.length - 1, at = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= ms) {
        at = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return at;
  }
}

/// Synced words in the LRC format ("[01:23.45] a line"), or null when there are none.
Lyrics? parseLrc(String text, {String source = ''}) {
  final stamp = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  final rows = <(int, String)>[];
  for (final raw in const LineSplitter().convert(text)) {
    final marks = stamp.allMatches(raw).toList();
    if (marks.isEmpty) continue;
    final words = raw.substring(marks.last.end).trim();
    for (final m in marks) {
      final frac = m.group(3) ?? '0';
      final ms = int.parse(frac.padRight(3, '0').substring(0, 3));
      rows.add(((int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!)) * 1000 + ms, words));
    }
  }
  if (rows.isEmpty) return null;
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  return Lyrics([for (final r in rows) r.$2.isEmpty ? '♪' : r.$2], times: [for (final r in rows) r.$1], source: source);
}

/// YouTube Music's synced words (the Android app's answer), or null.
Lyrics? parseTimedLyrics(Map<String, Object?> data) {
  for (final holder in findAll(data, 'timedLyricsData', lists: true)) {
    final lines = <String>[];
    final times = <int>[];
    for (final x in asList(holder['timedLyricsData'])) {
      final m = asMap(x);
      final cue = asMap(m['cueRange']);
      if (!cue.containsKey('startTimeMilliseconds')) continue;
      final line = '${m['lyricLine'] ?? ''}'.trim();
      lines.add(line.isEmpty ? '♪' : line);
      times.add(toInt(cue['startTimeMilliseconds']));
    }
    if (lines.isNotEmpty) return Lyrics(lines, times: times, source: _source(findText(data, 'sourceMessage')));
  }
  return null;
}

/// YouTube Music's plain words, or null.
Lyrics? parsePlainLyrics(Map<String, Object?> data) {
  final shelf = findOne(data, 'musicDescriptionShelfRenderer');
  final text = textOf(shelf['description']).trim();
  if (text.isEmpty) return null;
  return Lyrics(const LineSplitter().convert(text), source: _source(textOf(shelf['footer'])));
}

String _source(String s) => s.replaceFirst(RegExp(r'^Source:\s*'), '');

/// A title the way lyrics sites know it: without "(Official Video)", "- Remastered" and the featured artists.
String cleanTitle(String title) => title
    .replaceAll(RegExp(r'\s*[\(\[][^\)\]]*(official|video|audio|lyrics?|visuali[sz]er|remaster\w*|feat\.?|ft\.?)[^\)\]]*[\)\]]',
        caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+-\s+(\d{4}\s+)?remaster(ed)?.*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+(feat|ft)\.?\s.*$', caseSensitive: false), '')
    .trim();

class LyricsFinder {
  LyricsFinder({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _found = <String, Lyrics?>{};
  final _asking = <String, Future<Lyrics?>>{};

  static final the = LyricsFinder();

  /// What is known already for a song (null: none, or not asked yet; see [known]).
  Lyrics? cached(Track t) => _found[t.id];

  bool known(Track t) => _found.containsKey(t.id);

  Future<Lyrics?> of(Track t) {
    if (_found.containsKey(t.id)) return Future.value(_found[t.id]);
    return _asking[t.id] ??= _look(t).then((l) {
      _found[t.id] = l;
      while (_found.length > 40) {
        _found.remove(_found.keys.first);
      }
      return l;
    }).whenComplete(() {
      _asking.remove(t.id);
    });
  }

  Future<Lyrics?> _look(Track t) async {
    final title = cleanTitle(t.title);
    final artist = t.artist.split(RegExp(r',|&| x | feat\.? ')).first.trim();
    Lyrics? plain;
    try {
      final (synced, words) = await _lrclib(title, artist, t.dur, t.album);
      if (synced != null) return synced;
      plain = words;
    } on Object {
      // lrclib is down or slow: YouTube Music may have them
    }
    if (t.src == 'yt') {
      try {
        final next = await Music.next(t.ref);
        if (next.lyrics.isNotEmpty) {
          final timed = parseTimedLyrics(await YouTube.inner.browseRaw(next.lyrics, mobile: true));
          if (timed != null) return timed;
          plain ??= parsePlainLyrics(await YouTube.inner.browseRaw(next.lyrics));
        }
      } on Object {
        // nothing more to try
      }
    }
    return plain;
  }

  Future<(Lyrics?, Lyrics?)> _lrclib(String title, String artist, int dur, String album) async {
    const headers = {'User-Agent': 'Mixtape for phones (https://github.com/Nykairo/mixtape-mobile)'};
    final get = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (album.isNotEmpty) 'album_name': album,
      if (dur > 0) 'duration': '$dur',
    });
    var res = await _http.get(get, headers: headers).timeout(const Duration(seconds: 8));
    Map<String, Object?>? hit;
    if (res.statusCode == 200) {
      hit = asMap(jsonDecode(utf8.decode(res.bodyBytes)));
    } else {
      final search = Uri.https('lrclib.net', '/api/search', {'track_name': title, 'artist_name': artist});
      res = await _http.get(search, headers: headers).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return (null, null);
      final rows = [for (final r in asList(jsonDecode(utf8.decode(res.bodyBytes)))) asMap(r)];
      // the same length (within a few seconds), synced words first
      rows.removeWhere((r) => dur > 0 && (toInt(r['duration']) - dur).abs() > 4);
      rows.sort((a, b) => (b['syncedLyrics'] is String ? 1 : 0) - (a['syncedLyrics'] is String ? 1 : 0));
      if (rows.isNotEmpty) hit = rows.first;
    }
    if (hit == null || hit['instrumental'] == true) return (null, null);
    final synced = hit['syncedLyrics'];
    final words = hit['plainLyrics'];
    return (
      synced is String ? parseLrc(synced, source: 'lrclib') : null,
      words is String && words.trim().isNotEmpty ? Lyrics(const LineSplitter().convert(words), source: 'lrclib') : null,
    );
  }
}
