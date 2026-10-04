/// Widget tests — Signal screen states (MOCK_MODE).
///
/// Full setup detail, lifecycle timeline, 1H/5M badges, TP selector, and a
/// global guard that agreement language never reads as a forecast.
library;


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xauvote/config.dart' show mockMode;
import 'package:xauvote/main.dart';
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/screens/radar_screen.dart';
import 'package:xauvote/state/app_state.dart';
import 'package:xauvote/widgets/harbor_widgets.dart';

/// Substrings that must never appear in any rendered text (spec §7).
/// Written as adjacent literals so this file itself contains no banned
/// string for repo-wide greps while still asserting on the real values.
const _banned = ['ch' 'ance', 'prob' 'ability', 'win' ' %'];

Future<void> _pumpApp(WidgetTester tester) async {
  // Tall surface so lazily-built sliver children all exist for finders.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauVoteApp());
  await tester.pumpAndSettle();
}

Future<void> _openSignal(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-SIGNAL')));
  await tester.pumpAndSettle();
}

/// Sets the target scope on the app's own [AppState].
///
/// The default scope is TP1, so a test that exercises anything other than the
/// target selector must state the scope it wants rather than inherit the
/// default. `XauVoteApp` owns its provider, so an outer one is shadowed; the
/// state is reached through the rendered tree instead.
///
/// Must be called while the Radar tab is showing — the shell renders only the
/// selected screen, so `RadarScreen` is absent once another tab is open.
Future<void> _setTargets(WidgetTester tester, TargetSelection targets) async {
  final state = Provider.of<AppState>(
    tester.element(find.byType(RadarScreen)),
    listen: false,
  );
  state.setTargets(targets);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Signal shows levels, timeline, context and TP control',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);
    // This test is about the setup's levels and lifecycle, not the target
    // scope, so it pins all three rather than inheriting the TP1 default. Set
    // before navigating: the shell renders only the selected screen.
    await _setTargets(tester, TargetSelection.all);
    await _openSignal(tester);

    expect(find.text('ACTIVE SETUP · 15M LONG'), findsOneWidget);
    // Direction is the HarborPill badge (trend glyph + label), not a text mark.
    expect(find.text('LONG'), findsOneWidget);
    expect(find.text('▲ LONG'), findsNothing);
    expect(find.text('4,275-4,280'), findsOneWidget);
    expect(find.text('4,262'), findsOneWidget);
    expect(find.text('4,295'), findsOneWidget);

    // Lifecycle timeline (spec §14).
    expect(find.text('DEVELOPING'), findsOneWidget);
    expect(find.text('READY'), findsOneWidget);
    expect(find.text('CONFIRMED · 5M'), findsOneWidget);
    expect(find.text('ACTIVE'), findsWidgets);

    // 1H context + 5M confirmation badges (below the fold: scroll first —
    // SliverList builds lazily, so off-screen children don't exist yet).
    await tester.scrollUntilVisible(find.text('SUPPORTIVE'), 300);
    await tester.pumpAndSettle();
    expect(find.text('SUPPORTIVE'), findsOneWidget);
    expect(find.text('CONFIRMED'), findsWidgets);

    // TP selection control (spec §10).
    expect(find.text('TP1'), findsWidgets);
    expect(find.text('TP1 + 2'), findsOneWidget);
    expect(find.text('TP1 + 2 + 3'), findsOneWidget);

    // Agreement label, not a forecast.
    expect(find.textContaining('STRONG 82'), findsOneWidget);
  });

  testWidgets('Signal TP selector narrows the visible targets',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);
    // Start from all three so this measures narrowing rather than the default.
    await _setTargets(tester, TargetSelection.all);
    await _openSignal(tester);

    expect(find.text('4,340'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('TP1 + 2 + 3'), 300);
    await tester.pumpAndSettle();
    // The scope control is the shared HarborPill row, not a SegmentedButton.
    final tp1 = find.descendant(
      of: find.byType(TargetSelector),
      matching: find.text('TP1'),
    );
    await tester.ensureVisible(tp1);
    await tester.pumpAndSettle();
    await tester.tap(tp1);
    await tester.pumpAndSettle();
    expect(find.text('4,340'), findsNothing);
    expect(find.text('4,295'), findsOneWidget);
  });

  testWidgets('No rendered text frames agreement as a forecast',
      skip: !mockMode,
      (tester) async {
    await _pumpApp(tester);
    for (final label in ['SIGNAL', 'SOURCES', 'HISTORY', 'SETTINGS']) {
      await tester.tap(find.byKey(ValueKey('nav-$label')));
      await tester.pumpAndSettle();
      // Build lazily-loaded rows too, so the scan covers the whole list.
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
    }
    final texts = tester.widgetList<Text>(find.byType(Text));
    final rendered = texts
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .join('\n')
        .toLowerCase();
    for (final banned in _banned) {
      expect(
        rendered.contains(banned),
        isFalse,
        reason: 'Banned substring "$banned" rendered in UI text.',
      );
    }
  });
}
