/// Your music on the phone: the tapes, the liked songs and what played lately, kept in the app's folder
/// and, when you're signed in, in step with your Mixtape Account (and so with the computer).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'account.dart';
import 'model.dart';
import 'store.dart';

const _libraryFile = 'library.json';
const _syncFile = 'sync.json';
const _recentMax = 60;

class Library extends ChangeNotifier {
  Library(this.account) {
    _save = LaterSave(_libraryFile, _dump);
    _saveSync = LaterSave(_syncFile, _dumpSync, delay: const Duration(milliseconds: 300));
  }

  final Account account;

  /// Tapes by name, in the order the computer keeps them (oldest first).
  final Map<String, Tape> tapes = {};

  /// Liked songs, oldest first (the way the computer keeps them; the pages show the newest on top).
  final List<Track> liked = [];
  final Set<String> _likedIds = {};

  /// What played lately, newest first.
  final List<Track> recent = [];

  late final LaterSave _save;
  late final LaterSave _saveSync;

  // what the account had when this phone last spoke to it
  String _since = '';
  String _uid = '';
  final Map<String, String> _known = {}; // tape name -> fingerprint as it went up or came down
  List<String> _likedBase = []; // the liked songs' ids at the last sync
  bool _likedChanged = false;

  bool syncing = false;
  String? trouble; // why the last sync didn't work, in words for the person
  DateTime? syncedAt;
  Future<void>? _running;
  bool _again = false;
  Timer? _soon;

  Future<void> load() async {
    final j = await Store.the.read(_libraryFile);
    if (j is Map) {
      final t = j['tapes'];
      if (t is Map) {
        t.forEach((name, data) {
          if (name is String && name.isNotEmpty) tapes[name] = Tape.fromJson(name, data);
        });
      }
      for (final x in j['liked'] is List ? j['liked'] as List : const []) {
        final track = Track.fromJson(x);
        if (track != null && _likedIds.add(track.id)) liked.add(track);
      }
      for (final x in j['recent'] is List ? j['recent'] as List : const []) {
        final track = Track.fromJson(x);
        if (track != null) recent.add(track);
      }
    }
    final s = await Store.the.read(_syncFile);
    if (s is Map) {
      _uid = '${s['uid'] ?? ''}';
      _since = '${s['since'] ?? ''}';
      final known = s['known'];
      if (known is Map) {
        known.forEach((k, v) {
          if (k is String && v is String) _known[k] = v;
        });
      }
      final base = s['liked_base'];
      _likedBase = base is List ? [for (final x in base) '$x'] : [];
      _likedChanged = s['liked_changed'] == true;
    }
    notifyListeners();
  }

  Object? _dump() => {
        'tapes': {for (final e in tapes.entries) e.key: e.value.toJson()},
        'liked': [for (final t in liked) t.toJson()],
        'recent': [for (final t in recent) t.toJson()],
      };

  Object? _dumpSync() => {
        'uid': _uid,
        'since': _since,
        'known': _known,
        'liked_base': _likedBase,
        'liked_changed': _likedChanged,
      };

  /// Something changed here: saved in a moment, and in the account a little later.
  void _changed({bool sync = true}) {
    _save.soon();
    notifyListeners();
    if (sync && account.signedIn) {
      _soon?.cancel();
      _soon = Timer(const Duration(seconds: 4), () => this.sync());
    }
  }

  /// Everything waiting goes to disk now (the app is going to the background).
  Future<void> flush() async {
    await _save.now();
    await _saveSync.now();
  }

  // ------------------------------------------------------------ liked songs

  bool isLiked(Track t) => _likedIds.contains(t.id);

  /// Likes a song, or unlikes it when it was liked. Returns whether it's liked now.
  bool toggleLike(Track t) {
    final now = !isLiked(t);
    if (now) {
      liked.add(t);
      _likedIds.add(t.id);
    } else {
      liked.removeWhere((x) => x.id == t.id);
      _likedIds.remove(t.id);
    }
    _likedChanged = true;
    _saveSync.soon();
    _changed();
    return now;
  }

  // ------------------------------------------------------------ tapes

  /// The tapes that show in the library: all of them but the computer's folder tapes, whose files
  /// aren't on the phone (the computer doesn't send those anyway).
  List<Tape> get shownTapes => [
        for (final t in tapes.values)
          if (t.group != 'Local') t,
      ];

  /// A name for a new tape that no tape has yet.
  String freeName(String wanted) {
    final base = wanted.trim().isEmpty ? 'New tape' : wanted.trim();
    if (!tapes.containsKey(base)) return base;
    for (var k = 2;; k++) {
      final name = '$base $k';
      if (!tapes.containsKey(name)) return name;
    }
  }

