/// How Mixtape looks on the phone: the cassette look from the computer. Warm black plastic, cream label
/// paper, ballpoint ink, and the tape color (orange unless picked otherwise) for what plays.
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import 'model.dart';

class Look {
  // the deck
  static const bg = Color(0xFF191410);
  static const side = Color(0xFF201A15);
  static const raised = Color(0xFF2A221C);
  static const edge = Color(0xFF3A3029);
  static const cream = Color(0xFFF1E6CF);
  static const muted = Color(0xFFA99A88);
  static const faint = Color(0xFF7A6D60);
  static const ink = Color(0xFF25428E);
  static const tape = Color(0xFF3B2618);

  /// The tape stocks: an accent and the two other label stripes (the computer's Settings, Look).
  static const stocks = <String, List<Color>>{
    'Ferric': [Color(0xFFFF6A1A), Color(0xFFFFA323), Color(0xFFFFD567)],
    'Chrome': [Color(0xFF4DA3FF), Color(0xFF2A6CD4), Color(0xFFA9DBFF)],
    'Metal': [Color(0xFFE7B24A), Color(0xFFC47A2C), Color(0xFFF5DC93)],
    'Rose': [Color(0xFFFF5F8F), Color(0xFFFF9A72), Color(0xFFFFD2B8)],
    'Mint': [Color(0xFF39D0A0), Color(0xFF9BDC63), Color(0xFFE4F59B)],
  };
  static String stock = 'Ferric';

  static List<Color> get stripes => stocks[stock] ?? stocks['Ferric']!;
  static Color get accent => stripes[0];

  static TextStyle ui(double size, {FontWeight weight = FontWeight.w400, Color color = cream, double? height}) =>
      TextStyle(fontFamily: 'Barlow', fontSize: size, fontWeight: weight, color: color, height: height);

  /// Condensed capitals for headings, printed like a deck's lettering.
  static TextStyle cond(double size, {FontWeight weight = FontWeight.w700, Color color = muted, double spacing = 1.4}) =>
      TextStyle(
          fontFamily: 'Barlow Condensed', fontSize: size, fontWeight: weight, color: color, letterSpacing: spacing);

  /// Handwriting, for tape labels and sticky notes.
  static TextStyle hand(double size, {Color color = ink}) =>
      TextStyle(fontFamily: 'Covered By Your Grace', fontSize: size, color: color, height: 1.0);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: bg,
    ).copyWith(primary: accent, onPrimary: bg, secondary: stripes[1], surface: bg, onSurface: cream);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      fontFamily: 'Barlow',
      splashFactory: InkSparkle.splashFactory,
      textTheme: ThemeData.dark().textTheme.apply(bodyColor: cream, displayColor: cream, fontFamily: 'Barlow'),
      iconTheme: const IconThemeData(color: muted),
      dividerColor: edge,
      snackBarTheme: SnackBarThemeData(
        backgroundColor: raised,
        contentTextStyle: ui(14, color: cream),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: side,
        showDragHandle: true,
        dragHandleColor: edge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        hintStyle: ui(15, color: faint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: edge)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: edge)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accent)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: bg,
          textStyle: ui(15, weight: FontWeight.w700),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cream,
          side: const BorderSide(color: edge),
          textStyle: ui(15, weight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: muted, textStyle: ui(14, weight: FontWeight.w600)),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: accent,
        inactiveTrackColor: edge,
        thumbColor: cream,
        overlayColor: accent.withValues(alpha: 0.16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: edge),
    );
  }
}

/// Label papers, the same as the desktop's: paper, three stripes, ink. Slot 0 follows the tape stock.
const papers = <(Color, List<Color>, Color)>[
  (Look.cream, [], Color(0xFF25428E)),
  (Color(0xFFF4F0E8), [Color(0xFFD8402A), Color(0xFFF0A12B), Color(0xFF262220)], Color(0xFF1F1A16)),
  (Color(0xFFDCC39A), [Color(0xFF2E8C86), Color(0xFFF1E6CF), Color(0xFF1F1A16)], Color(0xFF1F1A16)),
  (Color(0xFFF2D36B), [Color(0xFF262220), Color(0xFFE35D23), Color(0xFFF6EAD0)], Color(0xFF1F1A16)),
  (Color(0xFFD3E3EE), [Color(0xFF24418F), Color(0xFFD8402A), Color(0xFFF4F0E8)], Color(0xFF1D2F63)),
  (Color(0xFFF0CBC6), [Color(0xFF7A3B62), Color(0xFFE0708A), Color(0xFFF6ECE4)], Color(0xFF4A1F3B)),
  (Color(0xFFC9A372), [Color(0xFF5B3A1F), Color(0xFFEFE2C6), Color(0xFF2A1D12)], Color(0xFF2A1D12)),
  (Color(0xFF2A2733), [Color(0xFFD0567F), Color(0xFFF2B35C), Color(0xFF7BC3C3)], Color(0xFFEFE9DD)),
  (Color(0xFFDDD0EF), [Color(0xFF5A3C8F), Color(0xFFE98BB0), Color(0xFFF7F2FB)], Color(0xFF3A2466)),
  (Color(0xFFD0E8D5), [Color(0xFF1F6B52), Color(0xFFF0B54A), Color(0xFFF5F2E8)], Color(0xFF173D31)),
];

/// The paper for a slot: (paper, stripes, ink).
(Color, List<Color>, Color) paperFor(int slot) {
  final s = slot % papers.length;
  if (s == 0) return (Look.cream, Look.stripes, Look.ink);
  return papers[s];
}

/// The paper a tape gets from its name when nobody picked one: the desktop's checksum over the first
/// six papers, so a tape wears the same label on the phone as on the computer.
int slotFor(String name) => crc32(utf8.encode(name)) % 6;

Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;
