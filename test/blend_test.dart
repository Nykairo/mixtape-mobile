import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/blend.dart';

void main() {
  test('every shape starts with the old song alone and ends with the new one alone', () {
    for (final shape in fadeShapes.keys) {
      final (out0, in0) = blendGains(shape, 0);
      final (out1, in1) = blendGains(shape, 1);
      expect(out0, closeTo(1, 1e-9), reason: shape);
      expect(in0, closeTo(0, 1e-9), reason: shape);
      expect(out1, closeTo(0, 1e-9), reason: shape);
      expect(in1, closeTo(1, 1e-9), reason: shape);
    }
  });

  test('smooth keeps the two as loud as one song all the way', () {
    for (var k = 0; k <= 20; k++) {
      final (out, into) = blendGains('smooth', k / 20);
      expect(sqrt(out * out + into * into), closeTo(1, 1e-9));
    }
  });

  test('DJ brings the next song up early, gentle lets the last one go first', () {
    final (djOut, djIn) = blendGains('dj', 0.6);
    expect(djIn, closeTo(1, 1e-9));
    expect(djOut, greaterThan(0.5));
    final (gOut, gIn) = blendGains('gentle', 0.35);
    expect(gIn, closeTo(0, 1e-9));
    expect(gOut, lessThan(0.9));
  });

  test('lengths from the settings file stay between 1 and 12 seconds, in halves', () {
    expect(fadeSecondsOf(null), 0);
    expect(fadeSecondsOf(0), 0);
    expect(fadeSecondsOf(-3), 0);
    expect(fadeSecondsOf(0.2), 1);
    expect(fadeSecondsOf(6.3), 6.5);
    expect(fadeSecondsOf(40), 12);
    expect(fadeSecondsOf('4'), 4);
    expect(fadeShapeOf('dj'), 'dj');
    expect(fadeShapeOf('wobbly'), 'smooth');
  });
}
