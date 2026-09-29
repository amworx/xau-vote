/// Timestamped signal state machine (spec §14).
library;

import 'package:xau_core/xau_core.dart';

/// Thrown on illegal transitions when the machine runs in strict mode.
class IllegalTransitionException implements Exception {
  /// State the machine was in when the illegal move was attempted.
  final SignalStatus from;

  /// State that was requested.
  final SignalStatus to;

  /// Creates an illegal-transition error for [from] → [to].
  const IllegalTransitionException(this.from, this.to);

  @override
  String toString() => 'IllegalTransitionException: ${from.toJson()} -> '
      '${to.toJson()} is not a legal signal transition.';
}

/// One stamped state change.
class SignalStateTransition {
  /// State the signal left.
  final SignalStatus from;

  /// State the signal entered.
  final SignalStatus to;

  /// Caller-supplied timestamp of the transition (no clock reads inside).
  final DateTime at;

  /// Optional human-readable cause (e.g. `TP1 hit at 4296.0`).
  final String? reason;

  /// Creates a stamped transition record.
  const SignalStateTransition({
    required this.from,
    required this.to,
    required this.at,
    this.reason,
  });
}

/// Legal-transition state machine over [SignalStatus] (spec §14).
///
/// Legal edges:
/// ```text
/// noSetup    → developing
/// developing → ready | invalidated | expired
/// ready      → confirmed | invalidated | expired
/// confirmed  → active | invalidated | expired
/// active     → tp1Hit | invalidated
/// tp1Hit     → tp2Hit | invalidated
/// tp2Hit     → tp3Hit | invalidated
/// ```
/// Terminal states (no outgoing edges): tp3Hit, invalidated, expired.
///
/// In strict mode (default, for tests) illegal transitions throw
/// [IllegalTransitionException]. In prod mode (`strict: false`) they are
/// ignored and reported via the `false` return so callers can log them.
class SignalStateMachine {
  /// Legal outgoing edges per state. Empty set means terminal.
  static const Map<SignalStatus, Set<SignalStatus>> legalTransitions = {
    SignalStatus.noSetup: {SignalStatus.developing},
    SignalStatus.developing: {
      SignalStatus.ready,
      SignalStatus.invalidated,
      SignalStatus.expired,
    },
    SignalStatus.ready: {
      SignalStatus.confirmed,
      SignalStatus.invalidated,
      SignalStatus.expired,
    },
    SignalStatus.confirmed: {
      SignalStatus.active,
      SignalStatus.invalidated,
      SignalStatus.expired,
    },
    SignalStatus.active: {SignalStatus.tp1Hit, SignalStatus.invalidated},
    SignalStatus.tp1Hit: {SignalStatus.tp2Hit, SignalStatus.invalidated},
    SignalStatus.tp2Hit: {SignalStatus.tp3Hit, SignalStatus.invalidated},
    SignalStatus.tp3Hit: {},
    SignalStatus.invalidated: {},
    SignalStatus.expired: {},
  };

  SignalStatus _current;
  final List<SignalStateTransition> _history = [];

  /// When false, illegal transitions are ignored (return false) instead of
  /// throwing, so production callers can log and continue.
  final bool strict;

  /// Creates a machine in [initial] (default `developing`).
  SignalStateMachine({
    SignalStatus initial = SignalStatus.developing,
    this.strict = true,
  }) : _current = initial;

  /// Current lifecycle state.
  SignalStatus get current => _current;

  /// Stamped transition history, oldest first.
  List<SignalStateTransition> get history => List.unmodifiable(_history);

  /// True when no outgoing edge exists (tp3Hit, invalidated, expired).
  bool get isTerminal => legalTransitions[_current]?.isEmpty ?? true;

  /// True when [from] → [to] is a legal edge.
  static bool isLegal(SignalStatus from, SignalStatus to) =>
      legalTransitions[from]?.contains(to) ?? false;

  /// Attempts the move to [next] stamped with [now].
  ///
  /// Returns true on success. On illegal moves throws
  /// [IllegalTransitionException] in strict mode, or returns false (state
  /// and history untouched) in prod mode.
  bool transitionTo(SignalStatus next, DateTime now, {String? reason}) {
    if (!isLegal(_current, next)) {
      if (strict) throw IllegalTransitionException(_current, next);
      return false;
    }
    _history.add(
      SignalStateTransition(from: _current, to: next, at: now, reason: reason),
    );
    _current = next;
    return true;
  }

  /// Moves `ready`/`confirmed` signals at or past [expiresAt] to `expired`
  /// (spec §14/§15). Returns true when a transition happened.
  ///
  /// Other states are never touched here: `developing` has no expiry edge in
  /// the accepted TASK-02 scope, and live/terminal states resolve via
  /// TP hits, SL breaches, or not at all.
  bool expireIfDue(DateTime now, DateTime? expiresAt, {String? reason}) {
    if (expiresAt == null) return false;
    if ((_current == SignalStatus.ready ||
            _current == SignalStatus.confirmed) &&
        !now.isBefore(expiresAt)) {
      return transitionTo(
        SignalStatus.expired,
        now,
        reason: reason ?? 'past expiresAt',
      );
    }
    return false;
  }
}
