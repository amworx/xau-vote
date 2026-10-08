/// Regime card widgets against a bars-serving fake backend.
///
/// Proves the Signal context card end to end: real bars in, regime tiles out,
/// toggles hide tiles, sentiment waits honestly. No fixtures: the bars are a
/// hand-built intraday rally with pullbacks, and every asserted reading is a
/// property of that series (uptrend, positive momentum), not a magic number.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xauvote/data/analysis_service.dart';
import 'package:xauvote/data/live_repository.dart';
import 'package:xauvote/models/sentiment_layers.dart';
import 'package:xauvote/state/app_state.dart';
import 'package:xauvote/theme.dart';
import 'package:xauvote/widgets/regime_card.dart';

/// 100 rising 15m candles with three sharp pullbacks (strict V-shapes so
/// fractal swings confirm cleanly) and tick volumes, ending higher. Regime
/// math must read an uptrend with positive momentum off this.
List<Candle> _rallyBars() {
  const dips = {20, 45, 70};
  final out = <Candle>[];
  var c = 4100.0;
  for (var i = 0; i < 100; i++) {
    final double o = c, h, l, close;
    if (dips.contains(i)) {
      close = c - 3.0;
      h = c + 0.1;
      // Deep wick: strictly below both neighbors so the fractal low
      // confirms (a tie with the next bar's low would disqualify it).
      l = close - 1.0;
    } else {
      close = c + 0.5;
      h = (c > close ? c : close) + 0.3;
      l = (c < close ? c : close) - 0.3;
    }
    out.add(Candle(
      openTime: DateTime.utc(2026, 10, 7, 6).add(Duration(minutes: 15 * i)),
      open: o,
      high: h,
      low: l,
      close: close,
      volume: 10.0 + (i % 5),
    ));
    c = close;
  }
  return out;
}

class _BarsRepo implements LiveRepository {
  @override
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async {
    return {
      Tf.m15: TimeframeBars(timeframe: Tf.m15, bars: _rallyBars(), allDegraded: false),
    };
  }

  @override
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async =>
      (spread: const VenueSpread.undisclosed(source: 'venue-internal'), ageSeconds: 5.0);

  @override
  Future<List<EconomicEvent>> analysisEvents({int hoursAhead = 24}) async => const [];

  @override
  Future<SentimentLayers> sentimentLayers() async => const SentimentLayers.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Future<void> _pumpRegime(
  WidgetTester tester, {
  AppState? state,
  required AnalysisService analysis,
}) async {
  final owned = state == null;
  state ??= AppState();
  if (owned) addTearDown(state.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: harborTheme(),
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: state),
          ChangeNotifierProvider<AnalysisService>.value(value: analysis),
        ],
        child: const Scaffold(body: SingleChildScrollView(child: RegimeSection())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('regime card reads real bars', () {
    testWidgets('uptrend renders the bullish stack', (tester) async {
      final analysis = AnalysisService(repository: _BarsRepo());
      addTearDown(analysis.dispose);
      await analysis.refresh();
      await _pumpRegime(tester, analysis: analysis);

      expect(find.text('BULLISH LEAN'), findsOneWidget);
      // Agreement fraction, not a probability.
      expect(find.textContaining('agree'), findsOneWidget);
      // Regime words only: LONG/SHORT belong to consensus verdicts.
      expect(find.text('LONG'), findsNothing);
      expect(find.text('SHORT'), findsNothing);
      // Tiles present with timeframe tags.
      expect(find.text('EMA stack + structure'), findsOneWidget);
      expect(find.text('RSI'), findsOneWidget);
      expect(find.text('MACD'), findsOneWidget);
      expect(find.text('VWAP'), findsOneWidget);
      expect(find.text('ATR'), findsOneWidget);
      expect(find.text('15M'), findsWidgets);
      // Honest volume: the fake carries volumes, so no pending tile.
      expect(find.text('Waiting for bars.'), findsNothing);
    });

    testWidgets('a toggle hides its tiles', (tester) async {
      final analysis = AnalysisService(repository: _BarsRepo());
      addTearDown(analysis.dispose);
      await analysis.refresh();
      final state = AppState();
      addTearDown(state.dispose);
      await _pumpRegime(tester, state: state, analysis: analysis);
      expect(find.text('RSI'), findsOneWidget);

      state.setIndRsi(false);
      await tester.pump();

      expect(find.text('RSI'), findsNothing);
      // The rest of the stack is untouched.
      expect(find.text('MACD'), findsOneWidget);
      expect(find.text('BULLISH LEAN'), findsOneWidget);
    });

    testWidgets('slow sentiment waits honestly', (tester) async {
      final analysis = AnalysisService(repository: _BarsRepo());
      addTearDown(analysis.dispose);
      await analysis.refresh();
      await _pumpRegime(tester, analysis: analysis);

      expect(find.text('COT positioning'), findsOneWidget);
      expect(find.text('FRED key pending'), findsWidgets);
      expect(find.text('Weekly job pending'), findsOneWidget);
    });

    testWidgets('no bars renders pending, never zeros', (tester) async {
      final analysis = AnalysisService(repository: _BarsRepoEmpty());
      addTearDown(analysis.dispose);
      await analysis.refresh();
      await _pumpRegime(tester, analysis: analysis);

      expect(find.text('Waiting for bars — regime appears after the first scan.'),
          findsOneWidget);
      expect(find.text('BULLISH LEAN'), findsNothing);
    });
  });
}

class _BarsRepoEmpty implements LiveRepository {
  @override
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async => const {};

  @override
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async =>
      (spread: const VenueSpread.unavailable(), ageSeconds: double.infinity);

  @override
  Future<List<EconomicEvent>> analysisEvents({int hoursAhead = 24}) async => const [];

  @override
  Future<SentimentLayers> sentimentLayers() async => const SentimentLayers.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}
