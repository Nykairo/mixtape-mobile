/// The cassette, drawn the way the desktop app draws it (widgets.py and decor.py there): the plastic
/// shell, the label with its stripes and handwriting, the sticky note on the corner and, in the window,
/// the two reels that turn while the music plays and trade tape as the song goes on.
library;

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'look.dart';

const ratio = 1.574; // a compact cassette is 100.4 x 63.8 mm

/// Where every part of a cassette sits when drawn into a rectangle.
class Geo {
  Geo._(this.x, this.y, this.w, this.h);

  factory Geo(Rect r) {
    final w = min(r.width, r.height * ratio);
    final h = w / ratio;
    return Geo._(r.left + (r.width - w) / 2, r.top + (r.height - h) / 2, w, h);
  }

  final double x, y, w, h;

  Rect get shell => Rect.fromLTWH(x, y, w, h);
  Rect get label => Rect.fromLTWH(x + w * 0.06, y + h * 0.075, w * 0.88, h * 0.63);
  double get _cy => label.top + label.height * 0.735;
  Rect get window {
    final ww = w * 0.54, wh = h * 0.205;
    return Rect.fromLTWH(x + (w - ww) / 2, _cy - wh / 2, ww, wh);
  }

  List<Offset> get hubs => [Offset(x + w * 0.31, _cy), Offset(x + w * 0.69, _cy)];
  double get hubR => w * 0.05;
  double get _packMin => hubR * 1.22;
  double get _packMax => w * 0.13;

  /// Tape pack radii. The amount of tape stays the same, so the two areas trade places.
  (double, double) packs(double progress) {
    final f = progress.clamp(0.0, 1.0);
    final a = _packMin * _packMin, b = _packMax * _packMax;
    return (sqrt(a + (b - a) * (1 - f)), sqrt(a + (b - a) * f));
  }

  /// Where the sticky note sits: center, side and tilt (each tape tilts its own way).
  (Offset, double, double) sticky(int slot) =>
      (Offset(x + w * 0.113, y + h * 0.178), w * 0.205, -3.5 - (slot % 5) * 1.25);

  /// The cover glued onto the label as a photo, when there's room for one.
  Rect? cover() {
    if (w < 200) return null;
    final L = label;
    final s = L.height * 0.42;
    return Rect.fromLTWH(L.right - L.width * 0.03 - s, L.top + L.height * 0.055, s, s);
  }
}

// ---------------------------------------------------------------- the materials (decor.py)

const _shells = <String, (int, int)>{
  'black': (0xFF2E2621, 255),
  'smoke': (0xFF4A4442, 150),
  'clear': (0xFFCDDBE4, 58),
  'white': (0xFFE8E3D8, 255),
  'red': (0xFFB2342A, 255),
  'orange': (0xFFD9692A, 255),
  'yellow': (0xFFE2B33B, 255),
  'mint': (0xFF56B190, 255),
  'blue': (0xFF335F9E, 255),
  'purple': (0xFF684A9C, 255),
  'pink': (0xFFDD86A4, 255),
};
const _inks = {
  'blue': 0xFF25428E,
  'black': 0xFF1F1A16,
  'red': 0xFFB3261E,
  'green': 0xFF1F6B45,
  'purple': 0xFF5B2A86,
  'white': 0xFFF6F1E7,
};
const _hubs = {
  'white': 0xFFECE4D4,
  'black': 0xFF36302B,
  'red': 0xFFC9392E,
  'blue': 0xFF3D6FD1,
  'gold': 0xFFD9AE4F,
  'mint': 0xFF5CC5A2,
};
const _tapes = {'brown': 0xFF3B2618, 'black': 0xFF18181B, 'chrome': 0xFF6B6E78, 'gold': 0xFF7D5C22, 'red': 0xFF5E1B17};
const _screws = {'silver': 0xFFB9B4AC, 'gold': 0xFFD6B25E, 'black': 0xFF26221F};
const _notes = {
  'yellow': 0xFFF8E17A,
  'pink': 0xFFF7B9C9,
  'blue': 0xFFBCDCF5,
  'green': 0xFFC8EAB2,
  'orange': 0xFFFFC68E,
  'lilac': 0xFFD8C7F3,
};
const _sticky = Color(0xFFF8E17A);
const _stickyPink = Color(0xFFF7B9C9);

