/// Offline pipeline orchestrator (spec §4 + §22, TASK-03 T3.4).
///
/// Flow: sources → normalize → filter chain (spec §4 order: XAUUSD →
/// intraday → 15M-relevant → fresh → actionable → not-duplicate) →
/// consensus → 1H context attach (metadata only) → lifecycle tick driven by
/// the [MarketDataProvider].
library;

import 'package:xau_core/xau_core.dart';
import 'package:xau_lifecycle/xau_lifecycle.dart';

import 'idea_source.dart';
import 'market_data_provider.dart';

/// Filter-chain stages in spec §4 order.
///
/// The order is load-bearing: each stage assumes the previous ones passed
/// (e.g. freshness is only meaningful for 15M-relevant XAUUSD ideas).
enum FilterStage {
  /// Symbol must be XAUUSD.
  xauusd,

  /// Timeframe must be intraday (forward guard; see [_isIntraday]).
  intraday,

  /// Only the 15M timeframe votes (core rule 1).
  m15Relevant,

  /// Not stale, not future-dated (spec §15 via [FreshnessPolicy]).
  fresh,

  /// Carries entry + SL + at least one TP ([TradeIdea.hasActionableLevels]).
  actionable,

  /// Not an exact duplicate of an already-accepted idea.
  notDuplicate;

  /// Serializes to the spec-style label.
  String toJson() {
    switch (this) {
      case FilterStage.xauusd:
        return 'XAUUSD';
      case FilterStage.intraday:
        return 'INTRADAY';
      case FilterStage.m15Relevant:
        return 'M15_RELEVANT';
      case FilterStage.fresh:
        return 'FRESH';
      case FilterStage.actionable:
        return 'ACTIONABLE';
      case FilterStage.notDuplicate:
        return 'NOT_DUPLICATE';
    }
  }
}

/// One idea rejected at a filter stage, with a machine-readable reason.
class FilterRejection {
  /// Id of the rejected idea.
  final String ideaId;

  /// Stage that rejected it.
  final FilterStage stage;

  /// Human-readable cause; actionable rejections carry INSUFFICIENT DATA.
  final String reason;

  /// Records a rejection.
  const FilterRejection({
    required this.ideaId,
    required this.stage,
    required this.reason,
  });
}

/// Full result of one pipeline pass.
class PipelineResult {
  /// Everything fetched from sources before filtering.
  final List<TradeIdea> collected;

  /// Ideas that survived the whole filter chain (consensus input).
  final List<TradeIdea> validIdeas;

  /// Per-idea rejections, in filter-chain order.
  final List<FilterRejection> rejections;

  /// Consensus outcome over [validIdeas] ([ConsensusOutcome] or [NoConsensus]).
  final ConsensusBuildResult consensus;

  /// 1H context attached when consensus exists; metadata only, never votes.
  final SignalContext? context;

  /// Market price that drove this pass's lifecycle tick, if any.
  final PriceQuote? price;

  /// Lifecycle state after this pass's tick, if a signal exists.
  final SignalStatus? lifecycleState;

  /// Builds a pass result.
  PipelineResult({
    required List<TradeIdea> collected,
    required List<TradeIdea> validIdeas,
    required List<FilterRejection> rejections,
    required this.consensus,
    this.context,
    this.price,
    this.lifecycleState,
  })  : collected = List.unmodifiable(collected),
        validIdeas = List.unmodifiable(validIdeas),
        rejections = List.unmodifiable(rejections);
}

/// Offline orchestrator over mocks (integration harness for Phases 1–3).
///
/// Market data enters only through [MarketDataProvider] and ideas only
/// through [IdeaSource]: swapping implementations requires zero changes
/// here (conformance-tested). Lifecycle interpretation decisions:
/// - ACTIVE means the confirmed entry filled; the MVP promotes
///   `confirmed → active` on the first tick after confirmation (barring
///   SL breach/expiry), since fills are not modeled.
/// - TP progression is direction-aware via [ConfirmationEvaluator].
/// - Expiry applies to `ready`/`confirmed` only (TASK-02 scope).
class RadarPipeline {
  /// Idea feeds collected on every [run].
  final List<IdeaSource> sources;

