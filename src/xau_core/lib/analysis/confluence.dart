/// Multi-timeframe confluence scoring and hard vetoes (methodology §8, §9, §15,
/// §16; MGC §9).
///
/// Two rules from the expert documents shape the whole design:
///
///   * **NO_TRADE is a first-class outcome, not an error.** Most scans end in
///     no trade, and the engine must be able to say exactly *why* with a
///     reason code instead of emitting a weak signal.
///   * **Indicators confirm, they never initiate.** Nothing here invents a
///     direction. [ConfluenceInput.direction] must already be established by
///     structure/context elsewhere; scoring only measures how well the
///     indicators support it.
///
/// All thresholds are `[INIT]` hypotheses from the methodology and must be
/// calibrated by backtest/walk-forward before their grades are trusted
/// (methodology §14, §25, §26).
library;

/// Timeframes, ordered from fastest to slowest.
enum Tf { m5, m15, m30, h1 }

/// Side of the market. XV is a directional assistant, so this is deliberately
/// two-valued: "neutral" is represented by a NO_TRADE verdict, never by a
/// neutral signal.
enum Side { long, short }

/// Quality grade (MGC §9.3). `aPlus` is the only grade that may be published
/// as a fresh signal; `b` requires the strongest additional confluence
/// because MGC forbids publishing B-grade against a counter-bias.
enum Grade { aPlus, a, b, insufficient }

/// Outcome of a scan.
enum Verdict { long, short, noTrade }

/// Human-readable reason codes. Every NO_TRADE carries at least one, and every
/// published signal carries the positives that justified it.
enum ReasonCode {
  // Positives (MGC V-list inverted: what made the setup eligible)
  h1TrendAligned,
  h1RsiFavorable,
  h1MacdAligned,
  m30StructureAligned,
  m15PullbackToZone,
  m15CandleConfirmation,
  m5TriggerPresent,
  adxConfirmsTrend,
  volatilitySuitable,
  macroSupports,
  sentimentSupports,

  // Vetoes
  v1Blackout,
  v2SpreadUnevaluated,
  v3DataStale,
  v4VolatilityExtreme,
  v5PoorRewardRisk,
  v6DirectionConflict,
  v7DailyLimit,
  v8SessionClosed,
  v9Duplicate,
  v10ConfirmationLow,
  v11H1Neutral,
  v12LowConfluence,
  v13BadStopDistance,
  v14RsiExhausted,
  v15ExtendedEntry,
}

/// Explicit spread availability, per the ratified option (a) rule
/// (`docs/expert-integration-spec.md` §1a, methodology §1.2).
///
/// A genuine spread is execution-venue ask minus bid. When no genuine
/// bid/ask feed exists the engine must say so and leave the spread vetoes
/// UNEVALUATED — never substitute a cross-source price difference.
enum SpreadStatus {
  /// Genuine venue bid/ask measured.
  available,

  /// No trustworthy measurement exists. `UNAVAILABLE` does not mean zero and
  /// does not mean normal; the spread vetoes are then UNEVALUATED.
  unavailable,
}

/// Per-timeframe technical state, as observed by the caller from closed bars.
class TimeframeState {
  const TimeframeState({
    required this.timeframe,
    this.close,
    this.ema20,
    this.ema50,
    this.ema200,
    this.rsi14,
    this.macdHistogram,
    this.adx14,
    this.plusDi,
    this.minusDi,
    this.atr,
    this.atrPercentile,
    this.swingLow,
    this.swingHigh,
    this.hasEngulfing = false,
    this.hasBreakRetest = false,
    this.hasRejectionWick = false,
    this.hasMicroStructureShift = false,
    this.hasCompressionBreakout = false,
    this.isTightRange = false,
  });

  final Tf timeframe;

  /// Latest close of the most recent **closed** bar.
  final double? close;
  final double? ema20;
  final double? ema50;
  final double? ema200;
  final double? rsi14;
  final double? macdHistogram;
  final double? adx14;
  final double? plusDi;
  final double? minusDi;
  final double? atr;

  /// ATR percentile within its own recent history; null when unknown.
  final double? atrPercentile;

  /// Most recent confirmed swing levels.
  final double? swingLow;
  final double? swingHigh;

  // §8.4 candle-pattern candidates, all of which require a *close* beyond the
  // level. "Do not enter merely because a candle touches a level."
  final bool hasEngulfing;
  final bool hasBreakRetest;
  final bool hasRejectionWick;
  final bool hasMicroStructureShift;
  final bool hasCompressionBreakout;

