/// Entry-zone value type.
library;

/// A closed price interval `[low, high]` in XAUUSD points.
///
/// Single-price levels are represented with `low == high`.
class PriceRange {
  final double low;
  final double high;

  PriceRange({required this.low, required this.high}) {
    if (low > high) {
      throw ArgumentError('PriceRange low ($low) must be <= high ($high).');
    }
  }

  /// Mid-point of the zone.
  double get mid => (low + high) / 2.0;

  /// Width of the zone in points.
  double get width => high - low;

  /// True when [price] lies inside the zone (inclusive).
  bool contains(double price) => price >= low && price <= high;

  Map<String, Object?> toJson() => <String, Object?>{
        'low': low,
        'high': high,
      };

  factory PriceRange.fromJson(Map<String, Object?> json) {
    return PriceRange(
      low: (json['low'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PriceRange && other.low == low && other.high == high;

  @override
  int get hashCode => Object.hash(low, high);

  @override
  String toString() => 'PriceRange($low–$high)';
}
