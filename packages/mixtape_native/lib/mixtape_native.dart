/// The parts of Mixtape that live on the Android side: YouTube Music through NewPipe's extractor, and
/// the widgets on the home screen.
library;

import 'dart:async';

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

  /// Hands a picture (a PNG file) to the phone's share sheet, with a line of [text] for apps that take
  /// one: saved to the gallery, sent to a friend, posted. False where there's no share sheet for it.
  static Future<bool> shareImage(String path, {String text = ''}) async {
    try {
      return await _channel.invokeMethod<bool>('shareImage', {'path': path, 'text': text}) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// A picture picked from the phone, made into a profile picture: its middle square, 256 pixels, a
  /// JPEG in base64. Null when nothing was picked, or where there's no picker.
  static Future<String?> pickPicture() async {
    try {
      return await _channel.invokeMethod<String>('pickPicture');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// The phone: its maker (one word: 'xiaomi' also for Redmi and POCO, 'transsion' for Tecno, Infinix
  /// and itel), brand and model, the Android version, whether battery saving leaves Mixtape alone
  /// ('batteryFree') and whether memory is short ('lowRam'). Empty where there's no Android side.
  static Future<Map<String, Object?>> phone() async {
    try {
      final got = await _channel.invokeMethod<Map<Object?, Object?>>('phone');
      return {for (final e in (got ?? const <Object?, Object?>{}).entries) '${e.key}': e.value};
    } on MissingPluginException {
      return const {};
    } on PlatformException {
      return const {};
    }
  }

  /// Asks Android, with its own little dialog, to leave Mixtape out of battery saving.
  static Future<bool> askBatteryFree() => _yes('askBatteryFree');

  /// Opens the maker's own page for apps in the background (Autostart on a Xiaomi, App launch on a
  /// Huawei, ...), or Mixtape's page in Settings where the maker has none.
  static Future<bool> openMakerSettings() => _yes('makerSettings');

  static Future<bool> _yes(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Tells the home screen widgets what plays: title, artist, playing, art (a picture file on the phone,
  /// '' for none), liked, shuffle, position and duration (milliseconds), index and count (where in the
  /// queue), tape, colors (the tape's, for the cassette) and track (the song itself, for a like tapped
  /// on a widget while the app is closed).
  static Future<void> widget(Map<String, Object?> playing) async {
    try {
      await _channel.invokeMethod<void>('widget', playing);
    } on MissingPluginException {
      // (in tests, and anywhere without the Android side)
    }
  }

  /// The tapes for the "My tapes" widget, first one first: id, name, songs, colors and liked (the liked
  /// songs, which aren't a tape of their own).
  static Future<void> shelf(List<Map<String, Object?>> tapes) async {
    try {
      await _channel.invokeMethod<void>('shelf', tapes);
    } on MissingPluginException {
      // as above
    }
  }

  static final _taps = StreamController<String>.broadcast();
  static bool _listening = false;

  /// What's tapped on a widget for the app to do: `like`, `shuffle`, or `tape:` and a tape's id (open that
  /// tape and play it).
  static Stream<String> get widgetTaps {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'widget' && call.arguments is String) _taps.add(call.arguments as String);
        return null;
      });
    }
    return _taps.stream;
  }

  /// The tape a widget opened Mixtape with (`tape:` and its id), once; null when the app was opened otherwise.
  static Future<String?> widgetLaunch() async {
    try {
      return await _channel.invokeMethod<String>('widgetLaunch');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Likes tapped on a widget while the app was closed: a JSON list of {track, liked}.
  static Future<String> widgetWaiting() async {
    try {
      return await _channel.invokeMethod<String>('widgetWaiting') ?? '[]';
    } on MissingPluginException {
      return '[]';
    } on PlatformException {
      return '[]';
    }
  }

  static List<Map<String, Object?>> _maps(List<Object?>? items) => [
        for (final x in items ?? const <Object?>[])
          if (x is Map) Map<String, Object?>.fromEntries(x.entries.map((e) => MapEntry('${e.key}', e.value))),
      ];
}
