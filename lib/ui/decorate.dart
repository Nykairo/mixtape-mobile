/// Decorating a tape on the phone, the way the computer's tape studio does it (studio.py there): sticky
/// notes with words or a picture, photos, the 85 vinyl stickers, washi tape, label-maker strips and
/// lines drawn with a finger. Tap a thing to pick it, drag it around, pinch it to turn and resize it
/// (or use its round handle and its corner), and the panel under the tape recolors it, stacks it and
/// takes it off again.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mixtape_native/mixtape_native.dart';

import '../app.dart';
import '../cassette.dart';
import '../decor.dart';
import '../look.dart';
import 'widgets.dart';

double _n(Object? v, [double fallback = 0]) => v is num && v.isFinite ? v.toDouble() : fallback;

double _round(double v, int places) {
  final k = pow(10, places).toDouble();
  return (v * k).roundToDouble() / k;
}

/// A turn in degrees, kept between -180 and 180, held still for a moment at the straight angles.
double _turned(double rot) {
  var r = (rot + 180) % 360 - 180;
  for (final snap in const [-180.0, -90.0, -45.0, 0.0, 45.0, 90.0, 180.0]) {
    if ((r - snap).abs() < 3) r = snap;
  }
  return _round(r, 1);
}

Map<String, Object?> _copy(Map<String, Object?> it) => Map<String, Object?>.from(jsonDecode(jsonEncode(it)) as Map);

// ---------------------------------------------------------------- what's on the tape

/// What's stuck and drawn on the tape while the studio is open, and which of it is picked.
class Decorations extends ChangeNotifier {
  Decorations(List<Map<String, Object?>> items) : items = [for (final it in items) _copy(it)];

  List<Map<String, Object?>> items;
  int sel = -1;
  bool pen = false;
  String penColor = 'black';
  String penWidth = 'medium';

  /// Counted up when anything on the tape changes ([stamp]) or only the picked thing does ([picked]):
  /// what lies under and over the picked thing is only drawn again when it has to be.
  int stamp = 0;
  int picked = 0;

  /// The photos, by name, as far as they're here.
  final pictures = <String, ui.Image>{};

  /// A change that is finished (for undo).
  VoidCallback? onCommit;

  final _rnd = Random();
  bool gone = false;

  Map<String, Object?>? get current => sel >= 0 && sel < items.length ? items[sel] : null;

  bool get full => items.length >= itemLimit;

  void _all({bool commit = true}) {
    stamp++;
    notifyListeners();
    if (commit) onCommit?.call();
  }

  /// The picked thing changed, nothing else did.
  void touched({bool commit = true}) {
    picked++;
    notifyListeners();
    if (commit) onCommit?.call();
  }

  void commit() => onCommit?.call();

  /// Something outside the things themselves came (the sticker sheet, a photo): everything again.
  void refresh() => _all(commit: false);

  void select(int k) {
    final now = k >= 0 && k < items.length ? k : -1;
    if (now == sel) return;
    sel = now;
    _all(commit: false);
  }

  void setPen(bool on) {
    pen = on;
    if (on) sel = -1;
    _all(commit: false);
  }

  void setPenColor(String key) {
    penColor = key;
    notifyListeners();
  }

  void setPenWidth(String key) {
    penWidth = key;
    notifyListeners();
  }

  /// Everything as it was at an earlier point (undo and redo).
  void restore(List<Map<String, Object?>> was) {
    items = [for (final it in was) _copy(it)];
    sel = -1;
    _all(commit: false);
  }

  /// Sticks a new thing on, where that kind goes best, and picks it. -1 when the tape is full.
  int add(String kind, {Map<String, Object?> fields = const {}}) {
    if (full) return -1;
    final r = _rnd;
    double between(double a, double b) => a + r.nextDouble() * (b - a);
    final it = <String, Object?>{
      'kind': kind,
      'x': _round(0.5 + between(-0.16, 0.16), 4),
      'y': _round(0.46 + between(-0.14, 0.14), 4),
      'rot': _round(between(-8, 8), 1),
    };
    switch (kind) {
      case 'note':
        final used = {
          for (final i in items)
            if (i['kind'] == 'note') i['color'],
        };
        final free = [
          for (final c in noteColors.keys)
            if (!used.contains(c)) c,
        ];
        it.addAll({'s': 0.2, 'color': free.isEmpty ? noteColors.keys.first : free.first});
      case 'photo':
        it.addAll({'s': 0.24, 'rot': _round(between(-9, 9), 1)});
      case 'sticker':
        it.addAll({'s': 0.12, 'rot': _round(between(-16, 16), 1)});
      case 'washi':
        // along an edge or over a corner, the way washi tape holds a real label down
        final spots = [
          (0.5, 0.05, between(-6, 6)),
          (0.08, 0.5, 90 + between(-8, 8)),
          (0.92, 0.5, 90 + between(-8, 8)),
          (0.18, 0.1, -38.0),
          (0.82, 0.1, 38.0),
        ];
        final (x, y, rot) = spots[r.nextInt(spots.length)];
        it.addAll({
          'x': x,
          'y': y,
          'rot': _round(rot, 1),
          's': 0.36,
          'pattern': washiPatterns[r.nextInt(washiPatterns.length)],
          'color': washiColors.keys.elementAt(r.nextInt(washiColors.length)),
        });
      case 'dymo':
        it.addAll({'s': 0.07, 'rot': _round(between(-4, 4), 1), 'color': 'red'});
    }
    it.addAll(fields);
    final clean = cleanItem(it);
    if (clean == null) return -1;
    items.add(clean);
    sel = items.length - 1;
    _all();
    return sel;
  }

  void remove() {
    if (current == null) return;
    items.removeAt(sel);
    sel = -1;
    _all();
  }

  void duplicate() {
    final it = current;
    if (it == null || full) return;
    final twin = _copy(it);
    twin['x'] = _round(_n(twin['x'], 0.5) + 0.04, 4);
    twin['y'] = _round(_n(twin['y'], 0.5) + 0.05, 4);
    items.add(twin);
    sel = items.length - 1;
    _all();
  }

  /// One step up (over the thing above it) or down.
  void restack(bool up) {
    final k = sel, j = up ? sel + 1 : sel - 1;
    if (current == null || j < 0 || j >= items.length) return;
    final t = items[k];
    items[k] = items[j];
    items[j] = t;
    sel = j;
    _all();
  }

  void turn(double degrees) {
    final it = current;
    if (it == null) return;
    it['rot'] = _round(((_n(it['rot']) + degrees + 180) % 360) - 180, 1);
    touched();
  }

  (double, double) sizesOf(Map<String, Object?> it) => itemSizes[it['kind']] ?? (0.05, 1.0);

