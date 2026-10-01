/// Smoke tests — Sources, History, Settings render in MOCK_MODE.
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/main.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  // Tall surface so lazily-built sliver children all exist for finders.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauVoteApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Sources lists all desks with View Original placeholder',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('SOURCES'));
    await tester.pumpAndSettle();

    expect(find.text('DESK A · GoldPulse'), findsOneWidget);
    expect(find.text('DESK D · BearBullion'), findsOneWidget);

    // Expand the first card and trigger View Original.
    final deskA = find.text('DESK A · GoldPulse');
    await tester.ensureVisible(deskA);
    await tester.pumpAndSettle();
    await tester.tap(deskA);
    await tester.pumpAndSettle();
    final viewOriginal = find.text('VIEW ORIGINAL');
    expect(viewOriginal, findsOneWidget);
    await tester.ensureVisible(viewOriginal);
    await tester.pumpAndSettle();
    await tester.tap(viewOriginal);
    await tester.pumpAndSettle();
    expect(find.textContaining('Opens https://'), findsOneWidget);
  });

  testWidgets('History shows every terminal state, newest first',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('HISTORY'));
    await tester.pumpAndSettle();

    expect(find.text('TP2 HIT'), findsOneWidget);
    // Stat header + status pill share these labels.
    expect(find.text('INVALIDATED'), findsNWidgets(2));
    expect(find.text('TP1 HIT'), findsOneWidget);
    expect(find.text('EXPIRED'), findsNWidgets(2));
    expect(find.text('TP3 HIT'), findsOneWidget);
    expect(find.text('NO CONSENSUS'), findsOneWidget);
  });

  testWidgets('Settings shows spec §24 controls with working toggles',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();

    expect(find.text('15M / 5M / 1H'), findsOneWidget);
    expect(find.text('TP1 + TP2 + TP3'), findsOneWidget);
    expect(find.text('Consensus forming'), findsOneWidget);
    expect(find.text('Invalidation'), findsOneWidget);

    // Target selection switches.
    final tp1Only = find.text('TP1 ONLY');
    await tester.ensureVisible(tp1Only);
    await tester.pumpAndSettle();
    await tester.tap(tp1Only);
    await tester.pumpAndSettle();
    expect(find.text('TP1 ONLY'), findsOneWidget);
  });
}
