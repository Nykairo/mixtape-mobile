/// ListenBrainz and Last.fm, the way the computer uses them (core.scrobble and together.py there):
/// what you listen to goes to your ListenBrainz profile, and you can listen along with people who use
/// Spotify, YouTube Music or anything else that sends their music to ListenBrainz or Last.fm.
///
/// Besides the title and the artist, Mixtape sends the YouTube link and when the song started, so a
/// friend who listens along gets the same recording at the same second.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'model.dart';
import 'settings.dart';

/// What somebody plays on ListenBrainz or Last.fm: the song as their player called it, the YouTube
/// video when their player said it (Mixtape does), and when it started (0 when unknown).
typedef OutsideSong = ({String title, String artist, int dur, String video, double started});

class ScrobbleTrouble implements Exception {
  const ScrobbleTrouble(this.why);

  final String why;

  @override
  String toString() => why;
}

class Scrobbler {
  Scrobbler(this.settings, {this.version = ''});

  final Settings settings;
  final String version;
  static final _client = http.Client();
  static const _api = 'https://api.listenbrainz.org/1';

  bool get on => settings.listenBrainzToken.isNotEmpty;

  /// Your ListenBrainz name for a token, or a ScrobbleTrouble saying what's wrong with it.
  static Future<String> check(String token) async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$_api/validate-token'), headers: {'Authorization': 'Token ${token.trim()}'})
          .timeout(const Duration(seconds: 12));
    } on Object {
      throw const ScrobbleTrouble("Couldn't reach ListenBrainz. Check the internet connection.");
    }
    final j = res.statusCode == 200 ? jsonDecode(res.body) : null;
    if (j is Map && j['valid'] == true && '${j['user_name'] ?? ''}'.isNotEmpty) return '${j['user_name']}';
    throw const ScrobbleTrouble("ListenBrainz doesn't know that token. Copy it again from listenbrainz.org/settings.");
  }

  /// A song started (at [pos] seconds into it): friends on ListenBrainz see it as playing now.
  void playingNow(Track t, {double pos = 0}) => _send('playing_now', t, pos: pos);

  /// A song that was heard long enough counts as a listen: half of it, or four minutes.
  void heard(Track t, int seconds, DateTime started) {
    if (seconds < 30 || (t.dur > 0 && seconds < (t.dur / 2).clamp(30, 240))) return;
    _send('single', t, at: started.millisecondsSinceEpoch ~/ 1000);
  }

  void _send(String kind, Track t, {int at = 0, double pos = 0}) {
    final token = settings.listenBrainzToken;
    if (token.isEmpty || t.title.isEmpty || t.src == 'local') return;
    final info = <String, Object?>{
      'submission_client': 'Mixtape',
      'submission_client_version': version,
      'media_player': 'Mixtape',
      if (t.dur > 0) 'duration_ms': t.dur * 1000,
      if (t.src == 'yt') 'origin_url': 'https://music.youtube.com/watch?v=${t.ref}',
      if (t.src == 'yt') 'music_service': 'youtube.com',
      if (kind == 'playing_now') 'mixtape_started': DateTime.now().millisecondsSinceEpoch ~/ 1000 - pos.round(),
    };
    final meta = <String, Object?>{
      'artist_name': t.artist.isEmpty ? 'unknown' : t.artist,
      'track_name': t.title,
      if (t.album.isNotEmpty) 'release_name': t.album,
      'additional_info': info,
    };
    final body = jsonEncode({
      'listen_type': kind,
      'payload': [
        {if (at > 0) 'listened_at': at, 'track_metadata': meta},
      ],
    });
    _client
        .post(Uri.parse('$_api/submit-listens'),
            headers: {'Authorization': 'Token $token', 'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 15))
        .then((_) {}, onError: (Object _) {}); // a listen that doesn't arrive is no reason to bother anyone
  }

  // ------------------------------------------------------------ what somebody plays elsewhere

  /// What [user] plays right now on ListenBrainz, or null when nothing.
  static Future<OutsideSong?> listenBrainzNow(String user) async {
    final res = await _client
        .get(Uri.parse('$_api/user/${Uri.encodeComponent(user)}/playing-now'))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode == 404) throw const ScrobbleTrouble('Nobody on ListenBrainz has that name.');
    if (res.statusCode != 200) throw ScrobbleTrouble('ListenBrainz said no (error ${res.statusCode}).');
    final j = jsonDecode(res.body);
    final listens = j is Map && j['payload'] is Map ? (j['payload'] as Map)['listens'] : null;
    if (listens is! List || listens.isEmpty || listens.first is! Map) return null;
    return outsideFromListenBrainz(Map<String, Object?>.from(listens.first as Map));
  }

  /// A playing-now listen as a song: the video from the YouTube link when the player sent one.
  static OutsideSong outsideFromListenBrainz(Map<String, Object?> listen) {
    final meta = listen['track_metadata'] is Map ? listen['track_metadata'] as Map : const {};
    final info = meta['additional_info'] is Map ? meta['additional_info'] as Map : const {};
    final url = '${info['origin_url'] ?? info['youtube_id'] ?? ''}';
    final video = RegExp(r'(?:v=|youtu\.be/|^)([\w-]{11})(?:$|[&?#])').firstMatch(url)?.group(1) ?? '';
    final ms = info['duration_ms'] is num ? (info['duration_ms'] as num).toInt() : 0;
    final secs = info['duration'] is num ? (info['duration'] as num).toInt() : 0;
    final started = info['mixtape_started'] is num ? (info['mixtape_started'] as num).toDouble() : 0.0;
    return (
      title: '${meta['track_name'] ?? ''}',
      artist: '${meta['artist_name'] ?? ''}',
      dur: ms > 0 ? ms ~/ 1000 : secs,
      video: video,
      started: started,
    );
  }

  /// What [user] plays right now on Last.fm (with an API key from last.fm/api), or null.
  static Future<OutsideSong?> lastFmNow(String user, String key) async {
    if (key.isEmpty) throw const ScrobbleTrouble('Last.fm needs an API key first: Settings, Listen along.');
    final url = Uri.https('ws.audioscrobbler.com', '/2.0/', {
      'method': 'user.getrecenttracks',
      'user': user,
      'api_key': key,
      'format': 'json',
      'limit': '1',
    });
    final res = await _client.get(url).timeout(const Duration(seconds: 12));
    final j = jsonDecode(res.body);
    if (j is Map && j['error'] != null) {
      throw ScrobbleTrouble(j['error'] == 6 ? 'Nobody on Last.fm has that name.' : 'Last.fm said: ${j['message'] ?? 'no'}');
    }
    final tracks = j is Map && j['recenttracks'] is Map ? (j['recenttracks'] as Map)['track'] : null;
    final first = tracks is List && tracks.isNotEmpty ? tracks.first : tracks;
    if (first is! Map) return null;
    final attr = first['@attr'];
    if (attr is! Map || attr['nowplaying'] != 'true') return null; // their last song, not one that plays
    final artist = first['artist'] is Map ? '${(first['artist'] as Map)['#text'] ?? ''}' : '';
    return (title: '${first['name'] ?? ''}', artist: artist, dur: 0, video: '', started: 0.0);
  }
}
