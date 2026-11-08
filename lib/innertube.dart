/// YouTube Music straight from Dart, the way YouTube's own apps ask it (its "InnerTube" API): searches,
/// artists, albums, playlists, the home page, radios, lyrics, the "most replayed" curve and where a song
/// or a video streams from. On the iPhone this is all there is; on Android NewPipe's extractor finds the
/// streams, and this does the rest. What the answers mean is read in music.dart.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'jsonwalk.dart';

/// Why something didn't work: the same short words the Android side uses (age, region, private,
/// members, busy, gone, network, trouble).
class InnerTubeError implements Exception {
  InnerTubeError(this.why, [this.detail = '']);

  final String why;
  final String detail;

  @override
  String toString() => 'InnerTubeError($why: $detail)';
}

class InnerTube {
  InnerTube({http.Client? client, this.language = 'en', this.country = 'US'}) : _http = client ?? http.Client();

  final http.Client _http;
  final String language;
  final String country;

  static const _music = 'https://music.youtube.com/youtubei/v1';
  static const _web = 'https://www.youtube.com/youtubei/v1';
  static const _browserAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/18.5 Safari/605.1.15';

  // The visionOS app's client: YouTube gives it plain addresses without the JavaScript puzzle the web
  // player has to solve first (yt-dlp's 'visionos' client, the same one the computer uses).
  static const visionAgent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';
  static const _vision = {
    'clientName': 'VISIONOS',
    'clientVersion': '1.02',
    'deviceMake': 'Apple',
    'deviceModel': 'RealityDevice17,1',
    'userAgent': visionAgent,
    'osName': 'visionOS',
    'osVersion': '26.5.23O471',
  };

  /// YouTube Music's search filters (the chips over its results).
  static const filters = {
    'songs': 'EgWKAQIIAWoMEA4QChADEAQQCRAF',
    'videos': 'EgWKAQIQAWoMEA4QChADEAQQCRAF',
    'albums': 'EgWKAQIYAWoMEA4QChADEAQQCRAF',
    'artists': 'EgWKAQIgAWoMEA4QChADEAQQCRAF',
    'playlists': 'Eg-KAQwIABAAGAAgACgBMABqChAEEAMQCRAFEAo%3D',
  };

  Map<String, Object?> _remix({bool mobile = false}) {
    final now = DateTime.now().toUtc();
    final day = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    // the Android app's client is the one YouTube hands timed lyrics to
    final client = mobile
        ? {'clientName': 'ANDROID_MUSIC', 'clientVersion': '7.21.50'}
        : {'clientName': 'WEB_REMIX', 'clientVersion': '1.$day.01.00'};
    return {
      'client': {...client, 'hl': language, 'gl': country},
    };
  }