/// A color from a table by name, or a '#rrggbb' given directly, or null.
Color? _pick(Object? key, Map<String, int> table) {
  if (key is! String) return null;
  final v = table[key];
  if (v != null) return Color(v);
  if (key.length == 7 && key.startsWith('#')) {
    final n = int.tryParse(key.substring(1), radix: 16);
    if (n != null) return Color(0xFF000000 | n);
  }
  return null;
}

Color _alpha(Color c, int a) => c.withAlpha(a);

Color _darker(Color c, double f) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withValue((hsv.value / f).clamp(0.0, 1.0)).toColor();
}

Color _lighter(Color c, double f) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withValue((hsv.value * f).clamp(0.0, 1.0)).toColor();
}

bool _light(Color c) => (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.58;

/// What a tape looks like: the label paper, its ink and pen, the shell and its parts.
class TapeLook {
  TapeLook({required this.slot, Map<String, Object?>? design}) : d = design ?? const {} {
    final paperSlot = d['paper'] is int ? d['paper'] as int : slot;
    final (paper, stripes, ink) = paperFor(paperSlot);
    this.paper = paper;
    this.stripes = stripes;
    this.ink = _pick(d['ink'], _inks) ?? ink;
    pen = d['pen'] is String ? d['pen'] as String : 'hand';
    final (shellColor, alpha) = _shells[d['shell']] ?? _shells['black']!;
    shell = Color(shellColor);
    shellAlpha = alpha;
    hub = _pick(d['hub'], _hubs);
    tape = _pick(d['tape'], _tapes) ?? Look.tape;
    finish = d['finish'] is String ? d['finish'] as String : '';
    stripeStyle = d['stripes'] is String ? d['stripes'] as String : 'classic';
    final screws = d['screws'];
    noScrews = screws == 'none';
    screw = _pick(screws, _screws) ??
        (_light(shell) || shellAlpha < 255 ? const Color(0xFFB9B4AC) : mix(shell, Colors.white, 0.2));
    cornerHidden = d['corner_hidden'] == true;
    final hue = HSVColor.fromColor(paper);
    note = _pick(d['corner_color'], _notes) ??
        (hue.hue / 360 >= 0.08 && hue.hue / 360 <= 0.19 && hue.saturation > 0.35 ? _stickyPink : _sticky);
  }

  final int slot;
  final Map<String, Object?> d;
  final String stock = Look.stock; // the tape stock colors slot 0's stripes
  late final Color paper;
  late final List<Color> stripes;
  late final Color ink;
  late final String pen;
  late final Color shell;
  late final int shellAlpha;
  late final Color? hub;
  late final Color tape;
  late final String finish;
  late final String stripeStyle;
  late final bool noScrews;
  late final Color screw;
  late final bool cornerHidden;
  late final Color note;

  bool get seeThrough => shellAlpha < 255;

  /// The label's writing in the chosen pen.
  TextStyle titleStyle(double px) => switch (pen) {
        'marker' => TextStyle(fontFamily: 'Barlow Condensed', fontSize: px * 0.82, fontWeight: FontWeight.w700),
        'type' => TextStyle(fontFamily: 'monospace', fontSize: px * 0.6, fontWeight: FontWeight.w600),
        'print' => TextStyle(
            fontFamily: 'Barlow Condensed', fontSize: px * 0.66, fontWeight: FontWeight.w600, letterSpacing: px * 0.04),
        _ => TextStyle(fontFamily: 'Covered By Your Grace', fontSize: px, height: 1.0),
      };

  String titleText(String t) => pen == 'marker' || pen == 'print' ? t.toUpperCase() : t;
}

TextPainter _text(String s, TextStyle style, {double? width, int lines = 1, TextAlign align = TextAlign.left}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: lines,
    ellipsis: '…',
  );
  tp.layout(maxWidth: width ?? double.infinity);
  return tp;
}

// ---------------------------------------------------------------- the still parts

