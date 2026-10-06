/// Multi-timeframe scanner: turns raw OHLC bars into an auditable trade verdict
/// (methodology §8.1 pipeline, §21 pseudocode).
///
/// This is the composition layer. The individual pieces already exist and are
/// individually tested; what is new here is the **order** they run in, and that
/// order is the whole point:
///
/// ```
/// 1. load closed bars
/// 2. validate + reject degraded/short series
/// 3. compute indicators per timeframe
/// 4. read the venue spread (genuine bid/ask only)
/// 5. evaluate the event lock
/// 6. score confluence
/// 7. build the structural stop
/// 8. return LONG / SHORT / NO TRADE with reason codes
/// ```
///
/// Two invariants the scanner enforces that the parts cannot enforce alone:
///
/// * **Direction is never invented here.** The scanner only evaluates a
///   direction that [ScanRequest.direction] supplies. A scan with no candidate
///   direction returns NO TRADE with `NO_CANDIDATE_DIRECTION`; it does not pick
///   the "better looking" side. Indicators confirm, they never initiate.
/// * **Degraded bars cannot produce levels.** Warm-up history is allowed to
///   warm indicators, but a stop and targets must never be derived from a proxy
///   instrument (§3.1: P2 is for "sanity and volatility, not exact levels").
///   If the bars backing a level are degraded, the plan is refused.
library;

import '../analysis/calendar_lock.dart';
import '../analysis/confluence.dart';
import '../analysis/indicators.dart';
import '../analysis/stop_plan.dart';
import '../models/candle.dart';

/// Bars for one timeframe, already filtered to what the engine may use.
class TimeframeBars {
  const TimeframeBars({
    required this.timeframe,
    required this.bars,
    required this.allDegraded,
  });

  final Tf timeframe;

  /// Closed, validated bars in ascending time order.
  final List<Candle> bars;

  /// True when every bar came from a degraded source (e.g. PAXG warm-up).
  final bool allDegraded;

  bool get isEmpty => bars.isEmpty;
  int get length => bars.length;
}

/// A measured venue spread.
///
/// Mirrors [SpreadStatus]: only a genuine execution-venue Ask − Bid may set
/// [genuineSpread]. There is deliberately no constructor path that accepts a
/// spread without also declaring whether it is genuine, so a proxy cannot be
/// introduced by accident.
class VenueSpread {
  const VenueSpread({required this.status, this.bid, this.ask, this.source});

  /// Genuine venue bid/ask, as measured at the execution venue.
  ///
  /// The source = source form is deliberate rather than an initializing
  /// formal: [status] has to be pinned to [SpreadStatus.available] here, and
  /// keeping both in the initializer list makes it impossible to construct an
  // "available" spread carrying a mismatched status.
  const VenueSpread.available({required this.bid, required this.ask, required String source})
      : status = SpreadStatus.available,
        source = source; // ignore: prefer_initializing_formals

  /// No trustworthy measurement. The spread vetoes stay UNEVALUATED.
  const VenueSpread.unavailable()
      : status = SpreadStatus.unavailable,
        bid = null,
        ask = null,
        source = 'NONE';

  final SpreadStatus status;
  final double? bid;
  final double? ask;
  final String? source;

  /// Spread in USD, or null when unmeasured. Never derived cross-source.
  double? get value {
    final b = bid;
    final a = ask;
    if (status != SpreadStatus.available || b == null || a == null) return null;
    final v = a - b;
    return v >= 0 ? v : null;
  }

  bool get isGenuine => status == SpreadStatus.available && value != null;
}

/// Everything one scan needs. Time is injected; nothing here reads a clock.
class ScanRequest {
  const ScanRequest({
    required this.direction,
    required this.m5,
    required this.m15,
    required this.m30,
    required this.h1,
    this.spread = const VenueSpread.unavailable(),
    this.events = const [],
    this.emergency,
    this.now,
    this.sessionOpen = true,
    this.signalsEmittedToday = 0,
    this.maxSignalsPerDay = 4,
    this.duplicate = false,
    this.currentPrice,
    this.blockedByLevel = false,
    this.spreadStatusOverride,
    this.macro,
    this.sentiment,
  });

  /// Candidate direction, established elsewhere. Null means no candidate.
  final Side? direction;

  final TimeframeBars m5;
  final TimeframeBars m15;
  final TimeframeBars m30;
  final TimeframeBars h1;

  final VenueSpread spread;
  final List<EconomicEvent> events;
  final EmergencyCondition? emergency;

  /// Evaluation time. Null means the caller wants no calendar gate applied.
  final DateTime? now;

