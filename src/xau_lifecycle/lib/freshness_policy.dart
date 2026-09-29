/// Freshness bands and expiry (spec §15).
library;

import 'package:xau_core/xau_core.dart';

/// Injectable freshness thresholds (spec §15 bands by default).
///
/// Default: `<15 min` VERY_FRESH, `15–30 min` FRESH, `30–60 min` AGING,
/// `60+ min` EXPIRED. Boundary semantics are exact [Duration] comparisons
/// (`age < threshold`), which matches [Freshness.fromAge] for every
/// whole-second age (conformance-tested in `test/freshness_policy_test.dart`).
///
/// Thresholds must be strictly increasing (`veryFreshBelow < freshBelow <
/// agingBelow`); the default values satisfy this.
class FreshnessPolicy {
  /// Ages strictly below this are VERY_FRESH (default 15 minutes).
  final Duration veryFreshBelow;

  /// Ages strictly below this (and at/above [veryFreshBelow]) are FRESH.
  final Duration freshBelow;

  /// Ages strictly below this (and at/above [freshBelow]) are AGING.
  /// At/above this is EXPIRED.
  final Duration agingBelow;

  /// Lifetime added to `publishedAt` by [expiresAtFor] (default 60 minutes).
  final Duration defaultLifetime;

  /// Creates a policy. Prefer [FreshnessPolicy.spec] for the spec defaults.
  const FreshnessPolicy({
    this.veryFreshBelow = const Duration(minutes: 15),
    this.freshBelow = const Duration(minutes: 30),
    this.agingBelow = const Duration(minutes: 60),
    this.defaultLifetime = const Duration(minutes: 60),
  });

  /// The spec §15 default policy.
  static const FreshnessPolicy spec = FreshnessPolicy();

  /// Classifies an [age]. Future (negative) ages order below every
  /// threshold and therefore classify as VERY_FRESH; callers that must
  /// reject future-dated ideas (e.g. the pipeline) guard that separately.
  Freshness classify(Duration age) {
    if (age < veryFreshBelow) return Freshness.veryFresh;
    if (age < freshBelow) return Freshness.fresh;
    if (age < agingBelow) return Freshness.aging;
    return Freshness.expired;
  }

  /// Classifies the age of [publishedAt] as of [now] (no clock reads).
  Freshness classifyAt(DateTime publishedAt, DateTime now) =>
      classify(now.difference(publishedAt));

  /// Classifies [idea] as of [now]. Ideas without `publishedAt` map to
  /// AGING, mirroring [Freshness.fromTimestamps].
  Freshness classifyIdea(TradeIdea idea, DateTime now) {
    final publishedAt = idea.publishedAt;
    if (publishedAt == null) return Freshness.aging;
    return classifyAt(publishedAt, now);
  }

  /// True when [age] falls in the EXPIRED band.
  bool isExpired(Duration age) => classify(age) == Freshness.expired;

  /// Computes `expiresAt` for content published at [publishedAt].
  DateTime expiresAtFor(DateTime publishedAt) =>
      publishedAt.toUtc().add(defaultLifetime);

  /// True when [now] is at or past [expiresAt]. Null expiry never expires.
  bool isPastExpiry(DateTime now, DateTime? expiresAt) =>
      expiresAt != null && !now.isBefore(expiresAt);
}

/// Per-source freshness overrides around one default policy.
///
/// [defaultPolicy] applies unless [overrides] holds an entry for the idea's
/// `source` name. This is the injection point TASK-02 T2.2 requires for
/// per-source expiry tuning.
class SourceFreshnessPolicies {
  /// Policy used when no per-source override matches.
  final FreshnessPolicy defaultPolicy;

  /// Override policies keyed by idea `source` name.
  final Map<String, FreshnessPolicy> overrides;

  /// Creates a registry with [defaultPolicy] and optional [overrides].
  const SourceFreshnessPolicies({
    this.defaultPolicy = FreshnessPolicy.spec,
    this.overrides = const <String, FreshnessPolicy>{},
  });

  /// Returns the override for [source], or [defaultPolicy].
  FreshnessPolicy forSource(String? source) =>
      (source != null ? overrides[source] : null) ?? defaultPolicy;

  /// Classifies [idea] as of [now] with its source's policy.
  Freshness classifyIdea(TradeIdea idea, DateTime now) =>
      forSource(idea.source).classifyIdea(idea, now);
}