  /// How big the picked thing is, from 0 to 1 across its kind's sizes (for the size slider).
  double get sizeFrac {
    final it = current;
    if (it == null) return 0.5;
    final (lo, hi) = sizesOf(it);
    return pow(((_n(it['s'], 0.2) - lo) / (hi - lo)).clamp(0.0, 1.0), 1 / 1.6).toDouble();
  }

  void setSize(double frac) {
    final it = current;
    if (it == null) return;
    final (lo, hi) = sizesOf(it);
    it['s'] = _round(lo + (hi - lo) * pow(frac.clamp(0.0, 1.0), 1.6), 4);
    touched(commit: false);
  }

  /// One of the picked thing's settings, or without it when [value] is null.
  void setField(String key, Object? value) {
    final it = current;
    if (it == null) return;
    if (value == null) {
      it.remove(key);
    } else {
      it[key] = value;
    }
    touched();
  }

  /// A line drawn with the pen, from points on the canvas, becomes a thing on the tape like any other.
  void addStroke(List<Offset> points, Geo g) {
    if (points.isEmpty || full) return;
    final q = points.length == 1 ? [points.first, points.first + const Offset(0.6, 0.3)] : points; // a dot
    final xs = [for (final p in q) p.dx], ys = [for (final p in q) p.dy];
    final cx = (xs.reduce(min) + xs.reduce(max)) / 2, cy = (ys.reduce(min) + ys.reduce(max)) / 2;
    final clean = cleanItem({
      'kind': 'ink',
      'x': (cx - g.x) / g.w,
      'y': (cy - g.y) / g.h,
      's': 1.0,
      'rot': 0.0,
      'pts': [
        for (final p in q) [(p.dx - cx) / g.w, (p.dy - cy) / g.w],
      ],
      'w': penWidths[penWidth] ?? 0.0095,
      'color': penColor,
    });
    if (clean == null) return;
    items.add(clean);
    _all();
  }

  /// A handful of random stickers, a strip of washi tape and sometimes a label (the computer's
  /// Surprise me). Undo takes it back. Returns how many things came.
  int surprise({required bool noteShows}) {
    final keys = [
      for (final (_, drawer) in StickerSheet.the?.drawers ?? const <(String, List<String>)>[]) ...drawer,
    ];
    if (keys.isEmpty) return 0;
    final r = _rnd;
    double between(double a, double b) => a + r.nextDouble() * (b - a);
    final spots = [(0.1, 0.86), (0.28, 0.9), (0.72, 0.9), (0.9, 0.86), (0.9, 0.14), (0.62, 0.12), (0.1, 0.6)]..shuffle(r);
    var added = 0;
    for (final (x, y) in spots.take(2 + r.nextInt(3))) {
      if (noteShows && x < 0.25 && y < 0.35) continue; // the corner note is there
      final it = <String, Object?>{
        'kind': 'sticker',
        'shape': keys[r.nextInt(keys.length)],
        'x': x + between(-0.03, 0.03),
        'y': y + between(-0.03, 0.03),
        's': between(0.09, 0.14),
        'rot': between(-20, 20),
      };
      final pick = r.nextInt(11); // glossy most of the time, now and then holo, glitter or matte
      if (pick >= 6) it['finish'] = pick < 8 ? 'holo' : (pick < 10 ? 'glitter' : 'matte');
      final clean = cleanItem(it);
      if (clean != null && !full) {
        items.add(clean);
        added++;
      }
    }
    final washi = cleanItem({
      'kind': 'washi',
      'pattern': washiPatterns[r.nextInt(washiPatterns.length)],
      'color': washiColors.keys.elementAt(r.nextInt(washiColors.length)),
      'x': const [0.5, 0.35, 0.65][r.nextInt(3)],
      'y': r.nextBool() ? 0.04 : 0.96,
      's': between(0.3, 0.45),
      'rot': between(-7, 7),
    });
    if (washi != null && !full) {
      items.insert(0, washi); // under everything else
      added++;
    }
    if (r.nextBool() && !full) {
      final words = ['play loud', 'side A', 'no skips', 'rewind', 'hi-fi', 'mix ${1 + r.nextInt(99)}'][r.nextInt(6)];
      final label = cleanItem({
        'kind': 'dymo',
        'text': words,
        'color': dymoColors.keys.elementAt(r.nextInt(dymoColors.length)),
        'x': between(0.35, 0.65),
        'y': r.nextBool() ? 0.3 : 0.74,
        's': 0.066,
        'rot': between(-5, 5),
      });
      if (label != null) {
        items.add(label);
        added++;
      }
    }
    if (added > 0) {
      sel = -1;
      _all();
    }
    return added;
  }

  void clear() {
    if (items.isEmpty) return;
    items.clear();
    sel = -1;
    _all();
  }

  /// Reads a photo for the tape from the phone (it shows as an empty frame until then).
  Future<void> show(String name) async {
    if (pictures.containsKey(name) || gone) return;
    final f = App.library.havePicture(name);
    if (f == null) return;
    try {
      final codec = await ui.instantiateImageCodec(await f.readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (gone) {
        frame.image.dispose();
        return;
      }
      pictures[name]?.dispose();
      pictures[name] = frame.image;
      refresh();
    } on Object {
      return; // not a picture after all: an empty frame it is
    }
  }

  @override
  void dispose() {
    gone = true;
    for (final img in pictures.values) {
      img.dispose();
    }
    pictures.clear();
    super.dispose();
  }
}

// ---------------------------------------------------------------- the tape to decorate

/// The tape as something to decorate: the things lie over [child] (the cassette, at [box]) and the
/// fingers move them. [onPicked] says a thing got picked, [onWrite] that one to write on was tapped
/// twice, [onTapElse] where a tap found nothing (the corner note, maybe).
class DecorCanvas extends StatefulWidget {
  const DecorCanvas({
    super.key,
    required this.decor,
    required this.box,
    required this.child,
    this.onPicked,
    this.onWrite,
    this.onTapElse,
  });

  final Decorations decor;
  final Rect box;
  final Widget child;
  final VoidCallback? onPicked;
  final void Function(int k)? onWrite;
  final void Function(Offset pos, Geo g)? onTapElse;

  @override
  State<DecorCanvas> createState() => _DecorCanvasState();
}

class _DecorCanvasState extends State<DecorCanvas> {
  final _fingers = <int, Offset>{};
  String _mode = ''; // move, pinch, turn, size, pen, off, or nothing in hand
  bool _going = false;
  bool _moved = false;
  bool _tapOk = false; // no finger moved since the first came down: lifting it is a tap
  Offset _downAt = Offset.zero;
  Offset _start = Offset.zero;
  Map<String, Object?>? _base; // the picked thing as it was when the fingers started
  Offset _center = Offset.zero;
  double _span = 1, _angle = 0;
  final _stroke = <Offset>[];
  int _strokeStamp = 0;
  Size _room = Size.zero;
  int _lastTap = -1;
  DateTime _lastTapAt = DateTime(2000);