  Tape newTape(String name, {List<Track> songs = const []}) {
    final tape = Tape(name: freeName(name), songs: [...songs]);
    tapes[tape.name] = tape;
    _changed();
    return tape;
  }

  /// Puts songs on a tape. Songs it has already stay where they are. Returns how many went on.
  int addTo(Tape tape, List<Track> songs) {
    final have = {for (final t in tape.songs) t.id};
    final fresh = [
      for (final t in songs)
        if (have.add(t.id)) t,
    ];
    if (fresh.isEmpty) return 0;
    tape.songs.addAll(fresh);
    _changed();
    return fresh.length;
  }

  void removeAt(Tape tape, int index) {
    if (index < 0 || index >= tape.songs.length) return;
    tape.songs.removeAt(index);
    _changed();
  }

  void move(Tape tape, int from, int to) {
    if (from == to || from < 0 || from >= tape.songs.length) return;
    final t = tape.songs.removeAt(from);
    tape.songs.insert(to.clamp(0, tape.songs.length), t);
    _changed();
  }

  void setNote(Tape tape, String note) {
    final text = note.trim();
    if (text == tape.note) return;
    tape.note = text.length > 80 ? text.substring(0, 80) : text;
    _changed();
  }

  /// A tape gets another name. The account knows tapes by their name, so it's the old one gone and a
  /// new one there, like on the computer.
  Tape rename(Tape tape, String name) {
    final wanted = name.trim();
    if (wanted.isEmpty || wanted == tape.name) return tape;
    final fresh = Tape(
        name: freeName(wanted), songs: tape.songs, note: tape.note, paper: tape.paper, design: tape.design, extra: tape.extra);
    final order = [for (final n in tapes.keys) n == tape.name ? fresh.name : n];
    final all = {...tapes, fresh.name: fresh}..remove(tape.name);
    tapes
      ..clear()
      ..addEntries(order.map((n) => MapEntry(n, all[n]!)));
    _changed();
    return fresh;
  }

  void deleteTape(Tape tape) {
    if (tapes.remove(tape.name) != null) _changed();
  }

  // ------------------------------------------------------------ played lately

  void played(Track t) {
    recent.removeWhere((x) => x.id == t.id);
    recent.insert(0, t);
    if (recent.length > _recentMax) recent.removeRange(_recentMax, recent.length);
    _changed(sync: false);
  }

  // ------------------------------------------------------------ the account

  /// After signing in, or signing in as somebody else: nothing of that account is known here yet.
  void signedIn() {
    final uid = account.session?.uid ?? '';
    if (uid != _uid) {
      _uid = uid;
      _since = '';
      _known.clear();
      _likedBase = [];
      _likedChanged = liked.isNotEmpty; // what was liked here before goes up along with the account's
      _saveSync.soon();
    }
    sync();
  }

  /// Signed out: the tapes stay on the phone, and nothing goes anywhere anymore.
  void signedOut() {
    _soon?.cancel();
    trouble = null;
    notifyListeners();
  }

