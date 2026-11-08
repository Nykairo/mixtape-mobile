// The real YouTube, asked the way the iPhone version asks it (InnerTube): run on their own with
// `flutter test --tags network`. YouTube is stricter with servers than with phones, so a "busy" here
// doesn't mean the app is broken.
@Tags(['network'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mixtape/innertube.dart';

void main() {
  final tube = InnerTube();

  test('a search finds songs', () async {
    final found = await tube.search('daft punk get lucky');
    // ignore: avoid_print
    print('search: ${found.length} songs, first: ${found.isEmpty ? '-' : found.first}');
    expect(found, isNotEmpty);
    expect(found.first['id'], isA<String>());
  });

  test('a song gives its audio, and its first bytes come', () async {
    final found = await tube.search('daft punk get lucky');
    final song = await tube.resolve('${found.first['id']}');
    // ignore: avoid_print
    print('resolve: ${song['mime']}, ${song['bitrate']} kbit/s, ${song['length']} bytes, '
        '${(song['related'] as List).length} songs like it');
    final res = await http.get(Uri.parse('${song['url']}'),
        headers: {'Range': 'bytes=0-65535', 'User-Agent': '${song['agent']}'});
    // ignore: avoid_print
    print('fetch: HTTP ${res.statusCode}, ${res.bodyBytes.length} bytes');
    expect(res.statusCode, anyOf(200, 206));
  });
}
