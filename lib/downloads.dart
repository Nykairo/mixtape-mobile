/// Songs saved on the phone, for listening without the internet: a whole tape, the liked songs, an album
/// or a single song. One song comes down at a time, as fast as it comes (in pieces, so YouTube doesn't
/// slow it down), each with its cover; a song that won't come is passed over and can be tried again.
/// The files live in the app's own folder (offline/), listed in offline.json.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'audio.dart';
import 'model.dart';
import 'store.dart';

const _indexFile = 'offline.json';

class SavedSong {
  const SavedSong(this.track, this.file, this.bytes);

  final Track track;
  final String file;
  final int bytes;
}

class Downloads extends ChangeNotifier {
  Downloads({http.Client? client}) : _http = client ?? http.Client();

  static final the = Downloads();

  final http.Client _http;
  final Map<String, SavedSong> _saved = {};
  final List<Track> _waiting = [];
  final Set<String> failed = {};

  /// What a batch was called ("Road trip") and which of its songs are still to come, for the word at the end.
  final List<(String, Set<String>)> _batches = [];

  /// Things to tell the person ("Road trip is on your phone").
  final notices = StreamController<String>.broadcast();

  Track? current;
  double progress = 0;
  bool _running = false;
  bool _stop = false;

  late final _save = LaterSave(_indexFile, _dump, delay: const Duration(milliseconds: 500));

  Directory get _dir => Directory('${Store.the.dir.path}/offline');

  Future<void> load() async {
    final j = await Store.the.read(_indexFile);
    if (j is! Map) return;
    final songs = j['songs'];
    if (songs is Map) {
      songs.forEach((id, v) {
        if (v is! Map) return;
        final t = Track.fromJson(v['track']);
        final file = '${v['file'] ?? ''}';
        if (t != null && file.isNotEmpty) _saved['$id'] = SavedSong(t, file, v['bytes'] is int ? v['bytes'] as int : 0);
      });
    }
    // what was still coming when the app closed comes on now
    final waiting = [
      for (final x in j['waiting'] is List ? j['waiting'] as List : const [])
        if (Track.fromJson(x) case final Track t) t,
    ];
    if (waiting.isNotEmpty) save(waiting);
  }

  Object? _dump() => {
        'songs': {
          for (final s in _saved.values)
            s.track.id: {'track': s.track.toJson(), 'file': s.file, 'bytes': s.bytes},
        },
        'waiting': [for (final t in _waiting) t.toJson()],
      };

  // ------------------------------------------------------------ asking

  bool has(Track t) => _saved.containsKey(t.id);

  bool isWaiting(Track t) => _waiting.any((w) => w.id == t.id) || current?.id == t.id;

  /// The file a song plays from without the internet, when it's saved.
  String? fileOf(Track t) {
    final s = _saved[t.id];
    if (s == null) return null;
    final f = File('${_dir.path}/${s.file}');
    return f.existsSync() ? f.path : null;
  }

  /// The saved cover of a song, for showing it offline.
  File? coverOf(Track t) {
    if (!_saved.containsKey(t.id)) return null;
    final f = File('${_dir.path}/${t.id}.jpg');
    return f.existsSync() ? f : null;
  }

  /// How many of these songs are saved, of how many that can be.
  (int, int) count(Iterable<Track> songs) {
    var have = 0, total = 0;
    for (final t in songs) {
      if (t.src != 'yt') continue;
      total++;
      if (_saved.containsKey(t.id)) have++;
    }
    return (have, total);
  }

  /// Whether any of these songs are on their way.
  bool busyWith(Iterable<Track> songs) => songs.any(isWaiting);

  List<SavedSong> get all => _saved.values.toList().reversed.toList();

  int get bytes => _saved.values.fold(0, (s, x) => s + x.bytes);

  // ------------------------------------------------------------ saving and letting go

  /// Lines up songs to be saved (the ones that are saved or on their way already are left out). [name]
  /// says what they are, for the word when they're all here. Returns how many will come.
  int save(Iterable<Track> songs, {String name = ''}) {
    final ids = <String>{};
    for (final t in songs) {
      if (t.src != 'yt' || _saved.containsKey(t.id) || isWaiting(t) || !ids.add(t.id)) continue;
      _waiting.add(t);
      failed.remove(t.id);
    }
    if (ids.isEmpty) return 0;
    if (name.isNotEmpty) _batches.add((name, ids));
    _save.soon();
    notifyListeners();
    _start();
    return ids.length;
  }

  /// Stops saving these songs (the one coming down right now comes to an end first).
  void cancel(Iterable<Track> songs) {
    final ids = {for (final t in songs) t.id};
    _waiting.removeWhere((t) => ids.contains(t.id));
    if (current != null && ids.contains(current!.id)) _stop = true;
    for (final b in _batches) {
      b.$2.removeAll(ids);
    }
    _batches.removeWhere((b) => b.$2.isEmpty);
    _save.soon();
    notifyListeners();
  }

  /// Takes songs off the phone.
  Future<void> remove(Iterable<Track> songs) async {
    cancel(songs);
    for (final t in songs) {
      final s = _saved.remove(t.id);
      if (s == null) continue;
      for (final name in [s.file, '${t.id}.jpg']) {
        try {
          await File('${_dir.path}/$name').delete();
        } on FileSystemException {
          // gone already
        }
      }
    }
    _save.soon();
    notifyListeners();
  }

  void _start() {
    if (_running) return;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      await _dir.create(recursive: true);
      while (_waiting.isNotEmpty) {
        final t = _waiting.removeAt(0);
        current = t;
        progress = 0;
        _stop = false;
        notifyListeners();
        var ok = false;
        try {
          ok = await _fetch(t);
        } on Object {
          ok = false;
        }
        if (!ok && !_stop) failed.add(t.id);
        current = null;
        _done(t, ok);
        _save.soon();
        notifyListeners();
      }
    } finally {
      _running = false;
      current = null;
      notifyListeners();
    }
  }

  void _done(Track t, bool ok) {
    for (final b in List.of(_batches)) {
      if (!b.$2.remove(t.id) || b.$2.isNotEmpty) continue;
      _batches.remove(b);
      notices.add(failed.isEmpty ? '${b.$1} is on your phone now' : '${b.$1} is on your phone, but for a few songs');
    }
  }

  Future<bool> _fetch(Track t) async {
    final source = YouTubeSource(t, _http);
    final size = await source.size();
    final link = await Links.get(t.ref);
    final ext = link.mime.contains('webm') ? 'webm' : 'm4a';
    final part = File('${_dir.path}/${t.id}.part');
    final sink = part.openWrite();
    var got = 0;
    var told = DateTime.now();
    try {
      await for (final chunk in source.bytes(0, size, paced: false)) {
        if (_stop) break;
        sink.add(chunk);
        got += chunk.length;
        progress = size > 0 ? got / size : 0;
        if (DateTime.now().difference(told) > const Duration(milliseconds: 250)) {
          told = DateTime.now();
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }
    if (_stop || got < size) {
      await part.delete().catchError((Object _) => part);
      return false;
    }
    final name = '${t.id}.$ext';
    await part.rename('${_dir.path}/$name');
    await _cover(t);
    _saved[t.id] = SavedSong(t, name, got);
    return true;
  }

  Future<void> _cover(Track t) async {
    final url = t.artAt(300);
    if (url.isEmpty) return;
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.bodyBytes.length < 1500000) {
        await File('${_dir.path}/${t.id}.jpg').writeAsBytes(res.bodyBytes, flush: true);
      }
    } on Object {
      // the song is here; the cover shows from the internet when there is some
    }
  }

  Future<void> flush() => _save.now();
}
