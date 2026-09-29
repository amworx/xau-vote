import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

TradeIdea idea({
  required String id,
  Direction direction = Direction.long,
  double? entryLow,
  double? entryHigh,
  double? stopLoss,
  List<double> tps = const [],
  String? author,
  String? reasoning,
  DateTime? publishedAt,
  String source = 'src',
}) {
  return TradeIdea(
    id: id,
    source: source,
    author: author,
    publishedAt: publishedAt,
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
}

void main() {
  group('fingerprint', () {
    test('normalizes direction/levels/author/bucket', () {
      final t = DateTime.utc(2026, 9, 29, 10, 37);
      final a = idea(
          id: 'a',
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295, 4315],
          author: 'Analyst X',
          publishedAt: t);
      final fp = IndependenceAssessor.fingerprint(a);
      expect(fp.startsWith('long|'), isTrue);
      expect(fp, contains('analyst x'));
      // 10:37 floors to the 10:35 five-minute bucket.
      expect(fp, contains('10:35'));
    });

    test('missing data uses na markers', () {
      final a = idea(id: 'a');
      expect(IndependenceAssessor.fingerprint(a), contains('na'));
    });
  });

  group('wordingSimilarity', () {
    test('identical texts score 1, disjoint score 0', () {
      expect(
          IndependenceAssessor.wordingSimilarity('gold breaks higher',
              'gold breaks higher'),
          1.0);
      expect(
          IndependenceAssessor.wordingSimilarity(
              'bullish breakout momentum', 'dollar weakness haven demand'),
          0.0);
    });

    test('empty input never counts as agreement', () {
      expect(IndependenceAssessor.wordingSimilarity(null, 'x'), 0.0);
      expect(IndependenceAssessor.wordingSimilarity('', ''), 0.0);
    });

    test('partial overlap is fractional', () {
      final s = IndependenceAssessor.wordingSimilarity(
          'gold bullish breakout momentum', 'gold bullish reversal risk');
      expect(s, greaterThan(0.0));
      expect(s, lessThan(1.0));
    });
  });

  group('spec §5: four copies → one independent vote', () {
    test('identical ideas collapse to a single group', () {
      final now = DateTime.utc(2026, 9, 29, 12);
      final ideas = List.generate(
        4,
        (i) => idea(
          id: 'copy-$i',
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295, 4315],
          author: 'Same Analyst',
          reasoning: 'same copied call long gold breakout',
          publishedAt: now.subtract(Duration(minutes: 6 - i)),
          source: 'Source ${'ABCD'[i]}',
        ),
      );
      final r = IndependenceAssessor.assess(ideas);
      expect(r.independentCount, 1);
      expect(r.groups.first.ideaIds.length, 4);
      // Earliest keeps 1.0, copies get epsilon.
      expect(r.weightOf('copy-0'), 1.0);
      expect(r.weightOf('copy-1'), duplicateEpsilon);
      expect(r.weightOf('copy-3'), duplicateEpsilon);
      expect(r.effectiveVotes, closeTo(1.15, 0.001));
      expect(r.weightOf('unknown'), 0.0);
    });
  });

  group('distinct ideas stay independent', () {
    test('spec §6 A/B/C are three votes', () {
      final now = DateTime.utc(2026, 9, 29, 12);
      final ideas = [
        idea(
            id: 'a',
            entryLow: 4275,
            entryHigh: 4280,
            stopLoss: 4262,
            tps: [4295, 4315],
            author: 'Alice',
            reasoning: 'bullish breakout above resistance with momentum',
            publishedAt: now.subtract(const Duration(minutes: 12))),
        idea(
            id: 'b',
            entryLow: 4276,
            entryHigh: 4281,
            stopLoss: 4264,
            tps: [4298, 4320],
            author: 'Bob',
            reasoning: 'gold support bounce off moving average trendline',
            publishedAt: now.subtract(const Duration(minutes: 5))),
        idea(
            id: 'c',
            entryLow: 4274,
            entryHigh: 4279,
            stopLoss: 4263,
            tps: [4296, 4318],
            author: 'Cara',
            reasoning: 'dollar weakness drives safe haven demand buying',
            publishedAt: now),
      ];
      final r = IndependenceAssessor.assess(ideas);
      expect(r.independentCount, 3);
    });

    test('same levels but different authors/times/wording stay separate', () {
      final now = DateTime.utc(2026, 9, 29, 12);
      final a = idea(
          id: 'a',
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295],
          author: 'Alice',
          reasoning: 'apples oranges bananas',
          publishedAt: now.subtract(const Duration(minutes: 30)));
      final b = idea(
          id: 'b',
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295],
          author: 'Bob',
          reasoning: 'cars trains planes',
          publishedAt: now);
      expect(IndependenceAssessor.isDuplicate(a, b), isFalse);
    });

    test('opposite directions never duplicate', () {
      final now = DateTime.utc(2026, 9, 29, 12);
      final a = idea(
          id: 'a',
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295],
          author: 'Same',
          reasoning: 'same words here',
          publishedAt: now);
      final b = idea(
          id: 'b',
          direction: Direction.short,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: [4295],
          author: 'Same',
          reasoning: 'same words here',
          publishedAt: now);
      expect(IndependenceAssessor.isDuplicate(a, b), isFalse);
    });
  });
}
