/// Video mode: the artist's music video for the song that plays, found and lined up the way the computer
/// does it (ytm.music_videos and video.py there). The song plays as always; its video plays along without
/// sound and follows it (ui/video_view.dart).
library;

import 'dart:io';

import 'package:mixtape_native/mixtape_native.dart';

import 'heat.dart';
import 'innertube.dart';
import 'jsonwalk.dart';
import 'model.dart';
import 'music.dart';
import 'youtube.dart';

/// A song's music video and where the song starts in it.
class MusicVideo {
  const MusicVideo(this.id, this.length, this.lead);

  final String id;
  final int length;

  /// Seconds of video before the song starts (its intro).
  final int lead;
}

const fit = 30; // seconds longer a video may be and be taken to have an intro that long
const longest = 150; // seconds longer it may be when the curves tell where the song is in it
const short = 4; // and seconds shorter

// Words that make a video something else than the song's music video: a lyric video, a live take, a
// cover. A song whose own title has the word (a live album, a remix) may still match on it.
final _notTheVideo = RegExp(
    r'\b(lyrics?|audio|visuali[sz]er|live|karaoke|cover|remix|sped|slowed|nightcore|8d|instrumental|reaction|'
    r'concert|tiny desk|performance|acoustic|extended|mash ?up|piano|tutorial|legendado|tradu[cç][aã]o|'
    r'sub espa[nñ]ol|letra|reverb|loop|hour)\b',
    caseSensitive: false);
final _hasFeat = RegExp(r'\b(feat|ft|featuring)\b', caseSensitive: false);
final _saysVideo = RegExp(r'official (music )?video|music video|\bmv\b', caseSensitive: false);

/// A title or a name for comparing: without bracketed bits, featured artists and "- Remastered".
String plainName(String text) {
  final t = text
      .replaceAll(RegExp(r'[\(\[][^\)\]]*[\)\]]'), '')
      .replaceAll(RegExp(r'\s+(feat\.?|ft\.?|featuring|with)\s.*$', caseSensitive: false), '')
      .replaceAll(
          RegExp(r'\s+-\s+(remaster(ed)?|live|radio edit|single version|mono|stereo|\d{4} remaster|from\s|original mix|'
              r'bonus track|album version).*$',
              caseSensitive: false),
          '');
  return folded(t);
}

Set<String> _words(String s) => {for (final m in _notTheVideo.allMatches(s)) m.group(1)!.toLowerCase()};

/// The song's official music videos among YouTube Music's videos for it, best first: the artist's own
/// (no lyric video, live take or cover) with the song's name, at most [longer] seconds longer than the
/// song. The same version comes first (no extra "feat."), then one that calls itself the official
/// video, then the most watched.
///
/// With [loose], the artist's lyric videos and visualizers count too: the same recording with something
/// to watch, for songs that have no video of their own.
List<Item> pickVideos(List<Item> rows, String title, String artist, int dur, {int longer = longest, bool loose = false}) {
  final name = plainName(title);
  final who = plainName(artist.split(',').first);
  if (name.isEmpty || who.isEmpty) return const [];
  final own = {..._words(title), if (loose) ...const {'lyric', 'lyrics', 'visualizer', 'visualiser'}};
  final found = <(bool, bool, double, Item)>[];
  for (final r in rows) {
    if (r.kind != Kind.video && r.kind != Kind.song) continue;
    final people = r.artist.split(',').map(plainName).where((p) => p.isNotEmpty).toList();
    if (!(r.official || people.contains(who)) || !people.any((p) => ' $p '.contains(' $who '))) continue;
    var shown = r.title;
    final dash = shown.indexOf(' - ');
    if (dash > 0 && plainName(shown.substring(0, dash)).contains(who)) shown = shown.substring(dash + 3);
    final words = _words(shown);
    final same = _hasFeat.hasMatch(shown) == _hasFeat.hasMatch(title);
    final said = _saysVideo.hasMatch(shown);
    // "Song | Official Music Video": what comes after the bar is no part of the name
    final bar = shown.indexOf(' | ');
    if (bar > 0 && !title.contains(' | ')) shown = shown.substring(0, bar);
    if (plainName(shown) != name || words.difference(own).isNotEmpty) continue;
    if (dur > 0 && r.dur > 0 && (r.dur - dur < -short || r.dur - dur > longer)) continue;
    found.add((same, said, r.views, r));
  }
  found.sort((a, b) {
    if (a.$1 != b.$1) return a.$1 ? -1 : 1;
    if (a.$2 != b.$2) return a.$2 ? -1 : 1;
    return b.$3.compareTo(a.$3);
  });
  return [for (final f in found) f.$4];
}

