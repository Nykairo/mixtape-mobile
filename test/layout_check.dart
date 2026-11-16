// What looks wrong on the screen right now, the way someone holding the phone would see it: words
// lying on other words, buttons half on top of each other, words or buttons under the status bar or
// the keys at the bottom, and words running off the side of the screen.
//
// Only what can be seen counts: a tap on the middle of it has to reach it. Words of a page under a
// sheet, or scrolled out of sight, are left alone.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixtape/ui/bars.dart';

class _Seen {
  _Seen(this.what, this.rect, this.box, {this.sideways = false, this.list});

  final String what;
  final Rect rect;
  final RenderBox box;

  /// In a list that scrolls sideways, which goes on past the screen's edge by design.
  final bool sideways;

  /// The list it scrolls in (null when it doesn't): a row half under the tabs is just scrolled there.
  final Element? list;
}

Element? _listOf(Element e) {
  Element? found;
  e.visitAncestorElements((a) {
    if (a.widget is Scrollable) {
      found = a;
      return false;
    }
    return true;
  });
  return found;
}

/// [rect] cut to the lists it scrolls in: what's scrolled out of a list can't be seen.
Rect _visible(Element e, Rect rect) {
  var out = rect;
  e.visitAncestorElements((a) {
    if (a.widget is Scrollable && a.renderObject is RenderBox && (a.renderObject as RenderBox).hasSize) {
      final box = a.renderObject as RenderBox;
      out = out.intersect(_global(box, Offset.zero & box.size));
    }
    return true;
  });
  return out.isEmpty ? Rect.zero : out;
}

bool _inSideways(Element e) {
  var sideways = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Scrollable && w.axisDirection != AxisDirection.down && w.axisDirection != AxisDirection.up) {
      sideways = true;
      return false;
    }
    return true;
  });
  return sideways;
}

/// An icon is drawn as a letter of an icon font (from Unicode's private areas): no words to read.
bool _icon(String s) => s.runes.every((r) => (r >= 0xE000 && r <= 0xF8FF) || r >= 0xF0000 || r == 0x20);

/// Where the app lays its own band over one of the phone's bars (see BarShade).
List<Rect> _shades() => [
      for (final e in find.byType(BarShade).evaluate())
        if ((e.widget as BarShade).visible && e.renderObject is RenderBox && (e.renderObject as RenderBox).hasSize)
          _global(e.renderObject as RenderBox, Offset.zero & (e.renderObject as RenderBox).size),
    ];

bool _reaches(WidgetTester tester, Offset at, RenderObject target) {
  final result = HitTestResult();
  tester.binding.hitTestInView(result, at, tester.view.viewId);
  return result.path.any((h) => h.target == target);
}

Rect _global(RenderBox box, Rect local) => MatrixUtils.transformRect(box.getTransformTo(null), local);

double _area(Rect r) => r.isEmpty ? 0 : r.width * r.height;

/// The words on the screen that can be seen, each with the room its letters take.
List<_Seen> _words(WidgetTester tester) {
  final out = <_Seen>[];
  final root = find.byType(Navigator).first;
  for (final e in find.descendant(of: root, matching: find.byType(RichText)).evaluate()) {
    final box = e.renderObject;
    if (box is! RenderParagraph || !box.attached || !box.hasSize || box.size.isEmpty) continue;
    final text = box.text.toPlainText();
    if (text.trim().isEmpty) continue;
    var local = Rect.zero;
    for (final b in box.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length))) {
      local = local.isEmpty ? b.toRect() : local.expandToInclude(b.toRect());
    }
    if (local.isEmpty) continue;
    final rect = _visible(e, _global(box, local));
    if (rect.isEmpty || !_reaches(tester, rect.center, box)) continue;
    out.add(_Seen(text.replaceAll('\n', ' '), rect, box, sideways: _inSideways(e), list: _listOf(e)));
  }
  return out;
}

/// The things on the screen that take a tap and can be seen.
List<_Seen> _buttons(WidgetTester tester) {
  final out = <_Seen>[];
  final root = find.byType(Navigator).first;
  final taps = find.descendant(
    of: root,
    matching: find.byWidgetPredicate((w) =>
        (w is InkResponse && (w.onTap != null || w.onLongPress != null)) ||
        (w is GestureDetector && w.onTap != null) ||
        w is Switch ||
        w is Slider),
  );
  for (final e in taps.evaluate()) {
    final box = e.renderObject;
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) continue;
    final rect = _visible(e, _global(box, Offset.zero & box.size));
    if (rect.isEmpty || !_reaches(tester, rect.center, box)) continue;
    final label = find.descendant(of: find.byElementPredicate((x) => x == e), matching: find.byType(RichText)).evaluate();
    final words = label.isEmpty ? '' : (label.first.renderObject as RenderParagraph).text.toPlainText();
    final tip = e.findAncestorWidgetOfExactType<Tooltip>()?.message ?? '';
    out.add(_Seen(words.isNotEmpty ? words : (tip.isNotEmpty ? tip : e.widget.runtimeType.toString()), rect, box,
        list: _listOf(e)));
  }
  return out;
}

