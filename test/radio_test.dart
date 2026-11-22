// A radio plays songs: the song next to a music video instead of the video, and no uploads of other
// people or podcast episodes (only the one the radio started from stays, whatever it is).

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/innertube.dart';
import 'package:mixtape/music.dart';

Map<String, Object?> panel(String id, String title, String type) => {
      'videoId': id,
      'title': {
        'runs': [
          {'text': title},
        ],
      },
      'longBylineText': {
        'runs': [
          {'text': 'Daft Punk'},
        ],
      },
      'lengthText': {
        'runs': [
          {'text': '3:45'},
        ],
      },
      'navigationEndpoint': {
        'watchEndpoint': {
          'videoId': id,
          'watchEndpointMusicSupportedConfigs': {
            'watchEndpointMusicConfig': {'musicVideoType': type},
          },
        },
      },
    };

void main() {
  test('songs instead of videos, and no uploads or episodes', () {
    final data = {
      'contents': {
        'playlistPanelRenderer': {
          'contents': [
            {'playlistPanelVideoRenderer': panel('seedUGC0001', 'The seed', 'MUSIC_VIDEO_TYPE_UGC')},
            {
              'playlistPanelVideoWrapperRenderer': {
                'primaryRenderer': {
                  'playlistPanelVideoRenderer': panel('omv00000001', 'Get Lucky (Official Video)', 'MUSIC_VIDEO_TYPE_OMV'),
                },
                'counterpart': [
                  {
                    'counterpartRenderer': {
                      'playlistPanelVideoRenderer': panel('atv00000001', 'Get Lucky', 'MUSIC_VIDEO_TYPE_ATV'),
                    },
                  },
                ],
              },
            },
            {'playlistPanelVideoRenderer': panel('ugc00000001', 'Get Lucky (cover)', 'MUSIC_VIDEO_TYPE_UGC')},
            {'playlistPanelVideoRenderer': panel('pod00000001', 'An episode', 'MUSIC_VIDEO_TYPE_PODCAST_EPISODE')},
            {'playlistPanelVideoRenderer': panel('omv00000002', 'One More Time', 'MUSIC_VIDEO_TYPE_OMV')},
            {'playlistPanelVideoRenderer': panel('atv00000002', 'Around the World', 'MUSIC_VIDEO_TYPE_ATV')},
          ],
        },
      },
    };
    final ids = [for (final t in parseNext(data, 'seedUGC0001').songs) t.ref];
    expect(ids, ['seedUGC0001', 'atv00000001', 'omv00000002', 'atv00000002']);
  });

  test('songs to go on with when the queue runs out: the radio without the song itself', () {
    Map<String, Object?> wrapped(String video, String song) => {
          'playlistPanelVideoWrapperRenderer': {
            'primaryRenderer': {'playlistPanelVideoRenderer': panel(video, 'A video', 'MUSIC_VIDEO_TYPE_OMV')},
            'counterpart': [
              {
                'counterpartRenderer': {'playlistPanelVideoRenderer': panel(song, 'A song', 'MUSIC_VIDEO_TYPE_ATV')},
              },
            ],
          },
        };
    final data = {
      'contents': {
        'playlistPanelRenderer': {
          'contents': [
            wrapped('omvseed0001', 'atvseed0001'),
            wrapped('omv00000003', 'atv00000003'),
            {'playlistPanelVideoRenderer': panel('ugc00000002', 'A fan upload', 'MUSIC_VIDEO_TYPE_UGC')},
            {'playlistPanelVideoRenderer': panel('atv00000004', 'Another song', 'MUSIC_VIDEO_TYPE_ATV')},
          ],
        },
      },
    };
    String id(Map<String, Object?> m) => '${m['videoId']}';
    expect(radioItems(data, 'omvseed0001', withSeed: false).map(id), ['atv00000003', 'atv00000004'],
        reason: 'neither the video that played nor its song comes again');
    expect(radioItems(data, 'atvseed0001', withSeed: false).map(id), ['atv00000003', 'atv00000004']);
    expect(radioItems(data, 'omvseed0001').map(id), ['atvseed0001', 'atv00000003', 'atv00000004']);
  });
}
