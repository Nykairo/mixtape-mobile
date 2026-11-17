"""Makes assets/stickers.json, the phone's sticker sheet, from the computer's stickers.py.

The computer draws every sticker with Qt: an outline, and details painted on top of the body color.
This runs that same drawing code against a stand-in painter that writes down, instead of drawing,
every step it is asked for, in the sticker's own units (one unit across): a shape filled, a line
drawn with its width, caps and joins, and the clip it was drawn in. The phone then repeats those
steps one after another, which is all its painter has to know.

Details sometimes depend on the sticker's color (a flower's middle is orange on a yellow flower), so
each sticker is written down once per color of the palette; where the shapes are the same for every
color, they are kept once with a color per palette entry.

    QT_QPA_PLATFORM=offscreen python3 tool/stickers_from_desktop.py ../mixtape assets/stickers.json

It checks itself: every sticker is drawn both ways (Qt directly, and from what was written down) and
the two pictures are compared pixel by pixel.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

desktop = Path(sys.argv[1]).resolve()
out_file = Path(sys.argv[2])
sys.path.insert(0, str(desktop))

from PyQt6.QtCore import QLineF, QPointF, QRectF, Qt  # noqa: E402
from PyQt6.QtGui import (QBrush, QColor, QFontMetricsF, QGradient, QImage, QLinearGradient, QPainter,  # noqa: E402
                         QPainterPath, QPainterPathStroker, QPen, QPolygonF, QRadialGradient, QTransform)
from PyQt6.QtWidgets import QApplication  # noqa: E402

app = QApplication([])
import decor  # noqa: E402
import stickers as ST  # noqa: E402

S = 1000.0  # drawn this big, so curves stay round and hairlines don't matter


class Rec:
    """A painter that writes down what it's asked to draw, the way the phone can draw it again: filled
    shapes and lines (with their width, ends and corners), each with its brush and the clipping around
    it, in sticker units."""

    def __init__(self) -> None:
        self.ops: list = []
        self.t = QTransform()
        self.pen = QPen(Qt.PenStyle.NoPen)
        self.brush = QBrush()
        self.clip: list = []  # clip paths in the sticker's units, one inside the other
        self.opacity = 1.0
        self.font = None
        self.stack: list = []

    # -------- state
    def save(self) -> None:
        self.stack.append((QTransform(self.t), QPen(self.pen), QBrush(self.brush), list(self.clip), self.opacity, self.font))

    def restore(self) -> None:
        self.t, self.pen, self.brush, self.clip, self.opacity, self.font = self.stack.pop()

    def translate(self, *a) -> None:
        dx, dy = (a[0].x(), a[0].y()) if len(a) == 1 else a
        self.t = QTransform().translate(dx, dy) * self.t

    def rotate(self, deg: float) -> None:
        self.t = QTransform().rotate(deg) * self.t

    def scale(self, sx: float, sy: float) -> None:
        self.t = QTransform().scale(sx, sy) * self.t

    def setPen(self, pen) -> None:
        self.pen = QPen(Qt.PenStyle.NoPen) if pen == Qt.PenStyle.NoPen else QPen(pen)

    def setBrush(self, brush) -> None:
        self.brush = QBrush() if brush == Qt.BrushStyle.NoBrush else QBrush(brush)

    def setOpacity(self, o: float) -> None:
        self.opacity = o

    def setFont(self, f) -> None:
        self.font = f

    def setRenderHint(self, *a) -> None:
        pass

    def setRenderHints(self, *a) -> None:
        pass

    def setCompositionMode(self, mode) -> None:
        if mode != QPainter.CompositionMode.CompositionMode_SourceOver:
            raise RuntimeError(f"composition mode {mode} is not written down")

    def setClipPath(self, path: QPainterPath, op=Qt.ClipOperation.ReplaceClip) -> None:
        mapped = self.t.map(path)
        mapped.setFillRule(path.fillRule())
        self.clip = (self.clip if op == Qt.ClipOperation.IntersectClip else []) + [mapped]

    def setClipRect(self, rect, op=Qt.ClipOperation.ReplaceClip) -> None:
        p = QPainterPath()
        p.addRect(QRectF(rect))
        self.setClipPath(p, op)

    # -------- what gets drawn
    def _scale(self) -> float:
        return math.sqrt(abs(self.t.determinant()))

    def _shape(self, path: QPainterPath, fill: bool = True, stroke: bool = True) -> None:
        if fill and self.brush.style() != Qt.BrushStyle.NoBrush:
            mapped = self.t.map(path)
            mapped.setFillRule(path.fillRule())
            self._put("w" if path.fillRule() == Qt.FillRule.WindingFill else "e", mapped, self.brush)
        if stroke and self.pen.style() != Qt.PenStyle.NoPen:
            if self.pen.style() == Qt.PenStyle.SolidLine:
                self._put("s", self.t.map(path), self.pen.brush(), self.pen.widthF() * self._scale(),
                          self.pen.capStyle(), self.pen.joinStyle())
            else:  # a dashed line goes down as the dashes' outlines
                st = QPainterPathStroker(self.pen)
                self._put("w", self.t.map(st.createStroke(path)), self.pen.brush())

    def _put(self, kind: str, path: QPainterPath, brush: QBrush, width: float = 0.0, cap=None, join=None) -> None:
        if path.isEmpty():
            return
        self.ops.append((kind, path, QBrush(brush), self.opacity, QTransform(self.t), width, cap, join, list(self.clip)))

    def drawPath(self, path: QPainterPath) -> None:
        self._shape(path)

    def fillPath(self, path: QPainterPath, brush) -> None:
        old = self.brush
        self.setBrush(brush)
        self._shape(path, stroke=False)
        self.brush = old

    def strokePath(self, path: QPainterPath, pen) -> None:
        old = self.pen
        self.setPen(pen)
        self._shape(path, fill=False)
        self.pen = old

    def drawEllipse(self, *a) -> None:
        p = QPainterPath()
        if len(a) == 3:
            p.addEllipse(QPointF(a[0]), a[1], a[2])
        elif len(a) == 1:
            p.addEllipse(QRectF(a[0]))
        else:
            p.addEllipse(QRectF(*a))
        self._shape(p)

    def drawRect(self, *a) -> None:
        p = QPainterPath()
        p.addRect(QRectF(*a) if len(a) == 4 else QRectF(a[0]))
        self._shape(p)

    def fillRect(self, rect, brush) -> None:
        p = QPainterPath()
        p.addRect(QRectF(rect))
        self.fillPath(p, brush)

    def drawRoundedRect(self, rect, rx: float, ry: float, mode=Qt.SizeMode.AbsoluteSize) -> None:
        p = QPainterPath()
        p.addRoundedRect(QRectF(rect), rx, ry, mode)
        self._shape(p)

    def drawLine(self, *a) -> None:
        if len(a) == 1:
            line = QLineF(a[0])
            a1, a2 = line.p1(), line.p2()
        elif len(a) == 2:
            a1, a2 = QPointF(a[0]), QPointF(a[1])
        else:
            a1, a2 = QPointF(a[0], a[1]), QPointF(a[2], a[3])
        p = QPainterPath(a1)
        p.lineTo(a2)
        self._shape(p, fill=False)

    def drawPolygon(self, poly, *rest) -> None:
        p = QPainterPath()
        p.addPolygon(QPolygonF(poly))
        p.closeSubpath()
        self._shape(p)

    def drawPolyline(self, poly) -> None:
        p = QPainterPath()
        p.addPolygon(QPolygonF(poly))
        self._shape(p, fill=False)

    def drawArc(self, rect, start: int, span: int) -> None:
        p = QPainterPath()
        p.arcMoveTo(QRectF(rect), start / 16)
        p.arcTo(QRectF(rect), start / 16, span / 16)
        self._shape(p, fill=False)

    def drawPie(self, rect, start: int, span: int) -> None:
        r = QRectF(rect)
        p = QPainterPath(r.center())
        p.arcTo(r, start / 16, span / 16)
        p.closeSubpath()
        self._shape(p)

    def drawText(self, rect, flags, text: str) -> None:
        r = QRectF(rect)
        fm = QFontMetricsF(self.font)
        lines = text.split("\n")
        lh = fm.height()
        top = r.center().y() - lh * len(lines) / 2
        path = QPainterPath()
        for k, line in enumerate(lines):
            w = fm.horizontalAdvance(line)
            path.addText(QPointF(r.center().x() - w / 2, top + lh * k + fm.ascent()), self.font, line)
        path.setFillRule(Qt.FillRule.WindingFill)
        old = self.brush
        self.brush = self.pen.brush()
        self._shape(path, stroke=False)
        self.brush = old


def _op(a: QPainterPath, b: QPainterPath, what: str) -> QPainterPath:
    return a.intersected(b) if what == "and" else a.united(b)


def d_of(path: QPainterPath) -> str:
    """A path in SVG's words (M, L, C, Z), in sticker units, three decimals. A subpath that ends where
    it began is closed (Z), the way Qt's stroker takes it: corners there, not two line ends."""
    out: list = []
    n = path.elementCount()

    def f(v: float) -> str:
        t = f"{v / S:.3f}".rstrip("0").rstrip(".")
        return "0" if t in ("-0", "") else t

    k = 0
    start = last = None
    while k < n:
        e = path.elementAt(k)
        if e.type == QPainterPath.ElementType.MoveToElement:
            if start is not None and last is not None and _same(start, last):
                out.append("Z")
            out.append(f"M{f(e.x)} {f(e.y)}")
            start = last = (e.x, e.y)
            k += 1
        elif e.type == QPainterPath.ElementType.LineToElement:
            out.append(f"L{f(e.x)} {f(e.y)}")
            last = (e.x, e.y)
            k += 1
        elif e.type == QPainterPath.ElementType.CurveToElement:
            c2, end = path.elementAt(k + 1), path.elementAt(k + 2)
            out.append(f"C{f(e.x)} {f(e.y)} {f(c2.x)} {f(c2.y)} {f(end.x)} {f(end.y)}")
            last = (end.x, end.y)
            k += 3
        else:
            k += 1
    if start is not None and last is not None and _same(start, last):
        out.append("Z")
    return "".join(out)


