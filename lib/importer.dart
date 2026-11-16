/// Playlists from elsewhere, made into tapes, the way the computer's importer does it (importer.py
/// there): Spotify playlists, albums and single songs (read from the small page Spotify makes for other
/// websites, so no login), Deezer, YouTube and YouTube Music lists, CSV exports (Exportify, TuneMyMusic)
/// and pasted lists of songs.
///
/// Songs from elsewhere arrive as titles and artists. Each one is looked up on YouTube Music, then as an
/// upload on YouTube, and a song that is on neither is listed at the end instead of being swapped for
/// some other song.
library;

import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'lyrics.dart' show folded;
import 'model.dart';
import 'music.dart';

/// A song still to be found: its title, its artists, and its length in seconds (0 when the list
/// doesn't say).
typedef Wanted = ({String title, String artist, int dur});

class Listing {
  const Listing(this.name, {this.ready = const [], this.wanted = const [], this.note = ''});

  final String name;

  /// Songs that play as they are (a YouTube Music list's).
  final List<Track> ready;
  final List<Wanted> wanted;

  /// Something to know about the list (Spotify shows only its first 100 songs without a login).
  final String note;
}

/// Why a list couldn't be read, in words for the person.
class ImportTrouble implements Exception {
  const ImportTrouble(this.why);

  final String why;

  @override
  String toString() => why;
}

final _spotify = RegExp(r'(playlist|album|track)[/:]([A-Za-z0-9]{22})');
const _browser = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0'};

class Importer {
  Importer._();

  static final _client = http.Client();

  /// Is this text a link to a list (or a song) somewhere else, for the search box to hand over here?
  static bool isListLink(String text) {
    final t = text.trim();
    if (t.contains(' ') || t.contains('\n')) return false;
    if (t.toLowerCase().startsWith('spotify:')) return true;
    final u = Uri.tryParse(t);
    if (u == null || !u.hasScheme || !u.scheme.startsWith('http')) return false;
    final host = u.host.toLowerCase();
    if (host.contains('spotify') || host.contains('deezer')) return true;
    return (host.contains('youtube') || host == 'youtu.be') && (u.queryParameters.containsKey('list') || u.path.contains('/browse/MPRE'));
  }

