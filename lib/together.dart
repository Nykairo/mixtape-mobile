/// Listening together: along with a friend (you hear what they play, at the same second) and rooms (a
/// queue everybody in it hears at the same second; a party is a room the host steers and the others ask
/// for songs in). The same rooms and the same friends as on the computer, so phones and computers mix.
///
/// What plays on the phone goes to the account too (a moment after it changes), so friends can listen
/// along with you; Settings turns that off.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'account.dart';
import 'audio.dart';
import 'jsonwalk.dart';
import 'model.dart';
import 'realtime.dart';
import 'rooms.dart' as rooms;
import 'rooms.dart' show RoomState;

/// A song as it travels to other phones and computers: only what playing and showing it takes, or null
/// for a song that can't play anywhere else.
Map<String, Object?>? shareable(Track t) {
  if (!const {'yt', 'sc', 'pod'}.contains(t.src)) return null;
  final j = t.toJson();
  return {
    for (final k in const ['id', 'src', 'ref', 'title', 'artist', 'album', 'art', 'dur', 'album_id', 'artist_id'])
      if (j[k] != null && j[k] != '') k: j[k],
  };
}

class Together extends ChangeNotifier {
  Together(this.account, this.audio, {required this.sharing});

  final Account account;
  final MixtapeAudio audio;

  /// Whether what plays here may go to friends (Settings).
  final bool Function() sharing;

  final String device = 'phone-${Random().nextInt(1 << 30).toRadixString(36)}';
  RtLink? _link;
  double _offset = 0; // the server's clock minus this phone's, in seconds
  DateTime? _measured;

  /// The last thing that happened, in words, for the page and a snackbar.
  final notices = StreamController<String>.broadcast();

  RtLink get _rt => _link ??= RtLink(accountUrl, accountKey, account.token);

  double now() => DateTime.now().millisecondsSinceEpoch / 1000 + _offset;

  Future<void> _clock() async {
    final m = _measured;
    if (m != null && DateTime.now().difference(m) < const Duration(minutes: 10)) return;
    (double, double)? best;
    for (var k = 0; k < 3; k++) {
      try {
        final t0 = DateTime.now().millisecondsSinceEpoch / 1000;
        final server = await account.serverTime();
        final t1 = DateTime.now().millisecondsSinceEpoch / 1000;
        if (best == null || t1 - t0 < best.$1) best = (t1 - t0, server - (t0 + t1) / 2);
        if (t1 - t0 < 0.12) break; // a quick answer is as good as it gets
      } on Object {
        break;
      }
    }
    if (best != null) {
      _offset = best.$2;
      _measured = DateTime.now();
    }
  }

  String get me => account.session?.username ?? '';

  // ------------------------------------------------------------ listening along

  /// The friend whose music plays here ('' when none), their name, and what they play.
  String friend = '';
  String friendName = '';
  Map<String, Object?>? friendNow;
  String _friendUid = '';
  RtChannel? _friendCh;
  Timer? _friendPoll;

  Future<void> listenAlong(String username) async {
    final name = Account.cleanName(username);
    if (name.isEmpty) return;
    if (name == me) throw AccountError('room', 'self');
    await leaveRoom();
    stopAlong();
    final p = await account.profile(name);
    if (p['share_listening'] == false) {
      throw AccountError('room', 'private');
    }
    await _clock();
    friend = name;
    friendName = '${p['display_name'] ?? ''}'.isEmpty ? name : '${p['display_name']}';
    _friendUid = '${p['id']}';
    final ch = _rt.channel('live-$_friendUid', changes: [
      {'event': '*', 'schema': 'public', 'table': 'live', 'filter': 'owner=eq.$_friendUid'},
    ]);
    ch.onChange = (data) {
      final rec = asMap(data['type'] == 'DELETE' ? data['old_record'] : data['record']);
      if (rec['owner'] != _friendUid) return; // somebody else's (deletes reach everybody on the table)
      _friendIs(data['type'] == 'DELETE' ? null : asMap(rec['state']));
    };
    _friendCh = ch;
    audio.steer = steer;
    _friendPoll = Timer.periodic(const Duration(seconds: 6), (_) => _askFriend());
    await _askFriend();
    notifyListeners();
  }

