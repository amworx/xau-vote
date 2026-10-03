import 'package:test/test.dart';
import 'package:xau_core/xau_core.dart';
// Imported directly because the barrel hides this IndependenceResult to avoid
// colliding with the consensus package's same-named type.
import 'package:xau_core/analysis/independence.dart' as ind;


DateTime t(int minute) => DateTime.utc(2026, 10, 2, 12, minute);

IdeaProvenance derived({
  required String id,
  String dataset = 'CFTC-COT-2026-09-25',
  String methodology = 'cot_positioning_reader',
  int minute = 0,
  ModelOwner owner = ModelOwner.us,
}) =>
    IdeaProvenance(
      ideaId: id,
      direction: 'LONG',
      modelOwner: owner,
      upstreamDataset: dataset,
      methodologyId: methodology,
      publishedAt: t(minute),
      derived: true,
    );

IdeaProvenance published({
  required String id,
  required String publisher,
  String? author,
  String methodology = 'manual_analysis',
  String? dataset,
  int minute = 0,
}) =>
    IdeaProvenance(
      ideaId: id,
      direction: 'LONG',
      modelOwner: ModelOwner.thirdParty,
      publisherId: publisher,
      authorId: author,
      upstreamDataset: dataset,
      methodologyId: methodology,
      publishedAt: t(minute),
      derived: false,
    );

