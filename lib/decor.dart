/// Things stuck and drawn on a tape, the same ones as on the computer (decor.py there): sticky notes,
/// photos, vinyl stickers, washi tape, label-maker strips and lines drawn with the pen.
///
/// Every item sits at x and y (parts of the cassette's width and height), turned rot degrees, s big
/// (a part of the cassette's width), the computer's way, so a tape decorated on one shows the same on
/// the other. The 85 stickers come from the computer's own drawings: tool/stickers_from_desktop.py
/// writes them down as outlines into assets/stickers.json, and this draws them again.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'account.dart' show picturePattern;
import 'cassette.dart';
import 'look.dart';

const paperWhite = Color(0xFFFBF9F4);

const stickerColors = {
  'red': Color(0xFFE5392D),
  'orange': Color(0xFFF2861E),
  'yellow': Color(0xFFF6C63C),
  'lime': Color(0xFF97C93D),
  'teal': Color(0xFF25AD9D),
  'blue': Color(0xFF3978DE),
  'purple': Color(0xFF8752D2),
  'pink': Color(0xFFEF69A1),
  'white': Color(0xFFF6F2EA),
  'black': Color(0xFF2A2522),
};
const noteColors = {
  'yellow': Color(0xFFF8E17A),
  'pink': Color(0xFFF7B9C9),
  'blue': Color(0xFFBCDCF5),
  'green': Color(0xFFC8EAB2),
  'orange': Color(0xFFFFC68E),
  'lilac': Color(0xFFD8C7F3),
};
const washiColors = {
  'pink': Color(0xFFF2A6B8),
  'mint': Color(0xFF99D6C6),
  'sky': Color(0xFFA6C6EF),
  'butter': Color(0xFFF4D985),
  'lilac': Color(0xFFC8B2E8),
  'peach': Color(0xFFF1BF96),
};
const washiPatterns = ['stripes', 'dots', 'grid', 'plain'];
const dymoColors = {
  'red': Color(0xFFC4271E),
  'black': Color(0xFF22201F),
  'blue': Color(0xFF1F4EA6),
  'green': Color(0xFF1D7548),
  'yellow': Color(0xFFE7B62A),
};
const inkColors = {
  'blue': Color(0xFF25428E),
  'black': Color(0xFF1F1A16),
  'red': Color(0xFFB3261E),
  'green': Color(0xFF1F6B45),
  'purple': Color(0xFF5B2A86),
  'white': Color(0xFFF6F1E7),
};
const inkNames = {
  'blue': 'Ballpoint',
  'black': 'Marker',
  'red': 'Red pen',
  'green': 'Green pen',
  'purple': 'Purple pen',
  'white': 'Paint pen',
};
const penWidths = {'fine': 0.0055, 'medium': 0.0095, 'bold': 0.016};
const stickerFinishes = [('gloss', 'Glossy'), ('matte', 'Matte'), ('holo', 'Holo'), ('glitter', 'Glitter')];

const kindNames = {
  'note': 'Sticky note',
  'photo': 'Photo',
  'sticker': 'Sticker',
  'washi': 'Washi tape',
  'dymo': 'Label',
  'ink': 'Drawing',
};

/// How long the words on a note, a photo's caption and a label can be.
const textLimits = {'note': 60, 'photo': 40, 'dymo': 24};

/// How small and how big each kind can get, in parts of the cassette's width.
const itemSizes = {
  'note': (0.08, 0.5),
  'photo': (0.1, 0.6),
  'sticker': (0.045, 0.45),
  'washi': (0.1, 1.2),
  'dymo': (0.035, 0.16),
  'ink': (0.2, 4.0),
};

/// Things on one tape, at most.
const itemLimit = 150;

/// A color from a table by name, a '#rrggbb' given directly, or [fallback].
Color pickColor(Object? key, Map<String, Color> table, Color fallback) {
  if (key is! String) return fallback;
  final named = table[key];
  if (named != null) return named;
  if (key.length == 7 && key.startsWith('#')) {
    final n = int.tryParse(key.substring(1), radix: 16);
    if (n != null) return Color(0xFF000000 | n);
  }
  return fallback;
}

double _num(Object? v, double fallback) => v is num && v.isFinite ? v.toDouble() : fallback;

/// Qt's lighter and darker: the color's value up or down by a percentage.
Color qtLighter(Color c, int percent) {
  final hsv = HSVColor.fromColor(c);
  final v = hsv.value * percent / 100;
  // brighter than white takes the saturation down instead, the way Qt does
  if (v > 1) return hsv.withValue(1).withSaturation((hsv.saturation - (v - 1)).clamp(0.0, 1.0)).toColor();
  return hsv.withValue(v).toColor();
}

Color qtDarker(Color c, int percent) {
  final hsv = HSVColor.fromColor(c);
  return hsv.withValue((hsv.value * 100 / percent).clamp(0.0, 1.0)).toColor();
}

