import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xauvote/data/analysis_service.dart';
import 'package:xauvote/data/live_repository.dart';
import 'package:xauvote/models/sentiment_layers.dart';

/// A repository stub that returns a controlled series, so the service can be
/// driven into every state the UI has to render.
class _Repo implements LiveRepository {
  _Repo({
    this.bars = const {},
    this.spread = const VenueSpread.unavailable(),
    this.ageSeconds = double.infinity,
    this.layers = const SentimentLayers.empty(),
  });

  Map<Tf, TimeframeBars> bars;
  VenueSpread spread;
  double ageSeconds;

  /// §5.1 layers. Defaults to "nothing measured" so the pre-existing tests keep
  /// asserting exactly what they asserted before the overlay was wired.
  SentimentLayers layers;

  @override
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async => bars;

  @override
  Future<SentimentLayers> sentimentLayers() async => layers;

  @override
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async =>
      (spread: spread, ageSeconds: ageSeconds);

  @override
  Future<List<EconomicEvent>> analysisEvents({int hoursAhead = 24}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed by this test');
}

List<Candle> bars({
  required int n,
  required double start,
  double drift = 0.0,
  double amplitude = 6,
  bool degraded = false,
  int minutes = 5,
}) {
  final base = DateTime.utc(2026, 9, 1);
  return [
    for (var i = 0; i < n; i++)
      Candle(
        openTime: base.add(Duration(minutes: minutes * i)),
        open: start + drift * i,
        high: start + drift * i + amplitude * (0.5 + 0.5 * math.sin(i / 9)),
        low: start + drift * i - amplitude * (0.5 + 0.5 * math.sin(i / 9)),
        close: start + drift * i + amplitude * math.sin(i / 9),
        quality: degraded ? CandleQuality.degraded : CandleQuality.primary,
      ),
  ];
}

Map<Tf, TimeframeBars> full({bool degraded = false, int n1h = 260}) => {
      Tf.h1: TimeframeBars(
        timeframe: Tf.h1,
        bars: bars(n: n1h, start: 4000, drift: 0.03, minutes: 60, degraded: degraded),
        allDegraded: degraded,
      ),
      Tf.m30: TimeframeBars(
        timeframe: Tf.m30,
        bars: bars(n: 260, start: 4000, drift: 0.06, minutes: 30, degraded: degraded),
        allDegraded: degraded,
      ),
      Tf.m15: TimeframeBars(
        timeframe: Tf.m15,
        bars: bars(n: 260, start: 4000, drift: 0.12, minutes: 15, degraded: degraded),
        allDegraded: degraded,
      ),
      Tf.m5: TimeframeBars(
        timeframe: Tf.m5,
        bars: bars(n: 260, start: 4000, drift: 0.35, degraded: degraded),
        allDegraded: degraded,
      ),
    };

void main() {
  group('service basics', () {
    test('an empty backend yields NO TRADE, never a fabricated setup', () async {
      final s = AnalysisService(repository: _Repo());
      final r = await s.refresh();
      expect(r, isNotNull);
      expect(r!.verdict, Verdict.noTrade);
      expect(s.error, isNull);
      expect(
        r.dataQuality.join(' '),
        anyOf(contains('insufficient history'), contains('no candidate direction')),
      );
    });

    test('a backend exception surfaces as an error rather than a fake result', () async {
      final s = AnalysisService(repository: _ThrowingRepo());
      await s.refresh();
      expect(s.result, isNull);
      expect(s.error, isNotNull);
    });

    // The service used to fetch bars, spread and events and nothing else, so
    // ConfluenceInput.macro / .sentiment were permanently null and every 5.1
    // layer was inert no matter what the database held.
    group('§5.1 layers reach the scan', () {
      SentimentLayers layer({
        required String layer,
        required double weight,
        int? alignment,
        num? score,
      }) => SentimentLayers([
            SentimentLayerRow.tryParse({
              'layer': layer,
              'horizon': 'hours-days',
              'weight': weight,
              'score': score,
              'alignment': alignment,
              'measured_at': '2026-10-02T00:00:00.000Z',
              'source': 'test',
              'source_url': null,
              'stale': false,
              'detail': <String, dynamic>{},
            })!,
          ]);

      test('unmeasured layers contribute nothing and say so', () async {
        final s = AnalysisService(repository: _Repo());
        final r = await s.refresh();
        expect(r, isNotNull);
        expect(r!.macroAlignment, isNull);
        expect(r.sentimentAlignment, isNull);
        expect(r.conflictPenalty, 0);
        expect(
          r.dataQuality.join(' '),
          contains('sentiment layers: none measured'),
          reason: 'a scan that weighed nothing must not look like a clean one',
        );
      });

      test('a measured layer is reported and counted in coverage', () async {
        // Uses full() because the scanner returns early - with null macro - when
        // there is no candidate direction, which is a different code path.
        final s = AnalysisService(
          repository: _Repo(
            bars: full(),
            layers: layer(layer: 'market_implied', weight: 20, alignment: -1),
          ),
        );
        final r = await s.refresh();
        // 20 of 55 macro-side points: below the gate, so alignment stays null
        // even though the impulse is measured.
        expect(r!.macroAlignment, isNull);
        expect(
          r.dataQuality.join(' '),
          allOf(contains('market_implied'), contains('macro coverage 36%')),
        );
      });

      test('policy plus market-implied clears the gate and resolves macro', () async {
        final s = AnalysisService(
          repository: _Repo(
            bars: full(),
            layers: SentimentLayers([
              SentimentLayerRow.tryParse({
                'layer': 'market_implied',
                'horizon': 'hours-days',
                'weight': 20,
                'score': null,
                'alignment': -1,
                'measured_at': '2026-10-05T00:00:00.000Z',
                'source': 'US Treasury',
                'source_url': null,
                'stale': false,
                'detail': <String, dynamic>{'legs_missing': ['usd', 'volatility']},
              })!,
              SentimentLayerRow.tryParse({
                'layer': 'policy',
                'horizon': 'days-weeks',
                'weight': 35,
                'score': -1.03,
                'alignment': -1,
                'measured_at': '2026-09-16T00:00:00.000Z',
                'source': 'FOMC',
                'source_url': null,
                'stale': false,
                'detail': <String, dynamic>{'action': 'raise'},
              })!,
            ]),
          ),
        );
        final r = await s.refresh();
        expect(r!.macroAlignment, -1, reason: '100% coverage resolves macro');
        expect(r.dataQuality.join(' '), contains('macro coverage 100%'));
      });

      SentimentLayerRow row(String layer, double weight, int alignment,
          {String measuredAt = '2026-10-05T00:00:00.000Z', num? score}) =>
          SentimentLayerRow.tryParse({
            'layer': layer,
            'horizon': 'hours-days',
            'weight': weight,
            'score': score,
            'alignment': alignment,
            'measured_at': measuredAt,
            'source': 'test',
            'source_url': null,
            'stale': false,
            'detail': <String, dynamic>{},
          })!;

      test('policy alone now clears the macro gate', () async {
        // CONSEQUENCE OF D-20261006-011, and deliberately visible rather than
        // papered over.
        //
        // The gate is a fixed 50% of macro-side weight, unchanged. But with the
        // unobtainable WGC layer removed the denominator is 55 instead of 75, so
        // policy alone is 35/55 = 64% rather than 35/75 = 47%. Policy therefore
        // clears the gate on its own, where before it could not, and the scorer
        // may now veto a setup on one macro layer out of two.
        //
        // That is a weakening of a safety property, so it is called out for the
        // owner rather than adopted quietly. The threshold itself was NOT
        // retuned: that is a methodology decision, not a licensing fix.
        final s = AnalysisService(
          repository: _Repo(
            bars: full(),
            layers: SentimentLayers([
              row('policy', 35, -1, score: -1.03),
              row('positioning', 25, -1, measuredAt: '2026-09-29T00:00:00.000Z'),
            ]),
          ),
        );
        final r = await s.refresh();
        expect(r!.macroAlignment, -1);
        expect(r.dataQuality.join(' '), contains('macro coverage 64%'),
            reason: 'policy 35 of 55 macro-side; positioning is not macro');
        expect(r.sentimentAlignment, -1, reason: 'positioning still reaches sentiment');
      });

      test('the live layer read is weighed on both sides', () async {
        // Mirrors the database on 2026-10-05: Fed hiked (policy -1), real yields
        // up (market_implied -1), COT at the 37.8th percentile (-1).
        final s = AnalysisService(
          repository: _Repo(
            bars: full(),
            layers: SentimentLayers([
              row('policy', 35, -1, score: -1.03),
              row('positioning', 25, -1, measuredAt: '2026-09-29T00:00:00.000Z'),
              row('market_implied', 20, -1),
            ]),
          ),
        );
        final r = await s.refresh();
        expect(r!.macroAlignment, -1);
        expect(r.sentimentAlignment, -1);
        expect(r.macroAgrees, isNotNull,
            reason: 'a resolved macro must resolve to an agreement sign');
        expect(r.sentimentAgrees, isNotNull);
        expect(r.dataQuality.join(' '), contains('macro coverage 100%'));
      });
    });

    test('a scan caches and exposes a timestamp', () async {
      final s = AnalysisService(repository: _Repo(bars: full()));
      await s.refresh();
      expect(s.result, isNotNull);
      expect(s.updatedAt, isNotNull);
    });
  });

  group('direction comes only from the 1H regime', () {
    test('a rising 1H offers a long candidate', () async {
      final s = AnalysisService(repository: _Repo(bars: full()));
      final r = await s.refresh();
      // Whatever the verdict, a rising 1H must not produce a short.
      expect(r!.verdict, isNot(Verdict.short));
    });

    test('a falling 1H offers a short candidate', () async {
      final falling = full();
      falling[Tf.h1] = TimeframeBars(
        timeframe: Tf.h1,
        bars: bars(n: 260, start: 4000, drift: -0.03, minutes: 60),
        allDegraded: false,
      );
      final s = AnalysisService(repository: _Repo(bars: falling));
      final r = await s.refresh();
      expect(r!.verdict, isNot(Verdict.long));
    });

    test('a flat 1H offers no candidate at all', () async {
      final flat = full();
      flat[Tf.h1] = TimeframeBars(
        timeframe: Tf.h1,
        // Zero drift and zero amplitude: price sits exactly on the mean.
        bars: [
          for (var i = 0; i < 260; i++)
            Candle(
              openTime: DateTime.utc(2026, 9, 1).add(Duration(hours: i)),
              open: 4000, high: 4000, low: 4000, close: 4000,
            ),
        ],
        allDegraded: false,
      );
      final s = AnalysisService(repository: _Repo(bars: flat));
      final r = await s.refresh();
      expect(r!.verdict, Verdict.noTrade);
      expect(r.dataQuality.join(' '), contains('no candidate direction'));
    });
  });

  group('spread status is reported honestly', () {
    test('a genuine fresh spread is marked available', () async {
      final s = AnalysisService(repository: _Repo(
        bars: full(),
        spread: const VenueSpread.available(bid: 4142.45, ask: 4143.28, source: 'oanda-practice'),
        ageSeconds: 30,
      ));
      final r = await s.refresh();
      expect(r!.spread.status, SpreadStatus.available);
      expect(s.hasGenuineSpread, isTrue);
      expect(r.dataQuality.join(' '), contains('venue spread'));
    });

    test('a stale spread is treated as unavailable', () async {
      final s = AnalysisService(repository: _Repo(
        bars: full(),
        spread: const VenueSpread.available(bid: 4142.45, ask: 4143.28, source: 'oanda-practice'),
        ageSeconds: 3600,
      ));
      final r = await s.refresh();
      // The measurement exists, but it is not current, so the vetoes stay
      // UNEVALUATED rather than relying on an hour-old number.
      expect(r!.spread.isGenuine, isTrue);
      expect(r.dataQuality.join(' '), contains('UNAVAILABLE'));
      expect(s.hasGenuineSpread, isTrue);
    });

    test('no spread reports UNAVAILABLE and names it as a data-quality note', () async {
      final s = AnalysisService(repository: _Repo(bars: full()));
      final r = await s.refresh();
      expect(r!.spread.status, SpreadStatus.unavailable);
      expect(r.dataQuality.join(' '), contains('spread UNAVAILABLE'));
      expect(s.hasGenuineSpread, isFalse);
    });
  });

  group('data-quality notes always explain a quiet app', () {
    test('degraded warm-up history is called out', () async {
      final s = AnalysisService(repository: _Repo(bars: full(degraded: true)));
      final r = await s.refresh();
      expect(r!.dataQuality.join(' '), contains('degraded'));
    });

    test('short history is called out with the shortfall', () async {
      final s = AnalysisService(repository: _Repo(bars: full(n1h: 30)));
      final r = await s.refresh();
      expect(r!.dataQuality.join(' '), contains('1h: 30/200'));
    });
  });

  group('independence metrics', () {
    IdeaProvenance idea({
      required String id,
      required ModelOwner owner,
      String? publisher,
      String? dataset,
      String? method,
    }) =>
        IdeaProvenance(
          ideaId: id,
          direction: 'LONG',
          modelOwner: owner,
          publisherId: publisher,
          upstreamDataset: dataset,
          methodologyId: method,
          publishedAt: DateTime.utc(2026, 10, 2, 12),
          derived: owner != ModelOwner.thirdParty,
        );

    test('our derived readers report methods but zero sources', () {
      final r = const IndependenceScorer().score(
        IdeaAgreement(direction: 'LONG', ideas: [
          idea(id: 'a', owner: ModelOwner.us, dataset: 'D1', method: 'cot_reader'),
          idea(id: 'b', owner: ModelOwner.us, dataset: 'D2', method: 'rates_reader'),
          idea(id: 'c', owner: ModelOwner.us, dataset: 'D3', method: 'cal_reader'),
        ]),
      );
      expect(r.externalVoices, 0);
      expect(r.analyticalMethods, 3);
      expect(r.upstreamDatasets, 3);
      // With no eligible publisher the UI must not render a ratio at all,
      // because "0 of 0 sources" reads as an error rather than a state.
      expect(r.canShowSourceRatio, isFalse);
      expect(r.isAwaitingExternalSources, isTrue);
    });

    test('external publishers produce a real ratio', () {
      final r = const IndependenceScorer().score(
        IdeaAgreement(direction: 'LONG', ideas: [
          idea(id: 'x', owner: ModelOwner.thirdParty, publisher: 'P1', method: 'm1'),
          idea(id: 'y', owner: ModelOwner.thirdParty, publisher: 'P2', method: 'm2'),
        ]),
        eligiblePublishers: 5,
      );
      expect(r.externalVoices, 2);
      expect(r.canShowSourceRatio, isTrue);
      expect(r.eligiblePublishers, 5);
    });

    test('one release read three ways is one effective voice', () {
      final r = const IndependenceScorer().score(
        IdeaAgreement(direction: 'LONG', ideas: [
          idea(id: 'A', owner: ModelOwner.us, dataset: 'CFTC-COT-1', method: 'cot_positioning'),
          idea(id: 'B', owner: ModelOwner.us, dataset: 'CFTC-COT-1', method: 'cot_trend'),
          idea(id: 'C', owner: ModelOwner.us, dataset: 'CFTC-COT-1', method: 'rsi_ema_macd'),
        ]),
      );
      expect(r.effectiveVoices, 1.0);
      expect(r.clusters, hasLength(1));
      // Methodological diversity survives only in its own metric.
      expect(r.analyticalMethods, 3);
      expect(r.upstreamDatasets, 1);
    });

    test('an unknown model owner cannot earn source credit', () {
      final r = const IndependenceScorer().score(
        IdeaAgreement(direction: 'LONG', ideas: [
          idea(id: 'u', owner: ModelOwner.unknown, publisher: 'P?', method: 'm'),
        ]),
      );
      expect(r.externalVoices, 0);
    });
  });

  group('session gate and DST', () {
    // Regression: the gate used a fixed -4h offset, which is wrong for roughly
    // eight months a year and would open the gate an hour early in winter.
    test('New York offset follows US daylight saving', () {
      // 2026: DST starts 8 March, ends 1 November.
      expect(newYorkTime(DateTime.utc(2026, 1, 15, 17)), DateTime.utc(2026, 1, 15, 12));
      expect(newYorkTime(DateTime.utc(2026, 7, 15, 16)), DateTime.utc(2026, 7, 15, 12));
    });

    test('the DST boundary itself flips at the right instant', () {
      // US DST starts at 02:00 local STANDARD time on 8 March 2026, which is
      // 07:00 UTC. One minute earlier is still EST (-5).
      expect(newYorkTime(DateTime.utc(2026, 3, 8, 6, 59)), DateTime.utc(2026, 3, 8, 1, 59));
      expect(newYorkTime(DateTime.utc(2026, 3, 8, 7, 0)), DateTime.utc(2026, 3, 8, 3, 0));
      // Across spring-forward, 1 minute of UTC advances the local clock by 1h01m
      // (01:59 EST -> 03:00 EDT): the 02:00 hour does not exist on this date.
      // That 61-minute skew is the proof the offset actually changed.
      final before = newYorkTime(DateTime.utc(2026, 3, 8, 6, 59));
      final after = newYorkTime(DateTime.utc(2026, 3, 8, 7, 0));
      expect(after.isAfter(before), isTrue);
      expect(
        after.difference(before),
        const Duration(hours: 1, minutes: 1),
      );
    });

    test('autumn fall-back repeats the hour and uses the autumn offset', () {
      // 2026: DST ends 1 November at 02:00 EDT = 06:00 UTC.
      // 05:59 UTC is 01:59 EDT; 06:00 UTC is 01:00 EST, so 01:00 occurs twice.
      // 05:30 UTC is 01:30 EDT (before the flip); 06:30 UTC is 01:30 EST (after).
      // Both land on 01:30 wall-clock, which is the observable signature of the
      // repeated hour.
      expect(newYorkTime(DateTime.utc(2026, 11, 1, 5, 30)), DateTime.utc(2026, 11, 1, 1, 30));
      expect(newYorkTime(DateTime.utc(2026, 11, 1, 6, 30)), DateTime.utc(2026, 11, 1, 1, 30));
      // One hour later in UTC is only one hour later locally after the flip.
      expect(
        newYorkTime(DateTime.utc(2026, 11, 1, 7, 30)),
        DateTime.utc(2026, 11, 1, 2, 30),
      );
    });

    test('the market is open midweek regardless of season', () {
      expect(sessionIsOpenAt(DateTime.utc(2026, 1, 14, 15)), isTrue);
      expect(sessionIsOpenAt(DateTime.utc(2026, 7, 15, 15)), isTrue);
    });

    test('Saturday is always closed', () {
      expect(sessionIsOpenAt(DateTime.utc(2026, 1, 10, 15)), isFalse);
    });

    test('Sunday opens at 18:00 New York, not 18:00 UTC', () {
      // 22:00 UTC in January = 17:00 EST -> still closed.
      expect(sessionIsOpenAt(DateTime.utc(2026, 1, 11, 22)), isFalse);
      // 23:00 UTC = 18:00 EST -> open.
      expect(sessionIsOpenAt(DateTime.utc(2026, 1, 11, 23)), isTrue);
      // In July the same 22:00 UTC is 18:00 EDT -> already open.
      expect(sessionIsOpenAt(DateTime.utc(2026, 7, 12, 22)), isTrue);
    });

    test('Friday closes at 17:00 New York, not 17:00 UTC', () {
      // 21:00 UTC in January = 16:00 EST -> still open.
      expect(sessionIsOpenAt(DateTime.utc(2026, 1, 9, 21)), isTrue);
      // 22:00 UTC = 17:00 EST -> closed.
      expect(sessionIsOpenAt(DateTime.utc(2026, 1, 9, 22)), isFalse);
    });
  });

  group('the scan never invents a signal', () {
    test('no configuration produces a long or short without levels', () async {
      final configs = [
        _Repo(bars: full()),
        _Repo(bars: full(degraded: true)),
        _Repo(bars: full(n1h: 30)),
        _Repo(bars: const {}),
        _Repo(
          bars: full(),
          spread: const VenueSpread.available(bid: 4142, ask: 4143, source: 'oanda'),
          ageSeconds: 5,
        ),
      ];
      for (final c in configs) {
        final s = AnalysisService(repository: c);
        final r = await s.refresh();
        if (r!.verdict != Verdict.noTrade) {
          expect(r.stopPlan, isNotNull, reason: 'a trade must carry a stop');
          expect(r.stopPlan!.isValid, isTrue);
        } else {
          expect(r.vetoes, isNotEmpty);
        }
      }
    });
  });
}

class _ThrowingRepo implements LiveRepository {
  @override
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async =>
      throw StateError('backend down');

  @override
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async =>
      throw StateError('backend down');

  @override
  Future<List<EconomicEvent>> analysisEvents({int hoursAhead = 24}) async =>
      throw StateError('backend down');

  @override
  Future<SentimentLayers> sentimentLayers() async =>
      throw StateError('backend down');

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed by this test');
}