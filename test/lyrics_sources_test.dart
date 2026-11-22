// When lrclib and YouTube Music have no lyrics for a song: lrclib's free-text search, Megalobiz's API
// (with the link back it asks for) and QQ Music find them, in that order, answering the way they do.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mixtape/lyrics.dart';
import 'package:mixtape/model.dart';

const song = Track(src: 'file', ref: '/x.mp3', title: 'Nightcall', artist: 'Kavinsky', art: '', dur: 258);

http.Response json(Object? body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: const {'content-type': 'application/json'});

void main() {
  test("lrclib's free-text search finds what the exact one didn't", () async {
    final asked = <String>[];
    final finder = LyricsFinder(client: MockClient((req) async {
      asked.add('${req.url.host}${req.url.path}?${req.url.query}');
      if (req.url.host != 'lrclib.net') return http.Response('', 404);
      if (req.url.path == '/api/get') return http.Response('', 404);
      if (req.url.queryParameters.containsKey('q')) {
        return json([
          {'trackName': 'Nightcall', 'artistName': 'Kavinsky, Lovefoxxx', 'duration': 257, 'syncedLyrics': "[00:01.00]I'm giving you a nightcall"},
        ]);
      }
      return json([]);
    }));
    final l = await finder.of(song);
    expect(l?.synced, isTrue);
    expect(l?.source, 'lrclib');
    expect(asked.any((a) => a.contains('q=Nightcall+Kavinsky')), isTrue);
  });

  test('Megalobiz: a sheet of the same length, and the page to link back to', () async {
    final finder = LyricsFinder(client: MockClient((req) async {
      if (req.url.host == 'api.megalobiz.com' && req.url.path.endsWith('/search')) {
        expect(req.url.queryParameters['duration'], '258');
        expect(req.headers['User-Agent'], contains('Mixtape'));
        return json({
          'count': 2,
          'results': [
            {'id': 1, 'title': 'Nightcall (Live)', 'artist': 'Kavinsky', 'duration_diff': 31.0, 'url': 'https://megalobiz.com/lrc/1'},
            {'id': 2, 'title': 'Nightcall', 'artist': 'Kavinsky', 'duration_diff': 0.6, 'url': 'https://megalobiz.com/lrc/2/nightcall'},
          ],
        });
      }
      if (req.url.host == 'api.megalobiz.com' && req.url.path.endsWith('/lrc/2')) {
        return json({
          'id': 2,
          'url': 'https://megalobiz.com/lrc/2/nightcall',
          'lines': [
            {'time_ms': 12340, 'text': "I'm giving you a nightcall"},
            {'time_ms': 15800, 'text': ''},
          ],
        });
      }
      return http.Response('', 404);
    }));
    final l = await finder.of(song);
    expect(l?.source, 'Megalobiz');
    expect(l?.link, 'https://megalobiz.com/lrc/2/nightcall');
    expect(l?.times, [12340, 15800]);
    expect(l?.lines, ["I'm giving you a nightcall", '♪']);
  });

  test('QQ Music, answering in a callback and with HTML marks in the words', () async {
    final finder = LyricsFinder(client: MockClient((req) async {
      if (req.url.host == 'c.y.qq.com' && req.url.path.contains('client_search_cp')) {
        return http.Response.bytes(
            utf8.encode('callback(${jsonEncode({
              'code': 0,
              'data': {
                'song': {
                  'list': [
                    {'songmid': 'abc', 'songname': 'Nightcall', 'interval': 258, 'singer': [{'name': 'Kavinsky'}]},
                  ],
                },
              },
            })})'),
            200);
      }
      if (req.url.host == 'c.y.qq.com' && req.url.path.contains('fcg_query_lyric_new')) {
        expect(req.headers['Referer'], 'https://y.qq.com/');
        return json({'code': 0, 'lyric': '[00&#58;01&#46;00]I&#39;m giving you a nightcall&#10;[00&#58;05&#46;50]to tell you how I feel'});
      }
      return http.Response('', 404);
    }));
    final l = await finder.of(song);
    expect(l?.source, 'QQ Music');
    expect(l?.lines, ["I'm giving you a nightcall", 'to tell you how I feel']);
    expect(l?.times, [1000, 5500]);
  });
}
