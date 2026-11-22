// A radio plays songs: the song next to a music video instead of the video, and no uploads of other
// people or podcast episodes (only the one the radio started from stays, whatever it is).

import 'package:flutter_test/flutter_test.dart';
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
}
