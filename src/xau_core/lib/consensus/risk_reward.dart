/// Risk/reward calculator (spec §11).
library;

import '../models/enums.dart';
import '../models/price_range.dart';

/// Risk and per-TP reward in points plus R:R multiples.
///
/// R:R multiple = reward / risk (e.g. 1.13 means "1 : 1.13").
class RiskRewardResult {
  /// Risk distance in points (always positive).
  final double risk;

  /// Reward distance per TP in points.
  final List<double> rewards;

  /// R:R multiple per TP (reward / risk).
  final List<double> ratios;

  const RiskRewardResult({
    required this.risk,
    required this.rewards,
    required this.ratios,
  });
}

/// Pure risk/reward math. No I/O, no clocks.
class RiskReward {
  /// Calculates risk/reward for an explicit [entryPrice].
  ///
  /// LONG: risk = entry − SL, reward = TP − entry.
  /// SHORT: risk = SL − entry, reward = entry − TP.
  /// Throws [ArgumentError] for non-positive risk or [Direction.neutral].
  static RiskRewardResult calculate({
    required double entryPrice,
    required double stopLoss,
    required List<double> takeProfits,
    required Direction direction,
  }) {
    if (direction == Direction.neutral) {
      throw ArgumentError('Cannot compute R:R for neutral direction.');
    }
    final risk = direction == Direction.long
        ? entryPrice - stopLoss
        : stopLoss - entryPrice;
    if (risk <= 0) {
      throw ArgumentError(
          'Invalid setup: risk must be positive (entry=$entryPrice, '
          'sl=$stopLoss, direction=${direction.toJson()}).');
    }
    final rewards = takeProfits.map((tp) {
      return direction == Direction.long ? tp - entryPrice : entryPrice - tp;
    }).toList();
    final ratios = rewards.map((r) => r / risk).toList();
    return RiskRewardResult(
      risk: risk,
      rewards: List.unmodifiable(rewards),
      ratios: List.unmodifiable(ratios),
    );
  }

  /// Conservative (worst-case) fill edge of [zone] for [direction]:
  /// LONG fills at the high, SHORT at the low.
  static double conservativeEdge(PriceRange zone, Direction direction) {
    if (direction == Direction.neutral) {
      throw ArgumentError('No conservative edge for neutral direction.');
    }
    return direction == Direction.long ? zone.high : zone.low;
  }

  /// Calculates R:R from an entry zone using its mid price.
  static RiskRewardResult fromZoneMid({
    required PriceRange entryZone,
    required double stopLoss,
    required List<double> takeProfits,
    required Direction direction,
  }) {
    return calculate(
      entryPrice: entryZone.mid,
      stopLoss: stopLoss,
      takeProfits: takeProfits,
      direction: direction,
    );
  }

  /// Calculates R:R from the worst-case edge of [entryZone].
  static RiskRewardResult fromWorstEdge({
    required PriceRange entryZone,
    required double stopLoss,
    required List<double> takeProfits,
    required Direction direction,
  }) {
    return calculate(
      entryPrice: conservativeEdge(entryZone, direction),
      stopLoss: stopLoss,
      takeProfits: takeProfits,
      direction: direction,
    );
  }
}
