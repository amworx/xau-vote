/// Widget tests — Radar screen states (MOCK_MODE).
///
/// Covers the strong-consensus §3 layout, the NO CONSENSUS divided state,
/// and VIEW ANALYSIS navigation. Strength is asserted as an agreement
/// label only (spec §7).
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:xau_radar/main.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  // Tall surface so lazily-built sliver children all exist for finders.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauRadarApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Radar renders the strong-consensus layout', (tester) async {
    await _pumpApp(tester);

    expect(find.text('XAU RADAR'), findsOneWidget);
    expect(find.text('4,278.30'), findsOneWidget);
    expect(find.text('▲ LONG'), findsOneWidget);
    expect(find.text('STRONG 82'), findsOneWidget);
    expect(find.text('82/100'), findsOneWidget);
    expect(find.text('4,275-4,280'), findsOneWidget);
    expect(find.text('4,262'), findsOneWidget);
    expect(find.text('4,295'), findsOneWidget);
    expect(find.text('4,315'), findsOneWidget);
    expect(find.text('4,340'), findsOneWidget);
    expect(find.text('4/5 agree'), findsOneWidget);
    expect(find.text('VIEW ANALYSIS'), findsOneWidget);
  });

  testWidgets('Radar divided preview shows NO CONSENSUS, never a signal',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('DIVIDED'));
    await tester.pumpAndSettle();

    expect(find.text('NO CONSENSUS'), findsOneWidget);
    expect(find.text('Sources are currently divided.'), findsOneWidget);
    expect(
      find.text('Waiting for stronger agreement.'),
      findsOneWidget,
    );
    expect(find.text('VIEW ANALYSIS'), findsNothing);
    expect(find.text('4,275-4,280'), findsNothing);
  });

  testWidgets('VIEW ANALYSIS navigates to the Signal tab', (tester) async {
    await _pumpApp(tester);

    final cta = find.text('VIEW ANALYSIS');
    await tester.ensureVisible(cta);
    await tester.pumpAndSettle();
    await tester.tap(cta);
    await tester.pumpAndSettle();

    expect(find.text('ACTIVE SETUP · 15M LONG'), findsOneWidget);
  });
}