Color _mixed(Color a, Color b, double f) => Color.lerp(a, b, f)!;

// ---------------------------------------------------------------- the sticker sheet

/// One step of a sticker's print: a filled shape or a line, its brush, and the shapes it's clipped to.
class _Op {
  _Op(this.path, this.brush, {this.stroke = 0, this.cap = StrokeCap.round, this.join = StrokeJoin.round, this.clips = const []});

  final Path path;
  final Object? brush; // '#rrggbbaa' as hex, {"each": [...]}, or a gradient {"l"|"r": [...], "s": [...]}
  final double stroke;
  final StrokeCap cap;
  final StrokeJoin join;
  final List<Path> clips;
}

class StickerSheet {
  StickerSheet._(this._s, this._colors, this.drawers);

  static StickerSheet? _the;

  /// The sheet once it's read (null until then: stickers wait a moment, the rest of the tape doesn't).
  static StickerSheet? get the => _the;

  static Future<StickerSheet>? _loading;

  static Future<StickerSheet> load() => _loading ??= _read();

  static Future<StickerSheet> _read() async {
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/stickers.json')) as Map<String, Object?>;
      final drawers = [
        for (final c in j['cats'] as List)
          ('${(c as List)[0]}', [for (final k in c[1] as List) '$k']),
      ];
      return _the = StickerSheet._(
          Map<String, Object?>.from(j['s'] as Map), [for (final n in j['colors'] as List) '$n'], drawers);
    } on Object {
      _loading = null; // the next one tries again
      rethrow;
    }
  }

  final Map<String, Object?> _s;
  final List<String> _colors;

  /// The stickers by drawer (Music, Words, Fun, Nature, Food, Space), as on the computer.
  final List<(String, List<String>)> drawers;

  final _outlines = <String, Path>{};
  final _prints = <String, List<_Op>>{};

  bool has(String key) => _s.containsKey(key);

  Map<Object?, Object?> _entry(String key) => _s[has(key) ? key : 'star'] as Map;

  String nameOf(String key) => '${_entry(key)['n'] ?? key}';

  String colorOf(String key) => '${_entry(key)['c'] ?? 'red'}';

  /// The sticker's outline, one unit across, centered on 0,0.
  Path outline(String key) => _outlines[key] ??= parsePath('${_entry(key)['o']}');

  /// Its box at one unit across, the white die-cut edge included.
  Rect box(String key) {
    final b = _entry(key)['b'] as List;
    return Rect.fromLTWH(_num(b[0], -0.5), _num(b[1], -0.5), _num(b[2], 1), _num(b[3], 1));
  }

  /// What's printed on the sticker, step by step.
  List<_Op> _print(String key) => _prints[key] ??= [
        for (final raw in _entry(key)['d'] as List? ?? const []) _op(raw as List),
      ];

  static _Op _op(List o) {
    final kind = '${o[0]}';
    final d = '${o[1]}';
    var k = 2;
    var width = 0.0;
    var cap = StrokeCap.round;
    var join = StrokeJoin.round;
    if (kind == 's') {
      width = _num(o[2], 0.01);
      cap = switch ('${o[3]}') { 'f' => StrokeCap.butt, 'q' => StrokeCap.square, _ => StrokeCap.round };
      join = switch ('${o[4]}') { 'm' => StrokeJoin.miter, 'b' => StrokeJoin.bevel, _ => StrokeJoin.round };
      k = 5;
    }
    final clips = <Path>[];
    if (o.length - k == 2) {
      for (final c in o[k] as List) {
        final t = '$c';
        clips.add(parsePath(t.substring(1), fill: t[0] == 'w' ? PathFillType.nonZero : PathFillType.evenOdd));
      }
      k++;
    }
    return _Op(
      parsePath(d, fill: kind == 'e' ? PathFillType.evenOdd : PathFillType.nonZero),
      o[k],
      stroke: kind == 's' ? width : 0,
      cap: cap,
      join: join,
      clips: clips,
    );
  }

  /// Which palette color a sticker color is (or the nearest one, for a color given as #rrggbb).
  int paletteIndex(Color c) {
    var best = 0;
    var bestD = double.infinity;
    for (var k = 0; k < _colors.length; k++) {
      final p = stickerColors[_colors[k]] ?? Colors.black;
      final d = pow(p.r - c.r, 2) + pow(p.g - c.g, 2) + pow(p.b - c.b, 2);
      if (d < bestD) {
        bestD = d.toDouble();
        best = k;
      }
    }
    return best;
  }
}