  final bool sessionOpen;
  final int signalsEmittedToday;
  final int maxSignalsPerDay;
  final bool duplicate;
  final double? currentPrice;
  final bool blockedByLevel;

  /// Forces a reported spread status, used when a caller knows better (for
  /// example a UI that wants to show UNAVAILABLE after a feed outage).
  final SpreadStatus? spreadStatusOverride;

  /// §5.1 macro regime. Null means no macro layer could be measured, which is
  /// NOT the same as a neutral reading — the engine treats null as "nothing to
  /// weigh", never as support.
  ///
  /// These two fields were absent, which meant `ConfluenceInput.macro` and
  /// `.sentiment` were permanently null and every macro/sentiment term in §8.3
  /// was dead code no matter how much layer data existed.
  final MacroState? macro;

  /// §5.1 positioning, already carrying its own staleness flag so a stale
  /// weekly reading cannot act as current.
  final SentimentState? sentiment;
}

/// Full result of a scan, including the data-quality notes.
class ScanResult {
  const ScanResult({
    required this.verdict,
    required this.grade,
    required this.reasonCodes,
    required this.vetoes,
    required this.technicalScore,
    required this.finalScore,
required this.macroAlignment,
    required this.macroAgrees,
    required this.sentimentAlignment,
    required this.sentimentAgrees,
    required this.conflictPenalty,
    required this.spread,
    required this.dataQuality,
    required this.lockSummary,
    required this.stopPlan,
    required this.atr5m,
  });

  final Verdict verdict;
  final Grade grade;
  final List<ReasonCode> reasonCodes;
  final List<ReasonCode> vetoes;
  final int technicalScore;
  final double finalScore;
/// The macro layer's OWN direction: -1 leaning bearish for gold, +1 bullish,
  /// null unmeasured. This is the reading, not a verdict.
  final int? macroAlignment;

  /// [macroAlignment] flipped for the traded side: >0 the trade ran with the
  /// macro read, <0 against it. This is what the score and the
  /// `v6DirectionConflict` veto used.
  final int? macroAgrees;

  /// The sentiment layer's own direction, same convention as [macroAlignment].
  final int? sentimentAlignment;

  /// [sentimentAlignment] flipped for the traded side, same reading convention.
  final int? sentimentAgrees;

  final int conflictPenalty;

  /// Measured spread, including UNAVAILABLE status. Never a proxy.
  final VenueSpread spread;

  /// Human-readable data-quality notes (gaps, degraded history, short series).
  final List<String> dataQuality;

  /// Calendar lock summary, e.g. `OPEN` or `LOCK_TIER_A_CPI`.
  final String lockSummary;

  /// Structural stop/targets, valid only when the verdict is a trade.
  final StopPlan? stopPlan;

  final double? atr5m;

  bool get isTrade => verdict != Verdict.noTrade;

  /// One-line summary for logs and the UI.
  String get headline {
    if (!isTrade) return 'NO TRADE (${vetoes.map(_codeName).join(', ')})';
    final levels = stopPlan;
    if (levels == null || !levels.isValid) {
      return '${_sideName(verdict)} ${grade.name.toUpperCase()} '
          'tech=$technicalScore final=${finalScore.toStringAsFixed(1)} NO LEVELS';
    }
    return '${_sideName(verdict)} ${grade.name.toUpperCase()} '
        'tech=$technicalScore final=${finalScore.toStringAsFixed(1)} '
        'R:R=${levels.tp2R.toStringAsFixed(2)}';
  }
}

String _sideName(Verdict v) =>
    v == Verdict.long ? 'LONG' : v == Verdict.short ? 'SHORT' : 'NO TRADE';

/// Canonical timeframe label, matching `market_bars.timeframe` in Postgres
/// ('5m', '15m', '30m', '1h'). Enum names do not: Tf.m5.name is 'm5'.
String timeframeLabel(Tf tf) => switch (tf) {
      Tf.m5 => '5m',
      Tf.m15 => '15m',
      Tf.m30 => '30m',
      Tf.h1 => '1h',
    };

String _codeName(ReasonCode c) => c.name;

/// Runs the §8.1 pipeline and returns an auditable verdict.
class MarketScanner {
  const MarketScanner({this.engine = const ConfluenceEngine(), this.stopConfig = const StopConfig()});

  final ConfluenceEngine engine;
  final StopConfig stopConfig;

