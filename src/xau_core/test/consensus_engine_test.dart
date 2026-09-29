import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

final _now = DateTime.utc(2026, 9, 29, 12);

TradeIdea mk({
  required String id,
  required Direction direction,
  double? entryLow,
  double? entryHigh,
  double? stopLoss,
  List<double> tps = const [],
  String? author,
  String? reasoning,
  DateTime? publishedAt,
  String source = 'src',
  TradeTimeframe timeframe = TradeTimeframe.m15,
  String symbol = 'XAUUSD',
}) {
  return TradeIdea(
    id: id,
    source: source,
    author: author,
    publishedAt: publishedAt ?? _now.subtract(const Duration(minutes: 5)),
    timeframe: timeframe,
    symbol: symbol,
    direction: direction,
    entryLow: entryLow,
    entryHigh: entryHigh,
    stopLoss: stopLoss,
    takeProfits: [
      for (var i = 0; i < tps.length; i++)
        TakeProfit(index: i + 1, price: tps[i]),
    ],
    reasoning: reasoning,
  );
}

void main() {
  group('spec §6 example: A/B/C LONG cluster, D excluded', () {
    test('strength ≥ STRONG with expected levels', () {
      final ideas = [
        mk(
            id: 'a',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295, 4315],
            author: 'Alice',
            reasoning: 'bullish breakout above resistance with momentum',
            publishedAt: _now.subtract(const Duration(minutes: 12))),
        mk(
            id: 'b',
            direction: Direction.long,
            entryLow: 4276,
            entryHigh: 4281,
            stopLoss: 4264,
            tps: [4298, 4320],
            author: 'Bob',
            reasoning: 'gold support bounce off moving average trendline',
            publishedAt: _now.subtract(const Duration(minutes: 5))),
        mk(
            id: 'c',
            direction: Direction.long,
            entryLow: 4274,
            entryHigh: 4279,
            stopLoss: 4263,
            tps: [4296, 4318],
            author: 'Cara',
            reasoning: 'dollar weakness drives safe haven demand buying',
            publishedAt: _now),
        mk(
            id: 'd',
            direction: Direction.short,
            entryLow: 4285,
            entryHigh: 4285,
            stopLoss: 4300,
            tps: [4260],
            author: 'Dan',
            reasoning: 'overbought rejection at supply double top',
            publishedAt: _now.subtract(const Duration(minutes: 3))),
      ];
      final result = ConsensusEngine.build(ideas, _now);
      expect(result, isA<ConsensusOutcome>());
      final outcome = result as ConsensusOutcome;
      final sig = outcome.signal;
      expect(sig.direction, Direction.long);
      expect(sig.strength, greaterThanOrEqualTo(75));
      expect(sig.strengthBand, isIn(
          [ConsensusStrength.strong, ConsensusStrength.veryStrong]));
      expect(sig.entryLow, 4275);
      expect(sig.entryHigh, 4280);
      expect(sig.stopLoss, closeTo(4263, 1.0));
      expect(sig.tp1, closeTo(4296, 1.5));
      expect(sig.tp2, closeTo(4317, 2.0));
      // Dissenting SHORT idea excluded from the cluster.
      expect(sig.agreeingSourceIds, containsAll(['a', 'b', 'c']));
      expect(sig.agreeingSourceIds, isNot(contains('d')));
      expect(sig.independentSourceCount, 3);
      expect(outcome.directionCounts[Direction.long], 3);
      expect(outcome.directionCounts[Direction.short], 1);
    });
  });

  group('spec §5 via engine: four copies → SINGLE_SOURCE no-consensus', () {
    test('copies collapse to one independent vote', () {
      final ideas = List.generate(
        4,
        (i) => mk(
          id: 'copy-$i',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295, 4315],
          author: 'Same Analyst',
          reasoning: 'same copied call long gold breakout',
          publishedAt: _now.subtract(Duration(minutes: 6 - i)),
          source: 'Source $i',
        ),
      );
      final result = ConsensusEngine.build(ideas, _now);
      expect(result, isA<NoConsensus>());
      final nc = result as NoConsensus;
      expect(nc.reason, 'SINGLE_SOURCE');
      expect(nc.independentVotes, closeTo(1.15, 0.01));
    });
  });

  group('spec §3 divided room: 2L/2S/1N → NO CONSENSUS', () {
    test('counts exposed', () {
      final ideas = [
        mk(
            id: 'l1',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            author: 'A',
            reasoning: 'alpha breakout momentum buying',
            publishedAt: _now.subtract(const Duration(minutes: 4))),
        mk(
            id: 'l2',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            author: 'B',
            reasoning: 'completely different zulu yahoo quasar',
            publishedAt: _now.subtract(const Duration(minutes: 20))),
        mk(
            id: 's1',
            direction: Direction.short,
            entryLow: 4285,
            entryHigh: 4290,
            stopLoss: 4305,
            tps: [4260],
            author: 'C',
            reasoning: 'rejection supply double top shorting',
            publishedAt: _now.subtract(const Duration(minutes: 6))),
        mk(
            id: 's2',
            direction: Direction.short,
            entryLow: 4286,
            entryHigh: 4291,
            stopLoss: 4306,
            tps: [4261],
            author: 'D',
            reasoning: 'overbought reversal breakdown selling',
            publishedAt: _now.subtract(const Duration(minutes: 25))),
        mk(
            id: 'n1',
            direction: Direction.neutral,
            entryLow: 4278,
            entryHigh: 4282,
            stopLoss: 4270,
            tps: [4290],
            author: 'E',
            reasoning: 'waiting sideways chop indecision непонятно',
            publishedAt: _now.subtract(const Duration(minutes: 8))),
      ];
      final result = ConsensusEngine.build(ideas, _now);
      expect(result, isA<NoConsensus>());
      final nc = result as NoConsensus;
      expect(nc.reason, 'DIVIDED');
      expect(nc.directionCounts[Direction.long], 2);
      expect(nc.directionCounts[Direction.short], 2);
      expect(nc.directionCounts[Direction.neutral], 1);
    });
  });

  group('single independent source → NO CONSENSUS', () {
    test('one idea is never enough', () {
      final ideas = [
        mk(
            id: 'only',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            author: 'Solo',
            reasoning: 'lone call',
            publishedAt: _now.subtract(const Duration(minutes: 2))),
      ];
      final result = ConsensusEngine.build(ideas, _now);
      expect(result, isA<NoConsensus>());
      expect((result as NoConsensus).reason, 'SINGLE_SOURCE');
    });
  });

  group('filtering rules', () {
    test('empty input → INSUFFICIENT_DATA', () {
      final r = ConsensusEngine.build([], _now);
      expect(r, isA<NoConsensus>());
      expect((r as NoConsensus).reason, 'INSUFFICIENT_DATA');
    });

    test('non-XAUUSD, non-M15, stale, level-less, future ideas ignored', () {
      final ideas = [
        mk(
            id: 'fx',
            direction: Direction.long,
            entryLow: 1.1,
            entryHigh: 1.2,
            stopLoss: 1.0,
            tps: [1.3],
            symbol: 'EURUSD'),
        mk(
            id: 'h1',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            timeframe: TradeTimeframe.h1),
        mk(
            id: 'stale',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            publishedAt: _now.subtract(const Duration(minutes: 90))),
        mk(id: 'nolevels', direction: Direction.long),
        mk(
            id: 'future',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            publishedAt: _now.add(const Duration(minutes: 5))),
      ];
      final r = ConsensusEngine.build(ideas, _now);
      expect(r, isA<NoConsensus>());
      expect((r as NoConsensus).reason, 'INSUFFICIENT_DATA');
    });

    test('exact 1:1 tie → DIVIDED', () {
      final ideas = [
        mk(
            id: 'l',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            author: 'A',
            publishedAt: _now.subtract(const Duration(minutes: 2))),
        mk(
            id: 's',
            direction: Direction.short,
            entryLow: 4285,
            entryHigh: 4290,
            stopLoss: 4305,
            tps: [4260],
            author: 'B',
            publishedAt: _now.subtract(const Duration(minutes: 10))),
      ];
      final r = ConsensusEngine.build(ideas, _now);
      expect((r as NoConsensus).reason, 'DIVIDED');
    });

    test('neutral majority → NON_ACTIONABLE_DIRECTION', () {
      final ideas = [
        mk(
            id: 'n1',
            direction: Direction.neutral,
            entryLow: 4278,
            entryHigh: 4282,
            stopLoss: 4270,
            tps: [4290],
            author: 'A',
            reasoning: 'alpha beta gamma delta',
            publishedAt: _now.subtract(const Duration(minutes: 2))),
        mk(
            id: 'n2',
            direction: Direction.neutral,
            entryLow: 4290,
            entryHigh: 4294,
            stopLoss: 4282,
            tps: [4300],
            author: 'B',
            reasoning: 'zulu yahoo quasar xenon',
            publishedAt: _now.subtract(const Duration(minutes: 20))),
        mk(
            id: 'l1',
            direction: Direction.long,
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295],
            author: 'C',
            publishedAt: _now.subtract(const Duration(minutes: 4))),
      ];
      final r = ConsensusEngine.build(ideas, _now);
      expect((r as NoConsensus).reason, 'NON_ACTIONABLE_DIRECTION');
    });

    test('scattered camp → WEAK_AGREEMENT below 60', () {
      final ideas = [
        mk(
            id: 'l1',
            direction: Direction.long,
            entryLow: 4270,
            entryHigh: 4271,
            stopLoss: 4260,
            tps: [4290],
            author: 'A',
            reasoning: 'alpha beta gamma delta epsilon',
            publishedAt: _now.subtract(const Duration(minutes: 5))),
        mk(
            id: 'l2',
            direction: Direction.long,
            entryLow: 4290,
            entryHigh: 4291,
            stopLoss: 4280,
            tps: [4310],
            author: 'B',
            reasoning: 'zulu yahoo quasar xenon wobble',
            publishedAt: _now.subtract(const Duration(minutes: 25))),
        mk(
            id: 's1',
            direction: Direction.short,
            entryLow: 4285,
            entryHigh: 4290,
            stopLoss: 4305,
            tps: [4260],
            author: 'C',
            publishedAt: _now.subtract(const Duration(minutes: 6))),
      ];
      final r = ConsensusEngine.build(ideas, _now);
      expect(r, isA<NoConsensus>());
      expect((r as NoConsensus).reason, 'WEAK_AGREEMENT');
    });

    test('ideas without publishedAt are kept with neutral freshness', () {
      final a = TradeIdea(
          id: 'a',
          source: 's',
          timeframe: TradeTimeframe.m15,
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          takeProfits: [TakeProfit(index: 1, price: 4295)],
          author: 'A',
          reasoning: 'shared bullish breakout momentum gold');
      final b = TradeIdea(
          id: 'b',
          source: 's',
          timeframe: TradeTimeframe.m15,
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          takeProfits: [TakeProfit(index: 1, price: 4295)],
          author: 'B',
          reasoning: 'shared bullish breakout momentum gold');
      // Same levels + overlapping wording → duplicates despite no times,
      // so this pair must NOT reach consensus alone.
      final r = ConsensusEngine.build([a, b], _now);
      expect(r, isA<NoConsensus>());
    });
  });
}
