/// Idea-source abstraction (spec §19) + mock fixtures (TASK-03 T3.2).
library;

import 'package:xau_core/xau_core.dart';

/// Static metadata for one idea source (spec §21 `sources` row).
class SourceInfo {
  /// Display name, e.g. `Source A`.
  final String name;

  /// Canonical URL of the source.
  final String url;

  /// URL of the license/terms page, when known.
  final String? licenseUrl;

  /// Whether automation against this source was explicitly allowed.
  /// Production adapters require a recorded licensing review (core rule 6);
  /// mocks default to false and must never be mistaken for clearance.
  final bool automationAllowed;

  /// Whether commercial redistribution was explicitly allowed.
  final bool commercialUseAllowed;

  /// Creates source metadata.
  const SourceInfo({
    required this.name,
    required this.url,
    this.licenseUrl,
    this.automationAllowed = false,
    this.commercialUseAllowed = false,
  });
}

/// External trade-idea feed normalized to [TradeIdea] (spec §19).
///
/// Each adapter converts external information into [TradeIdea]; adapters for
/// real sources additionally require a licensing/automation review before
/// being enabled (core rule 6).
abstract class IdeaSource {
  /// Static metadata for this source.
  SourceInfo get info;

  /// Ideas published at/after [since]. Implementations filter on
  /// `publishedAt`; ideas without a timestamp are always returned and left
  /// for the pipeline freshness stage to treat as AGING.
  Future<List<TradeIdea>> fetchRecent({required DateTime since});
}

/// In-memory [IdeaSource] over a fixed idea list (dev/test).
class MockIdeaSource implements IdeaSource {
  @override
  final SourceInfo info;

  /// Ideas returned by [fetchRecent] (subject to the `since` filter).
  final List<TradeIdea> ideas;

  /// Creates a mock returning [ideas] (copied unmodifiable).
  MockIdeaSource(List<TradeIdea> ideas, {SourceInfo? info})
      : ideas = List.unmodifiable(ideas),
        info = info ?? const SourceInfo(name: 'mock', url: 'mock://local');

  /// Spec §6 A/B/C/D scenario: clustered LONGs plus one SHORT dissenter.
  factory MockIdeaSource.abcd(DateTime now) => MockIdeaSource(
        MockFixtures.abcd(now),
        info: const SourceInfo(name: 'mock-abcd', url: 'mock://abcd'),
      );

  /// Spec §5: four copies of one underlying idea (one independent vote).
  factory MockIdeaSource.fourCopies(DateTime now) => MockIdeaSource(
        MockFixtures.fourCopies(now),
        info: const SourceInfo(name: 'mock-copies', url: 'mock://copies'),
      );

  /// Spec §3: divided room (2 LONG / 2 SHORT / 1 NEUTRAL).
  factory MockIdeaSource.divided(DateTime now) => MockIdeaSource(
        MockFixtures.divided(now),
        info: const SourceInfo(name: 'mock-divided', url: 'mock://divided'),
      );

  /// All ideas older than 60 minutes (freshness filter must reject all).
  factory MockIdeaSource.staleOnly(DateTime now) => MockIdeaSource(
        MockFixtures.staleOnly(now),
        info: const SourceInfo(name: 'mock-stale', url: 'mock://stale'),
      );

  /// Ideas without extractable levels (must become INSUFFICIENT DATA,
  /// never fabricated levels).
  factory MockIdeaSource.missingLevels(DateTime now) => MockIdeaSource(
        MockFixtures.missingLevels(now),
        info: const SourceInfo(name: 'mock-levels', url: 'mock://levels'),
      );

  @override
  Future<List<TradeIdea>> fetchRecent({required DateTime since}) async =>
      ideas
          .where(
            (idea) =>
                idea.publishedAt == null ||
                !idea.publishedAt!.isBefore(since),
          )
          .toList();
}

/// Deterministic fixture builders behind [MockIdeaSource].
///
/// Every builder takes the reference [now] so `publishedAt` values stay
/// deterministic; no clock reads inside. Level values for [abcd],
/// [fourCopies] and [divided] mirror the proven core engine tests.
class MockFixtures {
  const MockFixtures._();

  static TradeIdea _mk({
    required String id,
    required String source,
    required Direction direction,
    double? entryLow,
    double? entryHigh,
    double? stopLoss,
    List<double> tps = const [],
    String? author,
    String? reasoning,
    DateTime? publishedAt,
    TradeTimeframe timeframe = TradeTimeframe.m15,
    String symbol = 'XAUUSD',
  }) =>
      TradeIdea(
        id: id,
        source: source,
        author: author,
        publishedAt: publishedAt,
        timeframe: timeframe,
        symbol: symbol,
        direction: direction,
        entryLow: entryLow,
        entryHigh: entryHigh,
        stopLoss: stopLoss,
        takeProfits: [
          for (var i = 0; i < tps.length; i++)
            TakeProfit(index: i + 1, price: tps[i]),
        ],
        reasoning: reasoning,
      );

