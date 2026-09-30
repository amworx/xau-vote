/// Harbor design tokens (user-approved `docs/mockups/mockup.html`).
///
/// Light mist background (#E9ECEF), cobalt accent (#2347F5), dark ink
/// surfaces where the mockup inverts (day-move bar, guardrail bar, bottom
/// nav).
///
/// Typography is Sora (display/body) + Space Mono (numbers), bundled offline
/// in `assets/fonts` (both OFL-licensed). Icons are Flaticon UIcons Regular
/// Rounded 2.6.0, bundled offline — see `icons.dart` (attribution required:
/// "UIcons by Flaticon").
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

/// Warning/amber for MEDIUM impact (mockup `--warn:#B7791F`) and its tint
/// (events mockup `--warn-soft:#F6ECD4`).
const Color harborWarn = Color(0xFFB7791F);
const Color harborWarnSoft = Color(0xFFF6ECD4);

// ---------------------------------------------------------------------------
// Harbor neutrals introduced by docs/mockups/mockup.html (the Radar mockup).
// Raw values from the mockup's inline <style> — no derivation, no tuning.
// ---------------------------------------------------------------------------

/// Backdrop BEHIND the 390px phone frame in the mockup demo page only.
/// Never used as an app surface; the app background is [harborMist].
const Color pageSurround = Color(0xFFCFD5DC);

/// LIVE pill (header): `#b9c5d4` border, `#f7f8fa` fill, `#4c607b` ink.
const Color livePillBorder = Color(0xFFB9C5D4);
const Color livePillBg = Color(0xFFF7F8FA);
const Color livePillInk = Color(0xFF4C607B);

/// Bottom-nav idle label/icon color (mockup `.nav`).
const Color navIdle = Color(0xFF8291A7);

/// Timeframe switcher track (mockup `.switch`).
const Color switchTrack = Color(0xFFD9DEE5);

/// Consensus strength meter track (mockup `.strengthline`).
const Color meterTrack = Color(0xFFE6EAF0);

/// Level cell border, plus the highlighted Entry cell pair.
const Color levelBorder = Color(0xFFE1E5EB);
const Color levelEntryBg = Color(0xFFF5F7FF);
const Color levelEntryBorder = Color(0xFFCFD7FF);

/// Active TP pill fill (mockup `.tp button.active`).
const Color tpActiveBg = Color(0xFFEEF1FF);

/// Hairline above the agreement row (mockup `.agree`).
const Color divider = Color(0xFFEDF0F4);

/// Source chip fill / ink (mockup `.src`).
const Color chipBg = Color(0xFFF0F3F7);
const Color chipInk = Color(0xFF40516B);

/// Muted ink for text drawn on dark surfaces (mockup day-bar eyebrow,
/// guardrail sub-line) — lighter than [harborDim] for contrast on [harborInk].
const Color inkMuted = Color(0xFF93A1B8);

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

/// Harbor text theme: Sora for display/body, Space Mono for numbers.
///
/// Mockup type scale (root 16px): eyebrow labels ≈9–11px uppercase with
/// wide tracking, body 12–16px, section titles 16–20px, hero numerals
/// 23–34px tabular. Numbers that must align (prices, levels, pips) use
/// [mono] (Space Mono + tabular figures).
TextTheme harborTextTheme() {
  const sora = TextStyle(fontFamily: 'Sora');
  // ignore: avoid_redundant_argument_values
  return Typography.englishLike2021.apply(
    displayColor: harborInk,
    bodyColor: harborInk,
  ).copyWith(
    // Hero numerals (price, score): Sora 800, tight.
    displayLarge: sora.copyWith(
      fontSize: 33,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: harborInk,
    ),
    displayMedium: sora.copyWith(
      fontSize: 27,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: harborInk,
    ),
    // Section titles.
    titleLarge: sora.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: harborInk,
    ),
    titleMedium: sora.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: harborInk,
    ),
    titleSmall: sora.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: harborInk,
    ),
    // Body copy: mockup base is 16px Sora 400.
    bodyLarge: sora.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: harborInk,
    ),
    bodyMedium: sora.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: harborInk,
    ),
    bodySmall: sora.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: harborDim,
    ),
    // Eyebrow micro-labels: uppercase, tracked, faint/dim.
    labelSmall: sora.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: harborFaint,
    ),
    labelMedium: sora.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
      color: harborDim,
    ),
  );
}

/// Space Mono style for prices/levels/pips (tabular figures).
const TextStyle mono = TextStyle(
  fontFamily: 'Space Mono',
  fontFamilyFallback: ['Menlo', 'Consolas', 'monospace'],
  fontFeatures: [FontFeature.tabularFigures()],
);
