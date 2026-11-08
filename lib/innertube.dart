/// YouTube Music straight from Dart, the way YouTube's own apps ask it (its "InnerTube" API): songs for
/// a search, where a song's audio streams from, and songs like a song. On the iPhone this is all there
/// is; on Android NewPipe's extractor does it, and this steps in when that one can't.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Why a song or a search didn't work: the same short words the Android side uses (age, region,
/// private, members, busy, gone, network, trouble).
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

  // The visionOS app's client: YouTube gives it plain audio addresses without the JavaScript puzzle the
  // web player has to solve first (yt-dlp's 'visionos' client, the same one the computer uses).
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

  // YouTube Music's search, Songs only (ytmusicapi's filter for songs)
  static const _songsOnly = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  Map<String, Object?> _remix() {
    final now = DateTime.now().toUtc();
    final day = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return {
      'client': {'clientName': 'WEB_REMIX', 'clientVersion': '1.$day.01.00', 'hl': language, 'gl': country},
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

  /// Songs on YouTube Music for a search: maps with id, title, artist, art and dur, like the Android side.
  Future<List<Map<String, Object?>>> search(String query) async {
    final data = await _post('$_music/search?prettyPrint=false',
        {'context': _remix(), 'query': query, 'params': _songsOnly}, _musicHeaders);
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (final item in _all(data, 'musicResponsiveListItemRenderer')) {
      final song = _listItem(item);
      if (song != null && seen.add('${song['id']}')) out.add(song);
    }
    return out;
  }

  /// Songs like this one: YouTube Music's radio for it (what plays after it in their app).
  Future<List<Map<String, Object?>>> related(String id) async {
    final data = await _post('$_music/next?prettyPrint=false', {
      'context': _remix(),
      'videoId': id,
      'playlistId': 'RDAMVM$id',
      'isAudioOnly': true,
      'enablePersistentPlaylistPanel': true,
      'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
    }, _musicHeaders);
    final out = <Map<String, Object?>>[];
    final seen = <String>{id};
    for (final item in _all(data, 'playlistPanelVideoRenderer')) {
      final song = _panelItem(item);
      if (song != null && seen.add('${song['id']}')) out.add(song);
    }
    return out.take(25).toList();
  }

  /// Where a song's audio streams from right now, in the same shape as the Android side's resolve: url,
  /// mime, bitrate (kbit/s), length (bytes), duration (s), agent, expires (unix s), related.
  Future<Map<String, Object?>> resolve(String id, {bool withRelated = true}) async {
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
    final status = _map(data['playabilityStatus']);
    final state = '${status['status'] ?? ''}';
    if (state != 'OK') {
      final reason = '${status['reason'] ?? ''} ${_map(status['errorScreen'])}'.toLowerCase();
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
    final streaming = _map(data['streamingData']);
    final formats = [
      for (final f in _list(streaming['adaptiveFormats']))
        if (f is Map && '${f['mimeType'] ?? ''}'.startsWith('audio/') && f['url'] is String) Map<String, Object?>.from(f),
    ];
    if (formats.isEmpty) throw InnerTubeError('trouble', 'no plain audio stream');
    int rate(Map<String, Object?> f) => _int(f['averageBitrate'] ?? f['bitrate']);
    // AAC in MP4 first: it plays on every phone (the iPhone plays nothing else)
    final aac = formats.where((f) => '${f['mimeType']}'.startsWith('audio/mp4')).toList()
      ..sort((a, b) => rate(b).compareTo(rate(a)));
    final best = aac.isNotEmpty ? aac.first : (formats..sort((a, b) => rate(b).compareTo(rate(a)))).first;
    final url = '${best['url']}';
    final details = _map(data['videoDetails']);
    final life = _int(streaming['expiresInSeconds']);
    final expires = RegExp(r'[?&]expire=(\d+)').firstMatch(url)?.group(1);
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
      'length': _int(best['contentLength'], or: -1),
      'duration': _int(details['lengthSeconds']),
      'agent': visionAgent,
      'expires': int.tryParse(expires ?? '') ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000 + (life > 0 ? life : 3600),
      'related': like,
    };
  }

  void close() => _http.close();

  // ------------------------------------------------------------ reading YouTube's answers

  /// A song row from a search: its id, title, artists, length and cover.
  Map<String, Object?>? _listItem(Map<String, Object?> item) {
    final id = _videoId(item);
    if (id == null) return null;
    final columns = _list(item['flexColumns']);
    String text(int k) => k < columns.length
        ? _runs(_map(_map(_map(columns[k])['musicResponsiveListItemFlexColumnRenderer'])['text'])).join()
        : '';
    final title = text(0);
    if (title.isEmpty) return null;
    // the second line: artists • album • 3:45 (the parts between the dots)
    final parts = text(1).split(' • ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final dur = parts.isNotEmpty && _isClock(parts.last) ? _seconds(parts.removeLast()) : 0;
    if (parts.isNotEmpty && const {'Song', 'Video', 'Episode'}.contains(parts.first)) parts.removeAt(0);
    return {
      'id': id,
      'title': title,
      'artist': parts.isNotEmpty ? parts.first : '',
      'art': _thumb(item['thumbnail']),
      'dur': dur,
    };
  }

  /// A song from a radio: id, title, artist, length and cover.
  Map<String, Object?>? _panelItem(Map<String, Object?> item) {
    final id = item['videoId'];
    if (id is! String || id.isEmpty) return null;
    final byline = _runs(_map(item['longBylineText'] ?? item['shortBylineText'])).join().split(' • ');
    final length = _runs(_map(item['lengthText'])).join();
    return {
      'id': id,
      'title': _runs(_map(item['title'])).join(),
      'artist': byline.isNotEmpty ? byline.first.trim() : '',
      'art': _thumb(item['thumbnail']),
      'dur': _isClock(length) ? _seconds(length) : 0,
    };
  }

  static String? _videoId(Map<String, Object?> item) {
    final data = _map(item['playlistItemData'])['videoId'];
    if (data is String && data.isNotEmpty) return data;
    for (final w in _all(item, 'watchEndpoint')) {
      final v = w['videoId'];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// The biggest cover in a thumbnail object, wherever in it the list of pictures is.
  static String _thumb(Object? t) {
    for (final holder in _all(_map(t), 'thumbnails', lists: true)) {
      final pics = holder['thumbnails'];
      if (pics is List && pics.isNotEmpty && pics.last is Map) return '${(pics.last as Map)['url'] ?? ''}';
    }
    final pics = _map(t)['thumbnails'];
    if (pics is List && pics.isNotEmpty && pics.last is Map) return '${(pics.last as Map)['url'] ?? ''}';
    return '';
  }

  static List<String> _runs(Map<String, Object?> text) {
    final runs = text['runs'];
    if (runs is List) {
      return [
        for (final r in runs)
          if (r is Map) '${r['text'] ?? ''}',
      ];
    }
    final simple = text['simpleText'];
    return simple is String ? [simple] : const [];
  }

  /// Every object under [key] anywhere in [node] (or with [lists], every object that has a list under
  /// [key]): YouTube moves things around, so the answers are searched instead of walked.
  static Iterable<Map<String, Object?>> _all(Object? node, String key, {bool lists = false}) sync* {
    if (node is Map) {
      final hit = node[key];
      if (lists && hit is List) {
        yield Map<String, Object?>.from(node);
      } else if (!lists && hit is Map) {
        yield Map<String, Object?>.from(hit);
      }
      for (final v in node.values) {
        if (v is Map || v is List) yield* _all(v, key, lists: lists);
      }
    } else if (node is List) {
      for (final v in node) {
        if (v is Map || v is List) yield* _all(v, key, lists: lists);
      }
    }
  }

  static Map<String, Object?> _map(Object? v) => v is Map ? Map<String, Object?>.from(v) : const {};

  static List<Object?> _list(Object? v) => v is List ? v : const [];

  static int _int(Object? v, {int or = 0}) => v is int ? v : (int.tryParse('${v ?? ''}') ?? or);

  static bool _isClock(String s) => RegExp(r'^\d{1,2}(:\d{2}){1,2}$').hasMatch(s.trim());

  static int _seconds(String s) => s.trim().split(':').fold(0, (sum, part) => sum * 60 + (int.tryParse(part) ?? 0));
}
