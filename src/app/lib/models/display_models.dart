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
  });

  final String id;
  final String name;
  final Direction direction;
  final bool agrees;
  final String entryText;
  final String stopText;
  final String targetsText;
  final String freshnessText;
  final String reasoning;
  final String sourceUrl;
  final int tp1HitRate;
  final int tp2HitRate;
  final int tp3HitRate;
}

/// One closed/past signal row for the History screen.
class DisplayHistoryEntry {
  const DisplayHistoryEntry({
    required this.direction,
    required this.whenText,
    required this.detailText,
    required this.status,
    required this.pipsText,
  });

  final Direction? direction;
  final String whenText;
  final String detailText;
  final DisplayStatus? status;
  final String pipsText;
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

/// Pips (×0.01 per D-003) from the zone mid to [target], rounded DOWN to
/// the nearest hundred to match the mock pipeline's display rounding
/// (e.g. 17.5 pts → +1700, −15.5 pts → −1600).
int pipsTo(double target, double entryMid) =>
    ((target - entryMid)).floor() * 100;

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
