import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

Candle _c(double o, double h, double l, double c, [double? v, int min = 0]) {
  return Candle(
    openTime: DateTime.utc(2026, 10, 7, 12, 0).add(Duration(minutes: min)),
    open: o,
    high: h,
    low: l,
    close: c,
    volume: v,
  );
}

void main() {
  group('vwap', () {
    test('volume-weighted mean with honest flag', () {
      final bars = [
        _c(9, 10, 8, 9, 100),
        _c(11, 12, 10, 11, 200),
        _c(10, 11, 9, 10, 100),
      ];
      final r = vwap(bars, sessionStart: DateTime.utc(2026, 10, 7));
      expect(r, isNotNull);
      // (9*100 + 11*200 + 10*100) / 400 = 4100/400
      expect(r!.value, closeTo(10.25, 1e-9));
      expect(r.volumeBacked, isTrue);
    });

    test('equal-weight fallback without volume, flagged', () {
      final bars = [_c(9, 10, 8, 9), _c(11, 12, 10, 11), _c(10, 11, 9, 10)];
      final r = vwap(bars, sessionStart: DateTime.utc(2026, 10, 7));
      expect(r, isNotNull);
      // (9 + 11 + 10) / 3 — a session average, not a volume-weighted one.
      expect(r!.value, closeTo(10.0, 1e-9));
      expect(r.volumeBacked, isFalse);
    });

    test('respects the session start and empties to null', () {
      final bars = [_c(9, 10, 8, 9, 100)];
      expect(
        vwap(bars, sessionStart: DateTime.utc(2026, 10, 8)),
        isNull,
      );
    });
  });

  group('activityRatio', () {
    test('recent mean over prior mean', () {
      final bars = [
        for (final v in [10.0, 10.0, 10.0, 30.0, 30.0, 30.0])
          _c(v, v, v, v, v),
      ];
      expect(activityRatio(bars, lookback: 3), closeTo(3.0, 1e-9));
    });

    test('null on missing volume or short history', () {
      expect(activityRatio([_c(1, 1, 1, 1)], lookback: 3), isNull);
      final bars = [
        for (var i = 0; i < 6; i++) _c(1, 2, 0.5, 1.5, i < 3 ? null : 10.0),
      ];
      expect(activityRatio(bars, lookback: 3), isNull);
    });
  });

  group('structureState', () {
    test('higher highs and higher lows read bullish', () {
      final s = structureState([
        const Swing(index: 1, price: 100, isHigh: false),
        const Swing(index: 2, price: 110, isHigh: true),
        const Swing(index: 3, price: 105, isHigh: false),
        const Swing(index: 4, price: 115, isHigh: true),
      ]);
      expect(s.state, StructureState.bullish);
      expect(s.detail, 'HH / HL');
    });

    test('lower highs and lower lows read bearish', () {
      final s = structureState([
        const Swing(index: 1, price: 105, isHigh: false),
        const Swing(index: 2, price: 115, isHigh: true),
        const Swing(index: 3, price: 100, isHigh: false),
        const Swing(index: 4, price: 110, isHigh: true),
      ]);
      expect(s.state, StructureState.bearish);
      expect(s.detail, 'LH / LL');
    });

    test('mixed swings read ranging, short lists unknown', () {
      final s = structureState([
        const Swing(index: 1, price: 100, isHigh: false),
        const Swing(index: 2, price: 115, isHigh: true),
        const Swing(index: 3, price: 105, isHigh: false),
        const Swing(index: 4, price: 115, isHigh: true),
      ]);
      expect(s.state, StructureState.ranging);
      expect(
        structureState([const Swing(index: 1, price: 1, isHigh: true)]).state,
        StructureState.unknown,
      );
    });
  });

  group('summarizeLeans', () {
    test('3+ of 4 in one camp decides, else mixed', () {
      expect(
        summarizeLeans(bull: 4, bear: 0, total: 4, strongTrend: true).state,
        RegimeState.bullish,
      );
      expect(
        summarizeLeans(bull: 1, bear: 3, total: 4, strongTrend: false).state,
        RegimeState.bearish,
      );
      expect(
        summarizeLeans(bull: 2, bear: 2, total: 4, strongTrend: true).state,
        RegimeState.mixed,
      );
      expect(
        summarizeLeans(bull: 1, bear: 0, total: 4, strongTrend: false).state,
        RegimeState.mixed,
      );
      final s = summarizeLeans(bull: 3, bear: 1, total: 4, strongTrend: true);
      expect(s.fraction, closeTo(0.75, 1e-9));
      expect(s.strongTrend, isTrue);
    });
  });

  group('computeRegime', () {
    test('starved input yields nulls and a mixed summary, never zeros', () {
      final bars = [_c(100, 101, 99, 100), _c(100, 101, 99, 100)];
      final r = computeRegime(bars, sessionStart: DateTime.utc(2026, 10, 7));
      expect(r.emaTrend, isNull);
      expect(r.structure, StructureState.unknown);
      expect(r.adx, isNull);
      expect(r.summary.state, RegimeState.mixed);
      expect(r.summary.fraction, 0);
      // No volume anywhere: VWAP falls back flagged, activity is null.
      expect(r.volumeBacked, isFalse);
      expect(r.activityRatio, isNull);
    });

    test('sustained rally with pullbacks reads bullish', () {
      // Dip 90, rally 100, dip 95, rally through 105: HH/HL with the stack
      // aligned and rising at the end.
      final closes = <double>[
        100.0, 98, 94, 90, 92, 96, 100, 99, 96, 95,
        97, 100, 103, 102, 105, 104, 106, 108, 107, 109,
      ];
      final bars = [
        for (var i = 0; i < closes.length; i++)
          _c(closes[i] - 0.5, closes[i] + 1.5, closes[i] - 1.5, closes[i], 10.0, i * 15),
      ];
      final r = computeRegime(
        bars,
        params: const RegimeParams(
          emaFast: 3,
          emaMid: 5,
          emaTrend: 7,
          swingLookback: 1,
          adxPeriod: 5,
          rsiPeriod: 5,
          macdFast: 2,
          macdSlow: 4,
          macdSignal: 2,
          atrPeriod: 3,
        ),
        sessionStart: DateTime.utc(2026, 10, 7),
      );
      expect(r.structure, StructureState.bullish);
      expect(r.directionLean, RegimeLean.bullish);
      expect(r.vwap, isNotNull);
      expect(r.volumeBacked, isTrue);
      expect(r.summary.state, RegimeState.bullish);
    });
  });
}
