import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';

/// Fixed clock so every expectation is deterministic. 2026-03-10 12:00 UTC.
final _now = DateTime.utc(2026, 3, 10, 12);

ReleaseInput _release({
  String id = 'cpi',
  String title = 'CPI m/m',
  String currency = 'USD',
  ReleaseImpact impact = ReleaseImpact.high,
  double? actual,
  double? forecast,
  double? previous,
  int minutesFromNow = 30,
  DateTime? now,
}) {
  return ReleaseInput(
    id: id,
    title: title,
    currency: currency,
    impact: impact,
    figures: ReleaseFigures(actual: actual, forecast: forecast, previous: previous),
    startsAtUtc: (now ?? _now).add(Duration(minutes: minutesFromNow)),
    now: now ?? _now,
  );
}

void main() {
  const engine = EventOutlookEngine();

  group('refuses to answer without data (the case the calendar is in today)', () {
    test('no forecast at all yields no prediction', () {
      final out = engine.evaluate(_release());
      expect(out.bias, EventBias.none);
      expect(out.basis, EventBasis.noForecast);
      expect(out.hasNoPrediction, isTrue);
      expect(out.explanation, contains('No forecast'));
    });

    test('forecast present but no previous yields no prediction', () {
      final out = engine.evaluate(_release(forecast: 0.3));
      expect(out.bias, EventBias.none);
      expect(out.basis, EventBasis.noPrevious);
    });

    test('a bare forecast with a previous still waits for the release', () {
      final out = engine.evaluate(_release(forecast: 0.3, previous: 0.2));
      expect(out.bias, EventBias.none);
      expect(out.basis, EventBasis.awaitingRelease);
    });

    test('the explanation never claims a probability', () {
      final out = engine.evaluate(_release());
      expect(out.explanation.toLowerCase(), isNot(contains('%')));
      expect(out.explanation.toLowerCase(), isNot(contains('chance')));
    });
  });

  group('USD surprise is inverse for gold', () {
    test('a hotter than expected print is a headwind', () {
      final out = engine.evaluate(
        _release(actual: 0.5, forecast: 0.3, previous: 0.2),
      );
      expect(out.bias, EventBias.bearish);
      expect(out.basis, EventBasis.upsideSurprise);
    });

    test('a cooler than expected print is supportive', () {
      final out = engine.evaluate(
        _release(actual: 0.1, forecast: 0.3, previous: 0.2),
      );
      expect(out.bias, EventBias.bullish);
      expect(out.basis, EventBasis.downsideSurprise);
    });

    test('a figure in line moves nothing', () {
      final out = engine.evaluate(
        _release(actual: 0.3, forecast: 0.3, previous: 0.2),
      );
      expect(out.bias, EventBias.neutral);
      expect(out.basis, EventBasis.inlineData);
    });

    test('float noise on an unchanged figure is not a surprise', () {
      // 0.3 forecast against 0.3000001 actual must not read as "hot".
      final out = engine.evaluate(
        _release(actual: 0.3000001, forecast: 0.3, previous: 0.2),
      );
      expect(out.bias, EventBias.neutral);
      expect(out.basis, EventBasis.inlineData);
    });

    test('strength follows the impact tier', () {
      expect(
        engine.evaluate(_release(impact: ReleaseImpact.high)).strength,
        EventImpactStrength.strong,
      );
      expect(
        engine.evaluate(
          _release(id: 'm', impact: ReleaseImpact.medium, title: 'Retail sales'),
        ).strength,
        EventImpactStrength.notable,
      );
    });
  });

  group('central-bank decisions are never a confident lean', () {
    test('a hawkish hold is reported as neutral, because the statement dominates',
        () {
      final out = engine.evaluate(
        _release(
          id: 'fomc',
          title: 'FOMC decision',
          actual: 5.5,
          forecast: 5.25,
          previous: 5.25,
        ),
      );
      expect(out.bias, EventBias.neutral);
      expect(out.basis, EventBasis.centralBankDecision);
    });
  });

  group('non-USD releases have no claimed gold linkage', () {
    test('a EUR release is neutral, not guessed', () {
      final out = engine.evaluate(
        _release(
          id: 'eur',
          title: 'CPI m/m',
          currency: 'EUR',
          actual: 0.5,
          forecast: 0.3,
          previous: 0.2,
        ),
      );
      expect(out.bias, EventBias.neutral);
      expect(out.basis, EventBasis.noGoldLinkage);
    });
  });

  group('coincident releases are unstattributable', () {
    test('two high-impact releases in the same hour both decline', () {
      final cpi = _release(id: 'cpi', title: 'CPI m/m', minutesFromNow: 30);
      final nfp = _release(id: 'nfp', title: 'NFP', minutesFromNow: 60);
      final outs = engine.evaluateAll([cpi, nfp]);

      expect(outs.every((o) => o.bias == EventBias.none), isTrue);
      expect(outs.every((o) => o.basis == EventBasis.confounded), isTrue);
      // Each names the other, so the UI can say what collided.
      expect(outs.first.confoundedBy, contains('NFP'));
      expect(outs.last.confoundedBy, contains('CPI m/m'));
    });

    test('releases outside the window are independent', () {
      final cpi = _release(id: 'cpi', title: 'CPI m/m', minutesFromNow: 30);
      final claims = _release(
        id: 'claims',
        title: 'Jobless claims',
        minutesFromNow: 30 + 180,
      );
      final outs = engine.evaluateAll([cpi, claims]);
      // Three hours apart: not confounded.
      expect(outs.map((o) => o.basis), isNot(contains(EventBasis.confounded)));
    });

    test('a medium release next to a high one is not confounded', () {
      final cpi = _release(id: 'cpi', impact: ReleaseImpact.high);
      final other = _release(
        id: 'other',
        title: 'Fed speaker',
        impact: ReleaseImpact.medium,
        minutesFromNow: 20,
      );
      final outs = engine.evaluateAll([cpi, other]);
      expect(outs.first.basis, isNot(EventBasis.confounded));
    });
  });

  group('release history is exposed but never a countdown after the fact', () {
    test('minutesToRelease is null once the actual is known', () {
      final out = engine.evaluate(
        _release(actual: 0.5, forecast: 0.3, previous: 0.2, minutesFromNow: -10),
      );
      expect(out.minutesToRelease, isNull);
    });

    test('minutesToRelease is set while upcoming', () {
      final out = engine.evaluate(
        _release(forecast: 0.3, previous: 0.2, minutesFromNow: 45),
      );
      expect(out.minutesToRelease, const Duration(minutes: 45));
    });
  });
}