  /// Range/tight-range condition.
  final bool isTightRange;

  bool get hasMinimumData =>
      close != null && ema20 != null && ema50 != null && ema200 != null;

  bool get hasAnyConfluencePattern =>
      hasEngulfing ||
      hasBreakRetest ||
      hasRejectionWick ||
      hasMicroStructureShift ||
      hasCompressionBreakout;
}

/// Macro regime from the slow-moving stack (§5). Null when unavailable, and
/// callers must treat null as "not supportive" rather than "neutral-positive".
class MacroState {
  const MacroState({this.alignment, this.realYieldImpulse, this.dollarImpulse, this.inflationImpulse, this.policyImpulse});

  /// -1 strongly opposes, 0 neutral/mixed, +1 supports.
  final int? alignment;
  final int? realYieldImpulse;
  final int? dollarImpulse;
  final int? inflationImpulse;
  final int? policyImpulse;

  bool get isAvailable => alignment != null;
}

/// Weekly positioning (§6). Can only ever adjust confidence — never create an
/// entry (methodology §9 Rule 4).
class SentimentState {
  const SentimentState({this.alignment, this.cotStale = false});

  final int? alignment;

  /// COT refreshes weekly; a stale reading must not be treated as current
  /// (methodology §27 Failure 4).
  final bool cotStale;

  bool get isAvailable => alignment != null && !cotStale;
}

/// Every input the scorer needs. Deliberately explicit — no hidden globals, no
/// clock reads, so a scan is fully reproducible from its inputs.
class ConfluenceInput {
  const ConfluenceInput({
    required this.direction,
    required this.h1,
    required this.m30,
    required this.m15,
    required this.m5,
    required this.atr5m,
    this.macro,
    this.sentiment,
    this.spreadStatus = SpreadStatus.unavailable,
    this.blackout = false,
    this.dataStale = false,
    this.sessionOpen = true,
    this.signalsEmittedToday = 0,
    this.maxSignalsPerDay = 4,
    this.duplicate = false,
    this.stopDistanceAtr,
    this.tp2R,
    this.currentPrice,
    this.blockedByLevel = false,
  });

  /// Direction already established by structure/context. The scorer measures
  /// support for it; it never chooses it.
  final Side direction;

  final TimeframeState h1;
  final TimeframeState m30;
  final TimeframeState m15;
  final TimeframeState m5;

  /// ATR(5m), the volatility unit for stop placement.
  final double? atr5m;

  final MacroState? macro;
  final SentimentState? sentiment;
  final SpreadStatus spreadStatus;

  final bool blackout;
  final bool dataStale;
  final bool sessionOpen;
  final int signalsEmittedToday;
  final int maxSignalsPerDay;
  final bool duplicate;

  /// Stop distance in ATR units, for the V13 clamp check.
  final double? stopDistanceAtr;

  /// TP2 reward-to-risk ratio, for the R7 floor check.
  final double? tp2R;

  final double? currentPrice;

  /// A major opposing level sits on the path to target.
  final bool blockedByLevel;

  TimeframeState stateFor(Tf tf) {
    switch (tf) {
      case Tf.h1:
        return h1;
      case Tf.m30:
        return m30;
      case Tf.m15:
        return m15;
      case Tf.m5:
        return m5;
    }
  }
}

/// Result of a scan: verdict, reason codes, and the auditable numbers behind it.
class ConfluenceResult {
  const ConfluenceResult({
    required this.verdict,
    required this.grade,
    required this.reasonCodes,
    required this.technicalScore,
    required this.finalScore,
    required this.macroAlignment,
    required this.sentimentAlignment,
    required this.conflictPenalty,
    required this.spreadStatus,
    required this.vetoed,
  });

  final Verdict verdict;
  final Grade grade;
  final List<ReasonCode> reasonCodes;

  /// 0–12 directional technical score (§8.2).
  final int technicalScore;

  /// technical + 2×macro + sentiment − conflict penalty (§8.3).
  final double finalScore;

  final int? macroAlignment;
  final int? sentimentAlignment;
  final int conflictPenalty;

  final SpreadStatus spreadStatus;

  /// Codes that blocked publication, in order.
  final List<ReasonCode> vetoed;

  bool get isTrade => verdict != Verdict.noTrade;

  /// Convenience for tests and logging.
  bool has(ReasonCode c) => reasonCodes.contains(c);
}

