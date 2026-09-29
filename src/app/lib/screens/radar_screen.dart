/// Screen 1 — Radar (spec §3, exact layout).
///
/// Strong-consensus card (direction, agreement label, entry/SL/TP1–3,
/// R:R, "N / M sources agree", VIEW ANALYSIS → Signal tab) plus the
/// NO CONSENSUS divided state and a MOCK_MODE scenario preview switch.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mock_fixtures.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      key: const PageStorageKey<String>('radar'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const HarborHeader(subtitle: 'GOLD · XAUUSD · 15M'),
        const SizedBox(height: 12),
        _priceHero(MockFixtures.strongLong),
        const SizedBox(height: 10),
        _scenarioPreview(context, state),
        const SizedBox(height: 10),
        switch (state.scenario) {
          RadarScenario.strong => _consensusBody(context, MockFixtures.strongLong),
          RadarScenario.developing => _consensusBody(context, MockFixtures.developing),
          RadarScenario.noConsensus => _noConsensusBody(),
          RadarScenario.blackout => _blackoutBody(context),
        },
        const SizedBox(height: 10),
        // MEDIUM-event context line (badge only — never votes, rule 9).
        if (state.scenario == RadarScenario.strong ||
            state.scenario == RadarScenario.developing)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Center(
              child: Text(
                'Caution: Retail Sales in 42m',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: harborDim,
                ),
              ),
            ),
          ),
        // Macro backdrop strip (latest digest, display only → Events tab).
        MacroBackdropStrip(
          themes: MockFixtures.digestThemes,
          onTap: () => context.read<AppState>().setTab(5),
        ),
      ],
    );
  }

  /// MOCK_MODE preview switch so every required state renders on demand.
  Widget _scenarioPreview(BuildContext context, AppState state) {
    return SegmentedButton<RadarScenario>(
      segments: const [
        ButtonSegment(value: RadarScenario.strong, label: Text('STRONG')),
        ButtonSegment(value: RadarScenario.developing, label: Text('DEVELOPING')),
        ButtonSegment(value: RadarScenario.noConsensus, label: Text('DIVIDED')),
        ButtonSegment(value: RadarScenario.blackout, label: Text('EVENT')),
      ],
      selected: {state.scenario},
      onSelectionChanged: (selected) => state.setScenario(selected.first),
      style: const ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// Asymmetric two-column price hero; day-move inverts to dark ink.
  ///
  /// Wrapped in [IntrinsicHeight]: the [Row] stretches both cards to equal
  /// height, which needs a bounded cross-axis that a [ListView] child does
  /// not provide on its own (unbounded stretch breaks sliver layout).
  Widget _priceHero(DisplaySignal signal) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 8,
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CURRENT PRICE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.6,
                      color: harborFaint,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatPrice(signal.price),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: Container(
            decoration: BoxDecoration(
              color: harborInk,
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'DAY MOVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.6,
                    color: Color(0xFF93A1B8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '+${signal.dayMove.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: harborLong,
                  ),
                ),
                Text(
                  'spread ${signal.spread.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Color(0xFF93A1B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }

  /// Full §3 consensus layout for [signal].
  Widget _consensusBody(BuildContext context, DisplaySignal signal) {
    final state = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: harborLongSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    signal.direction == Direction.long
                        ? Icons.trending_up
                        : Icons.trending_down,
                    color: harborLong,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 13),
                DirectionMark(direction: signal.direction, size: 23),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${signal.agreeCount}/${signal.totalCount} agree',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: harborDim,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${bandLabel(signal.band)} ${signal.strength}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: harborLong,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        StrengthMeter(signal: signal),
        const SizedBox(height: 10),
        const TargetSelector(),
        const SizedBox(height: 10),
        _levelGrid(context, signal, state.targets),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => context.read<AppState>().goToSignal(),
          style: FilledButton.styleFrom(
            backgroundColor: harborCobalt,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          child: const Text('VIEW ANALYSIS'),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            bestRrLine(signal, state.targets),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              letterSpacing: 1,
              color: harborDim,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            '1H supportive · 5M ready · in-profit +30 pips',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: harborFaint,
            ),
          ),
        ),
      ],
    );
  }

  Widget _levelGrid(
    BuildContext context,
    DisplaySignal signal,
    TargetSelection selection,
  ) {
    final show = visibleTps(selection);
    final entryText =
        '${formatLevel(signal.entryLow)}-${formatLevel(signal.entryHigh)}';
    final cells = <Widget>[
      LevelCell(
        icon: Icons.my_location,
        title: 'ENTRY',
        value: entryText,
        subtitle:
            '${((signal.entryHigh - signal.entryLow) * 100).round()}-pip zone',
        valueColor: harborCobalt,
      ),
      LevelCell(
        icon: Icons.shield_outlined,
        title: 'STOP',
        value: formatLevel(signal.stopLoss),
        subtitle:
            '-${pipsTo(signal.entryMid, signal.stopLoss).abs()} pips',
        valueColor: harborShort,
      ),
    ];
    final tps = {1: signal.tp1, 2: signal.tp2, 3: signal.tp3};
    for (final n in show) {
      final tp = tps[n];
      if (tp == null) continue;
      final reward = pipsTo(tp, signal.entryMid);
      final rr = riskReward(
        target: tp,
        entryLow: signal.entryLow,
        stopLoss: signal.stopLoss,
      );
      cells.add(
        LevelCell(
          icon: Icons.flag_outlined,
          title: n == 3 && show.length == 3 ? 'TP3 · FINAL' : 'TP$n',
          value: formatLevel(tp),
          subtitle: '+$reward · 1:${rr.toStringAsFixed(1)}',
          valueColor: harborLong,
        ),
      );
    }
    return LevelGrid(cells: cells);
  }

  /// Blackout banner (addendum §5.1): replaces the signal card during a
  /// HIGH-event window. Countdown here is a static mock snapshot — the live
  /// 1-second ticker lives on the Events screen ([EventCountdown]).
  Widget _blackoutBody(BuildContext context) {
    final event = MockFixtures.upcomingEvents.first;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          children: [
            const Text(
              '⚠ HIGH-IMPACT EVENT',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: harborShort,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              event.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${event.currency} · HIGH · in ${formatCountdown(event.startsIn)}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: harborDim,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'New signals paused until 15 min after release.',
              style: TextStyle(fontSize: 13, color: harborDim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => context.read<AppState>().setTab(5),
              style: FilledButton.styleFrom(
                backgroundColor: harborInk,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              child: const Text('VIEW EVENTS'),
            ),
          ],
        ),
      ),
    );
  }

  /// NO CONSENSUS divided state (spec §3). Never fabricates a signal.
  Widget _noConsensusBody() {
    final votes = MockFixtures.dividedVotes;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        child: Column(
          children: [
            const Text(
              'NO CONSENSUS',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sources are currently divided.',
              style: TextStyle(fontSize: 13, color: harborDim),
            ),
            const SizedBox(height: 16),
            _voteRow('LONG', votes[Direction.long]!),
            _voteRow('SHORT', votes[Direction.short]!),
            _voteRow('NEUTRAL', votes[Direction.neutral]!),
            const SizedBox(height: 16),
            const Text(
              'Waiting for stronger agreement.',
              style: TextStyle(fontSize: 13, color: harborDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _voteRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
