import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/importer.dart';
import 'package:mixtape/model.dart';
import 'package:mixtape/podcasts.dart';

void main() {
  test('links from elsewhere are known as lists', () {
    expect(Importer.isListLink('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=1'), isTrue);
    expect(Importer.isListLink('spotify:album:4aawyAB9vmqN3uQ7FjRGTy'), isTrue);
    expect(Importer.isListLink('https://www.deezer.com/en/playlist/1479458365'), isTrue);
    expect(Importer.isListLink('https://music.youtube.com/playlist?list=PL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i'), isTrue);
    expect(Importer.isListLink('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isFalse);
    expect(Importer.isListLink('daft punk one more time'), isFalse);
  });

  test("Spotify's embed page gives the songs, without a login", () {
    final data = {
      'props': {
        'pageProps': {
          'state': {
            'data': {
              'entity': {
                'type': 'playlist',
                'name': 'Road trip',
                'trackList': [
                  {'title': 'Nightcall', 'subtitle': 'Kavinsky, Lovefoxxx', 'duration': 258000},
                  {'title': 'Midnight City', 'subtitle': 'M83', 'duration': 243000},
                  {'subtitle': 'no title, left out'},
                ],
              },
            },
          },
        },
      },
    };
    final page = '<html><script id="__NEXT_DATA__" type="application/json">${jsonEncode(data)}</script></html>';
    final list = Importer.spotifyPage(page);
    expect(list.name, 'Road trip');
    expect(list.wanted.length, 2);
    expect(list.wanted.first.title, 'Nightcall');
    expect(list.wanted.first.artist, 'Kavinsky, Lovefoxxx');
    expect(list.wanted.first.dur, 258);
    expect(list.note, isEmpty);
    expect(() => Importer.spotifyPage('<html>nothing</html>'), throwsA(isA<ImportTrouble>()));
  });

  test('pasted lists and CSV exports', () {
    final pasted = Importer.lines('Kavinsky - Nightcall\n\nM83 – Midnight City\nJust a title\n');
    expect(pasted.length, 3);
    expect(pasted[0].artist, 'Kavinsky');
    expect(pasted[0].title, 'Nightcall');
    expect(pasted[1].artist, 'M83');
    expect(pasted[2].artist, '');
    final csv = Importer.lines('"Track Name","Artist Name(s)","Track Duration (ms)"\n'
        '"Get Lucky","Daft Punk;Pharrell Williams","248000"\n'
        '"Hello, Goodbye","The Beatles","210000"\n');
    expect(csv.length, 2);
    expect(csv[0].artist, 'Daft Punk, Pharrell Williams');
    expect(csv[0].dur, 248);
    expect(csv[1].title, 'Hello, Goodbye');
  });

  test('songs are matched the way the computer matches them', () {
    expect(similar('nightcall', 'nightcall'), 1.0);
    expect(similar('abc', 'xyz'), 0.0);
    expect(similar('midnight city', 'midnight city remix'), greaterThan(0.8));
    expect(plainTitle('Nightcall (Official Video) - Remastered 2010'), 'nightcall');
    expect(artistsOf('Daft Punk feat. Pharrell Williams & Nile Rodgers'), ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']);
    const want = (title: 'Nightcall', artist: 'Kavinsky', dur: 258);
    const song = Track(src: 'yt', ref: 'a', title: 'Nightcall', artist: 'Kavinsky', dur: 259);
    const other = Track(src: 'yt', ref: 'b', title: 'Nightcall (Karaoke Version)', artist: 'Sing Along', dur: 260);
    expect(likeness(song, want), greaterThan(2.5));
    expect(likeness(other, want), lessThan(likeness(song, want)));
    const upload = Track(src: 'yt', ref: 'c', title: 'Kavinsky - Nightcall (Drive Original Movie Soundtrack)', artist: 'KavinskyVEVO', dur: 270);
    expect(playsAs(upload, want, 25), isTrue);
    expect(playsAs(other, want, 25), isFalse, reason: 'a karaoke version is another recording');
  });

  test('a podcast feed becomes its episodes', () {
    const xml = '''<?xml version="1.0"?><rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<title><![CDATA[Tape Talk & Friends]]></title><itunes:image href="https://example.com/show.jpg"/>
<item><title>Episode 2: Reels</title><enclosure url="https://example.com/2.mp3?a=1&amp;b=2" type="audio/mpeg" length="1"/>
<itunes:duration>1:02:03</itunes:duration></item>
<item><title>No sound here</title></item>
<item><title><![CDATA[Episode 1]]></title><enclosure url="https://example.com/1.mp3" type="audio/mpeg"/><itunes:duration>754</itunes:duration></item>
</channel></rss>''';
    final (name, eps) = Podcasts.read(xml);
    expect(name, 'Tape Talk & Friends');
    expect(eps.length, 2);
    expect(eps[0].src, 'pod');
    expect(eps[0].ref, 'https://example.com/2.mp3?a=1&b=2');
    expect(eps[0].dur, 3723);
    expect(eps[0].art, 'https://example.com/show.jpg');
    expect(eps[1].title, 'Episode 1');
    expect(eps[1].dur, 754);
    expect(eps[1].playable, isTrue);
  });
}
