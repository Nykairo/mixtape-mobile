/// The Mixtape Account on the phone: the same account as on the computer (a user name and a password),
/// with the tapes, the liked songs and the pictures on the tapes. It talks to the account's server the
/// way the desktop app does (account.py there), over plain HTTPS.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

const accountUrl = 'https://uxvtmfevflddyeogohdh.supabase.co';
const accountKey = 'sb_publishable_eqQFY5n-DJUq9LAVSapa5Q_huh6FfrJ';
const _mail = 'users.mixtape.invalid';
const _file = 'account.json';

final _name = RegExp(r'^[a-z0-9_.]{3,20}$');
final picturePattern = RegExp(r'^[0-9a-f]{20}\.(png|jpg)$');

/// What went wrong, in words for the person. [why] is a short key, the same ones the computer uses.
class AccountError implements Exception {
  AccountError(this.why, [this.detail = '']);

  final String why;
  final String detail;

  static const words = {
    'name': 'User names are 3 to 20 letters, digits, dots or underscores.',
    'password': 'Passwords need at least 8 characters.',
    'taken': 'That user name is taken already.',
    'busy': 'Too many new accounts from here in the last hour. Try again a little later.',
    'wrong': "That user name and password don't go together.",
    'signin': 'Your sign-in ran out. Sign in to your Mixtape Account again.',
    'offline': "Mixtape can't reach its server right now. Check the internet connection.",
    'server': "Mixtape's server had a problem. Try again in a moment.",
  };

  String get message => words[why] ?? words['server']!;

  @override
  String toString() => detail.isEmpty ? message : '$message ($detail)';
}

/// A signed-in account: who it is and the tokens that prove it.
class Session {
  Session({
    required this.uid,
    required this.username,
    required this.display,
    required this.access,
    required this.refresh,
    required this.expires,
  });

  final String uid;
  String username;
  String display;
  String access;
  String refresh;

  /// Unix seconds when [access] runs out.
  double expires;

  Map<String, Object?> toJson() =>
      {'uid': uid, 'username': username, 'display': display, 'access': access, 'refresh': refresh, 'expires': expires};

  static Session? fromJson(Object? j) {
    if (j is! Map || j['uid'] is! String || j['refresh'] is! String) return null;
    return Session(
      uid: j['uid'] as String,
      username: '${j['username'] ?? ''}',
      display: '${j['display'] ?? j['username'] ?? ''}',
      access: '${j['access'] ?? ''}',
      refresh: j['refresh'] as String,
      expires: (j['expires'] is num) ? (j['expires'] as num).toDouble() : 0,
    );
  }
}

double _now() => DateTime.now().millisecondsSinceEpoch / 1000;

/// The tapes table knows a tape by a short hash of its name (the same as the desktop's tape_id).
String tapeId(String name) => sha1.convert(utf8.encode(name)).toString().substring(0, 24);