  Future<void> _askFriend() async {
    if (friend.isEmpty) return;
    try {
      final row = await account.playing(_friendUid);
      _friendIs(row == null ? null : asMap(row['state']));
    } on AccountError {
      // offline for a moment: the next try, or the live line, brings it
    }
  }

  void _friendIs(Map<String, Object?>? s) {
    if (friend.isEmpty) return;
    final had = friendNow;
    friendNow = s;
    if (s == null || '${s['id'] ?? ''}'.isEmpty) {
      if (had != null) notices.add("$friendName isn't playing anything right now");
      if (audio.player.playing) audio.player.pause().ignore();
      notifyListeners();
      return;
    }
    final t = Track(
      src: 'yt',
      ref: '${s['id']}',
      title: '${s['title'] ?? ''}',
      artist: '${s['artist'] ?? ''}',
      dur: toInt(s['dur']),
    );
    final speed = s['speed'] is num ? (s['speed'] as num).toDouble() : 1.0;
    final playing = s['playing'] == true && s['loading'] != true;
    final pos0 = s['pos'] is num ? (s['pos'] as num).toDouble() : 0.0;
    final at = s['at'] is num ? (s['at'] as num).toDouble() : now();
    final pos = playing ? pos0 + max(0.0, now() - at) * speed : pos0;
    audio.followSong(t, Duration(milliseconds: (pos * 1000).round()),
        playing: playing, rate: speed, from: 'With $friendName');
    notifyListeners();
  }

  /// Stops listening along (the song that plays keeps playing, now yours).
  void stopAlong({String why = ''}) {
    if (friend.isEmpty) return;
    _friendPoll?.cancel();
    _friendCh?.leave();
    _friendCh = null;
    friend = '';
    friendNow = null;
    if (room == null) audio.steer = null;
    if (why.isNotEmpty) notices.add(why);
    notifyListeners();
  }

  // ------------------------------------------------------------ rooms

  /// The room you're in: code, kind ('together' or 'party'), name, role ('host' or 'guest'), host.
  Map<String, Object?>? room;
  RoomState state = rooms.blank();
  int version = 0;

  /// Who is in it right now (by account id: {user, name}), the members with their profiles, and the
  /// songs guests asked the host of a party for.
  Map<String, Map<String, Object?>> here = {};
  List<Map<String, Object?>> members = [];
  List<Map<String, Object?>> requests = [];
  RtChannel? _roomCh;
  Timer? _roomPoll;
  StreamSubscription<ProcessingState>? _ends;
  bool _keepGoing = true;

  String get code => '${room?['code'] ?? ''}';
  bool get isHost => room?['role'] == 'host';
  bool get party => room?['kind'] == 'party';

  /// Everybody steers a room; only the host steers a party.
  bool get canSteer => room != null && (!party || isHost);

  /// A new room with what plays here in it (from the song playing on), you its host.
  Future<String> openRoom({bool party = false, String name = ''}) async {
    if (!account.signedIn) throw AccountError('signin');
    stopAlong();
    await _clock();
    final view = audio.view;
    final songs = [
      for (var k = max(0, view.index); k < view.songs.length && k < max(0, view.index) + 60; k++) view.songs[k],
    ];
    final items = [
      for (final t in songs)
        if (shareable(t) case final Map<String, Object?> s) {'k': rooms.newKey(), 't': s, 'by': me},
    ];
    final first = rooms.blank()
      ..addAll({
        'q': items,
        'k': items.isEmpty ? '' : items.first['k'],
        'pos': audio.player.position.inMilliseconds / 1000,
        'at': now(),
        'paused': !audio.player.playing,
        'by': me,
        'did': 'start',
      });
    final shown = name.isNotEmpty ? name : "${account.session?.display ?? me}'s ${party ? 'party' : 'room'}";
    final got = await account.rpc('room_open', {
      'room_kind': party ? 'party' : 'together',
      'room_name': shown.length > 80 ? shown.substring(0, 80) : shown,
      'first_state': first,
      'room_settings': const {},
    });
    final code = '$got';
    await joinRoom(code);
    return code;
  }

