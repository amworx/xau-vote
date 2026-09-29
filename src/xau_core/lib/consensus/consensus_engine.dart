/// Consensus engine: turns clustered independent ideas into one setup.
///
/// Components (spec §6): direction, entry-zone, SL, TP, reasoning agreement,
/// freshness, source independence. 1H context and 5M confirmation are
/// explicitly NOT inputs here (separate phases). Scores are agreement
/// (spec §7), never a probability of profit.
library;

import '../models/consensus_signal.dart';
import '../models/enums.dart';
import '../models/price_range.dart';
import '../models/trade_idea.dart';
import 'independence_assessor.dart';
import 'price_clusterer.dart';

/// Minimum agreement score that may emit a signal (spec §7 MODERATE floor).
const int consensusThreshold = 60;

/// Minimum share of independent weight the dominant direction must hold.
/// Guards the divided case (e.g. 2L/2S/1N in spec §3): tight clusters inside
/// one camp must not override a split room.
const double minDominantShare = 0.6;

/// Minimum independent groups required in the dominant direction.
const int minIndependentSources = 2;

/// Weighted component scores (each 0–1) behind an agreement total.
class ScoreBreakdown {
  final double direction;
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final double reasoning;
  final double freshness;
  final double independence;

  const ScoreBreakdown({
    required this.direction,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.reasoning,
    required this.freshness,
    required this.independence,
  });

  /// Weighted 0–100 agreement total.
  int get total {
    final t = direction * 30.0 +
        entry * 15.0 +
        stopLoss * 15.0 +
        takeProfit * 10.0 +
        reasoning * 10.0 +
        freshness * 10.0 +
        independence * 10.0;
    return t.round().clamp(0, 100);
  }
}

/// Base type for build outcomes.
sealed class ConsensusBuildResult {
  const ConsensusBuildResult();
}

/// Successful consensus with the emitted signal and diagnostics.
class ConsensusOutcome extends ConsensusBuildResult {
  final ConsensusSignal signal;
  final ScoreBreakdown breakdown;
  final Map<Direction, int> directionCounts;
  final double independentVotes;

  const ConsensusOutcome({
    required this.signal,
    required this.breakdown,
    required this.directionCounts,
    required this.independentVotes,
  });
}

/// No signal emitted. Counts are always exposed for transparency.
class NoConsensus extends ConsensusBuildResult {
  /// Machine-readable reason: INSUFFICIENT_DATA, DIVIDED, SINGLE_SOURCE,
  /// WEAK_AGREEMENT, or NON_ACTIONABLE_DIRECTION.
  final String reason;
  final String message;
  final Map<Direction, int> directionCounts;
  final double independentVotes;

  const NoConsensus({
    required this.reason,
    required this.message,
    required this.directionCounts,
    required this.independentVotes,
  });
}

