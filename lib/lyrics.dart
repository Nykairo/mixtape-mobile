/// The words of the song that plays: synced when they can be (each line lights up as it's sung, a tap on
/// one jumps there), plain otherwise. Asked in the computer's order: lrclib (free and open), YouTube
/// Music's own (synced from Musixmatch for many songs), NetEase and KuGou (synced too, many Asian and
/// lesser known songs), then Genius and lyrics.ovh for at least the words. A search hit only counts when
/// its title, artist and length match the song, so a cover's or another song's words never show up.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;

import 'jsonwalk.dart';
import 'model.dart';
import 'music.dart';
import 'youtube.dart';

class Lyrics {
  const Lyrics(this.lines, {this.times = const [], this.source = '', this.link = ''});

  final List<String> lines;

  /// When each line starts, in milliseconds (empty for plain words).
  final List<int> times;
  final String source;

  /// The page the words came from, where the source asks to be linked (Megalobiz).
  final String link;

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

/// Lowercase letters and digits only, accents dropped: for telling whether two names match.
String folded(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final c = _plain[ch] ?? ch;
    b.write(_letter.hasMatch(c) ? c : ' ');
  }
  return b.toString().split(' ').where((w) => w.isNotEmpty).join(' ');
}

final _letter = RegExp(r'^[\p{L}\p{N}]+$', unicode: true);

