/// Market-status pill behaviour.
///
/// The bug these lock down: the header read a hardcoded `LIVE · 18s`, so the
/// app claimed a live market with a frozen timestamp while the market was shut
/// for the weekend. The pill must now reflect the real trading session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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