  Decorations get _d => widget.decor;

  Geo get _g => Geo(widget.box);

  int _itemAt(Offset pos) {
    final g = _g;
    for (var k = _d.items.length - 1; k >= 0; k--) {
      if (itemHit(g, _d.items[k], pos, slack: 6)) return k;
    }
    return -1;
  }

  String _handleAt(Offset pos) {
    final it = _d.current;
    if (it == null) return '';
    final h = handlesOf(_g, it, _room);
    for (final name in const ['off', 'turn', 'size']) {
      if ((h[name]! - pos).distance <= 22) return name;
    }
    return '';
  }

  Offset _focal() {
    var sum = Offset.zero;
    for (final p in _fingers.values) {
      sum += p;
    }
    return sum / _fingers.length.toDouble();
  }

  (double, double) _pair() {
    final two = _fingers.values.take(2).toList();
    final d = two[1] - two[0];
    return (max(d.distance, 1.0), d.direction);
  }

  void _down(PointerDownEvent e) {
    _fingers[e.pointer] = e.localPosition;
    if (_fingers.length == 1) {
      _downAt = e.localPosition;
      _tapOk = true;
      _begin(fresh: true);
    } else {
      _tapOk = false;
      _begin(fresh: false);
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.localPosition;
    if (_tapOk && (e.localPosition - _downAt).distance > 8) _tapOk = false;
    _update();
  }

  void _up(PointerEvent e) {
    if (_fingers.remove(e.pointer) == null) return;
    if (_fingers.isNotEmpty) {
      _begin(fresh: false); // a finger less: the others carry on from where they are
      return;
    }
    final tap = _tapOk && e is PointerUpEvent;
    _finish();
    if (tap) _tap(_downAt);
  }

  /// Fingers came down, or one more or one less: what's in hand, and where everything starts from.
  void _begin({required bool fresh}) {
    final pos = _focal();
    final g = _g;
    if (_d.pen) {
      if (fresh && g.shell.inflate(4).contains(pos)) {
        _mode = 'pen';
        _stroke
          ..clear()
          ..add(pos);
        _strokeStamp++;
        setState(() {});
      } else if (_mode == 'pen') {
        _finish(); // a second finger ends the line
      }
      return;
    }
    if (fresh) {
      _mode = '';
      _going = false;
      _moved = false;
      final h = _handleAt(pos);
      if (h.isNotEmpty) {
        _mode = h;
      } else {
        final k = _itemAt(pos);
        if (k >= 0) {
          if (k != _d.sel) {
            _d.select(k);
            widget.onPicked?.call();
          }
          _mode = 'move';
        }
      }
    } else if (_going || _mode.isNotEmpty) {
      if (_mode != 'off') _mode = _fingers.length >= 2 ? 'pinch' : 'move';
    } else if (_fingers.length >= 2) {
      // two fingers on the tape pinch the picked thing, or the one between them
      if (_d.current == null) {
        final k = _itemAt(pos);
        if (k < 0) return;
        _d.select(k);
        widget.onPicked?.call();
      }
      _mode = 'pinch';
    }
    final it = _d.current;
    if (_mode.isEmpty || _mode == 'off' || it == null) return;
    _going = true;
    _start = pos;
    _base = Map.of(it);
    _center = itemCenter(g, it);
    if (_fingers.length >= 2) {
      final (span, angle) = _pair();
      _span = span;
      _angle = angle;
    }
  }

  void _update() {
    final pos = _focal();
    if (_mode == 'pen') {
      if ((pos - _stroke.last).distance >= 1.6 && _stroke.length < 900) {
        _stroke.add(pos);
        _strokeStamp++;
        setState(() {});
      }
      return;
    }
    final it = _d.current, base = _base;
    if (!_going || it == null || base == null) return;
    if (!_moved && (pos - _start).distance < 2 && _mode != 'pinch') return;
    _moved = true;
    final g = _g;
    final (lo, hi) = _d.sizesOf(it);
    switch (_mode) {
      case 'move':
        it['x'] = _round((_n(base['x'], 0.5) + (pos.dx - _start.dx) / g.w).clamp(-0.1, 1.1), 4);
        it['y'] = _round((_n(base['y'], 0.5) + (pos.dy - _start.dy) / g.h).clamp(-0.1, 1.1), 4);
      case 'pinch':
        if (_fingers.length < 2) return;
        final (span, angle) = _pair();
        it['s'] = _round((_n(base['s'], 0.2) * span / _span).clamp(lo, hi), 4);
        it['rot'] = _turned(_n(base['rot']) + (angle - _angle) * 180 / pi);
        it['x'] = _round((_n(base['x'], 0.5) + (pos.dx - _start.dx) / g.w).clamp(-0.1, 1.1), 4);
        it['y'] = _round((_n(base['y'], 0.5) + (pos.dy - _start.dy) / g.h).clamp(-0.1, 1.1), 4);
      case 'turn':
        final a0 = (_start - _center).direction, a1 = (pos - _center).direction;
        it['rot'] = _turned(_n(base['rot']) + (a1 - a0) * 180 / pi);
      case 'size':
        final r0 = max(4.0, (_start - _center).distance);
        it['s'] = _round((_n(base['s'], 0.2) * (pos - _center).distance / r0).clamp(lo, hi), 4);
      default:
        return;
    }
    _d.touched(commit: false);
  }

  void _finish() {
    if (_mode == 'pen') {
      final line = List.of(_stroke);
      _stroke.clear();
      _strokeStamp++;
      _mode = '';
      setState(() {});
      _d.addStroke(line, _g);
      return;
    }
    final moved = _moved && _going;
    _mode = '';
    _going = false;
    _moved = false;
    _base = null;
    if (moved) _d.commit();
  }

  void _tap(Offset pos) {
    if (_d.pen) return; // the dot was drawn already
    if (_d.current != null) {
      final h = _handleAt(pos);
      if (h == 'off') {
        _d.remove();
        return;
      }
      if (h.isNotEmpty) return;
    }
    final k = _itemAt(pos);
    if (k >= 0) {
      final now = DateTime.now();
      final twice = k == _lastTap && now.difference(_lastTapAt) < const Duration(milliseconds: 400);
      _lastTap = k;
      _lastTapAt = now;
      if (k != _d.sel) {
        _d.select(k);
        widget.onPicked?.call();
      }
      if (twice && textLimits.containsKey(_d.items[k]['kind'])) widget.onWrite?.call(k);
      return;
    }
    _lastTap = -1;
    _d.select(-1);
    widget.onTapElse?.call(pos, _g);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      _room = Size(box.maxWidth, box.maxHeight);
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: ListenableBuilder(
          listenable: _d,
          builder: (context, _) {
            final n = _d.items.length;
            final sel = _d.current == null ? -1 : _d.sel;
            // what's under the picked thing, the picked thing, and what's over it, each on its own
            // layer: moving one thing doesn't draw the other hundred again
            return Stack(children: [
              Positioned.fromRect(rect: widget.box, child: widget.child),
              Positioned.fill(
                key: const ValueKey('under'),
                child: RepaintBoundary(
                  child: CustomPaint(painter: _Items(_d, 0, sel < 0 ? n : sel, widget.box, _d.stamp, 0)),
                ),
              ),
              if (sel >= 0) ...[
                Positioned.fill(
                  key: const ValueKey('picked'),
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _Items(_d, sel, sel + 1, widget.box, _d.stamp, _d.picked)),
                  ),
                ),
                Positioned.fill(
                  key: const ValueKey('over'),
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _Items(_d, sel + 1, n, widget.box, _d.stamp, 0)),
                  ),
                ),
              ],
              Positioned.fill(
                key: const ValueKey('chrome'),
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _Chrome(_d, widget.box, _room, _stroke, _d.stamp, _d.picked, _strokeStamp),
                  ),
                ),
              ),
            ]);
          },
        ),
      );
    });
  }
}

