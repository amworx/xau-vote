/// Deterministic 5M confirmation (spec §13).
library;

import 'package:xau_core/xau_core.dart';

/// Externally supplied 5M structure flags.
///
/// MVP rule: any single confirming flag while price holds the entry zone
/// confirms a ready setup. Flags arrive from price-action providers; this
/// package never reads market data itself.
class FiveMinuteStructure {
  /// Price broke out and retested the level.
  final bool breakoutRetest;

  /// Rejection wick / failed push through the zone edge.
  final bool rejection;

  /// Momentum push in the signal direction.
  final bool momentum;

  /// Creates a structure snapshot (default: no confirming flags).
  const FiveMinuteStructure({
    this.breakoutRetest = false,
    this.rejection = false,
    this.momentum = false,
  });

  /// True when at least one confirming flag is set (MVP confirmation rule).
  bool get confirms => breakoutRetest || rejection || momentum;
}

/// Deterministic 5M confirmation evaluator (spec §13).
///
/// Rules, checked in this order:
/// - invalidated: price closes beyond the invalidation level (SL side).
///   LONG is breached strictly below SL, SHORT strictly above SL; a print
///   exactly on SL is NOT a breach. Checked first, from any state.
/// - ready: price enters the consensus entry zone (inclusive edges).
/// - confirmed: the ready stage is sticky, and confirmation needs price
///   still inside the zone plus any one structure flag ([FiveMinuteStructure.confirms]).
/// - otherwise the current stage holds: leaving the zone without breaching
///   SL never demotes `ready` back to `developing`.
///
/// Only the pre-active stages (developing/ready/confirmed/invalidated) are
/// produced here; active/TP progression is the lifecycle's job (TP hits),
/// reusing [isBreached] and [isTakeProfitHit] so the rule lives in one place.
class ConfirmationEvaluator {
  const ConfirmationEvaluator._();

  /// True when [price] has closed beyond the SL side of [signal].
  /// Neutral signals never breach.
  static bool isBreached(ConsensusSignal signal, double price) {
    switch (signal.direction) {
      case Direction.long:
        return price < signal.stopLoss;
      case Direction.short:
        return price > signal.stopLoss;
      case Direction.neutral:
        return false;
    }
  }

  /// True when [price] touches the [tpIndex] target (1-based), direction
  /// aware (LONG: `price >= target`, SHORT: `price <= target`). Null
  /// targets never hit; neutral signals never hit.
  static bool isTakeProfitHit(
    ConsensusSignal signal,
    int tpIndex,
    double price,
  ) {
    final double? target;
    switch (tpIndex) {
      case 1:
        target = signal.tp1;
      case 2:
        target = signal.tp2;
      case 3:
        target = signal.tp3;
      default:
        throw ArgumentError('tpIndex must be 1-3, got $tpIndex.');
    }
    if (target == null) return false;
    switch (signal.direction) {
      case Direction.long:
        return price >= target;
      case Direction.short:
        return price <= target;
      case Direction.neutral:
        return false;
    }
  }

  /// Evaluates the next confirmation stage. Pure and deterministic:
  /// same inputs always yield the same output, and `now` is not needed.
  static SignalStatus evaluate({
    required ConsensusSignal signal,
    required double price,
    required FiveMinuteStructure structure,
    required SignalStatus current,
  }) {
    if (isBreached(signal, price)) return SignalStatus.invalidated;
    final inZone = signal.entryZone.contains(price);
    switch (current) {
      case SignalStatus.developing:
        return inZone ? SignalStatus.ready : SignalStatus.developing;
      case SignalStatus.ready:
        return (inZone && structure.confirms)
            ? SignalStatus.confirmed
            : SignalStatus.ready;
      case SignalStatus.confirmed:
        return SignalStatus.confirmed;
      case SignalStatus.invalidated:
        return SignalStatus.invalidated;
      default:
        // Active/TP-hit and terminal states are governed by TP hits, SL
        // breaches and expiry elsewhere; confirmation leaves them untouched.
        return current;
    }
  }
}
