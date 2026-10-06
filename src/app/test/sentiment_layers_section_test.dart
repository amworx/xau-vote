import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/models/sentiment_layers.dart';
import 'package:xauvote/widgets/sentiment_layers_section.dart';

SentimentLayerRow row(
  String layer,
  double weight, {
  int? alignment,
  num? score,
  String source = 'test',
  bool stale = false,
  String measuredAt = '2026-10-05T00:00:00.000Z',
  Map<String, dynamic> detail = const {},
}) =>
    SentimentLayerRow.tryParse({
      'layer': layer,
      'horizon': 'hours-days',
      'weight': weight,
      'score': score,
      'alignment': alignment,
      'measured_at': measuredAt,
      'source': source,
      'source_url': null,
      'stale': stale,
      'detail': detail,
    })!;

/// The live database state on 2026-10-05.
SentimentLayers live() => SentimentLayers([
      row('policy', 35,
          alignment: -1,
          score: -1.03,
          measuredAt: '2026-09-16T00:00:00.000Z',
          detail: const {
            'action': 'raise',
            'target_low_pct': 3.75,
            'target_high_pct': 4,
            'raw_score': -2,
            'effective_score': -1.03,
            'decay_days': 20,
            'dissents': <String>[],
            'sep_projection': null,
            'as_of': '2026-09-16',
          }),
      row('positioning', 25,
          alignment: -1,
          score: -1,
          measuredAt: '2026-09-29T00:00:00.000Z',
          detail: const {
            'managed_net_contracts': 120318,
            'percentile_156w': 37.8,
            'sample_weeks': 156,
            'managed_net_percent_of_oi': 0.296,
            'as_of': '2026-09-29',
          }),
      row('market_implied', 20,
          alignment: -1,
          detail: const {
            'real10y': 2.92,
            'change5d_bp': 9,
            'as_of': '2026-10-05',
            'legs_missing': ['usd', 'volatility'],
          }),
      row('gold_fundamentals', 20),
    ]);

Widget wrap(
  SentimentLayers layers, {
  int? macroAlignment,
  int? sentimentAlignment,
  bool hasDirection = true,
  bool isLong = true,
}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SentimentLayersSection(
            layers: layers,
            macroAlignment: macroAlignment,
            sentimentAlignment: sentimentAlignment,
            hasDirection: hasDirection,
            isLong: isLong,
          ),
        ),
      ),
    );