/// Where a picked thing's handles go: the round one turns it, the corner resizes it, the red one takes
/// it off. Each moves to another side when its usual spot is off the edge (the computer's way), and
/// they keep apart, so a thing in a corner can still be turned and resized.
Map<String, Offset> handlesOf(Geo g, Map<Object?, Object?> it, Size room) {
  final r = itemBox(g, it);
  final c = itemCenter(g, it), a = itemTurn(it);
  final ca = cos(a), sa = sin(a);
  Offset map(Offset p) => c + Offset(p.dx * ca - p.dy * sa, p.dx * sa + p.dy * ca);
  final inside = Rect.fromLTWH(14, 14, max(1.0, room.width - 28), max(1.0, room.height - 28));
  Offset keepIn(Offset p) => Offset(p.dx.clamp(inside.left, inside.right), p.dy.clamp(inside.top, inside.bottom));
  const out = 30.0;
  final sides = [
    (Offset(r.center.dx, r.top - out), Offset(r.center.dx, r.top)),
    (Offset(r.center.dx, r.bottom + out), Offset(r.center.dx, r.bottom)),
    (Offset(r.left - out, r.center.dy), Offset(r.left, r.center.dy)),
    (Offset(r.right + out, r.center.dy), Offset(r.right, r.center.dy)),
  ];
  var (turn, edge) = sides.first;
  for (final (p, e) in sides) {
    if (inside.contains(map(p))) {
      turn = p;
      edge = e;
      break;
    }
  }
  final corners = [r.bottomRight, r.bottomLeft, r.topLeft, r.topRight];
  final size = corners.firstWhere((p) => inside.contains(map(p)), orElse: () => corners.first);
  final rest = [r.topRight, r.topLeft, r.bottomLeft, r.bottomRight];
  final off = rest.firstWhere((p) => p != size && inside.contains(map(p)), orElse: () => rest.firstWhere((p) => p != size));
  final h = {'turn': map(turn), 'size': map(size), 'off': map(off), 'top': map(edge)};
  final placed = <Offset>[];
  for (final name in const ['size', 'off', 'turn']) {
    var p = keepIn(h[name]!);
    for (var k = 0; k < 8 && placed.any((q) => (q - p).distance < 40); k++) {
      final dx = p.dx < room.width / 2 ? 42.0 : -42.0;
      final dy = p.dy < room.height / 2 ? 42.0 : -42.0;
      p = keepIn(p + Offset(dx, dy * 0.4));
    }
    placed.add(p);
    h[name] = p;
  }
  return h;
}

/// The corners of a thing's turned box, for its outline.
List<Offset> _outline(Geo g, Map<Object?, Object?> it) {
  final r = itemBox(g, it);
  final c = itemCenter(g, it), a = itemTurn(it);
  final ca = cos(a), sa = sin(a);
  return [
    for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) c + Offset(p.dx * ca - p.dy * sa, p.dx * sa + p.dy * ca),
  ];
}

class _Items extends CustomPainter {
  _Items(this.d, this.from, this.to, this.box, this.stamp, this.picked);

  final Decorations d;
  final int from, to;
  final Rect box;
  final int stamp, picked;

  @override
  void paint(Canvas canvas, Size size) {
    final end = min(to, d.items.length);
    if (end <= from) return;
    paintItems(canvas, Geo(box), d.items.sublist(from, end), pictures: d.pictures);
  }

  @override
  bool shouldRepaint(_Items old) =>
      old.stamp != stamp || old.picked != picked || old.from != from || old.to != to || old.box != box;
}

/// The picked thing's outline and handles, and the line being drawn.
class _Chrome extends CustomPainter {
  _Chrome(this.d, this.box, this.room, this.stroke, this.stamp, this.picked, this.strokeStamp);

  final Decorations d;
  final Rect box;
  final Size room;
  final List<Offset> stroke;
  final int stamp, picked, strokeStamp;

  @override
  void paint(Canvas canvas, Size size) {
    final g = Geo(box);
    if (stroke.length > 1) {
      canvas.drawPath(
          smoothPath(stroke),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(0.8, (penWidths[d.penWidth] ?? 0.0095) * g.w)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = pickColor(d.penColor, inkColors, inkColors['black']!).withAlpha(238));
    } else if (stroke.length == 1) {
      canvas.drawCircle(
          stroke.first, max(0.8, (penWidths[d.penWidth] ?? 0.0095) * g.w) / 2, Paint()..color = pickColor(d.penColor, inkColors, inkColors['black']!));
    }
    final it = d.current;
    if (it == null) return;
    final corners = _outline(g, it);
    final line = Path()..addPolygon(corners, true);
    canvas.drawPath(
        line,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black.withAlpha(120));
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = Look.accent;
    for (var k = 0; k < 4; k++) {
      _dashes(canvas, corners[k], corners[(k + 1) % 4], dash);
    }
    final h = handlesOf(g, it, room);
    canvas.drawLine(
        h['top']!,
        h['turn']!,
        Paint()
          ..strokeWidth = 1.6
          ..color = Look.accent);
    final face = Paint()..color = Look.cream;
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Look.accent;
    canvas.drawCircle(h['turn']!, 9, face);
    canvas.drawCircle(h['turn']!, 9, rim);
    final corner = RRect.fromRectAndRadius(Rect.fromCenter(center: h['size']!, width: 16, height: 16), const Radius.circular(4));
    canvas.drawRRect(corner, face);
    canvas.drawRRect(corner, rim);
    final off = h['off']!;
    canvas.drawCircle(off, 11.5, Paint()..color = Colors.black.withAlpha(110));
    canvas.drawCircle(off, 10.5, Paint()..color = const Color(0xFFD8402A));
    final x = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    canvas.drawLine(off + const Offset(-3.8, -3.8), off + const Offset(3.8, 3.8), x);
    canvas.drawLine(off + const Offset(3.8, -3.8), off + const Offset(-3.8, 3.8), x);
  }

