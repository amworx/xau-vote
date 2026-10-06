import 'package:flutter_test/flutter_test.dart';
import 'package:xau_core/xau_core.dart';

import 'package:xauvote/data/outcome_recorder.dart';

/// Tests the mapping from an engine decision to the recorder payload.
///
/// [OutcomeRecorder.buildPayload] is pure precisely so this can be tested
/// without a network. Everything asserted here is something the SERVER cannot
/// recover on its own: the decision key, the spread status the engine actually
/// used, and the forced-trade construction. If any of these drift, the record
/// silently stops describing the runs that produced it.
void main() {
  const t = Thresholds();
  const sc = StopConfig();

  DateTime base = DateTime.utc(2026, 10, 6, 9);

  VenueSpread genuine() => const VenueSpread(
        status: SpreadStatus.available,
        bid: 4150.90,
        ask: 4151.40,
        source: 'oanda',
      );

  VenueSpread unavailable() =>
      const VenueSpread(status: SpreadStatus.unavailable, source: 'NONE');

  Candle candle(int minutesAgo, {bool closed = true}) => Candle(
        openTime: base.subtract(Duration(minutes: minutesAgo)),
        open: 4150.0,
        high: 4152.0,
        low: 4149.0,
        close: 4151.15,
        isClosed: closed,
      );

  TimeframeBars m15(List<Candle> bars) =>
      TimeframeBars(timeframe: Tf.m15, bars: bars, allDegraded: false);

  StopPlan plan() => const StopPlan(
        entry: 4151.15,
        stopLoss: 4149.15,
        tp1: 4153.15,
        tp2: 4155.15,
        tp3: 4157.15,
        riskDistance: 2.0,
        riskDistanceAtr: 1.0,
        riskPerUnit: 2.0,
        spreadStatus: SpreadStatus.available,
        bufferSource: 'SWING',
      );

  ScanResult trade({
    Verdict verdict = Verdict.long,
    Grade grade = Grade.a,
    StopPlan? stop,
    VenueSpread? spread,
    double? atr5m = 2.0,
  }) =>
      ScanResult(
        verdict: verdict,
        grade: grade,
        reasonCodes: const [ReasonCode.v12LowConfluence],
        vetoes: const [],
        technicalScore: 10,
        finalScore: 11.0,
        macroAlignment: 1,
        macroAgrees: 1,
        sentimentAlignment: null,
        sentimentAgrees: null,
        conflictPenalty: 0,
        spread: spread ?? genuine(),
        dataQuality: const ['INSUFFICIENT_BARS:1h:120/200'],
        lockSummary: '',
        stopPlan: stop,
        atr5m: atr5m,
      );

  Map<String, Object?> build(
    ScanResult scan, {
    DateTime? decidedAt,
    Side? direction,
    double? price = 4151.15,
    SpreadStatus effective = SpreadStatus.available,
  }) =>
      OutcomeRecorder.buildPayload(
        scan: scan,
        decidedAt: decidedAt ?? base,
        thresholds: t,
        stopConfig: sc,
        candidateDirection: direction,
        currentPrice: price,
        effectiveSpreadStatus: effective,
        effectiveSpreadNote: 'venue spread 0.50 USD',
      )!;

  group('decisionTimeFor', () {
    test('attributes a decision to the bar CLOSE, not the open', () {
      // A bar opening at 09:00 closes at 09:15. Attributing the decision to
      // 09:00 would let the row claim knowledge 15 minutes before it existed.
      final when = OutcomeRecorder.decisionTimeFor(
        m15([candle(0)]),
      );
      expect(when, DateTime.utc(2026, 10, 6, 9, 15));
    });

    test('ignores the still-forming bar', () {
      final bars = m15([candle(30), candle(15), candle(0, closed: false)]);
      // The forming bar opened at 09:00 and would close at 09:15. Only the
      // closed 08:45 bar counts, which closes at 09:00.
      expect(OutcomeRecorder.decisionTimeFor(bars), DateTime.utc(2026, 10, 6, 9));
    });

    test('is null with no closed bars', () {
      expect(OutcomeRecorder.decisionTimeFor(m15([])), isNull);
      expect(
        OutcomeRecorder.decisionTimeFor(m15([candle(0, closed: false)])),
        isNull,
      );
    });
  });

  group('trade payloads', () {
    test('carry the levels needed to score them', () {
      final p = build(trade(stop: plan()));
      expect(p['verdict'], 'LONG');
      expect(p['side'], 'LONG');
      expect(p['entry'], 4151.15);
      expect(p['stopLoss'], 4149.15);
      expect(p['tp1'], 4153.15);
      expect(p['riskDistance'], 2.0);
      expect(p['riskDistanceAtr'], 1.0);
    });

    test('map a short verdict to SHORT', () {
      final p = build(trade(verdict: Verdict.short, stop: plan()));
      expect(p['verdict'], 'SHORT');
      expect(p['side'], 'SHORT');
    });

    test('map every grade to its database spelling', () {
      expect(build(trade(grade: Grade.aPlus, stop: plan()))['grade'], 'A_PLUS');
      expect(build(trade(grade: Grade.a, stop: plan()))['grade'], 'A');
      expect(build(trade(grade: Grade.b, stop: plan()))['grade'], 'B');
      expect(build(trade(grade: Grade.insufficient, stop: plan()))['grade'], 'INSUFFICIENT');
    });

    test('a trade with no usable stop plan is not submitted at all', () {
      // Recording a directional decision with no risk distance would create a row
      // that can never be scored, which is a silent gap in the denominator.
      expect(
        OutcomeRecorder.buildPayload(
          scan: trade(stop: null),
          decidedAt: base,
          thresholds: t,
          stopConfig: sc,
          candidateDirection: Side.long,
          currentPrice: 4151.15,
          effectiveSpreadStatus: SpreadStatus.available,
          effectiveSpreadNote: '',
        ),
        isNull,
      );
    });
  });

  group('decision keys', () {
    test('differ when the direction flips within one bar', () {
      // ignoreDuplicates on decision_key means a collision would silently drop
      // the second decision rather than record both.
      final long = build(trade(verdict: Verdict.long, stop: plan()));
      final short = build(trade(verdict: Verdict.short, stop: plan()));
      expect(long['decisionKey'], isNot(short['decisionKey']));
    });

    test('are stable for the same bar and direction', () {
      final a = build(trade(stop: plan()));
      final b = build(trade(stop: plan()));
      expect(a['decisionKey'], b['decisionKey']);
    });

    test('carry the bar instant and the side', () {
      final p = build(trade(stop: plan()));
      expect(p['decisionKey'], contains('2026-10-06T09:00:00.000Z'));
      expect(p['decisionKey'], endsWith(':LONG'));
    });
  });

  group('abstentions', () {
    test('are recorded with no levels', () {
      final p = build(trade(verdict: Verdict.noTrade, stop: null));
      expect(p['verdict'], 'NO_TRADE');
      expect(p['side'], 'NO_TRADE');
      expect(p.containsKey('entry'), isFalse);
      expect(p.containsKey('tp1'), isFalse);
      expect(p.containsKey('riskDistance'), isFalse);
    });

    test('carry a forced counterfactual when a direction is known', () {
      final p = build(
        trade(verdict: Verdict.noTrade, stop: null),
        direction: Side.long,
      );
      final cf = p['counterfactual']! as Map<String, Object?>;
      expect(cf['side'], 'FORCED_LONG');
      expect(cf['entry'], 4151.15);
      // Pre-registered construction: 1xATR5m risk and exactly 1R.
      expect(cf['riskDistance'], 2.0);
    });

    test('mirror the direction for a short lean', () {
      final p = build(
        trade(verdict: Verdict.noTrade, stop: null),
        direction: Side.short,
      );
      expect((p['counterfactual']! as Map<String, Object?>)['side'], 'FORCED_SHORT');
    });

    test('omit the counterfactual when there is no candidate direction', () {
      // Inventing a side to satisfy the benchmark would manufacture the very
      // comparison the benchmark exists to make.
      final p = build(
        trade(verdict: Verdict.noTrade, stop: null),
        direction: null,
      );
      expect(p.containsKey('counterfactual'), isFalse);
    });

    test('omit the counterfactual when ATR is unmeasurable', () {
      final p = build(
        trade(verdict: Verdict.noTrade, stop: null, atr5m: null),
        direction: Side.long,
      );
      expect(p.containsKey('counterfactual'), isFalse);
    });

    test('omit the counterfactual when there is no price', () {
      final p = build(
        trade(verdict: Verdict.noTrade, stop: null),
        direction: Side.long,
        price: null,
      );
      expect(p.containsKey('counterfactual'), isFalse);
    });
  });

  group('spread accounting', () {
    test('reports the EFFECTIVE status, not the raw measurement', () {
      // This is the subtle one. A stale-but-genuine spread was vetoed by the
      // engine as unavailable. If the payload reported it as available, the
      // recorder would subtract a spread cost the engine never saw, making every
      // result look worse than the run that produced it.
      final p = build(
        trade(verdict: Verdict.noTrade, stop: null, spread: genuine()),
        effective: SpreadStatus.unavailable,
      );
      expect(p['spreadStatus'], 'unavailable');
      // The measurement is still reported, so the gap stays auditable.
      expect(p['spreadValue'], isNotNull);
    });

    test('reports available when the engine accepted it', () {
      final p = build(trade(stop: plan()));
      expect(p['spreadStatus'], 'available');
      expect(p['spreadValue'], 4151.40 - 4150.90);
    });

    test('a genuinely absent spread sends no value to subtract', () {
      final p = build(
        trade(stop: plan(), spread: unavailable()),
      );
      expect(p['spreadValue'], isNull);
    });
  });

  group('parameter verification', () {
    test('reports the values the engine actually ran with', () {
      final params = build(trade(stop: plan()))['clientParameters']! as Map<String, double>;
      expect(params['minTechnical'], 8.0);
      expect(params['minFinal'], 9.0);
      expect(params['tp2FloorR'], 1.8);
      expect(params['atrBufferMultiple'], 0.20);
      expect(params['minStopAtr'], 0.80);
      expect(params['maxStopAtr'], 1.80);
      expect(params['tp1R'], 1.0);
      expect(params['tp2R'], 2.0);
      expect(params['tp3R'], 3.0);
    });

    test('sends every key the server verifies', () {
      // The server compares against its own canonical set; a missing key is
      // treated as a mismatch and VOIDs the row.
      final params = build(trade(stop: plan()))['clientParameters']! as Map<String, double>;
      expect(params.keys, hasLength(20));
    });
  });

  group('reason codes', () {
    test('are sent by name so the record is readable later', () {
      final p = build(trade(verdict: Verdict.noTrade, stop: null));
      expect(p['reasonCodes'], contains('v12LowConfluence'));
    });
  });
}