void main() {
  group('layer readings', () {
    testWidgets('shows the measured policy decision, not just a badge', (t) async {
      await t.pumpWidget(wrap(live(), macroAlignment: -1, sentimentAlignment: -1));
      expect(find.textContaining('Fed raised the target range'), findsOneWidget);
      expect(find.textContaining('3.75%'), findsOneWidget);
      expect(find.textContaining('raw -2'), findsOneWidget);
      expect(find.textContaining('no dissents'), findsOneWidget);
    });

    testWidgets('shows the positioning percentile and open-interest share', (t) async {
      await t.pumpWidget(wrap(live()));
      expect(find.textContaining('+120318'), findsOneWidget);
      expect(find.textContaining('37.8 pctile'), findsOneWidget);
      expect(find.textContaining('156 weeks'), findsOneWidget);
      expect(find.textContaining('of open interest'), findsOneWidget);
    });

    testWidgets('shows the real yield and its 5-session change', (t) async {
      await t.pumpWidget(wrap(live()));
      expect(find.textContaining('10-year real yield'), findsOneWidget);
      expect(find.textContaining('+9bp over 5 sessions'), findsOneWidget);
    });

    testWidgets('the four layers appear in weight order', (t) async {
      await t.pumpWidget(wrap(live()));
      // Only the layer headers: name plus " NN%", which is what distinguishes
      // them from the "MACRO COVERAGE 73%" chip.
      final names = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((s) => RegExp(r'^\S[\S-]*\s+\d+%$').hasMatch(s))
          .toList();
      expect(names, hasLength(4));
      expect(names[0], startsWith('POLICY'));
      expect(names[1], startsWith('POSITIONING'));
      expect(names[2], startsWith('MARKET-IMPLIED'));
      expect(names[3], startsWith('GOLD-FUNDAMENTALS'));
    });
  });

  group('honesty about what is missing', () {
    testWidgets('an unmeasured layer reads NOT MEASURED, never NEUTRAL', (t) async {
      await t.pumpWidget(wrap(live()));
      expect(find.text('NOT MEASURED'), findsWidgets);
      // No layer measured zero, so no NEUTRAL badge may appear.
      expect(find.text('NEUTRAL'), findsNothing);
      expect(find.text('World Gold Council demand data — not ingested'), findsOneWidget);
    });

    testWidgets('a partly measured layer names the missing legs', (t) async {
      await t.pumpWidget(wrap(live()));
      expect(find.textContaining('usd and volatility of this layer are missing'),
          findsOneWidget);
    });

    testWidgets('policy discloses that the SEP path is unread', (t) async {
      await t.pumpWidget(wrap(live()));
      expect(find.textContaining('SEP projections not read'), findsOneWidget);
    });

    testWidgets('a stale layer reads STALE and says it is ignored', (t) async {
      final stale = SentimentLayers([
        row('positioning', 25, alignment: -1, stale: true),
      ]);
      await t.pumpWidget(wrap(stale));
      expect(find.text('STALE'), findsOneWidget);
      expect(find.textContaining('Past its window'), findsOneWidget);
    });

    testWidgets('a layer with no row at all is shown as unbuilt', (t) async {
      await t.pumpWidget(wrap(const SentimentLayers.empty()));
      expect(find.textContaining('MACRO COVERAGE 0%'), findsOneWidget);
      expect(find.text('UNBUILT LAYER  —'), findsWidgets);
    });
  });

  group('agreement is separate from the layer lean', () {
    // The strip is driven by the RAW alignment, and each row is derived
    // independently. It previously took the engine's `macroAgrees`, which is
    // already relative to the traded side, and flipped it again per row - so
    // with no candidate direction to orient against, BOTH rows came out
    // inverted. `isLong` now only highlights; it must not change the numbers.
    testWidgets('a bearish macro is a CONFLICT for a long and SUPPORTS a short',
        (t) async {
      await t.pumpWidget(wrap(live(), macroAlignment: -1, sentimentAlignment: -1, isLong: true));
      expect(find.text('vs LONG'), findsOneWidget);
      expect(find.text('vs SHORT'), findsOneWidget);
      expect(find.text('CONFLICT'), findsOneWidget);
      expect(find.text('SUPPORTS'), findsOneWidget);
      expect(find.textContaining('macro opposes'), findsOneWidget);
      expect(find.textContaining('macro credits'), findsOneWidget);
    });

    testWidgets('the rows do not depend on which side is live', (t) async {
      await t.pumpWidget(wrap(live(), macroAlignment: -1, sentimentAlignment: -1, isLong: true));
      final asLong = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').toList();

      await t.pumpWidget(wrap(live(), macroAlignment: -1, sentimentAlignment: -1, isLong: false));
      final asShort = find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').toList();

      expect(asLong.where((s) => s == 'CONFLICT' || s == 'SUPPORTS').toList(),
          asShort.where((s) => s == 'CONFLICT' || s == 'SUPPORTS').toList(),
          reason: 'flipping the live side must not change either row');
    });

    testWidgets('a bullish macro flips both rows', (t) async {
      await t.pumpWidget(wrap(live(), macroAlignment: 1, sentimentAlignment: 1));
      expect(find.text('SUPPORTS'), findsOneWidget);
      expect(find.text('CONFLICT'), findsOneWidget);
      expect(find.textContaining('macro credits'), findsOneWidget);
    });

    testWidgets('a neutral macro reads as neutral, not as support', (t) async {
      await t.pumpWidget(wrap(live(), macroAlignment: 0, sentimentAlignment: 0));
      expect(find.textContaining('macro neutral'), findsNWidgets(2));
      expect(find.text('SUPPORTS'), findsNothing);
      expect(find.text('CONFLICT'), findsNothing);
    });

    testWidgets('below the gate the layers are NOT WEIGHED, not neutral', (t) async {
      final thin = SentimentLayers([row('market_implied', 20, alignment: -1)]);
      await t.pumpWidget(wrap(thin));
      expect(find.text('NOT WEIGHED'), findsNWidgets(2));
      expect(find.textContaining('below the coverage gate'), findsNWidgets(2));
      expect(find.text('NEUTRAL'), findsNothing);
    });
  });

  group('no probability language', () {
    testWidgets('never renders a chance or a vote count', (t) async {
      await t.pumpWidget(wrap(live(), macroAlignment: 1, sentimentAlignment: 1));
      for (final text in find.byType(Text).evaluate()) {
        final s = ((text.widget as Text).data ?? '').toLowerCase();
        expect(s.contains('% chance'), isFalse);
        expect(s.contains('probability of'), isFalse);
        expect(s.contains('votes'), isFalse);
      }
      expect(
        find.textContaining('not a probability'),
        findsOneWidget,
        reason: 'the disclaimer states it explicitly',
      );
    });
  });

  group('coverage', () {
    testWidgets('live state reports 73%', (t) async {
      await t.pumpWidget(wrap(live()));
      expect(find.textContaining('MACRO COVERAGE 73%'), findsOneWidget);
    });

    testWidgets('renders at 390px without overflowing', (t) async {
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(wrap(live(), macroAlignment: -1, sentimentAlignment: -1));
      expect(t.takeException(), isNull);
    });
  });
}