  /// Spec §6 A/B/C/D: three clustered LONGs + one SHORT dissenter.
  /// Builds a STRONG LONG consensus via [ConsensusEngine].
  static List<TradeIdea> abcd(DateTime now) => [
        _mk(
          id: 'a',
          source: 'Source A',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: const [4295, 4315],
          author: 'Alice',
          reasoning: 'bullish breakout above resistance with momentum',
          publishedAt: now.subtract(const Duration(minutes: 12)),
        ),
        _mk(
          id: 'b',
          source: 'Source B',
          direction: Direction.long,
          entryLow: 4276,
          entryHigh: 4281,
          stopLoss: 4264,
          tps: const [4298, 4320],
          author: 'Bob',
          reasoning: 'gold support bounce off moving average trendline',
          publishedAt: now.subtract(const Duration(minutes: 5)),
        ),
        _mk(
          id: 'c',
          source: 'Source C',
          direction: Direction.long,
          entryLow: 4274,
          entryHigh: 4279,
          stopLoss: 4263,
          tps: const [4296, 4318],
          author: 'Cara',
          reasoning: 'dollar weakness drives safe haven demand buying',
          publishedAt: now,
        ),
        _mk(
          id: 'd',
          source: 'Source D',
          direction: Direction.short,
          entryLow: 4285,
          entryHigh: 4285,
          stopLoss: 4300,
          tps: const [4260],
          author: 'Dan',
          reasoning: 'overbought rejection at supply double top',
          publishedAt: now.subtract(const Duration(minutes: 3)),
        ),
      ];

  /// Spec §5: four copies of one idea → one independent vote
  /// (SINGLE_SOURCE, no consensus).
  static List<TradeIdea> fourCopies(DateTime now) => List.generate(
        4,
        (i) => _mk(
          id: 'copy-$i',
          source: 'Source ${'ABCD'[i]}',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: const [4295, 4315],
          author: 'Same Analyst',
          reasoning: 'same copied call long gold breakout',
          publishedAt: now.subtract(Duration(minutes: 6 - i)),
        ),
      );

  /// Spec §3: 2 LONG / 2 SHORT / 1 NEUTRAL → DIVIDED, no consensus.
  static List<TradeIdea> divided(DateTime now) => [
        _mk(
          id: 'l1',
          source: 'Source A',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: const [4295],
          author: 'A',
          reasoning: 'alpha breakout momentum buying',
          publishedAt: now.subtract(const Duration(minutes: 4)),
        ),
        _mk(
          id: 'l2',
          source: 'Source B',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: const [4295],
          author: 'B',
          reasoning: 'completely different zulu yahoo quasar',
          publishedAt: now.subtract(const Duration(minutes: 20)),
        ),
        _mk(
          id: 's1',
          source: 'Source C',
          direction: Direction.short,
          entryLow: 4285,
          entryHigh: 4290,
          stopLoss: 4305,
          tps: const [4260],
          author: 'C',
          reasoning: 'rejection supply double top shorting',
          publishedAt: now.subtract(const Duration(minutes: 6)),
        ),
        _mk(
          id: 's2',
          source: 'Source D',
          direction: Direction.short,
          entryLow: 4286,
          entryHigh: 4291,
          stopLoss: 4306,
          tps: const [4261],
          author: 'D',
          reasoning: 'overbought reversal breakdown selling',
          publishedAt: now.subtract(const Duration(minutes: 25)),
        ),
        _mk(
          id: 'n1',
          source: 'Source E',
          direction: Direction.neutral,
          entryLow: 4278,
          entryHigh: 4282,
          stopLoss: 4270,
          tps: const [4290],
          author: 'E',
          reasoning: 'waiting sideways chop indecision patience',
          publishedAt: now.subtract(const Duration(minutes: 8)),
        ),
      ];

  /// Every idea older than 60 minutes: the freshness stage must reject all,
  /// yielding NO CONSENSUS (reason INSUFFICIENT_DATA).
  static List<TradeIdea> staleOnly(DateTime now) => [
        _mk(
          id: 'stale-1',
          source: 'Source A',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          stopLoss: 4262,
          tps: const [4295, 4315],
          author: 'Alice',
          reasoning: 'bullish breakout above resistance with momentum',
          publishedAt: now.subtract(const Duration(minutes: 65)),
        ),
        _mk(
          id: 'stale-2',
          source: 'Source B',
          direction: Direction.long,
          entryLow: 4276,
          entryHigh: 4281,
          stopLoss: 4264,
          tps: const [4298, 4320],
          author: 'Bob',
          reasoning: 'gold support bounce off moving average trendline',
          publishedAt: now.subtract(const Duration(minutes: 75)),
        ),
        _mk(
          id: 'stale-3',
          source: 'Source C',
          direction: Direction.long,
          entryLow: 4274,
          entryHigh: 4279,
          stopLoss: 4263,
          tps: const [4296, 4318],
          author: 'Cara',
          reasoning: 'dollar weakness drives safe haven demand buying',
          publishedAt: now.subtract(const Duration(minutes: 95)),
        ),
      ];

  /// Ideas without extractable levels. They carry direction and reasoning
  /// but no entry/SL/TP, so the actionable stage must reject them as
  /// INSUFFICIENT DATA (core rule 5: never fabricate levels).
  static List<TradeIdea> missingLevels(DateTime now) => [
        _mk(
          id: 'ml-1',
          source: 'Source A',
          direction: Direction.long,
          author: 'Alice',
          reasoning: 'gold looks bullish today no levels given',
          publishedAt: now.subtract(const Duration(minutes: 5)),
        ),
        _mk(
          id: 'ml-2',
          source: 'Source B',
          direction: Direction.long,
          entryLow: 4275,
          entryHigh: 4280,
          author: 'Bob',
          reasoning: 'entry zone spotted but no stop or target stated',
          publishedAt: now.subtract(const Duration(minutes: 8)),
        ),
      ];
}
