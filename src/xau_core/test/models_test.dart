import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

void main() {
  group('ConsensusStrength bands (spec §7 exact)', () {
    test('boundaries map exactly', () {
      expect(ConsensusStrength.fromScore(0), ConsensusStrength.weak);
      expect(ConsensusStrength.fromScore(39), ConsensusStrength.weak);
      expect(ConsensusStrength.fromScore(40), ConsensusStrength.developing);
      expect(ConsensusStrength.fromScore(59), ConsensusStrength.developing);
      expect(ConsensusStrength.fromScore(60), ConsensusStrength.moderate);
      expect(ConsensusStrength.fromScore(74), ConsensusStrength.moderate);
      expect(ConsensusStrength.fromScore(75), ConsensusStrength.strong);
      expect(ConsensusStrength.fromScore(89), ConsensusStrength.strong);
      expect(ConsensusStrength.fromScore(90), ConsensusStrength.veryStrong);
      expect(ConsensusStrength.fromScore(100), ConsensusStrength.veryStrong);
    });

    test('min/max score accessors match bands', () {
      expect(ConsensusStrength.weak.minScore, 0);
      expect(ConsensusStrength.weak.maxScore, 39);
      expect(ConsensusStrength.developing.minScore, 40);
      expect(ConsensusStrength.developing.maxScore, 59);
      expect(ConsensusStrength.moderate.minScore, 60);
      expect(ConsensusStrength.moderate.maxScore, 74);
      expect(ConsensusStrength.strong.minScore, 75);
      expect(ConsensusStrength.strong.maxScore, 89);
      expect(ConsensusStrength.veryStrong.minScore, 90);
      expect(ConsensusStrength.veryStrong.maxScore, 100);
    });

    test('clamps out-of-range scores', () {
      expect(ConsensusStrength.fromScore(-5), ConsensusStrength.weak);
      expect(ConsensusStrength.fromScore(1000), ConsensusStrength.veryStrong);
    });

    test('json round-trip', () {
      for (final s in ConsensusStrength.values) {
        expect(ConsensusStrength.fromJson(s.toJson()), s);
      }
    });
  });

  group('Freshness buckets (spec §15)', () {
    final now = DateTime.utc(2026, 9, 29, 12);
    test('thresholds', () {
      expect(Freshness.fromAge(const Duration(minutes: 5)),
          Freshness.veryFresh);
      expect(
          Freshness.fromAge(const Duration(minutes: 14, seconds: 59)),
          Freshness.veryFresh);
      expect(Freshness.fromAge(const Duration(minutes: 15)), Freshness.fresh);
      expect(Freshness.fromAge(const Duration(minutes: 29)), Freshness.fresh);
      expect(Freshness.fromAge(const Duration(minutes: 30)), Freshness.aging);
      expect(Freshness.fromAge(const Duration(minutes: 59)), Freshness.aging);
      expect(Freshness.fromAge(const Duration(minutes: 60)), Freshness.expired);
      expect(Freshness.fromAge(const Duration(hours: 3)), Freshness.expired);
    });

    test('fromTimestamps uses passed now', () {
      expect(
          Freshness.fromTimestamps(now.subtract(const Duration(minutes: 3)),
              now),
          Freshness.veryFresh);
      expect(Freshness.fromTimestamps(null, now), Freshness.aging);
    });
  });

  group('PriceRange', () {
    test('mid/width/contains', () {
      final r = PriceRange(low: 4275, high: 4280);
      expect(r.mid, 4277.5);
      expect(r.width, 5);
      expect(r.contains(4277), isTrue);
      expect(r.contains(4300), isFalse);
    });

    test('rejects inverted range', () {
      expect(() => PriceRange(low: 5, high: 4), throwsArgumentError);
    });

    test('json round-trip', () {
      final r = PriceRange(low: 4275.5, high: 4280.25);
      expect(PriceRange.fromJson(r.toJson()), r);
    });
  });

  group('TakeProfit', () {
    test('rejects index < 1', () {
      expect(() => TakeProfit(index: 0, price: 1), throwsArgumentError);
    });

    test('json round-trip', () {
      final tp = TakeProfit(index: 2, price: 4315);
      expect(TakeProfit.fromJson(tp.toJson()), tp);
    });
  });

  group('TradeIdea', () {
    test('json round-trip preserves every spec §4 field', () {
      final idea = TradeIdea(
        id: 'a',
        source: 'Source A',
        sourceUrl: 'https://example.com/a',
        author: 'Analyst A',
        publishedAt: DateTime.utc(2026, 9, 29, 11, 50),
        collectedAt: DateTime.utc(2026, 9, 29, 11, 55),
        symbol: 'XAUUSD',
        timeframe: TradeTimeframe.m15,
        direction: Direction.long,
        entryType: 'zone',
        entryLow: 4275,
        entryHigh: 4280,
        stopLoss: 4262,
        takeProfits: [
          TakeProfit(index: 1, price: 4295),
          TakeProfit(index: 2, price: 4315),
        ],
        triggerCondition: 'hold above 4275',
        invalidationCondition: 'break below 4262',
        reasoning: 'bullish breakout momentum',
        confidence: 0.7,
        freshness: Freshness.veryFresh,
        sourceFingerprint: 'fp-a',
      );
      final back = TradeIdea.fromJson(idea.toJson());
      expect(back.id, idea.id);
      expect(back.source, idea.source);
      expect(back.sourceUrl, idea.sourceUrl);
      expect(back.author, idea.author);
      expect(back.publishedAt, idea.publishedAt);
      expect(back.collectedAt, idea.collectedAt);
      expect(back.symbol, idea.symbol);
      expect(back.timeframe, idea.timeframe);
      expect(back.direction, idea.direction);
      expect(back.entryType, idea.entryType);
      expect(back.entryLow, idea.entryLow);
      expect(back.entryHigh, idea.entryHigh);
      expect(back.stopLoss, idea.stopLoss);
      expect(back.takeProfits, idea.takeProfits);
      expect(back.triggerCondition, idea.triggerCondition);
      expect(back.invalidationCondition, idea.invalidationCondition);
      expect(back.reasoning, idea.reasoning);
      expect(back.confidence, idea.confidence);
      expect(back.freshness, idea.freshness);
      expect(back.sourceFingerprint, idea.sourceFingerprint);
      expect(back.entryRange, PriceRange(low: 4275, high: 4280));
      expect(back.entryMid, 4277.5);
      expect(back.hasActionableLevels, isTrue);
    });

    test('hasActionableLevels false when levels missing', () {
      final idea = TradeIdea(
        id: 'x',
        source: 's',
        timeframe: TradeTimeframe.m15,
        direction: Direction.long,
      );
      expect(idea.hasActionableLevels, isFalse);
      expect(idea.entryRange, isNull);
      expect(idea.entryMid, isNull);
    });

    test('enum parse errors throw', () {
      expect(() => Direction.fromJson('up'), throwsArgumentError);
      expect(() => TradeTimeframe.fromJson('D1'), throwsArgumentError);
      expect(() => SignalStatus.fromJson('X'), throwsArgumentError);
      expect(() => Freshness.fromJson('stale'), throwsArgumentError);
    });
  });

  group('ConsensusSignal', () {
    test('strength band derives from score', () {
      final sig = ConsensusSignal(
        id: 's1',
        direction: Direction.long,
        strength: 82,
        entryLow: 4275,
        entryHigh: 4280,
        stopLoss: 4263,
        tp1: 4296,
        tp2: 4317,
      );
      expect(sig.strengthBand, ConsensusStrength.strong);
      expect(sig.entryZone, PriceRange(low: 4275, high: 4280));
      expect(sig.takeProfitList, [4296, 4317]);
    });

    test('json round-trip', () {
      final sig = ConsensusSignal(
        id: 's1',
        direction: Direction.short,
        strength: 61,
        entryLow: 4280,
        entryHigh: 4285,
        stopLoss: 4300,
        tp1: 4260,
        status: SignalStatus.ready,
        createdAt: DateTime.utc(2026, 9, 29, 12),
        updatedAt: DateTime.utc(2026, 9, 29, 12, 1),
        expiresAt: DateTime.utc(2026, 9, 29, 13),
        independentSourceCount: 3,
        totalSourceCount: 4,
        agreeingSourceIds: const ['a', 'b'],
      );
      final back = ConsensusSignal.fromJson(sig.toJson());
      expect(back.id, sig.id);
      expect(back.direction, sig.direction);
      expect(back.strength, sig.strength);
      expect(back.entryLow, sig.entryLow);
      expect(back.entryHigh, sig.entryHigh);
      expect(back.stopLoss, sig.stopLoss);
      expect(back.tp1, sig.tp1);
      expect(back.status, sig.status);
      expect(back.independentSourceCount, 3);
      expect(back.agreeingSourceIds, ['a', 'b']);
    });

    test('validation rejects bad strength/range', () {
      expect(
          () => ConsensusSignal(
              id: 'x',
              direction: Direction.long,
              strength: 101,
              entryLow: 1,
              entryHigh: 2,
              stopLoss: 0),
          throwsArgumentError);
      expect(
          () => ConsensusSignal(
              id: 'x',
              direction: Direction.long,
              strength: 50,
              entryLow: 5,
              entryHigh: 4,
              stopLoss: 0),
          throwsArgumentError);
    });
  });
}
