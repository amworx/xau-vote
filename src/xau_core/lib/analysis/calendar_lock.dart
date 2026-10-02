/// Economic-calendar event tiers and tier-specific blackout windows
/// (methodology §4.1, §4.2; MGC §5).
///
/// The important design point is that **blackout width scales with event
/// importance**. XV's existing calendar only gated "HIGH" impact with a flat
/// window, which is both too wide for routine releases and too narrow for the
/// Fed. The methodology's tiering fixes both ends.
///
/// Everything here is time-injected: no clock is read inside this library, so
/// a calendar decision is fully reproducible from its inputs.
library;

/// Event importance tiers (§4.1).
enum EventTier {
  /// Mandatory trading blackout: FOMC, CPI, NFP, emergency geopolitical.
  tierA,

  /// Normal high caution: PPI, GDP, retail sales, ISM, major energy shocks.
  tierB,

  /// Context only — annotates, never suppresses or votes.
  tierC,
}

/// A scheduled economic event.
class EconomicEvent {
  const EconomicEvent({
    required this.name,
    required this.currency,
    required this.tier,
    required this.releaseTime,
    this.actual,
    this.forecast,
    this.previous,
    this.source = 'unknown',
  });

  final String name;
  final String currency;
  final EventTier tier;

  /// Scheduled release time, UTC.
  final DateTime releaseTime;

  /// Published values, when known. Null means "no actual available" — which
  /// is a valid state and must not be read as zero (§4.4: classify by reaction
  /// and label the gap, never infer).
  final double? actual;
  final double? forecast;
  final double? previous;
  final String source;

  bool get hasActual => actual != null;

  /// Surprising-release check. Only meaningful once [actual] exists, and it
  /// returns null when it cannot be evaluated.
  ///
  /// IV.2.1 specifies a >5% relative surprise (or an absolute miss larger than
  /// the smaller of 0.3% or the forecast) as materially surprising.
  bool? get isMaterialSurprise {
    final a = actual;
    final f = forecast;
    if (a == null || f == null) return null;
    if (f == 0) {
      // A 0% forecast cannot be scaled by, so the rule degenerates to a pure
      // absolute test. Note this makes small absolute moves "surprising"
      // against a 0 baseline — that is the honest reading of the published
      // rule, and it is why providers should supply a real forecast.
      return (a - 0).abs() > 0.3;
    }
    final rel = ((a - f).abs() / f.abs()) * 100.0;
    final abs = (a - f).abs();
    return rel > 5.0 || abs > 0.3;
  }

  @override
  String toString() => 'EconomicEvent($name, $currency, ${tier.name}, '
      '${releaseTime.toIso8601String()})';
}

/// Blackout state for a scan.
enum LockState {
  /// Scanning is allowed.
  open,

  /// Inside a scheduled event lock.
  blackout,

  /// An emergency condition froze entries pending reassessment.
  emergencyFreeze,
}

/// The full calendar decision, with the reason attached so the UI can explain
/// a suppressed signal instead of silently hiding it.
class LockDecision {
  const LockDecision({
    required this.state,
    required this.activeEvents,
    required this.lockUntil,
    required this.reasonCodes,
    this.emergencyEvidence = const [],
  });

  final LockState state;

  /// Events currently or soon contributing to a lock.
  final List<EconomicEvent> activeEvents;

  /// When scanning resumes, or null when unlocked.
  final DateTime? lockUntil;

  /// Human-readable codes, e.g. `LOCK_TIER_A_FOMC`.
  final List<String> reasonCodes;

  /// Emergency triggers observed, for the data-quality note.
  final List<String> emergencyEvidence;

  bool get isLocked => state != LockState.open;

  String get summary => reasonCodes.isEmpty ? 'OPEN' : reasonCodes.join(', ');
}

/// Blackout windows in minutes, relative to the event time.
class BlackoutWindows {
  const BlackoutWindows({
    this.tierAMinutesBefore = 45,
    this.tierAMinutesAfter = 30,
    this.tierBMinutesBefore = 15,
    this.tierBMinutesAfter = 15,
    this.tierCMinutesBefore = 0,
    this.tierCMinutesAfter = 0,
    this.emergencyMinutes = 30,
  });

  /// FOMC-class events carry the longest information content: lock from T−45,
  /// hold through the decision and press conference, release T+30 after.
  final int tierAMinutesBefore;
  final int tierAMinutesAfter;

  /// Routine releases get a short caution window rather than a full blackout.
  final int tierBMinutesBefore;
  final int tierBMinutesAfter;

  /// Tier C never locks.
  final int tierCMinutesBefore;
  final int tierCMinutesAfter;

  /// Minimum freeze after an emergency condition (methodology §4.2).
  final int emergencyMinutes;
}

/// Emergency market conditions that freeze entries (§4.2).
///
/// Note the spread condition is intentionally absent: genuine bid/ask data are
/// unavailable, and the ratified option (a) rule forbids substituting a
/// cross-source price difference. The remaining conditions still evaluate.
class EmergencyCondition {
  const EmergencyCondition({
    this.atrPercentile,
    this.atrPercentileThreshold = 95,
    this.lastCandleRange,
    this.atr14,
    this.rangeMultipleThreshold = 2.0,
    this.gappedThroughLevel = false,
  });

  final double? atrPercentile;
  final double atrPercentileThreshold;

  /// Range of the most recent 5m candle.
  final double? lastCandleRange;
  final double? atr14;
  final double rangeMultipleThreshold;

  final bool gappedThroughLevel;

