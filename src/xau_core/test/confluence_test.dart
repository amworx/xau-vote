import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

/// A clean bullish stack on every timeframe, used as the "everything agrees"
/// baseline that individual tests then break in exactly one way.
TimeframeState bull({
  double? rsi,
  double? adx,
  double? atrPct,
  bool pattern = true,
  double? close,
}) =>
    TimeframeState(
      timeframe: Tf.m30,
      close: close ?? 4050,
      ema20: 4040,
      ema50: 4030,
      ema200: 4000,
      rsi14: rsi ?? 60.0,
      macdHistogram: 1.0,
      adx14: adx ?? 28.0,
      plusDi: 30,
      minusDi: 10,
      atr: 10,
      atrPercentile: atrPct ?? 50,
      swingLow: 4035,
      swingHigh: 4048,
      hasEngulfing: pattern,
    );

/// The 15m setup must be a *pullback*: price parked inside the EMA20-50 zone,
/// not extended beyond it. Using the trend fixture here would score a chase,
/// which the methodology explicitly rejects.
TimeframeState pullbackLong({bool pattern = true}) => TimeframeState(
      timeframe: Tf.m15,
      close: 4035,
      ema20: 4040,
      ema50: 4030,
      ema200: 4000,
      rsi14: 58,
      macdHistogram: 0.5,
      adx14: 26,
      plusDi: 28,
      minusDi: 12,
      atr: 10,
      atrPercentile: 50,
      swingLow: 4025,
      swingHigh: 4050,
      hasEngulfing: pattern,
    );

TimeframeState pullbackShort({bool pattern = true}) => TimeframeState(
      timeframe: Tf.m15,
      close: 3965,
      ema20: 3960,
      ema50: 3970,
      ema200: 4000,
      rsi14: 42,
      macdHistogram: -0.5,
      adx14: 26,
      plusDi: 12,
      minusDi: 28,
      atr: 10,
      atrPercentile: 50,
      swingLow: 3950,
      swingHigh: 3975,
      hasEngulfing: pattern,
    );

TimeframeState bear({
  double? rsi,
  double? adx,
  double? atrPct,
  bool pattern = true,
  double? close,
}) =>
    TimeframeState(
      timeframe: Tf.m30,
      close: close ?? 3950,
      ema20: 3960,
      ema50: 3970,
      ema200: 4000,
      rsi14: rsi ?? 40.0,
      macdHistogram: -1.0,
      adx14: adx ?? 28.0,
      plusDi: 10,
      minusDi: 30,
      atr: 10,
      atrPercentile: atrPct ?? 50,
      swingLow: 3952,
      swingHigh: 3965,
      hasEngulfing: pattern,
    );

ConfluenceInput build({
  Side dir = Side.long,
  TimeframeState? h1,
  TimeframeState? m30,
  TimeframeState? m15,
  TimeframeState? m5,
  bool blackout = false,
  bool dataStale = false,
  bool sessionOpen = true,
  bool duplicate = false,
  bool blockedByLevel = false,
  SpreadStatus spread = SpreadStatus.unavailable,
  MacroState? macro,
  SentimentState? sentiment,
  int today = 0,
  double? stopAtr = 1.2,
  double? tp2R = 2.0,
  double? atrPctOverride,
  double? rsiOverride,
}) =>
    ConfluenceInput(
      direction: dir,
      h1: h1 ?? (dir == Side.long ? bull(rsi: rsiOverride) : bear(rsi: rsiOverride)),
      m30: m30 ??
          (dir == Side.long ? bull(atrPct: atrPctOverride) : bear(atrPct: atrPctOverride)),
      m15: m15 ?? (dir == Side.long ? pullbackLong() : pullbackShort()),
      m5: m5 ?? (dir == Side.long ? bull(atrPct: atrPctOverride) : bear(atrPct: atrPctOverride)),
      atr5m: 10,
      macro: macro,
      sentiment: sentiment,
      spreadStatus: spread,
      blackout: blackout,
      dataStale: dataStale,
      sessionOpen: sessionOpen,
      signalsEmittedToday: today,
      duplicate: duplicate,
      stopDistanceAtr: stopAtr,
      tp2R: tp2R,
      blockedByLevel: blockedByLevel,
    );

