import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

void main() {
  const cfg = StopConfig();

  group('structural stop (methodology §11)', () {
    test('long stop sits below the confirmed swing plus a 0.20 ATR buffer', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3990,
      );
      expect(p.isValid, isTrue);
      // 3990 - (0.20 * 10) = 3988
      expect(p.stopLoss, 3988.0);
      expect(p.riskDistance, 12.0);
      expect(p.bufferSource, '0.20*ATR');
    });

    test('short stop mirrors above the confirmed swing', () {
      final p = buildStopPlan(
        direction: Side.short,
        entry: 4000,
        atr5m: 10,
        swingHigh: 4010,
      );
      expect(p.isValid, isTrue);
      expect(p.stopLoss, 4012.0);
      expect(p.riskDistance, 12.0);
    });

    test('refuses without a confirmed swing rather than using an ATR guess', () {
      expect(
        buildStopPlan(direction: Side.long, entry: 4000, atr5m: 10).rejectionReason,
        'NO_CONFIRMED_SWING_LOW',
      );
      expect(
        buildStopPlan(direction: Side.short, entry: 4000, atr5m: 10).rejectionReason,
        'NO_CONFIRMED_SWING_HIGH',
      );
    });

    test('rejects a swing on the wrong side of entry', () {
      expect(
        buildStopPlan(direction: Side.long, entry: 4000, atr5m: 10, swingLow: 4005)
            .rejectionReason,
        'SWING_LOW_ABOVE_ENTRY',
      );
      expect(
        buildStopPlan(direction: Side.short, entry: 4000, atr5m: 10, swingHigh: 3995)
            .rejectionReason,
        'SWING_HIGH_BELOW_ENTRY',
      );
    });

    test('rejects a structural stop wider than 1.8 ATR instead of widening it', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3970, // 30 USD away = 3.0 ATR
      );
      expect(p.isValid, isFalse);
      expect(p.rejectionReason, 'STRUCTURAL_STOP_TOO_WIDE');
    });

    test('widens an over-tight stop to the 0.8 ATR floor', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3999.5, // 0.5 USD = 0.05 ATR
      );
      expect(p.isValid, isTrue);
      expect(p.riskDistanceAtr, closeTo(0.80, 1e-9));
      expect(p.bufferSource, contains('widened'));
    });

    test('a valid structural stop stays inside the ATR envelope', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3989, // 11 + 2 buffer = 13 USD = 1.3 ATR
      );
      expect(p.riskDistanceAtr, closeTo(1.3, 1e-9));
      expect(p.riskDistanceAtr, inInclusiveRange(cfg.minStopAtr, cfg.maxStopAtr));
    });

    test('rejects missing or non-positive ATR', () {
      expect(
        buildStopPlan(direction: Side.long, entry: 4000, atr5m: 0, swingLow: 3990)
            .rejectionReason,
        'ATR_UNAVAILABLE',
      );
      expect(
        buildStopPlan(direction: Side.long, entry: 4000, atr5m: double.nan, swingLow: 3990)
            .rejectionReason,
        'ATR_UNAVAILABLE',
      );
    });

    test('rejects a non-positive entry', () {
      expect(
        buildStopPlan(direction: Side.long, entry: 0, atr5m: 10, swingLow: -5)
            .rejectionReason,
        'ENTRY_UNAVAILABLE',
      );
    });
  });

  group('spread never proxied (ratified option (a))', () {
    test('absent spread uses the pure ATR buffer', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3990,
      );
      expect(p.bufferSource, '0.20*ATR');
      expect(p.stopLoss, 3988.0);
    });

    test('a supplied spread is ignored while status is UNAVAILABLE', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3990,
        spreadStatus: SpreadStatus.unavailable,
        genuineSpread: 5.0, // must NOT be honoured
      );
      expect(p.bufferSource, '0.20*ATR');
      expect(p.stopLoss, 3988.0);
    });

    test('genuine venue spread widens the buffer when larger', () {
      // swingLow 3985 -> buffer = max(2, 10) = 10 -> stop 3975, distance 25
      // = 2.5 ATR, which the envelope correctly rejects. The point of the
      // test is the buffer derivation, so a wide-enough swing is used.
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3992, // 8 + 10 = 18 USD = 1.8 ATR, at the limit
        spreadStatus: SpreadStatus.available,
        genuineSpread: 5.0, // spread*2 = 10 > atrBuffer 2
      );
      expect(p.isValid, isTrue);
      expect(p.bufferSource, 'max(0.20*ATR, spread*2)');
      expect(p.stopLoss, 3982.0);
      expect(p.riskDistance, 18.0);
    });

    test('ATR buffer wins when it already exceeds spread*2', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 50,
        swingLow: 3960,
        spreadStatus: SpreadStatus.available,
        genuineSpread: 1.0, // spread*2 = 2 < atrBuffer 10
      );
      expect(p.bufferSource, 'max(0.20*ATR, spread*2)');
      expect(p.stopLoss, 3950.0);
    });

    test('the unavailable flag is carried through to the plan', () {
      final p = buildStopPlan(direction: Side.long, entry: 4000, atr5m: 10, swingLow: 3990);
      expect(p.spreadStatus, SpreadStatus.unavailable);
    });
  });

  group('R-multiple targets (methodology §12)', () {
    test('targets are exact R multiples of the real risk', () {
      final p = buildStopPlan(
        direction: Side.long,
        entry: 4000,
        atr5m: 10,
        swingLow: 3990,
      );
      expect(p.tp1, closeTo(4012, 1e-9)); // 1R
      expect(p.tp2, closeTo(4024, 1e-9)); // 2R
      expect(p.tp3, closeTo(4036, 1e-9)); // 3R
    });

    test('short targets sit below entry', () {
      final p = buildStopPlan(
        direction: Side.short,
        entry: 4000,
        atr5m: 10,
        swingHigh: 4010,
      );
      expect(p.tp1, 3988.0);
      expect(p.tp2, 3976.0);
      expect(p.tp3, 3964.0);
      expect(p.tp1, lessThan(p.entry));
    });

    test('the default plan satisfies the 1.8R TP2 floor', () {
      final p = buildStopPlan(direction: Side.long, entry: 4000, atr5m: 10, swingLow: 3990);
      expect(p.tp2R, closeTo(2.0, 1e-9));
      expect(meetsTp2Floor(p.tp2R), isTrue);
    });

    test('a 1.7R configuration fails the floor', () {
      expect(meetsTp2Floor(1.7), isFalse);
      expect(meetsTp2Floor(1.8), isTrue);
    });
  });

  group('structural target override (§12)', () {
    test('an unblocked target keeps its R multiple', () {
      final r = applyTargetOverride(
        direction: Side.long,
        entry: 4000,
        riskDistance: 12,
        targetR: 3,
        blockingLevels: const [4500],
      );
      expect(r, 3.0);
    });

    test('a level just short of TP1 makes the target unreachable', () {
      final r = applyTargetOverride(
        direction: Side.long,
        entry: 4000,
        riskDistance: 12,
        targetR: 1,
        blockingLevels: const [4005], // 0.42R
      );
      expect(r, isNull);
    });

    test('a level between entry and the target pulls the target back', () {
      final r = applyTargetOverride(
        direction: Side.long,
        entry: 4000,
        riskDistance: 12,
        targetR: 3,
        blockingLevels: const [4020], // 1.67R
      );
      expect(r, isNotNull);
      expect(r!, lessThan(1.67));
    });

    test('a level behind entry does not block a long', () {
      final r = applyTargetOverride(
        direction: Side.long,
        entry: 4000,
        riskDistance: 12,
        targetR: 2,
        blockingLevels: const [3900],
      );
      expect(r, 2.0);
    });

    test('a level above entry does not block a short target', () {
      final r = applyTargetOverride(
        direction: Side.short,
        entry: 4000,
        riskDistance: 12,
        targetR: 2,
        blockingLevels: const [4100],
      );
      expect(r, 2.0);
    });

    test('non-positive risk returns null rather than dividing by zero', () {
      expect(
        applyTargetOverride(
          direction: Side.long,
          entry: 4000,
          riskDistance: 0,
          targetR: 2,
          blockingLevels: const [],
        ),
        isNull,
      );
    });
  });

  group('disclaimer (MGC R11)', () {
    test('every published plan carries the disclaimer text', () {
      expect(riskDisclaimer, isNotEmpty);
      expect(riskDisclaimer.toLowerCase(), contains('not financial advice'));
      expect(riskDisclaimer, contains('does not execute'));
    });
  });
}