// Confirmation tests: ready needs zone entry, confirmed needs a structure
// flag, SL breach invalidates from any pre-active state (and the shared
// breach/TP helpers behave direction-aware with strict-beyond semantics).
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xau_lifecycle/xau_lifecycle.dart';

final _now = DateTime.utc(2026, 9, 29, 12);

ConsensusSignal _longSignal() => ConsensusSignal(
      id: 'sig-long',
      direction: Direction.long,
      strength: 80,
      entryLow: 4275,
      entryHigh: 4280,
      stopLoss: 4263,
      tp1: 4296,
      tp2: 4317,
      createdAt: _now,
    );

ConsensusSignal _shortSignal() => ConsensusSignal(
      id: 'sig-short',
      direction: Direction.short,
      strength: 80,
      entryLow: 4285,
      entryHigh: 4290,
      stopLoss: 4305,
      tp1: 4260,
      createdAt: _now,
    );

void main() {
  group('LONG: developing → ready', () {
    test('price entering the zone (inclusive edges) becomes ready', () {
      final sig = _longSignal();
      const none = FiveMinuteStructure();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4277,
          structure: none,
          current: SignalStatus.developing,
        ),
        SignalStatus.ready,
      );
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4275,
          structure: none,
          current: SignalStatus.developing,
        ),
        SignalStatus.ready,
      );
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4280,
          structure: none,
          current: SignalStatus.developing,
        ),
        SignalStatus.ready,
      );
    });

    test('price outside the zone stays developing', () {
      final sig = _longSignal();
      const none = FiveMinuteStructure();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4270,
          structure: none,
          current: SignalStatus.developing,
        ),
        SignalStatus.developing,
      );
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4290,
          structure: none,
          current: SignalStatus.developing,
        ),
        SignalStatus.developing,
      );
    });
  });

  group('LONG: ready → confirmed requires a structure flag', () {
    test('each single flag confirms while price holds the zone', () {
      final sig = _longSignal();
      for (final structure in const [
        FiveMinuteStructure(breakoutRetest: true),
        FiveMinuteStructure(rejection: true),
        FiveMinuteStructure(momentum: true),
      ]) {
        expect(
          ConfirmationEvaluator.evaluate(
            signal: sig,
            price: 4277,
            structure: structure,
            current: SignalStatus.ready,
          ),
          SignalStatus.confirmed,
        );
      }
    });

    test('no flags stays ready; zone exit without breach stays ready', () {
      final sig = _longSignal();
      const none = FiveMinuteStructure();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4277,
          structure: none,
          current: SignalStatus.ready,
        ),
        SignalStatus.ready,
      );
      // Sticky: leaving the zone without breaching SL does not demote.
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4290,
          structure: const FiveMinuteStructure(momentum: true),
          current: SignalStatus.ready,
        ),
        SignalStatus.ready,
      );
    });

    test('confirmed stage holds (promotion to active is lifecycle work)',
        () {
      final sig = _longSignal();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4277,
          structure: const FiveMinuteStructure(),
          current: SignalStatus.confirmed,
        ),
        SignalStatus.confirmed,
      );
    });
  });

  group('invalidation: SL breach from any pre-active state', () {
    test('LONG breached strictly below SL, print on SL is safe', () {
      final sig = _longSignal();
      const flags = FiveMinuteStructure(momentum: true);
      for (final current in [
        SignalStatus.developing,
        SignalStatus.ready,
        SignalStatus.confirmed,
      ]) {
        expect(
          ConfirmationEvaluator.evaluate(
            signal: sig,
            price: 4262.5,
            structure: flags,
            current: current,
          ),
          SignalStatus.invalidated,
          reason: '$current must invalidate below SL',
        );
        // Exactly on SL is not beyond: normal rules apply.
        final onSl = ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4263,
          structure: const FiveMinuteStructure(),
          current: current,
        );
        expect(onSl, isNot(SignalStatus.invalidated));
      }
      expect(ConfirmationEvaluator.isBreached(sig, 4263), isFalse);
      expect(ConfirmationEvaluator.isBreached(sig, 4262.99), isTrue);
    });

    test('SHORT mirror: breached strictly above SL', () {
      final sig = _shortSignal();
      const none = FiveMinuteStructure();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4287,
          structure: none,
          current: SignalStatus.developing,
        ),
        SignalStatus.ready,
      );
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4310,
          structure: none,
          current: SignalStatus.ready,
        ),
        SignalStatus.invalidated,
      );
      expect(ConfirmationEvaluator.isBreached(sig, 4305), isFalse);
      expect(ConfirmationEvaluator.isBreached(sig, 4305.01), isTrue);
    });

    test('invalidated is sticky', () {
      final sig = _longSignal();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4277,
          structure: const FiveMinuteStructure(momentum: true),
          current: SignalStatus.invalidated,
        ),
        SignalStatus.invalidated,
      );
    });
  });

  group('take-profit helper', () {
    test('direction-aware touch semantics; null targets never hit', () {
      final long = _longSignal();
      expect(ConfirmationEvaluator.isTakeProfitHit(long, 1, 4295.99), isFalse);
      expect(ConfirmationEvaluator.isTakeProfitHit(long, 1, 4296), isTrue);
      expect(ConfirmationEvaluator.isTakeProfitHit(long, 3, 9999), isFalse);

      final short = _shortSignal();
      expect(ConfirmationEvaluator.isTakeProfitHit(short, 1, 4260.01), isFalse);
      expect(ConfirmationEvaluator.isTakeProfitHit(short, 1, 4260), isTrue);
    });

    test('bad tp index throws', () {
      expect(
        () => ConfirmationEvaluator.isTakeProfitHit(_longSignal(), 4, 4300),
        throwsArgumentError,
      );
    });
  });

  group('later/terminal stages untouched by confirmation', () {
    test('active and expired pass through', () {
      final sig = _longSignal();
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4277,
          structure: const FiveMinuteStructure(momentum: true),
          current: SignalStatus.active,
        ),
        SignalStatus.active,
      );
      expect(
        ConfirmationEvaluator.evaluate(
          signal: sig,
          price: 4277,
          structure: const FiveMinuteStructure(momentum: true),
          current: SignalStatus.expired,
        ),
        SignalStatus.expired,
      );
    });
  });
}
