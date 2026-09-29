/// Harbor design tokens (user-approved mockups 11A + screens 2–5).
///
/// Light mist background (#E9ECEF), cobalt accent (#2347F5), dark ink
/// surfaces where the mockup inverts (day-move card, summary headers).
///
/// NOTE — typography/icons: the mockups specify Sora + Space Mono and
/// Flaticon UIcons (Regular Rounded). Those are web assets; to keep the MVP
/// fully offline we use the platform defaults via [harborTextTheme] and
/// plain Material Icons as the closest offline equivalent. If Sora/Space
/// Mono are bundled later, only [harborTextTheme] needs to change.
library;

import 'package:flutter/material.dart';

/// Light mist page background from the Harbor mockups.
const Color harborMist = Color(0xFFE9ECEF);

/// Cobalt accent from the Harbor mockups.
const Color harborCobalt = Color(0xFF2347F5);

/// Dark ink used for text and inverted surfaces.
const Color harborInk = Color(0xFF0D1526);

/// Muted secondary text.
const Color harborDim = Color(0xFF5A6B84);

/// Faint tertiary text / icons.
const Color harborFaint = Color(0xFF8FA0B8);

/// Hairline borders on white cards.
const Color harborLine = Color(0xFFD5DCE6);

/// LONG direction (green) and its soft tint.
const Color harborLong = Color(0xFF0E9F6E);
const Color harborLongSoft = Color(0xFFDFF5EA);

/// SHORT direction (red) and its soft tint.
const Color harborShort = Color(0xFFE05252);
const Color harborShortSoft = Color(0xFFFBE3E3);

/// Builds the light-first Harbor [ThemeData] (Material 3).
///
/// Harbor is LIGHT-first per the approved mockups (overrides the generic
/// dark-first trading-UI note in TASK-05); dark ink is used only for
/// inverted surfaces such as the day-move card.
ThemeData harborTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: harborCobalt,
    brightness: Brightness.light,
  ).copyWith(
    primary: harborCobalt,
    surface: Colors.white,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: harborMist,
    appBarTheme: const AppBarTheme(
      backgroundColor: harborMist,
      foregroundColor: harborInk,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: harborLine),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: harborCobalt.withValues(alpha: 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected =
            states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: selected ? harborCobalt : harborFaint,
        );
      }),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return harborInk;
          return Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return harborDim;
        }),
        side: const WidgetStatePropertyAll(
          BorderSide(color: harborLine),
        ),
      ),
    ),
    textTheme: harborTextTheme(),
  );
}

/// Offline text theme standing in for Sora (display) + Space Mono (numbers).
///
/// Numbers that must align (prices, levels, pips) use tabular figures via
/// [mono] so columns stay stable without the webfont.
TextTheme harborTextTheme() {
  // ignore: avoid_redundant_argument_values
  return Typography.englishLike2021.apply(
    displayColor: harborInk,
    bodyColor: harborInk,
  );
}

/// Monospace-ish style for prices/levels (tabular figures).
const TextStyle mono = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'],
  fontFeatures: [FontFeature.tabularFigures()],
);