/// Everything but the reels: drawn once, and again only when the tape or its size changes.
class CassettePainter extends CustomPainter {
  CassettePainter({
    required this.look,
    this.title = '',
    this.side = 'A',
    this.leftNote = '',
    this.rightNote = '',
    this.sticky = '',
    this.progress = 0.35,
    this.cover = false,
  });

  final TapeLook look;
  final String title;
  final String side;
  final String leftNote;
  final String rightNote;
  final String sticky;
  final double progress; // only see-through shells show it here (the packs through the plastic)
  final bool cover; // a cover photo goes on the label (drawn on top by the widget), the title makes room

  @override
  void paint(Canvas canvas, Size size) {
    final g = Geo(Offset.zero & size);
    final w = g.w;
    final detail = w >= 120;
    final note = sticky.trim().isNotEmpty && detail && !look.cornerHidden;
    _shell(canvas, g, detail);

    // label paper
    final L = g.label;
    final lr = Radius.circular(w * 0.016);
    canvas.drawRRect(
        RRect.fromRectAndRadius(L, lr),
        Paint()
          ..shader = ui.Gradient.linear(L.topCenter, L.bottomCenter, [look.paper, mix(look.paper, Colors.black, 0.07)]));
    canvas.drawRRect(
        RRect.fromRectAndRadius(L, lr),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _alpha(Colors.black, 60));
    _stripes(canvas, L);

    // side box and the ruled line for writing (moved along when the sticky note covers the corner)
    final lw = L.width, lh = L.height;
    final (nc, ns, tilt) = g.sticky(look.slot);
    var boxX = L.left + lw * 0.028;
    if (note) boxX = max(boxX, nc.dx + ns * 0.58 + lw * 0.018);
    final box = Rect.fromLTWH(boxX, L.top + lh * 0.09, lh * 0.2, lh * 0.2);
    final textLeft = box.right + lw * 0.03;
    final textRight = cover && g.cover() != null ? L.right - lw * 0.06 - lh * 0.42 : L.right - lw * 0.035;
    final lineY = L.top + lh * 0.355;
    final trect = Rect.fromLTRB(textLeft, L.top + lh * 0.03, textRight, lineY - lh * 0.01);
    canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, w * 0.0035)
          ..color = _alpha(look.ink, 170));
    final sideText = _text(side,
        TextStyle(fontFamily: 'Barlow Condensed', fontWeight: FontWeight.w700, fontSize: box.height * 0.82, color: look.ink, height: 1));
    sideText.paint(canvas, Offset(box.center.dx - sideText.width / 2, box.center.dy - sideText.height / 2 + 0.5));
    sideText.dispose();
    canvas.drawLine(Offset(trect.left, lineY), Offset(L.right - lw * 0.035, lineY),
        Paint()
          ..strokeWidth = 1
          ..color = _alpha(look.ink, 45));
    if (title.isNotEmpty) {
      final text = look.titleText(title);
      var px = lh * 0.23;
      TextPainter tp;
      while (true) {
        tp = _text(text, look.titleStyle(px).copyWith(color: look.ink));
        if (tp.width <= trect.width || px <= lh * 0.15) break;
        tp.dispose();
        px -= 1;
      }
      if (tp.width > trect.width) {
        tp.dispose();
        tp = _text(text, look.titleStyle(px).copyWith(color: look.ink), width: trect.width);
      }
      final drop = look.pen == 'hand' ? 0.0 : lh * 0.012;
      tp.paint(canvas, Offset(trect.left, trect.bottom - drop - tp.height));
      tp.dispose();
    }

    // printed notes either side of the window
    if (detail && (leftNote.isNotEmpty || rightNote.isNotEmpty)) {
      final zoneTop = L.top + lh * 0.605;
      final lz = Rect.fromLTRB(L.left + lw * 0.025, zoneTop, g.window.left - lw * 0.025, L.bottom);
      final rz = Rect.fromLTRB(g.window.right + lw * 0.025, zoneTop, L.right - lw * 0.025, L.bottom);
      for (final (t, zone, right) in [(leftNote, lz, false), (rightNote, rz, true)]) {
        if (t.isEmpty) continue;
        var px = max(7.0, lh * 0.1);
        TextPainter tp;
        while (true) {
          tp = _text(t, TextStyle(fontFamily: 'Barlow Condensed', fontWeight: FontWeight.w600, fontSize: px,
              letterSpacing: 0.5, color: _alpha(look.ink, 200), height: 1));
          if (tp.width <= zone.width || px <= 5.5) break;
          tp.dispose();
          px -= 0.5;
        }
        if (tp.width > zone.width) {
          tp.dispose();
          tp = _text(t, TextStyle(fontFamily: 'Barlow Condensed', fontWeight: FontWeight.w600, fontSize: px,
              color: _alpha(look.ink, 200), height: 1), width: zone.width);
        }
        tp.paint(canvas, Offset(right ? zone.right - tp.width : zone.left, zone.center.dy - tp.height / 2));
        tp.dispose();
      }
    }

    // the window: the dark inside of the shell, seen through it
    final win = g.window;
    final wr = Radius.circular(win.height * 0.3);
    canvas.drawRRect(
        RRect.fromRectAndRadius(win, wr),
        Paint()
          ..shader = ui.Gradient.linear(win.topCenter, win.bottomCenter, const [Color(0xFF0A0806), Color(0xFF1B1511)]));

    if (cover) {
      final c = g.cover();
      if (c != null) {
        // the white photo paper the cover is glued on with (the picture itself comes on top)
        canvas.save();
        canvas.translate(c.center.dx, c.center.dy);
        canvas.rotate(-4 * pi / 180);
        final loc = Rect.fromCenter(center: Offset.zero, width: c.width, height: c.height);
        canvas.drawRect(loc.shift(const Offset(1.2, 1.6)), Paint()..color = _alpha(Colors.black, 70));
        canvas.drawRect(loc, Paint()..color = const Color(0xFFFBF8F1));
        canvas.restore();
      }
    }
    if (note) _note(canvas, nc, ns, tilt);
  }

  void _stripes(Canvas canvas, Rect L) {
    final lw = L.width, lh = L.height;
    var top = L.top + lh * 0.40;
    final s = look.stripes;
    switch (look.stripeStyle) {
      case 'none':
        return;
      case 'band':
        canvas.drawRect(Rect.fromLTWH(L.left, top, lw, lh * 0.185), Paint()..color = s[0]);
        return;
      case 'lines':
        for (var k = 0; k < 3; k++) {
          canvas.drawRect(Rect.fromLTWH(L.left, top + lh * (0.02 + k * 0.06), lw, lh * 0.022), Paint()..color = s[k]);
        }
        return;
      case 'fade':
        canvas.drawRect(
            Rect.fromLTWH(L.left, top, lw, lh * 0.185),
            Paint()
              ..shader = ui.Gradient.linear(Offset(L.left, 0), Offset(L.right, 0), [s[0], s[1], s[2]], const [0, 0.5, 1]));
        return;
    }
    for (final (c, frac) in [(s[0], 0.085), (s[1], 0.06), (s[2], 0.04)]) {
      canvas.drawRect(Rect.fromLTWH(L.left, top, lw, lh * frac), Paint()..color = c);
      top += lh * frac;
    }
  }

  /// The plastic body, its bottom bump with the tape openings, and the screws. See-through shells
  /// show the tape packs, the rollers and the tape running along the bottom.
  void _shell(Canvas canvas, Geo g, bool detail) {
    final x = g.x, y = g.y, w = g.w, h = g.h;
    final base = look.shell;
    final alpha = look.shellAlpha;
    final see = look.seeThrough;
    final rad = Radius.circular(w * 0.045);
    final body = RRect.fromRectAndRadius(g.shell, rad);
    if (see) _internals(canvas, g, body);
    canvas.drawRRect(
        body,
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, y), Offset(0, y + h),
              [_alpha(mix(base, Colors.white, 0.07), alpha), _alpha(mix(base, Colors.black, 0.28), alpha)]));
    canvas.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, w * 0.004)
          ..color = _alpha(Colors.black, see ? 130 : 110));
    canvas.drawRRect(
        RRect.fromRectAndRadius(g.shell.deflate(1.5), Radius.circular(max(0.0, w * 0.045 - 1))),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _alpha(Colors.white, see ? 58 : 16));
    if ((see || look.finish == 'gloss') && detail) {
      canvas.drawRRect(
          body,
          Paint()
            ..shader = ui.Gradient.linear(Offset(x, y), Offset(x + w * 0.4, y + h),
                [_alpha(Colors.white, see ? 40 : 52), _alpha(Colors.white, 0)], const [0, 0.35]));
      if (look.finish == 'gloss') {
        canvas.drawRRect(
            body,
            Paint()
              ..shader = ui.Gradient.linear(Offset(x + w * 0.55, y), Offset(x + w * 0.75, y + h),
                  [_alpha(Colors.white, 0), _alpha(Colors.white, 22), _alpha(Colors.white, 0)], const [0, 0.5, 1]));
      }
    }
    if (look.finish == 'glitter' && detail) _glitter(canvas, g, base);

    // the bottom bump with the tape openings
    final t = y + h * 0.79, b = y + h - max(1.0, w * 0.004);
    final trap = Path()
      ..moveTo(x + w * 0.25, t)
      ..lineTo(x + w * 0.75, t)
      ..lineTo(x + w * 0.79, b)
      ..lineTo(x + w * 0.21, b)
      ..close();
    canvas.drawPath(trap, Paint()..color = _alpha(mix(base, Colors.black, 0.38), see ? min(255, alpha + 40) : 255));
    canvas.drawPath(
        trap,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _alpha(Colors.white, see ? 40 : 14));
    final hole = Paint()..color = Look.bg;
    final hr = w * 0.021;
    for (final fx in const [0.335, 0.665]) {
      canvas.drawCircle(Offset(x + w * fx, y + h * 0.895), hr, hole);
    }
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x + w * 0.46, y + h * 0.86, w * 0.08, h * 0.07), const Radius.circular(1.5)),
        hole);

    // screws
    if (detail && !look.noScrews) {
      final sr = w * 0.0135;
      final metal = Paint()..color = look.screw;
      final rim = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _alpha(Colors.black, 120);
      final slot = Paint()
        ..strokeWidth = max(1.0, sr * 0.35)
        ..color = _alpha(Colors.black, 150);
      for (final (fx, fy) in const [(0.045, 0.07), (0.955, 0.07), (0.045, 0.93), (0.955, 0.93), (0.5, 0.745)]) {
        final c = Offset(x + w * fx, y + h * fy);
        canvas.drawCircle(c, sr, metal);
        canvas.drawCircle(c, sr, rim);
        canvas.drawLine(Offset(c.dx - sr * 0.6, c.dy - sr * 0.3), Offset(c.dx + sr * 0.6, c.dy + sr * 0.3), slot);
      }
    }
  }

  void _internals(Canvas canvas, Geo g, RRect body) {
    final x = g.x, y = g.y, w = g.w, h = g.h;
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(g.shell, Paint()..color = _alpha(const Color(0xFF0F0C0A), look.shellAlpha > 100 ? 150 : 70));
    final (left, right) = g.packs(progress);
    final hubs = g.hubs;
    for (final (c, r) in [(hubs[0], left), (hubs[1], right)]) {
      canvas.drawCircle(c, r, Paint()..shader = tapePack(c, r, look.tape));
      canvas.drawCircle(c, g.hubR, Paint()..color = look.hub ?? const Color(0xFFE9E0CF));
    }
    final rl = Offset(x + w * 0.155, y + h * 0.86), rr = Offset(x + w * 0.845, y + h * 0.86);
    final low = y + h * 0.915;
    final band = Paint()
      ..strokeWidth = max(1.0, w * 0.009)
      ..color = mix(look.tape, Colors.white, 0.1);
    canvas.drawLine(Offset(hubs[0].dx - left * 0.92, hubs[0].dy + left * 0.3), rl, band);
    canvas.drawLine(Offset(hubs[1].dx + right * 0.92, hubs[1].dy + right * 0.3), rr, band);
    canvas.drawLine(Offset(rl.dx + w * 0.01, low), Offset(rr.dx - w * 0.01, low), band);
    final roller = Paint()..color = const Color(0xFFDCD6CB);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _alpha(Colors.black, 120);
    for (final c in [rl, rr]) {
      canvas.drawCircle(c, w * 0.02, roller);
      canvas.drawCircle(c, w * 0.02, rim);
    }
    canvas.drawRect(Rect.fromLTWH(x + w * 0.47, low - h * 0.035, w * 0.06, h * 0.03), Paint()..color = const Color(0xFFCFBF9A));
    canvas.restore();
  }

  /// Fine sparkles pressed into the plastic, always the same ones for the same size.
  void _glitter(Canvas canvas, Geo g, Color base) {
    final x = g.x, y = g.y, w = g.w, h = g.h;
    var seed = (w * 7).toInt();
    if (seed == 0) seed = 1;
    final lightDot = Paint()..color = _alpha(Colors.white, 150);
    final darkDot = Paint()..color = _alpha(mix(base, Colors.white, 0.45), 120);
    final label = g.label;
    for (var k = 0; k < (w * 0.9).toInt(); k++) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      final fx = (seed % 10000) / 10000;
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      final fy = (seed % 10000) / 10000;
      final p = Offset(x + w * (0.02 + 0.96 * fx), y + h * (0.03 + 0.94 * fy));
      if (label.contains(p)) continue; // the label is paper: no sparkle on it
      canvas.drawCircle(p, max(0.6, w * (k % 3 != 0 ? 0.0018 : 0.0026)), k % 3 == 0 ? lightDot : darkDot);
    }
  }

  /// A square note stuck on with its glue strip at the top, so the bottom edge lifts a little.
  void _note(Canvas canvas, Offset c, double s, double tilt) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(tilt * pi / 180);
    final r = Rect.fromCenter(center: Offset.zero, width: s, height: s);
    for (final (k, a) in const [(3.0, 14), (2.0, 20), (1.0, 34)]) {
      final d = s * 0.014 * k;
      final sh = Path()
        ..moveTo(r.left + d * 0.3, r.top + s * 0.2)
        ..lineTo(r.right + d * 0.8, r.top + s * 0.2)
        ..lineTo(r.right + d * 0.9, r.bottom + d * 1.5)
        ..quadraticBezierTo(r.center.dx, r.bottom + d * 0.6, r.left + d * 0.5, r.bottom + d * 1.2)
        ..close();
      canvas.drawPath(sh, Paint()..color = _alpha(Colors.black, a));
    }
    final base = look.note;
    canvas.drawRect(
        r,
        Paint()
          ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter,
              [_darker(base, 1.07), _darker(base, 1.03), base, _lighter(base, 1.02), _darker(base, 1.04)], const [0, 0.16, 0.2, 0.86, 1]));
    canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.6, s * 0.01)
          ..color = _alpha(const Color(0xFF5A4410), 40));
    final curl = Path()
      ..moveTo(r.right, r.bottom - s * 0.34)
      ..lineTo(r.right, r.bottom)
      ..lineTo(r.right - s * 0.34, r.bottom)
      ..close();
    canvas.drawPath(
        curl,
        Paint()
          ..shader = ui.Gradient.linear(Offset(r.right - s * 0.32, r.bottom - s * 0.32), r.bottomRight,
              [_alpha(Colors.white, 0), _alpha(Colors.white, 46), _alpha(Colors.black, 18)], const [0, 0.75, 1]));
    final box = Rect.fromLTRB(r.left + s * 0.11, r.top + s * 0.2, r.right - s * 0.09, r.bottom - s * 0.1);
    var px = box.height * 0.56;
    TextPainter tp;
    while (true) {
      tp = _text(sticky.trim(), TextStyle(fontFamily: 'Covered By Your Grace', fontSize: px, height: 0.78, color: Look.ink),
          width: box.width, lines: 3, align: TextAlign.center);
      if ((!tp.didExceedMaxLines && tp.height <= box.height * 1.1) || px <= max(5.0, box.height * 0.2)) break;
      tp.dispose();
      px -= 0.5;
    }
    tp.paint(canvas, Offset(box.left + (box.width - tp.width) / 2, box.center.dy - tp.height / 2));
    tp.dispose();
    canvas.restore();
  }

  @override
  bool shouldRepaint(CassettePainter old) =>
      old.look != look ||
      old.title != title ||
      old.side != side ||
      old.leftNote != leftNote ||
      old.rightNote != rightNote ||
      old.sticky != sticky ||
      old.cover != cover ||
      (look.seeThrough && (old.progress - progress).abs() > 0.01);
}

