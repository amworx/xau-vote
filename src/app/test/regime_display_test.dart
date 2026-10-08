import 'package:flutter_test/flutter_test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xauvote/models/regime_display.dart';

void main() {
  group('regime summary wording', () {
    test('states read as leans, never as trade direction', () {
      expect(regimeStateWord(RegimeState.bullish), 'BULLISH LEAN');
      expect(regimeStateWord(RegimeState.bearish), 'BEARISH LEAN');
      expect(regimeStateWord(RegimeState.mixed), 'MIXED — NO LEAN');
      for (final w in [
        regimeStateWord(RegimeState.bullish),
        regimeStateWord(RegimeState.bearish),
        regimeStateWord(RegimeState.mixed),
      ]) {
        expect(w.contains('LONG'), isFalse);
        expect(w.contains('SHORT'), isFalse);
      }
    });

    test('fractions count camps, splits say split', () {
      const s = RegimeSummary(
          state: RegimeState.bullish, bull: 3, bear: 1, total: 4, strongTrend: true);
      expect(regimeFractionText(s), '3 of 4 agree');
      const m = RegimeSummary(
          state: RegimeState.mixed, bull: 2, bear: 2, total: 4, strongTrend: false);
      expect(regimeFractionText(m), '4 of 4 · split');
    });

    test('bullish note names areas and trend support', () {
      const s = RegimeSummary(
          state: RegimeState.bullish, bull: 3, bear: 0, total: 4, strongTrend: true);
      final n = regimeNote(
        summary: s,
        bullAreas: const ['direction', 'momentum', 'intraday'],
        bearAreas: const [],
        strongTrend: true,
        weakTrend: false,
      );
      expect(n, contains('Bullish across direction, momentum and intraday.'));
      expect(n, contains('follow-through'));
    });

    test('mixed never leans and names the split', () {
      const s = RegimeSummary(
          state: RegimeState.mixed, bull: 1, bear: 1, total: 4, strongTrend: false);
      final n = regimeNote(
        summary: s,
        bullAreas: const ['direction'],
        bearAreas: const ['momentum'],
        strongTrend: false,
        weakTrend: true,
      );
      expect(n, contains('Split read'));
      expect(n, contains('Nothing to lean on.'));
      expect(n, contains('chop likely'));
    });
  });
}