/// Builds 15M consensus from pre-collected ideas.
///
/// [now] is passed in for testability; this method never reads the clock.
/// Only XAUUSD M15 ideas with actionable levels and non-expired freshness
/// are eligible. Ideas on other symbols/timeframes are ignored.
class ConsensusEngine {
  /// Builds consensus from [ideas] as of [now].
  static ConsensusBuildResult build(
    List<TradeIdea> ideas,
    DateTime now, {
    double entryTolerance = PriceClusterer.defaultEntryTolerance,
    double slTolerance = PriceClusterer.defaultSlTolerance,
    double tpTolerance = PriceClusterer.defaultTpTolerance,
  }) {
    Map<Direction, int> emptyCounts() => <Direction, int>{
          Direction.long: 0,
          Direction.short: 0,
          Direction.neutral: 0,
        };

    // 1. Eligibility filter (spec §4 pipeline).
    final eligible = <TradeIdea>[];
    for (final idea in ideas) {
      if (idea.symbol.toUpperCase() != 'XAUUSD') continue;
      if (idea.timeframe != TradeTimeframe.m15) continue;
      if (!idea.hasActionableLevels) continue;
      if (idea.publishedAt != null) {
        final age = now.difference(idea.publishedAt!);
        if (age.inSeconds < 0) continue; // published in the future: ignore
        if (Freshness.fromAge(age) == Freshness.expired) continue;
      }
      eligible.add(idea);
    }

    final rawCounts = emptyCounts();
    for (final idea in eligible) {
      rawCounts[idea.direction] = (rawCounts[idea.direction] ?? 0) + 1;
    }

    if (eligible.isEmpty) {
      return NoConsensus(
        reason: 'INSUFFICIENT_DATA',
        message: 'No eligible 15M XAUUSD ideas with actionable levels.',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: 0.0,
      );
    }

    // 2. Independence weighting (spec §5).
    final independence = IndependenceAssessor.assess(eligible);
    final weightById = independence.weightsById;

    // Independent groups per direction (group votes with the majority of
    // their members; ties inside a group fall back to the leader).
    final groupDirection = <int, Direction>{};
    for (var gi = 0; gi < independence.groups.length; gi++) {
      final ids = independence.groups[gi].ideaIds;
      final tally = <Direction, int>{
        Direction.long: 0,
        Direction.short: 0,
        Direction.neutral: 0,
      };
      for (final id in ids) {
        final idea = eligible.firstWhere((e) => e.id == id);
        tally[idea.direction] = (tally[idea.direction] ?? 0) + 1;
      }
      var best = Direction.long;
      var bestN = -1;
      for (final d in Direction.values) {
        if ((tally[d] ?? 0) > bestN) {
          bestN = tally[d] ?? 0;
          best = d;
        }
      }
      groupDirection[gi] = best;
    }

    final weightByDirection = <Direction, double>{
      Direction.long: 0.0,
      Direction.short: 0.0,
      Direction.neutral: 0.0,
    };
    for (final idea in eligible) {
      final w = weightById[idea.id] ?? 0.0;
      weightByDirection[idea.direction] =
          (weightByDirection[idea.direction] ?? 0.0) + w;
    }
    final groupsByDirection = <Direction, int>{
      Direction.long: 0,
      Direction.short: 0,
      Direction.neutral: 0,
    };
    groupDirection.forEach((_, d) {
      groupsByDirection[d] = (groupsByDirection[d] ?? 0) + 1;
    });

    final totalWeight = weightByDirection.values.fold(0.0, (a, b) => a + b);

    // 3. Dominant direction by independence-weighted majority.
    var dominant = Direction.long;
    var dominantWeight = -1.0;
    var tied = false;
    for (final d in [Direction.long, Direction.short, Direction.neutral]) {
      final w = weightByDirection[d] ?? 0.0;
      if (w > dominantWeight) {
        dominantWeight = w;
        dominant = d;
        tied = false;
      } else if (w == dominantWeight) {
        tied = true;
      }
    }

    final dominantGroups = groupsByDirection[dominant] ?? 0;
    final share = totalWeight <= 0 ? 0.0 : dominantWeight / totalWeight;

    if (tied) {
      return NoConsensus(
        reason: 'DIVIDED',
        message: 'Sources are currently divided.',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: independence.effectiveVotes,
      );
    }

    if (dominantGroups < minIndependentSources) {
      return NoConsensus(
        reason: 'SINGLE_SOURCE',
        message: 'Fewer than two independent sources agree.',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: independence.effectiveVotes,
      );
    }

    if (dominant == Direction.neutral) {
      return NoConsensus(
        reason: 'NON_ACTIONABLE_DIRECTION',
        message: 'Dominant camp is neutral; no LONG/SHORT setup.',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: independence.effectiveVotes,
      );
    }

    if (share < minDominantShare) {
      return NoConsensus(
        reason: 'DIVIDED',
        message: 'Sources are currently divided.',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: independence.effectiveVotes,
      );
    }

    // 4. Cluster levels within the dominant camp only.
    final camp =
        eligible.where((e) => e.direction == dominant).toList(growable: false);

    final entryRanges = <PriceRange>[];
    for (final idea in camp) {
      if (idea.entryLow != null && idea.entryHigh != null) {
        entryRanges.add(
            PriceRange(low: idea.entryLow!, high: idea.entryHigh!));
      } else if (idea.entryLow != null) {
        entryRanges.add(PriceRange(low: idea.entryLow!, high: idea.entryLow!));
      } else if (idea.entryHigh != null) {
        entryRanges
            .add(PriceRange(low: idea.entryHigh!, high: idea.entryHigh!));
      }
    }
    final slValues = camp
        .where((e) => e.stopLoss != null)
        .map((e) => e.stopLoss!)
        .toList(growable: false);

    // TP values grouped per TP index (TP1s together, TP2s, TP3s).
    final tpByIndex = <int, List<double>>{};
    for (final idea in camp) {
      for (final tp in idea.takeProfits) {
        tpByIndex.putIfAbsent(tp.index, () => <double>[]).add(tp.price);
      }
    }

    if (entryRanges.isEmpty || slValues.isEmpty || tpByIndex.isEmpty) {
      return NoConsensus(
        reason: 'INSUFFICIENT_DATA',
        message: 'Dominant camp lacks clusterable entry/SL/TP levels.',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: independence.effectiveVotes,
      );
    }

    final entryCluster = PriceClusterer.clusterRanges(
      entryRanges,
      tolerance: entryTolerance,
    );
    final slCluster = PriceClusterer.clusterValues(
      slValues,
      tolerance: slTolerance,
    );
    final tpClusters = PriceClusterer.clusterTakeProfits(
      tpByIndex,
      tolerance: tpTolerance,
    );

    // 5. Component scores (each 0–1).
    final directionScore =
        totalWeight <= 0 ? 0.0 : dominantWeight / totalWeight;
    final entryScore =
        entryRanges.isEmpty ? 0.0 : entryCluster.inliers.length / entryRanges.length;
    final slScore =
        slValues.isEmpty ? 0.0 : slCluster.inliers.length / slValues.length;

    double tpScore;
    if (tpByIndex.isEmpty) {
      tpScore = 0.0;
    } else {
      var sum = 0.0;
      var n = 0;
      tpByIndex.forEach((index, values) {
        final c = tpClusters[index];
        if (c != null && values.isNotEmpty) {
          sum += c.inliers.length / values.length;
          n++;
        }
      });
      tpScore = n == 0 ? 0.0 : sum / n;
    }

    final reasoningScore = _reasoningAgreement(camp);

    var freshSum = 0.0;
    for (final idea in camp) {
      if (idea.publishedAt == null) {
        freshSum += 0.5;
      } else {
        freshSum += Freshness.fromTimestamps(idea.publishedAt, now)
            .agreementWeight;
      }
    }
    final freshnessScore = camp.isEmpty ? 0.0 : freshSum / camp.length;

    final independenceScore = eligible.isEmpty
        ? 0.0
        : (independence.effectiveVotes / eligible.length).clamp(0.0, 1.0);

    final breakdown = ScoreBreakdown(
      direction: directionScore.clamp(0.0, 1.0),
      entry: entryScore.clamp(0.0, 1.0),
      stopLoss: slScore.clamp(0.0, 1.0),
      takeProfit: tpScore.clamp(0.0, 1.0),
      reasoning: reasoningScore.clamp(0.0, 1.0),
      freshness: freshnessScore.clamp(0.0, 1.0),
      independence: independenceScore,
    );
    final total = breakdown.total;

    if (total < consensusThreshold) {
      return NoConsensus(
        reason: 'WEAK_AGREEMENT',
        message: 'Agreement below the MODERATE floor ($total < '
            '$consensusThreshold).',
        directionCounts: Map.unmodifiable(rawCounts),
        independentVotes: independence.effectiveVotes,
      );
    }

    // 6. Emit the setup. Dissenting directions are excluded from levels.
    final tpPrices = <int, double>{};
    tpClusters.forEach((index, c) {
      tpPrices[index] = c.consensus;
    });
    final orderedTp = tpPrices.keys.toList()..sort();
    final tpList = orderedTp.map((k) => tpPrices[k]!).toList();

    final signal = ConsensusSignal(
      id: 'sig-${now.toUtc().toIso8601String()}-${dominant.toJson()}',
      direction: dominant,
      strength: total,
      entryLow: entryCluster.consensus.low,
      entryHigh: entryCluster.consensus.high,
      stopLoss: slCluster.consensus,
      tp1: tpList.isNotEmpty ? tpList[0] : null,
      tp2: tpList.length > 1 ? tpList[1] : null,
      tp3: tpList.length > 2 ? tpList[2] : null,
      status: SignalStatus.developing,
      createdAt: now,
      updatedAt: now,
      expiresAt: now.toUtc().add(const Duration(minutes: 60)),
      independentSourceCount: dominantGroups,
      totalSourceCount: camp.length,
      agreeingSourceIds: camp.map((e) => e.id).toList(),
    );

    return ConsensusOutcome(
      signal: signal,
      breakdown: breakdown,
      directionCounts: Map.unmodifiable(rawCounts),
      independentVotes: independence.effectiveVotes,
    );
  }

  /// Mean pairwise wording overlap within [camp]. Empty reasoning never
  /// counts as agreement: all-empty camps score neutral 0.5.
  static double _reasoningAgreement(List<TradeIdea> camp) {
    if (camp.length < 2) return 0.5;
    var sum = 0.0;
    var pairs = 0;
    var anyNonEmpty = false;
    for (var i = 0; i < camp.length; i++) {
      if ((camp[i].reasoning ?? '').trim().isNotEmpty) anyNonEmpty = true;
      for (var j = i + 1; j < camp.length; j++) {
        sum += IndependenceAssessor.wordingSimilarity(
          camp[i].reasoning,
          camp[j].reasoning,
        );
        pairs++;
      }
    }
    if (!anyNonEmpty) return 0.5;
    if (pairs == 0) return 0.5;
    return sum / pairs;
  }
}
