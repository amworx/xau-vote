/// Widget tests — Events screen + Radar event context (MOCK_MODE, TASK-07).
///
/// Upcoming countdowns, blackout banner, results surprise flags, news
/// headlines + macro backdrop. Rule 9: events/news are context, never votes
/// — asserted by the absence of forecast language and the presence of the
/// NEVER VOTES subtitle.
///
/// NOTE: the Upcoming countdown ticks on a 1-second [Timer], so once the
/// Events tab is open this file uses `tester.pump()` — never
/// `pumpAndSettle()` — or the frame scheduler never settles.
library;

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:xau_radar/main.dart';

/// Substrings that must never appear in any rendered text (spec §7 + rule 9).
/// Adjacent literals so this file itself contains no banned string.
const _banned = ['ch' 'ance', 'prob' 'ability', 'win' ' %'];

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(const XauRadarApp());
  await tester.pumpAndSettle();
}

Future<void> _openEvents(WidgetTester tester) async {
  await tester.tap(find.text('EVENTS'));
  // No settle: the live countdown timer is now mounted.
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('Radar shows MEDIUM caution line + macro backdrop strip',
      (tester) async {
    await _pumpApp(tester);

    expect(find.text('Caution: Retail Sales in 42m'), findsOneWidget);
    expect(
      find.text('Hawkish Fed repricing · Dovish ECB tilt · Neutral Asia flows'),
      findsOneWidget,
    );
  });

  testWidgets('EVENT preview shows blackout banner, never a signal',
      (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('EVENT'));
    await tester.pumpAndSettle();

    expect(find.text('⚠ HIGH-IMPACT EVENT'), findsOneWidget);
    expect(find.text('NFP — Non-Farm Payrolls'), findsOneWidget);
    expect(find.text('VIEW EVENTS'), findsOneWidget);
    expect(find.text('VIEW ANALYSIS'), findsNothing);
    for (final banned in _banned) {
      expect(find.textContaining(banned), findsNothing);
    }
  });

  testWidgets('Events Upcoming lists countdowns + blackout note',
      (tester) async {
    await _pumpApp(tester);
    await _openEvents(tester);

    expect(
      find.text('MACRO CONTEXT · NEVER VOTES'),
      findsOneWidget,
    );
    expect(find.text('NEXT HIGH-IMPACT'), findsOneWidget);
    expect(find.text('NFP — Non-Farm Payrolls'), findsWidgets);
    expect(
      find.text(
        'New signals paused from 30 min before until 15 min after release.',
      ),
      findsOneWidget,
    );
    expect(find.text('Retail Sales m/m'), findsOneWidget);
    expect(find.text('ECB Rate Decision'), findsOneWidget);
    // Live countdown ticks from the 12m41s fixture (prefix 'in ').
    expect(find.textContaining('in 00:12:4'), findsWidgets);
    for (final banned in _banned) {
      expect(find.textContaining(banned), findsNothing);
    }
  });

  testWidgets('Events Results flags surprises vs in-line prints',
      (tester) async {
    await _pumpApp(tester);
    await _openEvents(tester);

    await tester.tap(find.text('RESULTS'));
    await tester.pump();
    await tester.pump();

    expect(find.text('CPI y/y'), findsOneWidget);
    expect(find.textContaining('SURPRISE'), findsNWidgets(2));
    expect(find.text('○ IN LINE — near forecast'), findsOneWidget);
    expect(find.textContaining('A 3.4% · F 3.1%'), findsOneWidget);
  });

  testWidgets('Events News shows backdrop themes + headlines with links',
      (tester) async {
    await _pumpApp(tester);
    await _openEvents(tester);

    await tester.tap(find.text('NEWS'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hawkish Fed repricing'), findsOneWidget);
    expect(find.text('HAWKISH'), findsOneWidget);
    expect(find.text('DOVISH'), findsOneWidget);
    expect(
      find.text('Gold holds range ahead of US payrolls data'),
      findsOneWidget,
    );
    expect(find.textContaining('OPEN ORIGINAL'), findsWidgets);

    // Tapping a headline offers the original link (placeholder in MOCK_MODE).
    await tester.tap(find.text('Gold holds range ahead of US payrolls data'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Opens https://'), findsOneWidget);
  });

  testWidgets('Settings shows the Events group (addendum §5.3)',
      (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text('CONFIG'));
    await tester.pumpAndSettle();

    expect(find.text('EVENTS · CONTEXT ONLY'), findsOneWidget);
    expect(find.text('30 min'), findsOneWidget);
    expect(find.text('60-min warning'), findsOneWidget);
    expect(find.text('News spikes'), findsOneWidget);
  });
}
