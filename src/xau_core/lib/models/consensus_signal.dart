/// Consensus trading setup produced from clustered ideas (spec §6–§11).
library;

import 'enums.dart';
import 'price_range.dart';

/// One clear 15-minute setup derived from agreement among ideas.
///
/// [strength] is a 0–100 agreement score (spec §7). It is never a
/// probability of profit and must never be displayed as one.
class ConsensusSignal {
  final String id;
  final String symbol;
  final TradeTimeframe timeframe;
  final Direction direction;

  /// Agreement score 0–100.
  final int strength;

  final double entryLow;
  final double entryHigh;
  final double stopLoss;
  final double? tp1;
  final double? tp2;
  final double? tp3;

  final SignalStatus status;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? expiresAt;

  /// Independent sources agreeing with this signal.
  final int independentSourceCount;

  /// Total raw ideas considered for the dominant direction.
  final int totalSourceCount;

  /// Ids of the agreeing ideas (cluster members).
  final List<String> agreeingSourceIds;

  ConsensusSignal({
    required this.id,
    this.symbol = 'XAUUSD',
    this.timeframe = TradeTimeframe.m15,
    required this.direction,
    required this.strength,
    required this.entryLow,
    required this.entryHigh,
    required this.stopLoss,
    this.tp1,
    this.tp2,
    this.tp3,
    this.status = SignalStatus.developing,
    this.createdAt,
    this.updatedAt,
    this.expiresAt,
    this.independentSourceCount = 0,
    this.totalSourceCount = 0,
    List<String>? agreeingSourceIds,
  })  : agreeingSourceIds =
            List.unmodifiable(agreeingSourceIds ?? const <String>[]) {
    if (strength < 0 || strength > 100) {
      throw ArgumentError('strength must be 0–100, got $strength.');
    }
    if (entryLow > entryHigh) {
      throw ArgumentError(
          'entryLow ($entryLow) must be <= entryHigh ($entryHigh).');
    }
  }

  /// Strength band per spec §7.
  ConsensusStrength get strengthBand => ConsensusStrength.fromScore(strength);

  /// Consensus entry zone.
  PriceRange get entryZone => PriceRange(low: entryLow, high: entryHigh);

  /// Ordered non-null take-profit targets.
  List<double> get takeProfitList {
    final out = <double>[];
    if (tp1 != null) out.add(tp1!);
    if (tp2 != null) out.add(tp2!);
    if (tp3 != null) out.add(tp3!);
    return out;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'symbol': symbol,
        'timeframe': timeframe.toJson(),
        'direction': direction.toJson(),
        'strength': strength,
        'entryLow': entryLow,
        'entryHigh': entryHigh,
        'stopLoss': stopLoss,
        'tp1': tp1,
        'tp2': tp2,
        'tp3': tp3,
        'status': status.toJson(),
        'createdAt': createdAt?.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'expiresAt': expiresAt?.toUtc().toIso8601String(),
        'independentSourceCount': independentSourceCount,
        'totalSourceCount': totalSourceCount,
        'agreeingSourceIds': agreeingSourceIds,
      };

  factory ConsensusSignal.fromJson(Map<String, Object?> json) {
    DateTime? parseTime(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    return ConsensusSignal(
      id: json['id'] as String,
      symbol: (json['symbol'] as String?) ?? 'XAUUSD',
      timeframe: json['timeframe'] == null
          ? TradeTimeframe.m15
          : TradeTimeframe.fromJson(json['timeframe'] as String),
      direction: Direction.fromJson(json['direction'] as String),
      strength: (json['strength'] as num).toInt(),
      entryLow: (json['entryLow'] as num).toDouble(),
      entryHigh: (json['entryHigh'] as num).toDouble(),
      stopLoss: (json['stopLoss'] as num).toDouble(),
      tp1: (json['tp1'] as num?)?.toDouble(),
      tp2: (json['tp2'] as num?)?.toDouble(),
      tp3: (json['tp3'] as num?)?.toDouble(),
      status: json['status'] == null
          ? SignalStatus.developing
          : SignalStatus.fromJson(json['status'] as String),
      createdAt: parseTime(json['createdAt']),
      updatedAt: parseTime(json['updatedAt']),
      expiresAt: parseTime(json['expiresAt']),
      independentSourceCount:
          (json['independentSourceCount'] as num?)?.toInt() ?? 0,
      totalSourceCount: (json['totalSourceCount'] as num?)?.toInt() ?? 0,
      agreeingSourceIds: ((json['agreeingSourceIds'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }

  @override
  String toString() =>
      'ConsensusSignal(${direction.toJson()} strength=$strength '
      'entry=$entryLow–$entryHigh sl=$stopLoss)';
}
