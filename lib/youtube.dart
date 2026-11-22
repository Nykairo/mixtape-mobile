/// YouTube for the rest of the app. InnerTube asks YouTube Music for everything it shows and finds where
/// songs stream from; on Android NewPipe's extractor (packages/mixtape_native) searches and stands by for
/// the streams. On the iPhone InnerTube does it all.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:mixtape_native/mixtape_native.dart';

import 'innertube.dart';

export 'package:mixtape_native/mixtape_native.dart' show YouTubeError;

class YouTube {
  /// InnerTube for everything YouTube Music shows (music.dart reads its answers). The tests put one
  /// in that answers from files.
  static InnerTube inner = InnerTube(
    language: ui.PlatformDispatcher.instance.locale.languageCode,
    country: ui.PlatformDispatcher.instance.locale.countryCode ?? 'US',
  );

  /// Answers the other way can't change: the song is what it is.
  static const _final = {'age', 'region', 'private', 'members', 'gone'};

  /// Songs on YouTube Music for a search: maps with id, title, artist, art and dur.
  static Future<List<Map<String, Object?>>> search(String query) async {
    if (Platform.isAndroid) {
      try {
        final found = await MixtapeNative.search(query);
        if (found.isNotEmpty) return found;
      } on YouTubeError catch (e) {
        if (_final.contains(e.why)) rethrow;
      }
    }
    try {
      return await inner.search(query);
    } on InnerTubeError catch (e) {
      throw YouTubeError(e.why, e.detail);
    }
  }

  /// How long the quick way gets before NewPipe is asked as well.
  static const hedge = Duration(milliseconds: 900);

  /// Where a song's audio streams from right now (see MixtapeNative.resolve for the keys). The visionOS
  /// app's request goes first: one small answer, mostly back in a few tenths of a second. On Android
  /// NewPipe's extractor is asked as well when that hasn't answered within [hedge], or went wrong; the
  /// first good answer plays. When both go wrong, the more telling reason comes back (one about the song
  /// itself).
  static Future<Map<String, Object?>> resolve(String id) {
    final quick = _quick(id);
    if (!Platform.isAndroid) return quick;
    return _Race(id, quick).done.future;
  }

  static Future<Map<String, Object?>> _quick(String id) async {
    try {
      return await inner.resolve(id);
    } on InnerTubeError catch (e) {
      throw YouTubeError(e.why, e.detail);
    }
  }

  /// Songs like this one (a radio from it), for when the queue runs out.
  static Future<List<Map<String, Object?>>> related(String id) async {
    try {
      return await inner.related(id);
    } on InnerTubeError catch (e) {
      throw YouTubeError(e.why, e.detail);
    }
  }
}

/// The quick way and NewPipe asked about the same song: NewPipe only when the quick way is slow or went
/// wrong, and the first good answer plays (see YouTube.resolve).
class _Race {
  _Race(this.id, Future<Map<String, Object?>> quick) {
    quick.then(_ok, onError: _failed);
    Timer(YouTube.hedge, _askNative);
  }

  final String id;
  final done = Completer<Map<String, Object?>>();
  final _errors = <YouTubeError>[];
  var _asking = 1;
  var _native = false;

  void _ok(Map<String, Object?> m) {
    if (!done.isCompleted) done.complete(m);
  }

  void _failed(Object e) {
    _asking--;
    _errors.add(e is YouTubeError ? e : YouTubeError('trouble', '$e'));
    if (done.isCompleted) return;
    _askNative(); // (when it isn't asked yet)
    if (_asking > 0) return;
    // both went wrong: a reason about the song itself tells the most
    done.completeError(_errors.firstWhere((x) => YouTube._final.contains(x.why), orElse: () => _errors.last));
  }

  void _askNative() {
    if (_native || done.isCompleted) return;
    _native = true;
    _asking++;
    MixtapeNative.resolve(id).then(_ok, onError: _failed);
  }
}