  void _dashes(Canvas canvas, Offset a, Offset b, Paint paint) {
    final len = (b - a).distance;
    if (len <= 0) return;
    final step = (b - a) / len;
    for (var t = 0.0; t < len; t += 9) {
      canvas.drawLine(a + step * t, a + step * min(t + 5, len), paint);
    }
  }

  @override
  bool shouldRepaint(_Chrome old) =>
      old.stamp != stamp ||
      old.picked != picked ||
      old.strokeStamp != strokeStamp ||
      old.box != box ||
      old.room != room;
}

// ---------------------------------------------------------------- the panel under the tape

/// What can be done with the things on the tape: sticking new ones on, the pen, and whatever the
/// picked one can do. [onUndo] puts back what "Take all off" took.
class DecorPanel extends StatelessWidget {
  const DecorPanel({super.key, required this.decor, required this.noteShows, required this.onUndo});

  final Decorations decor;
  final bool Function() noteShows;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: decor,
      builder: (context, _) {
        if (decor.pen) return _PenPanel(decor);
        final it = decor.current;
        if (it == null) return _AddPanel(decor, noteShows: noteShows, onUndo: onUndo);
        return _ItemPanel(decor, it);
      },
    );
  }
}

/// Writes on a note, a photo's caption or a label (the one at [k]).
Future<void> writeOn(BuildContext context, Decorations d, int k) async {
  if (k < 0 || k >= d.items.length) return;
  final it = d.items[k];
  final kind = '${it['kind']}';
  final most = textLimits[kind];
  if (most == null) return;
  final (title, hint) = switch (kind) {
    'note' => ('Write on the note', 'write something'),
    'dymo' => ('The label says', 'MIXTAPE'),
    _ => ('A caption', 'a caption'),
  };
  final text = await askText(context,
      title: title, hint: hint, start: '${it['text'] ?? ''}', action: 'Done', max: most, blank: true);
  // the thing may be gone by now (undo), or another one picked
  if (text == null || d.gone || k >= d.items.length || !identical(d.items[k], it)) return;
  d.select(k);
  d.setField('text', text.trim().isEmpty ? null : text.trim());
}

/// A photo from the phone for the tape: a new one, or in place of the picked one's picture.
Future<void> addPhoto(BuildContext context, Decorations d, {bool replace = false}) async {
  if (!replace && d.full) {
    say(context, 'This tape is full. Take something off first.');
    return;
  }
  final got = await MixtapeNative.pickTapePhoto();
  if (got == null || d.gone) return;
  final (bytes, png) = got;
  final String name;
  try {
    name = await App.library.keepPicture(bytes, png: png);
  } on FileSystemException {
    if (context.mounted) say(context, "The phone is full, the photo didn't fit.");
    return;
  }
  await d.show(name);
  if (d.gone) return;
  if (replace) {
    d.setField('image', name);
  } else {
    d.add('photo', fields: {'image': name});
  }
}

class _AddPanel extends StatelessWidget {
  const _AddPanel(this.d, {required this.noteShows, required this.onUndo});

  final Decorations d;
  final bool Function() noteShows;
  final VoidCallback onUndo;

  void _add(BuildContext context, String kind, {Map<String, Object?> fields = const {}}) {
    final k = d.add(kind, fields: fields);
    if (k < 0) {
      say(context, 'This tape is full. Take something off first.');
      return;
    }
    if (kind == 'note' || kind == 'dymo') writeOn(context, d, k);
  }

  Future<void> _sticker(BuildContext context) async {
    if (d.full) {
      say(context, 'This tape is full. Take something off first.');
      return;
    }
    final key = await pickSticker(context);
    if (key != null && context.mounted) _add(context, 'sticker', fields: {'shape': key});
  }

  void _surprise(BuildContext context) {
    if (StickerSheet.the == null) return;
    if (d.surprise(noteShows: noteShows()) == 0) say(context, 'This tape is full. Take something off first.');
  }

  void _clear(BuildContext context) {
    d.clear();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Everything is off'),
        action: SnackBarAction(label: 'Undo', onPressed: onUndo),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final n = d.items.length;
    final missing = picturesOf(d.items).difference(d.pictures.keys.toSet()).length;
    final tools = <(String, String, VoidCallback)>[
      ('note', 'Sticky note', () => _add(context, 'note')),
      ('photo', 'Photo', () => addPhoto(context, d)),
      ('sticker', 'Sticker', () => _sticker(context)),
      ('washi', 'Washi tape', () => _add(context, 'washi')),
      ('dymo', 'Label', () => _add(context, 'dymo')),
      ('ink', 'Pen', () => d.setPen(true)),
      ('surprise', 'Surprise me', () => _surprise(context)),
      if (n > 0) ('clear', 'Take all off', () => _clear(context)),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
      LayoutBuilder(builder: (context, box) {
        final w = ((box.maxWidth - 30) / 4).floorToDouble();
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final (kind, name, tap) in tools) SizedBox(width: w, child: _Tool(kind, name, tap, sheet: StickerSheet.the != null)),
        ]);
      }),
      const SizedBox(height: 16),
      Text(
        n == 0
            ? 'Stick things on the tape or draw on it. Tap a thing to change it, drag it around, pinch it '
                'with two fingers to turn and resize it.'
            : '${count(n, 'thing')} on this tape. Tap one to change it, drag it around, pinch it with two '
                'fingers to turn and resize it. Tap it twice to write on it.',
        style: Look.ui(13.5, color: Look.muted, height: 1.35),
      ),
      if (missing > 0) ...[
        const SizedBox(height: 10),
        Text(
          missing == 1
              ? "A photo on this tape isn't on the phone yet: it shows as an empty frame until it comes."
              : "$missing photos on this tape aren't on the phone yet: they show as empty frames until they come.",
          style: Look.ui(13, color: Look.faint, height: 1.35),
        ),
      ],
    ]);
  }
}

/// A button for sticking something on, with a little one of it as its picture.
class _Tool extends StatelessWidget {
  const _Tool(this.kind, this.name, this.onTap, {required this.sheet});