  /// Market data driving every lifecycle tick.
  final MarketDataProvider market;

  /// Freshness rules (with per-source overrides) for the fresh stage.
  final SourceFreshnessPolicies freshness;

  /// Look-back for `fetchRecent` (`since = now - fetchWindow`).
  /// Defaults to 2h so stale fixtures still reach the freshness stage
  /// (which — not the fetch — must reject them).
  final Duration fetchWindow;

  ConsensusSignal? _signal;
  SignalStateMachine? _lifecycle;

  /// Append-only log of lifecycle moves and ignored illegal attempts.
  final List<String> lifecycleLog = [];

  /// Creates a pipeline. Freshness and fetch window are injectable.
  RadarPipeline({
    required this.sources,
    required this.market,
    SourceFreshnessPolicies? freshness,
    this.fetchWindow = const Duration(hours: 2),
  }) : freshness = freshness ?? const SourceFreshnessPolicies();

  /// Consensus signal from the latest [run], if any.
  ConsensusSignal? get signal => _signal;

  /// Lifecycle machine from the latest [run], if consensus exists.
  SignalStateMachine? get lifecycle => _lifecycle;

  /// One full pass: collect → filter → consensus → context → market tick.
  ///
  /// The 1H trend is attached as metadata after consensus and cannot alter
  /// the score (the engine never receives it).
  Future<PipelineResult> run({
    required DateTime now,
    required Direction h1Trend,
    FiveMinuteStructure structure = const FiveMinuteStructure(),
  }) async {
    final since = now.subtract(fetchWindow);
    final collected = <TradeIdea>[];
    for (final source in sources) {
      collected.addAll(await source.fetchRecent(since: since));
    }

    final rejections = <FilterRejection>[];
    final valid = _filterChain(collected, now, rejections);
    final consensus = ConsensusEngine.build(valid, now);

    SignalContext? context;
    if (consensus is ConsensusOutcome) {
      final fresh = consensus.signal;
      _signal ??= fresh;
      _lifecycle ??= SignalStateMachine(
        initial: SignalStatus.developing,
        strict: false,
      );
      context = ContextClassifier.attach(
        signalDirection: fresh.direction,
        h1Trend: h1Trend,
      );
    }

    final price = await market.currentPrice('XAUUSD');
    _tickWithPrice(price: price.price, now: now, structure: structure);

    return PipelineResult(
      collected: collected,
      validIdeas: valid,
      rejections: rejections,
      consensus: consensus,
      context: context,
      price: price,
      lifecycleState: _lifecycle?.current,
    );
  }

  /// Advances the lifecycle with the next market price without re-fetching
  /// ideas. Returns the quote consumed, or null when no signal exists.
  Future<PriceQuote?> tick({
    required DateTime now,
    FiveMinuteStructure structure = const FiveMinuteStructure(),
  }) async {
    if (_signal == null || _lifecycle == null) return null;
    final price = await market.currentPrice('XAUUSD');
    _tickWithPrice(price: price.price, now: now, structure: structure);
    return price;
  }

  void _move(
    SignalStateMachine machine,
    SignalStatus next,
    DateTime now,
    String message,
  ) {
    final ok = machine.transitionTo(next, now, reason: message);
    lifecycleLog.add(ok ? message : 'ignored illegal $next: $message');
  }

