/// The History stats bento.
///
/// The point of these tests is that the figures are TRACEABLE. A hero this
/// large is dangerous by default: a big percentage over a trade log invites
/// reading it as "the chance the next trade wins", which product rule 4
/// forbids and which no closed-outcome statistic can honestly answer. So the
/// assertions are about the denominator being present, the counts coming from
/// the rows, open trades staying out, and the chart never inventing a point.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/screens/history_screen.dart';
import 'package:xauvote/widgets/stats_bento.dart';

/// One closed setup. [points] is canonical points; [status] drives the counts.
DisplayHistoryEntry _row(
  DisplayStatus? status,
  double points, {
  String when = 'TODAY · 10:00',
}) =>
    DisplayHistoryEntry(
      direction: Direction.long,
      whenText: when,
      detailText: 'IN 4,100 · SL 4,090 · TP1 4,120 · STRONG 80',
      status: status,
      pipsPoints: points,
    );

HistoryStats _stats(List<DisplayHistoryEntry> rows, {int pipFactor = 10}) =>
    HistoryStats.from(rows, pipFactor: pipFactor, live: true);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('derivation', () {
    test('the hit rate is over closed outcomes only', () {
      final s = _stats([
        _row(DisplayStatus.tp1Hit, 10),
        _row(DisplayStatus.tp2Hit, 20),
        _row(DisplayStatus.invalidated, -5),
        _row(DisplayStatus.expired, 0),
      ]);

      expect(s.tpHits, 2);
      expect(s.invalidated, 1);
      expect(s.expired, 1);
      expect(s.resolved, 4);
      expect(s.hitRatePercent, 50);
    });

    test('open and held setups stay out of the denominator', () {
      final s = _stats([
        _row(DisplayStatus.tp1Hit, 10),
        // Still open - not a closed outcome.
        _row(DisplayStatus.developing, 0),
        // The engine correctly held: no vote, so nothing to score.
        _row(null, 0),
      ]);

      expect(s.resolved, 1, reason: 'developing and null are open');
      expect(s.hitRatePercent, 100);
    });

    test('an empty log yields no percentage at all', () {
      final s = _stats(const []);

      expect(s.resolved, 0);
      expect(
        s.hitRatePercent,
        isNull,
        reason: 'an empty log must not render a confident 0%',
      );
    });

    test('counts come from the rows, never from constants', () {
      // The four-tile row this replaced printed 9 / 3 / 2 while these rows held
      // 2 TP hits, 1 invalidated and 1 expired - the tiles and the log above
      // them disagreed.
      final s = _stats([
        _row(DisplayStatus.tp1Hit, 10),
        _row(DisplayStatus.tp3Hit, 10),
        _row(DisplayStatus.invalidated, -5),
        _row(DisplayStatus.expired, 0),
        _row(DisplayStatus.expired, 0),
      ]);

      expect(s.tpHits, 2);
      expect(s.invalidated, 1);
      expect(s.expired, 2);
    });

    test('the series is reversed to read oldest-first', () {
      final s = _stats([
        _row(DisplayStatus.tp1Hit, 10, when: 'NEWEST'),
        _row(DisplayStatus.invalidated, -5, when: 'MIDDLE'),
        _row(DisplayStatus.tp2Hit, 20, when: 'OLDEST'),
      ]);

      expect(s.series, [200.0, -50.0, 100.0]);
    });

    test('pips scale with the active convention', () {
      final rows = [_row(DisplayStatus.tp1Hit, 31)];

      // Convention A: 1 pip = 0.10 points, factor 10. B: 1 pip = 0.01, factor
      // 100 - so the LARGER factor is the SMALLER pip. Getting this backwards
      // is easy and silently reports every figure 10x out.
      expect(_stats(rows, pipFactor: 10).netPips, 310);
      expect(_stats(rows, pipFactor: 100).netPips, 3100);
    });

    test('offline marks the net as a window total, live does not', () {
      final rows = [_row(DisplayStatus.tp1Hit, 10)];

      expect(
        HistoryStats.from(rows, pipFactor: 10, live: true).netIsWindowTotal,
        isFalse,
      );
      expect(
        HistoryStats.from(rows, pipFactor: 10, live: false).netIsWindowTotal,
        isTrue,
        reason: 'offline the net is a recorded 7-day total, not the row sum',
      );
    });

    test('a negative window net keeps its sign', () {
      final s = HistoryStats.from(
        [_row(DisplayStatus.invalidated, -40)],
        pipFactor: 10,
        live: true,
      );

      expect(s.netPips, -400);
    });
  });

  group('presentation', () {
    testWidgets('the hero states the denominator beside the percentage',
        (tester) async {
      await tester.pumpWidget(_host(const StatsHero(
        badge: 'TP hit rate',
        figure: '64',
        suffix: '%',
        caption: 'Closed signals: 9 of 14 hit a TP. Open setups excluded.',
      )));

      expect(find.text('64'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(
        find.textContaining('9 of 14'),
        findsOneWidget,
        reason: 'a bare percentage must never stand alone',
      );
    });

    testWidgets('an empty hero shows a dash, not a zero', (tester) async {
      await tester.pumpWidget(_host(const StatsHero(
        badge: 'TP hit rate',
        figure: '–',
        suffix: '',
        caption: 'Closed signals: none in this window yet.',
      )));

      expect(find.text('0'), findsNothing);
      expect(find.text('%'), findsNothing);
    });

    testWidgets('the growth card distinguishes the window net from the series',
        (tester) async {
      await tester.pumpWidget(_host(Column(children: [
        StatsGrowth(
          eyebrow: 'Net pips · 7-day window',
          value: '+8400',
          sub: 'pip 0.01 · chart is per closed signal',
          chart: PipsLineChart(values: const [20, -5, 10]),
        ),
      ])));

      expect(find.textContaining('WINDOW'), findsOneWidget);
      expect(
        find.textContaining('per closed signal'),
        findsOneWidget,
        reason: 'the chart sums to 30 while the net says 8400; the card has to '
            'say they measure different things',
      );
    });

    testWidgets('one data point draws no chart rather than a stub',
        (tester) async {
      await tester.pumpWidget(_host(
        const PipsLineChart(values: [10]),
      ));

      expect(
        // Scoped to the chart: MaterialApp and Scaffold bring their own
        // CustomPaint, so a bare type finder proves nothing either way.
        find.descendant(
          of: find.byType(PipsLineChart),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
        reason: 'a single point cannot describe a trend',
      );
    });

    testWidgets('two or more points do draw the chart', (tester) async {
      await tester.pumpWidget(_host(
        const PipsLineChart(values: [10, -5]),
      ));

      expect(
        find.descendant(
          of: find.byType(PipsLineChart),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the chart exposes the series to screen readers',
        (tester) async {
      await tester.pumpWidget(_host(
        const PipsLineChart(
          values: [20, -5, 10],
          semanticsLabel: 'Pips per closed signal, oldest to newest.',
        ),
      ));

      expect(
        find.bySemanticsLabel('Pips per closed signal, oldest to newest.').first,
        findsOneWidget,
      );
    });

    testWidgets('number cards share a min height so a pair stays level',
        (tester) async {
      await tester.pumpWidget(_host(Row(children: [
        Expanded(
          child: StatsNumber(
            value: '1',
            label: 'Invalidated',
            valueColor: Colors.red,
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: StatsNumber(
            value: '2',
            label: 'Expired',
            valueColor: Colors.blue,
          ),
        ),
      ])));

      final a = tester.getSize(find.byType(StatsNumber).first);
      final b = tester.getSize(find.byType(StatsNumber).last);
      expect(a.height, b.height);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bento lays out at 360dp without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_host(const StatsBento(children: [
        StatsHero(
          badge: 'TP hit rate',
          figure: '60',
          suffix: '%',
          caption: 'Closed signals: 3 of 5 hit a TP. Open setups excluded.',
        ),
        StatsGrowth(
          eyebrow: 'Net pips · 7-day window',
          value: '+8400',
          sub: 'pip 0.01 · chart is per closed signal',
          chart: PipsLineChart(values: [20, -5, 10, 30, -8]),
        ),
        Row(children: [
          Expanded(
            child: StatsNumber(
              value: '1',
              label: 'Invalidated',
              valueColor: Colors.red,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: StatsNumber(
              value: '1',
              label: 'Expired',
              valueColor: Colors.blue,
            ),
          ),
        ]),
      ])));

      expect(tester.takeException(), isNull);
    });
  });
}