void main() {
  const engine = ConfluenceEngine();

  group('technical scoring (methodology §8.2, 12-point)', () {
    test('fully aligned long scores 12 and publishes', () {
      final r = engine.evaluate(build());
      expect(r.technicalScore, 12);
      expect(r.verdict, Verdict.long);
      expect(r.grade, Grade.aPlus);
    });

    test('short mirrors the long symmetrically', () {
      final r = engine.evaluate(build(dir: Side.short));
      expect(r.technicalScore, 12);
      expect(r.verdict, Verdict.short);
    });

    test('neutral 1H with no EMA stack cannot reach the floor', () {
      // Mixed EMAs drop the alignment points and the structural points.
      final flat = TimeframeState(
        timeframe: Tf.m30,
        close: 4000,
        ema20: 4000,
        ema50: 4000,
        ema200: 4000,
        rsi14: 50,
        atrPercentile: 50,
        swingLow: 3990,
        swingHigh: 4010,
      );
      final r = engine.evaluate(build(h1: flat, m30: flat));
      expect(r.verdict, Verdict.noTrade);
      expect(r.has(ReasonCode.v11H1Neutral) || r.has(ReasonCode.v12LowConfluence), isTrue);
    });

    test('m15 pullback out of the EMA zone removes the setup points', () {
      final r = engine.evaluate(build(m15: bull(close: 4100)));
      expect(r.has(ReasonCode.m15PullbackToZone), isFalse);
      expect(r.has(ReasonCode.v15ExtendedEntry), isTrue);
      expect(r.verdict, Verdict.noTrade);
    });

    test('no 5m trigger costs the trigger points', () {
      final r = engine.evaluate(build(m5: bull(pattern: false)));
      expect(r.has(ReasonCode.m5TriggerPresent), isFalse);
      expect(r.technicalScore, lessThan(12));
    });

    test('weak ADX removes the trend-strength point but can still qualify', () {
      final r = engine.evaluate(build(m30: bull(adx: 12)));
      expect(r.has(ReasonCode.adxConfirmsTrend), isFalse);
      expect(r.technicalScore, 11);
    });
  });

  group('hard vetoes (methodology §9, §15)', () {
    test('event blackout vetoes even a perfect setup (Rule 1)', () {
      final r = engine.evaluate(build(blackout: true));
      expect(r.verdict, Verdict.noTrade);
      expect(r.vetoed, contains(ReasonCode.v1Blackout));
    });

    test('extreme volatility vetoes (Rule 2)', () {
      final r = engine.evaluate(build(atrPctOverride: 99));
      expect(r.vetoed, contains(ReasonCode.v4VolatilityExtreme));
    });

    test('stale or missing data vetoes', () {
      expect(engine.evaluate(build(dataStale: true)).vetoed, contains(ReasonCode.v3DataStale));
      final noData = TimeframeState(timeframe: Tf.h1, close: null);
      expect(engine.evaluate(build(h1: noData)).vetoed, contains(ReasonCode.v3DataStale));
    });

    test('closed session vetoes', () {
      expect(engine.evaluate(build(sessionOpen: false)).vetoed, contains(ReasonCode.v8SessionClosed));
    });

    test('daily signal limit vetoes', () {
      expect(engine.evaluate(build(today: 4)).vetoed, contains(ReasonCode.v7DailyLimit));
      expect(engine.evaluate(build(today: 3)).verdict, Verdict.long);
    });

    test('duplicate vetoes', () {
      expect(engine.evaluate(build(duplicate: true)).vetoed, contains(ReasonCode.v9Duplicate));
    });

    test('TP2 below the 1.8R floor vetoes', () {
      expect(engine.evaluate(build(tp2R: 1.5)).vetoed, contains(ReasonCode.v5PoorRewardRisk));
      expect(engine.evaluate(build(tp2R: 1.8)).vetoed, isNot(contains(ReasonCode.v5PoorRewardRisk)));
    });

    test('a level blocking the path vetoes', () {
      expect(engine.evaluate(build(blockedByLevel: true)).vetoed, contains(ReasonCode.v5PoorRewardRisk));
    });

    test('stop outside 0.8-1.8 ATR vetoes', () {
      expect(engine.evaluate(build(stopAtr: 0.5)).vetoed, contains(ReasonCode.v13BadStopDistance));
      expect(engine.evaluate(build(stopAtr: 2.5)).vetoed, contains(ReasonCode.v13BadStopDistance));
      expect(engine.evaluate(build(stopAtr: 1.0)).vetoed, isNot(contains(ReasonCode.v13BadStopDistance)));
    });

    test('RSI exhaustion blocks a fresh entry at the extremes', () {
      expect(engine.evaluate(build(rsiOverride: 80)).vetoed, contains(ReasonCode.v14RsiExhausted));
      final short = engine.evaluate(build(dir: Side.short, rsiOverride: 20));
      expect(short.vetoed, contains(ReasonCode.v14RsiExhausted));
    });

    test('macro strongly opposing vetoes (Rule 3)', () {
      final r = engine.evaluate(build(macro: const MacroState(alignment: -1)));
      expect(r.vetoed, contains(ReasonCode.v6DirectionConflict));
    });

    test('technical below the floor vetoes', () {
      final weak = TimeframeState(
        timeframe: Tf.m30,
        close: 4000,
        ema20: 4001,
        ema50: 3999,
        ema200: 4000,
        rsi14: 50,
        atrPercentile: 50,
      );
      final r = engine.evaluate(build(h1: weak, m30: weak, m15: weak, m5: weak));
      expect(r.vetoed, contains(ReasonCode.v12LowConfluence));
    });
  });

  group('spread policy (ratified option (a))', () {
    test('unavailable spread is recorded UNEVALUATED and never fires a veto', () {
      final r = engine.evaluate(build(spread: SpreadStatus.unavailable));
      expect(r.spreadStatus, SpreadStatus.unavailable);
      expect(r.has(ReasonCode.v2SpreadUnevaluated), isTrue);
      // The spread veto must NOT fire: missing data is not a pass, it is
      // simply unmeasured.
      expect(r.vetoed, isNot(contains(ReasonCode.v2SpreadUnevaluated)));
      expect(r.verdict, Verdict.long);
    });

    test('an available spread does not add the data-quality note', () {
      final r = engine.evaluate(build(spread: SpreadStatus.available));
      expect(r.has(ReasonCode.v2SpreadUnevaluated), isFalse);
    });

    test('a perfect setup still publishes without spread data', () {
      expect(engine.evaluate(build()).verdict, Verdict.long);
    });
  });

  group('macro and sentiment overlay (§8.3)', () {
    test('supporting macro raises the final score without touching technical', () {
      final base = engine.evaluate(build());
      final supported = engine.evaluate(build(macro: const MacroState(alignment: 1)));
      expect(supported.technicalScore, base.technicalScore);
      expect(supported.finalScore, base.finalScore + 2);
    });

    test('stale COT is treated as unavailable, not as bearish', () {
      final r = engine.evaluate(build(sentiment: const SentimentState(alignment: -1, cotStale: true)));
      expect(r.sentimentAlignment, isNull);
      expect(r.conflictPenalty, 0);
      expect(r.verdict, Verdict.long);
    });

    test('slow sentiment reduces confidence but never reverses (Rule 4)', () {
      final r = engine.evaluate(build(sentiment: const SentimentState(alignment: -1)));
      expect(r.verdict, Verdict.long, reason: 'sentiment must never flip a trade');
      expect(r.finalScore, lessThan(12.0));
      expect(r.conflictPenalty, 1);
    });

    test('unavailable macro contributes zero rather than a default +1', () {
      final r = engine.evaluate(build());
      expect(r.macroAlignment, isNull);
      expect(r.finalScore, r.technicalScore.toDouble());
    });
  });

  group('grading (MGC §9.3)', () {
    test('a vetoed scan never grades A or better', () {
      final r = engine.evaluate(build(blackout: true));
      expect(r.grade, Grade.insufficient);
    });

    test('B grade is the floor for a published signal', () {
      final mild = bull(adx: 21);
      final r = engine.evaluate(build(m30: mild, h1: bull(adx: 21)));
      expect(r.verdict, Verdict.long);
      expect(r.grade, anyOf(Grade.a, Grade.aPlus, Grade.b));
    });
  });

  group('reproducibility and reason codes', () {
    test('identical inputs give identical output', () {
      final a = engine.evaluate(build());
      final b = engine.evaluate(build());
      expect(a.technicalScore, b.technicalScore);
      expect(a.finalScore, b.finalScore);
      expect(a.reasonCodes, b.reasonCodes);
    });

    test('every NO_TRADE carries at least one reason code', () {
      for (final input in [
        build(blackout: true),
        build(today: 9),
        build(stopAtr: 9),
        build(dataStale: true),
      ]) {
        final r = engine.evaluate(input);
        expect(r.verdict, Verdict.noTrade);
        expect(r.reasonCodes, isNotEmpty);
        expect(r.vetoed, isNotEmpty);
      }
    });

    test('reason codes are unique', () {
      final r = engine.evaluate(build(macro: const MacroState(alignment: -1)));
      expect(r.reasonCodes.toSet().length, r.reasonCodes.length);
    });

    test('a published signal reports the spread gap as context, not a veto', () {
      final r = engine.evaluate(build());
      expect(r.isTrade, isTrue);
      expect(r.vetoed, isEmpty);
      expect(r.has(ReasonCode.v2SpreadUnevaluated), isTrue);
    });
  });
}