/// The few things to set on the phone: the tape stock (the color of what plays), whether the music goes
/// on with songs like the last one when a list runs out, whether friends can listen along, and how the
/// library shows.
library;

import 'package:flutter/foundation.dart';

import 'look.dart';
import 'store.dart';

const _file = 'settings.json';

class Settings extends ChangeNotifier {
  String get stock => Look.stock;
  bool autoplay = true;

  /// Friends with a Mixtape Account can listen along with what plays here.
  bool shareListening = true;

  /// The library as a grid of cassettes (or a list), and how it's sorted: 'recent', 'name' or 'songs'.
  bool grid = false;
  String sort = 'recent';

  late final _save = LaterSave(_file, () => {
        'stock': Look.stock,
        'autoplay': autoplay,
        'share_listening': shareListening,
        'grid': grid,
        'sort': sort,
      }, delay: const Duration(milliseconds: 400));

  Future<void> load() async {
    final j = await Store.the.read(_file);
    if (j is Map) {
      final s = j['stock'];
      if (s is String && Look.stocks.containsKey(s)) Look.stock = s;
      autoplay = j['autoplay'] != false;
      shareListening = j['share_listening'] != false;
      grid = j['grid'] == true;
      final order = j['sort'];
      if (order is String && const {'recent', 'name', 'songs'}.contains(order)) sort = order;
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

  void setShareListening(bool on) {
    if (on == shareListening) return;
    shareListening = on;
    _save.soon();
    notifyListeners();
  }

  void setLibraryView({bool? grid, String? sort}) {
    if (grid != null) this.grid = grid;
    if (sort != null) this.sort = sort;
    _save.soon();
    notifyListeners();
  }

  Future<void> flush() => _save.now();
}
