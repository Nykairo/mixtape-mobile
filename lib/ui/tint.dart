/// The color of the song that plays, taken from its cover: the big player's background and the little
/// player wear it, the way Spotify does. Read from a 24 pixel copy of the cover, once per cover.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../downloads.dart';
import '../look.dart';
import '../model.dart';

class Tint {
  /// The color of what plays now (the deck's own brown when there's no cover).
  static final now = ValueNotifier<Color>(_plain);

  static const _plain = Color(0xFF4A3426);
  static final _known = <String, Color>{};
  static String _for = '';

  /// The song changed: its color comes in a moment.
  static Future<void> follow(Track? t) async {
    if (t == null) return;
    final key = t.id;
    _for = key;
    final c = await of(t);
    if (_for == key) now.value = c ?? _plain;
  }

  static Future<Color?> of(Track t) {
    final file = Downloads.the.coverOf(t);
    return _read(t.id, file != null ? FileImage(file) : (t.artAt(120).isEmpty ? null : NetworkImage(t.artAt(120))));
  }

  /// The color of any picture on the internet (an album's cover, an artist's photo).
  static Future<Color?> ofUrl(String url) => _read(url, url.isEmpty ? null : NetworkImage(url));

  static Future<Color?> _read(String key, ImageProvider? source) async {
    final hit = _known[key];
    if (hit != null) return hit;
    if (source == null) return null;
    try {
      final img = await _load(ResizeImage(source, width: 24, height: 24));
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      if (data == null) return null;
      final c = _pick(data);
      _known[key] = c;
      while (_known.length > 100) {
        _known.remove(_known.keys.first);
      }
      return c;
    } on Object {
      return null;
    }
  }

  static Future<ui.Image> _load(ImageProvider provider) {
    final done = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    }, onError: (e, st) {
      if (!done.isCompleted) done.completeError(e, st);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    return done.future.timeout(const Duration(seconds: 10));
  }

  /// The cover's own color: its colorful pixels count most, grey and near black ones hardly at all. It
  /// comes out deep enough for light text to stay readable on it.
  static Color _pick(ByteData data) {
    var r = 0.0, g = 0.0, b = 0.0, total = 0.0;
    for (var k = 0; k + 3 < data.lengthInBytes; k += 4) {
      final c = Color.fromARGB(255, data.getUint8(k), data.getUint8(k + 1), data.getUint8(k + 2));
      final hsv = HSVColor.fromColor(c);
      final w = 0.05 + hsv.saturation * hsv.value * hsv.value;
      r += data.getUint8(k) * w;
      g += data.getUint8(k + 1) * w;
      b += data.getUint8(k + 2) * w;
      total += w;
    }
    if (total <= 0) return _plain;
    final avg = Color.fromARGB(255, (r / total).round(), (g / total).round(), (b / total).round());
    final hsv = HSVColor.fromColor(avg);
    return hsv.withSaturation(min(hsv.saturation * 1.15, 0.85)).withValue(min(max(hsv.value, 0.28), 0.5)).toColor();
  }
}

/// Builds with the color of what plays, sliding from one color to the next.
class TintBuilder extends StatelessWidget {
  const TintBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Color tint) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: Tint.now,
      builder: (context, target, _) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (context, c, _) => builder(context, c ?? target),
      ),
    );
  }
}

/// A darker or lighter shade of a color, keeping its hue.
Color shade(Color c, double value) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withValue(min(max(value, 0.0), 1.0)).toColor();
}

/// The file a cover was saved to, when it's on the phone (for showing it offline).
File? savedCover(Track t) => Downloads.the.coverOf(t);

/// A gradient from a tint down into the deck's black, for the top of a page.
LinearGradient fadeFrom(Color tint, {double strength = 0.9}) => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color.lerp(Look.bg, tint, strength)!, Look.bg],
    );
