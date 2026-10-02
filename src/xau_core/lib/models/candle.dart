/// Candle model and validation (expert methodology §1.2 "Market-data
/// normalized schema" + processing rules 1–9).
///
/// EVERY RULE HERE COMES FROM THE EXPERT METHODOLOGY and is deliberately
/// strict, because a silent data defect upstream poisons every indicator,
/// score and veto downstream:
///
///   1. Reject duplicated timestamps.
///   2. Reject bars where `high < max(open, close)` or `low > min(open, close)`.
///   3. Detect missing intervals.
///   4. **Do not forward-fill price bars.**
///   5. Missing bars inside an indicator window mark the indicator `degraded`
///      rather than inventing data.
///   6. All timestamps are UTC.
///   8. Higher timeframes are built only from complete lower-timeframe bars.
///   9. **Never use the current unfinished candle as a confirmed signal candle.**
///
/// Failure 5 (§27 "Using an unfinished candle") and the no-look-ahead rule
/// (MGC R3) are the two most common ways a backtest lies, so both are enforced
/// in code rather than left to convention.
library;

/// A single OHLC bar on a fixed timeframe.
///
/// [isClosed] distinguishes a completed bar from the in-progress one. Only
/// closed bars may feed indicators or produce a signal (rule 9).
class Candle {
  Candle({
    required this.openTime,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume,
    this.isClosed = true,
    this.source = 'unknown',
    this.quality = CandleQuality.primary,
  });

  /// Bar open time, always UTC.
  final DateTime openTime;

  final double open;
  final double high;
  final double low;
  final double close;

  /// Tick volume when the venue provides it. Spot XAUUSD has no true volume,
  /// so this is frequently null and callers must treat it as a participation
  /// *proxy* only, never an absolute.
  final double? volume;

  /// False for the still-forming bar. Never feed these to indicators.
  final bool isClosed;

  final String source;
  final CandleQuality quality;

  /// Bar close time (exclusive) — the next bar's open.
  DateTime get closeTime => openTime;

  bool get isDegraded => quality == CandleQuality.degraded;

  /// Structural validation (processing rule 2). Returns null when valid,
  /// otherwise a human-readable reason for the rejection.
  String? get validationError {
    if (!openTime.isUtc) return 'openTime must be UTC';
    for (final v in [open, high, low, close]) {
      if (v.isNaN || v.isInfinite) return 'non-finite value';
      if (v <= 0) return 'non-positive price';
    }
    if (high < low) return 'high < low';
    if (high < open || high < close) return 'high < max(open, close)';
    if (low > open || low > close) return 'low > min(open, close)';
    return null;
  }

  @override
  String toString() => 'Candle(${openTime.toIso8601String()} '
      'O:$open H:$high L:$low C:$close'
      '${volume != null ? ' V:$volume' : ''}'
      '${isClosed ? '' : ' [OPEN]'})';
}

/// Provenance tier. Higher tiers override lower ones on conflicting facts
/// (MGC §3.9 / METH §1.1 source priority).
enum CandleQuality {
  /// Tier A: an official or primary venue feed.
  primary,

  /// Tier B: an established aggregator or mirror.
  secondary,

  /// Tier C: unofficial, cross-check only. Must not drive a signal alone.
  degraded,
}

/// Why a series failed validation. Surfaced rather than silently dropped
/// (MGC R4: every number must trace to a named source and timestamp).
enum CandleIssue { duplicateTimestamp, invalidOhlc, missingInterval }

/// Result of validating a candle series.
class CandleValidation {
  CandleValidation({
    required this.accepted,
    required this.rejected,
    required this.gaps,
  });

  /// Clean, strictly increasing, valid bars.
  final List<Candle> accepted;

  /// Rejected bars with the reason, for the data-quality note.
  final Map<CandleIssue, List<String>> rejected;

  /// Detected gaps as `[afterOpenTime, beforeOpenTime]` pairs.
  final List<List<DateTime>> gaps;

  bool get isClean => rejected.isEmpty && gaps.isEmpty;

  /// One-line summary for `data_health` / the data-quality note.
  String get summary {
    final parts = <String>['${accepted.length} bars'];
    if (rejected.isNotEmpty) parts.add('${rejected.values.fold(0, (a, b) => a + b.length)} rejected');
    if (gaps.isNotEmpty) parts.add('${gaps.length} gap(s)');
    return parts.join(', ');
  }
}

