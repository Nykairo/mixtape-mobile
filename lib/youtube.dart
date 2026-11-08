/// YouTube for the rest of the app. On Android NewPipe's extractor does the work (packages/mixtape_native)
/// and InnerTube steps in when it can't; on the iPhone InnerTube does it all.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:mixtape_native/mixtape_native.dart';

import 'innertube.dart';

export 'package:mixtape_native/mixtape_native.dart' show YouTubeError;

class YouTube {
  static final _inner = InnerTube(
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
      return await _inner.search(query);
    } on InnerTubeError catch (e) {
      throw YouTubeError(e.why, e.detail);
    }
  }

  /// Where a song's audio streams from right now (see MixtapeNative.resolve for the keys).
  static Future<Map<String, Object?>> resolve(String id) async {
    YouTubeError? first;
    if (Platform.isAndroid) {
      try {
        return await MixtapeNative.resolve(id);
      } on YouTubeError catch (e) {
        if (_final.contains(e.why)) rethrow;
        first = e;
      }
    }
    try {
      return await _inner.resolve(id);
    } on InnerTubeError catch (e) {
      // when both went wrong, the more telling answer: a reason about the song itself, or else the
      // first one (from the way that usually works)
      if (first == null || _final.contains(e.why)) throw YouTubeError(e.why, e.detail);
      throw first;
    }
  }
}
