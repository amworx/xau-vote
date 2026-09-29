/// Source-independence assessment (spec §5).
///
/// Copies of one underlying idea must count as ONE independent vote.
/// Grouping key: direction + near-identical levels AND (same author OR
/// overlapping wording OR publication times within minutes).
library;

import '../models/trade_idea.dart';

/// Epsilon weight for non-first copies in a duplicate group.
const double duplicateEpsilon = 0.05;

/// One group of ideas sharing a single independent vote.
class IndependenceGroup {
  /// Idea ids in this group, earliest-published first.
  final List<String> ideaIds;

  const IndependenceGroup(this.ideaIds);
}

/// Per-idea independence weights plus grouping.
class IndependenceResult {
  /// Weight per idea id in (0, 1]. Group leaders are 1.0, copies 0.05.
  final Map<String, double> weightsById;

  /// Duplicate groups (each counts as one independent vote).
  final List<IndependenceGroup> groups;

  const IndependenceResult({
    required this.weightsById,
    required this.groups,
  });

  /// Number of independent votes (one per group).
  int get independentCount => groups.length;

  /// Effective votes: sum of all weights.
  double get effectiveVotes =>
      weightsById.values.fold(0.0, (a, b) => a + b);

  /// Weight for [ideaId], 0 when unknown.
  double weightOf(String ideaId) => weightsById[ideaId] ?? 0.0;
}

/// Assesses independence across ideas. Pure logic, no I/O or clocks.
class IndependenceAssessor {
  /// Entry-mid difference (points) still considered near-identical.
  static const double entryNear = 1.5;

  /// SL difference (points) still considered near-identical.
  static const double slNear = 1.5;

  /// Mean per-index TP difference (points) still near-identical.
  static const double tpNear = 2.0;

  /// Publication gap (minutes) suggesting a copy cascade.
  static const double timeNearMinutes = 5.0;

  /// Jaccard wording overlap suggesting a copy.
  static const double wordingThreshold = 0.5;

  /// Builds a normalized fingerprint for [idea].
  ///
  /// Format: `DIR|ENTRY|SL|TPS|AUTHOR|BUCKET` where prices are rounded to
  /// whole points, TPS is the sorted rounded set, author is lowercased, and
  /// BUCKET is the 5-minute publication bucket (`na` when unknown).
  static String fingerprint(TradeIdea idea) {
    final dir = idea.direction.toJson();
    final entry = idea.entryMid == null ? 'na' : '${idea.entryMid!.round()}';
    final sl = idea.stopLoss == null ? 'na' : '${idea.stopLoss!.round()}';
    final tps = idea.takeProfits.isEmpty
        ? 'na'
        : ((idea.takeProfits.map((e) => e.price.round()).toList()..sort())
            .join(','));
    final author = (idea.author ?? '').trim().toLowerCase();
    final bucket = _bucket5min(idea.publishedAt);
    return '$dir|$entry|$sl|$tps|$author|$bucket';
  }

  static String _bucket5min(DateTime? t) {
    if (t == null) return 'na';
    final u = t.toUtc();
    final bucketMin = (u.minute ~/ 5) * 5;
    final mm = bucketMin.toString().padLeft(2, '0');
    final hh = u.hour.toString().padLeft(2, '0');
    return '${u.year}-${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}T$hh:$mm';
  }

  /// Jaccard similarity of lowercased word tokens. Empty inputs score 0
  /// (missing reasoning never counts as agreement).
  static double wordingSimilarity(String? a, String? b) {
    if (a == null || b == null) return 0.0;
    final ta = _tokens(a);
    final tb = _tokens(b);
    if (ta.isEmpty || tb.isEmpty) return 0.0;
    final inter = ta.intersection(tb).length;
    final union = ta.union(tb).length;
    if (union == 0) return 0.0;
    return inter / union;
  }

  static Set<String> _tokens(String s) {
    return s
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty)
        .toSet();
  }

  static bool _sameAuthor(String? a, String? b) {
    if (a == null || b == null) return false;
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    return x.isNotEmpty && x == y;
  }

  static double? _timeGapMinutes(TradeIdea a, TradeIdea b) {
    if (a.publishedAt == null || b.publishedAt == null) return null;
    return a.publishedAt!
        .difference(b.publishedAt!)
        .inSeconds
        .abs() /
        60.0;
  }

  static bool _levelsNear(TradeIdea a, TradeIdea b) {
    if (a.direction != b.direction) return false;
    final ae = a.entryMid;
    final be = b.entryMid;
    if (ae != null && be != null) {
      if ((ae - be).abs() > entryNear) return false;
    } else if (ae != be) {
      return false;
    }
    if (a.stopLoss != null && b.stopLoss != null) {
      if ((a.stopLoss! - b.stopLoss!).abs() > slNear) return false;
    } else if (a.stopLoss != be) {
      // One side missing SL while the other has it: not near-identical.
      if ((a.stopLoss == null) != (b.stopLoss == null)) return false;
    }
    final atp = a.takeProfits.map((e) => e.price).toList();
    final btp = b.takeProfits.map((e) => e.price).toList();
    if (atp.isEmpty || btp.isEmpty) return false;
    final n = atp.length < btp.length ? atp.length : btp.length;
    var sum = 0.0;
    for (var i = 0; i < n; i++) {
      sum += (atp[i] - btp[i]).abs();
    }
    return (sum / n) <= tpNear;
  }

  /// True when [a] and [b] are the same underlying idea.
  static bool isDuplicate(TradeIdea a, TradeIdea b) {
    if (!_levelsNear(a, b)) return false;
    if (_sameAuthor(a.author, b.author)) return true;
    if (wordingSimilarity(a.reasoning, b.reasoning) >= wordingThreshold) {
      return true;
    }
    final gap = _timeGapMinutes(a, b);
    if (gap != null && gap <= timeNearMinutes) return true;
    return false;
  }

  /// Groups [ideas] into independent votes and assigns weights.
  ///
  /// Within each group the earliest-published idea (nulls last, ties by id)
  /// keeps weight 1.0; the rest receive [duplicateEpsilon].
  static IndependenceResult assess(List<TradeIdea> ideas) {
    final groupMembers = <List<TradeIdea>>[];
    for (final idea in ideas) {
      var placed = false;
      for (final group in groupMembers) {
        if (isDuplicate(group.first, idea)) {
          group.add(idea);
          placed = true;
          break;
        }
      }
      if (!placed) groupMembers.add(<TradeIdea>[idea]);
    }
    final weights = <String, double>{};
    final groups = <IndependenceGroup>[];
    for (final group in groupMembers) {
      final ordered = List<TradeIdea>.of(group)
        ..sort((a, b) {
          if (a.publishedAt == null && b.publishedAt == null) {
            return a.id.compareTo(b.id);
          }
          if (a.publishedAt == null) return 1;
          if (b.publishedAt == null) return -1;
          final c = a.publishedAt!.compareTo(b.publishedAt!);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      for (var i = 0; i < ordered.length; i++) {
        weights[ordered[i].id] = i == 0 ? 1.0 : duplicateEpsilon;
      }
      groups.add(IndependenceGroup(
          List.unmodifiable(ordered.map((e) => e.id))));
    }
    return IndependenceResult(
      weightsById: Map.unmodifiable(weights),
      groups: List.unmodifiable(groups),
    );
  }
}
