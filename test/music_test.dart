// YouTube Music's answers, read the way the app reads them. The answers in test/fixtures are real ones
// (November 2026, made smaller), so these checks fail when the reading goes wrong, not when YouTube
// changes: that shows in the YouTube check against the real thing (youtube_live_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/heat.dart';
import 'package:mixtape/innertube.dart';
import 'package:mixtape/lyrics.dart';
import 'package:mixtape/music.dart';
import 'package:mixtape/video.dart';

Map<String, Object?> fixture(String name) =>
    Map<String, Object?>.from(jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map);

void main() {
  group('search', () {
    test('everything at once: the top result and a mix of the rest', () {
      final r = parseSearch(fixture('search_all'));
      expect(r.top?.kind, Kind.artist);
      expect(r.top?.title, 'Daft Punk');
      expect(r.top?.id, 'UCRr1xG_2WIDs18a6cIiCxeA');
      final album = r.items.firstWhere((i) => i.title == 'Random Access Memories');
      expect(album.kind, Kind.album);
      expect(album.id, 'MPREb_K8qWMWVqXGi');
      expect(album.artist, 'Daft Punk');
      final song = r.items.firstWhere((i) => i.title == 'Harder, Better, Faster, Stronger');
      expect(song.kind, Kind.song);
      expect(song.artist, 'Daft Punk');
      expect(r.items.any((i) => i.kind == Kind.video), isTrue);
    });

    test('songs, with album, length and more to come', () {
      final r = parseSearch(fixture('search_songs'));
      expect(r.items.length, greaterThanOrEqualTo(15));
      final first = r.items.first;
      expect(first.kind, Kind.song);
      expect(first.title, startsWith('Arena'));
      expect(first.dur, 94);
      expect(first.album, 'TRON: Legacy');
      expect(first.albumId, startsWith('MPREb_'));
      expect(first.artistId, 'UCRr1xG_2WIDs18a6cIiCxeA');
      expect(first.views, greaterThan(1e6));
      expect(first.track.extra['album_id'], first.albumId);
      expect(r.more, isNotEmpty);
    });

    test('albums and artists', () {
      final albums = parseSearch(fixture('search_albums')).items;
      expect(albums.first.kind, Kind.album);
      expect(albums.first.subtitle, contains('2013'));
      final artists = parseSearch(fixture('search_artists')).items;
      expect(artists.every((a) => a.kind == Kind.artist), isTrue);
      expect(artists.first.title, 'Daft Punk');
    });

    test('videos: official ones, with views and length', () {
      final videos = parseSearch(fixture('search_videos')).items;
      final omv = videos.firstWhere((v) => v.title == 'Blinding Lights (Official Video)');
      expect(omv.kind, Kind.video);
      expect(omv.official, isTrue);
      expect(omv.artist, 'The Weeknd');
      expect(omv.dur, 263);
      expect(omv.views, greaterThan(1e8));
    });

    test('suggestions while typing', () {
      final (words, items) = parseSuggestions(fixture('suggestions'));
      expect(words, contains('daft punk'));
      expect(items.any((i) => i.kind == Kind.artist && i.title == 'Daft Punk'), isTrue);
      expect(items.any((i) => i.kind == Kind.song), isTrue);
    });
  });

  group('pages', () {
    test('an artist: top songs, albums, the mix', () {
      final a = parseArtist(fixture('artist'), 'UCRr1xG_2WIDs18a6cIiCxeA');
      expect(a.name, 'Daft Punk');
      expect(a.art, isNotEmpty);
      expect(a.songs.length, 5);
      expect(a.songs.first.title, startsWith('Instant Crush'));
      expect(a.allSongs, startsWith('VL'));
      expect(a.radio, startsWith('RDEM'));
      final albums = a.shelves.firstWhere((s) => s.title == 'Albums');
      expect(albums.items.first.kind, Kind.album);
      expect(albums.items.first.artist, 'Daft Punk');
      final fans = a.shelves.firstWhere((s) => s.title == 'Fans might also like');
      expect(fans.items.first.kind, Kind.artist);
      expect(a.shelves.firstWhere((s) => s.title == 'Videos').items.first.kind, Kind.video);
    });

    test('an album: its songs with the album cover and artist', () {
      final l = parseList(fixture('album'), 'MPREb_K8qWMWVqXGi');
      expect(l.title, 'Random Access Memories');
      expect(l.kind, Kind.album);
      expect(l.artist, 'Daft Punk');
      expect(l.songs.length, 13);
      expect(l.songs.first.title, 'Give Life Back to Music');
      expect(l.songs.first.dur, 276);
      expect(l.songs.first.art, l.art);
      expect(l.songs.first.album, 'Random Access Memories');
      expect(l.second, contains('13 songs'));
    });

    test('the home page: moods to pick and shelves', () {
      final h = parseHome(fixture('home'));
      expect(h.chips.map((c) => c.$1), contains('Relax'));
      expect(h.chips.every((c) => c.$2.isNotEmpty), isTrue);
      expect(h.shelves.map((s) => s.title), contains('Throwbacks'));
      expect(h.shelves.first.items.first.kind, Kind.playlist);
    });

    test('moods and genres', () {
      final m = parseMoods(fixture('moods'));
      expect(m.length, greaterThan(30));
      final chill = m.firstWhere((x) => x.title == 'Chill');
      expect(chill.genre, isFalse);
      expect(chill.params, isNotEmpty);
      expect(m.any((x) => x.genre), isTrue);
    });

    test("a song's radio, with its lyrics and related pages", () {
      final n = parseNext(fixture('next'), 'J7p4bzqLvCw');
      expect(n.songs.length, greaterThanOrEqualTo(10));
      expect(n.songs.first.ref, 'J7p4bzqLvCw');
      expect(n.songs.first.album, 'Blinding Lights');
      expect(n.lyrics, startsWith('MPLY'));
      expect(n.related, startsWith('MPTR'));
    });

    test('related: songs and artists like it', () {
      final shelves = parseShelves(fixture('related'));
      expect(shelves.map((s) => s.title), containsAll(['You might also like', 'Similar artists']));
    });
  });

  group('lyrics', () {
    test("YouTube Music's synced words", () {
      final l = parseTimedLyrics(fixture('lyrics_timed'))!;
      expect(l.synced, isTrue);
      expect(l.lines[1], 'Yeah');
      expect(l.times[1], 13530);
      expect(l.source, 'Musixmatch');
      expect(l.lineAt(14000), 1);
      expect(l.lineAt(0), 0);
    });

    test('plain words', () {
      final l = parsePlainLyrics(fixture('lyrics_plain'))!;
      expect(l.synced, isFalse);
      expect(l.lines.first, 'Yeah');
    });

    test('LRC from lrclib', () {
      final l = parseLrc('[ar: x]\n[00:13.13]Yeah\n[00:16.56]\n[01:02.5]Later [00:30.00]wrong place\n[00:20.00][00:40.00]twice')!;
      expect(l.lines.first, 'Yeah');
      expect(l.times.first, 13130);
      expect(l.lines[1], '♪');
      expect(l.times, orderedEquals([...l.times]..sort()));
      expect(l.lineAt(21000), l.times.indexOf(20000));
      expect(l.lines.where((x) => x == 'twice').length, 2);
      expect(l.lineAt(5000), -1);
    });

    test('titles the way lyrics sites know them', () {
      expect(cleanTitle('Get Lucky (feat. Pharrell Williams and Nile Rodgers)'), 'Get Lucky');
      expect(cleanTitle('Bohemian Rhapsody - Remastered 2011'), 'Bohemian Rhapsody');
      expect(cleanTitle('Song (Official Video)'), 'Song');
    });
  });

  group('the most replayed curve', () {
    test('read from youtube.com', () {
      final h = InnerTube.heatOf(fixture('web_next'));
      expect(h.length, 100);
      expect(h.first.$3, 1.0);
    });

    test('the best half minute', () {
      final h = InnerTube.heatOf(fixture('web_next'));
      final at = bestPart(h, 202);
      expect(at, inInclusiveRange(10, 168));
      expect(bestPart(const [], 200), 66.7);
      expect(bestPart(const [], 20), 0);
    });

    test('where a song starts in its music video', () {
      final pairs = jsonDecode(File('test/fixtures/heat_pairs.json').readAsStringSync()) as List;
      Heat curve(Object? rows) => [
            for (final r in rows as List) ((r[0] as num).toDouble(), (r[1] as num).toDouble(), (r[2] as num).toDouble()),
          ];
      for (final p in pairs.cast<Map>()) {
        final got = lineUp(curve(p['song']), curve(p['clip']), (p['song_len'] as num).toDouble(), (p['video_len'] as num).toDouble());
        final lead = p['lead'];
        if (lead == null) {
          expect(got, isNull, reason: '${p['title']} is another recording');
        } else {
          expect(got, inInclusiveRange((lead as List)[0] as int, lead[1] as int), reason: '${p['title']}');
        }
      }
    });
  });

  group('video mode', () {
    test('the official video, and nothing that only looks like it', () {
      final rows = parseSearch(fixture('search_videos')).items;
      final picked = pickVideos(rows, 'Blinding Lights', 'The Weeknd', 202);
      expect(picked.first.title, 'Blinding Lights (Official Video)');
      expect(picked.any((v) => v.title.contains('Lyrics')), isFalse);
      expect(pickVideos(rows, 'Blinding Lights', 'Somebody Else', 202), isEmpty);
      expect(plainName('Señorita (feat. X)'), 'senorita');
      expect(plainName('Wonderwall - Remastered 2014'), 'wonderwall');
    });
  });
}
