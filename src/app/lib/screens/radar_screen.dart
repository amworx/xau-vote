/// Screen 1 — Radar (mockup `.top` … `.scenario`, exact layout).
///
/// Price block, day bar, timeframe display, the verdict card (LONG/SHORT
/// direction, agreement strength, entry/stop/TP levels, target scope,
/// source agreement, copy/share), plus the NO CONSENSUS, DEVELOPING and
/// event-guardrail states. A MOCK_MODE-only demo switcher sits under the
/// scenario strip so every required state stays reviewable.
///
/// LIVE MODE
/// `--dart-define=LIVE=true` mounts the [LiveData] poller above the screen
/// (see `main.dart`); every figure on this screen then comes from that
/// snapshot, and the offline build — which mounts no poller — renders
/// [MockFixtures]. Three rules shape the live branch:
///
///   * **Never fabricate.** A figure the pipeline has not published prints `—`
///     or an honest empty state, never a fixture value (product rule 2).
///   * **No demo affordances.** The scenario switcher is offline-only; the
///     pipeline owns the state in a live build.
///   * **A failed poll is not a failed screen.** The previous good values stay
///     on top and the failure is one quiet line beneath them.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:xau_core/analysis/independence.dart';
// Session calendar only; the barrel also exports a Direction enum that collides
// with the app's display models.
import 'package:xau_core/analysis/session.dart';

import '../config.dart';
import '../data/analysis_service.dart';
import '../data/live_data.dart';
import '../data/mock_fixtures.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/analysis_verdict_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/independence_line.dart';
import '../widgets/harbor_widgets.dart';

