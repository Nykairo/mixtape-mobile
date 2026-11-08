/// The few things to set on the phone: the tape stock (the color of what plays) and whether the music
/// goes on with songs like the last one when a list runs out.
library;

import 'package:flutter/foundation.dart';

import 'look.dart';
import 'store.dart';

const _file = 'settings.json';

class Settings extends ChangeNotifier {
  String get stock => Look.stock;
  bool autoplay = true;

  late final _save = LaterSave(_file, () => {'stock': Look.stock, 'autoplay': autoplay},
      delay: const Duration(milliseconds: 400));

  Future<void> load() async {
    final j = await Store.the.read(_file);
    if (j is Map) {
      final s = j['stock'];
      if (s is String && Look.stocks.containsKey(s)) Look.stock = s;
      autoplay = j['autoplay'] != false;
    }
  }

  void setStock(String name) {
    if (!Look.stocks.containsKey(name) || name == Look.stock) return;
    Look.stock = name;
    _save.soon();
    notifyListeners();
  }

  void setAutoplay(bool on) {
    if (on == autoplay) return;
    autoplay = on;
    _save.soon();
    notifyListeners();
  }

  Future<void> flush() => _save.now();
}