/// An SVG path's M, L, C and Z, as a Path.
Path parsePath(String d, {PathFillType fill = PathFillType.evenOdd}) {
  final p = Path()..fillType = fill;
  for (final m in RegExp(r'([MLCZ])([^MLCZ]*)').allMatches(d)) {
    final v = [
      for (final n in m.group(2)!.trim().split(RegExp(r'[\s,]+')))
        if (n.isNotEmpty) double.parse(n),
    ];
    switch (m.group(1)) {
      case 'M':
        p.moveTo(v[0], v[1]);
      case 'L':
        p.lineTo(v[0], v[1]);
      case 'C':
        p.cubicTo(v[0], v[1], v[2], v[3], v[4], v[5]);
      default:
        p.close();
    }
  }
  return p;
}

Color _hex(String h) => Color(int.parse('${h.substring(6, 8)}${h.substring(0, 6)}', radix: 16));

/// A brush from the sheet as a Paint, for the sticker's palette color [k].
Paint _paintOf(Object? b, int k) {
  if (b is Map && b['each'] is List) b = (b['each'] as List)[k];
  if (b is String) return Paint()..color = _hex(b);
  final g = b as Map;
  final stops = [for (final s in g['s'] as List) _num((s as List)[0], 0)];
  final colors = [for (final s in g['s'] as List) _hex('${(s as List)[1]}')];
  if (g['l'] case final List l) {
    return Paint()
      ..shader = ui.Gradient.linear(Offset(_num(l[0], 0), _num(l[1], 0)), Offset(_num(l[2], 1), _num(l[3], 1)), colors, stops);
  }
  final r = g['r'] as List;
  final focal = Offset(_num(r[3], 0), _num(r[4], 0));
  final center = Offset(_num(r[0], 0), _num(r[1], 0));
  return Paint()
    ..shader = ui.Gradient.radial(
        center, _num(r[2], 0.5), colors, stops, TileMode.clamp, null, focal == center ? null : focal);
}

/// The holo foil's colors, going round. Qt goes round the other way, so they're listed backwards.
const _holo = [Color(0xFFFF7AC0), Color(0xFFB394FF), Color(0xFF73D8FF), Color(0xFF9AF7B0), Color(0xFFFFD36B), Color(0xFFFF7AC0)];
const _holoStops = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0];

ui.Image? _glitterTile;

/// Flakes of glitter on a tile that repeats without a seam, made once (the computer's, flake for flake).
ui.Image _glitter() {
  final had = _glitterTile;
  if (had != null) return had;
  const n = 128.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final rnd = Random(42);
  for (var k = 0; k < 430; k++) {
    final x = rnd.nextDouble() * n, y = rnd.nextDouble() * n, r = 0.7 + rnd.nextDouble() * 1.0;
    final bright = rnd.nextDouble() < 0.6;
    final paint = Paint()
      ..color = bright ? Colors.white.withAlpha(90 + rnd.nextInt(146)) : Colors.black.withAlpha(30 + rnd.nextInt(56));
    final a = rnd.nextDouble() * pi;
    final flake = Path();
    flake.moveTo(r * cos(a), r * sin(a));
    for (var i = 1; i < 6; i++) {
      flake.lineTo(r * cos(a + i * pi / 3), r * sin(a + i * pi / 3));
    }
    flake.close();
    for (final dx in const [-n, 0.0, n]) {
      for (final dy in const [-n, 0.0, n]) {
        if (x + dx > -3 && x + dx < n + 3 && y + dy > -3 && y + dy < n + 3) c.drawPath(flake.shift(Offset(x + dx, y + dy)), paint);
      }
    }
  }
  return _glitterTile = rec.endRecording().toImageSync(n.toInt(), n.toInt());
}