  final String kind, name;
  final VoidCallback onTap;
  final bool sheet; // the stickers are ready (their pictures need them)

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Look.raised,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 9),
            child: Column(children: [
              SizedBox(
                height: 44,
                width: double.infinity,
                child: kind == 'clear'
                    ? const Icon(Icons.layers_clear_outlined, color: Look.muted, size: 26)
                    : CustomPaint(painter: _ToolPicture(kind, sheet)),
              ),
              const SizedBox(height: 5),
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Look.ui(12.5, weight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ToolPicture extends CustomPainter {
  _ToolPicture(this.kind, this.sheet);

  final String kind;
  final bool sheet;

  static const _samples = <String, Map<String, Object?>>{
    'note': {'kind': 'note', 'x': 0.5, 'y': 0.5, 's': 0.34, 'rot': -5, 'color': 'yellow', 'text': 'hi!'},
    'photo': {'kind': 'photo', 'x': 0.5, 'y': 0.5, 's': 0.27, 'rot': 6},
    'washi': {'kind': 'washi', 'x': 0.5, 'y': 0.5, 's': 0.66, 'rot': -14, 'pattern': 'dots', 'color': 'mint'},
    'dymo': {'kind': 'dymo', 'x': 0.5, 'y': 0.5, 's': 0.17, 'rot': -4, 'color': 'red', 'text': 'label'},
    'ink': {
      'kind': 'ink',
      'x': 0.5,
      'y': 0.5,
      's': 1.0,
      'rot': 0,
      'w': 0.028,
      'color': 'blue',
      'pts': [
        [-0.24, 0.07],
        [-0.15, -0.09],
        [-0.05, 0.08],
        [0.05, -0.09],
        [0.14, 0.08],
        [0.24, -0.05],
      ],
    },
  };

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    switch (kind) {
      case 'sticker':
        paintStickerIn(canvas, Rect.fromCenter(center: c, width: 40, height: 40), 'heart', finish: 'holo');
      case 'surprise':
        paintStickerIn(canvas, Rect.fromCenter(center: c, width: 40, height: 40), 'dice', color: 'purple', finish: 'glitter');
      default:
        final it = _samples[kind];
        if (it == null) return;
        paintItem(canvas, Geo(Rect.fromCenter(center: c, width: 100, height: 100 / ratio)), it);
    }
  }

  @override
  bool shouldRepaint(_ToolPicture old) => old.kind != kind || old.sheet != sheet;
}

class _PenPanel extends StatelessWidget {
  const _PenPanel(this.d);

  final Decorations d;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
      Row(children: [
        Expanded(child: Text('Pen', style: Look.ui(18, weight: FontWeight.w800))),
        FilledButton(onPressed: () => d.setPen(false), child: const Text('Done drawing')),
      ]),
      const SizedBox(height: 8),
      Text(
        'Draw right on the tape with a finger. Every line can be moved, recolored or taken off later, like a sticker.',
        style: Look.ui(13.5, color: Look.muted, height: 1.35),
      ),
      const PanelHeading('Color'),
      Swatches([
        for (final MapEntry(:key, :value) in inkColors.entries)
          Swatch(value, inkNames[key] ?? key, d.penColor == key, () => d.setPenColor(key)),
      ]),
      const PanelHeading('Line'),
      Choices([
        for (final (k, name) in const [('fine', 'Fine'), ('medium', 'Medium'), ('bold', 'Bold')])
          (name, d.penWidth == k, () => d.setPenWidth(k)),
      ]),
    ]);
  }
}

class _ItemPanel extends StatelessWidget {
  const _ItemPanel(this.d, this.it);

  final Decorations d;
  final Map<String, Object?> it;

  String get _kind => '${it['kind']}';

  Future<void> _swap(BuildContext context) async {
    final key = await pickSticker(context, current: stickerShapeOf(it), swap: true);
    if (key != null && !d.gone && identical(d.current, it)) d.setField('shape', key);
  }

  Future<void> _anyColor(BuildContext context) async {
    final shape = stickerShapeOf(it);
    final now = pickColor(it['color'], stickerColors, stickerColors[StickerSheet.the?.colorOf(shape) ?? 'red'] ?? Colors.red);
    final picked = await pickAnyColor(context, now, shape: shape, finish: '${it['finish'] ?? 'gloss'}');
    if (picked != null && !d.gone && identical(d.current, it)) d.setField('color', picked);
  }

  Future<void> _notePicture(BuildContext context) async {
    if (it['image'] != null) {
      d.setField('image', null);
      return;
    }
    await addPhoto(context, d, replace: true);
  }

  @override
  Widget build(BuildContext context) {
    final kind = _kind;
    final color = it['color'] is String ? '${it['color']}' : '';
    final sheet = StickerSheet.the;
    final shape = stickerShapeOf(it);
    final title = kindNames[kind] ?? 'Sticker';
    final subtitle = kind == 'sticker' && sheet != null ? sheet.nameOf(shape) : '';
    final blocks = <Widget>[
      if (kind == 'note') ...[
        const PanelHeading('Color'),
        Swatches([
          for (final MapEntry(:key, :value) in noteColors.entries)
            Swatch(value, _named(key), (color.isEmpty ? 'yellow' : color) == key, () => d.setField('color', key)),
        ]),
        const SizedBox(height: 16),
        _Buttons([
          (Icons.edit_outlined, 'Write on it', () => writeOn(context, d, d.sel)),
          (it['image'] != null ? Icons.hide_image_outlined : Icons.image_outlined, it['image'] != null ? 'No picture' : 'Picture',
              () => _notePicture(context)),
        ]),
      ],
      if (kind == 'photo') ...[
        const SizedBox(height: 12),
        _Buttons([
          (Icons.edit_outlined, 'Caption', () => writeOn(context, d, d.sel)),
          (Icons.image_outlined, 'Other picture', () => addPhoto(context, d, replace: true)),
        ]),
      ],
      if (kind == 'sticker') ...[
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => _swap(context),
            icon: SizedBox(
              width: 26,
              height: 26,
              child: CustomPaint(painter: StickerIcon(shape, color: it['color'], finish: '${it['finish'] ?? 'gloss'}')),
            ),
            label: const Text('Swap sticker'),
          ),
        ),
        const PanelHeading('Finish'),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (k, name) in stickerFinishes)
            _FinishSwatch(shape, it['color'], k, name, '${it['finish'] ?? 'gloss'}' == k,
                () => d.setField('finish', k == 'gloss' ? null : k)),
        ]),
        const PanelHeading('Color'),
        Swatches([
          for (final MapEntry(:key, :value) in stickerColors.entries)
            Swatch(value, _named(key), (color.isEmpty ? (sheet?.colorOf(shape) ?? '') : color) == key,
                () => d.setField('color', key)),
          _AnySwatch(color.startsWith('#') ? pickColor(color, const {}, Colors.white) : null, () => _anyColor(context)),
        ]),
      ],
      if (kind == 'washi') ...[
        const PanelHeading('Pattern'),
        Choices([
          for (final k in washiPatterns)
            (_named(k), '${it['pattern'] ?? 'stripes'}' == k, () => d.setField('pattern', k)),
        ]),
        const PanelHeading('Color'),
        Swatches([
          for (final MapEntry(:key, :value) in washiColors.entries)
            Swatch(value, _named(key), (color.isEmpty ? 'pink' : color) == key, () => d.setField('color', key)),
        ]),
      ],
      if (kind == 'dymo') ...[
        const SizedBox(height: 12),
        _Buttons([(Icons.edit_outlined, 'Change the words', () => writeOn(context, d, d.sel))]),
        const PanelHeading('Color'),
        Swatches([
          for (final MapEntry(:key, :value) in dymoColors.entries)
            Swatch(value, _named(key), (color.isEmpty ? 'red' : color) == key, () => d.setField('color', key)),
        ]),
      ],
      if (kind == 'ink') ...[
        const PanelHeading('Color'),
        Swatches([
          for (final MapEntry(:key, :value) in inkColors.entries)
            Swatch(value, inkNames[key] ?? key, (color.isEmpty ? 'black' : color) == key, () => d.setField('color', key)),
        ]),
        const PanelHeading('Line'),
        Choices([
          for (final (k, name) in const [('fine', 'Fine'), ('medium', 'Medium'), ('bold', 'Bold')])
            (name, _nearestWidth(_n(it['w'], 0.0095)) == k, () => d.setField('w', penWidths[k])),
        ]),
      ],
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 28), children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Look.ui(18, weight: FontWeight.w800)),
            if (subtitle.isNotEmpty) Text(subtitle, style: Look.ui(13.5, color: Look.muted)),
          ]),
        ),
        TextButton(onPressed: () => d.select(-1), child: const Text('Done')),
      ]),
      ...blocks,
      const PanelHeading('Size'),
      Slider(value: d.sizeFrac, onChanged: d.setSize, onChangeEnd: (_) => d.commit()),
      const SizedBox(height: 4),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _Act(Icons.rotate_left_rounded, 'Turn left', () => d.turn(-15)),
        _Act(Icons.rotate_right_rounded, 'Turn right', () => d.turn(15)),
        _Act(Icons.flip_to_front_rounded, 'Bring forward', () => d.restack(true)),
        _Act(Icons.flip_to_back_rounded, 'Send backward', () => d.restack(false)),
        _Act(Icons.copy_rounded, 'Duplicate', d.duplicate),
        _Act(Icons.delete_outline_rounded, 'Take it off', d.remove),
      ]),
    ]);
  }
}

