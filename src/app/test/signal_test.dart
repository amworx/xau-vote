/// Widget tests — Signal screen states (MOCK_MODE).
///
/// Full setup detail, lifecycle timeline, 1H/5M badges, TP selector, and a
/// global guard that agreement language never reads as a forecast.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xau_radar/main.dart';
import 'package:xau_radar/models/display_models.dart';

/// Substrings that must never appear in any rendered text (spec §7).
/// Written as adjacent literals so this file itself contains no banned
/// string for repo-wide greps while still asserting on the real values.
const _banned = ['ch' 'ance', 'prob' 'ability', 'win' ' %'];

Future<void> _pumpApp(WidgetTester tester) async {
  // Tall surface so lazily-built sliver children all exist for finders.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauRadarApp());
  await tester.pumpAndSettle();
}

Future<void> _openSignal(WidgetTester tester) async {
  await tester.tap(find.text('SIGNAL'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Signal shows levels, timeline, context and TP control',
      (tester) async {
    await _pumpApp(tester);
    await _openSignal(tester);

    expect(find.text('ACTIVE SETUP · 15M LONG'), findsOneWidget);
    expect(find.text('▲ LONG'), findsOneWidget);
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
      (tester) async {
    await _pumpApp(tester);
    await _openSignal(tester);

    expect(find.text('4,340'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('TP1 + 2 + 3'), 300);
    await tester.pumpAndSettle();
    final tp1 = find.descendant(
      of: find.byType(SegmentedButton<TargetSelection>),
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
      (tester) async {
    await _pumpApp(tester);
    for (final label in ['SIGNAL', 'SOURCES', 'HISTORY', 'SETTINGS']) {
      await tester.tap(find.text(label));
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
