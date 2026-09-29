/// Core enumerations for XAU Radar domain models.
///
/// Strength bands match spec §7 exactly. Scores represent agreement among
/// sources, never a probability of profit.
library;

/// Trade direction of an idea or signal.
enum Direction {
  long,
  short,
  neutral;

  /// Parses a JSON string (`long`, `short`, `neutral`).
  static Direction fromJson(String value) {
    switch (value) {
      case 'long':
        return Direction.long;
      case 'short':
        return Direction.short;
      case 'neutral':
        return Direction.neutral;
      default:
        throw ArgumentError('Unknown Direction: $value');
    }
  }

  /// Serializes to JSON string.
  String toJson() {
    switch (this) {
      case Direction.long:
        return 'long';
      case Direction.short:
        return 'short';
      case Direction.neutral:
        return 'neutral';
    }
  }
}

/// Trading timeframe. Only [m15] may vote in consensus (spec core rule 1).
enum TradeTimeframe {
  m5,
  m15,
  h1;

  static TradeTimeframe fromJson(String value) {
    switch (value) {
      case 'M5':
        return TradeTimeframe.m5;
      case 'M15':
        return TradeTimeframe.m15;
      case 'H1':
        return TradeTimeframe.h1;
      default:
        throw ArgumentError('Unknown TradeTimeframe: $value');
    }
  }

  String toJson() {
    switch (this) {
      case TradeTimeframe.m5:
        return 'M5';
      case TradeTimeframe.m15:
        return 'M15';
      case TradeTimeframe.h1:
        return 'H1';
    }
  }
}

/// Signal lifecycle states (spec §14).
enum SignalStatus {
  noSetup,
  developing,
  ready,
  confirmed,
  active,
  tp1Hit,
  tp2Hit,
  tp3Hit,
  invalidated,
  expired;

  static SignalStatus fromJson(String value) {
    switch (value) {
      case 'NO_SETUP':
        return SignalStatus.noSetup;
      case 'DEVELOPING':
        return SignalStatus.developing;
      case 'READY':
        return SignalStatus.ready;
      case 'CONFIRMED':
        return SignalStatus.confirmed;
      case 'ACTIVE':
        return SignalStatus.active;
      case 'TP1_HIT':
        return SignalStatus.tp1Hit;
      case 'TP2_HIT':
        return SignalStatus.tp2Hit;
      case 'TP3_HIT':
        return SignalStatus.tp3Hit;
      case 'INVALIDATED':
        return SignalStatus.invalidated;
      case 'EXPIRED':
        return SignalStatus.expired;
      default:
        throw ArgumentError('Unknown SignalStatus: $value');
    }
  }

  String toJson() {
    switch (this) {
      case SignalStatus.noSetup:
        return 'NO_SETUP';
      case SignalStatus.developing:
        return 'DEVELOPING';
      case SignalStatus.ready:
        return 'READY';
      case SignalStatus.confirmed:
        return 'CONFIRMED';
      case SignalStatus.active:
        return 'ACTIVE';
      case SignalStatus.tp1Hit:
        return 'TP1_HIT';
      case SignalStatus.tp2Hit:
        return 'TP2_HIT';
      case SignalStatus.tp3Hit:
        return 'TP3_HIT';
      case SignalStatus.invalidated:
        return 'INVALIDATED';
      case SignalStatus.expired:
        return 'EXPIRED';
    }
  }
}

/// Idea freshness buckets (spec §15).
///
/// Thresholds: <15 min VERY FRESH, 15–30 FRESH, 30–60 AGING, 60+ EXPIRED.
enum Freshness {
  veryFresh,
  fresh,
  aging,
  expired;

  /// Derives freshness from an age duration. Pure function of [age].
  static Freshness fromAge(Duration age) {
    final minutes = age.inSeconds / 60.0;
    if (minutes < 15) return Freshness.veryFresh;
    if (minutes < 30) return Freshness.fresh;
    if (minutes < 60) return Freshness.aging;
    return Freshness.expired;
  }

  /// Derives freshness from timestamps. Caller passes [now]; no clock reads.
  static Freshness fromTimestamps(DateTime? publishedAt, DateTime now) {
    if (publishedAt == null) return Freshness.aging;
    return fromAge(now.difference(publishedAt));
  }

  /// Agreement-scoring weight for this bucket (0–1).
  double get agreementWeight {
    switch (this) {
      case Freshness.veryFresh:
        return 1.0;
      case Freshness.fresh:
        return 0.8;
      case Freshness.aging:
        return 0.4;
      case Freshness.expired:
        return 0.0;
    }
  }

  static Freshness fromJson(String value) {
    switch (value) {
      case 'veryFresh':
        return Freshness.veryFresh;
      case 'fresh':
        return Freshness.fresh;
      case 'aging':
        return Freshness.aging;
      case 'expired':
        return Freshness.expired;
      default:
        throw ArgumentError('Unknown Freshness: $value');
    }
  }

  String toJson() {
    switch (this) {
      case Freshness.veryFresh:
        return 'veryFresh';
      case Freshness.fresh:
        return 'fresh';
      case Freshness.aging:
        return 'aging';
      case Freshness.expired:
        return 'expired';
    }
  }
}

/// Consensus strength bands (spec §7, exact).
///
/// ```
/// 0–39     WEAK
/// 40–59    DEVELOPING
/// 60–74    MODERATE
/// 75–89    STRONG
/// 90–100   VERY STRONG
/// ```
///
/// The score is agreement among sources, never a probability of profit.
enum ConsensusStrength {
  weak,
  developing,
  moderate,
  strong,
  veryStrong;

  /// Maps a 0–100 agreement score to its band. Values are clamped.
  static ConsensusStrength fromScore(num score) {
    final s = score.clamp(0, 100);
    if (s <= 39) return ConsensusStrength.weak;
    if (s <= 59) return ConsensusStrength.developing;
    if (s <= 74) return ConsensusStrength.moderate;
    if (s <= 89) return ConsensusStrength.strong;
    return ConsensusStrength.veryStrong;
  }

  /// Minimum score that maps to this band.
  int get minScore {
    switch (this) {
      case ConsensusStrength.weak:
        return 0;
      case ConsensusStrength.developing:
        return 40;
      case ConsensusStrength.moderate:
        return 60;
      case ConsensusStrength.strong:
        return 75;
      case ConsensusStrength.veryStrong:
        return 90;
    }
  }

  /// Maximum score that maps to this band.
  int get maxScore {
    switch (this) {
      case ConsensusStrength.weak:
        return 39;
      case ConsensusStrength.developing:
        return 59;
      case ConsensusStrength.moderate:
        return 74;
      case ConsensusStrength.strong:
        return 89;
      case ConsensusStrength.veryStrong:
        return 100;
    }
  }

  static ConsensusStrength fromJson(String value) {
    switch (value) {
      case 'weak':
        return ConsensusStrength.weak;
      case 'developing':
        return ConsensusStrength.developing;
      case 'moderate':
        return ConsensusStrength.moderate;
      case 'strong':
        return ConsensusStrength.strong;
      case 'veryStrong':
        return ConsensusStrength.veryStrong;
      default:
        throw ArgumentError('Unknown ConsensusStrength: $value');
    }
  }

  String toJson() {
    switch (this) {
      case ConsensusStrength.weak:
        return 'weak';
      case ConsensusStrength.developing:
        return 'developing';
      case ConsensusStrength.moderate:
        return 'moderate';
      case ConsensusStrength.strong:
        return 'strong';
      case ConsensusStrength.veryStrong:
        return 'veryStrong';
    }
  }
}