String _named(String key) => key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';

String _nearestWidth(double w) {
  var best = 'medium';
  var gap = double.infinity;
  for (final MapEntry(:key, :value) in penWidths.entries) {
    if ((value - w).abs() < gap) {
      gap = (value - w).abs();
      best = key;
    }
  }
  return best;
}

class _Buttons extends StatelessWidget {
  const _Buttons(this.items);

  final List<(IconData, String, VoidCallback)> items;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (icon, name, tap) in items)
          OutlinedButton.icon(
            onPressed: tap,
            icon: Icon(icon, size: 18),
            label: Text(name),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11)),
          ),
      ]);
}

class _Act extends StatelessWidget {
  const _Act(this.icon, this.tip, this.onTap);

  final IconData icon;
  final String tip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tip,
        child: Material(
          color: Look.raised,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(11), child: Icon(icon, size: 21, color: Look.cream)),
          ),
        ),
      );
}

/// The picked sticker in one of the finishes, to pick that finish.
class _FinishSwatch extends StatelessWidget {
  const _FinishSwatch(this.shape, this.color, this.finish, this.name, this.on, this.onTap);

  final String shape;
  final Object? color;
  final String finish, name;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 50,
            height: 50,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Look.raised,
              border: Border.all(color: on ? Look.accent : Look.edge, width: on ? 3 : 1.4),
            ),
            child: CustomPaint(painter: StickerIcon(shape, color: color, finish: finish)),
          ),
          const SizedBox(height: 4),
          Text(name, style: Look.ui(11.5, weight: FontWeight.w600, color: on ? Look.cream : Look.muted)),
        ]),
      ),
    );
  }
}

/// A color of one's own for a sticker: a rainbow until one is picked, then that color.
class _AnySwatch extends StatelessWidget {
  const _AnySwatch(this.color, this.onTap);

  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mine = color;
    return Tooltip(
      message: 'Any color',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: mine,
            gradient: mine == null
                ? const SweepGradient(colors: [
                    Color(0xFFFF5A5A),
                    Color(0xFFFFC94A),
                    Color(0xFF8BE15A),
                    Color(0xFF45D6E0),
                    Color(0xFF5A7BFF),
                    Color(0xFFD65AFF),
                    Color(0xFFFF5A5A),
                  ])
                : null,
            border: Border.all(color: mine != null ? Look.accent : Look.edge, width: mine != null ? 3 : 1.4),
          ),
          child: Icon(Icons.add_rounded, size: 20, color: mine == null ? Colors.white : Colors.white.withAlpha(0)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the sticker sheet

/// A sticker drawn on its own, fitted into its box.
class StickerIcon extends CustomPainter {
  StickerIcon(this.shape, {this.color, this.finish = 'gloss'});

  final String shape;
  final Object? color;
  final String finish;

  @override
  void paint(Canvas canvas, Size size) => paintStickerIn(canvas, Offset.zero & size, shape, color: color, finish: finish);

  @override
  bool shouldRepaint(StickerIcon old) => old.shape != shape || old.color != color || old.finish != finish;
}

/// The sticker sheet: every sticker on its backing paper, a tab per drawer. Gives back the one tapped
/// (to stick on, or with [swap] to put in place of the picked one).
Future<String?> pickSticker(BuildContext context, {String current = '', bool swap = false}) async {
  final StickerSheet sheet;
  try {
    sheet = await StickerSheet.load();
  } on Object {
    if (context.mounted) say(context, "The stickers didn't load. Try again in a moment.");
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => _Sheet(sheet, current: current, swap: swap),
  );
}

class _Sheet extends StatelessWidget {
  const _Sheet(this.sheet, {required this.current, required this.swap});

  final StickerSheet sheet;
  final String current;
  final bool swap;

  static int _lastDrawer = 0;

  @override
  Widget build(BuildContext context) {
    final drawers = sheet.drawers;
    var start = _lastDrawer.clamp(0, drawers.length - 1);
    for (var k = 0; k < drawers.length; k++) {
      if (drawers[k].$2.contains(current)) start = k;
    }
    final all = drawers.fold<int>(0, (n, d) => n + d.$2.length);
    return SafeArea(
      child: LayoutBuilder(builder: (context, box) => _drawers(box.maxWidth, drawers, start, all)),
    );
  }

  Widget _drawers(double width, List<(String, List<String>)> drawers, int start, int all) {
    final cols = width >= 560 ? 8 : (width >= 380 ? 5 : 4);
    final rows = (drawers.fold<int>(0, (n, d) => max(n, d.$2.length)) / cols).ceil();
    final cell = (width - 42) / cols; // the paper's padding and the grid's own
    return DefaultTabController(
      length: drawers.length,
      initialIndex: start,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Row(children: [
            Expanded(child: Text(swap ? 'Swap sticker' : 'Stickers', style: Look.ui(19, weight: FontWeight.w800))),
            Text('$all on the sheet', style: Look.ui(13, color: Look.muted)),
          ]),
        ),
        TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Look.accent,
          labelColor: Look.cream,
          unselectedLabelColor: Look.muted,
          dividerColor: Colors.transparent,
          labelStyle: Look.cond(14, spacing: 1.4),
          onTap: (k) => _lastDrawer = k,
          tabs: [for (final (name, _) in drawers) Tab(text: name.toUpperCase())],
        ),
        SizedBox(
          height: rows * cell + 22,
          child: TabBarView(children: [
            for (final (_, keys) in drawers)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: CustomPaint(
                  painter: const _BackingPaper(),
                  child: GridView.count(
                    crossAxisCount: cols,
                    padding: const EdgeInsets.all(5),
                    physics: const NeverScrollableScrollPhysics(),
                    children: [for (final key in keys) _StickerCell(sheet, key, key == current)],
                  ),
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Text(
            swap
                ? 'Pick a sticker to put in place of this one. It keeps its spot, its size and its turn.'
                : 'Tap one to stick it on, then recolor it or make it holo. Hold one to see its name.',
            style: Look.ui(13, color: Look.muted, height: 1.3),
          ),
        ),
      ]),
    );
  }
}

class _StickerCell extends StatelessWidget {
  const _StickerCell(this.sheet, this.shape, this.current);

