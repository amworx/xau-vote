/// Screen 1 — Radar (mockup `.top` … `.scenario`, exact layout).
///
/// Price block, day bar, timeframe display, the verdict card (LONG/SHORT
/// direction, agreement strength, entry/stop/TP levels, target scope,
/// source agreement, copy/share), plus the NO CONSENSUS, DEVELOPING and
/// event-guardrail states. A MOCK_MODE-only demo switcher sits under the
/// scenario strip so every required state stays reviewable.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/mock_fixtures.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  /// Bottom-nav index of the Events screen.
  static const int eventsTab = 4;

  /// Market snapshot (price, day move, spread, session). Scenario switching
  /// changes the signal, never the quote, so this is always the live one.
  static const DisplaySignal quote = MockFixtures.strongLong;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final consensus = state.scenario == RadarScenario.developing
        ? MockFixtures.developing
        : quote;
    return ListView(
      key: const PageStorageKey<String>('radar'),
      padding: EdgeInsets.zero,
      children: [
        const HarborHeader(),
        const SpotPriceBlock(signal: quote),
        const DayMoveBar(signal: quote),
        const TimeframeSwitch(),
        switch (state.scenario) {
          RadarScenario.strong => _verdictCard(context, consensus),
          RadarScenario.developing => _verdictCard(
              context,
              consensus,
              stateLabel: statusLabel(consensus.status),
            ),
          RadarScenario.noConsensus => const _NoConsensusCard(),
          RadarScenario.blackout => EventGuardrailBar(
              event: MockFixtures.upcomingEvents.first,
              onTap: () => context.read<AppState>().setTab(eventsTab),
            ),
        },
        ScenarioStrip(pills: _scenarioPills(consensus)),
        if (mockMode) const DemoStateRow(),
        // MEDIUM-event context line (badge only — never votes, rule 9).
        if (state.scenario == RadarScenario.strong ||
            state.scenario == RadarScenario.developing)
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(HarborIcons.bell, size: 10, color: harborWarn),
                SizedBox(width: 5),
                Flexible(
                  child: Text(
                    'Caution: Retail Sales in 42m',
                    style: TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 10,
                      color: harborDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Macro backdrop strip (latest digest, display only → Events tab).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: MacroBackdropStrip(
            themes: MockFixtures.digestThemes,
            onTap: () => context.read<AppState>().setTab(eventsTab),
          ),
        ),
        const SizedBox(height: 18),
      ],
    );
  }

  /// Context pills below the card: the direction that lost, the invalidation
  /// level, and the 5M confirmation state (rule 1: 5M confirms, never votes).
  List<({String label, String value})> _scenarioPills(DisplaySignal signal) {
    final alternate = MockFixtures.dividedVotes[Direction.short] ?? 0;
    return [
      (
        label: 'Alternate',
        value: 'SHORT $alternate/${signal.totalCount}',
      ),
      (label: 'Watch', value: formatLevel(signal.stopLoss)),
      const (label: '5M', value: 'CONFIRMING'),
    ];
  }

  /// Full verdict card (mockup `.verdict`) for [signal].
  Widget _verdictCard(
    BuildContext context,
    DisplaySignal signal, {
    String? stateLabel,
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
                const Text(
                  'updated 40s ago',
                  style: TextStyle(
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
            _agreeRow(signal, state.targets),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: HarborActionButton(
                    label: 'COPY LEVELS',
                    onTap: () => _publish(
                      context,
                      signal,
                      state.targets,
                      'Levels copied',
                    ),
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
                      'Setup text copied \u2014 paste to share',
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
        value: '${formatLevel(signal.entryLow)}-'
            '${formatLevel(signal.entryHigh)}',
        sub: 'market zone',
        highlighted: true,
      ),
      cells: cells,
    );
  }

  Widget _agreeRow(DisplaySignal signal, TargetSelection selection) {
    final sources = MockFixtures.sources.take(signal.totalCount);
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
                Text(
                  '${signal.agreeCount} of ${signal.totalCount} sources agree',
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    color: harborInk,
                  ),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final source in sources)
                      SourceChip(
                        label: 'Source ${source.id}',
                        agrees: source.agrees,
                      ),
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
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 9,
                  color: harborDim,
                ),
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
    unawaited(
      Clipboard.setData(ClipboardData(text: _summary(signal, selection))),
    );
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(toast)));
  }

  String _summary(DisplaySignal signal, TargetSelection selection) {
    final direction = signal.direction == Direction.short ? 'SHORT' : 'LONG';
    final lines = <String>[
      'XAUUSD 15M $direction \u2014 ${bandLabel(signal.band)} '
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
      lines.add(
        'TP$n ${formatLevel(tp)} (${levelDistance(signal.entryMid, tp)})',
      );
    }
    lines.add('R:R ${bestRrValue(signal, selection)}');
    return lines.join('\n');
  }
}

/// NO CONSENSUS divided state (spec §3). Never fabricates a signal.
class _NoConsensusCard extends StatelessWidget {
  const _NoConsensusCard();

  @override
  Widget build(BuildContext context) {
    final votes = MockFixtures.dividedVotes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: VerdictCardShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HarborEyebrow('Vote split'),
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
            const Text(
              'Sources are currently divided.',
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
            ),
            const SizedBox(height: 14),
            for (final entry in const [
              (Direction.long, 'LONG'),
              (Direction.short, 'SHORT'),
              (Direction.neutral, 'NEUTRAL'),
            ]) ...[
              _voteRow(entry.$2, votes[entry.$1] ?? 0),
            ],
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
