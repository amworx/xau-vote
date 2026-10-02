/// Structural stop and R-multiple targets (methodology §11, §12, §14).
///
/// The rule the whole file exists to enforce: **the stop is structural first
/// and mathematical second.** Start from the confirmed swing, add an ATR
/// buffer, then clamp into the 0.80–1.80 × ATR envelope. If the structural
/// distance cannot be clamped into that envelope, the correct answer is to
/// reject the setup — not to silently widen the stop and pretend the R:R still
/// holds.
///
/// The buffer is `0.20 × ATR`. The `max(0.20*ATR, spread*2)` form is only
/// available when a genuine venue bid/ask exists; per the ratified option (a)
/// rule no proxy spread may be used, so a caller without a spread simply gets
/// the ATR buffer and the engine reports the spread as UNEVALUATED.
library;

import '../analysis/confluence.dart';
import '../analysis/indicators.dart';

/// A built stop/target plan, or the reason it could not be built.
class StopPlan {
  const StopPlan({
    required this.entry,
    required this.stopLoss,
    required this.tp1,
    required this.tp2,
    required this.tp3,
    required this.riskDistance,
    required this.riskDistanceAtr,
    required this.riskPerUnit,
    required this.spreadStatus,
    required this.bufferSource,
    this.rejectionReason,
  });

  final double entry;
  final double stopLoss;
  final double tp1;
  final double tp2;
  final double tp3;

  /// Absolute USD distance from entry to stop. Never expressed in pips,
  /// because XAUUSD pip conventions differ between venues.
  final double riskDistance;

  /// Stop distance in ATR units, always inside 0.80–1.80.
  final double riskDistanceAtr;

  final double riskPerUnit;

  final SpreadStatus spreadStatus;

  /// Describes how the buffer was derived, for the audit trail.
  final String bufferSource;

  /// Non-null when the setup was rejected. A rejected plan carries no levels.
  final String? rejectionReason;

  bool get isValid => rejectionReason == null;

  double get r1 => riskDistance;
  double get r2 => riskDistance * 2;
  double get r3 => riskDistance * 3;

  /// TP2 reward-to-risk, the number MGC R7 floors at 1.8.
  double get tp2R => riskDistance == 0 ? double.infinity : (tp2 - entry).abs() / riskDistance;
}

/// Stop-placement thresholds (§11). `[INIT]` hypotheses, pending calibration.
class StopConfig {
  const StopConfig({
    this.atrBufferMultiple = 0.20,
    this.minStopAtr = 0.80,
    this.maxStopAtr = 1.80,
    this.tp1R = 1.0,
    this.tp2R = 2.0,
    this.tp3R = 3.0,
    this.tp2FloorR = 1.8,
    this.minimumTick = 0.01,
  });

  final double atrBufferMultiple;
  final double minStopAtr;
  final double maxStopAtr;

  /// R-multiple targets. §12 sets TP1 ≥ 1R and TP2 = 2R; TP3 is structure-led.
  final double tp1R;
  final double tp2R;
  final double tp3R;

  /// MGC R7: TP2 must be at least this multiple of risk.
  final double tp2FloorR;

  /// XAUUSD minimum price increment.
  final double minimumTick;
}

