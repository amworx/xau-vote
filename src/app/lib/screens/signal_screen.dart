/// Screen 2 — Signal: full setup detail.
///
/// Levels, per-TP R:R, lifecycle timeline, 1H context badge, 5M
/// confirmation state, TP selection (spec §10). Strength is an agreement
/// label only — never rendered as a forecast (spec §7).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mock_fixtures.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class SignalScreen extends StatelessWidget {
  const SignalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final signal = state.scenario == RadarScenario.noConsensus
        ? MockFixtures.developing
        : state.scenario == RadarScenario.developing
            ? MockFixtures.developing
            : MockFixtures.strongLong;
    final show = visibleTps(state.targets);
    return ListView(
      key: const PageStorageKey<String>('signal'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        HarborHeader(
          subtitle: 'SIGNAL · ${signal.id}',
          statusText: statusLabel(signal.status),
        ),
        const SizedBox(height: 12),
        const KickLabel('ACTIVE SETUP · 15M LONG'),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            DirectionMark(direction: signal.direction, size: 27),
            const SizedBox(width: 10),
            Text(
              '${formatPrice(signal.price)} · ${bandLabel(signal.band)} ${signal.strength}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: harborDim,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _lifecycleCard(signal),
        const SizedBox(height: 12),
        _levelGrid(signal, show),
        const SizedBox(height: 10),
        Row(
          children: const [
            Expanded(
              child: _ContextBadge(
                title: '1H TREND',
                value: 'SUPPORTIVE',
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _ContextBadge(
                title: '5M CONFIRM',
                value: 'CONFIRMED',
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _ContextBadge(
                title: 'POSITION',
                value: '+30 PIPS',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const TargetSelector(),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: harborLongSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'POSITION STATUS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: harborLong,
                ),
              ),
              Text(
                '● IN-PROFIT +30 PIPS',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: harborLong,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Signal text copied')),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: harborCobalt,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text('COPY SIGNAL TEXT'),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Opened 21:44:03 · expires 22:44',
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

  /// Lifecycle timeline through ACTIVE (spec §14), timestamps mocked.
  Widget _lifecycleCard(DisplaySignal signal) {
    const steps = [
      ('DEVELOPING', '21:31', DisplayStatus.developing),
      ('READY', '21:36', DisplayStatus.ready),
      ('CONFIRMED · 5M', '21:41', DisplayStatus.confirmed),
      ('ACTIVE', 'SINCE 21:44', DisplayStatus.active),
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            Container(
              decoration: BoxDecoration(
                color: i == steps.length - 1
                    ? harborCobalt.withValues(alpha: 0.05)
                    : null,
                border: i > 0
                    ? const Border(top: BorderSide(color: harborLine))
                    : null,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i == steps.length - 1
                          ? harborCobalt
                          : harborLong,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    steps[i].$1,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 0.8,
                      fontWeight: i == steps.length - 1
                          ? FontWeight.w700
                          : FontWeight.w400,
                      color: i == steps.length - 1 ? harborInk : harborDim,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    steps[i].$2,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: i == steps.length - 1 ? harborCobalt : harborFaint,
                    ),
                  ),
                ],
              ),
            ),
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: harborLine),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    border: Border.all(color: harborLine, width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'TP1 ${signal.tp1 == null ? '—' : formatLevel(signal.tp1!)}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 0.8,
                    color: harborFaint,
                  ),
                ),
                const Spacer(),
                Text(
                  '+${pipsTo(signal.tp1 ?? signal.entryMid, signal.entryMid)} PIPS',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: harborFaint,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelGrid(DisplaySignal signal, List<int> show) {
    final tps = {1: signal.tp1, 2: signal.tp2, 3: signal.tp3};
    final cells = <Widget>[
      LevelCell(
        icon: Icons.my_location,
        title: 'ENTRY ZONE',
        value:
            '${formatLevel(signal.entryLow)}-${formatLevel(signal.entryHigh)}',
        subtitle:
            '${((signal.entryHigh - signal.entryLow) * 100).round()}-pip zone',
        valueColor: harborCobalt,
      ),
      LevelCell(
        icon: Icons.shield_outlined,
        title: 'STOP LOSS',
        value: formatLevel(signal.stopLoss),
        subtitle:
            '-${pipsTo(signal.entryMid, signal.stopLoss).abs()} pips · risk ${(signal.entryMid - signal.stopLoss).toStringAsFixed(1)} pts',
        valueColor: harborShort,
      ),
    ];
    for (final n in show) {
      final tp = tps[n];
      if (tp == null) continue;
      final rr = riskReward(
        target: tp,
        entryLow: signal.entryLow,
        stopLoss: signal.stopLoss,
      );
      cells.add(
        LevelCell(
          icon: Icons.flag_outlined,
          title: 'TP$n',
          value: formatLevel(tp),
          subtitle:
              '+${pipsTo(tp, signal.entryMid)} · 1:${rr.toStringAsFixed(1)}',
          valueColor: harborLong,
        ),
      );
    }
    return LevelGrid(cells: cells);
  }
}

class _ContextBadge extends StatelessWidget {
  const _ContextBadge({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: harborFaint,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: harborLong,
            ),
          ),
        ],
      ),
    );
  }
}
