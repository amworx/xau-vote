import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

Candle bar(int minutes, double o, double h, double l, double c,
        {bool closed = true, int quality = 0}) =>
    Candle(
      openTime: DateTime.utc(2026, 1, 1, 0, minutes),
      open: o,
      high: h,
      low: l,
      close: c,
      isClosed: closed,
      quality: CandleQuality.values[quality],
    );

void main() {
  group('Candle validation (rule 2)', () {
    test('accepts a well-formed bar', () {
      expect(bar(0, 4000, 4010, 3990, 4005).validationError, isNull);
    });

    test('rejects high below the body', () {
      final c = bar(0, 4000, 4002, 3990, 4005); // close 4005 > high 4002
      expect(c.validationError, contains('high < max(open, close)'));
    });

    test('rejects low above the body', () {
      final c = bar(0, 4000, 4010, 4002, 3995); // open 4000 < low 4002
      expect(c.validationError, contains('low > min(open, close)'));
    });

    test('rejects high < low', () {
      expect(bar(0, 4000, 3990, 4010, 4000).validationError, contains('high < low'));
    });

    test('rejects non-UTC timestamps', () {
      final c = Candle(
        openTime: DateTime(2026, 1, 1),
        open: 4000,
        high: 4010,
        low: 3990,
        close: 4005,
      );
      expect(c.validationError, contains('UTC'));
    });

    test('rejects non-finite and non-positive prices', () {
      expect(bar(0, double.nan, 4010, 3990, 4005).validationError, contains('non-finite'));
      expect(bar(0, 4000, 4010, 3990, 0).validationError, contains('non-positive'));
    });
  });

  group('validateCandles (rules 1-3)', () {
    test('reports duplicates instead of silently dropping them', () {
      final v = validateCandles(
        [bar(0, 4000, 4010, 3990, 4005), bar(0, 4000, 4010, 3990, 4009)],
        const Duration(minutes: 5),
      );
      expect(v.accepted.length, 1);
      expect(v.rejected[CandleIssue.duplicateTimestamp], hasLength(1));
      expect(v.isClean, isFalse);
    });

    test('detects a missing interval', () {
      final v = validateCandles(
        [bar(0, 4000, 4010, 3990, 4005), bar(15, 4005, 4015, 3995, 4010)],
        const Duration(minutes: 5),
      );
      expect(v.accepted.length, 2);
      expect(v.gaps, hasLength(1));
    });

    test('contiguous series is clean', () {
      final v = validateCandles(
        [
          bar(0, 4000, 4010, 3990, 4005),
          bar(5, 4005, 4015, 3995, 4010),
          bar(10, 4010, 4020, 4000, 4015),
        ],
        const Duration(minutes: 5),
      );
      expect(v.isClean, isTrue);
    });

    test('sorts out-of-order input without corrupting gaps', () {
      final v = validateCandles(
        [bar(10, 4010, 4020, 4000, 4015), bar(0, 4000, 4010, 3990, 4005)],
        const Duration(minutes: 5),
      );
      expect(v.accepted.map((c) => c.openTime.minute), [0, 10]);
      expect(v.gaps, hasLength(1)); // 5m interval missing
    });
  });

  group('closedOnly (rule 9)', () {
    test('drops the in-progress bar', () {
      final bars = [
        bar(0, 4000, 4010, 3990, 4005),
        bar(5, 4005, 4015, 3995, 4010, closed: false),
      ];
      expect(closedOnly(bars).length, 1);
      expect(closedOnly(bars).single.closeTime.minute, 0);
    });
  });

  group('resample (rule 8)', () {
    List<Candle> m5() => [
          for (var i = 0; i < 3; i++)
            bar(i * 5, 4000.0 + i, 4005.0 + i, 3995.0 + i, 4002.0 + i),
        ];

    test('three 5m bars form one complete 15m bar', () {
      final out = resample(m5(), const Duration(minutes: 5), const Duration(minutes: 15));
      expect(out, hasLength(1));
      expect(out.single.open, 4000.0);
      expect(out.single.high, 4007.0); // high of bar 3
      expect(out.single.low, 3995.0); // low of bar 1
      expect(out.single.close, 4004.0); // close of bar 3
    });

    test('incomplete bucket is withheld, never emitted as confirmed', () {
      final partial = m5().sublist(0, 2);
      final out = resample(partial, const Duration(minutes: 5), const Duration(minutes: 15));
      expect(out, isEmpty);
    });

    test('open source bars are ignored entirely', () {
      final bars = m5();
      bars[2] = bar(10, 4002, 4007, 3997, 4004, closed: false);
      final out = resample(bars, const Duration(minutes: 5), const Duration(minutes: 15));
      expect(out, isEmpty);
    });

    test('sums tick volume when present', () {
      final bars = [
        for (var i = 0; i < 3; i++)
          Candle(
            openTime: DateTime.utc(2026, 1, 1, 0, i * 5),
            open: 4000.0,
            high: 4005.0,
            low: 3995.0,
            close: 4002.0,
            volume: 10.0,
          ),
      ];
      final out = resample(bars, const Duration(minutes: 5), const Duration(minutes: 15));
      expect(out.single.volume, 30.0);
    });

    test('volume becomes null when any source bar lacks it', () {
      final bars = [
        for (var i = 0; i < 3; i++)
          Candle(
            openTime: DateTime.utc(2026, 1, 1, 0, i * 5),
            open: 4000.0,
            high: 4005.0,
            low: 3995.0,
            close: 4002.0,
            volume: i == 1 ? null : 10.0,
          ),
      ];
      final out = resample(bars, const Duration(minutes: 5), const Duration(minutes: 15));
      expect(out.single.volume, isNull);
    });

    test('degrades quality when any source bar is degraded', () {
      final bars = m5();
      bars[1] = bar(5, 4001, 4006, 3996, 4003, quality: 2);
      final out = resample(bars, const Duration(minutes: 5), const Duration(minutes: 15));
      expect(out.single.quality, CandleQuality.degraded);
    });

    test('rejects a target not longer than the source interval', () {
      expect(
        () => resample(m5(), const Duration(minutes: 15), const Duration(minutes: 5)),
        throwsArgumentError,
      );
    });
  });

  group('ema', () {
    test('is undefined before the period is satisfied', () {
      final r = ema([1, 2, 3], 3);
      expect(r[0], isNull);
      expect(r[1], isNull);
      expect(r[2], 2.0); // SMA seed
    });

    test('seeds with an SMA then applies k = 2/(p+1)', () {
      // period 3, seed = (1+2+3)/3 = 2, k = 0.5, next = (4-2)*0.5+2 = 3
      final r = ema([1, 2, 3, 4], 3);
      expect(r[2], 2.0);
      expect(r[3], 3.0);
    });

    test('constant series stays flat', () {
      final r = ema(List<double>.filled(10, 50), 5);
      expect(r.last, closeTo(50.0, 1e-9));
    });

    test('empty input yields no values', () {
      expect(ema([], 5).isEmpty, isTrue);
    });
  });

  group('rsi (14)', () {
    test('all-gains series pins to 100', () {
      final r = rsi(List<double>.generate(20, (i) => 100.0 + i));
      expect(r.last, 100.0);
    });

    test('all-losses series pins to 0', () {
      final r = rsi(List<double>.generate(20, (i) => 100.0 - i));
      expect(r.last, 0.0);
    });

    test('flat series is neutral at 50', () {
      final r = rsi(List<double>.filled(20, 100));
      expect(r.last, 50.0);
    });

    test('is undefined until period + 1 values exist', () {
      final r = rsi([1, 2, 3], period: 14);
      expect(r.isEmpty, isTrue);
    });

    test('strong uptrend sits above the 50 momentum regime line', () {
      final r = rsi(List<double>.generate(40, (i) => 4000.0 + i * 2));
      expect(r.last, greaterThan(50));
      expect(r.last, lessThanOrEqualTo(100));
    });
  });

  group('macd (12/26/9)', () {
    test('histogram equals macd minus signal', () {
      final prices = List<double>.generate(120, (i) => 4000 + (i % 17) * 1.5);
      final m = macd(prices);
      final i = prices.length - 1;
      expect(m.histogram[i], closeTo(m.macd[i]! - m.signal[i]!, 1e-9));
    });

    test('signal line starts one defined-MACD period after warm-up', () {
      final prices = List<double>.generate(120, (i) => 4000 + i.toDouble());
      final m = macd(prices);
      // Slow EMA (26) seeds at index 25, so MACD is defined from index 25.
      // The signal EMA needs 9 defined values: first signal lands at index 33.
      expect(m.macd[24], isNull);
      expect(m.macd[25], isNotNull);
      expect(m.signal[32], isNull);
      expect(m.signal[33], isNotNull);
    });

    test('series too short produces no histogram', () {
      expect(macd(List<double>.filled(10, 100)).histogram.isEmpty, isTrue);
    });
  });

  group('atr (14)', () {
    List<Candle> flat(int n, double range) => [
          for (var i = 0; i < n; i++)
            bar(i, 4000, 4000 + range, 4000 - range, 4000 + (i.isEven ? range : -range)),
        ];

    test('constant range gives ATR equal to that range', () {
      final r = atr(flat(20, 2.0));
      expect(r.last, closeTo(4.0, 1e-6));
    });

    test('is undefined before period + 1 bars', () {
      expect(atr(flat(10, 2.0), period: 14).isEmpty, isTrue);
    });

    test('trueRange uses the widest of HL, HC, LC', () {
      final prev = bar(0, 4000, 4000, 4000, 4000);
      expect(trueRange(prev, bar(5, 4000, 4010, 4000, 4005)), 10.0);
      expect(trueRange(prev, bar(5, 4000, 4000, 3990, 3995)), 10.0);
    });
  });

  group('adx (14)', () {
    test('strong one-way trend gives high ADX and DI dominance', () {
      final bars = [
        for (var i = 0; i < 60; i++)
          bar(i, 4000.0 + i * 5, 4005.0 + i * 5, 3998.0 + i * 5, 4003.0 + i * 5),
      ];
      final r = adx(bars);
      expect(r.adx.last, greaterThan(50));
      final p = r.plusDi.last;
      final m = r.minusDi.last;
      expect(p, isNotNull);
      expect(m, isNotNull);
      expect(p!, greaterThan(m!));
    });

    test('choppy flat market gives low ADX', () {
      final bars = [
        for (var i = 0; i < 60; i++)
          bar(i, 4000 + (i.isEven ? 1.0 : -1.0), 4002, 3998, 4000),
      ];
      final r = adx(bars);
      expect(r.adx.last, lessThan(30));
    });

    test('insufficient history yields no values', () {
      expect(adx([bar(0, 4000, 4010, 3990, 4005)]).adx.isEmpty, isTrue);
    });
  });

  group('bollinger (20, 2)', () {
    test('bands straddle the middle and bandwidth is positive', () {
      final prices = List<double>.generate(40, (i) => 4000 + (i % 7) * 2.0);
      final b = bollinger(prices);
      final i = prices.length - 1;
      expect(b.upper[i], greaterThan(b.middle[i]!));
      expect(b.lower[i], lessThan(b.middle[i]!));
      expect(b.bandwidth[i], greaterThan(0));
    });

    test('flat series has zero-width bands', () {
      final b = bollinger(List<double>.filled(40, 4000));
      expect(b.bandwidth.last, 0.0);
    });
  });

  group('swings', () {
    test('finds a peak at index 6 and a trough at index 9', () {
      // highs strictly rise to 6 then fall; lows strictly fall to 9 then rise.
      final highs = [4001.0, 4002.0, 4003.0, 4004.0, 4005.0, 4006.0, 4010.0,
        4009.0, 4008.0, 4007.0, 4008.0, 4009.0, 4010.0];
      final lows = [3999.0, 3998.0, 3997.0, 3996.0, 3995.0, 3994.0, 3993.0,
        3992.0, 3991.0, 3985.0, 3986.0, 3987.0, 3988.0];
      final bars = [
        for (var i = 0; i < 13; i++)
          Candle(
            openTime: DateTime.utc(2026, 1, 1, 0, i * 5),
            open: (highs[i] + lows[i]) / 2,
            high: highs[i],
            low: lows[i],
            close: (highs[i] + lows[i]) / 2,
          ),
      ];
      final s = swings(bars, lookback: 2);
      expect(s.any((x) => x.isHigh && x.index == 6), isTrue);
      expect(s.any((x) => !x.isHigh && x.index == 9), isTrue);
    });

    test('last lookback bars cannot produce a confirmed swing', () {
      final bars = [
        for (var i = 0; i < 10; i++) bar(i, 4000, 4000 + i.toDouble(), 3990, 4000),
      ];
      final s = swings(bars, lookback: 2);
      expect(s.every((x) => x.index <= bars.length - 1 - 2), isTrue);
    });

    test('too few bars yields no swings', () {
      expect(swings([bar(0, 4000, 4010, 3990, 4005)], lookback: 2), isEmpty);
    });

    test('lastSwingLow/High respect the index bound', () {
      final s = [
        const Swing(index: 2, price: 3990, isHigh: false),
        const Swing(index: 6, price: 4010, isHigh: true),
        const Swing(index: 9, price: 3980, isHigh: false),
      ];
      expect(lastSwingLow(s, 9)!.price, 3980);
      expect(lastSwingLow(s, 5)!.price, 3990);
      expect(lastSwingHigh(s, 9)!.price, 4010);
      expect(lastSwingHigh(s, 3), isNull);
    });
  });

  group('atrPercentile', () {
    // A percentile needs enough history to mean anything; the implementation
    // refuses to answer below 20 valid samples rather than inventing a rank.
    List<double> history(int n, double base) =>
        List<double>.generate(n, (i) => base + i);

    test('latest spike sits at the 100th percentile', () {
      final hist = [...history(19, 10.0), 99.0];
      expect(atrPercentile(hist), 100.0);
    });

    test('latest trough sits at the bottom of the window', () {
      final hist = [...history(19, 10.0), 5.0];
      expect(atrPercentile(hist), 5.0); // only itself is <= itself
    });

    test('refuses to answer on too little history', () {
      expect(atrPercentile([10.0, 11.0, 12.0]), isNull);
      expect(atrPercentile(history(19, 10.0)), isNull);
    });

    test('ignores non-positive and non-finite entries', () {
      final hist = [...history(20, 10.0), double.nan, 0.0, -5.0];
      final p = atrPercentile(hist);
      expect(p, isNotNull);
      expect(p, closeTo(100.0, 1e-9));
    });

    test('lookback window restricts ranking to recent history', () {
      // One ancient spike, then a long quiet stretch.
      final hist = [500.0, ...List<double>.filled(30, 10.0)];
      // Recent-only window: the spike is excluded, so 10.0 ranks last.
      expect(atrPercentile(hist, lookback: 10), 100.0);
      // Wider window: the spike drags the latest value's rank down slightly.
      expect(atrPercentile(hist, lookback: 100), closeTo(30 / 31 * 100, 1e-9));
    });
  });

  group('usdDistance', () {
    test('is absolute USD, independent of broker pip convention', () {
      expect(usdDistance(4010, 4000), 10.0);
      expect(usdDistance(4000, 4010), 10.0);
    });
  });
}