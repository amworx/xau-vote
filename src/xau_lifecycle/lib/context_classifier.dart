/// 1H context classification (spec §12). Metadata only: never votes.
library;

import 'package:xau_core/xau_core.dart';

/// Alignment of a 15M signal with the 1H trend (spec §12).
enum ContextAlignment {
  /// 15M and 1H agree (LONG/LONG or SHORT/SHORT).
  supportive,

  /// 15M opposes the 1H trend.
  counterTrend,

  /// Either side is neutral; no alignment statement is possible.
  neutral;

  /// Serializes to the spec-style label.
  String toJson() {
    switch (this) {
      case ContextAlignment.supportive:
        return 'SUPPORTIVE';
      case ContextAlignment.counterTrend:
        return 'COUNTER_TREND';
      case ContextAlignment.neutral:
        return 'NEUTRAL';
    }
  }

  /// Parses a spec-style label.
  static ContextAlignment fromJson(String value) {
    switch (value) {
      case 'SUPPORTIVE':
        return ContextAlignment.supportive;
      case 'COUNTER_TREND':
        return ContextAlignment.counterTrend;
      case 'NEUTRAL':
        return ContextAlignment.neutral;
      default:
        throw ArgumentError('Unknown ContextAlignment: $value');
    }
  }
}

/// 1H context attached to a signal.
///
/// Pure metadata: it carries no score and must never alter consensus output
/// (enforced by the regression test in `test/context_classifier_test.dart`).
class SignalContext {
  /// Externally supplied 1H trend direction.
  final Direction h1Trend;

  /// Alignment of the signal with [h1Trend].
  final ContextAlignment alignment;

  /// Attaches [alignment] of the signal to the [h1Trend].
  const SignalContext({required this.h1Trend, required this.alignment});
}

/// Classifies 1H context (spec §12).
///
/// - Same direction (LONG/LONG, SHORT/SHORT) → SUPPORTIVE.
/// - Opposite directions → COUNTER_TREND.
/// - Either side NEUTRAL → NEUTRAL.
///
/// Takes only directions and returns metadata; it cannot change any score.
class ContextClassifier {
  const ContextClassifier._();

  /// Classifies the alignment of [signalDirection] with [h1Trend].
  static ContextAlignment classify({
    required Direction signalDirection,
    required Direction h1Trend,
  }) {
    if (signalDirection == Direction.neutral ||
        h1Trend == Direction.neutral) {
      return ContextAlignment.neutral;
    }
    return signalDirection == h1Trend
        ? ContextAlignment.supportive
        : ContextAlignment.counterTrend;
  }

  /// Builds the context record for a signal direction and 1H trend.
  static SignalContext attach({
    required Direction signalDirection,
    required Direction h1Trend,
  }) =>
      SignalContext(
        h1Trend: h1Trend,
        alignment:
            classify(signalDirection: signalDirection, h1Trend: h1Trend),
      );
}
