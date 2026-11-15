/// Rooms: listening together, and listening parties, exactly like on the computer (rooms.py there), so a
/// phone and a computer can be in the same room.
///
/// A room is a queue everybody in it hears at the same second. Its whole state is one small document:
///
///     {"q": [{"k": "a1b2c3d4", "t": {song}, "by": "anna"}, ...]   the queue, the last few played included
///      "k": "a1b2c3d4"          the one playing ('' before anything did)
///      "pos": 12.5, "at": ...   where in it, in seconds, at that moment (on the server's clock)
///      "paused": false, "rate": 1.0
///      "by": "anna", "did": "skip"}   who changed it last, and how
///
/// Every change is a small function of the state, so a change that lost the race against somebody else's
/// is simply made again on top of theirs. Each one checks that it still makes sense there, which also
/// makes making it twice harmless.
library;

import 'dart:math';

typedef RoomState = Map<String, Object?>;
typedef RoomItem = Map<String, Object?>;
typedef Op = bool Function(RoomState s);

const most = 200; // songs waiting in a room at most
const played = 15; // songs already played that stay in it, for Previous and for the queue to show
const _keyChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
final _random = Random();

RoomState blank() => {'q': <RoomItem>[], 'k': '', 'pos': 0.0, 'at': 0.0, 'paused': true, 'rate': 1.0, 'by': '', 'did': ''};

double _num(Object? v, double or, double lo, double hi) {
  final f = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  if (f == null || !f.isFinite) return or;
  return min(hi, max(lo, f));
}

/// A state as it came from the server (or anyone in the room), made safe to use.
RoomState clean(Object? state) {
  final s = blank();
  if (state is! Map) return s;
  final q = <RoomItem>[];
  final seen = <String>{};
  final raw = state['q'];
  if (raw is List) {
    for (final it in raw.take(most + played)) {
      if (it is! Map) continue;
      final t = it['t'], k = it['k'];
      if (t is Map && t['id'] != null && t['ref'] != null && k is String && k.isNotEmpty && seen.add(k)) {
        q.add({'k': k.length > 16 ? k.substring(0, 16) : k, 't': Map<String, Object?>.from(t), 'by': _cut('${it['by'] ?? ''}', 40)});
      }
    }
  }
  s['q'] = q;
  s['k'] = q.any((it) => it['k'] == state['k']) ? state['k'] : '';
  s['pos'] = _num(state['pos'], 0, 0, 86400);
  s['at'] = _num(state['at'], 0, 0, 1e11);
  s['paused'] = state['paused'] != false;
  s['rate'] = _num(state['rate'], 1, 0.25, 4);
  s['by'] = _cut('${state['by'] ?? ''}', 40);
  s['did'] = _cut('${state['did'] ?? ''}', 20);
  return s;
}

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

String newKey() => List.generate(8, (_) => _keyChars[_random.nextInt(_keyChars.length)]).join();

List<RoomItem> queueOf(RoomState s) => (s['q'] as List).cast<RoomItem>();

String keyOf(RoomState s) => '${s['k'] ?? ''}';

int indexOf(RoomState s, String key) => queueOf(s).indexWhere((it) => it['k'] == key);

RoomItem? currentOf(RoomState s) {
  final k = keyOf(s).isEmpty ? -1 : indexOf(s, keyOf(s));
  return k >= 0 ? queueOf(s)[k] : null;
}

/// What comes after the song playing (everything, before anything played).
List<RoomItem> upcoming(RoomState s) {
  if (keyOf(s).isEmpty) return List.of(queueOf(s));
  final k = indexOf(s, keyOf(s));
  return k >= 0 ? queueOf(s).sublist(k + 1) : [];
}

/// The last song played to its end and nothing came after.
bool over(RoomState s) => s['did'] == 'end' && upcoming(s).isEmpty;

/// Where the song playing is at [now] (the server's clock), in seconds.
double position(RoomState s, double now) {
  if (keyOf(s).isEmpty) return 0;
  final pos = s['pos'] as double;
  if (s['paused'] == true) return pos;
  return pos + max(0.0, now - (s['at'] as double)) * (s['rate'] as double);
}

void _trim(RoomState s) {
  final k = indexOf(s, keyOf(s));
  var q = queueOf(s);
  if (k > played) q = q.sublist(k - played);
  if (q.length > most + played) q = q.sublist(0, most + played);
  s['q'] = q;
}

void _start(RoomState s, String key, double now, String by, String did) {
  s.addAll({'k': key, 'pos': 0.0, 'at': now, 'paused': false, 'by': by, 'did': did});
  _trim(s);
}

// ---------------------------------------------------------------- the changes

/// Play on from [pos] in the song with this key (from wherever it is, should another be playing).
Op play(String by, double now, String key, double pos) => (s) {
      if (keyOf(s).isEmpty) return false;
      if (s['did'] == 'end' && keyOf(s) == key) {
        _start(s, key, now, by, 'play'); // played to its end: Play starts it over
        return true;
      }
      final p = keyOf(s) == key ? pos : position(s, now);
      if (s['paused'] != true && (position(s, now) - p).abs() < 0.05) return false;
      s.addAll({'pos': p, 'at': now, 'paused': false, 'by': by, 'did': 'play'});
      return true;
    };

