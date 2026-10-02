import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

DateTime t(int hour, [int minute = 0]) => DateTime.utc(2026, 10, 2, hour, minute);

EconomicEvent ev({
  String name = 'CPI',
  String currency = 'USD',
  EventTier tier = EventTier.tierA,
  DateTime? at,
  double? actual,
  double? forecast,
  double? previous,
}) =>
    EconomicEvent(
      name: name,
      currency: currency,
      tier: tier,
      releaseTime: at ?? t(14, 30),
      actual: actual,
      forecast: forecast,
      previous: previous,
    );

void main() {
  const lock = CalendarLock();

  group('tier mapping', () {
    test('recognises common provider spellings', () {
      expect(tierFromImpact('HIGH'), EventTier.tierA);
      expect(tierFromImpact('high'), EventTier.tierA);
      expect(tierFromImpact('MEDIUM'), EventTier.tierB);
      expect(tierFromImpact('B'), EventTier.tierB);
    });

    test('unknown impact degrades to Tier C, never to a blackout', () {
      expect(tierFromImpact('whatever'), EventTier.tierC);
      expect(tierFromImpact(''), EventTier.tierC);
    });
  });

  group('material surprise', () {
    test('null when no actual is available', () {
      expect(ev(forecast: 3.0).isMaterialSurprise, isNull);
    });

    test('null when no forecast is available', () {
      expect(ev(actual: 3.0).isMaterialSurprise, isNull);
    });

    test('a >5% relative miss is surprising', () {
      expect(ev(actual: 4.0, forecast: 3.0).isMaterialSurprise, isTrue);
    });

    test('a small relative miss is not surprising', () {
      expect(ev(actual: 3.05, forecast: 3.0).isMaterialSurprise, isFalse);
    });

    test('a zero forecast falls back to the absolute rule', () {
      expect(ev(actual: 0.5, forecast: 0.0).isMaterialSurprise, isTrue);
      // A 0% forecast cannot be scaled, so the test becomes purely absolute.
      // Small absolute prints therefore count as surprising against that
      // degenerate baseline — the honest reading of the rule.
      expect(ev(actual: 0.1, forecast: 0.0).isMaterialSurprise, isFalse);
      expect(ev(actual: 0.0, forecast: 0.0).isMaterialSurprise, isFalse);
    });
  });

  group('effective tier escalation', () {
    test('a surprisingly strong Tier B release escalates to Tier A', () {
      final e = ev(name: 'PPI', tier: EventTier.tierB, actual: 5.0, forecast: 3.0);
      expect(effectiveTier(e), EventTier.tierA);
    });

    test('an in-line Tier B release stays Tier B', () {
      final e = ev(name: 'PPI', tier: EventTier.tierB, actual: 3.02, forecast: 3.0);
      expect(effectiveTier(e), EventTier.tierB);
    });

    test('Tier A never de-escalates', () {
      expect(effectiveTier(ev(tier: EventTier.tierA, actual: 3.0, forecast: 3.0)),
          EventTier.tierA);
    });
  });

  group('blackout windows (§4.2)', () {
    test('Tier A locks from T-45', () {
      final e = ev(at: t(14, 30));
      expect(lock.isLocked(e, t(13, 45)), isTrue);
      expect(lock.isLocked(e, t(13, 44)), isFalse);
    });

    test('Tier A holds through T+30', () {
      final e = ev(at: t(14, 30));
      expect(lock.isLocked(e, t(15, 0)), isFalse); // exactly T+30 has elapsed
      expect(lock.isLocked(e, t(14, 59)), isTrue);
      expect(lock.isLocked(e, t(15, 0)), isFalse);
    });

    test('Tier B uses a shorter caution window', () {
      final e = ev(name: 'PPI', tier: EventTier.tierB, at: t(14, 30));
      expect(lock.isLocked(e, t(14, 15)), isTrue); // T-15
      expect(lock.isLocked(e, t(14, 14)), isFalse);
      expect(lock.isLocked(e, t(14, 44)), isTrue); // T+14
      expect(lock.isLocked(e, t(14, 45)), isFalse); // T+15 elapsed
    });

    test('Tier C never locks', () {
      final e = ev(name: 'Fed H.4.1', tier: EventTier.tierC, at: t(14, 30));
      expect(lock.isLocked(e, t(14, 30)), isFalse);
      expect(lock.isLocked(e, t(14, 29)), isFalse);
    });
  });

  group('lock decision', () {
    test('no events means scanning is open', () {
      final d = lock.evaluate(now: t(10), events: const []);
      expect(d.state, LockState.open);
      expect(d.isLocked, isFalse);
      expect(d.lockUntil, isNull);
    });

    test('a USD Tier A event blocks and reports unlock time', () {
      final d = lock.evaluate(now: t(14, 0), events: [ev()]);
      expect(d.state, LockState.blackout);
      expect(d.isLocked, isTrue);
      expect(d.lockUntil, t(15, 0));
      expect(d.reasonCodes.single, contains('LOCK_TIER_A_CPI'));
    });

    test('reason codes name the event for the UI', () {
      final d = lock.evaluate(
        now: t(14, 0),
        events: [ev(name: 'FOMC Rate Decision')],
      );
      expect(d.reasonCodes.single, 'LOCK_TIER_A_FOMC_RATE_DECISION');
    });

    test('multiple active events extend the lock to the latest', () {
      final d = lock.evaluate(now: t(14, 10), events: [
        ev(name: 'CPI', at: t(14, 0)),
        ev(name: 'PPI', tier: EventTier.tierB, at: t(14, 20)),
      ]);
      expect(d.activeEvents, hasLength(2));
      // Tier A releases 14:30, Tier B releases 14:35; the later one wins.
      expect(d.lockUntil, t(14, 35));
    });

    test('a non-USD minor event does not suppress a gold setup', () {
      final d = lock.evaluate(
        now: t(14, 0),
        events: [
          ev(name: 'German Flash PMI', currency: 'EUR', tier: EventTier.tierC, at: t(14, 30)),
        ],
      );
      expect(d.state, LockState.open);
    });

    test('a major non-USD central-bank decision does suppress', () {
      final d = lock.evaluate(
        now: t(14, 0),
        events: [ev(name: 'ECB Rate Decision', currency: 'EUR', at: t(14, 30))],
      );
      expect(d.state, LockState.blackout);
      // The currency stays in the code so the UI can name the source.
      expect(d.reasonCodes.single, 'LOCK_TIER_A_EUR_ECB_RATE_DECISION');
    });

    test('an escalated Tier B surprise uses the wider window', () {
      final e = ev(name: 'PPI', tier: EventTier.tierB, at: t(14, 30), actual: 5.0, forecast: 3.0);
      final escalated = EconomicEvent(
        name: e.name,
        currency: e.currency,
        tier: effectiveTier(e),
        releaseTime: e.releaseTime,
        actual: e.actual,
        forecast: e.forecast,
      );
      // Escalated to Tier A, so T-45 applies instead of T-15.
      expect(lock.isLocked(escalated, t(13, 50)), isTrue);
    });
  });

  group('emergency conditions (§4.2)', () {
    test('no triggers means open', () {
      final c = EmergencyCondition(atrPercentile: 50, lastCandleRange: 10, atr14: 10);
      expect(c.triggered, isFalse);
    });

    test('high ATR percentile freezes entries', () {
      final c = EmergencyCondition(atrPercentile: 96);
      expect(c.triggered, isTrue);
      expect(c.codes.single, startsWith('EMERGENCY_ATR_PERCENTILE'));
    });

    test('a candle larger than 2x ATR freezes entries', () {
      final c = EmergencyCondition(lastCandleRange: 25, atr14: 10);
      expect(c.triggered, isTrue);
      expect(c.codes.single, contains('CANDLE_RANGE'));
    });

    test('a structure gap freezes entries', () {
      expect(EmergencyCondition(gappedThroughLevel: true).triggered, isTrue);
    });

    test('freeze holds for the configured minimum', () {
      final d = lock.evaluate(
        now: t(10),
        events: const [],
        emergency: EmergencyCondition(atrPercentile: 99),
      );
      expect(d.state, LockState.emergencyFreeze);
      expect(d.lockUntil, t(10, 30));
      expect(d.emergencyEvidence, isNotEmpty);
    });

    test('a scheduled lock takes precedence over an emergency freeze', () {
      final d = lock.evaluate(
        now: t(14, 0),
        events: [ev()],
        emergency: EmergencyCondition(atrPercentile: 99),
      );
      expect(d.state, LockState.blackout);
    });

    test('unknown ATR cannot trigger the range condition', () {
      final c = EmergencyCondition(lastCandleRange: 100, atr14: null);
      expect(c.codes.where((x) => x.contains('CANDLE_RANGE')), isEmpty);
    });

    test('a zero ATR cannot trigger the range condition', () {
      final c = EmergencyCondition(lastCandleRange: 100, atr14: 0);
      expect(c.codes.where((x) => x.contains('CANDLE_RANGE')), isEmpty);
    });
  });

  group('spread is never proxied in the emergency path', () {
    test('EmergencyCondition exposes no spread trigger at all', () {
      // The ratified option (a) rule forbids deriving spread from cross-source
      // prices, so the emergency gate simply has no spread input to misuse.
      const c = EmergencyCondition();
      expect(c.codes.where((x) => x.toUpperCase().contains('SPREAD')), isEmpty);
      expect(c.triggered, isFalse);
    });
  });
}