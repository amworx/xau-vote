/// Source-independence scoring for trade ideas (product rule 3).
///
/// # Why this exists
///
/// A naive row count reported one manual seed source as "11 of 11 sources
/// agree" — a tautology that could never show partial agreement, and a direct
/// breach of the rule that copied ideas count as ONE vote. The figure also
/// inflated a single author into several voices: our own derived readers read
/// different datasets but share one model, so they are not independent.
///
/// # The three metrics
///
/// [IndependenceResult] reports three separate numbers, deliberately never
/// combined:
///
///  * [IndependenceResult.externalVoices] — distinct external publishers that
///    agree. This is the only number allowed to be called "sources".
///  * [IndependenceResult.analyticalMethods] — distinct analytical methods
///    agreeing. Reported as "methods", never as sources or as independent.
///  * [IndependenceResult.upstreamDatasets] — distinct upstream documents read.
///    This is the real diversity available to a derived-only system.
///
/// # The hard rule
///
/// A derived idea contributes **zero** to [IndependenceResult.externalVoices],
/// no matter how many distinct datasets it reads. The test is not
/// derived-vs-direct but **who owns the model**: our transform over a public
/// dataset is our own analytical view, and every derived reader we write shares
/// our assumptions, parsing and bugs. Counting them as voices reintroduces
/// exactly the correlated error independence exists to remove — one author
/// split across three datasets instead of one source split across eleven ideas.
///
/// A derivation by a *third party*, delivered as a signal, is that party's
/// direct output and earns full credit. Hence [ModelOwner], not a boolean.
///
/// # Similarity and aggregation
///
/// Pairwise similarity is a weighted sum of shared provenance. Pairs at or above
/// [IndependenceWeights.similarityThreshold] join a cluster; clusters are then
/// weighted by voice and reduced by Shannon entropy to an effective count
/// `N_eff = exp(H)`. Equal clusters give exactly K; one cluster gives exactly 1.
library;

import 'dart:math' as math;

/// Who owns the analytical model behind an idea. This, not derived-vs-direct,
/// decides whether an idea can ever count as an independent source.
enum ModelOwner {
  /// We wrote the transform. Never an independent source, whatever it reads.
  us,

  /// A third party produced the signal, including a third party's derivation
  /// delivered as a signal. Counts as a normal external publisher.
  thirdParty,

  /// No model owner recorded. Treated as [ModelOwner.us] for safety, so an
  /// unlabelled idea cannot quietly earn source credit.
  unknown,
}

/// Provenance for one trade idea. Only [publisherId] identifies an external
/// voice; the rest describe where the idea came from.
class IdeaProvenance {
  const IdeaProvenance({
    required this.ideaId,
    required this.direction,
    required this.modelOwner,
    this.publisherId,
    this.authorId,
    this.upstreamDataset,
    this.methodologyId,
    required this.publishedAt,
    this.eventWindow,
    this.derived = false,
  });

  final String ideaId;
  final String direction;

  /// Decides source eligibility. See [ModelOwner].
  final ModelOwner modelOwner;

  /// The external publisher. Null for our own derived ideas.
  final String? publisherId;
  final String? authorId;

  /// Identity of the upstream document, e.g. `CFTC-COT-2026-09-25`. Two readers
  /// of the same release share this value and therefore cluster together.
  final String? upstreamDataset;

  /// Which transform produced the idea, e.g. `cot_positioning_reader`.
  final String? methodologyId;

  final DateTime publishedAt;

  /// The economic release or event window this idea responds to, if any.
  final String? eventWindow;

  /// Whether our code produced the number rather than a human publishing it.
  final bool derived;

  /// A derived idea can only ever be an analytical method, never a source.
  bool get isEligibleAsSource {
    final owner = modelOwner == ModelOwner.unknown ? ModelOwner.us : modelOwner;
    return owner == ModelOwner.thirdParty;
  }

  @override
  String toString() => 'IdeaProvenance($ideaId, $direction, '
      '${modelOwner.name}, pub=$publisherId, ds=$upstreamDataset, m=$methodologyId)';
}