  Future<void> joinRoom(String typed) async {
    if (!account.signedIn) throw AccountError('signin');
    final code = typed.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{6}$').hasMatch(code)) throw AccountError('room', 'gone');
    stopAlong();
    if (room != null && this.code != code) await leaveRoom();
    await _clock();
    final r = asMap(await account.rpc('room_join', {'room': code}));
    if (r['code'] != code) throw AccountError('server', 'odd answer');
    room = {
      'code': code,
      'kind': '${r['kind'] ?? 'together'}',
      'name': '${r['name'] ?? ''}',
      'role': '${r['role'] ?? 'guest'}',
      'host': '${r['host'] ?? ''}',
    };
    state = rooms.clean(r['state']);
    version = toInt(r['version']);
    final s = account.session!;
    final ch = _rt.channel('room-$code', presence: s.uid, changes: [
      for (final t in const ['rooms', 'room_members', 'room_requests'])
        {'event': '*', 'schema': 'public', 'table': t, 'filter': 'code=eq.$code'},
    ]);
    ch.onChange = _roomChanged;
    ch.onPeople = (people) {
      here = people;
      notifyListeners();
    };
    ch.track({'user': s.username, 'name': s.display});
    _roomCh = ch;
    _keepGoing = audio.autoplay;
    audio.autoplay = false;
    audio.steer = steer;
    _ends = audio.player.processingStateStream.listen((p) {
      final it = rooms.currentOf(state);
      if (p == ProcessingState.completed && it != null && room != null) {
        _change(rooms.ended(me, now(), '${it['k']}'));
      }
    });
    _roomPoll = Timer.periodic(const Duration(seconds: 5), (_) => _askRoom());
    _follow();
    unawaited(_fetchMembers());
    if (party && isHost) unawaited(_fetchRequests());
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    final c = code;
    if (room == null) return;
    _roomPoll?.cancel();
    await _ends?.cancel();
    _ends = null;
    _roomCh?.leave();
    _roomCh = null;
    room = null;
    state = rooms.blank();
    here = {};
    members = [];
    requests = [];
    audio.steer = friend.isEmpty ? null : steer;
    audio.autoplay = _keepGoing;
    notifyListeners();
    try {
      await account.rpc('room_leave', {'room': c}, timeout: const Duration(seconds: 8));
    } on AccountError {
      // the server lets go of us on its own after a while
    }
  }

  void _roomChanged(Map<String, Object?> data) {
    final rec = asMap(data['record']);
    final table = '${data['table'] ?? ''}';
    if (table == 'rooms' || rec.containsKey('state')) {
      if (data['type'] == 'DELETE') {
        notices.add('The room was closed');
        leaveRoom();
        return;
      }
      final v = toInt(rec['version']);
      if (v > version) _adopt(rec['state'], v);
    } else if (table == 'room_members' || (rec.containsKey('member') && rec.containsKey('role'))) {
      _fetchMembers();
    } else if (table == 'room_requests' || rec.containsKey('song')) {
      if (party && isHost) _fetchRequests();
    }
  }

  Future<void> _askRoom() async {
    if (room == null) return;
    try {
      final r = await account.room(code);
      if (r == null) {
        notices.add('The room was closed');
        await leaveRoom();
        return;
      }
      final v = toInt(r['version']);
      if (v > version) {
        _adopt(r['state'], v);
      } else {
        _follow(); // keeps it in step, should the song have drifted
      }
    } on AccountError {
      // offline for a moment
    }
  }

  void _adopt(Object? s, int v) {
    final fresh = rooms.clean(s);
    final words = rooms.said(fresh, me, _names);
    state = fresh;
    version = v;
    if (words.isNotEmpty) notices.add(words);
    _follow();
    notifyListeners();
  }

  Map<String, String> get _names => {
        for (final p in here.values)
          if (p['user'] is String) '${p['user']}': '${p['name'] ?? p['user']}',
      };

