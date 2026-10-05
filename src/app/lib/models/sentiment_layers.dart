/// Sentiment layers read from the `sentiment_layers` table, mapped onto the
/// confluence engine's [MacroState] / [SentimentState].
///
/// SOURCE OF THE NUMBERS: `supabase/functions/sentiment-layers`, which measures
/// §5.1 layers from US Treasury and CFTC publications. This file does no
/// measuring of its own — it only parses what was measured and refuses to
/// present a partial picture as a whole one.
///
/// ── The coverage rule, and why it exists ───────────────────────────────────
/// The scorer (confluence.dart §13) reads ONLY `macro.alignment` and
/// `sentiment.alignment`; the individual impulses are stored but unused. Two
/// consequences shape everything here:
///
///   * `macro.alignment < 0` calls `veto(v6DirectionConflict)` — it can block a
///     setup outright.
///   * `sentiment.alignment < 0` only applies a confidence penalty.
///
/// So the two are mapped differently, on purpose:
///
///   * Positioning is ONE complete §5.1 layer (25% weight, fully measured), so
///     its alignment is passed straight through. The worst it can do is reduce
///     confidence, which is what §6 requires of a weekly reading.
///
///   * Macro alignment is left NULL until enough macro-side weight is actually
///     measured. Today only `market_implied` (20) exists out of 75 macro-side
///     points, so it is 27% — and letting a 27% sample veto a trade would be
///     inventing conviction in either direction. The measured impulse is still
///     surfaced in [MacroState.realYieldImpulse] and in [measuredCoverage], so
///     the data is visible while it is not yet strong enough to act on.
///
/// A missing layer is reported as missing, never as zero. Zero means "neutral";
/// silence does not mean neutral.
library;

import 'package:xau_core/xau_core.dart';

/// One row of `sentiment_layers`.
class SentimentLayerRow {
  const SentimentLayerRow({
    required this.layer,
    required this.horizon,
    required this.weight,
    required this.score,
    required this.alignment,
    required this.measuredAt,
    required this.source,
    required this.sourceUrl,
    required this.stale,
    required this.detail,
  });

  final String layer;
  final String horizon;
  final double weight;

  /// Raw §5 score, or null when the layer could not be measured.
  final int? score;

  /// -1 / 0 / +1, or null when unmeasured.
  final int? alignment;

  /// When the underlying reading is from. Null-safe: an epoch timestamp means
  /// "never measured" upstream, not "measured in 1970".
  final DateTime? measuredAt;

  final String source;
  final String? sourceUrl;
  final bool stale;
  final Map<String, dynamic> detail;

  static double? _toDouble(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _toInt(Object? v) {
    final d = _toDouble(v);
    if (d == null) return null;
    return d.round();
  }

  static DateTime? _toDate(Object? v) {
    if (v == null) return null;
    final parsed = DateTime.tryParse(v.toString());
    if (parsed == null) return null;
    // The writer uses the Unix epoch to mean "never measured"; do not hand a
    // 1970 date to a caller that would render it as a real reading date.
    if (parsed.isBefore(DateTime.utc(2000))) return null;
    return parsed.toLocal();
  }

  /// Null on any missing required field — a half-parsed row is not a reading.
  static SentimentLayerRow? tryParse(Map<String, dynamic> row) {
    final layer = row['layer'];
    final source = row['source'];
    if (layer is! String || layer.isEmpty) return null;
    if (source is! String || source.isEmpty) return null;
    final weight = _toDouble(row['weight']);
    if (weight == null) return null;
    final detail = row['detail'];
    return SentimentLayerRow(
      layer: layer,
      horizon: row['horizon'] as String? ?? '',
      weight: weight,
      score: _toInt(row['score']),
      alignment: _toInt(row['alignment']),
      measuredAt: _toDate(row['measured_at']),
      source: source,
      sourceUrl: row['source_url'] as String?,
      stale: row['stale'] == true,
      detail: detail is Map ? Map<String, dynamic>.from(detail) : const {},
    );
  }

  /// True when the row exists but carries no measurement. Distinct from a row
  /// that measured 0.
  bool get isUnmeasured => alignment == null;

  /// A measured row that has aged past its layer's refresh cycle.
  bool get isStale => stale;
}

/// All four §5.1 layers as one aggregate.
class SentimentLayers {
  const SentimentLayers(this.rows);