def _same(a, b) -> bool:
    return abs(a[0] - b[0]) < 1e-3 and abs(a[1] - b[1]) < 1e-3


def hex8(c: QColor, opacity: float = 1.0) -> str:
    a = round(c.alpha() * opacity)
    return f"{c.red():02x}{c.green():02x}{c.blue():02x}{a:02x}"


def brush_of(brush: QBrush, opacity: float, t: QTransform):
    """A brush as the phone needs it: a color, or a gradient in sticker units."""
    g = brush.gradient()
    if g is None:
        return hex8(brush.color(), opacity)
    stops = [[round(at, 3), hex8(c, opacity)] for at, c in g.stops()]
    if g.type() == QGradient.Type.LinearGradient:
        lg = QLinearGradient(g)  # noqa
        a, b = t.map(g.start()), t.map(g.finalStop())
        return {"l": [round(a.x() / S, 3), round(a.y() / S, 3), round(b.x() / S, 3), round(b.y() / S, 3)], "s": stops}
    if g.type() == QGradient.Type.RadialGradient:
        c = t.map(g.center())
        f = t.map(g.focalPoint())
        k = math.hypot(t.m11(), t.m12())
        return {"r": [round(c.x() / S, 3), round(c.y() / S, 3), round(g.radius() * k / S, 3),
                      round(f.x() / S, 3), round(f.y() / S, 3)], "s": stops}
    raise RuntimeError(f"gradient {g.type()} is not written down")