/// Wound tape: nearly black by the hub, its own color further out, a lighter line where the last turns
/// catch the light, and a dark edge.
Shader tapePack(Offset c, double r, Color color) => ui.Gradient.radial(c, r, [
      mix(color, Colors.black, 0.62),
      mix(color, Colors.black, 0.25),
      color,
      mix(color, Colors.white, 0.18),
      mix(color, Colors.black, 0.5),
    ], const [0, 0.5, 0.88, 0.97, 1]);

// ---------------------------------------------------------------- the reels

/// Where the reels stand: how far each has turned (degrees) and how far through the song it is.
class Reels extends ChangeNotifier {
  double left = 0, right = 0, progress = 0.35;

  void set(double l, double r, double p) {
    left = l;
    right = r;
    progress = p;
    notifyListeners();
  }
}

class ReelsPainter extends CustomPainter {
  ReelsPainter(this.reels, this.look) : super(repaint: reels);

  final Reels reels;
  final TapeLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Geo(Offset.zero & size);
    final win = g.window;
    final wr = Radius.circular(win.height * 0.3);
    final clip = RRect.fromRectAndRadius(win, wr);
    final fine = g.w >= 150;
    final hr = g.hubR;
    canvas.save();
    canvas.clipRRect(clip);
    final (lp, rp) = g.packs(reels.progress);
    final hubs = g.hubs;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, g.w * 0.0028)
      ..color = _alpha(const Color(0xFF8A603F), 150);
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, g.w * 0.0016)
      ..color = _alpha(Colors.black, 34);
    for (final (c, r) in [(hubs[0], lp), (hubs[1], rp)]) {
      canvas.drawCircle(c, r, Paint()..shader = tapePack(c, r, look.tape));
      if (fine) {
        for (var k = 1; k < 5; k++) {
          canvas.drawCircle(c, hr * 1.15 + (r - hr * 1.15) * k / 5, groove);
        }
        canvas.drawCircle(
            c,
            r,
            Paint()
              ..shader = ui.Gradient.radial(Offset(c.dx - r * 0.3, c.dy - r * 0.45), r * 1.05,
                  [_alpha(const Color(0xFFFFD9B0), 30), _alpha(const Color(0xFFFFD9B0), 10), _alpha(const Color(0xFFFFD9B0), 0)],
                  const [0, 0.6, 1]));
      }
      canvas.drawCircle(c, r - g.w * 0.0014, rim);
    }
    final face = look.hub ?? const Color(0xFFE9E0CF);
    final spoke = Paint()..color = face;
    for (final (c, a) in [(hubs[0], reels.left), (hubs[1], reels.right)]) {
      canvas.drawCircle(c, hr * 1.1, Paint()..color = _alpha(Colors.black, 70));
      final hubPaint = Paint();
      if (fine) {
        hubPaint.shader = ui.Gradient.linear(Offset(c.dx - hr, c.dy - hr), Offset(c.dx + hr, c.dy + hr), [
          look.hub != null ? mix(face, Colors.white, 0.3) : const Color(0xFFF4EEE2),
          look.hub != null ? mix(face, Colors.black, 0.18) : const Color(0xFFCBBFA9),
        ]);
      } else {
        hubPaint.color = face;
      }
      canvas.drawCircle(c, hr, hubPaint);
      canvas.drawCircle(c, hr * 0.6, Paint()..color = const Color(0xFF120E0B));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a * pi / 180);
      final tw = hr * 0.22;
      for (var k = 0; k < 6; k++) {
        canvas.drawRect(Rect.fromLTWH(-tw / 2, -hr * 0.62, tw, hr * 0.26), spoke);
        canvas.rotate(pi / 3);
      }
      canvas.restore();
    }
    // the edge of the label throws a little shadow into the window, the glass catches the light
    canvas.drawRect(
        win,
        Paint()
          ..shader = ui.Gradient.linear(
              win.topCenter, Offset(win.center.dx, win.top + win.height * 0.3), [_alpha(Colors.black, 120), _alpha(Colors.black, 0)]));
    canvas.drawRRect(
        clip,
        Paint()
          ..shader = ui.Gradient.linear(win.topLeft, win.bottomRight,
              [_alpha(Colors.white, 34), _alpha(Colors.white, 7), _alpha(Colors.white, 0)], const [0, 0.45, 1]));
    canvas.restore();
    canvas.drawRRect(
        clip,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _alpha(Colors.black, 150));
  }

  @override
  bool shouldRepaint(ReelsPainter old) => old.reels != reels || old.look != look;
}

