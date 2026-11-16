/// Podcasts, the way the computer adds them (library.podcast there): found by name in Apple's podcast
/// directory, or from a pasted RSS link, and kept as a tape called "Podcast: <name>" with its newest
/// episodes, so the computer and the phone share them through the account.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'model.dart';

/// A podcast in the directory: its name, who makes it, its picture and its feed.
typedef Show = ({String name, String by, String art, String feed});

class PodcastTrouble implements Exception {
  const PodcastTrouble(this.why);

  final String why;

  @override
  String toString() => why;
}

class Podcasts {
  Podcasts._();

  static final _client = http.Client();

  /// Podcasts for a name or a few words, from Apple's directory (no account needed).
  static Future<List<Show>> search(String words) async {
    final url = Uri.https('itunes.apple.com', '/search', {'media': 'podcast', 'limit': '15', 'term': words});
    final j = jsonDecode(await _get(url));
    final results = j is Map && j['results'] is List ? j['results'] as List : const [];
    return [
      for (final r in results)
        if (r is Map && '${r['feedUrl'] ?? ''}'.startsWith('http'))
          (
            name: '${r['collectionName'] ?? r['trackName'] ?? 'Podcast'}',
            by: '${r['artistName'] ?? ''}',
            art: '${r['artworkUrl600'] ?? r['artworkUrl100'] ?? ''}',
            feed: '${r['feedUrl']}',
          ),
    ];
  }

  /// A feed's name and its newest episodes (fifty at most), as songs that play from their links.
  static Future<(String, List<Track>)> episodes(String feed) async {
    final xml = await _get(Uri.parse(feed));
    return read(xml);
  }

  /// Reads an RSS feed's text: the show's name and picture, and each episode with a sound file.
  static (String, List<Track>) read(String xml) {
    final start = xml.indexOf('<item');
    final head = start < 0 ? xml : xml.substring(0, start);
    final name = _text(_tag(head, 'title')).ifEmpty('Podcast');
    final art = _attr(head, 'itunes:image', 'href').ifEmpty(_text(_tag(_tag(head, 'image'), 'url')));
    final out = <Track>[];
    for (final m in RegExp(r'<item[\s>](.*?)</item>', dotAll: true).allMatches(xml)) {
      final item = m.group(1)!;
      final url = _attr(item, 'enclosure', 'url');
      if (!url.startsWith('http')) continue;
      out.add(Track(
        src: 'pod',
        ref: _entities(url),
        title: _text(_tag(item, 'title')).ifEmpty('Episode'),
        artist: name,
        art: _attr(item, 'itunes:image', 'href').ifEmpty(art),
        dur: _seconds(_text(_tag(item, 'itunes:duration'))),
      ));
      if (out.length >= 50) break;
    }
    if (out.isEmpty) throw const PodcastTrouble('That feed has no episodes to play.');
    return (name, out);
  }

  static Future<String> _get(Uri url) async {
    final http.Response res;
    try {
      res = await _client.get(url, headers: const {'User-Agent': 'Mixtape (a music player)'}).timeout(const Duration(seconds: 20));
    } on Object {
      throw const PodcastTrouble("Couldn't reach it. Check the internet connection.");
    }
    if (res.statusCode != 200) throw PodcastTrouble("It didn't answer (error ${res.statusCode}). Check the link.");
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  /// What's inside the first <tag>...</tag> (empty when there's none).
  static String _tag(String xml, String tag) {
    final m = RegExp('<$tag(?:\\s[^>]*)?>(.*?)</$tag>', dotAll: true).firstMatch(xml);
    return m?.group(1) ?? '';
  }

  /// An attribute of the first <tag ...>.
  static String _attr(String xml, String tag, String attr) {
    final m = RegExp('<$tag\\s[^>]*?$attr\\s*=\\s*["\']([^"\']*)["\']', dotAll: true).firstMatch(xml);
    return m?.group(1) ?? '';
  }

  /// A tag's text: CDATA unwrapped, tags inside dropped, entities read.
  static String _text(String inner) {
    var s = inner.trim();
    final cdata = RegExp(r'^<!\[CDATA\[(.*)\]\]>$', dotAll: true).firstMatch(s);
    if (cdata != null) s = cdata.group(1)!;
    return _entities(s.replaceAll(RegExp(r'<[^>]+>'), '')).replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _entities(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
      .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
      .replaceAll('&amp;', '&');

  /// "1:02:03", "62:03" or "3723" as seconds.
  static int _seconds(String v) {
    var total = 0;
    for (final part in v.split(':')) {
      final n = int.tryParse(part.trim().split('.').first);
      if (n == null) return 0;
      total = total * 60 + n;
    }
    return total;
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