  const SentimentLayers.empty() : rows = const [];

  final List<SentimentLayerRow> rows;

  /// §5.1 weights. Kept here so coverage can be computed without trusting
  /// whatever the rows happen to say.
  static const Map<String, double> expectedWeights = {
    'policy': 35,
    'positioning': 25,
    'gold_fundamentals': 20,
    'market_implied': 20,
  };

  /// Macro-side weight. Positioning is sentiment, not macro, so it is excluded;
  /// `dollar_impulse` and `inflation_impulse` have no §5.1 layer of their own and
  /// are not counted here.
  static const double macroSideWeight = 75;

  /// Fraction of macro-side weight that actually produced an alignment.
  double get macroCoverage {
    var measured = 0.0;
    for (final row in rows) {
      if (row.layer == 'positioning') continue;
      if (row.alignment != null) measured += expectedWeights[row.layer] ?? 0;
    }
    return measured / macroSideWeight;
  }

  /// Fraction of ALL §5.1 weight that produced an alignment.
  double get overallCoverage {
    var measured = 0.0;
    for (final row in rows) {
      if (row.alignment != null) measured += expectedWeights[row.layer] ?? 0;
    }
    return measured / 100;
  }

  SentimentLayerRow? operator [](String layer) {
    for (final row in rows) {
      if (row.layer == layer) return row;
    }
    return null;
  }

  /// True when the row is absent entirely (ingest not built yet).
  bool isMissing(String layer) => this[layer] == null;

  /// True when the row exists but has no measurement.
  bool isUnmeasured(String layer) => this[layer]?.isUnmeasured ?? true;

  /// Alignment only once at least half the macro-side weight is measured.
  /// Below that the reading is surfaced through [MacroState.realYieldImpulse]
  /// and [macroCoverage] instead of driving the macro overlay.
  static const double macroAlignmentThreshold = 0.5;

  /// Map onto the engine's macro input.
  ///
  /// [MacroState.alignment] stays null until [macroCoverage] reaches
  /// [macroAlignmentThreshold]: the scorer vetoes on a negative macro
  /// alignment, and a thin sample must not be able to block a setup.
  MacroState get macro {
    final yields = this['market_implied']?.alignment;
    final alignment =
        macroCoverage >= macroAlignmentThreshold
            ? _weightedAlignment()
            : null;
    return MacroState(
      alignment: alignment,
      realYieldImpulse: yields,
      // No dollar or inflation layer is measured yet. Left null rather than 0,
      // so "not measured" is not mistaken for "neutral".
      dollarImpulse: null,
      inflationImpulse: null,
      policyImpulse: this['policy']?.score,
    );
  }

  /// Sign of the weight-weighted mean of measured macro-side alignments, or
  /// null when nothing is measured. Only reached above the coverage threshold.
  int? _weightedAlignment() {
    var weighted = 0.0;
    var total = 0.0;
    for (final row in rows) {
      if (row.layer == 'positioning') continue;
      final a = row.alignment;
      if (a == null) continue;
      final w = expectedWeights[row.layer] ?? 0;
      weighted += a * w;
      total += w;
    }
    if (total == 0) return null;
    return weighted / total > 0
        ? 1
        : weighted / total < 0
        ? -1
        : 0;
  }

  /// Map onto the engine's sentiment input.
  ///
  /// Positioning is a single complete layer, so its alignment passes through.
  /// §27 Failure 4: a weekly reading past its window sets [SentimentState.cotStale],
  /// which makes the state unavailable rather than letting it act as current.
  SentimentState get sentiment {
    final row = this['positioning'];
    return SentimentState(
      alignment: row?.alignment,
      cotStale: row?.stale ?? true,
    );
  }
}