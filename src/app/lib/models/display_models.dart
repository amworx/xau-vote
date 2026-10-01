/// Minimal LOCAL display models for the Flutter app.
///
/// These intentionally duplicate the smallest display-relevant subset of
/// `xau_core` models (direction, strength bands, lifecycle states) instead
/// of depending on the `xau_core`/`xau_data` packages via path. Reason:
/// avoid cross-package version friction during the MVP UI phase; the live
/// wiring phase (T5.7) will replace these with the real packages or a thin
/// mapper. Field names/values mirror the domain packages where possible.
library;

/// Trade direction of an idea or signal.
enum Direction { long, short, neutral }

/// Agreement-strength bands, exactly per spec §7.
///
/// The score is agreement among sources and setup characteristics — never
/// a forecast of outcome. UI must render the band label + score only.
enum AgreementBand { weak, developing, moderate, strong, veryStrong }

/// Maps a 0–100 agreement score to its spec §7 band. Values are clamped.
AgreementBand bandForScore(int score) {
  final s = score.clamp(0, 100);
  if (s <= 39) return AgreementBand.weak;
  if (s <= 59) return AgreementBand.developing;
  if (s <= 74) return AgreementBand.moderate;
  if (s <= 89) return AgreementBand.strong;
  return AgreementBand.veryStrong;
}

/// Uppercase label for an [AgreementBand] (e.g. `STRONG`).
String bandLabel(AgreementBand band) {
  switch (band) {
    case AgreementBand.weak:
      return 'WEAK';
    case AgreementBand.developing:
      return 'DEVELOPING';
    case AgreementBand.moderate:
      return 'MODERATE';
    case AgreementBand.strong:
      return 'STRONG';
    case AgreementBand.veryStrong:
      return 'VERY STRONG';
  }
}

/// Signal lifecycle states (spec §14) relevant to display.
enum DisplayStatus {
  noSetup,
  developing,
  ready,
  confirmed,
  active,
  tp1Hit,
  tp2Hit,
  tp3Hit,
  invalidated,
  expired,
}

/// Uppercase lifecycle label (e.g. `TP2 HIT`, `NO CONSENSUS` handled by UI).
String statusLabel(DisplayStatus status) {
  switch (status) {
    case DisplayStatus.noSetup:
      return 'NO SETUP';
    case DisplayStatus.developing:
      return 'DEVELOPING';
    case DisplayStatus.ready:
      return 'READY';
    case DisplayStatus.confirmed:
      return 'CONFIRMED';
    case DisplayStatus.active:
      return 'ACTIVE';
    case DisplayStatus.tp1Hit:
      return 'TP1 HIT';
    case DisplayStatus.tp2Hit:
      return 'TP2 HIT';
    case DisplayStatus.tp3Hit:
      return 'TP3 HIT';
    case DisplayStatus.invalidated:
      return 'INVALIDATED';
    case DisplayStatus.expired:
      return 'EXPIRED';
  }
}

/// One clear 15-minute setup derived from source agreement (display view).
class DisplaySignal {
  const DisplaySignal({
    required this.id,
    required this.direction,
    required this.strength,
    required this.entryLow,
    required this.entryHigh,
    required this.stopLoss,
    this.tp1,
    this.tp2,
    this.tp3,
    required this.status,
    required this.agreeCount,
    required this.totalCount,
    this.price = 4278.30,
    this.dayMove = 12.40,
    this.spread = 0.35,
    this.dayLow,
    this.dayHigh,
  });

  final String id;
  final Direction direction;
  final int strength;
  final double entryLow;
  final double entryHigh;
  final double stopLoss;
  final double? tp1;
  final double? tp2;
  final double? tp3;
  final DisplayStatus status;
  final int agreeCount;
  final int totalCount;
  final double price;
  final double dayMove;
  final double spread;

  /// Session low/high for the day-move bar (mockup `.day` RANGE).
  ///
  /// Nullable on purpose: until the market-data provider (gate G3) supplies a
  /// real range the UI must show a neutral placeholder rather than invent
  /// numbers (product rule 2 — never fabricate).
  final double? dayLow;
  final double? dayHigh;

  AgreementBand get band => bandForScore(strength);

  double get entryMid => (entryLow + entryHigh) / 2;
}

/// One collected source idea behind the consensus (spec §17).
class DisplaySource {
  const DisplaySource({
    required this.id,
    required this.name,
    required this.direction,
    required this.agrees,
    required this.entryText,
    required this.stopText,
    required this.targetsText,
    required this.freshnessText,
    required this.reasoning,
    required this.sourceUrl,
    required this.tp1HitRate,
    required this.tp2HitRate,
    required this.tp3HitRate,
    this.stopPoints,
  });

