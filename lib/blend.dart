/// How one song blends into the next, the same four ways as on the computer (blend.py there).
///
/// A crossfade is two volume curves over the same few seconds: the song that ends goes down one while
/// the next song comes up the other.
///
///   smooth   equal power. Sine up, cosine down: together the two are as loud as one song all the way
///   linear   two straight lines, with a small dip in the middle
///   dj       the next song is at full strength by 60 %, and the last one only starts to fall at 40 %
///   gentle   the last song is mostly gone before the next one rises, a soft valley between the two
library;

import 'dart:math';

const fadeShapes = {'smooth': 'Smooth', 'linear': 'Linear', 'dj': 'DJ', 'gentle': 'Gentle'};

/// What each shape does, in a line for the settings.
const fadeShapeAbout = {
  'smooth': 'The two together stay as loud as one song all the way through',
  'linear': 'Two straight lines, a little quieter in the middle',
  'dj': 'The next song is up early and the last one drops late',
  'gentle': 'The last song is mostly gone before the next one rises',
};

/// The longest a blend can be, in seconds.
const longestFade = 12.0;

/// A quarter of a sine: 0 at the start, 1 at the end, gentle at both.
double _rise(double f) => sin(f.clamp(0.0, 1.0) * pi / 2);

/// (the song that ends, the song that starts) at fraction [f] of the blend, each from 0 to 1.
(double, double) blendGains(String shape, double f) {
  f = f.clamp(0.0, 1.0);
  return switch (shape) {
    'linear' => (1 - f, f),
    'dj' => (_rise(1 - max(0.0, f - 0.4) / 0.6), _rise(f / 0.6)),
    'gentle' => (_rise(1 - f / 0.65), _rise((f - 0.35) / 0.65)),
    _ => (_rise(1 - f), _rise(f)),
  };
}

String fadeShapeOf(Object? value) => value is String && fadeShapes.containsKey(value) ? value : 'smooth';

/// A crossfade length from the settings file: 1 to 12 seconds in half seconds, or 0 for none.
double fadeSecondsOf(Object? value) {
  final v = value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
  if (v == null || !v.isFinite || v <= 0) return 0;
  return ((v * 2).round() / 2).clamp(1.0, longestFade);
}