/// Builds a structural stop and R-multiple targets.
///
/// [swingLow] / [swingHigh] must be **confirmed** swing levels from the closed
/// series — using an unconfirmed swing is how a stop ends up inside the noise
/// the ATR buffer was supposed to clear.
StopPlan buildStopPlan({
  required Side direction,
  required double entry,
  required double atr5m,
  double? swingLow,
  double? swingHigh,
  SpreadStatus spreadStatus = SpreadStatus.unavailable,
  double? genuineSpread,
  StopConfig config = const StopConfig(),
}) {
  final bull = direction == Side.long;

  StopPlan reject(String why) => StopPlan(
        entry: entry,
        stopLoss: double.nan,
        tp1: double.nan,
        tp2: double.nan,
        tp3: double.nan,
        riskDistance: double.nan,
        riskDistanceAtr: double.nan,
        riskPerUnit: double.nan,
        spreadStatus: spreadStatus,
        bufferSource: 'none',
        rejectionReason: why,
      );

  if (atr5m.isNaN || atr5m <= 0) return reject('ATR_UNAVAILABLE');
  if (entry.isNaN || entry <= 0) return reject('ENTRY_UNAVAILABLE');

  // ---- Buffer -------------------------------------------------------------
  // A genuine venue spread may widen the buffer; a proxy may not.
  final hasGenuineSpread =
      spreadStatus == SpreadStatus.available && genuineSpread != null && genuineSpread > 0;
  final atrBuffer = config.atrBufferMultiple * atr5m;
  final buffer = hasGenuineSpread ? (atrBuffer > genuineSpread * 2 ? atrBuffer : genuineSpread * 2) : atrBuffer;
  final bufferSource = hasGenuineSpread ? 'max(0.20*ATR, spread*2)' : '0.20*ATR';

  // ---- Structural anchor --------------------------------------------------
  // Without a confirmed swing there is no structural stop, so refuse rather
  // than substituting the ATR midpoint.
  final double anchor;
  if (bull) {
    final lo = swingLow;
    if (lo == null || lo.isNaN) return reject('NO_CONFIRMED_SWING_LOW');
    if (lo >= entry) return reject('SWING_LOW_ABOVE_ENTRY');
    anchor = lo;
  } else {
    final hi = swingHigh;
    if (hi == null || hi.isNaN) return reject('NO_CONFIRMED_SWING_HIGH');
    if (hi <= entry) return reject('SWING_HIGH_BELOW_ENTRY');
    anchor = hi;
  }

  final stopRaw = bull ? anchor - buffer : anchor + buffer;
  final finalDistance = usdDistance(entry, stopRaw);
  final distanceAtr = finalDistance / atr5m;

  // ---- ATR envelope (§11) -------------------------------------------------
  // If the structural stop is wider than the envelope, the setup is rejected.
  // Widening is forbidden and narrowing would put the stop inside the swing.
  if (distanceAtr > config.maxStopAtr) return reject('STRUCTURAL_STOP_TOO_WIDE');
  if (distanceAtr < config.minStopAtr) {
    // Too tight to be a real stop: widen to the minimum rather than risk being
    // clipped by normal noise.
    final widened = bull ? entry - config.minStopAtr * atr5m : entry + config.minStopAtr * atr5m;
    return _finish(
      direction: direction,
      entry: entry,
      stopLoss: widened,
      atr5m: atr5m,
      spreadStatus: spreadStatus,
      bufferSource: '$bufferSource widened to ${config.minStopAtr}xATR floor',
      config: config,
    );
  }

  return _finish(
    direction: direction,
    entry: entry,
    stopLoss: stopRaw,
    atr5m: atr5m,
    spreadStatus: spreadStatus,
    bufferSource: bufferSource,
    config: config,
  );
}

StopPlan _finish({
  required Side direction,
  required double entry,
  required double stopLoss,
  required double atr5m,
  required SpreadStatus spreadStatus,
  required String bufferSource,
  required StopConfig config,
}) {
  final bull = direction == Side.long;
  final risk = usdDistance(entry, stopLoss);
  if (risk <= 0) {
    return StopPlan(
      entry: entry,
      stopLoss: double.nan,
      tp1: double.nan,
      tp2: double.nan,
      tp3: double.nan,
      riskDistance: double.nan,
      riskDistanceAtr: double.nan,
      riskPerUnit: double.nan,
      spreadStatus: spreadStatus,
      bufferSource: bufferSource,
      rejectionReason: 'NON_POSITIVE_RISK',
    );
  }

  double at(double r) =>
      bull ? entry + risk * r : entry - risk * r;

  final tp1 = at(config.tp1R);
  final tp2 = at(config.tp2R);
  final tp3 = at(config.tp3R);

  return StopPlan(
    entry: entry,
    stopLoss: stopLoss,
    tp1: tp1,
    tp2: tp2,
    tp3: tp3,
    riskDistance: risk,
    riskDistanceAtr: risk / atr5m,
    riskPerUnit: risk,
    spreadStatus: spreadStatus,
    bufferSource: bufferSource,
  );
}

/// Applies the §12 structural target override: a target blocked by a major
/// level should be dropped or moved rather than published as if reachable.
///
/// Returns the adjusted R-multiple, or null when the target is unreachable and
/// the setup should be rejected instead.
double? applyTargetOverride({
  required Side direction,
  required double entry,
  required double riskDistance,
  required double targetR,
  required List<double> blockingLevels,
}) {
  if (riskDistance <= 0) return null;
  var r = targetR;
  for (final level in blockingLevels) {
    final distance = usdDistance(entry, level);
    final levelR = distance / riskDistance;
    final bull = direction == Side.long;
    // A level *between* entry and the target blocks it.
    final isBetween = bull ? level > entry && level < entry + riskDistance * r
        : level < entry && level > entry - riskDistance * r;
    if (!isBetween) continue;
    if (levelR < 0.8) return null; // effectively at entry: unreachable
    // Pull the target back to sit just before the blocking level. The target
    // must also clear the 1.8R TP2 floor to remain publishable at all, so a
    // level close to the target can leave no valid R to publish.
    final adjusted = levelR - 0.1;
    r = r < adjusted ? r : adjusted;
  }
  return r <= 0 ? null : r;
}

/// Whether a candidate R:R satisfies the MGC R7 floor on TP2.
bool meetsTp2Floor(double tp2RewardRisk, {double floor = 1.8}) => tp2RewardRisk >= floor;

/// Disclaims the plan for display (MGC R11: every signal carries it).
const String riskDisclaimer =
    'Signals are educational setup analysis, not financial advice. '
    'Gold is leveraged and volatile; you can lose more than you expect. '
    'XV does not execute trades.';