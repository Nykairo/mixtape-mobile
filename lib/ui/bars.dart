/// The phone's own bars over the app. Mixtape draws edge to edge, so a page that scrolls would slide its
/// words under the clock and the battery; [StatusShade] lays a band of the page's color there once the
/// page has moved, and takes it away again at the top.
library;

import 'package:flutter/material.dart';

import '../look.dart';

/// A band over one of the phone's bars, solid while [visible]. A widget of its own, so the page tests
/// can tell what it covers.
class BarShade extends StatelessWidget {
  const BarShade({super.key, required this.visible, this.color});

  final bool visible;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: ColoredBox(color: color ?? Look.bg),
      ),
    );
  }
}

/// [child] with a [BarShade] over the status bar while its main list is scrolled away from the top.
class StatusShade extends StatefulWidget {
  const StatusShade({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  State<StatusShade> createState() => _StatusShadeState();
}

class _StatusShadeState extends State<StatusShade> {
  bool _moved = false;

  bool _scrolled(ScrollNotification n) {
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      final moved = n.metrics.pixels > 1;
      if (moved != _moved) setState(() => _moved = moved);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(children: [
      NotificationListener<ScrollNotification>(onNotification: _scrolled, child: widget.child),
      if (top > 0)
        Positioned(left: 0, right: 0, top: 0, height: top, child: BarShade(visible: _moved, color: widget.color)),
    ]);
  }
}