class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key, this.sessionOpenOverride});

  /// Pins the session state instead of reading the clock.
  ///
  /// The screen must know whether the market is trading, and a test that
  /// depends on the real calendar would pass on a Tuesday and fail at the
  /// weekend. Only tests pass this; production always reads the clock.
  @visibleForTesting
  final bool? sessionOpenOverride;

  /// Bottom-nav index of the Events screen.
  static const int eventsTab = 4;

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> {
  /// Bottom-nav index of the Events screen.
  static const int eventsTab = 4;

  /// Which timeframe the user is inspecting. 15M is the only one that can carry
  /// a consensus setup; 5M and 1H are context (product rule 1), so switching
  /// changes which view of the market is shown and never the published signal.
  String _timeframe = '15M';

/// Whether the market is treated as trading.
  ///
  /// The offline build is a UI preview over fixtures: it makes no market-status
  /// claim (the header hides the pill), and there is no real order to protect,
  /// so gating its preview on the real calendar would only blank the design at
  /// the weekend. A live build always reads the clock.
  bool _sessionOpenAt(DateTime now) =>
      widget.sessionOpenOverride ??
      (mockMode ? true : isSessionOpen(now.toUtc()));

  /// Market snapshot (offline build only). Scenario switching changes the
  /// signal, never the quote, so this is always the offline live one.
  static const DisplaySignal quote = MockFixtures.strongLong;

  /// The polled snapshot for this build, or null in an offline build.
  ///
  /// A live build always has a [LiveData] above it, so this resolves; an
  /// offline build has none and the screen reads [MockFixtures]. The lookup is
  /// the one place the two meet: it also resolves when a test mounts a snapshot
  /// above an offline build, which is what lets a single widget-test binary
  /// prove both data sources through the same screens.
  static LiveData? _liveOf(BuildContext context) {
    try {
      return context.watch<LiveData>();
    } on ProviderNotFoundException {
      // A live build that lost its poller must fail loudly rather than fall
      // back to fixtures — a trader must never read demo data as live data.
      if (!mockMode) rethrow;
      return null;
    }
  }

  /// `updated 12s ago` from the poller's own stamp, `updated —` before the
  /// first poll completes. Never the offline literal.
  String _agoLabel(DateTime? at) {
    if (at == null) return 'updated —';
    final s = DateTime.now().difference(at).inSeconds;
    if (s < 5) return 'updated just now';
    if (s < 60) return 'updated ${s}s ago';
    if (s < 3600) return 'updated ${(s / 60).floor()}m ago';
    return 'updated ${(s / 3600).floor()}h ago';
  }

  /// The analysis service, or null in an offline build.
  ///
  /// Like the live snapshot, this resolves in a live build and is absent
  /// offline. A missing service must not be treated as "no analysis": the
  /// card renders its own honest waiting state instead.
  static AnalysisService? _analysisOf(BuildContext context) {
    try {
      return context.watch<AnalysisService>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final live = _liveOf(context);
    final analysis = _analysisOf(context);
    // Offline build: the demo switcher drives the scenario. Live build: the
    // pipeline supplies the state, so its own signal is the only verdict there
    // can be — null is a real answer (NO CONSENSUS), never a fixture.
    final signal = live != null
        ? live.signal
        : state.scenario == RadarScenario.developing
        ? MockFixtures.developing
        : quote;
    final caution = _caution(live, state.scenario);
    final macroStrip = _macroStrip(live, context);

    // A published setup cannot be acted on while the market is shut, so it is
    // not offered. The levels stay in the database and reappear when the
    // session opens; showing them over a closed market invites a trader to act
    // on a price that will not move.
    final sessionOpen = _sessionOpenAt(DateTime.now());
    return ListView(
      key: const PageStorageKey<String>('radar'),
      padding: EdgeInsets.zero,
      children: [
        HarborHeader(sessionOpen: sessionOpen),
        if (live != null && live.error != null) _ErrorLine(live.error!),
        if (live != null && live.price == null && live.loading)
          // First read in flight: hold the layout with a skeleton instead of
          // flashing "WAITING FOR FIRST TICK", which reads as an error.
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 130, height: 9),
                SizedBox(height: 10),
                SkeletonBox(width: 190, height: 30, radius: 8),
                SizedBox(height: 10),
                SkeletonBox(width: 220, height: 11),
              ],
            ),
          )
        else if (live != null)
          _LiveQuoteHero(live: live)
        else
          const SpotPriceBlock(signal: quote),
        if (live != null) _LiveDayBar(live: live) else const DayMoveBar(signal: quote),
        TimeframeSwitch(
          active: _timeframe,
          onChanged: (tf) => setState(() => _timeframe = tf),
        ),
        if (!sessionOpen)
          const _MarketClosedCard()
        else if (live != null)
          signal == null
              ? const _NoConsensusCard(live: true)
              : _verdictCard(
                  context,
                  signal,
                  updatedLabel: _agoLabel(live.lastUpdated),
                  chips: const [],
                  independence: live.independence,
                )
        else
          switch (state.scenario) {
            RadarScenario.strong => _verdictCard(context, signal!),
            RadarScenario.developing => _verdictCard(
              context,
              signal!,
              stateLabel: statusLabel(signal.status),
            ),
            RadarScenario.noConsensus => const _NoConsensusCard(),
            RadarScenario.blackout => EventGuardrailBar(
              event: MockFixtures.upcomingEvents.first,
              onTap: () => context.read<AppState>().setTab(eventsTab),
            ),
          },
        ScenarioStrip(pills: _scenarioPills(signal, live)),
        // Multi-timeframe analysis: the expert methodology's own verdict,
        // shown separately from consensus because it answers a different
        // question. Consensus asks what independent sources agree on; this
        // asks whether the technicals, gates and vetoes permit a setup at all.
        AnalysisVerdictCard(scan: analysis?.result, onRefresh: analysis?.refresh),
        // The switcher demos states the live pipeline owns, so it must not
        // appear next to real rows.
        if (mockMode && live == null) const DemoStateRow(),
        // Event context line (annotation only — never votes, rule 9).
        ?caution,
        // Macro backdrop strip (latest digest, display only → Events tab).
        ?macroStrip,
        const SizedBox(height: 18),
      ],
    );
  }

  /// The macro backdrop strip, or null when there is nothing to say (a live
  /// build whose digest has not run) — an empty ink bar would read as a broken
  /// strip rather than as silence.
  Widget? _macroStrip(LiveData? live, BuildContext context) {
    final themes = live != null ? live.digest : MockFixtures.digestThemes;
    if (themes.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: MacroBackdropStrip(
        themes: themes,
        onTap: () => context.read<AppState>().setTab(eventsTab),
      ),
    );
  }

  /// Event context line. Offline it is the fixture-pinned retail-sales note;
  /// live it names the next real scheduled USD release, and nothing at all when
  /// the calendar has no HIGH/MED entry. Context only — it never votes and it
  /// never creates, suppresses or flips a setup (rule 9).
  Widget? _caution(LiveData? live, RadarScenario scenario) {
    String? text;
    if (live != null) {
      for (final event in live.events) {
        if (event.currency != 'USD') continue;
        if (event.impact == EventImpact.low) continue;
        text = 'Caution: ${event.title} in ${formatCountdown(event.startsIn)}';
        break;
      }
    } else if (scenario == RadarScenario.strong || scenario == RadarScenario.developing) {
      text = 'Caution: Retail Sales in 42m';
    }
    if (text == null) return null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(HarborIcons.bell, size: 10, color: harborWarn),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                color: harborDim,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Context pills below the card: the direction that lost, the invalidation
  /// level, and the 5M confirmation state (rule 1: 5M confirms, never votes).
  ///
  /// Offline the figures are fixture-pinned. Live the snapshot reports neither
  /// a per-direction vote count nor the 5M confirmation, so both print `—`
  /// rather than borrow a fixture (product rule 2).
  List<({String label, String value})> _scenarioPills(
    DisplaySignal? signal,
    LiveData? live,
  ) {
    return [
      (
        label: 'Alternate',
        value: live != null
            ? 'SHORT —'
            : 'SHORT ${MockFixtures.dividedVotes[Direction.short] ?? 0}/'
                  '${signal?.totalCount ?? 0}',
      ),
      (label: 'Watch', value: signal == null ? '—' : formatLevel(signal.stopLoss)),
      (label: '5M', value: live != null ? '—' : 'CONFIRMING'),
    ];
  }

  /// Full verdict card (mockup `.verdict`) for [signal].
  ///
  /// [updatedLabel] and [chips] are the two live-supplied rows: offline the
  /// literal fixture wording and the fixture source list are used, live the
  /// poller's own age label and no per-source chips (the snapshot carries the
  /// agreeing count, not the contributing rows).
  Widget _verdictCard(
    BuildContext context,
    DisplaySignal signal, {
    String? stateLabel,
    String? updatedLabel,
    List<DisplaySource>? chips,
    IndependenceResult? independence,
  }) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: VerdictCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DirectionPill(direction: signal.direction),
                const Spacer(),
                Text(
                  updatedLabel ?? 'updated 40s ago',
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 9,
                    color: harborFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (stateLabel != null) ...[
                        HarborEyebrow(stateLabel, color: harborWarn),
                        const SizedBox(height: 4),
                      ],
                      const Text(
                        '15M Consensus Setup',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ],
                  ),
                ),
                ConsensusMeter(signal: signal),
              ],
            ),
            const SizedBox(height: 14),
            _levelGrid(signal, state.targets),
            const SizedBox(height: 9),
            const TargetScopePills(),
            _agreeRow(signal, state.targets, independence: independence, chips: chips),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: HarborActionButton(
                    label: 'COPY LEVELS',
                    onTap: () =>
                        _publish(context, signal, state.targets, 'Levels copied'),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: HarborActionButton(
                    label: '↗ SHARE',
                    primary: false,
                    onTap: () => _publish(
                      context,
                      signal,
                      state.targets,
                      'Setup text copied — paste to share',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _levelGrid(DisplaySignal signal, TargetSelection selection) {
    final tps = {1: signal.tp1, 2: signal.tp2, 3: signal.tp3};
    final cells = <Widget>[
      VerdictLevelCell(
        label: 'Stop',
        value: formatLevel(signal.stopLoss),
        sub: levelDistance(signal.entryMid, signal.stopLoss),
      ),
    ];
    for (final n in visibleTps(selection)) {
      final tp = tps[n];
      if (tp == null) continue;
      cells.add(
        VerdictLevelCell(
          label: 'TP$n',
          value: formatLevel(tp),
          sub: levelDistance(signal.entryMid, tp),
        ),
      );
    }
    return VerdictLevelGrid(
      entry: VerdictLevelCell(
        label: 'Entry',
        value:
            '${formatLevel(signal.entryLow)}-'
            '${formatLevel(signal.entryHigh)}',
        sub: 'market zone',
        highlighted: true,
      ),
      cells: cells,
    );
  }

  Widget _agreeRow(
    DisplaySignal signal,
    TargetSelection selection, {
    IndependenceResult? independence,
    List<DisplaySource>? chips,
  }) {
    final sources = chips ?? MockFixtures.sources.take(signal.totalCount);
    return Container(
      margin: const EdgeInsets.only(top: 13),
      padding: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                IndependenceLine(
                  result: independence,
                  fallbackAgree: signal.agreeCount,
                  fallbackTotal: signal.totalCount,
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final source in sources)
                      SourceChip(label: 'Source ${source.id}', agrees: source.agrees),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'R:R',
                style: TextStyle(fontFamily: 'Sora', fontSize: 9, color: harborDim),
              ),
              const SizedBox(width: 4),
              Text(
                bestRrValue(signal, selection),
                style: const TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: harborDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Copy/share the setup. The MVP has no platform share channel (no extra
  /// packages), so both paths hand the summary to the clipboard and confirm
  /// with the same toast the Signal screen's copy action uses. The toast is
  /// raised synchronously so the feedback never waits on the clipboard.
  void _publish(
    BuildContext context,
    DisplaySignal signal,
    TargetSelection selection,
    String toast,
  ) {
    unawaited(Clipboard.setData(ClipboardData(text: _summary(signal, selection))));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
  }

  String _summary(DisplaySignal signal, TargetSelection selection) {
    final direction = signal.direction == Direction.short ? 'SHORT' : 'LONG';
    final lines = <String>[
      'XAUUSD 15M $direction — ${bandLabel(signal.band)} '
          '${signal.agreeCount}/${signal.totalCount}',
      'Entry ${formatLevel(signal.entryLow)}-${formatLevel(signal.entryHigh)}'
          ' (market zone)',
      'Stop ${formatLevel(signal.stopLoss)} '
          '(${levelDistance(signal.entryMid, signal.stopLoss)})',
    ];
    final tps = {1: signal.tp1, 2: signal.tp2, 3: signal.tp3};
    for (final n in visibleTps(selection)) {
      final tp = tps[n];
      if (tp == null) continue;
      lines.add('TP$n ${formatLevel(tp)} (${levelDistance(signal.entryMid, tp)})');
    }
    lines.add('R:R ${bestRrValue(signal, selection)}');
    return lines.join('\n');
  }
}

/// Live spot hero: the real quote, or the honest "no tick yet" state.
///
/// Deliberately not [SpotPriceBlock]: that widget prints the day's move and a
/// percentage derived from it, and the live feed publishes neither — handing it
/// the model's defaults would put `+12.40` and `+0.29%` in front of a live
/// trader. Everything else (eyebrow, mono hero, gutter, wrap meta) is the same
/// Harbor language, and the day move is simply absent rather than derived.
class _LiveQuoteHero extends StatelessWidget {
  const _LiveQuoteHero({required this.live});

  final LiveData live;

  @override
  Widget build(BuildContext context) {
    final price = live.price;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('XAUUSD · Spot Gold'),
          const SizedBox(height: 3),
          if (price == null)
            // No snapshot stored yet. Saying so beats printing the offline
            // figure (product rule 2).
            const Text(
              'WAITING FOR FIRST TICK',
              style: TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: harborDim,
              ),
            )
          else
            Text(
              formatPrice(price),
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 32,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -1.5,
              ),
            ),
          const SizedBox(height: 8),
          Text(
            price == null
                ? 'No market snapshot stored yet — the first tick appears here.'
                : 'Latest stored snapshot for XAUUSD.',
            style: const TextStyle(fontFamily: 'Sora', fontSize: 11, color: harborFaint),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(
                  text: 'Updated ',
                  style: TextStyle(fontFamily: 'Sora', fontSize: 10, color: harborDim),
                ),
                TextSpan(
                  text: clockLabel(),
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: harborInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Live day bar: the session range the pipeline actually observed.
///
/// The day move prints `—` because the feed publishes no session open. Deriving
/// one from the range (or carrying the offline literal) would put a number on
/// screen that no observation supports (product rule 2). Mirrors [DayMoveBar]:
/// ink surface, 16px radius, eyebrow label over a Space Mono value.
class _LiveDayBar extends StatelessWidget {
  const _LiveDayBar({required this.live});

  final LiveData live;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: harborInk,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Expanded(child: _cell('Day Move', '—')),
            _cell('Range', _range),
          ],
        ),
      ),
    );
  }

  /// `4,266.90 — 4,286.40`, or an honest `—` until the pipeline has observed
  /// enough snapshots to bound the session.
  String get _range {
    final low = live.sessionLow;
    final high = live.sessionHigh;
    if (low == null || high == null) return '—';
    return '${formatPrice(low)} — ${formatPrice(high)}';
  }

  Widget _cell(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        HarborEyebrow(label, color: inkMuted),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          style: const TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Poll failure, as one quiet line under the header.
///
/// Never replaces the screen: a failed poll keeps the last good values on top
/// (see [LiveData.refresh]), and the trader still sees how fresh they are.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
      child: Row(
        children: [
          const Icon(HarborIcons.cross, size: 9, color: harborDim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Feed degraded · $message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 9,
                color: harborDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// NO CONSENSUS state (spec §3). Never fabricates a signal.
///
/// Offline it also prints the per-direction vote split the mock pipeline
/// reported. Live the snapshot carries no vote counts at all, so those rows are
/// dropped rather than filled from [MockFixtures.dividedVotes] — "sources have
/// not agreed" is the honest statement, the counts are the invented part.
/// Shown in place of a setup when the spot market is closed.
///
/// This is deliberately a *withheld* state, not "no trade": a setup may well
/// exist, it just cannot be entered because nothing will move. Saying "no trade"
/// would misdescribe the situation and could read as a verdict on the
/// analysis; the honest answer is that the market is not trading.
class _MarketClosedCard extends StatelessWidget {
  const _MarketClosedCard();

  @override
  Widget build(BuildContext context) {
    final reopens = nextOpenUtc(DateTime.now().toUtc());
    final wait = reopens?.difference(DateTime.now().toUtc());
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: VerdictCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HarborEyebrow('Market status', color: harborWarn),
            const SizedBox(height: 6),
            const Text(
              'MARKET CLOSED',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Gold spot is closed for the weekend. Levels are withheld until '
              'the session reopens — a setup here could not be entered.',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                height: 1.45,
                color: harborDim,
              ),
            ),
            if (wait != null && !wait.isNegative) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const HarborEyebrow('Reopens in', color: harborFaint),
                  const SizedBox(width: 9),
                  Text(
                    formatCountdown(wait),
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: harborWarn,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoConsensusCard extends StatelessWidget {
  const _NoConsensusCard({this.live = false});

  /// True in a live build: drop the vote split and the "divided" wording,
  /// because without counts the app cannot know *how* the room is split.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final votes = live ? const <Direction, int>{} : MockFixtures.dividedVotes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: VerdictCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HarborEyebrow(live ? 'No vote' : 'Vote split'),
            const SizedBox(height: 6),
            const Text(
              'NO CONSENSUS',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              live
                  ? 'Sources have not reached agreement.'
                  : 'Sources are currently divided.',
              style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
            ),
            const SizedBox(height: 14),
            for (final entry in const [
              (Direction.long, 'LONG'),
              (Direction.short, 'SHORT'),
              (Direction.neutral, 'NEUTRAL'),
            ])
              if (!live) _voteRow(entry.$2, votes[entry.$1] ?? 0),
            const SizedBox(height: 14),
            const Text(
              'Waiting for stronger agreement.',
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voteRow(String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: divider)),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: harborDim,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 15,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }
}