/// One vinyl sticker [s] across, centered on 0,0: its shadow, the white die-cut edge, the body in its
/// color and finish, then its print.
void paintSticker(Canvas canvas, String shape, double s, Color color, {String finish = 'gloss', bool detail = true}) {
  final sheet = StickerSheet.the;
  if (sheet == null) return;
  final path = sheet.outline(shape).transform(Matrix4.diagonal3Values(s, s, 1).storage);
  if (detail) {
    final moved = path.shift(Offset(s * 0.025, s * 0.04));
    final shade = Paint()..color = Colors.black.withAlpha(55);
    canvas.drawPath(
        moved,
        Paint()
          ..color = shade.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.1
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
    canvas.drawPath(moved, shade);
  }
  canvas.drawPath(
      path,
      Paint()
        ..color = paperWhite
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.1
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round);
  canvas.drawPath(path, Paint()..color = paperWhite);
  final flat = finish == 'matte';
  canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(Offset(-s / 2, -s / 2), Offset(s / 2, s / 2),
            [qtLighter(color, flat ? 105 : 116), qtDarker(color, flat ? 106 : 112)]));
  canvas.save();
  canvas.clipPath(path);
  if (finish == 'glitter') {
    final k = s * 0.7 / 128;
    canvas.drawPath(
        path,
        Paint()
          ..shader = ImageShader(_glitter(), TileMode.repeated, TileMode.repeated, Matrix4.diagonal3Values(k, k, 1).storage));
  }
  if (detail || s >= 14) {
    final k = sheet.paletteIndex(color);
    canvas.save();
    canvas.scale(s, s);
    for (final op in sheet._print(shape)) {
      canvas.save();
      for (final c in op.clips) {
        canvas.clipPath(c);
      }
      final paint = _paintOf(op.brush, k);
      if (op.stroke > 0) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = op.stroke
          ..strokeCap = op.cap
          ..strokeJoin = op.join;
      }
      canvas.drawPath(op.path, paint);
      canvas.restore();
    }
    canvas.restore();
  }
  final box = Rect.fromLTWH(-s * 0.6, -s * 0.6, s * 1.2, s * 1.2);
  if (finish == 'holo') {
    // the foil over the print at half strength, the way the computer lays it on (hard light)
    canvas.drawRect(
        box,
        Paint()
          ..color = const Color(0x80000000)
          ..blendMode = BlendMode.hardLight
          ..shader = ui.Gradient.sweep(Offset(-s * 0.16, -s * 0.2), _holo, _holoStops, TileMode.clamp, -pi / 6, 2 * pi - pi / 6));
    if (detail) {
      canvas.drawRect(
          box,
          Paint()
            ..shader = ui.Gradient.linear(Offset(-s / 2, -s / 2), Offset(s / 2, s / 2), [
              Colors.white.withAlpha(0),
              Colors.white.withAlpha(0),
              Colors.white.withAlpha(130),
              Colors.white.withAlpha(0),
              Colors.white.withAlpha(0),
              Colors.white.withAlpha(90),
              Colors.white.withAlpha(0),
              Colors.white.withAlpha(0),
            ], const [0, 0.27, 0.33, 0.39, 0.5, 0.54, 0.58, 1]));
    }
  } else if (detail && finish != 'matte') {
    canvas.drawRect(
        Rect.fromLTWH(-s / 2, -s / 2, s, s * 0.62),
        Paint()
          ..shader = ui.Gradient.linear(Offset(-s / 2, -s / 2), Offset(s * 0.05, s * 0.15),
              [Colors.white.withAlpha(finish == 'glitter' ? 70 : 120), Colors.white.withAlpha(0)]));
    if (finish == 'glitter') _glints(canvas, path, s);
  }
  canvas.restore();
}

/// A few bright four-point sparkles where the glitter catches the light.
void _glints(Canvas canvas, Path path, double s) {
  final paint = Paint()..color = Colors.white.withAlpha(235);
  var shown = 0;
  for (final (x, y, r) in const [(-0.2, -0.22, 0.075), (0.18, 0.12, 0.055), (0.05, -0.05, 0.04), (-0.12, 0.24, 0.045), (0.26, -0.18, 0.05)]) {
    final c = Offset(x * s, y * s);
    if (!path.contains(c)) continue;
    final k = r * s;
    final star = Path()..moveTo(c.dx, c.dy - k);
    for (final (dx, dy) in const [(0.18, -0.18), (1.0, 0.0), (0.18, 0.18), (0.0, 1.0), (-0.18, 0.18), (-1.0, 0.0), (-0.18, -0.18), (0.0, -1.0)]) {
      star.lineTo(c.dx + dx * k, c.dy + dy * k);
    }
    canvas.drawPath(star, paint);
    if (++shown == 3) break;
  }
}

// ---------------------------------------------------------------- where an item sits

Offset itemCenter(Geo g, Map<Object?, Object?> it) => Offset(g.x + _num(it['x'], 0.5) * g.w, g.y + _num(it['y'], 0.5) * g.h);

double itemTurn(Map<Object?, Object?> it) => _num(it['rot'], 0) * pi / 180;

TextStyle _dymoStyle(double hgt) =>
    TextStyle(fontFamily: 'Barlow Condensed', fontWeight: FontWeight.w700, fontSize: hgt * 0.62, letterSpacing: hgt * 0.07, height: 1);

String dymoText(Map<Object?, Object?> it) => ('${it['text'] ?? ''}'.isEmpty ? 'MIXTAPE' : '${it['text']}').toUpperCase();