const _plain = {'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a', 'ç': 'c', 'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e', 'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g', 'ĥ': 'h', 'ħ': 'h', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i', 'ı': 'i', 'ĵ': 'j', 'ķ': 'k', 'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n', 'ŉ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o', 'ŕ': 'r', 'ŗ': 'r', 'ř': 'r', 'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ţ': 't', 'ť': 't', 'ŧ': 't', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u', 'ŵ': 'w', 'ý': 'y', 'ÿ': 'y', 'ŷ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'æ': 'ae', 'œ': 'oe', 'ß': 'ss', 'ð': 'd', 'þ': 'th'};

/// Does a search hit look like the song? Words of the wrong song are worse than none.
bool sameSong(String title, String artist, int dur, String title2, String artist2, int dur2) {
  if (dur > 0 && dur2 > 0 && (dur - dur2).abs() > 6) return false;
  final a = folded(title), b = folded(title2), x = folded(artist), y = folded(artist2);
  if (a.isEmpty || b.isEmpty || !(a.contains(b) || b.contains(a))) return false;
  return x.isEmpty || y.isEmpty || x.contains(y) || y.contains(x) || x.split(' ').toSet().intersection(y.split(' ').toSet()).isNotEmpty;
}

/// The words in a Genius lyrics page: what's inside its lyrics boxes, without the header Genius puts in
/// the first one (contributors, translations, a blurb about the song), and without [Chorus] and friends.
String geniusText(String page) {
  final out = StringBuffer();
  final tag = RegExp(r'<(/?)(div|br)\b([^>]*)>', caseSensitive: false);
  var depth = 0; // how deep inside a lyrics box, 0 outside
  var skip = 0; // how deep inside its header, 0 when not in it
  var at = 0;
  for (final m in tag.allMatches(page)) {
    if (depth > 0 && skip == 0) out.write(page.substring(at, m.start).replaceAll(RegExp(r'<[^>]+>'), ''));
    at = m.end;
    final closing = m.group(1) == '/';
    final name = m.group(2)!.toLowerCase();
    final attrs = m.group(3) ?? '';
    if (name == 'br') {
      if (depth > 0 && skip == 0) out.write('\n');
    } else if (closing) {
      if (depth > 0) {
        depth--;
        if (skip > 0) skip--;
      }
    } else if (depth > 0) {
      depth++;
      if (skip > 0) {
        skip++;
      } else if (attrs.contains('data-exclude-from-selection="true"')) {
        skip = 1;
      }
    } else if (attrs.contains('data-lyrics-container="true"')) {
      depth = 1;
      out.write('\n');
    }
  }
  final lines = [
    for (final l in const LineSplitter().convert(_entities(out.toString())))
      if (!(l.trim().startsWith('[') && l.trim().endsWith(']'))) l.trim(),
  ];
  return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

String _entities(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#x27;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));

/// Lyrics in the phone's own language, a few lines at a time, from the free MyMemory service (what the
/// computer uses too). Lines it can't translate stay as they are.
class Translator {
  Translator({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _done = <String, List<String>>{};

  static Translator the = Translator();

  /// The language to translate into: the phone's.
  static String get language => PlatformDispatcher.instance.locale.languageCode;

  Future<List<String>> lines(List<String> lines, {String? into}) async {
    final lang = into ?? language;
    final key = '$lang|${lines.join('\n')}';
    final known = _done[key];
    if (known != null) return known;
    final chunks = <List<String>>[[]];
    var size = 0;
    for (final l in lines) {
      if (size + l.length > 440 && chunks.last.isNotEmpty) {
        chunks.add([]);
        size = 0;
      }
      chunks.last.add(l);
      size += l.length + 1;
    }
    final out = <String>[];
    for (final c in chunks) {
      final text = c.join('\n');
      if (text.trim().isEmpty) {
        out.addAll(c);
        continue;
      }
      try {
        final res = await _http
            .get(Uri.https('api.mymemory.translated.net', '/get', {'q': text, 'langpair': 'autodetect|$lang'}))
            .timeout(const Duration(seconds: 12));
        final j = asMap(jsonDecode(utf8.decode(res.bodyBytes)));
        final got = '${asMap(j['responseData'])['translatedText'] ?? ''}';
        final ok = toInt(j['responseStatus']) == 200 && got.isNotEmpty && !got.contains('DISTINCT LANGUAGES');
        final back = ok ? const LineSplitter().convert(_entities(got)) : c;
        // the same number of lines back, or the lines can't be put next to each other
        out.addAll(back.length == c.length ? back : c);
      } on Object {
        out.addAll(c);
      }
    }
    _done[key] = out;
    return out;
  }
}

class LyricsFinder {
  LyricsFinder({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  final _found = <String, Lyrics?>{};
  final _asking = <String, Future<Lyrics?>>{};

  static LyricsFinder the = LyricsFinder();

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
        // on to the next ones
      }
    }
    for (final synced in [_megalobiz, _netease, _kugou, _qq]) {
      try {
        final l = await synced(title, artist, t.dur);
        if (l != null) return l;
      } on Object {
        // that one is down or slow
      }
    }
    if (plain != null) return plain;
    for (final words in [_genius, _ovh]) {
      try {
        final l = await words(title, artist, t.dur);
        if (l != null) return l;
      } on Object {
        // and that one
      }
    }
    return null;
  }

  static const _browser = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36',
  };

  Future<Map<String, Object?>> _json(Uri uri, {Map<String, String> headers = _browser}) async {
    final res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return const {};
    return asMap(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  static const _ownAgent = {'User-Agent': 'Mixtape for phones (https://github.com/Nykairo/mixtape-mobile)'};

  /// Megalobiz's free lyrics API: synced sheets found by title, artist and length. It asks to be linked
  /// where its words show (Lyrics.link) and to be asked only for what plays: it is.
  Future<Lyrics?> _megalobiz(String title, String artist, int dur) async {
    final d = await _json(
        Uri.https('api.megalobiz.com', '/api/public/v1/search', {
          'title': title,
          if (artist.isNotEmpty) 'artist': artist,
          if (dur > 0) 'duration': '$dur',
          'limit': '5',
        }),
        headers: _ownAgent);
    for (final x in asList(d['results'])) {
      final r = asMap(x);
      final off = r['duration_diff'];
      if (dur > 0 && off is num && off.abs() > 4) continue;
      if (!sameSong(title, artist, 0, '${r['title'] ?? ''}', '${r['artist'] ?? ''}', 0)) continue;
      final got = await _json(Uri.https('api.megalobiz.com', '/api/public/v1/lrc/${r['id']}'), headers: _ownAgent);
      final rows = [
        for (final line in asList(got['lines']))
          if (asMap(line)['time_ms'] is int) (asMap(line)['time_ms'] as int, '${asMap(line)['text'] ?? ''}'.trim()),
      ];
      if (rows.isEmpty) continue;
      return Lyrics([for (final row in rows) row.$2.isEmpty ? '♪' : row.$2],
          times: [for (final row in rows) row.$1], source: 'Megalobiz', link: '${got['url'] ?? r['url'] ?? ''}');
    }
    return null;
  }

  /// QQ Music: a big catalog with synced words for songs from everywhere, not only from China.
  Future<Lyrics?> _qq(String title, String artist, int dur) async {
    const head = {..._browser, 'Referer': 'https://y.qq.com/'};
    final found = await _http
        .get(Uri.https('c.y.qq.com', '/soso/fcgi-bin/client_search_cp', {'format': 'json', 'p': '1', 'n': '8', 'w': '$title $artist'}),
            headers: head)
        .timeout(const Duration(seconds: 8));
    if (found.statusCode != 200) return null;
    final d = asMap(jsonDecode(_unwrapJsonp(utf8.decode(found.bodyBytes, allowMalformed: true))));
    for (final x in asList(asMap(asMap(d['data'])['song'])['list']).take(8)) {
      final song = asMap(x);
      final who = [for (final a in asList(song['singer'])) '${asMap(a)['name'] ?? ''}'].join(' ');
      if (!sameSong(title, artist, dur, '${song['songname'] ?? ''}', who, toInt(song['interval']))) continue;
      final got = await _http
          .get(Uri.https('c.y.qq.com', '/lyric/fcgi-bin/fcg_query_lyric_new.fcg',
              {'songmid': '${song['songmid']}', 'format': 'json', 'nobase64': '1', 'g_tk': '5381'}),
              headers: head)
          .timeout(const Duration(seconds: 8));
      if (got.statusCode != 200) continue;
      final l = asMap(jsonDecode(_unwrapJsonp(utf8.decode(got.bodyBytes, allowMalformed: true))));
      final lyrics = parseLrc(_unescapeHtml('${l['lyric'] ?? ''}'), source: 'QQ Music');
      if (lyrics != null && lyrics.lines.any((w) => w != '♪')) return lyrics;
    }
    return null;
  }

  /// QQ's answers sometimes come wrapped in a callback ("MusicJsonCallback({...})").
  static String _unwrapJsonp(String text) {
    final t = text.trim();
    if (t.startsWith('{') || t.startsWith('[')) return t;
    final open = t.indexOf('(');
    final close = t.lastIndexOf(')');
    return open >= 0 && close > open ? t.substring(open + 1, close) : t;
  }

  static String _unescapeHtml(String text) => text
      .replaceAll('&#58;', ':')
      .replaceAll('&#46;', '.')
      .replaceAll('&#32;', ' ')
      .replaceAll('&#10;', '\n')
      .replaceAll('&#13;', '')
      .replaceAll('&#45;', '-')
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');

  Future<Lyrics?> _netease(String title, String artist, int dur) async {
    final head = {..._browser, 'Referer': 'https://music.163.com/'};
    final d = await _json(Uri.https('music.163.com', '/api/search/get', {'type': '1', 'limit': '8', 's': '$title $artist'}), headers: head);
    for (final x in asList(asMap(d['result'])['songs']).take(8)) {
      final song = asMap(x);
      final who = [for (final a in asList(song['artists'])) '${asMap(a)['name'] ?? ''}'].join(' ');
      if (!sameSong(title, artist, dur, '${song['name'] ?? ''}', who, toInt(song['duration']) ~/ 1000)) continue;
      final got = await _json(Uri.https('music.163.com', '/api/song/lyric', {'id': '${song['id']}', 'lv': '1', 'kv': '1', 'tv': '-1'}),
          headers: head);
      final l = parseLrc('${asMap(got['lrc'])['lyric'] ?? ''}', source: 'NetEase');
      if (l != null && l.lines.any((w) => w != '♪')) return l;
    }
    return null;
  }

  Future<Lyrics?> _kugou(String title, String artist, int dur) async {
    final d = await _json(Uri.https('krcs.kugou.com', '/search', {
      'ver': '1',
      'man': 'yes',
      'client': 'mobi',
      'keyword': artist.isEmpty ? title : '$artist - $title',
      'duration': '${dur * 1000}',
      'hash': '',
    }));
    for (final x in asList(d['candidates']).take(3)) {
      final c = asMap(x);
      if (!sameSong(title, artist, dur, '${c['song'] ?? ''}', '${c['singer'] ?? ''}', toInt(c['duration']) ~/ 1000)) continue;
      final got = await _json(Uri.https('lyrics.kugou.com', '/download', {
        'ver': '1',
        'client': 'pc',
        'id': '${c['id']}',
        'accesskey': '${c['accesskey']}',
        'fmt': 'lrc',
        'charset': 'utf8',
      }));
      final text = utf8.decode(base64.decode('${got['content'] ?? ''}'), allowMalformed: true);
      final l = parseLrc(text, source: 'KuGou');
      if (l != null && l.lines.any((w) => w != '♪')) return l;
    }
    return null;
  }

  Future<Lyrics?> _genius(String title, String artist, int dur) async {
    final d = await _json(Uri.https('genius.com', '/api/search/song', {'per_page': '5', 'q': '$title $artist'}));
    for (final sec in asList(asMap(d['response'])['sections'])) {
      for (final hit in asList(asMap(sec)['hits'])) {
        final r = asMap(asMap(hit)['result']);
        final who = '${r['primary_artist_names'] ?? r['artist_names'] ?? ''}';
        if (r['instrumental'] == true || !sameSong(title, artist, 0, '${r['title'] ?? ''}', who, 0)) continue;
        final page = await _http.get(Uri.parse('${r['url']}'), headers: _browser).timeout(const Duration(seconds: 10));
        final text = geniusText(utf8.decode(page.bodyBytes, allowMalformed: true));
        if (text.isNotEmpty) return Lyrics(const LineSplitter().convert(text), source: 'Genius');
      }
    }
    return null;
  }

  Future<Lyrics?> _ovh(String title, String artist, int dur) async {
    final d = await _json(Uri.parse('https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}'));
    final text = '${d['lyrics'] ?? ''}'.trim();
    return text.isEmpty ? null : Lyrics(const LineSplitter().convert(text), source: 'lyrics.ovh');
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
      if (rows.isEmpty) {
        // the names written differently there ("Tyler, The Creator" or a guest in the title): the words of
        // both, as free text, and the same length and title
        final loose = Uri.https('lrclib.net', '/api/search', {'q': '$title $artist'.trim()});
        final more = await _http.get(loose, headers: headers).timeout(const Duration(seconds: 8));
        if (more.statusCode == 200) {
          rows.addAll([
            for (final r in asList(jsonDecode(utf8.decode(more.bodyBytes))))
              if (sameSong(title, artist, dur, '${asMap(r)['trackName'] ?? ''}', '${asMap(r)['artistName'] ?? ''}',
                  toInt(asMap(r)['duration'])))
                asMap(r),
          ]);
        }
      }
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