/// Validates a candle series per processing rules 1–3.
///
/// [interval] is the bar duration; a gap is any missing interval between two
/// accepted bars. Rejected bars are reported, never silently dropped.
CandleValidation validateCandles(List<Candle> candles, Duration interval) {
  if (candles.isEmpty) {
    return CandleValidation(accepted: const [], rejected: const {}, gaps: const []);
  }

  final sorted = [...candles]..sort((a, b) => a.openTime.compareTo(b.openTime));
  final accepted = <Candle>[];
  final rejected = <CandleIssue, List<String>>{};
  final gaps = <List<DateTime>>[];
  final seen = <DateTime>{};

  void reject(CandleIssue issue, String why) {
    rejected.putIfAbsent(issue, () => <String>[]).add(why);
  }

  DateTime? prev;
  for (final c in sorted) {
    if (!seen.add(c.openTime)) {
      reject(CandleIssue.duplicateTimestamp, 'duplicate ${c.openTime.toIso8601String()}');
      continue;
    }
    final err = c.validationError;
    if (err != null) {
      reject(CandleIssue.invalidOhlc, '${c.openTime.toIso8601String()}: $err');
      continue;
    }
    if (prev != null) {
      final expected = prev.add(interval);
      final delta = c.openTime.difference(prev).inMilliseconds;
      if (delta > interval.inMilliseconds) {
        gaps.add([expected, c.openTime]);
      }
    }
    accepted.add(c);
    prev = c.openTime;
  }

  return CandleValidation(accepted: accepted, rejected: rejected, gaps: gaps);
}

/// Drops the trailing still-forming bar (rule 9).
///
/// The most recent bar on any live feed is open until the timeframe closes;
/// treating it as confirmed is look-ahead bias in a backtest and a repainting
/// bug live.
List<Candle> closedOnly(List<Candle> candles) =>
    candles.where((c) => c.isClosed).toList(growable: false);

/// Resamples closed lower-timeframe bars into a higher timeframe.
///
/// Only complete source bars contribute (rule 8): a higher bar is emitted
/// solely when the expected number of lower bars is present, so a partial
/// higher bar never appears as if it were confirmed.
///
/// [sourceInterval] is the duration of [lower]'s bars. It is required rather
/// than inferred, because inference from `b[1] - b[0]` silently breaks on a
/// series with a single bar or a leading gap.
List<Candle> resample(List<Candle> lower, Duration sourceInterval, Duration target) {
  if (lower.isEmpty) return const [];
  if (sourceInterval.inMilliseconds <= 0) return const [];
  if (target.inMilliseconds <= sourceInterval.inMilliseconds) {
    throw ArgumentError('target must be longer than source interval');
  }

  final stepMs = target.inMilliseconds;
  final expected = stepMs ~/ sourceInterval.inMilliseconds;
  final out = <Candle>[];

  DateTime bucketOf(DateTime t) => DateTime.fromMillisecondsSinceEpoch(
        (t.millisecondsSinceEpoch ~/ stepMs) * stepMs,
        isUtc: true,
      );

  final buckets = <DateTime, List<Candle>>{};
  for (final c in lower) {
    if (!c.isClosed) continue; // rule 8 + rule 9
    buckets.putIfAbsent(bucketOf(c.openTime), () => <Candle>[]).add(c);
  }

  final keys = buckets.keys.toList()..sort();
  for (final k in keys) {
    final group = buckets[k]!..sort((a, b) => a.openTime.compareTo(b.openTime));
    // Require a complete set of source bars before emitting (rule 8).
    if (group.length < expected) continue;
    var high = double.negativeInfinity;
    var low = double.infinity;
    var volume = 0.0;
    var hasVolume = true;
    for (final c in group) {
      if (c.high > high) high = c.high;
      if (c.low < low) low = c.low;
      final v = c.volume;
      if (v != null) {
        volume += v;
      } else {
        hasVolume = false;
      }
    }
    out.add(Candle(
      openTime: k,
      open: group.first.open,
      high: high,
      low: low,
      close: group.last.close,
      volume: hasVolume ? volume : null,
      source: group.first.source,
      quality: group.any((c) => c.isDegraded)
          ? CandleQuality.degraded
          : group.first.quality,
    ));
  }
  return out;
}