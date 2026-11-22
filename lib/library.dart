/// Your music on the phone: the tapes, the liked songs and what played lately, kept in the app's folder
/// and, when you're signed in, in step with your Mixtape Account (and so with the computer).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'account.dart';
import 'decor.dart' show cleanItems, layerPngReading, picturesOf;
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

  /// Albums, playlists and artists opened lately, newest first (for Home's shortcuts).
  final List<Map<String, Object?>> opened = [];

  /// What was searched for lately, newest first.
  final List<String> searches = [];

  /// Tapes pinned to the top of the library, in the order they were pinned ('' is Liked songs).
  final List<String> pinned = [];

  /// Songs the person isn't interested in: mixes, radios, Quick picks and Samples leave them out.
  final Map<String, Track> hidden = {};

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
      for (final x in j['opened'] is List ? j['opened'] as List : const []) {
        if (x is Map && x['id'] is String) opened.add(Map<String, Object?>.from(x));
      }
      for (final x in j['searches'] is List ? j['searches'] as List : const []) {
        if (x is String) searches.add(x);
      }
      for (final x in j['pinned'] is List ? j['pinned'] as List : const []) {
        if (x is String) pinned.add(x);
      }
      for (final x in j['hidden'] is List ? j['hidden'] as List : const []) {
        final track = Track.fromJson(x);
        if (track != null) hidden[track.id] = track;
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
        'opened': opened,
        'searches': searches,
        'pinned': pinned,
        'hidden': [for (final t in hidden.values) t.toJson()],
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

  /// Songs that had lost their artist get it back (see mend.dart), [found] by the song's id, wherever
  /// they are: liked, lately played, hidden and on tapes (which then go to the account, mended there too).
  void giveArtists(Map<String, Track> found) {
    var any = false;
    Track fix(Track t) {
      final f = found[t.id];
      if (f == null || t.artist.isNotEmpty) return t;
      any = true;
      return t.withArtist(f.artist, artistId: '${f.extra['artist_id'] ?? ''}');
    }

    for (final list in [liked, recent, for (final tape in tapes.values) tape.songs]) {
      for (var k = 0; k < list.length; k++) {
        list[k] = fix(list[k]);
      }
    }
    hidden.updateAll((_, t) => fix(t));
    if (any) _changed();
  }

  // ------------------------------------------------------------ liked songs

  bool isLiked(Track t) => _likedIds.contains(t.id);

  /// Likes a song, or unlikes it when it was liked. Returns whether it's liked now (a phone's own file
  /// never is: see Track.fromPhone).
  bool toggleLike(Track t) {
    if (t.fromPhone) return false;
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

  /// A new tape (a phone's own files stay off it: they'd play nowhere else, nor here after a restart).
  Tape newTape(String name, {List<Track> songs = const []}) {
    final tape = Tape(name: freeName(name), songs: [
      for (final t in songs)
        if (!t.fromPhone) t,
    ]);
    tapes[tape.name] = tape;
    _changed();
    return tape;
  }

  /// Puts songs on a tape. Songs it has already stay where they are. Returns how many went on.
  int addTo(Tape tape, List<Track> songs) {
    final have = {for (final t in tape.songs) t.id};
    final fresh = [
      for (final t in songs)
        if (!t.fromPhone && have.add(t.id)) t,
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
    final wasPinned = pinned.indexOf(tape.name);
    final fresh = Tape(
        name: freeName(wanted), songs: tape.songs, note: tape.note, paper: tape.paper, design: tape.design, extra: tape.extra);
    final order = [for (final n in tapes.keys) n == tape.name ? fresh.name : n];
    final all = {...tapes, fresh.name: fresh}..remove(tape.name);
    tapes
      ..clear()
      ..addEntries(order.map((n) => MapEntry(n, all[n]!)));
    if (wasPinned >= 0) pinned[wasPinned] = fresh.name;
    _changed();
    return fresh;
  }

  void deleteTape(Tape tape) {
    if (tapes.remove(tape.name) != null) _changed();
  }

  // ------------------------------------------------------------ played lately

  void played(Track t) {
    if (t.fromPhone) return; // gone after a restart: no use coming back to it from Home
    recent.removeWhere((x) => x.id == t.id);
    recent.insert(0, t);
    if (recent.length > _recentMax) recent.removeRange(_recentMax, recent.length);
    _changed(sync: false);
  }

  // ------------------------------------------------------------ what was opened, searched, pinned, hidden

  /// An album, a playlist or an artist was opened: it goes to the front of Home's shortcuts.
  void openedItem(Map<String, Object?> item) {
    opened.removeWhere((x) => x['id'] == item['id']);
    opened.insert(0, item);
    if (opened.length > 12) opened.removeRange(12, opened.length);
    _changed(sync: false);
  }

  void searched(String q) {
    final text = q.trim();
    if (text.isEmpty) return;
    searches.removeWhere((x) => x.toLowerCase() == text.toLowerCase());
    searches.insert(0, text);
    if (searches.length > 20) searches.removeRange(20, searches.length);
    _changed(sync: false);
  }

  void forgetSearch([String? q]) {
    if (q == null) {
      searches.clear();
    } else {
      searches.remove(q);
    }
    _changed(sync: false);
  }

  bool isPinned(String name) => pinned.contains(name);

  void pin(String name, bool on) {
    pinned.remove(name);
    if (on) pinned.add(name);
    _changed(sync: false);
  }

  bool isHidden(Track t) => hidden.containsKey(t.id);

  /// Not interested in a song (or interested again).
  void hide(Track t, bool on) {
    if (on) {
      hidden[t.id] = t;
      while (hidden.length > 2000) {
        hidden.remove(hidden.keys.first);
      }
    } else {
      hidden.remove(t.id);
    }
    _changed(sync: false);
  }

  /// A tape's new look from the tape studio. With [items], what's stuck and drawn on it changes too
  /// ([layer]: their picture for the phones, see keepLayer); otherwise the ones it has stay.
  void setDesign(Tape tape, Map<String, Object?> design, {int? paper, List<Map<String, Object?>>? items, String? layer}) {
    final keep = tape.design ?? const {};
    tape.design = {
      if (items == null)
        for (final e in keep.entries)
          if (const {'items', 'layer'}.contains(e.key)) e.key: e.value,
      ...design,
      if (items != null && items.isNotEmpty) 'items': items,
      if (items != null && items.isNotEmpty && layer != null) 'layer': layer,
    };
    if (paper != null) tape.paper = paper;
    _changed();
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
      // the pictures first, so the computer finds them when the tapes arrive
      await account.pushPictures({
        for (final d in changed.values)
          if (d['design'] case final Map<String, Object?> design) ...{
            ...picturesOf(design['items']),
            if (design['layer'] case final String layer) layer,
          },
      }, (name) async {
        try {
          return await havePicture(name)?.readAsBytes();
        } on FileSystemException {
          return null;
        }
      });
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

  /// The picture of a tape's stickers, photos and doodles, as the computer (or the studio here) drew
  /// it: the phone lays it over its own cassette. Null when the tape has none or it isn't here yet.
  String? layerOf(Tape tape) {
    final name = tape.design?['layer'];
    if (name is! String || !picturePattern.hasMatch(name)) return null;
    final f = Store.the.file('layers/$name');
    return f.existsSync() ? f.path : null;
  }

  /// A photo for a tape (as the picker made it), kept under a name made from the picture itself, the
  /// computer's way: the same picture always gets the same name, on every device.
  Future<String> keepPicture(List<int> bytes, {required bool png}) =>
      _keep('pictures', bytes, png ? 'png' : 'jpg');

  /// The drawing of a tape's decorations for the phones (see decor.layerPng).
  Future<String> keepLayer(List<int> png) => _keep('layers', png, 'png');

  Future<String> _keep(String folder, List<int> bytes, String ext) async {
    final name = '${sha1.convert(bytes).toString().substring(0, 20)}.$ext';
    final f = Store.the.file('$folder/$name');
    if (!f.existsSync()) {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(f.path);
    }
    return name;
  }

  // ------------------------------------------------------------ the whole library in one file

  /// A song as it plays anywhere else (the computer, another phone); null for a file on this phone.
  static Map<String, Object?>? _portable(Track t) {
    if (!const {'yt', 'sc', 'pod'}.contains(t.src)) return null;
    final j = t.toJson();
    return {
      for (final k in const ['id', 'src', 'ref', 'title', 'artist', 'album', 'art', 'dur', 'album_id', 'artist_id'])
        if (j[k] != null && j[k] != '') k: j[k],
    };
  }

  /// The whole library in one file, the computer's mixtape-library.json (core.export_library there):
  /// the liked songs, the tapes with their notes, label papers and decorations, and the pictures on
  /// them. The computer takes it in with Ctrl+I, another phone in Settings.
  Future<Map<String, Object?>> exportLibrary() async {
    final playlists = <String, Object?>{};
    final notes = <String, String>{};
    final papers = <String, int>{};
    final designs = <String, Object?>{};
    final pictures = <String, String>{};
    for (final t in shownTapes) {
      playlists[t.name] = [
        for (final s in t.songs)
          if (_portable(s) case final j?) j,
      ];
      if (t.note.isNotEmpty) notes[t.name] = t.note;
      if (t.paper case final int paper) papers[t.name] = paper;
      final design = t.design;
      if (design == null || design.isEmpty) continue;
      designs[t.name] = {
        for (final e in design.entries)
          if (e.key != 'layer') e.key: e.value, // the phones' own picture of it; the file has what it's made of
      };
      for (final name in picturesOf(design['items'])) {
        final f = havePicture(name);
        if (f == null || pictures.containsKey(name)) continue;
        try {
          pictures[name] = base64.encode(await f.readAsBytes());
        } on FileSystemException {
          continue; // the tape goes without that photo
        }
      }
    }
    return {
      'liked': [
        for (final s in liked)
          if (_portable(s) case final j?) j,
      ],
      'playlists': playlists,
      'notes': notes,
      'papers': papers,
      'designs': designs,
      if (pictures.isNotEmpty) 'sticker_images': pictures,
    };
  }

  /// The library written into a file, to send off with the share sheet (see exportLibrary).
  Future<File> exportFile() async {
    final text = await compute(jsonEncode, await exportLibrary());
    final f = Store.the.file('export/mixtape-library.json');
    await f.parent.create(recursive: true);
    await f.writeAsString(text, flush: true);
    return f;
  }

  /// Takes in a library file picked on the phone (see importLibrary).
  Future<(int, int)> importFile(String path) async {
    final f = File(path);
    // the computer's files stay well under this even with photos on every tape
    if (await f.length() > 64 << 20) throw const FormatException("That's far too big for a Mixtape library");
    final text = await f.readAsString();
    return importLibrary(await compute(jsonDecode, text));
  }

  /// Takes in a library file (the computer's or a phone's) the way the computer does: the liked songs
  /// not liked here yet, the tapes whose names aren't taken, and notes, label papers and decorations
  /// for tapes that have none of their own. Nothing here is changed or lost. Returns how many liked
  /// songs and how many tapes came in; a FormatException when it isn't a library at all.
  Future<(int, int)> importLibrary(Object? raw) async {
    if (raw is! Map || (raw['liked'] is! List && raw['playlists'] is! Map)) {
      throw const FormatException("That isn't a Mixtape library");
    }
    var likes = 0;
    for (final j in raw['liked'] is List ? raw['liked'] as List : const []) {
      final t = Track.fromJson(j);
      if (t == null || !_likedIds.add(t.id)) continue;
      liked.add(t);
      likes++;
    }
    if (likes > 0) {
      _likedChanged = true;
      _saveSync.soon();
    }
    final came = <Tape>[];
    final lists = raw['playlists'] is Map ? raw['playlists'] as Map : const {};
    for (final MapEntry(:key, :value) in lists.entries) {
      final name = '$key'.trim();
      if (name.isEmpty || tapes.containsKey(name) || value is! List) continue;
      final tape = Tape(name: name, songs: [
        for (final j in value)
          if (Track.fromJson(j) case final t?) t,
      ]);
      tapes[name] = tape;
      came.add(tape);
    }
    final notes = raw['notes'] is Map ? raw['notes'] as Map : const {};
    final papers = raw['papers'] is Map ? raw['papers'] as Map : const {};
    final designs = raw['designs'] is Map ? raw['designs'] as Map : const {};
    final decorated = <Tape>[];
    for (final t in tapes.values) {
      if (notes[t.name] case final String note when t.note.isEmpty && note.trim().isNotEmpty) t.note = note.trim();
      if (papers[t.name] case final int paper when t.paper == null && paper >= 0 && paper < 64) t.paper = paper;
      if (designs[t.name] case final Map design when t.design == null) {
        final d = <String, Object?>{
          for (final e in design.entries)
            if (e.key != 'layer') '${e.key}': e.value,
        };
        final items = cleanItems(d['items']);
        if (items.isEmpty) {
          d.remove('items');
        } else {
          d['items'] = items;
          decorated.add(t);
        }
        t.design = d;
      }
    }
    // the pictures on the tapes, under the names the decorations know them by
    final pictures = raw['sticker_images'] is Map ? raw['sticker_images'] as Map : const {};
    for (final MapEntry(:key, :value) in pictures.entries) {
      final name = '$key';
      if (!picturePattern.hasMatch(name) || value is! String || havePicture(name) != null) continue;
      try {
        final f = Store.the.file('pictures/$name');
        await f.parent.create(recursive: true);
        await f.writeAsBytes(base64.decode(value), flush: true);
      } on Object {
        continue; // a broken one: that photo shows as an empty frame
      }
    }
    // and the picture of each one's decorations, which the phones lay over the cassette
    for (final t in decorated) {
      final items = cleanItems(t.design?['items']);
      try {
        final png = await layerPngReading(items, (name) async {
          final f = havePicture(name);
          return f == null ? null : await f.readAsBytes();
        });
        if (png != null) t.design = {...?t.design, 'layer': await keepLayer(png)};
      } on Object {
        continue; // drawn when the tape studio opens it
      }
    }
    if (likes > 0 || came.isNotEmpty || decorated.isNotEmpty) _changed();
    return (likes, came.length);
  }

  /// A picture from the tapes' decorations, if it's on the phone.
  File? havePicture(String name) {
    if (!picturePattern.hasMatch(name)) return null;
    for (final folder in const ['pictures', 'layers']) {
      final f = Store.the.file('$folder/$name');
      if (f.existsSync()) return f;
    }
    return null;
  }

  /// The photos on a tape the phone doesn't have yet, from the account (when signed in). Returns the
  /// ones that came; whatever doesn't come shows as an empty frame.
  Future<Set<String>> fetchPictures(Iterable<String> names) async {
    final missing = [
      for (final n in names)
        if (havePicture(n) == null) n,
    ];
    if (missing.isEmpty || !account.signedIn) return const {};
    final Map<String, List<int>> got;
    try {
      got = await account.pullPictures(missing);
    } on Object {
      return const {}; // no connection or no answer: they come another time
    }
    final came = <String>{};
    for (final e in got.entries) {
      try {
        await _keep('pictures', e.value, e.key.endsWith('.png') ? 'png' : 'jpg');
        came.add(e.key);
      } on FileSystemException {
        continue; // a full phone: that one stays an empty frame
      }
    }
    return came;
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
    tidyPictures();
  }

  /// Lets go of the decoration pictures no tape uses anymore. One from the last day stays: the tape
  /// studio may still be about to use it.
  void tidyPictures() {
    final used = <String>{
      for (final t in tapes.values) ...{
        ...picturesOf(t.design?['items']),
        if (t.design?['layer'] case final String name) name,
      },
    };
    final young = DateTime.now().subtract(const Duration(days: 1));
    for (final folder in const ['layers', 'pictures']) {
      final dir = Directory('${Store.the.dir.path}/$folder');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        if (used.contains(f.uri.pathSegments.last)) continue;
        try {
          if (f.lastModifiedSync().isAfter(young)) continue;
          f.deleteSync();
        } on FileSystemException {
          // in use a moment longer: next time
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