/// Directional agreement for one side (long or short).
class IdeaAgreement {
  IdeaAgreement({required this.direction, required this.ideas});

  final String direction;
  final List<IdeaProvenance> ideas;

  bool get isEmpty => ideas.isEmpty;
}

/// Provenance similarity weights.
///
/// Derived from the reviewed formula; the dominant term is shared upstream data,
/// which is what collapses several readers of one release into a single voice.
class IndependenceWeights {
  const IndependenceWeights({
    this.publisher = 0.10,
    this.author = 0.05,
    this.upstreamDataset = 0.70,
    this.methodology = 0.05,
    this.timeWindow = 0.04,
    this.eventWindow = 0.04,
    this.derivedFlag = 0.02,
    this.similarityThreshold = 0.65,
    this.timeWindowTolerance = const Duration(minutes: 15),
  });

  final double publisher;
  final double author;
  final double upstreamDataset;
  final double methodology;
  final double timeWindow;
  final double eventWindow;
  final double derivedFlag;

  /// Pairs at or above this join a cluster. 0.65 sits just below the 0.70 that
  /// shared upstream data alone contributes, so two readers of one release are
  /// always one voice while two unrelated publishers never merge.
  final double similarityThreshold;

  final Duration timeWindowTolerance;

  double similarity(IdeaProvenance a, IdeaProvenance b) {
    if (a.ideaId == b.ideaId) return 1.0;
    var s = 0.0;
    s += publisher * _sameNonEmpty(a.publisherId, b.publisherId);
    s += author * _sameNonEmpty(a.authorId, b.authorId);
    s += upstreamDataset * _sameNonEmpty(a.upstreamDataset, b.upstreamDataset);
    s += methodology * _sameNonEmpty(a.methodologyId, b.methodologyId);
    s += timeWindow * _withinWindow(a.publishedAt, b.publishedAt, timeWindowTolerance);
    s += eventWindow * _sameNonEmpty(a.eventWindow, b.eventWindow);
    s += derivedFlag * ((a.derived == b.derived) ? 1.0 : 0.0);
    return s;
  }

  static double _sameNonEmpty(String? a, String? b) {
    if (a == null || b == null || a.isEmpty || b.isEmpty) return 0.0;
    return a == b ? 1.0 : 0.0;
  }

  static double _withinWindow(DateTime a, DateTime b, Duration tol) {
    final diff = a.difference(b).abs();
    return diff <= tol ? 1.0 : 0.0;
  }
}

/// Three independent measures. Never merged into one figure.
class IndependenceResult {
  const IndependenceResult({
    required this.direction,
    required this.externalVoices,
    required this.eligiblePublishers,
    required this.analyticalMethods,
    required this.upstreamDatasets,
    required this.effectiveVoices,
    required this.clusters,
    required this.derivedCount,
  });

  final String direction;

  /// Distinct external publishers that agree. The only figure that may be
  /// labelled "sources".
  final int externalVoices;

  /// Total eligible publishers in the pool, i.e. the "of M" denominator.
  final int eligiblePublishers;

  /// Distinct analytical methods agreeing. Reported as "methods", never as
  /// sources and never described as independent.
  final int analyticalMethods;

  /// Distinct upstream documents read by the agreeing ideas.
  final int upstreamDatasets;

  /// Shannon-entropy effective count over the clusters. Equals [externalVoices]
  /// for external-only agreement; used to describe method diversity.
  final double effectiveVoices;

  /// Cluster membership, for the provenance drill-down.
  final List<List<String>> clusters;

  /// How many agreeing ideas were derived rather than published.
  final int derivedCount;

  bool get hasExternalAgreement => externalVoices > 0;

  /// True when there is no external publisher to be right or wrong, so the UI
  /// must say so rather than render a zero.
  bool get isAwaitingExternalSources => eligiblePublishers == 0;

  /// Whether "N of M sources" wording is meaningful at all.
  bool get canShowSourceRatio => eligiblePublishers > 0;

