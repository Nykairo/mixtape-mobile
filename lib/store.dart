/// Where the phone keeps what it knows: small JSON files in the app's own folder. A file is written next
/// to its old self and then moved over it, so a phone that switches off halfway keeps the old one.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class Store {
  Store._(this.dir);

  final Directory dir;

  static Store? _the;

  static Store get the {
    final s = _the;
    if (s == null) throw StateError('Store.open() first');
    return s;
  }

  /// Opens the app's folder (once; every later call gives the same store). [at] is for tests.
  static Future<Store> open({Directory? at}) async {
    final s = _the;
    if (s != null) return s;
    final dir = at ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return _the = Store._(dir);
  }

  File file(String name) => File('${dir.path}/$name');

  /// The JSON in a file, or null when it isn't there or can't be read.
  Future<Object?> read(String name) async {
    try {
      return jsonDecode(await file(name).readAsString());
    } on Object {
      return null;
    }
  }

  Future<void> write(String name, Object? json) async {
    final f = file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> delete(String name) async {
    try {
      await file(name).delete();
    } on FileSystemException {
      // it wasn't there
    }
  }
}

/// Saves something a little after it last changed, so a burst of changes is one write. [now] writes
/// what waits right away (when the app goes to the background).
class LaterSave {
  LaterSave(this.name, this.what, {this.delay = const Duration(seconds: 2)});

  final String name;
  final Object? Function() what;
  final Duration delay;
  Timer? _timer;
  Future<void> _last = Future.value();

  void soon() {
    _timer?.cancel();
    _timer = Timer(delay, now);
  }

  Future<void> now() {
    final waiting = _timer != null;
    _timer?.cancel();
    _timer = null;
    if (!waiting) return _last;
    final json = what();
    return _last = _last.then((_) => Store.the.write(name, json)).catchError((Object _) {});
  }
}
