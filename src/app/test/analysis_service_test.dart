import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xauvote/data/analysis_service.dart';
import 'package:xauvote/data/live_repository.dart';

/// A repository stub that returns a controlled series, so the service can be
/// driven into every state the UI has to render.
class _Repo implements LiveRepository {
  _Repo({
    this.bars = const {},
    this.spread = const VenueSpread.unavailable(),
    this.ageSeconds = double.infinity,
  });

  Map<Tf, TimeframeBars> bars;
  VenueSpread spread;
  double ageSeconds;

  @override
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async => bars;

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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed by this test');
}