  @override
  String toString() => 'IndependenceResult($direction: '
      '$externalVoices/$eligiblePublishers sources, '
      '$analyticalMethods methods, $upstreamDatasets datasets)';
}

/// Scores agreement using provenance, never row counts.
class IndependenceScorer {
  const IndependenceScorer([this.weights = const IndependenceWeights()]);

  final IndependenceWeights weights;

  IndependenceResult score(
    IdeaAgreement agreement, {
    int eligiblePublishers = 0,
  }) {
    final ideas = agreement.ideas;
    if (ideas.isEmpty) {
      return IndependenceResult(
        direction: agreement.direction,
        externalVoices: 0,
        eligiblePublishers: eligiblePublishers,
        analyticalMethods: 0,
        upstreamDatasets: 0,
        effectiveVoices: 0,
        clusters: const [],
        derivedCount: 0,
      );
    }

    // ---- Hard rule: only third-party models can be sources ----------------
    final external = ideas.where((i) => i.isEligibleAsSource).toList();
    final externalVoices = external
        .map((i) => i.publisherId ?? i.authorId ?? i.ideaId)
        .toSet()
        .length;

    // Analytical methods include every agreeing reader, external or not,
    // because the question is "how many distinct ways of reading the data
    // point this way" — never "how many sources agree".
    final methods = ideas
        .map((i) => i.methodologyId)
        .whereType<String>()
        .where((m) => m.isNotEmpty)
        .toSet()
        .length;

    final datasets = ideas
        .map((i) => i.upstreamDataset)
        .whereType<String>()
        .where((d) => d.isNotEmpty)
        .toSet()
        .length;

    final derivedCount = ideas.where((i) => i.derived).length;

    // ---- Cluster, then reduce by entropy ---------------------------------
    final clusters = _cluster(ideas);
    final effective = _effectiveCount(clusters, ideas);

    return IndependenceResult(
      direction: agreement.direction,
      externalVoices: externalVoices,
      eligiblePublishers: eligiblePublishers,
      analyticalMethods: methods,
      upstreamDatasets: datasets,
      effectiveVoices: effective,
      clusters: clusters,
      derivedCount: derivedCount,
    );
  }

  /// Thresholded connected components over the similarity graph.
  List<List<String>> _cluster(List<IdeaProvenance> ideas) {
    final n = ideas.length;
    final parent = List<int>.generate(n, (i) => i);

    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (weights.similarity(ideas[i], ideas[j]) >= weights.similarityThreshold) {
          union(i, j);
        }
      }
    }

    final byRoot = <int, List<String>>{};
    for (var i = 0; i < n; i++) {
      byRoot.putIfAbsent(find(i), () => <String>[]).add(ideas[i].ideaId);
    }
    final out = byRoot.values.map((ids) => ids..sort()).toList();
    // Deterministic ordering. Union-find roots depend on traversal order, so
    // without this the same idea set could report its clusters in a different
    // order on each run and break result reproducibility.
    out.sort((a, b) {
      final bySize = b.length.compareTo(a.length);
      return bySize != 0 ? bySize : a.first.compareTo(b.first);
    });
    return out;
  }

  /// `N_eff = exp(H)` where `H` is the Shannon entropy of the cluster weight
  /// distribution. Equal clusters give exactly K; a single cluster gives 1.
  double _effectiveCount(List<List<String>> clusters, List<IdeaProvenance> ideas) {
    if (clusters.isEmpty) return 0;
    if (clusters.length == 1) return 1;

    final byId = {for (final i in ideas) i.ideaId: i};
    final weights = clusters
        .map((c) => c.fold<double>(0, (sum, id) => sum + (byId[id] == null ? 0 : 1)))
        .toList();
    final total = weights.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return clusters.length.toDouble();

    var h = 0.0;
    for (final w in weights) {
      final p = w / total;
      // ln(1) == 0, and a zero-probability cluster contributes nothing.
      if (p > 0 && p < 1) h -= p * math.log(p);
    }
    return math.exp(h);
  }
}