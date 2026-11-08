/// Songs and tapes, in the same shape the desktop Mixtape keeps them, so a tape from the Mixtape Account
/// reads the same here as on the computer.
library;

import 'dart:convert';
import 'dart:typed_data';

/// A song. [id] is the source plus its reference ('yt' + the YouTube video id), [ref] the reference
/// alone, [dur] its length in seconds. Songs from YouTube and podcast episodes (their [ref] is the
/// episode's own address) play here; songs from a computer's music folder and SoundCloud only show.
class Track {
  const Track({
    required this.src,
    required this.ref,
    required this.title,
    this.artist = '',
    this.art = '',
    this.dur = 0,
    this.extra = const {},
  });

  final String src;
  final String ref;
  final String title;
  final String artist;
  final String art;
  final int dur;

  /// What else the computer wrote down about the song (album, album_id, artist_id...). It is kept as it
  /// came, so a tape changed on the phone goes back to the account with all of it.
  final Map<String, Object?> extra;

  String get id => '$src$ref';

  bool get playable => src == 'yt' || (src == 'pod' && ref.startsWith('http'));

  String get album => '${extra['album'] ?? ''}';

  /// A song as YouTube search gives it (see MixtapeNative.search).
  factory Track.fromYouTube(Map<String, Object?> m) => Track(
        src: 'yt',
        ref: '${m['id'] ?? ''}',
        title: '${m['title'] ?? ''}',
        artist: '${m['artist'] ?? ''}',
        art: '${m['art'] ?? ''}',
        dur: _int(m['dur']),
      );

  /// A song as the desktop Mixtape (and the account) writes it, or null when it isn't one.
  static Track? fromJson(Object? j) {
    if (j is! Map) return null;
    final src = j['src'];
    final ref = j['ref'];
    if (src is! String || ref == null || '$ref'.isEmpty) return null;
    final extra = <String, Object?>{};
    j.forEach((k, v) {
      if (!_own.contains(k)) extra['$k'] = v;
    });
    return Track(
      src: src,
      ref: '$ref',
      title: '${j['title'] ?? ''}',
      artist: '${j['artist'] ?? ''}',
      art: '${j['art'] ?? ''}',
      dur: _int(j['dur']),
      extra: extra,
    );
  }

  static const _own = {'id', 'src', 'ref', 'title', 'artist', 'art', 'dur'};

  Map<String, Object?> toJson() =>
      {...extra, 'id': id, 'src': src, 'ref': ref, 'title': title, 'artist': artist, 'art': art, 'dur': dur};

  /// The cover at a size that suits the phone: YouTube Music's pictures come in any size asked for.
  String artAt(int px) {
    if (art.contains('googleusercontent.com') && RegExp(r'=w\d+-h\d+').hasMatch(art)) {
      return art.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w$px-h$px');
    }
    if (src == 'yt' && art.isEmpty) return 'https://i.ytimg.com/vi/$ref/${px > 200 ? 'hq' : 'mq'}default.jpg';
    return art;
  }

  @override
  bool operator ==(Object other) => other is Track && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A tape: its songs, the sticky note, the label paper and the decorations (see Cassette for those).
class Tape {
  Tape({required this.name, List<Track>? songs, this.note = '', this.paper, this.design, Map<String, Object?>? extra})
      : songs = songs ?? [],
        extra = extra ?? {};

  final String name;
  List<Track> songs;
  String note;
  int? paper;

  /// The tape studio's decorations, exactly as the computer made them (the phone shows them, it
  /// doesn't change them).
  Map<String, Object?>? design;

  /// Whatever else a newer Mixtape puts on a tape, kept for the trip back.
  final Map<String, Object?> extra;

  /// The part of the name that shows: 'Podcast: x' and 'YouTube: x' tapes keep their group in front.
  String get shownName => group == null ? name : name.substring(name.indexOf(': ') + 2);

  /// 'Podcast', 'YouTube' or 'Local' for the computer's grouped tapes, null for the usual ones.
  String? get group {
    for (final g in const ['Podcast', 'YouTube', 'Local']) {
      if (name.startsWith('$g: ')) return g;
    }
    return null;
  }

  int get seconds => songs.fold(0, (sum, t) => sum + t.dur);

  /// A tape the way it travels to the account and back.
  Map<String, Object?> toJson() => {
        ...extra,
        'songs': [for (final t in songs) t.toJson()],
        'note': note,
        'paper': paper,
        'design': design,
      };

  static Tape fromJson(String name, Object? data) {
    final d = data is Map ? data : const {};
    final songs = d['songs'];
    final design = d['design'];
    final extra = <String, Object?>{};
    d.forEach((k, v) {
      if (!const {'songs', 'note', 'paper', 'design'}.contains(k)) extra['$k'] = v;
    });
    final paper = d['paper'];
    return Tape(
      name: name,
      songs: songs is List ? songs.map(Track.fromJson).whereType<Track>().toList() : [],
      note: d['note'] is String ? d['note'] as String : '',
      paper: paper is int && paper >= 0 && paper < 64 ? paper : null,
      design: design is Map ? Map<String, Object?>.from(design) : null,
      extra: extra,
    );
  }
}

/// A short fingerprint of some JSON, to tell whether a tape changed since it last went to the account.
/// Keys are sorted first, so the same tape always gives the same fingerprint.
String fingerprint(Object? json) {
  final text = jsonEncode(_sorted(json));
  return crc32(utf8.encode(text)).toRadixString(16).padLeft(8, '0') + text.length.toRadixString(16);
}

Object? _sorted(Object? v) {
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return {for (final k in keys) k: _sorted(v[k])};
  }
  if (v is List) return [for (final x in v) _sorted(x)];
  return v;
}

/// The smallest cassette a list fits on: C46, C60, C90 or C120, the way the desktop app labels it.
String tapeFor(int seconds) {
  final minutes = (seconds + 59) ~/ 60;
  for (final (cap, name) in const [(46, 'C46'), (60, 'C60'), (90, 'C90'), (120, 'C120')]) {
    if (minutes <= cap) return name;
  }
  return '${(minutes + 89) ~/ 90}×C90';
}

/// Seconds as m:ss (or h:mm:ss for an hour and more).
String clock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  final ss = r.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// CRC-32 (the zip one), the checksum the desktop picks a tape's label paper with (zlib.crc32).
int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final b in bytes) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >>> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    }
    t[n] = c;
  }
  return t;
}();

int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0);
