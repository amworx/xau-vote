import 'package:xauvote/models/sentiment_layers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a `sentiment_layers` row the way PostgREST returns it (snake_case).
Map<String, dynamic> row({
  required String layer,
  required double weight,
  // score is numeric since §5.2 decays policy by exp(-days/30), so it is not
  // always an integer. alignment stays a smallint.
  num? score,
  int? alignment,
  String measuredAt = '2026-10-02T00:00:00.000Z',
  String source = 'some public source',
  bool stale = false,
  Map<String, dynamic> detail = const {},
}) => {
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
};

void main() {
  group('SentimentLayerRow.tryParse', () {
    test('parses a measured row', () {
      final r = SentimentLayerRow.tryParse(
        row(layer: 'positioning', weight: 25, score: -1, alignment: -1),
      )!;
      expect(r.layer, 'positioning');
      expect(r.weight, 25);
      expect(r.score, -1);
      expect(r.alignment, -1);
      expect(r.stale, isFalse);
      expect(r.isUnmeasured, isFalse);
      expect(r.measuredAt, isNotNull);
    });

    test('a null alignment is unmeasured, not a zero reading', () {
      final r = SentimentLayerRow.tryParse(
        row(layer: 'policy', weight: 35, score: null, alignment: null),
      )!;
      expect(r.score, isNull);
      expect(r.alignment, isNull);
      expect(r.isUnmeasured, isTrue);
    });

    test('a zero alignment is a real neutral reading, not unmeasured', () {
      final r = SentimentLayerRow.tryParse(
        row(layer: 'market_implied', weight: 20, alignment: 0),
      )!;
      expect(r.alignment, 0);
      expect(r.isUnmeasured, isFalse);
    });

    test('rejects rows missing a layer or source', () {
      expect(
        SentimentLayerRow.tryParse(row(layer: '', weight: 20, alignment: 1)),
        isNull,
      );
      expect(
        SentimentLayerRow.tryParse(
          row(layer: 'policy', weight: 35).tap((m) => m.remove('source')),
        ),
        isNull,
      );
      expect(
        SentimentLayerRow.tryParse(row(layer: 'policy', weight: 35).tap((m) => m['source'] = '')),
        isNull,
      );
    });

    test('rejects a row with no weight rather than assuming one', () {
      final m = row(layer: 'policy', weight: 35, alignment: 1)..remove('weight');
      expect(SentimentLayerRow.tryParse(m), isNull);
    });

    test('the epoch used for "never measured" is not read as a date', () {
      final r = SentimentLayerRow.tryParse(
        row(layer: 'policy', weight: 35, measuredAt: '1970-01-01T00:00:00.000Z'),
      )!;
      expect(r.measuredAt, isNull);
    });

    test('numeric strings parse, matching PostgREST numeric formatting', () {
      final r = SentimentLayerRow.tryParse(
        row(layer: 'positioning', weight: 25, score: -1, alignment: -1)
          ..['weight'] = '25'
          ..['alignment'] = '-1',
      )!;
      expect(r.weight, 25);
      expect(r.alignment, -1);
    });

    test('detail survives as a map', () {
      final r = SentimentLayerRow.tryParse(
        row(
          layer: 'positioning',
          weight: 25,
          alignment: -1,
          detail: const {'percentile_156w': 37.8, 'sample_weeks': 156},
        ),
      )!;
      expect(r.detail['percentile_156w'], 37.8);
      expect(r.detail['sample_weeks'], 156);
    });
  });

  group('coverage', () {
    test('live state: only market_implied measured -> 20 of 55 macro-side', () {
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'market_implied', weight: 20, alignment: -1),
        )!,
        SentimentLayerRow.tryParse(
          row(layer: 'positioning', weight: 25, score: -1, alignment: -1),
        )!,
        SentimentLayerRow.tryParse(row(layer: 'policy', weight: 35))!,
      ]);
      expect(layers.macroCoverage, closeTo(20 / 55, 1e-9));
      expect(layers.overallCoverage, closeTo(45 / 80, 1e-9));
    });

    test('positioning counts toward overall but not macro coverage', () {
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'positioning', weight: 25, alignment: 1),
        )!,
      ]);