CAPS = {Qt.PenCapStyle.RoundCap: "r", Qt.PenCapStyle.FlatCap: "f", Qt.PenCapStyle.SquareCap: "q"}
JOINS = {Qt.PenJoinStyle.RoundJoin: "r", Qt.PenJoinStyle.MiterJoin: "m", Qt.PenJoinStyle.BevelJoin: "b",
         Qt.PenJoinStyle.SvgMiterJoin: "m"}


def record(shape: str, color: QColor) -> list:
    """The details of one sticker in one color: [shape, brush], the shape as [kind, d, ...] (the same
    for every color when the drawing doesn't depend on it)."""
    r = Rec()
    ST.details(r, shape, S, color, True)
    out = []
    for kind, path, brush, op, t, width, cap, join, clip in r.ops:
        geo: list = [kind, d_of(path)]
        if kind == "s":
            geo += [round(width / S, 4), CAPS.get(cap, "q"), JOINS.get(join, "b")]
        if clip:
            geo.append([("w" if c.fillRule() == Qt.FillRule.WindingFill else "e") + d_of(c) for c in clip])
        out.append((geo, brush_of(brush, op, t)))
    return out


palette = list(decor.STICKER_COLORS.items())
sheet: dict = {"colors": [n for n, _ in palette], "hex": [h for _, h in palette], "cats": [], "s": {}}
for cat, rows in ST.CATEGORIES:
    sheet["cats"].append([cat, [k for k, _n, _c in rows]])
for shape in ST.SHAPES:
    outline = decor.shape_path(shape)
    up = QTransform().scale(S, S)
    box = decor.sticker_box(shape)
    entry = {
        "n": ST.NAMES[shape],
        "c": ST.COLORS[shape],
        "o": d_of(up.map(outline)),
        "b": [round(box.x(), 3), round(box.y(), 3), round(box.width(), 3), round(box.height(), 3)],
    }
    per = [record(shape, QColor(h)) for _, h in palette]
    same = all(len(p) == len(per[0]) and all(a[0] == b[0] for a, b in zip(p, per[0])) for p in per)
    if not same:
        raise RuntimeError(f"{shape}: its drawing changes with its color, which the phone can't follow")
    ops = []
    for k, (geo, _b) in enumerate(per[0]):
        brushes = [p[k][1] for p in per]
        one = all(json.dumps(b) == json.dumps(brushes[0]) for b in brushes)
        ops.append(geo + [brushes[0] if one else {"each": brushes}])  # "each": one brush per palette color
    entry["d"] = ops
    sheet["s"][shape] = entry

text = json.dumps(sheet, separators=(",", ":"))
out_file.parent.mkdir(parents=True, exist_ok=True)
out_file.write_text(text)
print(f"{len(sheet['s'])} stickers, {len(text) // 1024} KB")