  /// What plays here follows the room: its song, at its second, playing or paused.
  void _follow() {
    final it = rooms.currentOf(state);
    if (it == null) {
      if (audio.player.playing) audio.player.pause().ignore();
      return;
    }
    final t = Track.fromJson(it['t']);
    if (t == null || !t.playable) return;
    final pos = rooms.position(state, now());
    audio.followSong(t, Duration(milliseconds: (pos * 1000).round()),
        playing: state['paused'] != true && !rooms.over(state),
        rate: (state['rate'] as double?) ?? 1.0,
        from: '${room?['name'] ?? 'Room'}');
  }

  /// A change to the room: made here at once, then on the server. Somebody else's came first: it is
  /// made again on top of theirs.
  Future<void> _change(rooms.Op op) async {
    if (room == null) return;
    final c = code;
    var base = state;
    var seen = version;
    for (var tries = 0; tries < 4; tries++) {
      final next = rooms.apply(base, [op]);
      if (jsonEncode(next) == jsonEncode(rooms.clean(base))) return; // it changes nothing
      state = next;
      _follow();
      notifyListeners();
      try {
        final got = asMap(await account.rpc('room_put', {'room': c, 'new_state': next, 'seen': seen}));
        if (room == null || code != c) return;
        if (got['ok'] == true) {
          version = toInt(got['version']);
          return;
        }
        base = rooms.clean(got['state']);
        seen = toInt(got['version']);
        state = base;
        version = seen;
      } on AccountError catch (e) {
        notices.add(e.message);
        return;
      }
    }
  }

  /// Songs into the room's queue (a party's guests ask the host instead).
  Future<void> addSongs(List<Track> songs, {bool next = false}) async {
    if (room == null) return;
    if (!canSteer) {
      for (final t in songs.take(5)) {
        await ask(t);
      }
      return;
    }
    final items = [
      for (final t in songs)
        if (shareable(t) case final Map<String, Object?> s) {'k': rooms.newKey(), 't': s, 'by': me},
    ];
    if (items.isEmpty) return;
    await _change(rooms.add(me, now(), items, nextUp: next));
  }

  Future<void> removeKey(String key) => _change(rooms.remove(me, key));

  Future<void> playKey(String key) {
    final it = rooms.currentOf(state);
    return _change(rooms.skip(me, now(), '${it?['k'] ?? ''}', key));
  }

  /// A party's guest asks the host for a song.
  Future<void> ask(Track t) async {
    final s = shareable(t);
    if (s == null) return;
    await account.rpc('room_ask', {'room': code, 'song': s});
    notices.add('Asked for ${t.title}');
  }

  Future<void> invite(String username) async {
    await account.rpc('room_invite', {'room': code, 'username': Account.cleanName(username)});
    notices.add('Invite sent to $username');
  }

  Future<void> _fetchMembers() async {
    try {
      final rows = await account.roomMembers(code);
      final profiles = await account.people([for (final r in rows) '${r['member']}']);
      for (final r in rows) {
        r['profile'] = profiles['${r['member']}'] ?? const {};
      }
      members = rows;
      notifyListeners();
    } on AccountError {
      // shown again with the next change
    }
  }

  Future<void> _fetchRequests() async {
    try {
      requests = await account.roomRequests(code);
      notifyListeners();
    } on AccountError {
      // next time
    }
  }

  /// The host of a party takes a guest's song into the queue (or not).
  Future<void> answer(Map<String, Object?> request, bool take) async {
    final id = toInt(request['id'], or: -1);
    if (take) {
      final t = Track.fromJson(request['song']);
      if (t != null) await addSongs([t]);
    }
    requests.removeWhere((r) => r['id'] == request['id']);
    notifyListeners();
    if (id >= 0) {
      try {
        await account.dropRequest(id);
      } on AccountError {
        // it goes with the room
      }
    }
  }

  // ------------------------------------------------------------ the keys, while together

