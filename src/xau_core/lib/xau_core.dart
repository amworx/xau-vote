/// XV (XAU-Vote) core: pure-Dart domain models, consensus logic and technical
/// analysis.
///
/// No Flutter, no I/O, no network. Time is always passed in by callers.
library;

export 'analysis/calendar_lock.dart';
export 'analysis/confluence.dart';
// The consensus package already exports an `IndependenceResult` used for
// cluster vote weighting. This module's result is hidden from the barrel so
// callers import it explicitly, keeping the two meanings of "independence"
// unambiguous instead of silently shadowing one with the other.
export 'analysis/independence.dart' hide IndependenceResult;
export 'analysis/indicators.dart';
export 'analysis/scanner.dart';
export 'analysis/session.dart';
export 'analysis/stop_plan.dart';
export 'consensus/consensus.dart';
export 'models/candle.dart';
export 'models/models.dart';
