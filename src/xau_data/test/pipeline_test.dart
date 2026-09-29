// Pipeline integration tests (TASK-03 acceptance):
// - A/B/C/D fixture → STRONG LONG → scripted prices drive
//   ready → confirmed → active → tp1Hit.
// - Divided → NO CONSENSUS. Stale → NO CONSENSUS (fresh-stage rejections).
// - Missing levels → INSUFFICIENT DATA with logged reason.
// - Filter-chain order and per-stage rejections.
// - Provider swap needs zero pipeline changes (interface conformance).
// - SL breach invalidates an active signal; expiry fires past expiresAt.
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xau_data/xau_data.dart';
import 'package:xau_lifecycle/xau_lifecycle.dart';

final _t0 = DateTime.utc(2026, 9, 29, 12);

PriceQuote _q(double price, int minuteOffset) => PriceQuote(
      symbol: 'XAUUSD',
      price: price,
      bid: price - 0.2,
      ask: price + 0.2,
      timestamp: _t0.add(Duration(minutes: minuteOffset)),
    );

/// A second, independently written provider impl: the conformance test
/// injects it to prove the pipeline depends only on the interface.
class FixedMarketDataProvider implements MarketDataProvider {
  final PriceQuote quote;
  FixedMarketDataProvider(this.quote);

  @override
  Future<PriceQuote> currentPrice(String symbol) async => quote;

  @override
  Stream<PriceQuote> watchPrice(String symbol, Duration interval) async* {
    yield quote;
  }
}

TradeIdea _levelIdea({
  required String id,
  String symbol = 'XAUUSD',
  TradeTimeframe timeframe = TradeTimeframe.m15,
  int minutesAgo = 5,
  bool future = false,
  String? fingerprint,
  double? entryLow = 4275,
  double? entryHigh = 4280,
  double? stopLoss = 4262,
  List<double> tps = const [4295],
}) =>
    TradeIdea(
      id: id,
      source: 'TestWire',
      timeframe: timeframe,
      symbol: symbol,
      direction: Direction.long,
      entryLow: entryLow,
      entryHigh: entryHigh,
      stopLoss: stopLoss,
      takeProfits: [
        for (var i = 0; i < tps.length; i++)
          TakeProfit(index: i + 1, price: tps[i]),
      ],
      publishedAt: future
          ? _t0.add(const Duration(minutes: 5))
          : _t0.subtract(Duration(minutes: minutesAgo)),
      sourceFingerprint: fingerprint,
    );