String _short(String s) => s.length > 32 ? '${s.substring(0, 30)}…' : s;

/// One line for each thing that looks wrong, empty when everything sits where it should.
List<String> layoutProblems(WidgetTester tester) {
  final ratio = tester.view.devicePixelRatio;
  final screen = Offset.zero & (tester.view.physicalSize / ratio);
  final top = tester.view.padding.top / ratio;
  final bottom = tester.view.padding.bottom / ratio;
  final status = Rect.fromLTRB(0, 0, screen.width, top);
  final keys = Rect.fromLTRB(0, screen.height - bottom, screen.width, screen.height);
  final out = <String>[];

  final shades = _shades();
  bool shaded(Rect r) => shades.any((s) => s.contains(r.center));
  final words = _words(tester);
  for (var i = 0; i < words.length; i++) {
    final a = words[i];
    if (!a.sideways && !_icon(a.what) && (a.rect.left < screen.left - 1 || a.rect.right > screen.right + 1)) {
      out.add('"${_short(a.what)}" runs off the side of the screen');
    }
    if (top > 0 && a.rect.intersect(status).height > a.rect.height * 0.3 && !shaded(a.rect.intersect(status))) {
      out.add('"${_short(a.what)}" is under the status bar');
    }
    if (bottom > 0 && a.rect.intersect(keys).height > a.rect.height * 0.3 && !shaded(a.rect.intersect(keys))) {
      out.add('"${_short(a.what)}" is under the keys at the bottom');
    }
    for (var j = i + 1; j < words.length; j++) {
      final b = words[j];
      final both = a.rect.intersect(b.rect);
      if (both.isEmpty) continue;
      // the same words twice in the same place is a shadow or an outline, drawn on purpose
      if (a.what == b.what && (a.rect.center - b.rect.center).distance < 4) continue;
      // letters' boxes are taller than the letters (handwriting most of all): only a real overlap
      // counts, and only where it can be seen (not where a bar on top covers both)
      final small = math.min(_area(a.rect), _area(b.rect));
      final low = math.min(a.rect.height, b.rect.height);
      if (_area(both) > math.max(12.0, small * 0.3) && both.height > low * 0.4) {
        final hit = HitTestResult();
        tester.binding.hitTestInView(hit, both.center, tester.view.viewId);
        if (hit.path.any((h) => h.target == a.box || h.target == b.box)) {
          out.add('"${_short(a.what)}" lies on "${_short(b.what)}"');
        }
      }
    }
  }

  final buttons = _buttons(tester);
  for (var i = 0; i < buttons.length; i++) {
    final a = buttons[i];
    final area = _area(a.rect);
    if (top > 0 && _area(a.rect.intersect(status)) > area * 0.4 && !shaded(a.rect.intersect(status))) {
      out.add('button "${_short(a.what)}" is under the status bar');
    }
    if (bottom > 0 && _area(a.rect.intersect(keys)) > area * 0.4 && !shaded(a.rect.intersect(keys))) {
      out.add('button "${_short(a.what)}" is under the keys at the bottom');
    }
    for (var j = i + 1; j < buttons.length; j++) {
      final b = buttons[j];
      // only buttons of the same list (or both of none) can be out of place against each other
      if (a.list != b.list) continue;
      final both = a.rect.intersect(b.rect);
      if (both.isEmpty) continue;
      // one inside the other (a key on a card) is how it's meant to be
      if (a.rect.inflate(1).contains(b.rect.topLeft) && a.rect.inflate(1).contains(b.rect.bottomRight)) continue;
      if (b.rect.inflate(1).contains(a.rect.topLeft) && b.rect.inflate(1).contains(a.rect.bottomRight)) continue;
      if (_area(both) > math.min(area, _area(b.rect)) * 0.25) {
        out.add('buttons "${_short(a.what)}" and "${_short(b.what)}" lie on each other');
      }
    }
  }
  return out;
}