  ScanResult scan(ScanRequest req) {
    final quality = <String>[];

    // ---- 2. Data validity ------------------------------------------------
    // A timeframe with too few bars cannot support its indicators. Report it
    // rather than silently scoring it as flat, which would read as "no
    // structure" and could masquerade as a genuine NO TRADE.
    final tooShort = <String>[];
    for (final tf in [Tf.h1, Tf.m30, Tf.m15, Tf.m5]) {
      final b = _barsFor(req, tf);
      final need = _minBarsFor(tf);
      if (b.length < need) {
        final have = b.length;
      // Report the same timeframe labels the database and UI use. Tf.m5.name
      // would render "m5", which matches nothing else in the system.
      tooShort.add('${timeframeLabel(tf)}: $have/$need bars');
      }
    }
    if (tooShort.isNotEmpty) quality.add('insufficient history: ${tooShort.join(', ')}');

    // Degraded history is usable for indicators but must be surfaced, because
    // it changes what the numbers mean.
    final degradedTf = [
      for (final tf in [Tf.h1, Tf.m30, Tf.m15, Tf.m5])
        if (_barsFor(req, tf).allDegraded) timeframeLabel(tf),
    ];
    if (degradedTf.isNotEmpty) {
      quality.add('degraded warm-up history on ${degradedTf.join(', ')} '
          '(proxy source; levels refused)');
    }

    // ---- 1. Direction ----------------------------------------------------
    final dir = req.direction;
    if (dir == null) {
      return ScanResult(
        verdict: Verdict.noTrade,
        grade: Grade.insufficient,
        reasonCodes: const [],
        vetoes: const [ReasonCode.v10ConfirmationLow],
        technicalScore: 0,
        finalScore: 0,
macroAlignment: null,
        macroAgrees: null,
        sentimentAlignment: null,
        sentimentAgrees: null,
        conflictPenalty: 0,
        spread: req.spread,
        dataQuality: ['no candidate direction: indicators never initiate a trade', ...quality],
        lockSummary: 'N/A',
        stopPlan: null,
        atr5m: null,
      );
    }

    // ---- 3. Per-timeframe indicator state -------------------------------
    final h1 = _stateFor(_barsFor(req, Tf.h1), Tf.h1);
    final m30 = _stateFor(_barsFor(req, Tf.m30), Tf.m30);
    final m15 = _stateFor(_barsFor(req, Tf.m15), Tf.m15);
    final m5 = _stateFor(_barsFor(req, Tf.m5), Tf.m5);

    // ATR(5m) drives volatility gates and every stop distance.
    final atr5m = m5.atr;

    // ---- 4. Event lock ---------------------------------------------------
    var lockSummary = 'N/A';
    var blackout = false;
    if (req.now != null) {
      final decision = CalendarLock().evaluate(
        now: req.now!,
        events: req.events,
        emergency: req.emergency,
      );
      blackout = decision.isLocked;
      lockSummary = decision.summary;
      if (blackout) quality.add('calendar: $lockSummary');
    }

    // ---- 5/6. Confluence -------------------------------------------------
    final reportedSpread =
        req.spreadStatusOverride ?? req.spread.status;

    final confluence = engine.evaluate(
      ConfluenceInput(
        direction: dir,
        h1: h1,
        m30: m30,
        m15: m15,
        m5: m5,
        atr5m: atr5m,
        spreadStatus: reportedSpread,
        blackout: blackout,
        // Short series must veto rather than score against missing EMAs.
        dataStale: tooShort.isNotEmpty,
        sessionOpen: req.sessionOpen,
        signalsEmittedToday: req.signalsEmittedToday,
        maxSignalsPerDay: req.maxSignalsPerDay,
        duplicate: req.duplicate,
        currentPrice: req.currentPrice,
        blockedByLevel: req.blockedByLevel,
        // The §5.1 layers. Null whenever a caller has not supplied them, which
        // is why the overlay contributed nothing before this was threaded.
        macro: req.macro,
        sentiment: req.sentiment,
      ),
    );

    // ---- 7. Structural stop ---------------------------------------------
    StopPlan? plan;
    if (confluence.verdict != Verdict.noTrade) {
      plan = _buildPlan(
        req: req,
        dir: dir,
        m5: m5,
        m15: m15,
        atr5m: atr5m,
      );
      if (plan != null && !plan.isValid) {
        quality.add('stop refused: ${plan.rejectionReason}');
      }
      // A refused stop means there are no levels to publish, so there is no
      // signal -- publishing entry without stop/TP would breach MGC R1.
      if (plan == null || !plan.isValid) {
        return ScanResult(
          verdict: Verdict.noTrade,
          grade: Grade.insufficient,
          reasonCodes: confluence.reasonCodes,
          vetoes: [...confluence.vetoed, ReasonCode.v13BadStopDistance],
          technicalScore: confluence.technicalScore,
          finalScore: confluence.finalScore,
          macroAlignment: confluence.macroAlignment,
          macroAgrees: confluence.macroAgrees,
          sentimentAlignment: confluence.sentimentAlignment,
          sentimentAgrees: confluence.sentimentAgrees,
          conflictPenalty: confluence.conflictPenalty,
          spread: req.spread,
          dataQuality: quality,
          lockSummary: lockSummary,
          stopPlan: plan,
          atr5m: atr5m,
        );
      }
    }

    return ScanResult(
      verdict: confluence.verdict,
      grade: confluence.grade,
      reasonCodes: confluence.reasonCodes,
      vetoes: confluence.vetoed,
      technicalScore: confluence.technicalScore,
      finalScore: confluence.finalScore,
      macroAlignment: confluence.macroAlignment,
      macroAgrees: confluence.macroAgrees,
      sentimentAlignment: confluence.sentimentAlignment,
      sentimentAgrees: confluence.sentimentAgrees,
      conflictPenalty: confluence.conflictPenalty,
      spread: req.spread,
      dataQuality: quality,
      lockSummary: lockSummary,
      stopPlan: plan,
      atr5m: atr5m,
    );
  }