/// The item's own box, before it is turned, around its center.
Rect itemBox(Geo g, Map<Object?, Object?> it) {
  final kind = it['kind'];
  final s = _num(it['s'], 0.2) * g.w;
  switch (kind) {
    case 'photo':
      return Rect.fromLTWH(-s / 2, -s * 1.17 / 2, s, s * 1.17);
    case 'washi':
      final t = s * 0.22;
      return Rect.fromLTWH(-s / 2, -t / 2, s, t);
    case 'dymo':
      final tp = TextPainter(text: TextSpan(text: dymoText(it), style: _dymoStyle(s)), textDirection: TextDirection.ltr)..layout();
      final w = tp.width + s * 1.1;
      tp.dispose();
      return Rect.fromLTWH(-w / 2, -s / 2, w, s);
    case 'ink':
      final pts = it['pts'];
      if (pts is! List || pts.isEmpty) return const Rect.fromLTWH(-1, -1, 2, 2);
      final k = g.w * _num(it['s'], 1.0);
      final xs = [for (final p in pts) _num((p as List)[0], 0) * k];
      final ys = [for (final p in pts) _num((p as List)[1], 0) * k];
      final pad = _num(it['w'], 0.008) * k / 2 + 2;
      return Rect.fromLTRB(xs.reduce(min) - pad, ys.reduce(min) - pad, xs.reduce(max) + pad, ys.reduce(max) + pad);
    case 'sticker':
      final b = StickerSheet.the?.box(stickerShapeOf(it)) ?? const Rect.fromLTWH(-0.52, -0.52, 1.04, 1.04);
      return Rect.fromLTWH(b.left * s, b.top * s, b.width * s, b.height * s);
    default:
      return Rect.fromLTWH(-s / 2, -s / 2, s, s);
  }
}

String stickerShapeOf(Map<Object?, Object?> it) {
  final shape = '${it['shape'] ?? 'star'}';
  return StickerSheet.the?.has(shape) ?? true ? shape : 'star';
}

/// Where a point on the cassette is in the item's own turned box.
Offset _local(Geo g, Map<Object?, Object?> it, Offset pos) {
  final c = itemCenter(g, it);
  final a = -itemTurn(it);
  final d = pos - c;
  return Offset(d.dx * cos(a) - d.dy * sin(a), d.dx * sin(a) + d.dy * cos(a));
}

/// Is [pos] on the item? A drawn line counts only near the line itself, not its whole box.
bool itemHit(Geo g, Map<Object?, Object?> it, Offset pos, {double slack = 0}) {
  final local = _local(g, it, pos);
  if (it['kind'] == 'ink') {
    final pts = it['pts'];
    if (pts is! List || pts.length < 2) return false;
    final k = g.w * _num(it['s'], 1.0);
    final reach = max(10.0, _num(it['w'], 0.008) * k + 8 + 2 * slack) / 2;
    for (var i = 1; i < pts.length; i++) {
      final a = Offset(_num((pts[i - 1] as List)[0], 0) * k, _num((pts[i - 1] as List)[1], 0) * k);
      final b = Offset(_num((pts[i] as List)[0], 0) * k, _num((pts[i] as List)[1], 0) * k);
      if (_toSegment(local, a, b) <= reach) return true;
    }
    return false;
  }
  return itemBox(g, it).inflate(slack).contains(local);
}

double _toSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len = ab.distanceSquared;
  if (len == 0) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

// ---------------------------------------------------------------- drawing them

/// Everything stuck and drawn on the tape, oldest first, and wrapped round the shell's edge.
/// [pictures]: the photos by name, as far as they're here (a photo that isn't shows its frame).
void paintItems(Canvas canvas, Geo g, Object? items, {Map<String, ui.Image> pictures = const {}, int skip = -1}) {
  if (items is! List || items.isEmpty || g.w < 56) return;
  final detail = g.w >= 130;
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(g.shell, Radius.circular(g.w * 0.045)));
  for (var k = 0; k < items.length; k++) {
    final it = items[k];
    if (k == skip || it is! Map) continue;
    final depth = canvas.getSaveCount();
    try {
      paintItem(canvas, g, it, pictures: pictures, detail: detail);
    } on Object catch (e, stack) {
      // one odd sticker never takes the whole tape with it (while testing, it still says so)
      assert(() {
        FlutterError.reportError(FlutterErrorDetails(exception: e, stack: stack, library: 'decor'));
        return true;
      }());
    } finally {
      canvas.restoreToCount(depth);
    }
  }
  canvas.restore();
}

void paintItem(Canvas canvas, Geo g, Map<Object?, Object?> it, {Map<String, ui.Image> pictures = const {}, bool detail = true}) {
  final s = _num(it['s'], 0.2) * g.w;
  final c = itemCenter(g, it);
  canvas.save();
  canvas.translate(c.dx, c.dy);
  canvas.rotate(itemTurn(it));
  switch (it['kind']) {
    case 'note':
      _note(canvas, s, it, pictures, detail);
    case 'photo':
      _photo(canvas, s, it, pictures, detail);
    case 'sticker':
      paintSticker(canvas, stickerShapeOf(it), s,
          pickColor(it['color'], stickerColors, stickerColors[StickerSheet.the?.colorOf(stickerShapeOf(it)) ?? 'red'] ?? Colors.red),
          finish: '${it['finish'] ?? 'gloss'}', detail: detail);
    case 'washi':
      _washi(canvas, s, it, detail);
    case 'dymo':
      _dymo(canvas, s, it, detail);
    case 'ink':
      _ink(canvas, g, it);
  }
  canvas.restore();
}

