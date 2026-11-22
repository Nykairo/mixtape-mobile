// YouTube Music in other languages than English: counts of plays and the words in front of rows must
// never end up as an artist's name (they did, in German, before 0.3.3, and showed up in Rewind).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/innertube.dart';
import 'package:mixtape/model.dart';
import 'package:mixtape/music.dart';
import 'package:mixtape/yt_words.dart';

/// A real answer with its counts said the way YouTube says them in German, and (with [bare]) the
/// artist column of each row left empty, the way album pages often have it.
Map<String, Object?> inGerman(String name, {bool bare = false}) {
  var text = File('test/fixtures/$name.json').readAsStringSync();
  text = text.replaceAllMapped(RegExp(r'"(\d+(?:\.\d+)?)([KMB]) (plays|views)"'), (m) {
    final number = m[1]!.replaceAll('.', ',');
    final size = const {'K': 'Tsd.', 'M': 'Mio.', 'B': 'Mrd.'}[m[2]]!;
    return '"$number $size ${m[3] == 'plays' ? 'Wiedergaben' : 'Aufrufe'}"';
  });
  final data = jsonDecode(text) as Map<String, Object?>;
  if (bare) _dropArtists(data);
  return data;
}

void _dropArtists(Object? node) {
  if (node is Map) {
    final row = node['musicResponsiveListItemRenderer'];
    if (row is Map && row['flexColumns'] is List && (row['flexColumns'] as List).length > 1) {
      final cols = row['flexColumns'] as List;
      (cols[1] as Map)['musicResponsiveListItemFlexColumnRenderer'] = {
        'text': {'runs': <Object?>[]},
      };
    }
    node.values.forEach(_dropArtists);
  } else if (node is List) {
    node.forEach(_dropArtists);
  }
}

void main() {
  test('counts in many languages are counts', () {
    for (final c in [
      '1.2M views', '1,2 Mio. Aufrufe', '12 mil reproducciones', '1,2 M de vues', '4,5万回視聴', '조회수 120만회',
      '1.2B plays', '12K monthly audience', '1,2 млн просмотров', '1.234 Aufrufe', '1.2M', '1,2 Mio.', '120만',
      '3 Wiedergaben', '1.2M plays', '1,2 Mio. Aufrufe', '12 tys. wyświetleń', '1,2 mln weergaven',
      '45 B görüntüleme', '8 views',
    ]) {
      expect(looksLikeCount(c), isTrue, reason: c);
    }
  });

  test('names with numbers in them are names', () {
    for (final n in [
      '50 Cent', 'Blink-182', 'M83', '112', '2 Chainz', 'Sum 41', '21 Savage', 'The 1975', 'Daft Punk', '',
      '1K Phew', '5 Seconds of Summer', 'Maroon 5', '2Pac', 'UB40', '3 Doors Down', 'Mio', 'Views', '702',
      'Plays 4 You', 'Club 8 Views',
    ]) {
      expect(looksLikeCount(n), isFalse, reason: n);
    }
  });

  test('what a count is worth', () {
    for (final (c, v) in [
      ('1.2M views', 1.2e6), ('1,2 Mio. Aufrufe', 1.2e6), ('1,234 views', 1234.0), ('1.234 Aufrufe', 1234.0),
      ('4,5万回視聴', 45000.0), ('조회수 120만회', 1.2e6), ('12 mil reproducciones', 12000.0), ('1,2 B görüntüleme', 1200.0),
      ('3 Wiedergaben', 3.0), ('1.2B plays', 1.2e9), ('1 234 567 vues', 1234567.0), ('1,2 mln weergaven', 1.2e6),
    ]) {
      expect(countValue(c), closeTo(v, v * 1e-9), reason: c);
    }
  });

  test('a line under a title: its linked artists, else its first plain part, never a count', () {
    Map<String, Object?> artist(String name) => {
          'text': name,
          'navigationEndpoint': {
            'browseEndpoint': {
              'browseId': 'UC1',
              'browseEndpointContextSupportedConfigs': {
                'browseEndpointContextMusicConfig': {'pageType': 'MUSIC_PAGE_TYPE_ARTIST'},
              },
            },
          },
        };
    expect(
        InnerTube.artistIn({
          'runs': [artist('Daft Punk'), {'text': ' & '}, artist('Julian Casablancas'), {'text': ' • 1,2 Mrd. Wiedergaben'}],
        }),
        'Daft Punk, Julian Casablancas');
    expect(InnerTube.artistIn({'runs': [{'text': 'Titel • 1,2 Mio. Wiedergaben • 3:45'}]}), '');
    expect(InnerTube.artistIn({'runs': [{'text': 'Song • Daft Punk • Discovery • 3:45'}]}), 'Daft Punk');
    expect(InnerTube.artistIn({'runs': [{'text': '4,5万回視聴'}]}), '');
  });

  test('a German album page whose rows name no artist: the album artist, not the plays', () {
    final l = parseList(inGerman('album', bare: true), 'MPREb_K8qWMWVqXGi');
    expect(l.songs, isNotEmpty);
    for (final s in l.songs) {
      expect(s.artist, 'Daft Punk', reason: s.title);
    }
  });

  test('German search and artist pages: plays are views, never artists', () {
    final songs = parseSearch(inGerman('search_songs')).items.where((i) => i.kind == Kind.song).toList();
    expect(songs, isNotEmpty);
    expect(songs.every((s) => !looksLikeCount(s.artist) && s.artist.isNotEmpty), isTrue);
    final page = parseArtist(inGerman('artist', bare: true), 'UCRr1xG_2WIDs18a6cIiCxeA');
    expect(page.songs, isNotEmpty);
    for (final s in page.songs) {
      expect(s.artist, 'Daft Punk', reason: s.title); // not the plays, and not the album next to them
    }
    for (final shelf in page.shelves) {
      for (final i in shelf.items) {
        expect(looksLikeCount(i.artist), isFalse, reason: '${shelf.title}: ${i.title} by ${i.artist}');
      }
    }
  });

  test('a song saved with a count for its artist loads without it', () {
    final t = Track.fromJson({'src': 'yt', 'ref': 'abc', 'title': 'x', 'artist': '1,2 Mio. Aufrufe'});
    expect(t?.artist, '');
    final kept = Track.fromJson({'src': 'yt', 'ref': 'abc', 'title': 'x', 'artist': '50 Cent'});
    expect(kept?.artist, '50 Cent');
    expect(t?.withArtist('Daft Punk', artistId: 'UC1').extra['artist_id'], 'UC1');
  });
}