  final String id;
  final String name;
  final Direction direction;
  final bool agrees;
  final String entryText;

  /// The desk's own stop LOSS LEVEL, e.g. `4,262`. Never carries a pip figure
  /// — the pip distance is derived from [stopPoints] at render time so it
  /// follows the trader's [PipConvention] (D-20260927-003).
  final String stopText;

  final String targetsText;
  final String freshnessText;
  final String reasoning;
  final String sourceUrl;
  final int tp1HitRate;
  final int tp2HitRate;
  final int tp3HitRate;

  /// Distance from the desk's own fill to its stop, in POINTS — the canonical
  /// unit (spec A§11). Signed: negative when the stop sits below the fill.
  ///
  /// The quoted `−1600p` a desk publishes is a pip string in the desk's own
  /// convention, so it is recorded here as the point distance it means and the
  /// pip figure is re-derived for the trader (D-20260927-003). Null when the
  /// source quotes a bare level with no distance; the row then shows the level
  /// alone rather than inventing one (product rule 2 — never fabricate).
  final double? stopPoints;
}

/// One closed/past signal row for the History screen.
class DisplayHistoryEntry {
  const DisplayHistoryEntry({
    required this.direction,
    required this.whenText,
    required this.detailText,
    required this.status,
    required this.pipsPoints,
  });

  final Direction? direction;
  final String whenText;
  final String detailText;
  final DisplayStatus? status;

  /// Realised distance of the closed setup in POINTS — the canonical unit
  /// (spec A§11). Deliberately not a preformatted pip string: the pip figure
  /// is derived from this at render time through [PipConvention]
  /// (D-20260927-003), so switching the convention rescales the row instead
  /// of leaving a stale convention behind. Zero for a setup that never closed
  /// (no consensus, expired, cancelled) rather than an invented result.
  final double pipsPoints;
}

/// Target-scope selection (spec §10).
enum TargetSelection { tp1Only, tp1Tp2, all }

/// Which TP cells are visible for a [TargetSelection].
List<int> visibleTps(TargetSelection selection) {
  switch (selection) {
    case TargetSelection.tp1Only:
      return const [1];
    case TargetSelection.tp1Tp2:
      return const [1, 2];
    case TargetSelection.all:
      return const [1, 2, 3];
  }
}

/// Risk/reward for [target] vs a conservative fill at the zone edge
/// ([entryLow]) and [stopLoss]. LONG math; mock fixtures are LONG-only.
double riskReward({
  required double target,
  required double entryLow,
  required double stopLoss,
}) {
  final risk = entryLow - stopLoss;
  if (risk <= 0) return 0;
  return (target - entryLow) / risk;
}

/// Pip-size convention — accepted decision D-20260927-003.
///
/// Points are canonical (spec A§11); **pips are a display-only unit** and
/// brokers disagree on their size, so the trader picks one of two:
///
/// * **A — 1 pip = 0.10 points** (one point = 10 pips)
/// * **B — 1 pip = 0.01 points** (one point = 100 pips)
///
/// **B is the default** (the user trades FXPro/Vantage). Switching rescales
/// every pip figure ×10 (B) or ÷10 (A) from the same point value: a price, a
/// level and an R:R are never touched by the convention (D-20260927-003).
enum PipConvention {
  /// A — 1 pip = 0.10 points.
  a,

  /// B — 1 pip = 0.01 points. Default (FXPro/Vantage quoting).
  b,
}

/// Display scaling and wording for a [PipConvention].
extension PipConventionScale on PipConvention {
  /// Points per pip: A → 10, B → 100. The single multiplier every pip
  /// readout derives from.
  int get pipFactor => switch (this) {
    PipConvention.a => 10,
    PipConvention.b => 100,
  };

  /// The pip size itself as the picker and the caption state it — `0.10` /
  /// `0.01`.
  String get pipSizeLabel => switch (this) {
    PipConvention.a => '0.10',
    PipConvention.b => '0.01',
  };
}

/// Pips from the zone mid to [target] at [pipFactor] points per pip
/// (D-20260927-003), rounded DOWN to a whole pip to match the mock
/// pipeline's display rounding (e.g. 17.5 pts → +1700, −15.5 pts → −1600 at
/// convention B).
///
/// Truncation runs before scaling and stays sign-asymmetric on purpose: the
/// documented convention-B figures must not move.
int pipsTo(double target, double entryMid, {required int pipFactor}) =>
    (target - entryMid).floor() * pipFactor;

/// Pips for a signed point distance that is not a whole-number level gap
/// (a closed History outcome). The magnitude is truncated to a whole pip
/// before scaling, so a sign can never round a truncated value up.
int pipsFromPoints(double points, {required int pipFactor}) {
  final magnitude = points.abs().floor() * pipFactor;
  return points < 0 ? -magnitude : magnitude;
}