/// A picture drawn to fill [box], its middle kept.
void _fill(Canvas canvas, Rect box, ui.Image img) {
  final scale = max(box.width / img.width, box.height / img.height);
  final w = box.width / scale, h = box.height / scale;
  final src = Rect.fromLTWH((img.width - w) / 2, (img.height - h) / 2, w, h);
  canvas.drawImageRect(img, src, box, Paint()..filterQuality = FilterQuality.medium);
}

void _note(Canvas canvas, double s, Map<Object?, Object?> it, Map<String, ui.Image> pictures, bool detail) {
  final color = pickColor(it['color'], noteColors, noteColors['yellow']!);
  final text = '${it['text'] ?? ''}';
  final img = pictures['${it['image'] ?? ''}'];
  paintSticky(canvas, Offset.zero, s, 0, img != null || !detail ? '' : text, color, lines: 4);
  if (img == null) return;
  final box = Rect.fromLTWH(-s / 2 + s * 0.11, -s / 2 + s * 0.21, s * 0.78, s * (text.isNotEmpty ? 0.5 : 0.66));
  if (detail) canvas.drawRect(box.shift(Offset(s * 0.012, s * 0.018)), Paint()..color = Colors.black.withAlpha(40));
  canvas.drawRect(box.inflate(s * 0.02), Paint()..color = paperWhite);
  _fill(canvas, box, img);
  if (text.isNotEmpty && detail) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: Look.hand(s * 0.15)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: s * 0.8);
    tp.paint(canvas, Offset(-tp.width / 2, box.bottom + s * 0.015 + (s * 0.2 - tp.height) / 2));
    tp.dispose();
  }
}

void _photo(Canvas canvas, double s, Map<Object?, Object?> it, Map<String, ui.Image> pictures, bool detail) {
  final w = s, h = s * 1.17;
  final r = Rect.fromLTWH(-w / 2, -h / 2, w, h);
  if (detail) {
    for (final (k, a) in const [(2.2, 22), (1.2, 34)]) {
      canvas.drawRect(r.shift(Offset(w * 0.012 * k, w * 0.016 * k)), Paint()..color = Colors.black.withAlpha(a));
    }
  }
  canvas.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topLeft, r.bottomRight, const [paperWhite, Color(0xFFECE7DC)]));
  canvas.drawRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, w * 0.006)
        ..color = Colors.black.withAlpha(36));
  final pic = Rect.fromLTWH(r.left + w * 0.075, r.top + w * 0.075, w * 0.85, w * 0.85);
  final img = pictures['${it['image'] ?? ''}'];
  if (img != null) {
    _fill(canvas, pic, img);
  } else {
    canvas.drawRect(pic, Paint()..color = const Color(0xFFCFC8BB));
    final sz = pic.width * 0.34;
    if (sz >= 8) {
      final icon = TextPainter(
        text: TextSpan(
            text: String.fromCharCode(Icons.image_outlined.codePoint),
            style: TextStyle(fontFamily: Icons.image_outlined.fontFamily, package: Icons.image_outlined.fontPackage, fontSize: sz, color: const Color(0xFF8F877B))),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(canvas, pic.center - Offset(icon.width / 2, icon.height / 2));
      icon.dispose();
    }
  }
  canvas.drawRect(
      pic,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, w * 0.004)
        ..color = Colors.black.withAlpha(46));
  final text = '${it['text'] ?? ''}';
  if (text.isNotEmpty && detail) {
    final cap = Rect.fromLTRB(r.left + w * 0.06, pic.bottom + h * 0.01, r.right - w * 0.06, r.bottom - h * 0.01);
    final tp = TextPainter(
      text: TextSpan(text: text, style: Look.hand(h * 0.12, color: const Color(0xFF2C2A33))),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: cap.width);
    tp.paint(canvas, Offset(-tp.width / 2, cap.center.dy - tp.height / 2));
    tp.dispose();
  }
  if (detail) {
    // a bit of paper tape holds it on
    canvas.save();
    canvas.translate(0, r.top + w * 0.005);
    canvas.rotate(-5 * pi / 180);
    canvas.drawPath(_torn(Rect.fromLTWH(-w * 0.2, -w * 0.06, w * 0.4, w * 0.12), 4), Paint()..color = const Color(0xAFF2E8C4));
    canvas.restore();
  }
}

/// A strip with zigzag ends, the way paper tape tears.
Path _torn(Rect r, int teeth) {
  final d = r.height * 0.09;
  final p = Path()..moveTo(r.right, r.top);
  for (var k = 1; k <= teeth; k++) {
    p.lineTo(r.right - (k.isOdd ? d : 0), r.top + r.height * k / teeth);
  }
  for (var k = 0; k <= teeth; k++) {
    p.lineTo(r.left + (k.isOdd ? d : 0), r.bottom - r.height * k / teeth);
  }
  return p..close();
}

