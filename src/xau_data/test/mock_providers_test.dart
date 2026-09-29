// Provider unit tests: scripted ticks (advance/clamp/reset/stream) and
// the mock idea source `since` filter.
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xau_data/xau_data.dart';

final _t0 = DateTime.utc(2026, 9, 29, 12);

PriceQuote _q(double price, DateTime at) => PriceQuote(
      symbol: 'XAUUSD',
      price: price,
      bid: price - 0.2,
      ask: price + 0.2,
      timestamp: at,
    );

void main() {
  group('MockMarketDataProvider', () {
    test('serves the scripted series in order, then replays the last tick',
        () async {
      final market = MockMarketDataProvider(script: [
        _q(4270, _t0),
        _q(4277, _t0.add(const Duration(minutes: 1))),
      ]);
      expect(market.cursor, 0);
      expect((await market.currentPrice('XAUUSD')).price, 4270);
      expect(market.cursor, 1);
      expect((await market.currentPrice('XAUUSD')).price, 4277);
      // Clamped: over-reads replay the final tick instead of throwing.
      expect((await market.currentPrice('XAUUSD')).price, 4277);
    });

    test('reset replays from the start', () async {
      final market = MockMarketDataProvider(script: [
        _q(4270, _t0),
        _q(4277, _t0.add(const Duration(minutes: 1))),
      ]);
      await market.currentPrice('XAUUSD');
      await market.currentPrice('XAUUSD');
      market.reset();
      expect(market.cursor, 0);
      expect((await market.currentPrice('XAUUSD')).price, 4270);
    });

    test('watchPrice yields remaining ticks in order', () async {
      final market = MockMarketDataProvider(script: [
        _q(4270, _t0),
        _q(4277, _t0.add(const Duration(minutes: 1))),
        _q(4280, _t0.add(const Duration(minutes: 2))),
      ]);
      final seen = await market
          .watchPrice('XAUUSD', Duration.zero)
          .map((quote) => quote.price)
          .toList();
      expect(seen, [4270, 4277, 4280]);
      expect(market.cursor, 3);
    });

    test('empty script throws', () {
      expect(() => MockMarketDataProvider(script: const []),
          throwsArgumentError);
    });
  });

  group('MockIdeaSource', () {
    test('fetchRecent filters on since; null timestamps always pass',
        () async {
      final source = MockIdeaSource.abcd(_t0);
      // Whole window: all four ideas (oldest is 12 min ago).
      expect(
        (await source.fetchRecent(
                since: _t0.subtract(const Duration(hours: 1))))
            .map((idea) => idea.id),
        containsAll(['a', 'b', 'c', 'd']),
      );
      // `since: now` keeps only the idea published exactly at now.
      expect(
        (await source.fetchRecent(since: _t0)).map((idea) => idea.id),
        ['c'],
      );
      // Past the newest: empty.
      expect(
        await source.fetchRecent(
            since: _t0.add(const Duration(minutes: 1))),
        isEmpty,
      );
    });

    test('untimestamped ideas always pass the since filter', () async {
      final timeless = TradeIdea(
        id: 'timeless',
        source: 'mock',
        timeframe: TradeTimeframe.m15,
        direction: Direction.long,
        entryLow: 4275,
        entryHigh: 4280,
        stopLoss: 4262,
        takeProfits: [TakeProfit(index: 1, price: 4295)],
      );
      final source = MockIdeaSource([timeless]);
      expect(
        await source.fetchRecent(
            since: _t0.add(const Duration(days: 1))),
        hasLength(1),
      );
    });

    test('all five fixtures build without throwing', () {
      expect(MockFixtures.abcd(_t0), hasLength(4));
      expect(MockFixtures.fourCopies(_t0), hasLength(4));
      expect(MockFixtures.divided(_t0), hasLength(5));
      expect(MockFixtures.staleOnly(_t0), hasLength(3));
      expect(MockFixtures.missingLevels(_t0), hasLength(2));
      for (final ideas in [
        MockFixtures.abcd(_t0),
        MockFixtures.fourCopies(_t0),
        MockFixtures.divided(_t0),
      ]) {
        for (final idea in ideas) {
          expect(idea.hasActionableLevels, isTrue);
        }
      }
      for (final idea in MockFixtures.missingLevels(_t0)) {
        expect(idea.hasActionableLevels, isFalse);
      }
    });
  });
}
