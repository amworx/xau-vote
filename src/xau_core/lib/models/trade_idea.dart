/// Standardized intraday trade idea (spec §4).
library;

import 'enums.dart';
import 'price_range.dart';
import 'take_profit.dart';

/// Standardized internal representation of one source's trade idea.
///
/// Field list mirrors spec §4 exactly. Freshness is derived from
/// [publishedAt] against a caller-supplied `now`; the stored [freshness]
/// field is an optional cached snapshot.
class TradeIdea {
  final String id;
  final String source;
  final String? sourceUrl;
  final String? author;
  final DateTime? publishedAt;
  final DateTime? collectedAt;

  final String symbol;
  final TradeTimeframe timeframe;
  final Direction direction;

  final String? entryType;
  final double? entryLow;
  final double? entryHigh;

  final double? stopLoss;
  final List<TakeProfit> takeProfits;

  final String? triggerCondition;
  final String? invalidationCondition;
  final String? reasoning;

  final double? confidence;
  final Freshness? freshness;
  final String? sourceFingerprint;

  TradeIdea({
    required this.id,
    required this.source,
    this.sourceUrl,
    this.author,
    this.publishedAt,
    this.collectedAt,
    this.symbol = 'XAUUSD',
    required this.timeframe,
    required this.direction,
    this.entryType,
    this.entryLow,
    this.entryHigh,
    this.stopLoss,
    List<TakeProfit>? takeProfits,
    this.triggerCondition,
    this.invalidationCondition,
    this.reasoning,
    this.confidence,
    this.freshness,
    this.sourceFingerprint,
  }) : takeProfits = List.unmodifiable(takeProfits ?? const <TakeProfit>[]);

  /// Entry zone when both edges are present, else null.
  PriceRange? get entryRange {
    if (entryLow == null || entryHigh == null) return null;
    return PriceRange(low: entryLow!, high: entryHigh!);
  }

  /// Mid of the entry zone, or the single available edge, else null.
  double? get entryMid {
    if (entryLow != null && entryHigh != null) {
      return (entryLow! + entryHigh!) / 2.0;
    }
    return entryLow ?? entryHigh;
  }

  /// Freshness derived from [publishedAt] against [now] (no clock reads).
  Freshness derivedFreshness(DateTime now) =>
      Freshness.fromTimestamps(publishedAt, now);

  /// True when the idea carries the minimum actionable levels:
  /// an entry edge, a stop loss, and at least one take profit.
  bool get hasActionableLevels =>
      (entryLow != null || entryHigh != null) &&
      stopLoss != null &&
      takeProfits.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'source': source,
        'sourceUrl': sourceUrl,
        'author': author,
        'publishedAt': publishedAt?.toUtc().toIso8601String(),
        'collectedAt': collectedAt?.toUtc().toIso8601String(),
        'symbol': symbol,
        'timeframe': timeframe.toJson(),
        'direction': direction.toJson(),
        'entryType': entryType,
        'entryLow': entryLow,
        'entryHigh': entryHigh,
        'stopLoss': stopLoss,
        'takeProfits': takeProfits.map((e) => e.toJson()).toList(),
        'triggerCondition': triggerCondition,
        'invalidationCondition': invalidationCondition,
        'reasoning': reasoning,
        'confidence': confidence,
        'freshness': freshness?.toJson(),
        'sourceFingerprint': sourceFingerprint,
      };

  factory TradeIdea.fromJson(Map<String, Object?> json) {
    DateTime? parseTime(Object? v) =>
        v == null ? null : DateTime.parse(v as String);
    return TradeIdea(
      id: json['id'] as String,
      source: json['source'] as String,
      sourceUrl: json['sourceUrl'] as String?,
      author: json['author'] as String?,
      publishedAt: parseTime(json['publishedAt']),
      collectedAt: parseTime(json['collectedAt']),
      symbol: (json['symbol'] as String?) ?? 'XAUUSD',
      timeframe: TradeTimeframe.fromJson(json['timeframe'] as String),
      direction: Direction.fromJson(json['direction'] as String),
      entryType: json['entryType'] as String?,
      entryLow: (json['entryLow'] as num?)?.toDouble(),
      entryHigh: (json['entryHigh'] as num?)?.toDouble(),
      stopLoss: (json['stopLoss'] as num?)?.toDouble(),
      takeProfits: ((json['takeProfits'] as List?) ?? const [])
          .map((e) => TakeProfit.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
      triggerCondition: json['triggerCondition'] as String?,
      invalidationCondition: json['invalidationCondition'] as String?,
      reasoning: json['reasoning'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      freshness: json['freshness'] == null
          ? null
          : Freshness.fromJson(json['freshness'] as String),
      sourceFingerprint: json['sourceFingerprint'] as String?,
    );
  }

  @override
  String toString() =>
      'TradeIdea($id ${direction.toJson()} ${timeframe.toJson()} '
      'entry=$entryLow–$entryHigh sl=$stopLoss)';
}