void _washi(Canvas canvas, double s, Map<Object?, Object?> it, bool detail) {
  final t = s * 0.22;
  final r = Rect.fromLTWH(-s / 2, -t / 2, s, t);
  final base = pickColor(it['color'], washiColors, washiColors['pink']!);
  final strip = _torn(r, max(4, t ~/ 3.2));
  canvas.drawPath(strip, Paint()..color = base.withAlpha(208));
  final pattern = washiPatterns.contains(it['pattern']) ? '${it['pattern']}' : 'stripes';
  canvas.save();
  canvas.clipPath(strip);
  final ink = _mixed(base, Colors.white, 0.55).withAlpha(170);
  final dark = _mixed(base, Colors.black, 0.25).withAlpha(110);
  if (pattern == 'stripes') {
    final pen = Paint()
      ..color = ink
      ..strokeWidth = t * 0.16;
    for (var k = -t; k < s + t; k += t * 0.5) {
      canvas.drawLine(Offset(r.left + k, r.bottom), Offset(r.left + k + t, r.top), pen);
    }
  } else if (pattern == 'dots') {
    final dot = Paint()..color = ink;
    final step = t * 0.36;
    var row = 0;
    for (var yy = r.top + step * 0.5; yy < r.bottom + step; yy += step * 0.86, row++) {
      for (var xx = r.left + (row.isOdd ? step * 0.5 : 0); xx < r.right + step; xx += step) {
        canvas.drawCircle(Offset(xx, yy), t * 0.075, dot);
      }
    }
  } else if (pattern == 'grid') {
    final pen = Paint()
      ..color = dark
      ..strokeWidth = max(0.5, t * 0.04);
    final step = t * 0.3;
    for (var xx = r.left; xx < r.right; xx += step) {
      canvas.drawLine(Offset(xx, r.top), Offset(xx, r.bottom), pen);
    }
    for (var yy = r.top + step * 0.5; yy < r.bottom; yy += step) {
      canvas.drawLine(Offset(r.left, yy), Offset(r.right, yy), pen);
    }
  }
  if (detail) {
    canvas.drawLine(
        Offset(r.left, r.top + 0.5),
        Offset(r.right, r.top + 0.5),
        Paint()
          ..color = Colors.white.withAlpha(60)
          ..strokeWidth = max(0.5, t * 0.04));
  }
  canvas.restore();
}

void _dymo(Canvas canvas, double hgt, Map<Object?, Object?> it, bool detail) {
  final text = dymoText(it);
  final base = pickColor(it['color'], dymoColors, dymoColors['red']!);
  final darkText = (0.299 * base.r + 0.587 * base.g + 0.114 * base.b) > 0.58;
  TextPainter label(Color c) =>
      TextPainter(text: TextSpan(text: text, style: _dymoStyle(hgt).copyWith(color: c)), textDirection: TextDirection.ltr)..layout();
  final front = label(darkText ? const Color(0xFF272320) : const Color(0xFFF8F6F1));
  final w = front.width + hgt * 1.1;
  final r = Rect.fromLTWH(-w / 2, -hgt / 2, w, hgt);
  final corner = Radius.circular(hgt * 0.1);
  if (detail) {
    canvas.drawRRect(RRect.fromRectAndRadius(r.shift(Offset(hgt * 0.03, hgt * 0.06)), corner), Paint()..color = Colors.black.withAlpha(60));
  }
  canvas.drawRRect(
      RRect.fromRectAndRadius(r, corner),
      Paint()
        ..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [qtLighter(base, 122), base, qtDarker(base, 126)], const [0, 0.5, 1]));
  final at = Offset(-front.width / 2, -front.height / 2);
  if (detail) {
    // pressed into the plastic: the letters' edge catches the light
    final edge = label(darkText ? Colors.white.withAlpha(120) : Colors.black.withAlpha(90));
    edge.paint(canvas, at + Offset(hgt * 0.025, hgt * 0.045));
    edge.dispose();
  }
  front.paint(canvas, at);
  front.dispose();
}

/// A hand-drawn line through the points, rounded off between them.
Path smoothPath(List<Offset> q) {
  final path = Path()..moveTo(q[0].dx, q[0].dy);
  if (q.length == 2) return path..lineTo(q[1].dx, q[1].dy);
  for (var k = 1; k + 1 < q.length; k++) {
    final a = q[k], b = q[k + 1];
    path.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }
  return path..lineTo(q.last.dx, q.last.dy);
}

