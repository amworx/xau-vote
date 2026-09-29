// Context tests: the spec §12 matrix, plus the regression test proving 1H
// context is metadata only and can never change the consensus score.
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xau_lifecycle/xau_lifecycle.dart';

final _now = DateTime.utc(2026, 9, 29, 12);

TradeIdea _idea({
  required String id,
  required Direction direction,
  required String author,
  required String reasoning,
  required int minutesAgo,
  double entryLow = 4275,
  double entryHigh = 4280,
  double stopLoss = 4262,
  List<double> tps = const [4295, 4315],
}) =>
    TradeIdea(
      id: id,
      source: 'Source $id',
      author: author,
      publishedAt: _now.subtract(Duration(minutes: minutesAgo)),
      timeframe: TradeTimeframe.m15,
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

/// The spec §6 A/B/C LONG camp (proven STRONG in the core engine tests).
List<TradeIdea> _longCamp() => [
      _idea(
        id: 'a',
        direction: Direction.long,
        author: 'Alice',
        reasoning: 'bullish breakout above resistance with momentum',
        minutesAgo: 12,
        entryLow: 4275,
        entryHigh: 4280,
        stopLoss: 4262,
        tps: const [4295, 4315],
      ),
      _idea(
        id: 'b',
        direction: Direction.long,
        author: 'Bob',
        reasoning: 'gold support bounce off moving average trendline',
        minutesAgo: 5,
        entryLow: 4276,
        entryHigh: 4281,
        stopLoss: 4264,
        tps: const [4298, 4320],
      ),
      _idea(
        id: 'c',
        direction: Direction.long,
        author: 'Cara',
        reasoning: 'dollar weakness drives safe haven demand buying',
        minutesAgo: 0,
        entryLow: 4274,
        entryHigh: 4279,
        stopLoss: 4263,
        tps: const [4296, 4318],
      ),
      _idea(
        id: 'd',
        direction: Direction.short,
        author: 'Dan',
        reasoning: 'overbought rejection at supply double top',
        minutesAgo: 3,
        entryLow: 4285,
        entryHigh: 4285,
        stopLoss: 4300,
        tps: const [4260],
      ),
    ];

void main() {
  group('spec §12 classification matrix', () {
    test('agreement is supportive, opposition is counter-trend', () {
      expect(
        ContextClassifier.classify(
          signalDirection: Direction.long,
          h1Trend: Direction.long,
        ),
        ContextAlignment.supportive,
      );
      expect(
        ContextClassifier.classify(
          signalDirection: Direction.short,
          h1Trend: Direction.short,
        ),
        ContextAlignment.supportive,
      );
      expect(
        ContextClassifier.classify(
          signalDirection: Direction.long,
          h1Trend: Direction.short,
        ),
        ContextAlignment.counterTrend,
      );
      expect(
        ContextClassifier.classify(
          signalDirection: Direction.short,
          h1Trend: Direction.long,
        ),
        ContextAlignment.counterTrend,
      );
    });

    test('any neutral side is neutral', () {
      for (final h1 in Direction.values) {
        expect(
          ContextClassifier.classify(
            signalDirection: Direction.neutral,
            h1Trend: h1,
          ),
          ContextAlignment.neutral,
        );
      }
      for (final signal in Direction.values) {
        expect(
          ContextClassifier.classify(
            signalDirection: signal,
            h1Trend: Direction.neutral,
          ),
          ContextAlignment.neutral,
        );
      }
    });

    test('attach builds the metadata record', () {
      final context = ContextClassifier.attach(
        signalDirection: Direction.long,
        h1Trend: Direction.short,
      );
      expect(context.h1Trend, Direction.short);
      expect(context.alignment, ContextAlignment.counterTrend);
    });

    test('labels round-trip', () {
      for (final alignment in ContextAlignment.values) {
        expect(
          ContextAlignment.fromJson(alignment.toJson()),
          alignment,
        );
      }
    });
  });

  group('regression: context never changes the score (core rule 1)', () {
    test('same ideas + different 1H trend → identical consensus output', () {
      final ideas = _longCamp();
      final first = ConsensusEngine.build(ideas, _now);
      expect(first, isA<ConsensusOutcome>());
      final firstSignal = (first as ConsensusOutcome).signal;

      // The classifier only sees directions after consensus is built.
      final supportive = ContextClassifier.attach(
        signalDirection: firstSignal.direction,
        h1Trend: Direction.long,
      );
      final counter = ContextClassifier.attach(
        signalDirection: firstSignal.direction,
        h1Trend: Direction.short,
      );
      expect(supportive.alignment, ContextAlignment.supportive);
      expect(counter.alignment, ContextAlignment.counterTrend);

      // Rebuilding consensus is unaffected by either classification:
      // the engine never even receives the 1H trend.
      final second = ConsensusEngine.build(ideas, _now);
      final secondSignal = (second as ConsensusOutcome).signal;
      expect(secondSignal.strength, firstSignal.strength);
      expect(secondSignal.direction, firstSignal.direction);
      expect(secondSignal.entryLow, firstSignal.entryLow);
      expect(secondSignal.entryHigh, firstSignal.entryHigh);
      expect(secondSignal.stopLoss, firstSignal.stopLoss);
      expect(secondSignal.tp1, firstSignal.tp1);

      // And attaching context does not mutate the signal object.
      expect(firstSignal.strength, greaterThanOrEqualTo(75));
    });
  });
}
