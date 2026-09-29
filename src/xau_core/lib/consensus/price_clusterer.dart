/// Median-based price clustering with outlier rejection.
///
/// Interpretation note (spec ambiguity): spec §8/§9 show illustrative zones
/// (`4277–4281`, `4262–4265`) rather than a normative algorithm. This
/// implementation uses median-based rejection with fixed point tolerances
/// (entry 2.0, SL 6.0, TP 4.0). The adaptive draft formula
/// `max(1.5, span × 0.5)` from TASK-01 was rejected because a span-dependent
/// tolerance absorbs the very outliers it should reject (e.g. the 4300 SL
/// widens the span to ~40, yielding tolerance ~20).
library;

import '../models/price_range.dart';

/// Result of clustering scalar price levels.
class ValueCluster {
  /// Inlier values kept after rejection.
  final List<double> inliers;

  /// Rejected outliers.
  final List<double> outliers;

  /// Median of inliers (the consensus price).
  final double consensus;

  /// Minimum inlier (lower edge of the consensus band).
  final double low;

  /// Maximum inlier (upper edge of the consensus band).
  final double high;

  const ValueCluster({
    required this.inliers,
    required this.outliers,
    required this.consensus,
    required this.low,
    required this.high,
  });
}

/// Result of clustering entry zones.
class RangeCluster {
  final PriceRange consensus;
  final List<PriceRange> inliers;
  final List<PriceRange> outliers;

  const RangeCluster({
    required this.consensus,
    required this.inliers,
    required this.outliers,
  });
}

/// Clusters price levels with median-based outlier rejection.
///
/// No I/O, no clock access. All thresholds are explicit parameters.
class PriceClusterer {
  /// Default tolerance for entry-zone mids (XAUUSD points).
  static const double defaultEntryTolerance = 2.0;

  /// Default tolerance for stop-loss values (wider: SLs disperse more).
  static const double defaultSlTolerance = 6.0;

  /// Default tolerance for take-profit values per TP index.
  static const double defaultTpTolerance = 4.0;

  /// Median of [values]. Throws on empty input.
  static double median(List<double> values) {
    if (values.isEmpty) {
      throw ArgumentError('Cannot take median of empty list.');
    }
    final sorted = List<double>.of(values)..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  /// Clusters scalar [values], rejecting points farther than [tolerance]
  /// from the median. If every point is rejected, keeps the single point
  /// closest to the median so callers always get a usable consensus.
  static ValueCluster clusterValues(
    List<double> values, {
    double tolerance = defaultSlTolerance,
  }) {
    if (values.isEmpty) {
      throw ArgumentError('Cannot cluster an empty value list.');
    }
    final med = median(values);
    final inliers = <double>[];
    final outliers = <double>[];
    for (final v in values) {
      if ((v - med).abs() <= tolerance) {
        inliers.add(v);
      } else {
        outliers.add(v);
      }
    }
    var finalInliers = inliers;
    var finalOutliers = outliers;
    if (finalInliers.isEmpty) {
      var closest = values.first;
      var best = (closest - med).abs();
      for (final v in values.skip(1)) {
        final d = (v - med).abs();
        if (d < best) {
          best = d;
          closest = v;
        }
      }
      finalInliers = <double>[closest];
      finalOutliers = values.where((v) => v != closest).toList();
    }
    final consensus = median(finalInliers);
    var low = finalInliers.first;
    var high = finalInliers.first;
    for (final v in finalInliers.skip(1)) {
      if (v < low) low = v;
      if (v > high) high = v;
    }
    return ValueCluster(
      inliers: List.unmodifiable(finalInliers),
      outliers: List.unmodifiable(finalOutliers),
      consensus: consensus,
      low: low,
      high: high,
    );
  }

  /// Clusters entry [ranges] by their mids, then takes the median low and
  /// median high of the inlier zones as the consensus zone.
  static RangeCluster clusterRanges(
    List<PriceRange> ranges, {
    double tolerance = defaultEntryTolerance,
  }) {
    if (ranges.isEmpty) {
      throw ArgumentError('Cannot cluster an empty range list.');
    }
    final mids = ranges.map((r) => r.mid).toList();
    final med = median(mids);
    final inliers = <PriceRange>[];
    final outliers = <PriceRange>[];
    for (var i = 0; i < ranges.length; i++) {
      if ((mids[i] - med).abs() <= tolerance) {
        inliers.add(ranges[i]);
      } else {
        outliers.add(ranges[i]);
      }
    }
    var finalInliers = inliers;
    var finalOutliers = outliers;
    if (finalInliers.isEmpty) {
      var bestIdx = 0;
      var best = (mids[0] - med).abs();
      for (var i = 1; i < ranges.length; i++) {
        final d = (mids[i] - med).abs();
        if (d < best) {
          best = d;
          bestIdx = i;
        }
      }
      finalInliers = <PriceRange>[ranges[bestIdx]];
      finalOutliers =
          ranges.where((r) => r != ranges[bestIdx]).toList();
    }
    final low = median(finalInliers.map((r) => r.low).toList());
    final high = median(finalInliers.map((r) => r.high).toList());
    return RangeCluster(
      consensus: PriceRange(low: low, high: high),
      inliers: List.unmodifiable(finalInliers),
      outliers: List.unmodifiable(finalOutliers),
    );
  }

  /// Clusters take-profit targets per TP index. Input maps TP index (1-based)
  /// to the list of quoted prices for that index.
  static Map<int, ValueCluster> clusterTakeProfits(
    Map<int, List<double>> byIndex, {
    double tolerance = defaultTpTolerance,
  }) {
    final out = <int, ValueCluster>{};
    byIndex.forEach((index, values) {
      if (values.isNotEmpty) {
        out[index] = clusterValues(values, tolerance: tolerance);
      }
    });
    return out;
  }
}