void _ink(Canvas canvas, Geo g, Map<Object?, Object?> it) {
  final pts = it['pts'];
  if (pts is! List || pts.length < 2) return;
  final k = g.w * _num(it['s'], 1.0);
  final q = [for (final p in pts) Offset(_num((p as List)[0], 0) * k, _num(p[1], 0) * k)];
  canvas.drawPath(
      smoothPath(q),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = pickColor(it['color'], inkColors, inkColors['black']!).withAlpha(238)
        ..strokeWidth = max(0.7, _num(it['w'], 0.008) * k)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
}

// ---------------------------------------------------------------- the way they're kept

double _within(Object? v, double lo, double hi, double fallback, int places) {
  var f = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  if (f == null || !f.isFinite) f = fallback;
  final k = pow(10, places);
  return (f.clamp(lo, hi) * k).roundToDouble() / k;
}

String _cut(String v, int n) => v.runes.length > n ? String.fromCharCodes(v.runes.take(n)) : v;

/// One thing stuck or drawn on a tape the way the account keeps it, or null when it makes no sense:
/// the computer's core.clean_item, rule for rule, so both ends keep the same.
Map<String, Object?>? cleanItem(Object? raw) {
  if (raw is! Map || !kindNames.containsKey(raw['kind'])) return null;
  final kind = '${raw['kind']}';
  final out = <String, Object?>{
    'kind': kind,
    'x': _within(raw['x'], -0.25, 1.25, 0.5, 4),
    'y': _within(raw['y'], -0.25, 1.25, 0.5, 4),
    's': _within(raw['s'], 0.02, 2.5, 0.2, 4),
    'rot': _within(raw['rot'], -720, 720, 0, 2),
  };
  for (final (key, n) in const [('color', 24), ('shape', 16), ('pattern', 16), ('finish', 12)]) {
    final v = raw[key];
    if (v is String && v.isNotEmpty) out[key] = _cut(v, n);
  }
  if (raw['text'] case final String t) {
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).join(' ');
    if (words.isNotEmpty) out['text'] = _cut(words, 80);
  }
  if (raw['image'] case final String img when picturePattern.hasMatch(img)) out['image'] = img;
  if (kind == 'photo' && !out.containsKey('image')) return null;
  if (kind == 'ink') {
    final pts = raw['pts'];
    if (pts is! List) return null;
    final clean = [
      for (final p in pts.take(900))
        if (p is List && p.length == 2) [_within(p[0], -3, 3, 0, 4), _within(p[1], -3, 3, 0, 4)],
    ];
    if (clean.length < 2) return null;
    out['pts'] = clean;
    out['w'] = _within(raw['w'], 0.001, 0.08, 0.008, 4);
  }
  return out;
}

/// A tape's decorations, cleaned, the oldest first (as many as fit on a tape).
List<Map<String, Object?>> cleanItems(Object? raw) => [
      if (raw is List)
        for (final it in raw.take(itemLimit))
          if (cleanItem(it) case final c?) c,
    ];

/// The pictures the decorations use (photos, and pictures on sticky notes).
Set<String> picturesOf(Object? items) => {
      if (items is List)
        for (final it in items)
          if (it is Map && it['image'] is String && picturePattern.hasMatch('${it['image']}')) '${it['image']}',
    };

/// Everything stuck and drawn on the tape, drawn once onto a see-through picture of the cassette as a
/// PNG: what Mixtape on a phone lays over its own cassette (the computer's widgets.layer_png). A
/// picture that comes out too big for the account is drawn smaller; null when there's nothing on it.
Future<Uint8List?> layerPng(List<Map<String, Object?>> items, {Map<String, ui.Image> pictures = const {}}) async {
  if (items.isEmpty) return null;
  for (final w in const [900, 640, 480]) {
    final h = (w / ratio).round();
    final rec = ui.PictureRecorder();
    paintItems(Canvas(rec), Geo(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())), items, pictures: pictures);
    final picture = rec.endRecording();
    final img = await picture.toImage(w, h);
    picture.dispose();
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (data == null) return null;
    final png = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    if (png.length <= 1800000) return png;
  }
  return null;
}

/// A sticker on its own, fitted into [box] (for the sticker sheet and the studio's buttons).
void paintStickerIn(Canvas canvas, Rect box, String shape, {Object? color, String finish = 'gloss'}) {
  final sheet = StickerSheet.the;
  if (sheet == null) return;
  final b = sheet.box(shape);
  final px = min(box.width, box.height);
  final s = px * 0.92 / (max(b.width, b.height) + 0.04);
  canvas.save();
  canvas.translate(box.center.dx - b.center.dx * s - s * 0.012, box.center.dy - b.center.dy * s - s * 0.02);
  paintSticker(canvas, shape, s, pickColor(color, stickerColors, stickerColors[sheet.colorOf(shape)] ?? Colors.red),
      finish: finish, detail: px >= 20);
  canvas.restore();
}