  Future<Map<String, Object?>> _post(String url, Map<String, Object?> body, Map<String, String> headers) async {
    try {
      final res = await _http
          .post(Uri.parse(url), headers: {'Content-Type': 'application/json', ...headers}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 429) throw InnerTubeError('busy', 'HTTP 429');
      if (res.statusCode != 200) throw InnerTubeError('trouble', 'HTTP ${res.statusCode}');
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is! Map) throw InnerTubeError('trouble', 'not JSON');
      return Map<String, Object?>.from(data);
    } on TimeoutException {
      throw InnerTubeError('network', 'timed out');
    } on http.ClientException catch (e) {
      throw InnerTubeError('network', e.message);
    } on IOException catch (e) {
      throw InnerTubeError('network', '$e');
    } on FormatException catch (e) {
      throw InnerTubeError('trouble', e.message);
    }
  }

  Map<String, String> get _musicHeaders =>
      {'User-Agent': _browserAgent, 'Origin': 'https://music.youtube.com', 'Referer': 'https://music.youtube.com/'};

  // ------------------------------------------------------------ YouTube Music's own pages

  /// A search, all kinds of results or one [filter] (see [filters]); [more] continues an earlier one.
  Future<Map<String, Object?>> searchRaw(String query, {String filter = '', String more = ''}) {
    final params = filters[filter];
    final tail = more.isEmpty ? '' : '&ctoken=$more&continuation=$more';
    return _post('$_music/search?prettyPrint=false$tail',
        {'context': _remix(), 'query': query, if (params != null) 'params': params}, _musicHeaders);
  }

  /// What the search box offers while typing.
  Future<Map<String, Object?>> suggestRaw(String input) =>
      _post('$_music/music/get_search_suggestions?prettyPrint=false', {'context': _remix(), 'input': input}, _musicHeaders);

  /// A page by its id: an artist (UC...), an album (MPREb...), a playlist (VL...), the home page
  /// (FEmusic_home), moods (FEmusic_moods_and_genres), lyrics (MPLYt...). [more] continues a long list.
  Future<Map<String, Object?>> browseRaw(String id, {String params = '', String more = '', bool mobile = false}) =>
      _post('$_music/browse?prettyPrint=false', {
        'context': _remix(mobile: mobile),
        if (more.isNotEmpty) 'continuation': more else 'browseId': id,
        if (params.isNotEmpty && more.isEmpty) 'params': params,
      }, _musicHeaders);

  /// What YouTube Music plays after a song (its radio), with the ids of its lyrics and related pages.
  Future<Map<String, Object?>> nextRaw(String videoId, {String playlist = '', String params = ''}) =>
      _post('$_music/next?prettyPrint=false', {
        'context': _remix(),
        'videoId': videoId,
        'playlistId': playlist.isEmpty ? 'RDAMVM$videoId' : playlist,
        if (params.isNotEmpty) 'params': params,
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
      }, _musicHeaders);

  /// The "most replayed" curve under a video on youtube.com: (start, length, how much, 0 to 1), in
  /// seconds. Empty when the video has none (too few views).
  Future<List<(double, double, double)>> mostReplayed(String videoId) async {
    final data = await _post('$_web/next?prettyPrint=false', {
      'context': {
        'client': {'clientName': 'WEB', 'clientVersion': '2.20251105.01.00', 'hl': language, 'gl': country},
      },
      'videoId': videoId,
    }, {
      'User-Agent': _browserAgent,
      'Origin': 'https://www.youtube.com',
    });
    return heatOf(data);
  }

  /// The curve in a youtube.com "next" answer (see [mostReplayed]).
  static List<(double, double, double)> heatOf(Map<String, Object?> data) {
    for (final e in findAll(data, 'macroMarkersListEntity')) {
      final list = asMap(e['markersList']);
      if (list['markerType'] != 'MARKER_TYPE_HEATMAP') continue;
      return [
        for (final m in asList(list['markers']))
          if (m is Map)
            (
              toInt(m['startMillis']) / 1000,
              toInt(m['durationMillis']) / 1000,
              (m['intensityScoreNormalized'] is num ? (m['intensityScoreNormalized'] as num).toDouble() : 0.0),
            ),
      ];
    }
    return const [];
  }

  // ------------------------------------------------------------ for the YouTube facade (youtube.dart)

  /// Songs on YouTube Music for a search: maps with id, title, artist, art and dur, like the Android side.
  Future<List<Map<String, Object?>>> search(String query) async {
    final data = await searchRaw(query, filter: 'songs');
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final item in findAll(data, 'musicResponsiveListItemRenderer')) {
      final song = _listItem(item);
      if (song != null && seen.add('${song['id']}')) out.add(song);
    }
    return out;
  }

  /// Songs like this one: YouTube Music's radio for it (what plays after it in their app).
  Future<List<Map<String, Object?>>> related(String id) async {
    final data = await nextRaw(id);
    final out = <Map<String, Object?>>[];
    final seen = <String>{id};
    for (final item in findAll(data, 'playlistPanelVideoRenderer')) {
      final song = panelItem(item);
      if (song != null && seen.add('${song['id']}')) out.add(song);
    }
    return out.take(25).toList();
  }

  Future<Map<String, Object?>> _player(String id) async {
    final data = await _post('$_web/player?prettyPrint=false', {
      'context': {
        'client': {..._vision, 'hl': language, 'gl': country, 'timeZone': 'UTC', 'utcOffsetMinutes': 0},
      },
      'videoId': id,
      'contentCheckOk': true,
      'racyCheckOk': true,
      'playbackContext': {
        'contentPlaybackContext': {'html5Preference': 'HTML5_PREF_WANTS'},
      },
    }, {
      'User-Agent': visionAgent,
      'X-YouTube-Client-Name': '101',
      'X-YouTube-Client-Version': '1.02',
      'Origin': 'https://www.youtube.com',
    });
    final status = asMap(data['playabilityStatus']);
    final state = '${status['status'] ?? ''}';
    if (state != 'OK') {
      final reason = '${status['reason'] ?? ''} ${asMap(status['errorScreen'])}'.toLowerCase();
      if (reason.contains('confirm your age') || reason.contains('age-restricted') || reason.contains('inappropriate')) {
        throw InnerTubeError('age', state);
      }
      if (reason.contains('not a bot') || reason.contains('sign in to confirm')) throw InnerTubeError('busy', state);
      if (reason.contains('country')) throw InnerTubeError('region', state);
      if (reason.contains('private')) throw InnerTubeError('private', state);
      if (reason.contains('members')) throw InnerTubeError('members', state);
      if (state == 'ERROR' || reason.contains('unavailable') || reason.contains('removed')) {
        throw InnerTubeError('gone', state);
      }
      throw InnerTubeError('trouble', '$state $reason'.trim());
    }
    return data;
  }

  /// Where a song's audio streams from right now, in the same shape as the Android side's resolve: url,
  /// mime, bitrate (kbit/s), length (bytes), duration (s), agent, expires (unix s), related.
  Future<Map<String, Object?>> resolve(String id, {bool withRelated = true}) async {
    final data = await _player(id);
    final streaming = asMap(data['streamingData']);
    final formats = [
      for (final f in asList(streaming['adaptiveFormats']))
        if (f is Map && '${f['mimeType'] ?? ''}'.startsWith('audio/') && f['url'] is String) Map<String, Object?>.from(f),
    ];
    if (formats.isEmpty) throw InnerTubeError('trouble', 'no plain audio stream');
    int rate(Map<String, Object?> f) => toInt(f['averageBitrate'] ?? f['bitrate']);
    // AAC in MP4 first: it plays on every phone (the iPhone plays nothing else)
    final aac = formats.where((f) => '${f['mimeType']}'.startsWith('audio/mp4')).toList()
      ..sort((a, b) => rate(b).compareTo(rate(a)));
    final best = aac.isNotEmpty ? aac.first : (formats..sort((a, b) => rate(b).compareTo(rate(a)))).first;
    final url = '${best['url']}';
    final details = asMap(data['videoDetails']);
    List<Map<String, Object?>> like = const [];
    if (withRelated) {
      try {
        like = await related(id);
      } on InnerTubeError {
        like = const []; // the song plays all the same
      }
    }
    return {
      'url': url,
      'mime': '${best['mimeType']}'.split(';').first,
      'bitrate': rate(best) ~/ 1000,
      'length': toInt(best['contentLength'], or: -1),
      'duration': toInt(details['lengthSeconds']),
      'agent': visionAgent,
      'expires': _expires(url, toInt(streaming['expiresInSeconds'])),
      'related': like,
    };
  }

  /// A music video's picture for video mode: the best video-only stream up to 480 lines, H.264 first.
  Future<Map<String, Object?>> video(String id) async {
    final data = await _player(id);
    final streaming = asMap(data['streamingData']);
    final formats = [
      for (final f in asList(streaming['adaptiveFormats']))
        if (f is Map && '${f['mimeType'] ?? ''}'.startsWith('video/mp4') && f['url'] is String && toInt(f['height']) <= 480)
          Map<String, Object?>.from(f),
    ]..sort((a, b) {
        final avc = ('${b['mimeType']}'.contains('avc1') ? 1 : 0) - ('${a['mimeType']}'.contains('avc1') ? 1 : 0);
        return avc != 0 ? avc : toInt(b['height']).compareTo(toInt(a['height']));
      });
    if (formats.isEmpty) throw InnerTubeError('trouble', 'no plain video stream');
    final best = formats.first;
    return {
      'url': '${best['url']}',
      'height': toInt(best['height']),
      'duration': toInt(asMap(data['videoDetails'])['lengthSeconds']),
      'agent': visionAgent,
    };
  }

  static int _expires(String url, int life) =>
      int.tryParse(RegExp(r'[?&]expire=(\d+)').firstMatch(url)?.group(1) ?? '') ??
      DateTime.now().millisecondsSinceEpoch ~/ 1000 + (life > 0 ? life : 3600);

  void close() => _http.close();

  // ------------------------------------------------------------ rows the facade hands on as maps

  /// A song row from a search: its id, title, artists, length and cover.
  static Map<String, Object?>? _listItem(Map<String, Object?> item) {
    final id = _videoId(item);
    if (id == null) return null;
    final columns = asList(item['flexColumns']);
    String text(int k) =>
        k < columns.length ? textOf(asMap(asMap(columns[k])['musicResponsiveListItemFlexColumnRenderer'])['text']) : '';
    final title = text(0);
    if (title.isEmpty) return null;
    // the second line: artists • album • 3:45 (the parts between the dots)
    final parts = text(1).split(' • ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final dur = parts.isNotEmpty && isClock(parts.last) ? clockSeconds(parts.removeLast()) : 0;
    if (parts.isNotEmpty && const {'Song', 'Video', 'Episode'}.contains(parts.first)) parts.removeAt(0);
    return {
      'id': id,
      'title': title,
      'artist': parts.isNotEmpty ? parts.first : '',
      'art': thumbOf(item['thumbnail']),
      'dur': dur,
    };
  }

  /// A song from a radio: id, title, artist, length and cover.
  static Map<String, Object?>? panelItem(Map<String, Object?> item) {
    final id = item['videoId'];
    if (id is! String || id.isEmpty) return null;
    final byline = textOf(item['longBylineText'] ?? item['shortBylineText']).split(' • ');
    final length = textOf(item['lengthText']);
    return {
      'id': id,
      'title': textOf(item['title']),
      'artist': byline.isNotEmpty ? byline.first.trim() : '',
      'art': thumbOf(item['thumbnail']),
      'dur': isClock(length) ? clockSeconds(length) : 0,
    };
  }

  static String? _videoId(Map<String, Object?> item) {
    final data = asMap(item['playlistItemData'])['videoId'];
    if (data is String && data.isNotEmpty) return data;
    for (final w in findAll(item, 'watchEndpoint')) {
      final v = w['videoId'];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }
}