/// Technical thresholds. Every value here is an `[INIT]` hypothesis from the
/// methodology, not a validated constant.
class Thresholds {
  const Thresholds({
    this.minTechnical = 8,
    this.minFinal = 9.0,
    this.rsiPreferredLow = 52,
    this.rsiPreferredHigh = 68,
    this.rsiExhaustedLong = 75,
    this.rsiExhaustedShort = 25,
    this.adxTrending = 20,
    this.atrPercentileLow = 25,
    this.atrPercentileHigh = 90,
    this.atrPercentileExtreme = 95,
    this.stopMinAtr = 0.80,
    this.stopMaxAtr = 1.80,
    this.tp2FloorR = 1.8,
    this.maxDailySignals = 4,
  });

  final int minTechnical;
  final double minFinal;
  final int rsiPreferredLow;
  final int rsiPreferredHigh;
  final int rsiExhaustedLong;
  final int rsiExhaustedShort;
  final int adxTrending;
  final double atrPercentileLow;
  final double atrPercentileHigh;
  final double atrPercentileExtreme;
  final double stopMinAtr;
  final double stopMaxAtr;
  final double tp2FloorR;
  final int maxDailySignals;

  Thresholds copyWith({int? maxDailySignals}) => Thresholds(
        minTechnical: minTechnical,
        minFinal: minFinal,
        rsiPreferredLow: rsiPreferredLow,
        rsiPreferredHigh: rsiPreferredHigh,
        rsiExhaustedLong: rsiExhaustedLong,
        rsiExhaustedShort: rsiExhaustedShort,
        adxTrending: adxTrending,
        atrPercentileLow: atrPercentileLow,
        atrPercentileHigh: atrPercentileHigh,
        atrPercentileExtreme: atrPercentileExtreme,
        stopMinAtr: stopMinAtr,
        stopMaxAtr: stopMaxAtr,
        tp2FloorR: tp2FloorR,
        maxDailySignals: maxDailySignals ?? this.maxDailySignals,
      );
}

/// Scores the confluence and enforces every veto.
///
/// Ordering follows methodology §8.1 exactly: data validity, event lock,
/// volatility, higher-timeframe regime, structure, setup, trigger, then
/// score. Evaluating the score before the vetoes would waste work and risk
/// reporting a "high score" for a setup that was never tradable.
class ConfluenceEngine {
  const ConfluenceEngine([this.thresholds = const Thresholds()]);

  final Thresholds thresholds;