Op pause(String by, double now, String key, double pos) => (s) {
      if (keyOf(s).isEmpty || s['paused'] == true) return false;
      s.addAll({'pos': keyOf(s) == key ? pos : position(s, now), 'at': now, 'paused': true, 'by': by, 'did': 'pause'});
      return true;
    };

Op seek(String by, double now, String key, double pos) => (s) {
      if (keyOf(s) != key) return false; // that song isn't playing anymore: the jump was meant for it
      if (s['did'] == 'end') s['paused'] = false;
      s.addAll({'pos': max(0.0, pos), 'at': now, 'by': by, 'did': 'seek'});
      return true;
    };

/// From one song to another. Made only if the song it started from is still playing, so two people
/// pressing Next at once skip one song, not two.
Op skip(String by, double now, String fromKey, String toKey) => (s) {
      if (keyOf(s) != fromKey || indexOf(s, toKey) < 0) return false;
      _start(s, toKey, now, by, 'skip');
      return true;
    };

/// The song with this key played to its end here: the next one starts, or the room stops after the last.
Op ended(String by, double now, String key) => (s) {
      if (keyOf(s) != key || s['did'] == 'end') return false;
      final k = indexOf(s, key);
      final q = queueOf(s);
      if (k >= 0 && k < q.length - 1) {
        _start(s, '${q[k + 1]['k']}', now, by, 'next');
      } else {
        s.addAll({'pos': position(s, now), 'at': now, 'paused': true, 'by': by, 'did': 'end'});
      }
      return true;
    };

/// Songs into the queue: right after the one playing or at the end. A song still waiting moves up
/// instead of coming twice. With nothing playing, or [playNow], the first one starts.
Op add(String by, double now, List<RoomItem> fresh, {bool nextUp = false, bool playNow = false}) => (s) {
      final news = [
        for (final it in fresh)
          if (indexOf(s, '${it['k']}') < 0) it,
      ];
      if (news.isEmpty) return false;
      final ids = {for (final it in news) (it['t'] as Map)['id']};
      final q = queueOf(s);
      final k = keyOf(s).isEmpty ? -1 : indexOf(s, keyOf(s));
      final head = q.sublist(0, k + 1);
      final rest = [
        for (final it in q.sublist(k + 1))
          if (!ids.contains((it['t'] as Map)['id'])) it,
      ];
      var all = nextUp || playNow ? [...head, ...news, ...rest] : [...head, ...rest, ...news];
      if (all.length - head.length > most) all = all.sublist(0, head.length + most);
      s['q'] = all;
      if (playNow || keyOf(s).isEmpty || over(s) || s['did'] == 'end') {
        _start(s, '${news.first['k']}', now, by, playNow ? 'play_now' : 'add');
      } else {
        s.addAll({'by': by, 'did': 'add'});
      }
      return true;
    };

/// A waiting song out of the queue (the one playing stays: skip it instead).
Op remove(String by, String key) => (s) {
      final k = indexOf(s, key);
      if (k < 0 || keyOf(s) == key) return false;
      s['q'] = List.of(queueOf(s))..removeAt(k);
      s.addAll({'by': by, 'did': 'remove'});
      return true;
    };

/// A waiting song up to right after the one playing.
Op moveNext(String by, String key) => (s) {
      final k = indexOf(s, key);
      final now = keyOf(s).isEmpty ? -1 : indexOf(s, keyOf(s));
      if (k < 0 || k <= now + 1) return false;
      final q = List.of(queueOf(s));
      final it = q.removeAt(k);
      q.insert(now + 1, it);
      s['q'] = q;
      s.addAll({'by': by, 'did': 'move'});
      return true;
    };

Op setRate(String by, double now, double rate) => (s) {
      final r = _num(rate, 1, 0.25, 4);
      if (((s['rate'] as double) - r).abs() < 1e-3) return false;
      s.addAll({'pos': position(s, now), 'at': now, 'rate': r, 'by': by, 'did': 'speed'});
      return true;
    };

/// A copy of the state with these changes made on it, in order.
RoomState apply(Object? state, List<Op> ops) {
  final s = clean(state);
  for (final op in ops) {
    op(s);
  }
  return s;
}

/// A few words about the last change, when somebody else made it ('' for your own, or nothing to say).
String said(RoomState s, String me, [Map<String, String> names = const {}]) {
  final did = '${s['did']}';
  final by = names[s['by']] ?? '${s['by']}';
  final it = currentOf(s);
  final title = it != null ? '“${(it['t'] as Map)['title']}”' : 'the song';
  if (did == 'end') return 'That was the last song. Add more to keep going.';
  if (by.isEmpty || s['by'] == me) return '';
  return switch (did) {
    'pause' => '$by paused',
    'play' => '$by pressed play',
    'seek' => '$by jumped in $title',
    'skip' || 'play_now' => '$by put on $title',
    'add' => '$by added a song',
    'remove' => '$by took a song out of the queue',
    'move' => '$by moved a song up',
    'speed' => '$by set the speed to ${s['rate']}×',
    _ => '',
  };
}