  /// In step with the account: what changed there comes in, what changed here goes up. One at a time;
  /// asking while one runs makes it run once more right after.
  Future<void> sync() {
    if (!account.signedIn) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _sync().whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        sync();
      }
    });
  }

  Future<void> _sync() async {
    syncing = true;
    notifyListeners();
    try {
      await _pullTapes();
      await _pushTapes();
      await _syncLiked();
      await _pullLayers();
      trouble = null;
      syncedAt = DateTime.now();
    } on AccountError catch (e) {
      trouble = e.message;
      final s = account.session;
      if (e.why == 'signin' && s != null) {
        s.expires = 0; // the server didn't take the sign-in: it's renewed before the next try
      }
    } finally {
      syncing = false;
      _saveSync.soon();
      _save.soon();
      notifyListeners();
    }
  }

  /// The account's tapes since last time (all of them the first time). New ones and ones changed
  /// elsewhere come in; one changed here as well keeps the phone's version, which goes up next.
  Future<void> _pullTapes() async {
    final rows = await account.pullTapes(since: _since);
    var newest = _since;
    for (final r in rows) {
      final name = '${r['name'] ?? ''}';
      if (name.isEmpty) continue;
      final at = '${r['updated_at'] ?? ''}';
      if (at.compareTo(newest) > 0) newest = at;
      final local = tapes[name];
      final untouchedHere = local != null && _known[name] == fingerprint(local.toJson());
      if (r['deleted'] == true) {
        if (untouchedHere) tapes.remove(name);
        if (local == null || untouchedHere) _known.remove(name);
        continue;
      }
      if (local == null || untouchedHere) {
        final tape = Tape.fromJson(name, r['data']);
        tapes[name] = tape;
        _known[name] = fingerprint(tape.toJson());
      } else if (_since.isEmpty && !_known.containsKey(name)) {
        // the first time this phone meets the account, and both have a tape of this name: the
        // account's tape with the phone's other songs at its end (that goes up next)
        final tape = Tape.fromJson(name, r['data']);
        _known[name] = fingerprint(tape.toJson());
        final have = {for (final t in tape.songs) t.id};
        tape.songs.addAll([
          for (final t in local.songs)
            if (have.add(t.id)) t,
        ]);
        tapes[name] = tape;
      }
    }
    _since = newest;
  }

  /// Tapes changed here since they last went up go up; deleted ones go as deleted. What changes while
  /// they travel is left for the next time.
  Future<void> _pushTapes() async {
    final changed = <String, Map<String, Object?>>{};
    final stamps = <String, String>{};
    for (final t in tapes.values) {
      if (t.group == 'Local') continue;
      final data = t.toJson();
      final stamp = fingerprint(data);
      if (_known[t.name] != stamp) {
        changed[t.name] = data;
        stamps[t.name] = stamp;
      }
    }
    final gone = [
      for (final n in _known.keys)
        if (!tapes.containsKey(n)) n,
    ];
    if (changed.isNotEmpty) {
      await account.pushTapes(changed);
      _known.addAll(stamps);
    }
    for (final n in gone) {
      await account.dropTape(n);
      _known.remove(n);
    }
  }

  /// Liked songs travel in the account's library, as one list. Both sides may have changed it since
  /// last time: songs liked on either side stay, songs unliked on either side go.
  Future<void> _syncLiked() async {
    final row = await account.pullLibrary();
    final data = row['data'] is Map ? Map<String, Object?>.from(row['data'] as Map) : <String, Object?>{};
    final theirs = [
      for (final x in data['liked'] is List ? data['liked'] as List : const [])
        if (Track.fromJson(x) case final Track t) t,
    ];
    final base = _likedBase.toSet();
    final theirIds = {for (final t in theirs) t.id};
    final goneThere = base.difference(theirIds);
    final merged = [
      for (final t in liked)
        if (!goneThere.contains(t.id)) t,
    ];
    final mine = {for (final t in merged) t.id};
    for (final t in theirs) {
      if (!base.contains(t.id) && mine.add(t.id)) merged.add(t); // liked on the other side
    }
    final mergedIds = [for (final t in merged) t.id];
    final changedHere = !_sameIds(mergedIds, [for (final t in liked) t.id]);
    if (changedHere) {
      liked
        ..clear()
        ..addAll(merged);
      _likedIds
        ..clear()
        ..addAll(mergedIds);
    }
    if (!_sameIds(mergedIds, [for (final t in theirs) t.id]) || (_likedChanged && row.isEmpty)) {
      data['liked'] = [for (final t in merged) t.toJson()];
      await account.pushLibrary(data);
    }
    _likedBase = mergedIds;
    _likedChanged = false;
  }

  // ------------------------------------------------------------ decorations

  /// The picture of a tape's stickers, photos and doodles, as the computer drew it (the phone lays it
  /// over its own cassette), or null when the tape has none or it isn't here yet.
  String? layerOf(Tape tape) {
    final name = tape.design?['layer'];
    if (name is! String || !picturePattern.hasMatch(name)) return null;
    final f = Store.the.file('layers/$name');
    return f.existsSync() ? f.path : null;
  }

  /// Fetches the decoration pictures this phone doesn't have yet, and lets go of the ones no tape uses.
  Future<void> _pullLayers() async {
    final dir = Directory('${Store.the.dir.path}/layers');
    final want = <String>{
      for (final t in tapes.values)
        if (t.design?['layer'] case final String name)
          if (picturePattern.hasMatch(name)) name,
    };
    final missing = [
      for (final n in want)
        if (!File('${dir.path}/$n').existsSync()) n,
    ];
    if (missing.isNotEmpty) {
      await dir.create(recursive: true);
      final got = await account.pullPictures(missing);
      for (final e in got.entries) {
        await File('${dir.path}/${e.key}').writeAsBytes(e.value, flush: true);
      }
    }
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (!want.contains(f.uri.pathSegments.last)) {
          try {
            f.deleteSync();
          } on FileSystemException {
            // in use a moment longer: next time
          }
        }
      }
    }
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var k = 0; k < a.length; k++) {
      if (a[k] != b[k]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _soon?.cancel();
    super.dispose();
  }
}
