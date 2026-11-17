/// The phone Mixtape runs on, for what differs between makers. Plain Android lets music play on with the
/// screen off, but the battery managers of Xiaomi, Huawei, Honor, Oppo, Realme, OnePlus, Vivo, Samsung,
/// Tecno, Infinix and a few others stop it after a while all the same, unless Mixtape is let off in
/// their own settings. This knows whose phone it is, whether that's done, and how to get there.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mixtape_native/mixtape_native.dart';

class PhoneInfo extends ChangeNotifier with WidgetsBindingObserver {
  PhoneInfo._();

  static final the = PhoneInfo._();

  String maker = '';
  String brand = '';
  String model = '';

  /// Android's battery saving leaves Mixtape alone (always true off Android).
  bool batteryFree = true;

  /// Android Go or under 3 GB of memory.
  bool lowRam = false;

  /// The Android version as its API level (33 is Android 13), 0 when it isn't known or not Android.
  int android = 0;

  bool _watching = false;

  /// Makers whose battery managers are known to stop music in the background.
  static const strict = {
    'xiaomi', 'huawei', 'honor', 'oppo', 'realme', 'oneplus', 'vivo', 'samsung', 'transsion', 'asus', 'nokia', 'meizu',
  };

  /// What to switch on the maker's own page, in the words their settings use.
  static const _tips = {
    'xiaomi': 'Turn on Autostart for Mixtape, and in its battery saver pick No restrictions.',
    'huawei': 'Under App launch, set Mixtape to Manage manually and leave all three switches on.',
    'honor': 'Under App launch, set Mixtape to Manage manually and leave all three switches on.',
    'oppo': 'Allow Mixtape to auto launch and to run in the background (Battery, App battery management).',
    'realme': 'Allow Mixtape to auto launch and to run in the background (Battery, App battery management).',
    'oneplus': 'Allow Mixtape to auto launch and to run in the background (Battery, App battery management).',
    'vivo': 'Allow Mixtape high background power use, and to start by itself.',
    'samsung': "Set Mixtape's Battery to Unrestricted, and keep it off the list of sleeping apps.",
    'transsion': 'In Phone Master, let Mixtape auto-start and leave it out of power saving.',
    'asus': 'In Mobile Manager, allow Mixtape to auto-start.',
    'nokia': "Add Mixtape to the battery saver's exceptions.",
    'meizu': 'In Security, allow Mixtape to run in the background.',
  };

  bool get isStrict => strict.contains(maker);

  String get tip => _tips[maker] ?? '';

  /// The name to say: the brand on the phone the way its maker writes it (samsung and HUAWEI come out as
  /// Samsung and Huawei; Redmi, POCO, OPPO and OnePlus stay as they are).
  String get name {
    final b = brand.isNotEmpty ? brand : maker;
    if (b.isEmpty) return 'this phone';
    final shouted = b == b.toUpperCase() && b.length > 4;
    if (b == b.toLowerCase() || shouted) return b[0].toUpperCase() + b.substring(1).toLowerCase();
    return b;
  }

  Future<void> load() async {
    if (!Platform.isAndroid) return;
    await refresh();
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addObserver(this); // back from the settings: see what changed there
    }
  }

  Future<void> refresh() async {
    final p = await MixtapeNative.phone();
    if (p.isEmpty) return;
    maker = '${p['maker'] ?? ''}';
    brand = '${p['brand'] ?? ''}';
    model = '${p['model'] ?? ''}';
    batteryFree = p['batteryFree'] != false;
    lowRam = p['lowRam'] == true;
    final level = p['android'];
    if (level is int) android = level;
    notifyListeners();
  }

  Future<void> askBatteryFree() => MixtapeNative.askBatteryFree();

  Future<void> openMakerSettings() => MixtapeNative.openMakerSettings();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }
}