  ConfluenceResult evaluate(ConfluenceInput input) {
    final reasons = <ReasonCode>[];
    final vetoes = <ReasonCode>[];
    final dir = input.direction;
    final bull = dir == Side.long;

    void veto(ReasonCode c) => vetoes.add(c);
    void credit(ReasonCode c) => reasons.add(c);

    // ---- 2. Data validity (V3) ------------------------------------------
    if (input.dataStale || !input.h1.hasMinimumData) veto(ReasonCode.v3DataStale);

    // ---- 3. Event lock (V1) ---------------------------------------------
    if (input.blackout) veto(ReasonCode.v1Blackout);

    // ---- 4. Spread status: report, never proxy (V2) -----------------------
    if (input.spreadStatus == SpreadStatus.unavailable) {
      // Explicitly UNEVALUATED: recorded as a data-quality note, and the
      // vetoes below must NOT fire. A missing measurement is not a pass.
      reasons.add(ReasonCode.v2SpreadUnevaluated);
    }

    // ---- 5. Session (V8) -------------------------------------------------
    if (!input.sessionOpen) veto(ReasonCode.v8SessionClosed);

    // ---- 6. Daily limit (V7) ---------------------------------------------
    if (input.signalsEmittedToday >= (input.maxSignalsPerDay == 0 ? thresholds.maxDailySignals : input.maxSignalsPerDay)) {
      veto(ReasonCode.v7DailyLimit);
    }
    if (input.duplicate) veto(ReasonCode.v9Duplicate);

    // ---- 7. Volatility (V4) ----------------------------------------------
    final atrPct = input.m5.atrPercentile;
    if (atrPct != null && atrPct >= thresholds.atrPercentileExtreme) {
      veto(ReasonCode.v4VolatilityExtreme);
    }

    // ---- 8. 1H regime (V11) ----------------------------------------------
    var technical = 0;

    // EMA alignment (0-2)
    final emaScore = _emaAlignmentScore(input.h1, bull);
    if (emaScore == 2) {
      credit(ReasonCode.h1TrendAligned);
    }
    technical += emaScore;

    // H1 RSI regime (0-1). Exhaustion at the extremes blocks a fresh entry.
    final h1Rsi = input.h1.rsi14;
    if (h1Rsi != null) {
      if (bull && h1Rsi >= thresholds.rsiExhaustedLong) {
        veto(ReasonCode.v14RsiExhausted);
      } else if (!bull && h1Rsi <= thresholds.rsiExhaustedShort) {
        veto(ReasonCode.v14RsiExhausted);
      } else {
        // The preferred zone is side-aware: 52–68 for a long, and its mirror
        // 32–48 for a short. Reading a short's preferred zone as 52–68 would
        // make the symmetric short case unscoreable.
        final lo = bull ? thresholds.rsiPreferredLow : 100.0 - thresholds.rsiPreferredHigh;
        final hi = bull ? thresholds.rsiPreferredHigh : 100.0 - thresholds.rsiPreferredLow;
        if (h1Rsi >= lo && h1Rsi <= hi) {
          technical += 1;
          credit(ReasonCode.h1RsiFavorable);
        }
      }
    }

    // H1 MACD regime (0-1)
    if (_macdAligned(input.h1, bull)) {
      technical += 1;
      credit(ReasonCode.h1MacdAligned);
    }

    // 30m structure (0-2)
    final structure = _structureScore(input.m30, bull);
    if (structure > 0) credit(ReasonCode.m30StructureAligned);
    technical += structure;

    // 15m setup (0-2): pullback to zone plus a closing confirmation pattern
    if (_pullbackToZone(input.m15, bull)) {
      credit(ReasonCode.m15PullbackToZone);
      technical += 1;
      if (input.m15.hasAnyConfluencePattern) {
        technical += 1;
        credit(ReasonCode.m15CandleConfirmation);
      }
    }

    // 5m trigger (0-2)
    if (_m5Trigger(input.m5, bull)) {
      credit(ReasonCode.m5TriggerPresent);
      technical += 2;
    }

    // ADX / trend strength (0-1)
    final adxV = input.m30.adx14 ?? input.m15.adx14;
    final diFav = bull ? (input.m30.plusDi ?? 0) > (input.m30.minusDi ?? 0) : (input.m30.minusDi ?? 0) > (input.m30.plusDi ?? 0);
    if (adxV != null && adxV >= thresholds.adxTrending && diFav) {
      technical += 1;
      credit(ReasonCode.adxConfirmsTrend);
    }

    // Volatility suitability (0-1)
    if (atrPct != null && atrPct >= thresholds.atrPercentileLow && atrPct < thresholds.atrPercentileHigh) {
      technical += 1;
      credit(ReasonCode.volatilitySuitable);
    }

    // ---- 9. Overextended entry (R: prefer pullback) -----------------------
    if (_extendedEntry(input.m15, bull)) veto(ReasonCode.v15ExtendedEntry);

    // ---- 10. Confirmation floor (V10) -----------------------------------
    final confirmations = technical >= 0 ? _confirmCount(reasons) : 0;
    if (technical > 0 && confirmations < 2) veto(ReasonCode.v10ConfirmationLow);

    // ---- 11. Stop distance (V13) ----------------------------------------
    final stopAtr = input.stopDistanceAtr;
    if (stopAtr != null && (stopAtr < thresholds.stopMinAtr || stopAtr > thresholds.stopMaxAtr)) {
      veto(ReasonCode.v13BadStopDistance);
    }

    // ---- 12. Reward-to-risk (V5 / R7) -----------------------------------
    final r = input.tp2R;
    if (r != null && r < thresholds.tp2FloorR) veto(ReasonCode.v5PoorRewardRisk);
    if (input.blockedByLevel) veto(ReasonCode.v5PoorRewardRisk);

    // ---- 13. Macro / sentiment overlay (§8.3) ---------------------------
    final macro = input.macro?.alignment;
    final sentiment = input.sentiment?.isAvailable == true ? input.sentiment!.alignment : null;
    var conflictPenalty = 0;

    if (macro != null) {
      if (macro > 0) credit(ReasonCode.macroSupports);
      if (macro < 0) {
        conflictPenalty += 1;
        veto(ReasonCode.v6DirectionConflict);
      }
    }
    if (sentiment != null && sentiment > 0) credit(ReasonCode.sentimentSupports);
    if (sentiment != null && sentiment < 0) {
      conflictPenalty += 1;
      // Slow sentiment never reverses a trade, it only reduces confidence —
      // so this is a penalty, not a veto.
    }

    final finalScore = technical + 2.0 * (macro ?? 0) + (sentiment ?? 0) - conflictPenalty;

    // ---- 14. Technical floor (V12) --------------------------------------
    if (technical < thresholds.minTechnical) veto(ReasonCode.v12LowConfluence);

    // ---- 15. Final score floor ------------------------------------------
    if (finalScore < thresholds.minFinal) veto(ReasonCode.v12LowConfluence);

    // ---- Verdict ---------------------------------------------------------
    final noTrade = vetoes.isNotEmpty;
    final grade = noTrade ? Grade.insufficient : _gradeFor(technical, finalScore, input);

    return ConfluenceResult(
      verdict: noTrade ? Verdict.noTrade : (bull ? Verdict.long : Verdict.short),
      grade: grade,
      reasonCodes: [...reasons, ...vetoes],
      technicalScore: technical,
      finalScore: finalScore,
      macroAlignment: macro,
      sentimentAlignment: sentiment,
      conflictPenalty: conflictPenalty,
      spreadStatus: input.spreadStatus,
      vetoed: vetoes,
    );
  }

