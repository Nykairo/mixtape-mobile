/// YouTube's "most replayed" curve, put to two uses, the same way the computer does (core.py): where a
/// song's best half minute starts (Samples), and where a song starts inside its music video (video mode).
/// A curve is a list of (start, length, how much) in seconds, the last from 0 to 1.
library;

import 'dart:math';

typedef Heat = List<(double, double, double)>;

/// Where the best [length] seconds of a song start: the stretch its listeners replay the most. With no
/// curve to go by, a third of the way in, which is past the intro and the first verse of most songs.
double bestPart(Heat heat, double dur, {double length = 30}) {
  final last = dur - length - 4;
  if (last <= 0) return 0;
  if (heat.isEmpty) return (min(last, max(12.0, dur / 3)) * 10).round() / 10;
  var best = -1.0, at = 0.0;
  for (final (start, _, _) in heat) {
    if (start > last) break;
    var total = 0.0;
    for (final (a, len, v) in heat) {
      total += v * max(0.0, min(a + len, start + length) - max(a, start));
    }
    if (total > best) {
      best = total;
      at = start;
    }
  }
  return (at * 10).round() / 10;
}

List<double> _perSecond(Heat heat, double length) {
  final out = List<double>.filled(max(0, length.floor()), 0);
  for (final (a, len, v) in heat) {
    for (var s = max(0, a.floor()); s < min(out.length, (a + len).floor() + 1); s++) {
      out[s] = v;
    }
  }
  return out;
}

/// How many seconds into its music video a song starts, read from the two curves. People replay the same
/// parts of a song (the chorus, the drop) wherever they hear it, so the curves match once the song's is
/// moved by the length of the video's intro. Null without both curves, or when no shift makes them match
/// well enough to trust (a true match lines up at 0.9 and better).
int? lineUp(Heat song, Heat clip, double songLen, double clipLen) {
  if (song.isEmpty || clip.isEmpty || songLen < 30 || clipLen < 30) return null;
  final a = _perSecond(song, songLen), b = _perSecond(clip, clipLen);
  final skip = max(6, (songLen * 0.05).floor()); // everybody "replays" the first seconds: that's where they start
  var best = -1.0;
  var at = 0;
  for (var shift = -10; shift <= (clipLen - songLen).floor() + 10; shift++) {
    final xs = <double>[], ys = <double>[];
    for (var s = skip; s < a.length - 3; s++) {
      if (s + shift >= 0 && s + shift < b.length) {
        xs.add(a[s]);
        ys.add(b[s + shift]);
      }
    }
    if (xs.length < songLen * 0.6) continue;
    final mx = xs.reduce((p, q) => p + q) / xs.length;
    final my = ys.reduce((p, q) => p + q) / ys.length;
    var cov = 0.0, vx = 0.0, vy = 0.0;
    for (var k = 0; k < xs.length; k++) {
      cov += (xs[k] - mx) * (ys[k] - my);
      vx += (xs[k] - mx) * (xs[k] - mx);
      vy += (ys[k] - my) * (ys[k] - my);
    }
    if (vx > 0 && vy > 0) {
      final r = cov / sqrt(vx * vy);
      if (r > best) {
        best = r;
        at = shift;
      }
    }
  }
  return best >= 0.8 ? at : null;
}
