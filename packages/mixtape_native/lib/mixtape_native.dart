/// The parts of Mixtape that live on the Android side: YouTube Music through NewPipe's extractor, and
/// the "Now playing" widget on the home screen.
library;

import 'package:flutter/services.dart';

/// Why YouTube won't give a song, as the codes the Android side sends: age, region, private, members,
/// busy (YouTube asks to slow down), gone, network, trouble.
class YouTubeError implements Exception {
  YouTubeError(this.why, this.detail);

  final String why;
  final String detail;

  @override
  String toString() => 'YouTubeError($why: $detail)';
}

class MixtapeNative {
  static const _channel = MethodChannel('mixtape/native');

  /// Songs on YouTube Music for a search: maps with id, title, artist, art and dur (seconds).
  static Future<List<Map<String, Object?>>> search(String query) async {
    try {
      final got = await _channel.invokeListMethod<Object?>('search', {'query': query});
      return _maps(got);
    } on PlatformException catch (e) {
      throw YouTubeError(e.code, e.message ?? '');
    }
  }

  /// Where a song's audio streams from right now: url, mime, bitrate, length (bytes, -1 when unknown),
  /// duration (seconds), agent (the User-Agent to fetch it with), expires (unix seconds), and related
  /// (songs like it, as search gives them).
  static Future<Map<String, Object?>> resolve(String id) async {
    try {
      final got = await _channel.invokeMapMethod<String, Object?>('resolve', {'id': id});
      final out = Map<String, Object?>.of(got ?? const {});
      out['related'] = _maps(out['related'] as List<Object?>?);
      return out;
    } on PlatformException catch (e) {
      throw YouTubeError(e.code, e.message ?? '');
    }
  }

  /// A music video's picture for video mode: url (video only, at most 480 lines), height, duration
  /// (seconds) and agent.
  static Future<Map<String, Object?>> video(String id) async {
    try {
      final got = await _channel.invokeMapMethod<String, Object?>('video', {'id': id});
      return Map<String, Object?>.of(got ?? const {});
    } on PlatformException catch (e) {
      throw YouTubeError(e.code, e.message ?? '');
    }
  }

  /// Hands text (a song's link) to the phone's share sheet. False where there is none (the iPhone
  /// copies it instead, see the app).
  static Future<bool> share(String text) async {
    try {
      await _channel.invokeMethod<void>('share', {'text': text});
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Tells the home screen widget what plays. [art] is a picture file on the phone ('' for none).
  static Future<void> widget({
    required String title,
    required String artist,
    required bool playing,
    String art = '',
  }) async {
    try {
      await _channel.invokeMethod<void>(
          'widget', {'title': title, 'artist': artist, 'playing': playing, 'art': art});
    } on MissingPluginException {
      // (in tests, and anywhere without the Android side)
    }
  }

  static List<Map<String, Object?>> _maps(List<Object?>? items) => [
        for (final x in items ?? const <Object?>[])
          if (x is Map) Map<String, Object?>.fromEntries(x.entries.map((e) => MapEntry('${e.key}', e.value))),
      ];
}
