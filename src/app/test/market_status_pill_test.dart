/// Market-status pill behaviour.
///
/// The bug these lock down: the header read a hardcoded `LIVE · 18s`, so the
/// app claimed a live market with a frozen timestamp while the market was shut
/// for the weekend. The pill must now reflect the real trading session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Session calendar only: the barrel also exports a Direction enum that
// collides with the app's display models.
import 'package:xau_core/analysis/session.dart';
import 'package:xauvote/widgets/harbor_widgets.dart';

/// Pumps a bare header with explicit session state, bypassing the clock so the
/// assertions are deterministic regardless of when the suite runs.
///
/// [marketStatusLabel] defaults to `true` because the suite runs offline
/// (`mockMode == true`), where the header deliberately hides the derived pill.
/// The `false` case is covered explicitly below.
Future<void> _pump(
  WidgetTester tester, {
  bool? sessionOpen,
  String? sessionName,
  String? statusText,
  bool marketStatusLabel = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HarborHeader(
          subtitle: 'SETTINGS',
          sessionOpen: sessionOpen,
          sessionName: sessionName,
          statusText: statusText,
          marketStatusLabel: marketStatusLabel,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('the default pill reads the clock, not a hardcoded default',
      (tester) async {
    // Regression: the constructor once defaulted sessionOpen to true and
    // sessionName to 'LIVE', so the nullable fields were never null and the
    // clock was never consulted. Every other test here passes explicit values,
    // so only this one - which omits them - can catch that.
    // marketStatusLabel:true stands in for a live build, so the derived pill
    // renders. Without it an offline test build hides the pill (correctly), and
    // there would be nothing to assert against.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: HarborHeader(marketStatusLabel: true)),
      ),
    );

    // The pill is the trailing Text in the header row; "XV" is the wordmark.
    final pill = tester.widget<Text>(find.byType(Text).last);
    expect(pill.data, isNot('XV'));
    final now = DateTime.now().toUtc();
    if (isSessionOpen(now)) {
      expect(pill.data, sessionLabel(sessionAt(now)));
    } else {
      expect(pill.data, 'MARKET CLOSED');
    }
    // Never the old frozen literal, whatever the hour.
    expect(pill.data, isNot(contains('18s')));
  });

  testWidgets('a shut market never reads as live', (tester) async {
    await _pump(tester, sessionOpen: false, sessionName: 'US');
    expect(find.text('US · CLOSED'), findsOneWidget);
  });

  testWidgets('an open market names its session phase, not "LIVE"',
      (tester) async {
    await _pump(tester, sessionOpen: true, sessionName: 'US');
    expect(find.text('US'), findsOneWidget);
    expect(find.text('LIVE'), findsNothing);
  });

  testWidgets('a closed market with no phase reads MARKET CLOSED',
      (tester) async {
    await _pump(tester, sessionOpen: false, sessionName: 'CLOSED');
    expect(find.text('MARKET CLOSED'), findsOneWidget);
  });

  testWidgets('an explicit statusText overrides the derived session',
      (tester) async {
    await _pump(tester, sessionOpen: true, sessionName: 'US',
        statusText: 'NO CONSENSUS');
    expect(find.text('NO CONSENSUS'), findsOneWidget);
    expect(find.text('US'), findsNothing);
  });

  testWidgets('no timestamp is invented when statusText is omitted',
      (tester) async {
    await _pump(tester, sessionOpen: true, sessionName: 'US');
    // The old literal ended in a frozen "18s".
    expect(find.textContaining('18s'), findsNothing);
  });

  testWidgets('offline builds make no market claim at all', (tester) async {
    await _pump(tester, marketStatusLabel: false);
    // Brand still renders; the pill does not.
    expect(find.text('XV'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('US'), findsNothing);
    expect(find.text('CLOSED'), findsNothing);
  });

  testWidgets('an explicit statusText shows even when the pill is gated off',
      (tester) async {
    // The pill also carries signal lifecycle labels, which are not market
    // claims and must survive the offline gate.
    await _pump(
      tester,
      marketStatusLabel: false,
      statusText: 'NO CONSENSUS',
    );
    expect(find.text('NO CONSENSUS'), findsOneWidget);
  });
}