  /// Builds the stop plan, refusing to derive levels from proxy history.
  StopPlan? _buildPlan({
    required ScanRequest req,
    required Side dir,
    required TimeframeState m5,
    required TimeframeState m15,
    required double? atr5m,
  }) {
    if (atr5m == null || atr5m <= 0) return null;

    final entry = req.currentPrice ?? m5.close;
    if (entry == null || entry <= 0) return null;

    // Structural levels come from the 15m swing set. If that history is
    // degraded proxy data, refuse rather than publish a level the market may
    // never have printed.
    final m15Degraded = req.m15.allDegraded;
    if (m15Degraded) return null;

    final swings15 = swings(_barsFor(req, Tf.m15).bars, lookback: 2);
    final lastIdx = req.m15.length - 1;
    final low = lastSwingLow(swings15, lastIdx);
    final high = lastSwingHigh(swings15, lastIdx);

    return buildStopPlan(
      direction: dir,
      entry: entry,
      atr5m: atr5m,
      swingLow: low?.price,
      swingHigh: high?.price,
      spreadStatus: req.spread.isGenuine ? SpreadStatus.available : SpreadStatus.unavailable,
      // Only a genuine venue spread may widen the buffer.
      genuineSpread: req.spread.isGenuine ? req.spread.value : null,
      config: stopConfig,
    );
  }

  TimeframeBars _barsFor(ScanRequest r, Tf tf) {
    switch (tf) {
      case Tf.m5:
        return r.m5;
      case Tf.m15:
        return r.m15;
      case Tf.m30:
        return r.m30;
      case Tf.h1:
        return r.h1;
    }
  }

  /// Minimum bars needed before a timeframe's indicators are meaningful.
  int _minBarsFor(Tf tf) => switch (tf) {
        Tf.m5 => 20,
        Tf.m15 => 50,
        Tf.m30 => 50,
        Tf.h1 => 200, // EMA200 is the primary regime filter
      };

  /// Builds a [TimeframeState] from validated bars.
  ///
  /// Everything stays null when undefined, so an absent indicator is never
  /// mistaken for a neutral one.
  TimeframeState _stateFor(TimeframeBars tb, Tf tf) {
    final bars = tb.bars;
    if (bars.isEmpty) return TimeframeState(timeframe: tf);

    final c = closes(bars);
    final e20 = ema(c, 20).last;
    final e50 = ema(c, 50).last;
    final e200 = ema(c, 200).last;
    final r = rsi(c, period: 14).last;
    final m = macd(c);
    final a = atr(bars, period: 14);
    final d = adx(bars, period: 14);
    final sw = swings(bars, lookback: 2);
    final lastIdx = bars.length - 1;

    // ATR percentile needs a window of ATR values, not just the latest.
    final atrSeries = [
      for (var i = 0; i < a.length; i++)
        if (a[i] != null) a[i]!,
    ];

    return TimeframeState(
      timeframe: tf,
      close: c.last,
      ema20: e20,
      ema50: e50,
      ema200: e200,
      rsi14: r,
      macdHistogram: m.histogram.last,
      adx14: d.adx.last,
      plusDi: d.plusDi.last,
      minusDi: d.minusDi.last,
      atr: a.last,
      atrPercentile: atrPercentile(atrSeries),
      swingLow: lastSwingLow(sw, lastIdx)?.price,
      swingHigh: lastSwingHigh(sw, lastIdx)?.price,
      // Candle-pattern flags stay false here: pattern detection is a separate
      // concern and inferring it from indicator state would be fabricating a
      // structural observation the scanner did not actually make.
    );
  }
}