void main() {
  group('end-to-end mock run (TASK-03 acceptance)', () {
    test('A/B/C/D → STRONG LONG → ready → confirmed → active → tp1Hit',
        () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.abcd(_t0)],
        market: MockMarketDataProvider(script: [
          _q(4270, 0), // below the zone: developing holds
          _q(4277, 1), // inside 4275–4280: ready
          _q(4278, 2), // inside + structure flag: confirmed
          _q(4280, 3), // entry filled: active
          _q(4300, 4), // above TP1 (~4296): tp1Hit
        ]),
      );

      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);

      // Consensus: STRONG LONG with the spec §6 levels.
      expect(result.consensus, isA<ConsensusOutcome>());
      final signal =
          (result.consensus as ConsensusOutcome).signal;
      expect(signal.direction, Direction.long);
      expect(signal.strength, greaterThanOrEqualTo(75));
      expect(
        signal.strengthBand,
        isIn([ConsensusStrength.strong, ConsensusStrength.veryStrong]),
      );
      expect(signal.entryLow, 4275);
      expect(signal.entryHigh, 4280);
      expect(signal.stopLoss, closeTo(4263, 1.0));
      expect(signal.tp1, closeTo(4296, 1.5));

      // 1H context attached as metadata only.
      expect(result.context, isNotNull);
      expect(result.context!.alignment, ContextAlignment.supportive);
      expect(result.context!.h1Trend, Direction.long);

      // First tick below the zone: developing holds.
      expect(pipeline.lifecycle, isNotNull);
      expect(pipeline.lifecycle!.current, SignalStatus.developing);

      final first = await pipeline.tick(
        now: _t0.add(const Duration(minutes: 1)),
      );
      expect(first!.price, 4277);
      expect(pipeline.lifecycle!.current, SignalStatus.ready);

      await pipeline.tick(
        now: _t0.add(const Duration(minutes: 2)),
        structure: const FiveMinuteStructure(breakoutRetest: true),
      );
      expect(pipeline.lifecycle!.current, SignalStatus.confirmed);

      await pipeline.tick(now: _t0.add(const Duration(minutes: 3)));
      expect(pipeline.lifecycle!.current, SignalStatus.active);

      await pipeline.tick(now: _t0.add(const Duration(minutes: 4)));
      expect(pipeline.lifecycle!.current, SignalStatus.tp1Hit);

      // Stamped history in lifecycle order.
      final states =
          pipeline.lifecycle!.history.map((t) => t.to).toList();
      expect(states, [
        SignalStatus.ready,
        SignalStatus.confirmed,
        SignalStatus.active,
        SignalStatus.tp1Hit,
      ]);
      for (var i = 1; i < states.length; i++) {
        expect(
          pipeline.lifecycle!.history[i].at.isAfter(
            pipeline.lifecycle!.history[i - 1].at,
          ),
          isTrue,
        );
      }
    });

    test('four copies collapse to SINGLE_SOURCE (spec §5)', () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.fourCopies(_t0)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(result.consensus, isA<NoConsensus>());
      expect(
        (result.consensus as NoConsensus).reason,
        'SINGLE_SOURCE',
      );
      expect(pipeline.lifecycle, isNull);
      expect(result.context, isNull);
    });

    test('divided room → NO CONSENSUS with counts (spec §3)', () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.divided(_t0)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(result.consensus, isA<NoConsensus>());
      final noConsensus = result.consensus as NoConsensus;
      expect(noConsensus.reason, 'DIVIDED');
      expect(noConsensus.directionCounts[Direction.long], 2);
      expect(noConsensus.directionCounts[Direction.short], 2);
      expect(noConsensus.directionCounts[Direction.neutral], 1);
      expect(pipeline.lifecycle, isNull);
    });

    test('stale-only → NO CONSENSUS, all rejected at the fresh stage',
        () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.staleOnly(_t0)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(result.validIdeas, isEmpty);
      expect(result.rejections, hasLength(3));
      for (final rejection in result.rejections) {
        expect(rejection.stage, FilterStage.fresh);
      }
      expect(result.consensus, isA<NoConsensus>());
      expect(
        (result.consensus as NoConsensus).reason,
        'INSUFFICIENT_DATA',
      );
    });

    test('missing levels → INSUFFICIENT DATA with reason logged', () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.missingLevels(_t0)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(result.validIdeas, isEmpty);
      expect(result.rejections, hasLength(2));
      for (final rejection in result.rejections) {
        expect(rejection.stage, FilterStage.actionable);
        expect(rejection.reason, contains('INSUFFICIENT DATA'));
      }
      expect(result.consensus, isA<NoConsensus>());
      expect(
        (result.consensus as NoConsensus).reason,
        'INSUFFICIENT_DATA',
      );
    });
  });

  group('filter chain order (spec §4)', () {
    test('each idea fails at its first failing stage only', () async {
      final ideas = [
        _levelIdea(id: 'eurusd', symbol: 'EURUSD'),
        _levelIdea(id: 'h1', timeframe: TradeTimeframe.h1),
        _levelIdea(id: 'm5', timeframe: TradeTimeframe.m5),
        _levelIdea(id: 'stale90', minutesAgo: 90),
        _levelIdea(id: 'future5', future: true),
        _levelIdea(
          id: 'nolevels',
          entryLow: null,
          entryHigh: null,
          stopLoss: null,
          tps: const [],
        ),
        _levelIdea(id: 'dupA', fingerprint: 'fp-1'),
        _levelIdea(id: 'dupB', fingerprint: 'fp-1'),
      ];
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource(ideas)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);

      final stageById = {
        for (final r in result.rejections) r.ideaId: r.stage,
      };
      expect(stageById['eurusd'], FilterStage.xauusd);
      expect(stageById['h1'], FilterStage.m15Relevant);
      expect(stageById['m5'], FilterStage.m15Relevant);
      expect(stageById['stale90'], FilterStage.fresh);
      expect(stageById['future5'], FilterStage.fresh);
      expect(stageById['nolevels'], FilterStage.actionable);
      expect(stageById['dupB'], FilterStage.notDuplicate);
      expect(stageById, isNot(contains('dupA')));

      // Only dupA survives → single independent source, no consensus.
      expect(result.validIdeas.map((i) => i.id), ['dupA']);
      expect(result.consensus, isA<NoConsensus>());
      expect(
        (result.consensus as NoConsensus).reason,
        'SINGLE_SOURCE',
      );
    });

    test('per-source freshness override is honored by the pipeline',
        () async {
      final ideas = [
        _levelIdea(id: 'strict-old', minutesAgo: 10),
        _levelIdea(id: 'strict-new', minutesAgo: 2),
      ];
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource(ideas)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
        freshness: const SourceFreshnessPolicies(
          overrides: {
            'TestWire': FreshnessPolicy(
              veryFreshBelow: Duration(minutes: 5),
              freshBelow: Duration(minutes: 8),
              agingBelow: Duration(minutes: 9),
            ),
          },
        ),
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);
      // 10-minute idea is EXPIRED under the override (>9 min); the 2-minute
      // idea survives the chain (but alone cannot form consensus).
      expect(result.validIdeas.map((i) => i.id), ['strict-new']);
      expect(
        result.rejections
            .where((r) => r.ideaId == 'strict-old')
            .single
            .stage,
        FilterStage.fresh,
      );
    });
  });

  group('provider conformance (zero pipeline changes on swap)', () {
    test('a foreign MarketDataProvider impl drives the pipeline', () async {
      final fixed = FixedMarketDataProvider(_q(4277, 0));
      expect(fixed, isA<MarketDataProvider>());
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.abcd(_t0)],
        market: fixed,
      );
      final result = await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(result.consensus, isA<ConsensusOutcome>());
      expect(
        (result.consensus as ConsensusOutcome).signal.direction,
        Direction.long,
      );
      // Fixed price sits inside the entry zone → ready on the first pass.
      expect(pipeline.lifecycle!.current, SignalStatus.ready);
      expect(result.price!.price, 4277);
    });
  });

  group('lifecycle guards', () {
    test('SL breach invalidates an active signal', () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.abcd(_t0)],
        market: MockMarketDataProvider(script: [
          _q(4277, 0), // ready
          _q(4278, 1), // confirmed (flag below)
          _q(4280, 2), // active
          _q(4260, 3), // below SL (~4263): invalidated
        ]),
      );
      await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(pipeline.lifecycle!.current, SignalStatus.ready);
      await pipeline.tick(
        now: _t0.add(const Duration(minutes: 1)),
        structure: const FiveMinuteStructure(rejection: true),
      );
      expect(pipeline.lifecycle!.current, SignalStatus.confirmed);
      await pipeline.tick(now: _t0.add(const Duration(minutes: 2)));
      expect(pipeline.lifecycle!.current, SignalStatus.active);
      await pipeline.tick(now: _t0.add(const Duration(minutes: 3)));
      expect(pipeline.lifecycle!.current, SignalStatus.invalidated);
      expect(pipeline.lifecycle!.isTerminal, isTrue);
    });

    test('ready signal past expiresAt becomes expired', () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.abcd(_t0)],
        market: MockMarketDataProvider(script: [_q(4277, 0), _q(4277, 61)]),
      );
      await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(pipeline.lifecycle!.current, SignalStatus.ready);
      final expiresAt = pipeline.signal!.expiresAt!;
      await pipeline.tick(now: expiresAt.add(const Duration(minutes: 1)));
      expect(pipeline.lifecycle!.current, SignalStatus.expired);
    });

    test('tick without a signal returns null and does nothing', () async {
      final pipeline = RadarPipeline(
        sources: [MockIdeaSource.divided(_t0)],
        market: MockMarketDataProvider(script: [_q(4277, 0)]),
      );
      await pipeline.run(now: _t0, h1Trend: Direction.long);
      expect(
        await pipeline.tick(now: _t0.add(const Duration(minutes: 1))),
        isNull,
      );
    });
  });
}