void main() {
  const scorer = IndependenceScorer();
  const w = IndependenceWeights();

  group('similarity weights', () {
    test('self-similarity is exactly 1', () {
      final a = derived(id: 'a');
      expect(w.similarity(a, a), 1.0);
    });

    test('shared upstream data is the dominant term', () {
      final a = derived(id: 'a');
      final b = derived(id: 'b', methodology: 'other_reader');
      // Methodology differs and both are derived, so the additive total is
      // 0.70 (dataset) + 0.04 (time window, same minute) + 0.02 (both derived).
      expect(w.similarity(a, b), closeTo(0.76, 1e-9));
      // Isolating the dataset term: move the timestamp out of tolerance so only
      // dataset + derivedFlag remain.
      final later = derived(id: 'c', methodology: 'other_reader', minute: 40);
      expect(w.similarity(a, later), closeTo(0.72, 1e-9));
    });

    test('the threshold sits just below the shared-dataset weight', () {
      // This is the load-bearing relationship: readers of one release always
      // cluster, while unrelated publishers never do.
      expect(w.upstreamDataset, greaterThan(w.similarityThreshold));
      expect(w.upstreamDataset - w.similarityThreshold, lessThan(0.10));
    });

    test('two unrelated publishers score far below the threshold', () {
      final a = published(id: 'x', publisher: 'P1', methodology: 'm1');
      final b = published(id: 'y', publisher: 'P2', methodology: 'm2', minute: 40);
      expect(w.similarity(a, b), lessThan(w.similarityThreshold));
    });

    test('same publisher contributes 0.10 and same author 0.05', () {
      final a = published(id: 'x', publisher: 'P1', author: 'A1', methodology: 'm1');
      final b = published(id: 'y', publisher: 'P1', author: 'A1', methodology: 'm2', minute: 40);
      // publisher 0.10 + author 0.05 + both directly published 0.02.
      expect(w.similarity(a, b), closeTo(0.17, 1e-9));
    });

    test('nulls never count as a match', () {
      final a = published(id: 'x', publisher: 'P1', methodology: 'm1');
      final b = published(id: 'y', publisher: 'P2', methodology: 'm2', minute: 40);
      // No dataset on either side: the dominant term must contribute nothing.
      expect(w.similarity(a, b), lessThan(0.05));
    });

    test('a timestamp outside the tolerance does not match', () {
      final near = published(id: 'x', publisher: 'P1', methodology: 'm1', minute: 0);
      final justInside =
          published(id: 'y', publisher: 'P2', methodology: 'm2', minute: 14);
      final far = published(id: 'z', publisher: 'P3', methodology: 'm3', minute: 16);
      // Tolerance is inclusive at 15 minutes, so 15 still matches and 16 does
      // not. Inside: time term 0.04; outside: time term 0.
      expect(w.similarity(near, justInside), closeTo(0.06, 1e-9));
      expect(w.similarity(near, far), closeTo(0.02, 1e-9));
    });

    test('derived-vs-direct mismatch contributes 0.02', () {
      final a = derived(id: 'a', methodology: 'm');
      final b = published(id: 'b', publisher: 'P1', methodology: 'm', minute: 40);
      // methodology equal (0.05) but derived flags differ (0.02 withheld).
      expect(w.similarity(a, b), closeTo(0.05, 1e-9));
    });
  });

  group('the hard rule: our model is never an independent source', () {
    test('a derived reader earns zero external voices', () {
      final r = scorer.score(
        IdeaAgreement(
          direction: 'LONG',
          ideas: [
            derived(id: 'a', dataset: 'D1', methodology: 'm1'),
            derived(id: 'b', dataset: 'D2', methodology: 'm2'),
            derived(id: 'c', dataset: 'D3', methodology: 'm3'),
          ],
        ),
      );
      expect(r.externalVoices, 0);
      expect(r.analyticalMethods, 3);
      expect(r.upstreamDatasets, 3);
    });

    test('more datasets never convert derived ideas into sources', () {
      final few = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        derived(id: 'a', dataset: 'D1', methodology: 'm1'),
      ]));
      final many = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        derived(id: 'a', dataset: 'D1', methodology: 'm1'),
        derived(id: 'b', dataset: 'D2', methodology: 'm2'),
        derived(id: 'c', dataset: 'D3', methodology: 'm3'),
        derived(id: 'd', dataset: 'D4', methodology: 'm4'),
      ]));
      expect(few.externalVoices, 0);
      expect(many.externalVoices, 0);
    });

    test('an unknown model owner is treated as ours, never as a source', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        IdeaProvenance(
          ideaId: 'u',
          direction: 'LONG',
          modelOwner: ModelOwner.unknown,
          publisherId: 'P?',
          methodologyId: 'm',
          publishedAt: t(0),
          derived: true,
        ),
      ]));
      expect(r.externalVoices, 0);
    });

    test('a third-party derivation delivered as a signal does count', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        IdeaProvenance(
          ideaId: 'third',
          direction: 'LONG',
          modelOwner: ModelOwner.thirdParty,
          publisherId: 'CFTC',
          methodologyId: 'official_positioning',
          publishedAt: t(0),
          derived: true,
        ),
      ]));
      expect(r.externalVoices, 1);
    });

    test('two ideas from one publisher are one voice', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        published(id: 'a', publisher: 'P1', methodology: 'm1'),
        published(id: 'b', publisher: 'P1', methodology: 'm2', minute: 40),
      ]));
      expect(r.externalVoices, 1);
    });

    test('two publishers are two voices', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        published(id: 'a', publisher: 'P1', methodology: 'm1'),
        published(id: 'b', publisher: 'P2', methodology: 'm2', minute: 40),
      ]));
      expect(r.externalVoices, 2);
    });
  });

  group('worked example 1: three derived readers, one COT release', () {
    late ind.IndependenceResult r;

    setUp(() {
      r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        derived(id: 'A', dataset: 'CFTC-COT-2026-09-25', methodology: 'cot_positioning_reader'),
        derived(id: 'B', dataset: 'CFTC-COT-2026-09-25', methodology: 'cot_trend_reader', minute: 5),
        derived(id: 'C', dataset: 'CFTC-COT-2026-09-25', methodology: 'rsi_ema_macd_reader', minute: 9),
      ]));
    });

    test('all three cluster into one voice', () {
      expect(r.clusters, hasLength(1));
      expect(r.clusters.single, hasLength(3));
    });

    test('the effective count is exactly 1, not 2', () {
      // This is the case where a prior review suggested 2/3 by crediting
      // methodological difference as partial independence. That is rejected:
      // one release read three ways is still one voice.
      expect(r.effectiveVoices, 1.0);
    });

    test('three methods and one dataset are still reported separately', () {
      expect(r.analyticalMethods, 3);
      expect(r.upstreamDatasets, 1);
      expect(r.externalVoices, 0);
      expect(r.derivedCount, 3);
    });

    test('no source ratio is available with zero eligible publishers', () {
      expect(r.canShowSourceRatio, isFalse);
      expect(r.isAwaitingExternalSources, isTrue);
    });
  });

  group('worked example 2: two analysts plus a derived reader', () {
    late ind.IndependenceResult r;

    setUp(() {
      r = scorer.score(
        IdeaAgreement(direction: 'LONG', ideas: [
          published(id: 'X', publisher: 'P1', methodology: 'm1'),
          published(id: 'Y', publisher: 'P2', methodology: 'm2', dataset: 'D2', minute: 40),
          derived(id: 'Z', dataset: 'D3', methodology: 'm3', minute: 80),
        ]),
        eligiblePublishers: 5,
      );
    });

    test('three separate clusters', () {
      expect(r.clusters, hasLength(3));
    });

    test('effective count equals the cluster count', () {
      expect(r.effectiveVoices, closeTo(3.0, 1e-9));
    });

    test('only the two publishers count as sources', () {
      expect(r.externalVoices, 2);
      expect(r.analyticalMethods, 3);
      expect(r.upstreamDatasets, 2);
    });

    test('the source ratio is available and honest', () {
      expect(r.canShowSourceRatio, isTrue);
      expect(r.eligiblePublishers, 5);
      expect(r.isAwaitingExternalSources, isFalse);
      expect(r.hasExternalAgreement, isTrue);
    });
  });

  group('entropy reduction', () {
    test('a single cluster always yields exactly 1', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        derived(id: 'a', dataset: 'D1', methodology: 'm1'),
        derived(id: 'b', dataset: 'D1', methodology: 'm2', minute: 3),
      ]));
      expect(r.effectiveVoices, 1.0);
    });

    test('equal clusters yield exactly their count', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        published(id: 'a', publisher: 'P1', methodology: 'm1'),
        published(id: 'b', publisher: 'P2', methodology: 'm2', minute: 40),
        published(id: 'c', publisher: 'P3', methodology: 'm3', minute: 80),
        published(id: 'd', publisher: 'P4', methodology: 'm4', minute: 120),
      ]));
      expect(r.effectiveVoices, closeTo(4.0, 1e-9));
    });

    test('an unbalanced clustering lands between 1 and K', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        // Cluster 1: three readers of one release.
        derived(id: 'a', dataset: 'D1', methodology: 'm1'),
        derived(id: 'b', dataset: 'D1', methodology: 'm2', minute: 2),
        derived(id: 'c', dataset: 'D1', methodology: 'm3', minute: 4),
        // Cluster 2: one lone publisher.
        published(id: 'd', publisher: 'P1', methodology: 'm4', minute: 90),
      ]));
      expect(r.effectiveVoices, greaterThan(1.0));
      expect(r.effectiveVoices, lessThan(2.0));
    });
  });

  group('edge cases', () {
    test('empty agreement reports zeroes rather than dividing by zero', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: const []));
      expect(r.externalVoices, 0);
      expect(r.effectiveVoices, 0.0);
      expect(r.clusters, isEmpty);
      expect(r.canShowSourceRatio, isFalse);
    });

    test('a method id is required before it counts as a method', () {
      // Our own model with a publisher recorded is still NOT a source: the
      // hard rule is decided by model ownership, not by the presence of a
      // publisher field.
      final ours = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        IdeaProvenance(
          ideaId: 'x',
          direction: 'LONG',
          modelOwner: ModelOwner.us,
          publisherId: 'P1',
          publishedAt: t(0),
        ),
      ]));
      expect(ours.analyticalMethods, 0);
      expect(ours.externalVoices, 0,
          reason: 'a publisher field cannot promote our own model to a source');

      // A third-party idea with no methodology still counts as one source.
      final theirs = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        IdeaProvenance(
          ideaId: 'y',
          direction: 'LONG',
          modelOwner: ModelOwner.thirdParty,
          publisherId: 'P2',
          publishedAt: t(0),
        ),
      ]));
      expect(theirs.analyticalMethods, 0);
      expect(theirs.externalVoices, 1);
    });

    test('an author without a publisher still identifies a voice', () {
      final r = scorer.score(IdeaAgreement(direction: 'LONG', ideas: [
        IdeaProvenance(
          ideaId: 'x',
          direction: 'LONG',
          modelOwner: ModelOwner.thirdParty,
          authorId: 'analyst-77',
          methodologyId: 'm',
          publishedAt: t(0),
        ),
      ]));
      expect(r.externalVoices, 1);
    });

    test('scoring is order-independent', () {
      final ideas = [
        published(id: 'a', publisher: 'P1', methodology: 'm1'),
        published(id: 'b', publisher: 'P2', methodology: 'm2', minute: 40),
        derived(id: 'c', dataset: 'D3', methodology: 'm3', minute: 80),
      ];
      final forward = scorer.score(IdeaAgreement(direction: 'LONG', ideas: ideas));
      final reversed = scorer.score(IdeaAgreement(direction: 'LONG', ideas: ideas.reversed.toList()));
      expect(reversed.externalVoices, forward.externalVoices);
      expect(reversed.effectiveVoices, forward.effectiveVoices);
      expect(reversed.clusters, forward.clusters);
    });
  });
}