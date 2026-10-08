/// Wording for the regime summary card. Pure functions so the language is
/// pinned by tests, not eyeballed.
///
/// Vocabulary rule: regime words only (bullish / bearish / ranging / mixed).
/// LONG/SHORT belong to consensus verdicts and never appear here, so a
/// context card can never be mistaken for a trade call.
library;

import 'package:xau_core/xau_core.dart' show RegimeState, RegimeSummary;

/// 'BULLISH LEAN' / 'BEARISH LEAN' / 'MIXED — NO LEAN'.
String regimeStateWord(RegimeState state) => switch (state) {
      RegimeState.bullish => 'BULLISH LEAN',
      RegimeState.bearish => 'BEARISH LEAN',
      RegimeState.mixed => 'MIXED — NO LEAN',
    };

/// '3 of 4 agree' for a decided summary, '2 of 4 · split' for mixed.
String regimeFractionText(RegimeSummary s) {
  final top = s.bull > s.bear ? s.bull : s.bear;
  if (s.state == RegimeState.mixed) return '${s.bull + s.bear} of ${s.total} · split';
  return '$top of ${s.total} agree';
}

/// One-line read of where the agreement sits, plus the trend qualifier.
///
/// [bullAreas]/[bearAreas] name the layers on each side in display words
/// ('direction', 'momentum', 'intraday'). Mixed never claims a lean no
/// matter the counts.
String regimeNote({
  required RegimeSummary summary,
  required List<String> bullAreas,
  required List<String> bearAreas,
  required bool strongTrend,
  required bool weakTrend,
}) {
  final main = switch (summary.state) {
    RegimeState.bullish =>
      'Bullish across ${_joinAreas(bullAreas)}. ${strongTrend ? 'Trend strong — moves have follow-through.' : 'Trend is not strong — size accordingly.'}',
    RegimeState.bearish =>
      'Bearish across ${_joinAreas(bearAreas)}. ${strongTrend ? 'Trend strong — moves have follow-through.' : 'Trend is not strong — size accordingly.'}',
    RegimeState.mixed when bullAreas.isNotEmpty || bearAreas.isNotEmpty =>
      'Split read — ${_splitText(bullAreas, bearAreas)} Nothing to lean on.',
    RegimeState.mixed => 'No lean either way. Nothing to lean on.',
  };
  if (summary.state != RegimeState.mixed) return main;
  final extra = weakTrend ? ' Weak trend — chop likely.' : '';
  return '$main$extra';
}

String _joinAreas(List<String> areas) {
  final a = areas.toSet().toList();
  if (a.isEmpty) return 'the board';
  if (a.length == 1) return a.first;
  return '${a.sublist(0, a.length - 1).join(', ')} and ${a.last}';
}

String _splitText(List<String> bull, List<String> bear) {
  final parts = <String>[];
  if (bull.isNotEmpty) parts.add('${_joinAreas(bull)} bullish');
  if (bear.isNotEmpty) parts.add('${_joinAreas(bear)} bearish');
  if (parts.isEmpty) return '';
  return '${parts.join(', ')}. ';
}

/// Display lean word for a tile pill. Regime vocabulary, never LONG/SHORT.
String leanWord(String lean) => switch (lean) {
      'bullish' => 'BULLISH',
      'bearish' => 'BEARISH',
      _ => 'NEUTRAL',
    };