  final StickerSheet sheet;
  final String shape;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final b = sheet.box(shape);
    final wide = b.width > b.height * 1.5; // the word badges get the whole cell
    return Tooltip(
      message: sheet.nameOf(shape),
      child: Semantics(
        button: true,
        label: sheet.nameOf(shape),
        onTap: () => Navigator.of(context).pop(shape),
        excludeSemantics: true,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(shape),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: EdgeInsets.all(wide ? 2 : 8),
            decoration: current
                ? BoxDecoration(
                    color: Look.accent.withAlpha(46),
                    border: Border.all(color: Look.accent, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: RepaintBoundary(child: CustomPaint(painter: StickerIcon(shape), size: Size.infinite)),
          ),
        ),
      ),
    );
  }
}

/// The sheet's backing paper, with a faint grid printed on it like a real sticker sheet.
class _BackingPaper extends CustomPainter {
  const _BackingPaper();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFE9DEC6));
    canvas.save();
    canvas.clipRRect(r);
    final grid = Paint()
      ..color = const Color(0x229C8A6C)
      ..strokeWidth = 1;
    for (var y = 8.0; y < size.height; y += 12) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var x = 8.0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackingPaper old) => false;
}

// ---------------------------------------------------------------- a color of one's own

/// Any color for a sticker: the hue, then how light or deep it is, with the sticker itself to see it
/// on. Gives back '#rrggbb', the way the computer keeps one.
Future<String?> pickAnyColor(BuildContext context, Color start, {required String shape, String finish = 'gloss'}) =>
    showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _AnyColor(start, shape, finish),
    );

class _AnyColor extends StatefulWidget {
  const _AnyColor(this.start, this.shape, this.finish);

  final Color start;
  final String shape, finish;

  @override
  State<_AnyColor> createState() => _AnyColorState();
}

class _AnyColorState extends State<_AnyColor> {
  late double _hue;
  late double _shade; // 0 is pale, a half is full color, 1 is deep

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.start);
    _hue = hsv.hue;
    _shade = hsv.value >= 0.98 ? ((hsv.saturation - 0.25) / 1.3).clamp(0.0, 0.5) : (0.5 + (1 - hsv.value) / 1.3).clamp(0.5, 1.0);
  }

  static Color _color(double hue, double shade) {
    final s = shade <= 0.5 ? 0.25 + shade * 1.3 : 0.9;
    final v = shade <= 0.5 ? 1.0 : 1 - (shade - 0.5) * 1.3;
    return HSVColor.fromAHSV(1, hue, s.clamp(0.0, 1.0), v.clamp(0.0, 1.0)).toColor();
  }

  String get _hex => '#${(_color(_hue, _shade).toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Widget _track(List<Color> colors, double value, double most, ValueChanged<double> onChanged) {
    return SizedBox(
      height: 36,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(7), gradient: LinearGradient(colors: colors)),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.transparent,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Look.cream,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          ),
          child: Slider(value: value, max: most, onChanged: onChanged),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = _color(_hue, _shade);
    return AlertDialog(
      backgroundColor: Look.side,
      title: Text('Any color', style: Look.ui(19, weight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 110,
          height: 110,
          child: CustomPaint(painter: StickerIcon(widget.shape, color: _hex, finish: widget.finish)),
        ),
        const SizedBox(height: 14),
        _track([for (var h = 0; h <= 360; h += 60) _color(h.toDouble(), 0.5)], _hue, 360, (v) => setState(() => _hue = v)),
        _track([_color(_hue, 0), now.withAlpha(255), _color(_hue, 0.5), _color(_hue, 1)], _shade, 1,
            (v) => setState(() => _shade = v)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_hex), child: const Text('Use it')),
      ],
    );
  }
}

// ---------------------------------------------------------------- bits the studio shares

class PanelHeading extends StatelessWidget {
  const PanelHeading(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 10),
        child: Text(text.toUpperCase(), style: Look.cond(13, spacing: 2)),
      );
}

class Swatches extends StatelessWidget {
  const Swatches(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 12, children: children);
}

class Swatch extends StatelessWidget {
  const Swatch(this.color, this.name, this.on, this.onTap, {super.key, this.see = false, this.none = false});

  final Color color;
  final String name;
  final bool on;
  final VoidCallback onTap;
  final bool see;
  final bool none;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: Semantics(
        button: true,
        selected: on,
        label: name,
        onTap: onTap,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: see ? color.withValues(alpha: 0.5) : color,
              border: Border.all(color: on ? Look.accent : Look.edge, width: on ? 3 : 1.4),
              boxShadow: on ? [BoxShadow(color: Look.accent.withValues(alpha: 0.4), blurRadius: 10)] : null,
            ),
            child: none ? const Icon(Icons.block_rounded, size: 18, color: Look.muted) : null,
          ),
        ),
      ),
    );
  }
}

class Choices extends StatelessWidget {
  const Choices(this.items, {super.key});

  final List<(String, bool, VoidCallback)> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (name, on, tap) in items)
        ChoiceChip(
          label: Text(name),
          selected: on,
          showCheckmark: false,
          labelStyle: Look.ui(13.5, weight: FontWeight.w600, color: on ? Look.bg : Look.cream),
          selectedColor: Look.cream,
          backgroundColor: Look.raised,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onSelected: (_) => tap(),
        ),
    ]);
  }
}
