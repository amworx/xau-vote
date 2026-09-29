// Freshness tests: exact spec §15 bands at boundaries, conformance with
// the core Freshness.fromAge, expiry computation, per-source overrides.
import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xau_lifecycle/xau_lifecycle.dart';

final _t0 = DateTime.utc(2026, 9, 29, 12);

TradeIdea _idea({
  required String id,
  required String source,
  DateTime? publishedAt,
}) =>
    TradeIdea(
      id: id,
      source: source,
      timeframe: TradeTimeframe.m15,
      direction: Direction.long,
      entryLow: 4275,
      entryHigh: 4280,
      stopLoss: 4262,
      takeProfits: [TakeProfit(index: 1, price: 4295)],
      publishedAt: publishedAt,
    );

void main() {
  group('spec §15 bands exact at boundaries', () {
    test('14:59 vs 15:00, 29:59 vs 30:00, 59:59 vs 60:00', () {
      const policy = FreshnessPolicy.spec;
      Duration age(int minutes, [int seconds = 0]) =>
          Duration(minutes: minutes, seconds: seconds);

      expect(policy.classify(age(0)), Freshness.veryFresh);
      expect(policy.classify(age(14, 59)), Freshness.veryFresh);
      expect(policy.classify(age(15)), Freshness.fresh);
      expect(policy.classify(age(15, 1)), Freshness.fresh);
      expect(policy.classify(age(29, 59)), Freshness.fresh);
      expect(policy.classify(age(30)), Freshness.aging);
      expect(policy.classify(age(45)), Freshness.aging);
      expect(policy.classify(age(59, 59)), Freshness.aging);
      expect(policy.classify(age(60)), Freshness.expired);
      expect(policy.classify(age(90)), Freshness.expired);
      expect(policy.classify(age(24 * 60)), Freshness.expired);
    });

    test('classifyAt derives the same bands from timestamps', () {
      const policy = FreshnessPolicy.spec;
      expect(
        policy.classifyAt(
          _t0.subtract(const Duration(minutes: 14, seconds: 59)),
          _t0,
        ),
        Freshness.veryFresh,
      );
      expect(
        policy.classifyAt(
          _t0.subtract(const Duration(minutes: 15)),
          _t0,
        ),
        Freshness.fresh,
      );
      expect(
        policy.classifyAt(
          _t0.subtract(const Duration(minutes: 60)),
          _t0,
        ),
        Freshness.expired,
      );
    });
  });

  group('conformance with core Freshness.fromAge', () {
    test('identical buckets across a sweep of whole-second ages', () {
      const policy = FreshnessPolicy.spec;
      const probeSeconds = [
        0,
        1,
        599,
        899,
        900,
        901,
        1799,
        1800,
        1801,
        3599,
        3600,
        3601,
        5400,
        7200,
      ];
      for (final seconds in probeSeconds) {
        final age = Duration(seconds: seconds);
        expect(
          policy.classify(age),
          Freshness.fromAge(age),
          reason: 'age ${age.inSeconds}s must match core',
        );
      }
    });
  });

  group('expiry computation', () {
    test('expiresAtFor adds the default 60-minute lifetime in UTC', () {
      const policy = FreshnessPolicy.spec;
      expect(
        policy.expiresAtFor(_t0),
        _t0.add(const Duration(minutes: 60)),
      );
    });

    test('isPastExpiry is true at/after expiry, false before, never on null',
        () {
      const policy = FreshnessPolicy.spec;
      final expiresAt = _t0.add(const Duration(minutes: 60));
      expect(
        policy.isPastExpiry(_t0.add(const Duration(minutes: 59)), expiresAt),
        isFalse,
      );
      expect(policy.isPastExpiry(expiresAt, expiresAt), isTrue);
      expect(
        policy.isPastExpiry(_t0.add(const Duration(hours: 2)), expiresAt),
        isTrue,
      );
      expect(policy.isPastExpiry(_t0, null), isFalse);
    });

    test('isExpired mirrors the expired band', () {
      const policy = FreshnessPolicy.spec;
      expect(policy.isExpired(const Duration(minutes: 59)), isFalse);
      expect(policy.isExpired(const Duration(minutes: 60)), isTrue);
    });
  });

  group('classifyIdea', () {
    test('uses publishedAt against the passed now', () {
      const policy = FreshnessPolicy.spec;
      expect(
        policy.classifyIdea(
          _idea(
            id: 'fresh',
            source: 's',
            publishedAt: _t0.subtract(const Duration(minutes: 5)),
          ),
          _t0,
        ),
        Freshness.veryFresh,
      );
      expect(
        policy.classifyIdea(
          _idea(
            id: 'stale',
            source: 's',
            publishedAt: _t0.subtract(const Duration(minutes: 61)),
          ),
          _t0,
        ),
        Freshness.expired,
      );
    });

    test('null publishedAt maps to aging (mirrors core)', () {
      const policy = FreshnessPolicy.spec;
      expect(
        policy.classifyIdea(_idea(id: 'x', source: 's'), _t0),
        Freshness.aging,
      );
    });
  });

  group('per-source overrides', () {
    test('override policy applies to its source only', () {
      const strictSource = FreshnessPolicy(
        veryFreshBelow: Duration(minutes: 5),
        freshBelow: Duration(minutes: 10),
        agingBelow: Duration(minutes: 20),
      );
      const policies = SourceFreshnessPolicies(
        overrides: {'StrictWire': strictSource},
      );
      final publishedAt = _t0.subtract(const Duration(minutes: 10));

      // Default source: 10 min old is VERY_FRESH under spec bands.
      expect(
        policies.classifyIdea(
          _idea(id: 'a', source: 'NormalWire', publishedAt: publishedAt),
          _t0,
        ),
        Freshness.veryFresh,
      );
      // Overridden source: 10 min old is AGING under its own bands.
      expect(
        policies.classifyIdea(
          _idea(id: 'b', source: 'StrictWire', publishedAt: publishedAt),
          _t0,
        ),
        Freshness.aging,
      );
      expect(
        policies.forSource('StrictWire'),
        same(strictSource),
      );
      expect(
        policies.forSource('Unknown'),
        same(FreshnessPolicy.spec),
      );
      expect(policies.forSource(null), same(FreshnessPolicy.spec));
    });
  });
}