  int _confirmCount(List<ReasonCode> reasons) => reasons
      .where((c) => const {
            ReasonCode.h1TrendAligned,
            ReasonCode.h1RsiFavorable,
            ReasonCode.h1MacdAligned,
            ReasonCode.m30StructureAligned,
            ReasonCode.m15PullbackToZone,
            ReasonCode.m15CandleConfirmation,
            ReasonCode.m5TriggerPresent,
            ReasonCode.adxConfirmsTrend,
          }.contains(c))
      .length;

  Grade _gradeFor(int technical, double finalScore, ConfluenceInput input) {
    // A+ requires the strongest technical picture AND no unresolved conflict.
    if (technical >= 11 && finalScore >= 11 && input.macro?.alignment != -1) return Grade.aPlus;
    if (technical >= 10 && finalScore >= 10) return Grade.a;
    return Grade.b;
  }

  int _emaAlignmentScore(TimeframeState s, bool bull) {
    final c = s.close, e20 = s.ema20, e50 = s.ema50, e200 = s.ema200;
    if (c == null || e20 == null || e50 == null || e200 == null) return 0;
    final clean = bull ? (c > e20 && e20 > e50 && e50 > e200) : (c < e20 && e20 < e50 && e50 < e200);
    if (clean) return 2;
    final sideOf200 = bull ? c > e200 : c < e200;
    return sideOf200 ? 1 : 0;
  }

  bool _macdAligned(TimeframeState s, bool bull) {
    final h = s.macdHistogram;
    if (h == null) return false;
    return bull ? h > 0 : h < 0;
  }

  int _structureScore(TimeframeState s, bool bull) {
    // Structure from confirmed swing relationships, not indicator values.
    final c = s.close, hi = s.swingHigh, lo = s.swingLow;
    if (c == null || hi == null || lo == null) return 0;
    if (bull) {
      if (c > hi) return 2; // broke to a new confirmed high
      if (c > lo) return 1; // holding above a confirmed low
      return 0;
    } else {
      if (c < lo) return 2;
      if (c < hi) return 1;
      return 0;
    }
  }

  bool _pullbackToZone(TimeframeState s, bool bull) {
    // Price must be in the EMA20-50 zone (or at the recent swing) rather than
    // extended. Confirms the "wait for a pullback, do not chase" rule.
    final c = s.close, e20 = s.ema20, e50 = s.ema50;
    if (c == null || e20 == null || e50 == null) return false;
    final hiZone = e20 > e50 ? e20 : e50;
    final loZone = e20 > e50 ? e50 : e20;
    return c >= loZone && c <= hiZone;
  }

  bool _m5Trigger(TimeframeState s, bool bull) {
    return s.hasAnyConfluencePattern;
  }

  bool _extendedEntry(TimeframeState s, bool bull) {
    // A candle that has already closed far beyond the setup level is a chase,
    // not a setup. Uses ATR when available, else a conservative 2% band.
    final c = s.close, e20 = s.ema20, atr = s.atr;
    if (c == null || e20 == null) return false;
    final ref = atr != null && atr > 0 ? atr : (c * 0.02);
    final dist = (c - e20).abs();
    if (dist <= ref) return false;
    return bull ? c > e20 : c < e20;
  }
}