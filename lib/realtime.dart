/// Hearing about changes the moment they happen: Supabase Realtime over one WebSocket (the Phoenix
/// protocol, version 1.0.0, plain JSON), the way the computer does it (realtime.py there). Rooms and
/// listening along use it: a room's state, who is in it, and a friend's song as it changes.
///
/// It says hello every 10 seconds and expects an answer before the next one: a line that went dead
/// without saying so (another Wi-Fi, the phone waking up) is cut and opened again. Every new connection
/// gets a fresh sign-in token; when the connection breaks it comes back after 1, 2, 5 and then every
/// 10 seconds, joining again whatever it had joined.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _backoff = [1, 2, 5, 10];

class RtChannel {
  RtChannel._(this.link, String name, this.changes, this.presence) : topic = 'realtime:$name';

  final RtLink link;
  final String topic;
  final List<Map<String, String>> changes;

  /// Our key among the people there; empty: we don't show up.
  final String presence;

  Map<String, Object?>? meta;
  String joinRef = '';
  bool ready = false;
  bool joining = false;
  int tries = 0;
  final Map<String, Map<String, Object?>> here = {};

  /// A database change: {type, record, old_record, ...}.
  void Function(Map<String, Object?> data)? onChange;

  /// Who is there now, by key.
  void Function(Map<String, Map<String, Object?>> people)? onPeople;

  /// A message somebody else sent to everybody on the channel.
  void Function(String event, Map<String, Object?> payload)? onHeard;

  /// Whether changes reach us right now.
  void Function(bool live)? onLive;

  /// Shows up among the people there with this little bit about us (sent again after a reconnect).
  void track(Map<String, Object?> about) {
    meta = about;
    if (ready && presence.isNotEmpty) link._push(this, 'presence', {'type': 'presence', 'event': 'track', 'payload': about});
  }

  /// A message for everybody else on the channel right now (kept nowhere: who isn't there doesn't get it).
  void say(String event, Map<String, Object?> payload) {
    if (ready) link._push(this, 'broadcast', {'type': 'broadcast', 'event': event, 'payload': payload});
  }

  void leave() => link._drop(this);

  void _setReady(bool on) {
    if (on == ready) return;
    ready = on;
    onLive?.call(on);
  }

  Map<String, Object?> _joinPayload(String token) => {
        'config': {
          'broadcast': {'ack': false, 'self': false},
          'presence': {'enabled': presence.isNotEmpty, 'key': presence},
          'postgres_changes': changes,
          'private': false,
        },
        if (token.isNotEmpty) 'access_token': token,
      };

  void _people(Map<String, Object?> joins, Map<String, Object?> leaves, {bool replace = false}) {
    if (replace) here.clear();
    for (final k in leaves.keys) {
      here.remove(k);
    }
    joins.forEach((k, v) {
      final metas = v is Map ? v['metas'] : null;
      if (metas is List && metas.isNotEmpty && metas.last is Map) here[k] = Map<String, Object?>.from(metas.last as Map);
    });
    onPeople?.call(Map.of(here));
  }
}

class RtLink {
  RtLink(String server, String key, this.tokens)
      : url = '${server.replaceFirst('https://', 'wss://')}/realtime/v1/websocket?apikey=$key&vsn=1.0.0';

  final String url;

  /// A fresh sign-in token (renewed shortly before the old one runs out).
  final Future<String> Function() tokens;

  final List<RtChannel> channels = [];
  WebSocket? _ws;
  bool up = false;
  bool _closing = false;
  bool _opening = false;
  int _ref = 0;
  int _tries = 0;
  String _token = '';
  String _helloRef = '';
  Timer? _beat;
  Timer? _again;
  Timer? _renew;

  RtChannel channel(String name, {List<Map<String, String>> changes = const [], String presence = ''}) {
    final ch = RtChannel._(this, name, changes, presence);
    channels.add(ch);
    _closing = false;
    if (up) {
      _join(ch);
    } else {
      _open();
    }
    _renew ??= Timer.periodic(const Duration(minutes: 1), (_) => _freshToken());
    return ch;
  }

  void _drop(RtChannel ch) {
    if (!channels.remove(ch)) return;
    if (up && ch.ready) _send(ch.topic, 'phx_leave', const {}, joinRef: ch.joinRef);
    ch._setReady(false);
    if (channels.isEmpty) close();
  }

  void close() {
    _closing = true;
    _beat?.cancel();
    _again?.cancel();
    _renew?.cancel();
    _renew = null;
    final ws = _ws;
    _ws = null;
    up = false;
    ws?.close().ignore();
  }

  Future<void> _freshToken() async {
    try {
      final t = await tokens();
      if (t == _token) return;
      _token = t;
      for (final ch in channels) {
        if (ch.ready) _push(ch, 'access_token', {'access_token': t});
      }
    } on Object {
      // offline: the connection says so on its own
    }
  }

