// State-machine tests: the three spec §14 paths, stamped history,
// illegal-transition rejection (strict throw / prod-mode ignore).
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xau_lifecycle/xau_lifecycle.dart';

final _t0 = DateTime.utc(2026, 9, 29, 12);

void main() {
  group('happy path: noSetup → developing → ready → confirmed → active → TPs',
      () {
    test('full walk with strictly increasing timestamps', () {
      final machine = SignalStateMachine(initial: SignalStatus.noSetup);
      const path = [
        SignalStatus.developing,
        SignalStatus.ready,
        SignalStatus.confirmed,
        SignalStatus.active,
        SignalStatus.tp1Hit,
        SignalStatus.tp2Hit,
        SignalStatus.tp3Hit,
      ];
      var now = _t0;
      for (final next in path) {
        now = now.add(const Duration(minutes: 1));
        expect(
          machine.transitionTo(next, now, reason: 'test $next'),
          isTrue,
        );
      }
      expect(machine.current, SignalStatus.tp3Hit);
      expect(machine.isTerminal, isTrue);
      expect(machine.history, hasLength(path.length));
      for (var i = 0; i < machine.history.length; i++) {
        expect(
          machine.history[i].at,
          _t0.add(Duration(minutes: i + 1)),
        );
        if (i > 0) {
          expect(
            machine.history[i].at.isAfter(machine.history[i - 1].at),
            isTrue,
          );
        }
      }
      expect(machine.history.last.to, SignalStatus.tp3Hit);
    });
  });

  group('invalidation path: developing → invalidated', () {
    test('walks and terminates', () {
      final machine =
          SignalStateMachine(initial: SignalStatus.developing);
      final now = _t0.add(const Duration(minutes: 2));
      expect(
        machine.transitionTo(SignalStatus.invalidated, now, reason: 'SL'),
        isTrue,
      );
      expect(machine.current, SignalStatus.invalidated);
      expect(machine.isTerminal, isTrue);
      expect(machine.history, hasLength(1));
      expect(machine.history.single.at, now);
      expect(machine.history.single.reason, 'SL');
    });
  });

  group('expiry path: ready → expired', () {
    test('direct edge and expireIfDue helper', () {
      final machine = SignalStateMachine(initial: SignalStatus.developing);
      machine.transitionTo(SignalStatus.ready, _t0);
      final expiresAt = _t0.add(const Duration(minutes: 60));

      // Before expiry nothing happens.
      expect(
        machine.expireIfDue(
          _t0.add(const Duration(minutes: 59)),
          expiresAt,
        ),
        isFalse,
      );
      expect(machine.current, SignalStatus.ready);

      // At expiry the machine moves to expired with a stamp.
      expect(
        machine.expireIfDue(expiresAt, expiresAt),
        isTrue,
      );
      expect(machine.current, SignalStatus.expired);
      expect(machine.isTerminal, isTrue);
      expect(machine.history.last.at, expiresAt);
    });

    test('confirmed past expiresAt also expires', () {
      final machine = SignalStateMachine(initial: SignalStatus.ready);
      machine.transitionTo(SignalStatus.confirmed, _t0);
      expect(
        machine.expireIfDue(
          _t0.add(const Duration(hours: 2)),
          _t0.add(const Duration(minutes: 60)),
          reason: 'stale setup',
        ),
        isTrue,
      );
      expect(machine.current, SignalStatus.expired);
      expect(machine.history.last.reason, 'stale setup');
    });

    test('developing past expiresAt is untouched (TASK-02 scope)', () {
      final machine =
          SignalStateMachine(initial: SignalStatus.developing);
      expect(
        machine.expireIfDue(
          _t0.add(const Duration(hours: 3)),
          _t0.add(const Duration(minutes: 60)),
        ),
        isFalse,
      );
      expect(machine.current, SignalStatus.developing);
    });

    test('null expiresAt never expires', () {
      final machine = SignalStateMachine(initial: SignalStatus.ready);
      expect(machine.expireIfDue(_t0, null), isFalse);
      expect(machine.current, SignalStatus.ready);
    });
  });

  group('illegal transitions', () {
    test('strict mode throws and keeps state/history untouched', () {
      final machine =
          SignalStateMachine(initial: SignalStatus.developing);
      // Skipping ready is illegal.
      expect(
        () => machine.transitionTo(SignalStatus.confirmed, _t0),
        throwsA(isA<IllegalTransitionException>()),
      );
      expect(machine.current, SignalStatus.developing);
      expect(machine.history, isEmpty);

      // Self-transitions are illegal.
      expect(
        () => machine.transitionTo(SignalStatus.developing, _t0),
        throwsA(isA<IllegalTransitionException>()),
      );
    });

    test('skipped stages rejected along the happy path', () {
      final machine = SignalStateMachine(initial: SignalStatus.ready);
      // ready → active skips confirmed.
      expect(
        () => machine.transitionTo(SignalStatus.active, _t0),
        throwsA(isA<IllegalTransitionException>()),
      );
      final active = SignalStateMachine(initial: SignalStatus.active);
      // active → tp2Hit skips tp1Hit.
      expect(
        () => active.transitionTo(SignalStatus.tp2Hit, _t0),
        throwsA(isA<IllegalTransitionException>()),
      );
      // active can never go back to ready/confirmed.
      expect(
        () => active.transitionTo(SignalStatus.ready, _t0),
        throwsA(isA<IllegalTransitionException>()),
      );
    });

    test('terminal states reject every move', () {
      for (final terminal in [
        SignalStatus.tp3Hit,
        SignalStatus.invalidated,
        SignalStatus.expired,
      ]) {
        final machine = SignalStateMachine(initial: terminal);
        expect(machine.isTerminal, isTrue);
        for (final target in SignalStatus.values) {
          expect(
            () => machine.transitionTo(target, _t0),
            throwsA(isA<IllegalTransitionException>()),
            reason: '$terminal -> $target must throw',
          );
        }
      }
    });

    test('prod mode ignores illegal moves and returns false for logging',
        () {
      final machine = SignalStateMachine(
        initial: SignalStatus.developing,
        strict: false,
      );
      expect(
        machine.transitionTo(SignalStatus.confirmed, _t0),
        isFalse,
      );
      expect(machine.current, SignalStatus.developing);
      expect(machine.history, isEmpty);
      // Legal moves still work in prod mode.
      expect(machine.transitionTo(SignalStatus.ready, _t0), isTrue);
      expect(machine.current, SignalStatus.ready);
    });
  });

  group('transition legality table', () {
    test('matches TASK-02 T2.1 exactly', () {
      bool legal(SignalStatus from, SignalStatus to) =>
          SignalStateMachine.isLegal(from, to);
      expect(legal(SignalStatus.noSetup, SignalStatus.developing), isTrue);
      expect(
        legal(SignalStatus.developing, SignalStatus.ready),
        isTrue,
      );
      expect(
        legal(SignalStatus.developing, SignalStatus.invalidated),
        isTrue,
      );
      expect(legal(SignalStatus.developing, SignalStatus.expired), isTrue);
      expect(legal(SignalStatus.ready, SignalStatus.confirmed), isTrue);
      expect(
        legal(SignalStatus.ready, SignalStatus.invalidated),
        isTrue,
      );
      expect(legal(SignalStatus.ready, SignalStatus.expired), isTrue);
      expect(legal(SignalStatus.confirmed, SignalStatus.active), isTrue);
      expect(
        legal(SignalStatus.confirmed, SignalStatus.invalidated),
        isTrue,
      );
      expect(legal(SignalStatus.confirmed, SignalStatus.expired), isTrue);
      expect(legal(SignalStatus.active, SignalStatus.tp1Hit), isTrue);
      expect(
        legal(SignalStatus.active, SignalStatus.invalidated),
        isTrue,
      );
      expect(legal(SignalStatus.tp1Hit, SignalStatus.tp2Hit), isTrue);
      expect(
        legal(SignalStatus.tp1Hit, SignalStatus.invalidated),
        isTrue,
      );
      expect(legal(SignalStatus.tp2Hit, SignalStatus.tp3Hit), isTrue);
      expect(
        legal(SignalStatus.tp2Hit, SignalStatus.invalidated),
        isTrue,
      );
      // A sample of moves that must stay illegal.
      expect(legal(SignalStatus.developing, SignalStatus.active), isFalse);
      expect(legal(SignalStatus.ready, SignalStatus.active), isFalse);
      expect(legal(SignalStatus.confirmed, SignalStatus.tp1Hit), isFalse);
      expect(legal(SignalStatus.active, SignalStatus.expired), isFalse);
      expect(legal(SignalStatus.tp1Hit, SignalStatus.tp3Hit), isFalse);
    });
  });
}
