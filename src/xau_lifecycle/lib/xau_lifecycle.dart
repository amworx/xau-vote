/// XAU Radar lifecycle: state machine, freshness, confirmation, context.
///
/// Pure Dart. Time is always passed in by callers; this package never reads
/// the clock and never touches the network.
library;

export 'confirmation_evaluator.dart';
export 'context_classifier.dart';
export 'freshness_policy.dart';
export 'signal_state_machine.dart';