class Account {
  Account({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  Session? session;
  Future<String>? _renewing;

  bool get signedIn => session != null;

  /// The account this phone signed in to last time, if any.
  Future<void> load() async {
    session = Session.fromJson(await Store.the.read(_file));
  }

  Future<void> _keep(Session? s) async {
    session = s;
    if (s == null) {
      await Store.the.delete(_file);
    } else {
      await Store.the.write(_file, s.toJson());
    }
  }

  static String cleanName(String username) {
    var n = username.trim().toLowerCase();
    while (n.startsWith('@')) {
      n = n.substring(1);
    }
    return n;
  }

  // ------------------------------------------------------------ requests

  Future<(int, Object?)> _call(String method, String path,
      {Object? body, String token = '', String prefer = '', Duration timeout = const Duration(seconds: 15)}) async {
    final req = http.Request(method, Uri.parse(accountUrl + path));
    req.headers['apikey'] = accountKey;
    req.headers['Accept'] = 'application/json';
    req.headers['User-Agent'] = 'Mixtape-Android';
    if (token.isNotEmpty) req.headers['Authorization'] = 'Bearer $token';
    if (prefer.isNotEmpty) req.headers['Prefer'] = prefer;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      final res = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
      Object? data;
      if (res.bodyBytes.isNotEmpty) {
        try {
          data = jsonDecode(utf8.decode(res.bodyBytes));
        } on FormatException {
          data = null;
        }
      }
      return (res.statusCode, data);
    } on TimeoutException catch (e) {
      throw AccountError('offline', '$e');
    } on http.ClientException catch (e) {
      throw AccountError('offline', e.message);
    } on IOException catch (e) {
      throw AccountError('offline', '$e'); // a broken TLS handshake on a bad network, say
    }
  }

  AccountError _error(int status, Object? data) {
    final why = data is Map ? data['error'] : null;
    if (why is String && AccountError.words.containsKey(why)) return AccountError(why);
    if (status == 401 || status == 403) return AccountError('signin');
    final detail = data is Map ? '${data['message'] ?? data['msg'] ?? ''}' : '';
    return AccountError('server', '$status $detail'.trim());
  }

  Session _sessionFrom(Object? data, String username) {
    if (data is! Map || data['access_token'] is! String) throw AccountError('server', 'no token');
    final user = data['user'] is Map ? data['user'] as Map : const {};
    final meta = user['user_metadata'] is Map ? user['user_metadata'] as Map : const {};
    final name = meta['username'] is String ? meta['username'] as String : username;
    final life = data['expires_in'] is num ? (data['expires_in'] as num).toDouble() : 3600.0;
    return Session(
      uid: '${user['id'] ?? ''}',
      username: name,
      display: name,
      access: data['access_token'] as String,
      refresh: '${data['refresh_token'] ?? ''}',
      expires: _now() + life,
    );
  }

  // ------------------------------------------------------------ signing in

  Future<Session> signIn(String username, String password) async {
    final name = cleanName(username);
    if (!_name.hasMatch(name)) throw AccountError('wrong');
    final (status, data) = await _call('POST', '/auth/v1/token?grant_type=password',
        body: {'email': '$name@$_mail', 'password': password});
    if (status == 400) throw AccountError('wrong');
    if (status != 200) throw _error(status, data);
    final s = _sessionFrom(data, name);
    final me = await _get('/rest/v1/profiles?id=eq.${s.uid}&select=username,display_name', token: s.access);
    if (me.isNotEmpty) {
      s.username = '${me.first['username'] ?? s.username}';
      final shown = me.first['display_name'];
      s.display = shown is String && shown.isNotEmpty ? shown : s.username;
    }
    await _keep(s);
    return s;
  }

  Future<Session> signUp(String username, String password, {String display = ''}) async {
    final name = cleanName(username);
    if (!_name.hasMatch(name)) throw AccountError('name');
    if (password.length < 8) throw AccountError('password');
    final shown = display.trim();
    final (status, data) = await _call('POST', '/functions/v1/signup',
        body: {'username': name, 'password': password, 'display_name': shown.length > 40 ? shown.substring(0, 40) : shown},
        timeout: const Duration(seconds: 30));
    if (status != 200) throw _error(status, data);
    return signIn(name, password);
  }

  Future<void> signOut() async {
    final s = session;
    if (s != null) {
      try {
        await _call('POST', '/auth/v1/logout', body: const {}, token: s.access, timeout: const Duration(seconds: 6));
      } on AccountError {
        // offline: the tokens are forgotten here all the same
      }
    }
    await _keep(null);
  }

  /// A fresh access token, renewed shortly before it runs out. Two callers at once share one renewal.
  Future<String> token() {
    final s = session;
    if (s == null) return Future.error(AccountError('signin'));
    if (s.expires - _now() > 90) return Future.value(s.access);
    return _renewing ??= _renew(s).whenComplete(() {
      _renewing = null;
    });
  }

  Future<String> _renew(Session s) async {
    final (status, data) =
        await _call('POST', '/auth/v1/token?grant_type=refresh_token', body: {'refresh_token': s.refresh});
    if (status == 400 || status == 401 || status == 403) {
      await _keep(null); // the refresh token was used up or revoked: this phone is signed out now
      throw AccountError('signin');
    }
    if (status != 200) throw _error(status, data);
    final fresh = _sessionFrom(data, s.username);
    s
      ..access = fresh.access
      ..refresh = fresh.refresh.isEmpty ? s.refresh : fresh.refresh
      ..expires = fresh.expires;
    await _keep(s);
    return s.access;
  }

  // ------------------------------------------------------------ REST

  Future<List<Map<String, Object?>>> _get(String path,
      {String token = '', Duration timeout = const Duration(seconds: 15)}) async {
    final (status, data) = await _call('GET', path, token: token.isEmpty ? await this.token() : token, timeout: timeout);
    if (status != 200) throw _error(status, data);
    return [
      if (data is List)
        for (final row in data)
          if (row is Map) Map<String, Object?>.from(row),
    ];
  }

  Future<void> _put(String table, Object rows, String conflict, {Duration timeout = const Duration(seconds: 15)}) async {
    final (status, data) = await _call('POST', '/rest/v1/$table?on_conflict=$conflict',
        body: rows, token: await token(), prefer: 'resolution=merge-duplicates,return=minimal', timeout: timeout);
    if (status != 200 && status != 201 && status != 204) throw _error(status, data);
  }

  // ------------------------------------------------------------ tapes, liked songs, pictures

  /// The account's tapes, oldest change first: rows with name, data, deleted and updated_at. With
  /// [since] (an updated_at seen before, in the server's clock) only the ones changed after it.
  Future<List<Map<String, Object?>>> pullTapes({String since = ''}) async {
    final s = session;
    if (s == null) return const [];
    final after = since.isEmpty ? '' : '&updated_at=gt.${Uri.encodeComponent(since)}';
    return _get('/rest/v1/tapes?owner=eq.${s.uid}$after&select=name,data,deleted,updated_at&order=updated_at.asc',
        timeout: const Duration(seconds: 30));
  }

  /// Tapes up: {name: data}, in pieces of 50 for a big library.
  Future<void> pushTapes(Map<String, Map<String, Object?>> tapes) async {
    final s = session;
    if (s == null || tapes.isEmpty) return;
    final rows = [
      for (final e in tapes.entries)
        {
          'owner': s.uid,
          'tape_id': tapeId(e.key),
          'name': e.key.length > 200 ? e.key.substring(0, 200) : e.key,
          'data': e.value,
          'deleted': false,
        },
    ];
    for (var k = 0; k < rows.length; k += 50) {
      await _put('tapes', rows.sublist(k, k + 50 > rows.length ? rows.length : k + 50), 'owner,tape_id',
          timeout: const Duration(seconds: 30));
    }
  }

  /// A deleted tape stays in the account as deleted, so the other devices let go of it too.
  Future<void> dropTape(String name) async {
    final s = session;
    if (s == null) return;
    await _put('tapes', [
      {'owner': s.uid, 'tape_id': tapeId(name), 'name': name, 'data': const {}, 'deleted': true},
    ], 'owner,tape_id');
  }

  /// The account's library row: {'data': {...}, 'updated_at': ...}, empty when there is none yet.
  Future<Map<String, Object?>> pullLibrary() async {
    final s = session;
    if (s == null) return const {};
    final rows = await _get('/rest/v1/libraries?owner=eq.${s.uid}&select=data,updated_at');
    return rows.isEmpty ? const {} : rows.first;
  }

  Future<void> pushLibrary(Map<String, Object?> data) async {
    final s = session;
    if (s == null) return;
    await _put('libraries', {'owner': s.uid, 'data': data}, 'owner', timeout: const Duration(seconds: 30));
  }

  /// Pictures from the tapes' decorations, by name: {name: bytes}. A picture's name is made from the
  /// picture itself, so what arrives is checked against it.
  Future<Map<String, List<int>>> pullPictures(Iterable<String> names) async {
    final s = session;
    final want = {
      for (final n in names)
        if (picturePattern.hasMatch(n)) n,
    }.toList()
      ..sort();
    final out = <String, List<int>>{};
    if (s == null) return out;
    for (var k = 0; k < want.length; k += 8) {
      final part = want.sublist(k, k + 8 > want.length ? want.length : k + 8).join(',');
      final rows = await _get('/rest/v1/pictures?owner=eq.${s.uid}&name=in.($part)&select=name,data',
          timeout: const Duration(seconds: 60));
      for (final r in rows) {
        final name = '${r['name'] ?? ''}';
        List<int> raw;
        try {
          raw = base64.decode('${r['data'] ?? ''}');
        } on FormatException {
          continue;
        }
        if (want.contains(name) && sha1.convert(raw).toString().substring(0, 20) == name.substring(0, 20)) {
          out[name] = raw;
        }
      }
    }
    return out;
  }

  void close() => _http.close();
}
