/// Widget tests — Radar screen states (MOCK_MODE).
///
/// Covers the mockup verdict card (direction pill, strength meter, level
/// grid, target scope, source agreement, copy action), the NO CONSENSUS
/// divided state, the event guardrail bar and tab navigation. Strength is
/// asserted as an agreement label only (spec §7).
library;


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xauvote/config.dart' show mockMode;
import 'package:xauvote/main.dart';
import 'package:xauvote/screens/radar_screen.dart';
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/state/app_state.dart';
import 'package:xauvote/widgets/harbor_widgets.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  // Tall surface so lazily-built sliver children all exist for finders.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauVoteApp());
  await tester.pumpAndSettle();
}

/// Sets the target scope on the app's own [AppState].
///
/// The default scope is now TP1, so a test about narrowing from all three must
/// state that starting point rather than inherit the default. The state is
/// reached through the rendered tree because `XauVoteApp` owns its own
/// provider, and an outer one would simply be shadowed.
Future<void> _setTargets(WidgetTester tester, TargetSelection targets) async {
  final state = Provider.of<AppState>(
    tester.element(find.byType(RadarScreen)),
    listen: false,
  );
  state.setTargets(targets);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Radar renders the mockup header, quote, day bar and switcher',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);

    // Header: wordmark, no subtitle, no cobold icon tile.
    //
    // There is deliberately no market-status assertion here. The offline build
    // has no market feed, so the header hides the pill rather than asserting
    // "LIVE" from a string literal - the bug this replaced.
    expect(find.text('XV'), findsOneWidget);
    expect(find.text('GOLD · XAUUSD · 15M'), findsNothing);

    // Price block.
    expect(find.text('XAUUSD · SPOT GOLD'), findsOneWidget);
    expect(find.text('4,278.30'), findsOneWidget);
    expect(find.text('+0.29%'), findsOneWidget);
    expect(find.text('Spread 0.35'), findsOneWidget);

    // Day bar: real day move plus the session range supplied by the feed.
    // A range-less signal must fall back to the neutral `—` placeholder
    // rather than inventing numbers (rule 2: never fabricate).
    expect(find.text('DAY MOVE'), findsOneWidget);
    expect(find.text('+12.40'), findsOneWidget);
    expect(find.text('RANGE'), findsOneWidget);
    expect(find.text('4,266.90 — 4,286.40'), findsOneWidget);
    expect(find.text('—'), findsNothing);

    // Timeframe display is view-only, 15M active (product rule 1).
    final switcher = find.byType(TimeframeSwitch);
    for (final tf in ['15M', '5M', '1H']) {
      expect(
        find.descendant(of: switcher, matching: find.text(tf)),
        findsOneWidget,
      );
    }
  });

  testWidgets('Radar verdict card shows levels, targets and agreement',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);
    // This test is about the card's levels and agreement, not the target
    // scope, so it pins all three rather than inheriting the TP1 default.
    await _setTargets(tester, TargetSelection.all);

    expect(find.text('LONG'), findsOneWidget);
    expect(find.text('updated 40s ago'), findsOneWidget);
    expect(find.text('15M Consensus Setup'), findsOneWidget);
    expect(find.text('STRONG · 4 / 5'), findsOneWidget);

    // Levels are withheld. The verdict, the agreement split and the source chips
    // still render - only the numbers are gone. Absence is asserted on values
    // that appear nowhere else on the card: the stop figure is also rendered in
    // the "Watch" pill, so a global assertion on it would be wrong.
    expect(find.byType(VerdictLevelGrid), findsNothing);
    expect(find.text('ENTRY, STOP AND TARGETS WITHHELD'), findsOneWidget);
    for (final level in [
      'ENTRY',
      'market zone',
      '−15.50',
      '4,295',
      '4,315',
      '4,340',
      '+17.50',
      'R:R',
      '1:5.0',
    ]) {
      expect(
        find.text(level),
        findsNothing,
        reason: '$level must not be published before validation',
      );
    }

    expect(find.text('4 of 5 sources agree'), findsOneWidget);
    expect(find.text('Source A ✓'), findsOneWidget);
    expect(find.text('Source D ×'), findsOneWidget);

    expect(find.text('COPY LEVELS'), findsNothing);
    expect(find.text('↗ SHARE'), findsNothing);
  });

  testWidgets('Target scope no longer narrows anything, because no targets show',
      skip: !mockMode,
      (tester) async {
    // The target selector stays in place so the control does not silently
    // disappear from under a returning user, but with every target withheld it
    // must not reveal one on selection.
    await _pumpApp(tester);
    await _setTargets(tester, TargetSelection.all);

    expect(find.byType(VerdictLevelGrid), findsNothing);
    for (final level in ['4,295', '4,315', '4,340']) {
      expect(find.text(level), findsNothing,
          reason: '$level must stay hidden under every target scope');
    }
    expect(find.text('1:1.5'), findsNothing,
        reason: 'the R:R readout is derived from withheld targets');
  });

  // Levels are withheld, so there is no clipboard affordance left to reach them
  // with. This replaces the former "COPY LEVELS copies the setup" test: the
  // absence is the requirement now, and a copy path must not reappear silently.
  testWidgets('no copy affordance publishes levels', skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);

    expect(find.widgetWithText(InkWell, 'COPY LEVELS'), findsNothing);
    expect(find.widgetWithText(InkWell, '↗ SHARE'), findsNothing);
    expect(find.textContaining('COPY LEVELS'), findsNothing);
    // The reason is stated rather than the card silently losing content.
    expect(find.text('ENTRY, STOP AND TARGETS WITHHELD'), findsOneWidget);
    expect(find.byType(VerdictLevelGrid), findsNothing);
  });

  testWidgets('Radar divided preview shows NO CONSENSUS, never a signal',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'DIVIDED'));
    await tester.pumpAndSettle();

    expect(find.text('NO CONSENSUS'), findsOneWidget);
    expect(find.text('Sources are currently divided.'), findsOneWidget);
    expect(
      find.text('Waiting for stronger agreement.'),
      findsOneWidget,
    );
    expect(find.text('COPY LEVELS'), findsNothing);
    expect(find.text('4,275-4,280'), findsNothing);
  });

  testWidgets('Event preview shows the guardrail bar and routes to Events',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'EVENT'));
    await tester.pumpAndSettle();

    expect(find.text('EVENT GUARDRAIL'), findsOneWidget);
    expect(find.textContaining('USD HIGH impact event in'), findsOneWidget);
    expect(find.text('COPY LEVELS'), findsNothing);

    await tester.tap(find.text('EVENT GUARDRAIL'));
    await tester.pumpAndSettle();
    expect(find.text('MACRO CONTEXT · NEVER VOTES'), findsOneWidget);
  });

  testWidgets('DEVELOPING preview keeps the same card language', skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'DEVELOPING'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(VerdictCardShell),
        matching: find.text('DEVELOPING'),
      ),
      findsOneWidget,
    );
    expect(find.text('15M Consensus Setup'), findsOneWidget);
    expect(find.text('3 of 5 sources agree'), findsOneWidget);
    expect(find.text('COPY LEVELS'), findsNothing);
  });

  testWidgets('Bottom nav routes from Radar to the Signal tab', skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('nav-SIGNAL')));
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE SETUP · 15M LONG'), findsOneWidget);
  });
}
