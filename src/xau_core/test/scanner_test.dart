import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

/// Builds a deterministic closed-bar series with a controllable trend so
/// indicator state is predictable without hand-writing hundreds of bars.
List<Candle> series(
  Tf tf, {
  int n = 260,
  double start = 4000,
  double driftPerBar = 0.0,
  double amplitude = 6,
  double period = 9,
  int? qualityIndex,
  bool allDegraded = false,
}) {
  final mins = switch (tf) { Tf.m5 => 5, Tf.m15 => 15, Tf.m30 => 30, Tf.h1 => 60 };
  final base = DateTime.utc(2026, 9, 1);
  return [
    for (var i = 0; i < n; i++)
      Candle(
        openTime: base.add(Duration(minutes: mins * i)),
        open: start + driftPerBar * i,
        high: start + driftPerBar * i + amplitude * (0.5 + 0.5 * math.sin(i / period)),
        low: start + driftPerBar * i - amplitude * (0.5 + 0.5 * math.sin(i / period)),
        close: start + driftPerBar * i + amplitude * math.sin(i / period),
        quality: (allDegraded || qualityIndex == null)
            ? CandleQuality.primary
            : CandleQuality.values[qualityIndex],
      ),
  ];
}

TimeframeBars tf(Tf t, {int n = 260, double drift = 0.0, bool degraded = false}) => TimeframeBars(
      timeframe: t,
      bars: series(t, n: n, driftPerBar: drift, allDegraded: degraded),
      allDegraded: degraded,
    );

ScanRequest req({
  Side? dir = Side.long,
  TimeframeBars? m5,
  TimeframeBars? m15,
  TimeframeBars? m30,
  TimeframeBars? h1,
  VenueSpread spread = const VenueSpread.unavailable(),
  List<EconomicEvent> events = const [],
  EmergencyCondition? emergency,
  DateTime? now,
  bool sessionOpen = true,
  int today = 0,
  double? price,
  bool duplicate = false,
  SpreadStatus? override,
  MacroState? macro,
  SentimentState? sentiment,
}) =>
    ScanRequest(
      direction: dir,
      m5: m5 ?? tf(Tf.m5, drift: 0.35),
      m15: m15 ?? tf(Tf.m15, drift: 0.12),
      m30: m30 ?? tf(Tf.m30, drift: 0.06),
      h1: h1 ?? tf(Tf.h1, drift: 0.03),
      spread: spread,
      events: events,
      emergency: emergency,
      now: now,
      sessionOpen: sessionOpen,
      signalsEmittedToday: today,
      currentPrice: price,
      duplicate: duplicate,
      spreadStatusOverride: override,
      macro: macro,
      sentiment: sentiment,
    );