  /// The keys (on the player, the notification, the headphones) go to the room. Listening along, any
  /// key means you take over: the friend's music stays, now as yours.
  bool steer(String key, [Duration? at]) {
    if (room == null) {
      if (friend.isNotEmpty) stopAlong(why: 'You took over. The music is yours again.');
      return false;
    }
    if (!canSteer) {
      notices.add('Only the host steers a party. Find a song and ask for it.');
      return true;
    }
    final it = rooms.currentOf(state);
    final k = '${it?['k'] ?? ''}';
    final pos = audio.player.position.inMilliseconds / 1000;
    switch (key) {
      case 'play':
        _change(rooms.play(me, now(), k, pos));
      case 'pause':
        _change(rooms.pause(me, now(), k, pos));
      case 'seek':
        _change(rooms.seek(me, now(), k, (at ?? Duration.zero).inMilliseconds / 1000));
      case 'next':
        final up = rooms.upcoming(state);
        if (up.isNotEmpty) _change(rooms.skip(me, now(), k, '${up.first['k']}'));
      case 'previous':
        final q = rooms.queueOf(state);
        final i = rooms.indexOf(state, k);
        if (pos > 4 || i <= 0) {
          _change(rooms.seek(me, now(), k, 0));
        } else {
          _change(rooms.skip(me, now(), k, '${q[i - 1]['k']}'));
        }
      case 'speed':
        _change(rooms.setRate(me, now(), (at ?? const Duration(seconds: 1)).inMilliseconds / 1000));
    }
    return true;
  }

  // ------------------------------------------------------------ what plays here, for friends

  Timer? _publishSoon;
  String _published = '';
  final _subs = <StreamSubscription<Object?>>[];

  /// What plays here goes to the account a moment after it changes (song, pause, a jump).
  void startSharing() {
    if (_subs.isNotEmpty) return;
    _subs.add(audio.mediaItem.listen((_) => _soon()));
    _subs.add(audio.playbackState
        .map((s) => '${s.playing}${s.processingState}${(s.updatePosition.inMilliseconds / 3000).round()}${s.speed}')
        .distinct()
        .listen((_) => _soon()));
  }

  void _soon() {
    _publishSoon?.cancel();
    _publishSoon = Timer(const Duration(milliseconds: 1500), _publish);
  }

  Future<void> _publish() async {
    final t = audio.current;
    if (!account.signedIn || !sharing() || friend.isNotEmpty || t == null || t.src != 'yt') return;
    await _clock();
    final p = audio.player;
    final loading = p.processingState == ProcessingState.loading || p.processingState == ProcessingState.buffering;
    final view = audio.view;
    final next = view.index + 1 < view.songs.length ? view.songs[view.index + 1] : null;
    final s = <String, Object?>{
      'src': t.src,
      'id': t.ref,
      'title': t.title,
      'artist': t.artist,
      'dur': t.dur,
      'pos': (p.position.inMilliseconds / 10).round() / 100,
      'playing': p.playing && !loading,
      'at': (now() * 100).round() / 100,
      'dev': device,
      'on': 'phone', // Mixtape on the computer shows this on Discord, "on the phone"
      if (t.art.startsWith('https://') && t.art.length <= 256) 'art': t.art,
      if (loading) 'loading': true,
      if (p.speed != 1.0) 'speed': p.speed,
      if (next != null && next.src == 'yt')
        'next': {'id': next.ref, 'title': next.title, 'artist': next.artist, 'dur': next.dur},
    };
    final key = jsonEncode({...s, 'at': 0, 'pos': p.playing ? 0 : s['pos']});
    if (key == _published && p.playing) return; // nothing new for friends
    _published = key;
    try {
      await account.publish(s);
    } on AccountError {
      _published = ''; // the next change tries again
    }
  }

  /// The switch in Settings was flipped: friends hear this phone from now on, or stop hearing it.
  void sharingChanged() {
    if (sharing()) {
      _soon();
    } else {
      unawaited(stopSharing());
    }
  }

  /// The app is closing for good (or sharing was switched off): friends stop hearing this phone.
  Future<void> stopSharing() async {
    _publishSoon?.cancel();
    if (account.signedIn && _published.isNotEmpty) {
      try {
        await account.unpublish(device);
      } on AccountError {
        // it runs out on its own
      }
    }
    _published = '';
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _publishSoon?.cancel();
    _friendPoll?.cancel();
    _roomPoll?.cancel();
    _link?.close();
    super.dispose();
  }
}