  void _tickWithPrice({
    required double price,
    required DateTime now,
    required FiveMinuteStructure structure,
  }) {
    final machine = _lifecycle;
    final signal = _signal;
    if (machine == null || signal == null) return;

    // Expiry first: ready/confirmed at/past expiresAt → expired.
    if (machine.expireIfDue(now, signal.expiresAt, reason: 'signal expired')) {
      lifecycleLog.add('expired at $now');
      return;
    }

    switch (machine.current) {
      case SignalStatus.developing:
      case SignalStatus.ready:
      case SignalStatus.confirmed:
        final was = machine.current;
        final next = ConfirmationEvaluator.evaluate(
          signal: signal,
          price: price,
          structure: structure,
          current: was,
        );
        if (was == SignalStatus.confirmed &&
            next == SignalStatus.confirmed) {
          _move(machine, SignalStatus.active, now, 'entry filled at $price');
        } else if (next != was) {
          _move(machine, next, now, 'confirmation $next at $price');
        }
      case SignalStatus.active:
        if (ConfirmationEvaluator.isTakeProfitHit(signal, 1, price)) {
          _move(machine, SignalStatus.tp1Hit, now, 'TP1 hit at $price');
        } else if (ConfirmationEvaluator.isBreached(signal, price)) {
          _move(machine, SignalStatus.invalidated, now, 'SL breach at $price');
        }
      case SignalStatus.tp1Hit:
        if (ConfirmationEvaluator.isTakeProfitHit(signal, 2, price)) {
          _move(machine, SignalStatus.tp2Hit, now, 'TP2 hit at $price');
        } else if (ConfirmationEvaluator.isBreached(signal, price)) {
          _move(machine, SignalStatus.invalidated, now, 'SL breach at $price');
        }
      case SignalStatus.tp2Hit:
        if (ConfirmationEvaluator.isTakeProfitHit(signal, 3, price)) {
          _move(machine, SignalStatus.tp3Hit, now, 'TP3 hit at $price');
        } else if (ConfirmationEvaluator.isBreached(signal, price)) {
          _move(machine, SignalStatus.invalidated, now, 'SL breach at $price');
        }
      default:
        // noSetup is unused here; tp3Hit/invalidated/expired are terminal.
        break;
    }
  }

  /// Spec §4 filter chain in order. Appends one [FilterRejection] per
  /// rejected idea (first failing stage wins) and returns survivors.
  List<TradeIdea> _filterChain(
    List<TradeIdea> collected,
    DateTime now,
    List<FilterRejection> rejections,
  ) {
    final valid = <TradeIdea>[];
    final seenFingerprints = <String>{};
    for (final idea in collected) {
      if (idea.symbol.toUpperCase() != 'XAUUSD') {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.xauusd,
            reason: 'non-XAUUSD symbol ${idea.symbol}',
          ),
        );
        continue;
      }
      if (!_isIntraday(idea.timeframe)) {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.intraday,
            reason: 'non-intraday timeframe ${idea.timeframe.toJson()}',
          ),
        );
        continue;
      }
      if (idea.timeframe != TradeTimeframe.m15) {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.m15Relevant,
            reason: 'timeframe ${idea.timeframe.toJson()} does not vote '
                '(only M15 votes; 5M confirms, 1H is context)',
          ),
        );
        continue;
      }
      final policy = freshness.forSource(idea.source);
      if (idea.publishedAt != null && idea.publishedAt!.isAfter(now)) {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.fresh,
            reason: 'published in the future',
          ),
        );
        continue;
      }
      if (policy.classifyIdea(idea, now) == Freshness.expired) {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.fresh,
            reason: 'stale: age at/over 60 min (EXPIRED/context-only)',
          ),
        );
        continue;
      }
      if (!idea.hasActionableLevels) {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.actionable,
            reason: 'INSUFFICIENT DATA: missing entry/SL/TP levels; '
                'levels are extracted, never fabricated',
          ),
        );
        continue;
      }
      final fingerprint = idea.sourceFingerprint;
      if (fingerprint != null && !seenFingerprints.add(fingerprint)) {
        rejections.add(
          FilterRejection(
            ideaId: idea.id,
            stage: FilterStage.notDuplicate,
            reason: 'exact duplicate fingerprint $fingerprint already seen',
          ),
        );
        continue;
      }
      valid.add(idea);
    }
    return valid;
  }

  /// Intraday gate (spec §4). The current [TradeTimeframe] enum only models
  /// intraday frames (M5/M15/H1), so this passes everything today; it stays
  /// an explicit stage so Daily/H4/Weekly ideas (excluded by core rule 1)
  /// are rejected here once modeled, preserving the spec's chain order.
  static bool _isIntraday(TradeTimeframe timeframe) =>
      timeframe == TradeTimeframe.m5 ||
      timeframe == TradeTimeframe.m15 ||
      timeframe == TradeTimeframe.h1;
}