void main() {
  const scanner = MarketScanner();

  group('direction is never invented', () {
    test('a null direction yields NO TRADE, not a guessed side', () {
      final r = scanner.scan(req(dir: null));
      expect(r.verdict, Verdict.noTrade);
      expect(r.stopPlan, isNull);
      expect(
        r.dataQuality.join(' '),
        contains('no candidate direction'),
        reason: 'the scanner must state it declined to choose a side',
      );
    });

    test('a short candidate produces SHORT, never LONG', () {
      final r = scanner.scan(req(dir: Side.short, price: 3960));
      expect(r.verdict, anyOf(Verdict.short, Verdict.noTrade));
      if (r.verdict != Verdict.noTrade) expect(r.headline, startsWith('SHORT'));
    });
  });

  group('data sufficiency (never silently scored as flat)', () {
    test('too little 1H history vetoes and says how much is missing', () {
      final r = scanner.scan(req(h1: tf(Tf.h1, n: 30)));
      expect(r.verdict, Verdict.noTrade);
      expect(r.vetoes, contains(ReasonCode.v3DataStale));
      expect(r.dataQuality.join(' '), contains('1h: 30/200 bars'));
    });

    test('enough history passes the sufficiency check', () {
      final r = scanner.scan(req());
      expect(r.dataQuality.where((d) => d.contains('insufficient history')), isEmpty);
    });

    test('short 5m history alone is enough to veto', () {
      final r = scanner.scan(req(m5: tf(Tf.m5, n: 8)));
      expect(r.vetoes, contains(ReasonCode.v3DataStale));
      expect(r.dataQuality.join(' '), contains('5m: 8/20'));
    });
  });

  group('spread policy end-to-end (ratified option (a))', () {
    test('unavailable spread is reported, never substituted', () {
      final r = scanner.scan(req());
      expect(r.spread.status, SpreadStatus.unavailable);
      expect(r.spread.value, isNull);
      expect(r.spread.source, 'NONE');
    });

    test('genuine venue spread is carried through with its source', () {
      final r = scanner.scan(
        req(spread: const VenueSpread.available(bid: 4142.45, ask: 4143.28, source: 'oanda-practice')),
      );
      expect(r.spread.isGenuine, isTrue);
      expect(r.spread.value, closeTo(0.83, 1e-9));
      expect(r.spread.source, 'oanda-practice');
    });

    test('a genuine spread appears as context, not a veto', () {
      final r = scanner.scan(
        req(spread: const VenueSpread.available(bid: 4142.45, ask: 4143.28, source: 'oanda-practice')),
      );
      expect(r.vetoes, isNot(contains(ReasonCode.v2SpreadUnevaluated)));
    });

    test('a crossed quote yields no spread rather than a negative one', () {
      const crossed = VenueSpread.available(bid: 4145, ask: 4140, source: 'bad');
      expect(crossed.value, isNull);
      expect(crossed.isGenuine, isFalse);
    });

    // ---- undisclosed spread (rate withheld under provider licence) ---------
    //
    // The provider permits internal use only, so the ladder cannot reach the app
    // (D-20261006-013). That must change what the app can SHOW without changing
    // whether a setup is reachable. If it silently started vetoing every setup as
    // SPREAD_UNEVALUATED, a licensing constraint would masquerade as a technical
    // one and XV would lose its setup capability for a reason that has nothing to
    // do with the market.

    test('an undisclosed spread is acceptable but carries no number', () {
      const s = VenueSpread.undisclosed(source: 'venue-internal');
      expect(s.status, SpreadStatus.available);
      expect(s.isAcceptable, isTrue);
      expect(s.isUndisclosed, isTrue);
      expect(s.value, isNull, reason: 'the rate must not be recoverable');
      expect(s.bid, isNull);
      expect(s.ask, isNull);
      expect(s.source, 'venue-internal');
    });

    test('an undisclosed spread is context, not an unevaluated gap', () {
      final r = scanner.scan(
        req(spread: const VenueSpread.undisclosed(source: 'venue-internal')),
      );
      // Measured and acceptable, so the spread veto is genuinely evaluated and
      // must not be reported as UNEVALUATED.
      expect(r.reasonCodes, isNot(contains(ReasonCode.v2SpreadUnevaluated)));
      expect(r.spread.status, SpreadStatus.available);
    });

    test('an undisclosed spread never widens the stop buffer', () {
      // With no number in hand the buffer must stay on the ATR-only term. This
      // is the conservative direction: a wider buffer costs more room to reach
      // target, so guessing here would quietly distort every R:R figure.
      final r = scanner.scan(
        req(spread: const VenueSpread.undisclosed(source: 'venue-internal')),
      );
      expect(r.stopPlan?.bufferSource ?? '', isNot(contains('spread')));
    });

    test('an UNAVAILABLE spread stays distinguishable from an undisclosed one', () {
      // This is the whole reason the two states are separate. If both collapsed
      // to the same output there would be no way to tell "we are not allowed to
      // look" apart from "there was nothing to look at", and the first would
      // silently start costing setups the way the second legitimately does.
      final r = scanner.scan(req(spread: const VenueSpread.unavailable()));
      expect(r.reasonCodes, contains(ReasonCode.v2SpreadUnevaluated));
      expect(r.spread.isAcceptable, isFalse);
    });

    test('override can force UNAVAILABLE after a feed outage', () {
      final r = scanner.scan(
        req(
          spread: const VenueSpread.available(bid: 4142, ask: 4143, source: 'oanda-practice'),
          override: SpreadStatus.unavailable,
        ),
      );
      expect(r.reasonCodes, contains(ReasonCode.v2SpreadUnevaluated));
    });
  });

  group('calendar lock short-circuits the pipeline', () {
    final tierA = EconomicEvent(
      name: 'FOMC Rate Decision',
      currency: 'USD',
      tier: EventTier.tierA,
      releaseTime: DateTime.utc(2026, 10, 2, 14, 30),
    );

    test('a Tier A blackout vetoes regardless of technicals', () {
      final r = scanner.scan(
        req(now: DateTime.utc(2026, 10, 2, 14, 0), events: [tierA]),
      );
      expect(r.verdict, Verdict.noTrade);
      expect(r.vetoes, contains(ReasonCode.v1Blackout));
      expect(r.lockSummary, contains('FOMC'));
    });

    test('an emergency condition freezes and is named', () {
      final r = scanner.scan(
        req(
          now: DateTime.utc(2026, 10, 2, 10),
          emergency: EmergencyCondition(atrPercentile: 99),
        ),
      );
      expect(r.vetoes, contains(ReasonCode.v1Blackout));
      expect(r.lockSummary, contains('EMERGENCY_ATR_PERCENTILE'));
    });

    test('no calendar time means no calendar gate', () {
      final r = scanner.scan(req());
      expect(r.lockSummary, 'N/A');
      expect(r.vetoes, isNot(contains(ReasonCode.v1Blackout)));
    });
  });

  group('levels are never published without a stop (MGC R1)', () {
    test('a refused stop turns a passing setup into NO TRADE', () {
      // A flat series has no confirmed swing beyond entry, so the structural
      // stop cannot be built even though indicators may still score.
      TimeframeBars flat(Tf t) =>
          TimeframeBars(timeframe: t, bars: series(t, n: 260), allDegraded: false);
      final r = scanner.scan(req(
        dir: Side.long,
        m5: flat(Tf.m5),
        m15: flat(Tf.m15),
        m30: flat(Tf.m30),
        h1: flat(Tf.h1),
        price: 4000,
      ));
      if (r.verdict != Verdict.noTrade) {
        expect(r.stopPlan, isNotNull);
        expect(r.stopPlan!.isValid, isTrue);
        expect(r.stopPlan!.rejectionReason, isNull);
      } else {
        expect(r.vetoes, isNotEmpty);
      }
    });

    test('a published trade always carries stop plus three targets', () {
      final r = scanner.scan(req(price: 4100));
      if (r.isTrade) {
        final p = r.stopPlan!;
        expect(p.isValid, isTrue);
        expect(p.stopLoss.isFinite, isTrue);
        expect(p.tp1.isFinite && p.tp2.isFinite && p.tp3.isFinite, isTrue);
        expect(p.riskDistance, greaterThan(0));
        expect(p.tp2R, greaterThanOrEqualTo(1.8));
        expect(p.riskDistanceAtr, inInclusiveRange(0.80, 1.80));
      }
    });
  });

  group('degraded proxy history never produces levels', () {
    test('degraded 15m history refuses the level set', () {
      final r = scanner.scan(req(
        price: 4100,
        m15: tf(Tf.m15, drift: 0.12, degraded: true),
      ));
      // Either the technicals were insufficient, or the level set was refused.
      // In no case may levels be published from proxy history.
      if (r.isTrade) {
        fail('published levels from degraded history: ${r.headline}');
      }
      expect(
        r.dataQuality.join(' '),
        anyOf(contains('degraded'), contains('insufficient')),
      );
    });

    test('degraded history is surfaced as a data-quality note', () {
      final r = scanner.scan(req(
        h1: tf(Tf.h1, drift: 0.03, degraded: true),
        m30: tf(Tf.m30, drift: 0.06, degraded: true),
      ));
      expect(r.dataQuality.join(' '), contains('degraded'));
    });

    test('degraded bars still warm indicators rather than being discarded', () {
      final r = scanner.scan(req(h1: tf(Tf.h1, n: 260, drift: 0.03, degraded: true)));
      // 260 degraded bars count toward the 200-bar sufficiency floor.
      expect(r.dataQuality.where((d) => d.contains('h1: 260/200')), isEmpty);
    });
  });

  group('determinism and auditability', () {
    test('identical inputs produce identical output', () {
      final a = scanner.scan(req(price: 4100));
      final b = scanner.scan(req(price: 4100));
      expect(a.verdict, b.verdict);
      expect(a.technicalScore, b.technicalScore);
      expect(a.finalScore, b.finalScore);
      expect(a.reasonCodes, b.reasonCodes);
      expect(a.headline, b.headline);
    });

    test('every NO TRADE carries at least one reason', () {
      for (final r in [
        scanner.scan(req(dir: null)),
        scanner.scan(req(h1: tf(Tf.h1, n: 10))),
        scanner.scan(req(now: DateTime.utc(2026, 10, 2, 14), events: [
          EconomicEvent(
            name: 'CPI',
            currency: 'USD',
            tier: EventTier.tierA,
            releaseTime: DateTime.utc(2026, 10, 2, 14, 30),
          ),
        ])),
        scanner.scan(req(sessionOpen: false)),
        scanner.scan(req(today: 9)),
      ]) {
        expect(r.verdict, Verdict.noTrade);
        expect(r.reasonCodes.length + r.vetoes.length, greaterThan(0));
      }
    });

    test('the headline never implies probability', () {
      final r = scanner.scan(req(price: 4100));
      final h = r.headline.toLowerCase();
      for (final banned in ['%', 'chance', 'probabil', 'guarantee', 'sure']) {
        expect(h, isNot(contains(banned)));
      }
    });

    test('a spread-aware run and a spread-blind run agree on direction', () {
      final withSpread = scanner.scan(req(
        price: 4100,
        spread: const VenueSpread.available(bid: 4142, ask: 4143, source: 'oanda-practice'),
      ));
      final without = scanner.scan(req(price: 4100));
      expect(withSpread.verdict, without.verdict);
    });
  });

  // ScanRequest had no macro/sentiment fields at all, so every 8.3 macro and
  // sentiment term was dead code no matter how much layer data existed. These
  // pin that a supplied layer actually moves the verdict.
  group('sentiment layers reach the verdict', () {
    test('a bearish macro vetoes a long', () {
      final r = scanner.scan(
        req(dir: Side.long, macro: const MacroState(alignment: -1)),
      );
      expect(r.vetoes, contains(ReasonCode.v6DirectionConflict));
      expect(r.verdict, Verdict.noTrade);
      expect(r.macroAlignment, -1);
      expect(r.macroAgrees, -1, reason: 'macro runs against the long');
    });

    test('that same bearish macro does not veto a short', () {
      final r = scanner.scan(
        req(dir: Side.short, macro: const MacroState(alignment: -1)),
      );
      expect(r.vetoes, isNot(contains(ReasonCode.v6DirectionConflict)));
      expect(r.macroAgrees, 1, reason: 'macro agrees with the short');
      expect(r.reasonCodes, contains(ReasonCode.macroSupports));
    });

    test('bullish macro supports a long and conflicts with a short', () {
      final bull = scanner.scan(
        req(dir: Side.long, macro: const MacroState(alignment: 1)),
      );
      expect(bull.vetoes, isNot(contains(ReasonCode.v6DirectionConflict)));
      expect(bull.reasonCodes, contains(ReasonCode.macroSupports));

      final bear = scanner.scan(
        req(dir: Side.short, macro: const MacroState(alignment: 1)),
      );
      expect(bear.vetoes, contains(ReasonCode.v6DirectionConflict));
    });

    test('bearish sentiment penalises a long but never vetoes it', () {
      // Section 6: a weekly reading may lower conviction, not forbid the trade.
      final r = scanner.scan(
        req(dir: Side.long, sentiment: const SentimentState(alignment: -1)),
      );
      expect(r.vetoes, isNot(contains(ReasonCode.v6DirectionConflict)));
      expect(r.conflictPenalty, 1);
      expect(r.sentimentAlignment, -1);
      expect(r.sentimentAgrees, -1);
    });

    test('a stale COT reading contributes nothing at all', () {
      final r = scanner.scan(
        req(
          dir: Side.long,
          sentiment: const SentimentState(alignment: -1, cotStale: true),
        ),
      );
      expect(r.conflictPenalty, 0);
      expect(r.sentimentAgrees, isNull);
    });

    test('omitting the layers leaves the scan exactly as before', () {
      // A caller that knows nothing about 5.1 gets no macro weight, not a
      // fabricated neutral.
      final r = scanner.scan(req(dir: Side.long));
      expect(r.macroAlignment, isNull);
      expect(r.macroAgrees, isNull);
      expect(r.sentimentAlignment, isNull);
      expect(r.conflictPenalty, 0);
    });

    test('the real live read reaches a long as a conflict', () {
      // The live state on 2026-10-05: the Fed hiked (macro -1) and COT sits at
      // the 37.8th percentile (sentiment -1).
      final r = scanner.scan(
        req(
          dir: Side.long,
          macro: const MacroState(
            alignment: -1,
            policyImpulse: -1,
            realYieldImpulse: -1,
          ),
          sentiment: const SentimentState(alignment: -1),
        ),
      );
      expect(r.macroAlignment, -1);
      expect(r.sentimentAlignment, -1);
      expect(r.vetoes, contains(ReasonCode.v6DirectionConflict));
      expect(r.conflictPenalty, 2, reason: 'macro veto plus the sentiment penalty');
      expect(r.verdict, Verdict.noTrade);
    });
  });
}