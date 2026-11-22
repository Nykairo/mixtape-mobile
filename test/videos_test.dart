// More ways to a song's video: the artist's lyric video or visualizer when there's no music video, and
// youtube.com's own search (the artist's channel, or their VEVO) when YouTube Music has none.

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/music.dart';
import 'package:mixtape/video.dart';

Map<String, Object?> video(String id, String title, String channel, String length, {bool artist = false}) => {
      'videoRenderer': {
        'videoId': id,
        'title': {
          'runs': [
            {'text': title},
          ],
        },
        'ownerText': {
          'runs': [
            {'text': channel},
          ],
        },
        if (artist)
          'ownerBadges': [
            {
              'metadataBadgeRenderer': {'style': 'BADGE_STYLE_TYPE_VERIFIED_ARTIST'},
            },
          ],
        'lengthText': {'simpleText': length},
        'viewCountText': {'simpleText': '12,345,678 views'},
      },
    };

void main() {
  test("youtube.com's videos, read", () {
    final items = parseWebVideos({
      'contents': {
        'twoColumnSearchResultsRenderer': {
          'primaryContents': {
            'sectionListRenderer': {
              'contents': [
                {
                  'itemSectionRenderer': {
                    'contents': [
                      video('vevo0000001', 'Kavinsky - Nightcall (Official Video)', 'KavinskyVEVO', '4:19'),
                      video('own00000001', 'Nightcall | Official Lyric Video', 'Kavinsky', '4:20', artist: true),
                      video('fan00000001', 'Nightcall (cover)', 'Some Fan', '4:00'),
                    ],
                  },
                },
              ],
            },
          },
        },
      },
    });
    expect(items.map((i) => i.id), ['vevo0000001', 'own00000001', 'fan00000001']);
    expect(items.first.artist, 'Kavinsky', reason: 'VEVO is no part of the name');
    expect(items.first.dur, 259);
    expect(items.first.views, 12345678);
    expect(items[1].official, isTrue);
    expect(items.first.official, isFalse);

    final strict = pickVideos(items, 'Nightcall', 'Kavinsky', 258);
    expect(strict.map((i) => i.id), ['vevo0000001'], reason: "the music video; not the lyric video, not a fan's cover");
    final loose = pickVideos(items.skip(1).toList(), 'Nightcall', 'Kavinsky', 258, loose: true);
    expect(loose.map((i) => i.id), ['own00000001'], reason: "with no music video, the artist's lyric video");
    expect(pickVideos(items.skip(1).toList(), 'Nightcall', 'Kavinsky', 258), isEmpty);
  });

  test('what comes after a bar is read, but is no part of the name', () {
    Item row(String id, String title) =>
        Item(kind: Kind.video, id: id, title: title, artist: 'Kavinsky', dur: 258, official: true);
    final rows = [
      row('live0000001', 'Nightcall | Live at Coachella'),
      row('mv000000001', 'Nightcall | Official Music Video'),
    ];
    expect(pickVideos(rows, 'Nightcall', 'Kavinsky', 258).map((i) => i.id), ['mv000000001']);
    expect(pickVideos(rows, 'Nightcall', 'Kavinsky', 258, loose: true).map((i) => i.id), ['mv000000001'],
        reason: 'a live take is never the video, loose or not');
  });
}