class Videos {
  static final _found = <String, MusicVideo?>{};
  static final _looking = <String, Future<MusicVideo?>>{};
  static final _heat = <String, Heat>{};
  static final _streams = <String, (String, String, DateTime)>{};
  static final _opening = <String, Future<(String, String)>>{};

  /// A song's music video, or null when it has none that goes with it. Looked up once per song (two
  /// asking at once share the one look).
  static Future<MusicVideo?> find(Track t) {
    if (_found.containsKey(t.id)) return Future.value(_found[t.id]);
    return _looking[t.id] ??= _look(t).whenComplete(() => _looking.remove(t.id));
  }

  /// Video mode: the videos of these songs (the one that starts, and the next) looked up ahead, so the
  /// player has the picture at once. One that can't be found now is tried again when the player shows.
  static Future<void> prepare(Iterable<Track> songs) async {
    for (final t in songs) {
      if (t.src != 'yt') continue;
      try {
        final v = await find(t);
        if (v != null) await stream(v.id);
      } on Object {
        // the player tries again
      }
    }
  }

  /// The videos that could go with a song, best first: its official music video on YouTube Music, else
  /// the artist's lyric video or visualizer there, else the same from youtube.com itself (the artist's own
  /// channel, or their VEVO), where more videos are than YouTube Music shows.
  static Future<List<Item>> _candidates(Track t) async {
    final artist = t.artist.split(',').first.trim();
    final query = '${t.title} $artist';
    final music = (await Music.search(query, filter: 'videos')).items;
    for (final loose in [false, true]) {
      final picked = pickVideos(music, t.title, t.artist, t.dur, loose: loose);
      if (picked.isNotEmpty) return picked;
    }
    List<Item> web;
    try {
      web = await Music.webVideos('$artist ${t.title}');
    } on Object {
      return const [];
    }
    for (final loose in [false, true]) {
      final picked = pickVideos(web, t.title, t.artist, t.dur, loose: loose);
      if (picked.isNotEmpty) return picked;
    }
    return const [];
  }

  static Future<MusicVideo?> _look(Track t) async {
    MusicVideo? got;
    if (t.src == 'yt') {
      var dur = t.dur;
      for (final v in (await _candidates(t)).take(3)) {
        if (dur <= 0) dur = v.dur; // (a song whose length isn't known yet: no way to check)
        final extra = v.dur > 0 && dur > 0 ? v.dur - dur : 0;
        int? lead;
        if (dur > 0 && v.dur > 0) {
          lead = lineUp(await _curve(t.ref), await _curve(v.id), dur.toDouble(), v.dur.toDouble());
        }
        if (lead == null) {
          if (extra > fit) continue; // too much longer to guess where the song is in it
          lead = extra < 0 ? 0 : extra;
        }
        got = MusicVideo(v.id, v.dur, lead < 0 ? 0 : lead);
        break;
      }
    }
    _found[t.id] = got;
    while (_found.length > 60) {
      _found.remove(_found.keys.first);
    }
    return got;
  }

  static Future<Heat> _curve(String id) async {
    final have = _heat[id];
    if (have != null) return have;
    try {
      final h = await YouTube.inner.mostReplayed(id);
      _heat[id] = h;
      while (_heat.length > 80) {
        _heat.remove(_heat.keys.first);
      }
      return h;
    } on InnerTubeError {
      return const [];
    }
  }

  /// The "most replayed" curve of a song (Samples starts each song at its best part with it).
  static Future<Heat> curve(String id) => _curve(id);

  /// Where a video's picture streams from: (address, user agent). An address holds for a few hours, so
  /// one found in the last hour is used again.
  static Future<(String, String)> stream(String id) {
    final have = _streams[id];
    if (have != null && DateTime.now().difference(have.$3) < const Duration(hours: 1)) {
      return Future.value((have.$1, have.$2));
    }
    return _opening[id] ??= _open(id).whenComplete(() => _opening.remove(id));
  }

  static Future<(String, String)> _open(String id) async {
    final got = await _streamInfo(id);
    final url = '${got['url'] ?? ''}', agent = '${got['agent'] ?? ''}';
    if (url.isNotEmpty) {
      _streams[id] = (url, agent, DateTime.now());
      while (_streams.length > 20) {
        _streams.remove(_streams.keys.first);
      }
    }
    return (url, agent);
  }

  static Future<Map<String, Object?>> _streamInfo(String id) async {
    if (Platform.isAndroid) {
      try {
        return await MixtapeNative.video(id);
      } on YouTubeError {
        // NewPipe couldn't: InnerTube may
      }
    }
    try {
      return await YouTube.inner.video(id);
    } on InnerTubeError catch (e) {
      throw YouTubeError(e.why, e.detail);
    }
  }
}