expect(layers.macroCoverage, 0);
        // 25 of 80 claimed points, not 25 of 100. The denominator is the weight
        // the product actually claims, so removing an unobtainable layer raises
        // this fraction rather than leaving a permanent 80% ceiling.
        expect(layers.overallCoverage, closeTo(25 / 80, 1e-9));
    });

    test('empty layers report zero coverage, not a full read', () {
      const layers = SentimentLayers.empty();
      expect(layers.macroCoverage, 0);
      expect(layers.overallCoverage, 0);
    });
  });

  group('macro mapping', () {
    // Mirrors the rows actually in the database as of 2026-10-05: a 20-day-old
    // 25bp Fed hike (policy 35, alignment -1) and a +9bp real-yield move
    // (market_implied 20, alignment -1). WGC is still an unbuilt null row.
    SentimentLayers liveState() => SentimentLayers([
      SentimentLayerRow.tryParse(
        row(layer: 'market_implied', weight: 20, alignment: -1),
      )!,
      SentimentLayerRow.tryParse(
        row(layer: 'policy', weight: 35, score: -1.03, alignment: -1),
      )!,
        SentimentLayerRow.tryParse(
        row(layer: 'positioning', weight: 25, score: -1, alignment: -1),
      )!,
    ]);

    test('the measured real-yield impulse is always surfaced', () {
      expect(liveState().macro.realYieldImpulse, -1);
    });

    test('the policy impulse carries the decayed §5.2 score', () {
      // score is numeric since §5.2 decays it; the engine field is an int.
      expect(liveState().macro.policyImpulse, -1);
    });

    test('live macro coverage clears the gate and resolves to bearish', () {
      final layers = liveState();
      // policy 35 + market_implied 20 = 55 of 55 macro-side = 100%.
      expect(layers.macroCoverage, closeTo(55 / 55, 1e-9));
      expect(layers.macroCoverage, greaterThanOrEqualTo(SentimentLayers.macroAlignmentThreshold));
      expect(layers.macro.alignment, -1);
      expect(layers.macro.isAvailable, isTrue);
    });

    test('macro alignment stays null below the coverage threshold', () {
      // Only market_implied measured: 20/55 = 36%, under the 50% gate. The
      // scorer vetoes on a negative macro alignment, so a 27% sample must not be
      // able to block a setup.
      final thin = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'market_implied', weight: 20, alignment: -1),
        )!,
        SentimentLayerRow.tryParse(row(layer: 'policy', weight: 35))!,
      ]);
      expect(thin.macroCoverage, closeTo(20 / 55, 1e-9));
      final macro = thin.macro;
      expect(macro.alignment, isNull);
      expect(macro.isAvailable, isFalse);
      // The reading is still visible even while it cannot act.
      expect(macro.realYieldImpulse, -1);
    });

    test('dollar and inflation stay null instead of defaulting to 0', () {
      final macro = liveState().macro;
      expect(macro.dollarImpulse, isNull);
      expect(macro.inflationImpulse, isNull);
    });

    test('macro alignment resolves once the threshold is met', () {
      // market_implied 20 + policy 35 = 55 of 55 = 100%, over the gate.
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'market_implied', weight: 20, alignment: -1),
        )!,
        SentimentLayerRow.tryParse(
          row(layer: 'policy', weight: 35, score: 1, alignment: 1),
        )!,
      ]);
      expect(layers.macroCoverage, closeTo(55 / 55, 1e-9));
      // weight-weighted mean of (-1 * 20) and (+1 * 35) is positive.
      expect(layers.macro.alignment, 1);
      expect(layers.macro.isAvailable, isTrue);
    });

    test('a genuine macro negative resolves to -1', () {
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'market_implied', weight: 20, alignment: -1),
        )!,
        SentimentLayerRow.tryParse(
          row(layer: 'policy', weight: 35, score: -2, alignment: -1),
        )!,
      ]);
      expect(layers.macro.alignment, -1);
    });
  });

  group('sentiment mapping', () {
    test('a fresh positioning reading passes through', () {
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'positioning', weight: 25, score: -1, alignment: -1),
        )!,
      ]);
      final s = layers.sentiment;
      expect(s.alignment, -1);
      expect(s.cotStale, isFalse);
      expect(s.isAvailable, isTrue);
    });

    test('a stale weekly reading is unavailable, not merely flagged', () {
      // §27 Failure 4: COT past its window must not act as current.
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(
          row(layer: 'positioning', weight: 25, score: -1, alignment: -1, stale: true),
        )!,
      ]);
      final s = layers.sentiment;
      expect(s.alignment, -1);
      expect(s.cotStale, isTrue);
      expect(s.isAvailable, isFalse);
    });

    test('an absent positioning row is stale by default', () {
      const layers = SentimentLayers.empty();
      final s = layers.sentiment;
      expect(s.alignment, isNull);
      expect(s.cotStale, isTrue);
      expect(s.isAvailable, isFalse);
    });
  });

  group('layer presence', () {
    test('missing and unmeasured are distinguishable', () {
      final layers = SentimentLayers([
        SentimentLayerRow.tryParse(row(layer: 'policy', weight: 35))!,
      ]);
      // policy exists as a row but carries no measurement.
      expect(layers.isMissing('policy'), isFalse);
      expect(layers.isUnmeasured('policy'), isTrue);
    });
  });
}

extension _Tap on Map<String, dynamic> {
  Map<String, dynamic> tap(void Function(Map<String, dynamic>) fn) {
    fn(this);
    return this;
  }
}