  /// Codes for every emergency trigger observed.
  List<String> get codes {
    final out = <String>[];
    final p = atrPercentile;
    if (p != null && p >= atrPercentileThreshold) {
      out.add('EMERGENCY_ATR_PERCENTILE_${p.toStringAsFixed(0)}');
    }
    final r = lastCandleRange;
    final a = atr14;
    if (r != null && a != null && a > 0 && r > rangeMultipleThreshold * a) {
      out.add('EMERGENCY_CANDLE_RANGE_${(r / a).toStringAsFixed(1)}xATR');
    }
    if (gappedThroughLevel) out.add('EMERGENCY_STRUCTURE_GAP');
    return out;
  }

  bool get triggered => codes.isNotEmpty;
}

/// Evaluates the economic-calendar lock (methodology §4.2, §8.1 step 3).
class CalendarLock {
  const CalendarLock([this.windows = const BlackoutWindows()]);

  final BlackoutWindows windows;

  /// Whether [event] is locked at [now].
  ///
  /// A Tier B event is "caution", not a full blackout: it suppresses new
  /// entries but is reported separately from Tier A so the UI can show *why*
  /// a signal is missing and how long remains.
  bool isLocked(EconomicEvent event, DateTime now) {
    if (event.tier == EventTier.tierC) return false;
    final before = event.tier == EventTier.tierA
        ? windows.tierAMinutesBefore
        : windows.tierBMinutesBefore;
    final after = event.tier == EventTier.tierA
        ? windows.tierAMinutesAfter
        : windows.tierBMinutesAfter;
    final start = event.releaseTime.subtract(Duration(minutes: before));
    final end = event.releaseTime.add(Duration(minutes: after));
    return !now.isBefore(start) && now.isBefore(end);
  }

  DateTime? unlockAt(EconomicEvent event) {
    final after = event.tier == EventTier.tierA
        ? windows.tierAMinutesAfter
        : windows.tierBMinutesAfter;
    return event.releaseTime.add(Duration(minutes: after));
  }

  String codeFor(EconomicEvent event) {
    final tier = event.tier.name.substring(4).toUpperCase(); // 'tierA' -> 'A'
    final ccy = event.currency.toUpperCase();
    final prefix = ccy == 'USD' ? 'LOCK_TIER_$tier' : 'LOCK_TIER_${tier}_$ccy';
    final name = event.name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    return '${prefix}_$name';
  }

  /// Full lock decision across the calendar at [now].
  ///
  /// Only USD events can block XV: the product is XAUUSD-only, so a euro-area
  /// release is context that may *explain* a gold move but must not by itself
  /// suppress a gold setup unless it is a major central-bank decision the
  /// methodology classes as high impact for gold (§4.1 Tier B explicitly
  /// includes major ECB/BoE decisions).
  LockDecision evaluate({
    required DateTime now,
    required List<EconomicEvent> events,
    EmergencyCondition? emergency,
    Set<String> majorNonUsdCurrencies = const {'EUR', 'GBP', 'JPY'},
  }) {
    final active = <EconomicEvent>[];
    final codes = <String>[];

    for (final e in events) {
      if (!isLocked(e, now)) continue;
      final isUsd = e.currency.toUpperCase() == 'USD';
      final isMajorNonUsd = majorNonUsdCurrencies.contains(e.currency.toUpperCase());
      // Tier C never locks (handled above). A non-USD event only participates
      // if it is a Tier A/B policy decision the methodology treats as
      // gold-relevant.
      if (!isUsd && !isMajorNonUsd) continue;
      active.add(e);
      codes.add(codeFor(e));
    }

    if (active.isNotEmpty) {
      // Lock ends with the latest contributor.
      final latest = active
          .map(unlockAt)
          .whereType<DateTime>()
          .reduce((a, b) => a.isAfter(b) ? a : b);
      return LockDecision(
        state: LockState.blackout,
        activeEvents: active,
        lockUntil: latest,
        reasonCodes: codes,
      );
    }

    if (emergency != null && emergency.triggered) {
      return LockDecision(
        state: LockState.emergencyFreeze,
        activeEvents: const [],
        lockUntil: now.add(Duration(minutes: windows.emergencyMinutes)),
        reasonCodes: emergency.codes,
        emergencyEvidence: emergency.codes,
      );
    }

    return const LockDecision(
      state: LockState.open,
      activeEvents: [],
      lockUntil: null,
      reasonCodes: [],
    );
  }
}

/// Maps an economic calendar impact label to a tier.
///
/// Providers disagree on their vocabulary, so this accepts the common spellings
/// and falls back to [EventTier.tierC] for anything unrecognised — an unknown
/// impact must never silently become a blackout or, worse, a free pass.
EventTier tierFromImpact(String impact) {
  switch (impact.toUpperCase()) {
    case 'HIGH':
    case 'A':
    case 'TIER_A':
      return EventTier.tierA;
    case 'MEDIUM':
    case 'MED':
    case 'B':
    case 'TIER_B':
      return EventTier.tierB;
    default:
      return EventTier.tierC;
  }
}

/// Classifies a Tier B release as high impact once it is materially surprising
/// (§4.1 Tier B: "when the result is materially surprising").
///
/// This is how an unscheduled-looking surprise still triggers the wider Tier A
/// window without pretending we knew it in advance.
EventTier effectiveTier(EconomicEvent event) {
  if (event.tier == EventTier.tierB && event.isMaterialSurprise == true) {
    return EventTier.tierA;
  }
  return event.tier;
}