/// Signed History outcome as a display string, e.g. `+3100 PIPS`.
String pipsLabel(double points, {required int pipFactor}) {
  final pips = pipsFromPoints(points, pipFactor: pipFactor);
  final sign = pips > 0 ? '+' : (pips < 0 ? '-' : '');
  return '$sign${pips.abs()} PIPS';
}

/// Pips for a LIVE price move (the open position's P/L), which is fractional
/// where a level distance is whole — rounded to the nearest pip instead of
/// truncated, so +0.30 pts reads `+30` at convention B and `+3` at A.
///
/// Only the open P/L uses this. Entry/stop/target distances keep the
/// truncating [pipsTo] so the documented convention-B figures cannot move.
int pipsFromMove(double points, {required int pipFactor}) =>
    (points * pipFactor).round();

/// Pip width of an entry zone (e.g. 4,275–4,280 → `500 PIPS` at
/// convention B), rounded to the nearest pip.
int zonePips(double low, double high, {required int pipFactor}) =>
    ((high - low) * pipFactor).round();

/// Formats a Gold price with thousands separator and 2 decimals.
String formatPrice(double value) {
  final parts = value.toStringAsFixed(2).split('.');
  final digits = parts[0].replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (_) => ',',
        );

  return '$digits.${parts[1]}';
}

/// Compact level without decimals when whole (e.g. `4,295`).
String formatLevel(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
  }
  return formatPrice(value);
}

// ---------------------------------------------------------------------------
// TASK-07 — events & news display models (addendum docs/economic-calendar-news.md).
//
// LOCAL duplicates like the rest of this file (live wiring in T5.7 maps the
// Supabase rows). Rule 9 applies: these models carry CONTEXT ONLY — they can
// suppress, delay, annotate, or explain a signal, never create or flip one.
// ---------------------------------------------------------------------------

/// Calendar event impact (addendum §2). LOW rows are stored, hidden by filter.
enum EventImpact { high, medium, low }

/// Label for an [EventImpact] pill (e.g. `HIGH`).
String impactLabel(EventImpact impact) {
  switch (impact) {
    case EventImpact.high:
      return 'HIGH';
    case EventImpact.medium:
      return 'MEDIUM';
    case EventImpact.low:
      return 'LOW';
  }
}

/// One scheduled economic event (upcoming or past).
class DisplayEvent {
  const DisplayEvent({
    required this.id,
    required this.title,
    required this.currency,
    required this.impact,
    required this.startsIn,
    this.forecast,
    this.previous,
    this.actual,
    this.surprise,
  });

  final String id;
  final String title;
  final String currency;
  final EventImpact impact;

  /// Time until release from fixture load (MOCK_MODE). Live mode replaces
  /// this with the server `starts_at` timestamp.
  final Duration startsIn;
  final String? forecast;
  final String? previous;
  final String? actual;

  /// Post-release flag: 'hot' | 'cold' | 'inline' | null (no result yet).
  /// Volatility context only — never a direction.
  final String? surprise;

  bool get isPast => startsIn.isNegative;
  bool get isSurprise => surprise == 'hot' || surprise == 'cold';
}

/// USD-pressure reading per digest theme (addendum §3.2, display only).
enum NewsPressure { hawkish, dovish, neutral, unclear }

/// Label for a [NewsPressure] pill (e.g. `HAWKISH`).
String pressureLabel(NewsPressure pressure) {
  switch (pressure) {
    case NewsPressure.hawkish:
      return 'HAWKISH';
    case NewsPressure.dovish:
      return 'DOVISH';
    case NewsPressure.neutral:
      return 'NEUTRAL';
    case NewsPressure.unclear:
      return 'UNCLEAR';
  }
}

/// One macro-backdrop theme with evidence links (fixed schema, no prose).
class DisplayDigestTheme {
  const DisplayDigestTheme({
    required this.theme,
    required this.pressure,
    required this.evidenceCount,
  });

  final String theme;
  final NewsPressure pressure;
  final int evidenceCount;
}

/// One collected headline (title + source + link only, never full text).
class DisplayNewsItem {
  const DisplayNewsItem({
    required this.source,
    required this.title,
    required this.ageText,
    required this.url,
  });

  final String source;
  final String title;
  final String ageText;
  final String url;
}

/// Formats a [Duration] as `HH:MM:SS` (negative → `00:00:00`).
String formatCountdown(Duration remaining) {
  final s = remaining.isNegative ? 0 : remaining.inSeconds;
  final h = (s ~/ 3600).toString().padLeft(2, '0');
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$h:$m:$sec';
}