  /// Reads what was pasted: a link, a CSV export or one song per line.
  static Future<Listing> load(String text) async {
    final first = text.trim().split('\n').first.trim();
    if (first.isEmpty) throw const ImportTrouble('Paste a link or a few songs first.');
    if (first.toLowerCase().startsWith('spotify:')) return spotify(first);
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(first)) {
      final host = Uri.tryParse(first)?.host.toLowerCase() ?? '';
      if (host.contains('spotify')) return spotify(first);
      if (host.contains('deezer')) return deezer(first);
      if (host.contains('youtube') || host == 'youtu.be') return youtube(first);
      throw const ImportTrouble('Mixtape reads links from Spotify, YouTube, YouTube Music and Deezer.');
    }
    final wanted = lines(text);
    if (wanted.isEmpty) throw const ImportTrouble('No songs in there. One song per line, like: Artist - Title');
    return Listing('Imported songs', wanted: wanted);
  }

  static Future<String> _get(Uri url, {bool json = false}) async {
    final http.Response res;
    try {
      res = await _client.get(url, headers: _browser).timeout(const Duration(seconds: 20));
    } on Object {
      throw const ImportTrouble("Couldn't reach it. Check the internet connection.");
    }
    if (res.statusCode == 400 || res.statusCode == 404) {
      throw const ImportTrouble("That list doesn't exist (or isn't public). Check the link.");
    }
    if (res.statusCode != 200) throw ImportTrouble("It didn't answer (error ${res.statusCode}). Try again in a moment.");
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  // ------------------------------------------------------------ Spotify

  /// A public Spotify playlist, album or song. No login needed, but the page lists at most 100 songs.
  static Future<Listing> spotify(String link) async {
    final m = _spotify.firstMatch(link);
    if (m == null) throw const ImportTrouble("That Spotify link isn't a playlist, an album or a song.");
    final page = await _get(Uri.parse('https://open.spotify.com/embed/${m.group(1)}/${m.group(2)}'));
    return spotifyPage(page);
  }

  static Listing spotifyPage(String page) {
    final raw = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', dotAll: true).firstMatch(page);
    if (raw == null) {
      throw const ImportTrouble('Spotify changed its page. Export the playlist as CSV (exportify.net) and paste that here.');
    }
    final entity = _dig(jsonDecode(raw.group(1)!), 'entity');
    final e = entity is Map ? entity : const {};
    final List<Object?> rows;
    if (e['type'] == 'track') {
      final who = [
        for (final a in e['artists'] is List ? e['artists'] as List : const [])
          if (a is Map) '${a['name'] ?? ''}',
      ].join(', ');
      rows = [
        {'title': e['title'] ?? e['name'], 'subtitle': who, 'duration': e['duration']},
      ];
    } else {
      final list = e['trackList'] ?? _dig(e, 'trackList');
      rows = list is List ? list : const [];
    }
    final wanted = <Wanted>[
      for (final t in rows)
        if (t is Map && '${t['title'] ?? ''}'.isNotEmpty)
          (
            title: '${t['title']}',
            artist: '${t['subtitle'] ?? ''}'.replaceAll(' ', ' '),
            dur: (t['duration'] is num ? (t['duration'] as num).toInt() : 0) ~/ 1000,
          ),
    ];
    if (wanted.isEmpty) throw const ImportTrouble('No songs found. The playlist has to be public.');
    final note = e['type'] == 'playlist' && wanted.length >= 100
        ? 'Spotify only shows the first 100 songs of a playlist without a login. For all of them, export it '
            'as CSV on exportify.net and paste that here.'
        : '';
    return Listing('${e['name'] ?? 'Spotify import'}', wanted: wanted, note: note);
  }

  /// The first value under [key] anywhere in a JSON tree.
  static Object? _dig(Object? o, String key) {
    if (o is Map) {
      if (o.containsKey(key)) return o[key];
      for (final v in o.values) {
        final r = _dig(v, key);
        if (r != null) return r;
      }
    } else if (o is List) {
      for (final v in o) {
        final r = _dig(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  // ------------------------------------------------------------ Deezer

  /// A Deezer playlist, album or song. Short share links (deezer.page.link, link.deezer.com) are
  /// followed to where they lead first.
  static Future<Listing> deezer(String link) async {
    var url = link;
    for (var hop = 0; hop < 4 && !RegExp(r'/(playlist|album|track)/\d+').hasMatch(url); hop++) {
      final req = http.Request('GET', Uri.parse(url))
        ..followRedirects = false
        ..headers.addAll(_browser);
      try {
        final res = await _client.send(req).timeout(const Duration(seconds: 15));
        await res.stream.drain<void>();
        final next = res.headers['location'];
        if (next == null) break;
        url = Uri.parse(url).resolve(next).toString();
      } on Object {
        throw const ImportTrouble("Couldn't reach Deezer. Check the internet connection.");
      }
    }
    final m = RegExp(r'/(playlist|album|track)/(\d+)').firstMatch(url);
    if (m == null) throw const ImportTrouble("That Deezer link isn't a playlist, an album or a song.");
    final kind = m.group(1)!, id = m.group(2)!;
    Map<String, Object?> ask(String body) {
      final j = jsonDecode(body);
      if (j is! Map<String, Object?> || j['error'] != null) {
        throw const ImportTrouble("Deezer doesn't know that list, or it isn't public.");
      }
      return j;
    }

    Wanted song(Map t) => (
          title: '${t['title'] ?? ''}',
          artist: '${(t['artist'] is Map ? (t['artist'] as Map)['name'] : '') ?? ''}',
          dur: t['duration'] is num ? (t['duration'] as num).toInt() : 0,
        );
    if (kind == 'track') {
      final t = ask(await _get(Uri.parse('https://api.deezer.com/track/$id')));
      return Listing('${t['title'] ?? 'Deezer song'}', wanted: [song(t)]);
    }
    final head = ask(await _get(Uri.parse('https://api.deezer.com/$kind/$id')));
    final wanted = <Wanted>[];
    var next = 'https://api.deezer.com/$kind/$id/tracks?limit=100';
    while (next.isNotEmpty && wanted.length < 2000) {
      final page = ask(await _get(Uri.parse(next)));
      for (final t in page['data'] is List ? page['data'] as List : const []) {
        if (t is Map && '${t['title'] ?? ''}'.isNotEmpty) wanted.add(song(t));
      }
      next = page['next'] is String ? page['next'] as String : '';
    }
    return Listing('${head['title'] ?? 'Deezer import'}', wanted: wanted);
  }

  // ------------------------------------------------------------ YouTube and YouTube Music

  /// A YouTube or YouTube Music playlist, or an album: songs that play as they are.
  static Future<Listing> youtube(String link) async {
    final u = Uri.parse(link);
    final album = RegExp(r'browse/(MPRE[\w-]+)').firstMatch(link)?.group(1);
    final id = album ?? u.queryParameters['list'];
    if (id == null || id.isEmpty) throw const ImportTrouble("That link isn't a playlist or an album.");
    try {
      var page = await Music.list(id);
      while (page.more.isNotEmpty && page.songs.length < 2000) {
        page = await Music.more(page);
      }
      final songs = [
        for (final t in page.songs)
          if (t.playable) t,
      ];
      if (songs.isEmpty) throw const ImportTrouble('No songs in that list (or it is private).');
      return Listing(page.title.isEmpty ? 'YouTube list' : page.title, ready: songs);
    } on ImportTrouble {
      rethrow;
    } on Object {
      throw const ImportTrouble("YouTube didn't give that list. It may be private, or try again in a moment.");
    }
  }

  // ------------------------------------------------------------ pasted lists

  /// A CSV export (Exportify, TuneMyMusic and the like) or one song per line as Artist - Title.
  static List<Wanted> lines(String text) {
    final rows = [
      for (final l in const LineSplitter().convert(text))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    if (rows.isEmpty) return const [];
    if (rows.first.contains(',') && RegExp(r'track name|title', caseSensitive: false).hasMatch(rows.first)) {
      final head = [for (final h in _csvRow(rows.first)) h.toLowerCase()];
      int col(List<String> names) {
        for (final n in names) {
          final k = head.indexOf(n);
          if (k >= 0) return k;
        }
        return -1;
      }

      final ti = col(['track name', 'title', 'song']);
      final ai = col(['artist name(s)', 'artist name', 'artist']);
      final di = col(['track duration (ms)', 'duration (ms)']);
      return [
        for (final r in rows.skip(1).map(_csvRow))
          if (ti >= 0 && ti < r.length && r[ti].isNotEmpty)
            (
              title: r[ti],
              artist: ai >= 0 && ai < r.length ? r[ai].replaceAll(';', ', ') : '',
              dur: di >= 0 && di < r.length ? (int.tryParse(r[di]) ?? 0) ~/ 1000 : 0,
            ),
      ];
    }
    final dash = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$'); // a hyphen or either long dash between them
    return [
      for (final l in rows)
        if (dash.firstMatch(l) case final m?)
          (title: m.group(2)!.trim(), artist: m.group(1)!.trim(), dur: 0)
        else
          (title: l, artist: '', dur: 0),
    ];
  }

  /// One line of CSV: fields split at commas, a field in quotes can hold commas and doubled quotes.
  static List<String> _csvRow(String line) {
    final out = <String>[];
    final b = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (quoted) {
        if (c == '"' && i + 1 < line.length && line[i + 1] == '"') {
          b.write('"');
          i++;
        } else if (c == '"') {
          quoted = false;
        } else {
          b.write(c);
        }
      } else if (c == '"') {
        quoted = true;
      } else if (c == ',') {
        out.add(b.toString().trim());
        b.clear();
      } else {
        b.write(c);
      }
    }
    out.add(b.toString().trim());
    return out;
  }

  // ------------------------------------------------------------ finding each song

  /// Finds every wanted song, a few at a time, telling [progress] how far it is. Returns the songs
  /// found (in the list's order) and the ones that weren't.
  static Future<(List<Track>, List<Wanted>)> findAll(List<Wanted> wanted, {void Function(int done, int all)? progress}) async {
    final found = List<Track?>.filled(wanted.length, null);
    var next = 0, done = 0;
    Future<void> worker() async {
      while (next < wanted.length) {
        final k = next++;
        found[k] = await locate(wanted[k]);
        progress?.call(++done, wanted.length);
      }
    }

    await Future.wait([for (var w = 0; w < min(4, wanted.length); w++) worker()]);
    final seen = <String>{};
    return (
      [
        for (final t in found)
          if (t != null && seen.add(t.id)) t,
      ],
      [
        for (var k = 0; k < wanted.length; k++)
          if (found[k] == null) wanted[k],
      ],
    );
  }

  /// The song on YouTube Music when it's there, else an upload of it on YouTube; null rather than some
  /// other song when nothing really is the song.
  static Future<Track?> locate(Wanted w) async {
    if (w.title.trim().isEmpty) return null;
    final names = artistsOf(w.artist);
    final q = '${names.isEmpty ? '' : names.first} ${w.title}'.trim();
    Track? near;
    try {
      final got = await Music.search(q, filter: 'songs');
      Track? best;
      var top = -9.0;
      for (final i in got.items) {
        if (!i.playable) continue;
        final score = likeness(i.track, w);
        if (score > top) {
          top = score;
          best = i.track;
        }
      }
      if (best != null && top >= 2.0) return best;
      if (best != null && top >= 1.2 && (w.artist.isEmpty || artistMatch(best, w.artist) > 0)) near = best;
    } on Object {
      // nothing from the songs: the uploads may still have it
    }
    try {
      final got = await Music.search(q, filter: 'videos');
      for (final i in got.items) {
        if (i.playable && playsAs(i.track, w, 25)) return i.track;
      }
    } on Object {
      // no uploads either
    }
    return near;
  }
}

// ---------------------------------------------------------------- how alike two songs are

final _split = RegExp(r'\s*[,;&/]\s*|\s+(?:feat\.?|ft\.?|featuring|with|x|and)\s+', caseSensitive: false);
final _brackets = RegExp(r'[\(\[][^\)\]]*[\)\]]');
final _extra = RegExp(
    r'\s+-\s+(remaster(ed)?|live|radio edit|single version|mono|stereo|\d{4} remaster|from\s|original mix|bonus track|album version).*$',
    caseSensitive: false);
final _feat = RegExp(r'\s+(feat\.?|ft\.?|featuring|with)\s.*$', caseSensitive: false);

/// Words that make an upload some other recording of the song; they only count when the song looked
/// for doesn't have them in its own title.
const _versions = ['cover', 'karaoke', 'instrumental', 'remix', 'sped up', 'slowed', 'nightcore', '8d', 'reverb', 'live',
    'acoustic', 'reaction', 'mashup', 'bass boosted', 'tutorial', 'lesson'];

/// A title or name for comparing: without bracketed bits, featured artists and "- Remastered".
String plainTitle(String text) => folded(text.replaceAll(_brackets, '').replaceAll(_feat, '').replaceAll(_extra, ''));

/// "Daft Punk, Pharrell Williams" or "Kavinsky feat. Lovefoxxx" as the single names.
List<String> artistsOf(String artist) => [
      for (final a in artist.split(_split))
        if (a.trim().isNotEmpty) a.trim(),
    ];

/// How much of one of the wanted artists is in the song's artists, from 0 to 1.
double artistMatch(Track t, String artist) {
  final got = plainTitle(t.artist).split(' ').toSet();
  var best = 0.0;
  for (final a in artistsOf(artist)) {
    final want = plainTitle(a).split(' ').where((w) => w.isNotEmpty).toSet();
    if (want.isNotEmpty) best = max(best, want.intersection(got).length / want.length);
  }
  return best;
}

/// The title's likeness (twice as much as the rest), the artist's, minus a bit when the length is off.
double likeness(Track t, Wanted w) {
  final a = plainTitle(t.title), b = plainTitle(w.title);
  var score = a.isNotEmpty && b.isNotEmpty ? similar(a, b) * 2 : 0.0;
  if (w.artist.isNotEmpty) score += artistMatch(t, w.artist);
  if (w.dur > 0 && t.dur > 0) {
    final off = (t.dur - w.dur).abs();
    score -= off <= 4 ? 0 : min(1.0, off / 60);
  }
  return score;
}

/// Is an upload on YouTube really this song? Uploads often carry the artist in their title ("Kavinsky
/// - Nightcall (Official Video)"), and the uploader can be anyone. [slack]: how many seconds longer or
/// shorter it may be (music videos have intros).
bool playsAs(Track t, Wanted w, int slack) {
  if (w.dur > 0 && t.dur > 0 && (t.dur - w.dur).abs() > slack) return false;
  final want = plainTitle(w.title), got = plainTitle(t.title);
  if (want.replaceAll(' ', '').length >= 4) {
    if (!got.replaceAll(' ', '').contains(want.replaceAll(' ', ''))) return false;
  } else if (want.isEmpty || !' $got '.contains(' $want ')) {
    return false; // a short title like "Go" has to be a word of its own
  }
  final whole = ' ${folded(t.title)} ', asked = ' ${folded(w.title)} ';
  if (_versions.any((v) => whole.contains(' $v ') && !asked.contains(' $v '))) return false;
  if (w.artist.isEmpty) return true;
  final blob = '${folded(t.title)}|${folded(t.artist)}'.replaceAll(' ', '');
  return artistsOf(w.artist).map((a) => folded(a).replaceAll(' ', '')).any((p) => p.length >= 2 && blob.contains(p));
}

/// How alike two strings are, 0 to 1, the way Python's difflib measures it (Ratcliff and Obershelp):
/// twice the letters in matching runs over all the letters.
double similar(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  int matching(String x, String y) {
    if (x.isEmpty || y.isEmpty) return 0;
    var best = 0, bx = 0, by = 0;
    var prev = List<int>.filled(y.length + 1, 0);
    for (var i = 1; i <= x.length; i++) {
      final row = List<int>.filled(y.length + 1, 0);
      for (var j = 1; j <= y.length; j++) {
        if (x.codeUnitAt(i - 1) == y.codeUnitAt(j - 1)) {
          row[j] = prev[j - 1] + 1;
          if (row[j] > best) {
            best = row[j];
            bx = i - best;
            by = j - best;
          }
        }
      }
      prev = row;
    }
    if (best == 0) return 0;
    return best + matching(x.substring(0, bx), y.substring(0, by)) + matching(x.substring(bx + best), y.substring(by + best));
  }

  return 2 * matching(a, b) / (a.length + b.length);
}