// ---------------------------------------------------------------- the widget

/// A cassette that fills its space (at the cassette's own shape). While [playing], its reels turn:
/// the tape runs at one speed, so the reel with less tape on it turns faster, like the real thing.
class Cassette extends StatefulWidget {
  const Cassette({
    super.key,
    required this.title,
    this.slot = 0,
    this.design,
    this.side = 'A',
    this.leftNote = '',
    this.rightNote = '',
    this.sticky = '',
    this.progress = 0.35,
    this.playing = false,
    this.cover = '',
  });

  final String title;
  final int slot;
  final Map<String, Object?>? design;
  final String side;
  final String leftNote;
  final String rightNote;
  final String sticky;
  final double progress;
  final bool playing;

  /// A cover picture's address, glued onto the label like a photo ('' for none).
  final String cover;

  @override
  State<Cassette> createState() => _CassetteState();
}

class _CassetteState extends State<Cassette> with SingleTickerProviderStateMixin {
  final _reels = Reels();
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  late TapeLook _look;

  @override
  void initState() {
    super.initState();
    _look = TapeLook(slot: widget.slot, design: widget.design);
    _reels.progress = widget.progress;
    if (widget.playing) _ticker.start();
  }

  @override
  void didUpdateWidget(Cassette old) {
    super.didUpdateWidget(old);
    if (old.slot != widget.slot || old.design != widget.design || _look.stock != Look.stock) {
      _look = TapeLook(slot: widget.slot, design: widget.design);
    }
    if (widget.playing && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.playing && _ticker.isActive) {
      _ticker.stop();
    }
    if (!widget.playing) _reels.set(_reels.left, _reels.right, widget.progress);
  }

  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    final size = context.size;
    if (size == null || dt <= 0 || dt > 0.5) return;
    final g = Geo(Offset.zero & size);
    final (lp, rp) = g.packs(widget.progress);
    // tape speed: an empty hub turns about once every two seconds
    final speed = g.hubR * 1.22 * pi;
    final dl = speed / lp * dt * 180 / pi, dr = speed / rp * dt * 180 / pi;
    _reels.set((_reels.left + dl) % 360, (_reels.right + dr) % 360, widget.progress);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _reels.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: ratio,
      child: LayoutBuilder(builder: (context, box) {
        final size = Size(box.maxWidth, box.maxHeight);
        final g = Geo(Offset.zero & size);
        final spot = widget.cover.isEmpty ? null : g.cover();
        return Stack(children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: CassettePainter(
                  look: _look,
                  title: widget.title,
                  side: widget.side,
                  leftNote: widget.leftNote,
                  rightNote: widget.rightNote,
                  sticky: widget.sticky,
                  progress: widget.progress,
                  cover: spot != null,
                ),
              ),
            ),
          ),
          Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: ReelsPainter(_reels, _look)))),
          if (spot != null)
            Positioned.fromRect(
              rect: spot.deflate(2.2),
              child: Transform.rotate(
                angle: -4 * pi / 180,
                child: Image.network(
                  widget.cover,
                  fit: BoxFit.cover,
                  cacheWidth: (spot.width * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 512),
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  gaplessPlayback: true,
                ),
              ),
            ),
        ]);
      }),
    );
  }
}
