/// Market-data provider abstraction (spec §18) + deterministic mock.
///
/// NOTE (T3.3, gated): a production `GoldApiProvider` must NOT be added
/// until Gate G3 passes — user confirmation plus a licensing/automation
/// review recorded in `memory/decisions.md` (spec §18). This file is the
/// natural home for it once the gate is cleared.
library;

/// A single price snapshot (spec §21 `market_snapshots` row).
class PriceQuote {
  /// Symbol, e.g. `XAUUSD`.
  final String symbol;

  /// Last price in quote currency points.
  final double price;

  /// Optional bid price.
  final double? bid;

  /// Optional ask price.
  final double? ask;

  /// When the quote was produced (caller-supplied; no clock reads here).
  final DateTime timestamp;

  /// Creates a snapshot. Bid/ask are optional; [price] is the driver.
  const PriceQuote({
    required this.symbol,
    required this.price,
    this.bid,
    this.ask,
    required this.timestamp,
  });

  @override
  String toString() => 'PriceQuote($symbol $price @ $timestamp)';
}

/// Market-data source (spec §18).
///
/// Implementations must be swappable with zero pipeline changes
/// (conformance-tested in `test/pipeline_test.dart`). Never hard-wire the
/// application to one provider.
abstract class MarketDataProvider {
  /// Latest quote for [symbol] (e.g. `XAUUSD`).
  Future<PriceQuote> currentPrice(String symbol);

  /// Quote stream, one tick per [interval].
  Stream<PriceQuote> watchPrice(String symbol, Duration interval);
}

/// Deterministic scripted provider for dev/test.
///
/// Each [currentPrice] call serves the next scripted tick and advances an
/// internal cursor (clamped at the last tick, so over-reads replay the
/// final price instead of throwing). [reset] replays the script from the
/// start. [watchPrice] yields the remaining ticks in order.
class MockMarketDataProvider implements MarketDataProvider {
  /// Scripted tick series, in serve order.
  final List<PriceQuote> script;

  int _cursor = 0;

  /// Creates a mock over [script] (must not be empty).
  MockMarketDataProvider({required List<PriceQuote> script})
      : script = List.unmodifiable(script) {
    if (script.isEmpty) {
      throw ArgumentError('Mock script must not be empty.');
    }
  }

  /// Index of the next tick to serve.
  int get cursor => _cursor;

  /// Replays the script from the start.
  void reset() {
    _cursor = 0;
  }

  @override
  Future<PriceQuote> currentPrice(String symbol) async {
    final quote =
        script[_cursor < script.length ? _cursor : script.length - 1];
    if (_cursor < script.length - 1) _cursor++;
    return quote;
  }

  @override
  Stream<PriceQuote> watchPrice(String symbol, Duration interval) async* {
    while (_cursor < script.length) {
      yield script[_cursor];
      _cursor++;
      if (interval > Duration.zero) {
        await Future.delayed(interval);
      }
    }
  }
}
