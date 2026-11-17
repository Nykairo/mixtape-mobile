/// How the screen may turn: phones stay upright, like the music apps next to them; a tablet or an
/// unfolded foldable turns with the hand. (A video over the whole screen turns the phone on its side
/// for as long as it shows, then puts this back.)
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

bool? _big;

/// Puts the turning the way the app has it: when a foldable folds or unfolds, and with [force] after
/// something else had the screen its own way.
void appTurning({bool force = false}) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return;
  final v = views.first;
  final big = v.physicalSize.shortestSide / v.devicePixelRatio >= 600;
  if (big == _big && !force) return;
  _big = big;
  SystemChrome.setPreferredOrientations(big ? const [] : const [DeviceOrientation.portraitUp]);
}