  Future<void> _open() async {
    if (_closing || _opening || channels.isEmpty || _ws != null) return;
    _opening = true;
    try {
      _token = await tokens();
      final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 15));
      if (_closing) {
        ws.close().ignore();
        return;
      }
      _ws = ws;
      up = true;
      _tries = 0;
      _helloRef = '';
      ws.listen((m) => _heard(ws, m), onDone: () => _closed(ws), onError: (Object _) => _closed(ws), cancelOnError: true);
      _beat?.cancel();
      _beat = Timer.periodic(const Duration(seconds: 10), (_) => _hello());
      for (final ch in channels) {
        _join(ch);
      }
    } on Object {
      _retry();
    } finally {
      _opening = false;
    }
  }

  void _closed(WebSocket ws) {
    if (ws != _ws) return;
    _ws = null;
    up = false;
    _beat?.cancel();
    _helloRef = '';
    for (final ch in channels) {
      ch.joining = false;
      ch._setReady(false);
    }
    if (!_closing) _retry();
  }

  void _retry() {
    if (_closing || (_again?.isActive ?? false)) return;
    _again = Timer(Duration(seconds: _backoff[_tries < _backoff.length ? _tries : _backoff.length - 1]), _open);
    _tries++;
  }

  void _hello() {
    final ws = _ws;
    if (ws == null) return;
    if (_helloRef.isNotEmpty) {
      // the last hello was never answered: the line is dead, whatever the socket thinks
      _closed(ws);
      ws.close().ignore();
      return;
    }
    _helloRef = '${++_ref}';
    _send('phoenix', 'heartbeat', const {}, ref: _helloRef);
  }

  void _join(RtChannel ch) {
    ch.joinRef = '${++_ref}';
    ch.joining = true;
    _send(ch.topic, 'phx_join', ch._joinPayload(_token), joinRef: ch.joinRef, ref: ch.joinRef);
  }

  /// A channel the server turned down or closed: joined again after a pause, with a fresh token.
  void _rejoin(RtChannel ch) {
    ch.joining = false;
    ch._setReady(false);
    ch.tries++;
    Timer(Duration(seconds: _backoff[ch.tries < _backoff.length ? ch.tries : _backoff.length - 1]), () async {
      if (!channels.contains(ch) || !up) return;
      await _freshToken();
      if (!ch.ready && !ch.joining) _join(ch);
    });
  }

  void _push(RtChannel ch, String event, Map<String, Object?> payload) =>
      _send(ch.topic, event, payload, joinRef: ch.joinRef);

  void _send(String topic, String event, Map<String, Object?> payload, {String joinRef = '', String ref = ''}) {
    final ws = _ws;
    if (ws == null || !up) return;
    ws.add(jsonEncode({
      'topic': topic,
      'event': event,
      'payload': payload,
      'ref': ref.isEmpty ? '${++_ref}' : ref,
      if (joinRef.isNotEmpty) 'join_ref': joinRef,
    }));
  }

  void _heard(WebSocket ws, Object? message) {
    if (ws != _ws || message is! String) return;
    Object? msg;
    try {
      msg = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (msg is! Map) return;
    final topic = msg['topic'], event = msg['event'];
    final payload = msg['payload'] is Map ? Map<String, Object?>.from(msg['payload'] as Map) : <String, Object?>{};
    if (topic == 'phoenix') {
      if (event == 'phx_reply' && msg['ref'] == _helloRef) _helloRef = '';
      return;
    }
    for (final ch in List.of(channels)) {
      if (ch.topic != topic) continue;
      if (event == 'phx_reply' && msg['ref'] == ch.joinRef) {
        if (payload['status'] == 'ok') {
          ch.joining = false;
          ch.tries = 0;
          ch._setReady(true);
          final meta = ch.meta;
          if (meta != null && ch.presence.isNotEmpty) ch.track(meta);
        } else {
          _rejoin(ch);
        }
      } else if (event == 'postgres_changes') {
        final data = payload['data'];
        if (data is Map) ch.onChange?.call(Map<String, Object?>.from(data));
      } else if (event == 'broadcast') {
        final inner = payload['payload'];
        ch.onHeard?.call('${payload['event'] ?? ''}', inner is Map ? Map<String, Object?>.from(inner) : const {});
      } else if (event == 'presence_state') {
        ch._people(payload, const {}, replace: true);
      } else if (event == 'presence_diff') {
        final joins = payload['joins'], leaves = payload['leaves'];
        ch._people(joins is Map ? Map<String, Object?>.from(joins) : const {},
            leaves is Map ? Map<String, Object?>.from(leaves) : const {});
      } else if (event == 'phx_error' || event == 'phx_close') {
        final jr = msg['join_ref'];
        if (jr != null && jr != ch.joinRef) continue; // about an older join of this channel
        _rejoin(ch);
      } else if (event == 'system' && payload['status'] == 'error') {
        _rejoin(ch);
      }
    }
  }
}
