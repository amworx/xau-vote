/// Screen 5 — Settings (spec §24 controls).
///
/// Fixed timeframe display (15M/5M/1H), target selection, and notification
/// toggles. Persisted in-memory via [AppState] for the MVP; Supabase user
/// preferences arrive with live wiring (T5.7).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      key: const PageStorageKey<String>('settings'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const HarborHeader(subtitle: 'CONFIG'),
        const SizedBox(height: 12),
        const KickLabel('CONTROL PANEL'),
        const SizedBox(height: 12),
        _Group(
          title: 'TIMEFRAMES',
          children: const [
            _StaticRow(
              title: 'Signal / Confirm / Context',
              subtitle: 'Fixed by product spec',
              value: '15M / 5M / 1H',
            ),
            _StaticRow(
              title: 'Default view',
              subtitle: 'Screen shown on launch',
              value: 'RADAR',
            ),
          ],
        ),
        _Group(
          title: 'TARGETS',
          children: [
            RadioGroup<TargetSelection>(
              groupValue: state.targets,
              onChanged: (value) {
                if (value != null) state.setTargets(value);
              },
              child: Column(
                children: [
                  _TargetOption(
                    label: 'TP1 + TP2 + TP3',
                    value: TargetSelection.all,
                    onSelect: state.setTargets,
                  ),
                  _TargetOption(
                    label: 'TP1 + TP2',
                    value: TargetSelection.tp1Tp2,
                    onSelect: state.setTargets,
                  ),
                  _TargetOption(
                    label: 'TP1 ONLY',
                    value: TargetSelection.tp1Only,
                    onSelect: state.setTargets,
                  ),
                ],
              ),
            ),
          ],
        ),
        _Group(
          title: 'NOTIFICATIONS · SIGNALS',
          children: [
            _ToggleRow(
              title: 'Consensus forming',
              subtitle: 'Developing to ready transitions',
              value: state.notifyConsensus,
              onChanged: state.setNotifyConsensus,
            ),
            _ToggleRow(
              title: 'Entry approaching',
              subtitle: 'Price enters the zone',
              value: state.notifyEntry,
              onChanged: state.setNotifyEntry,
            ),
            _ToggleRow(
              title: 'Confirmation',
              subtitle: '5M confirms the setup',
              value: state.notifyConfirmation,
              onChanged: state.setNotifyConfirmation,
            ),
            const _ToggleRow(
              title: 'Invalidation',
              subtitle: 'Setup fails, always on',
              value: true,
              onChanged: null,
            ),
            _ToggleRow(
              title: 'Targets hit',
              subtitle: 'TP1 / TP2 / TP3',
              value: state.notifyTargets,
              onChanged: state.setNotifyTargets,
            ),
          ],
        ),
        _Group(
          title: 'EVENTS · CONTEXT ONLY',
          children: [
            _StaticRow(
              title: 'Blackout before HIGH event',
              subtitle: 'No new signals in this window',
              value: '${state.blackoutBeforeMin} min',
            ),
            _StaticRow(
              title: 'Blackout after HIGH event',
              subtitle: 'Resume scan after release',
              value: '${state.blackoutAfterMin} min',
            ),
            _ToggleRow(
              title: '60-min warning',
              subtitle: 'HIGH event approaching',
              value: state.notifyEvent60,
              onChanged: state.setNotifyEvent60,
            ),
            _ToggleRow(
              title: '15-min warning',
              subtitle: 'Blackout about to start',
              value: state.notifyEvent15,
              onChanged: state.setNotifyEvent15,
            ),
            _ToggleRow(
              title: 'Surprises',
              subtitle: 'Actual vs forecast gaps',
              value: state.notifySurprises,
              onChanged: state.setNotifySurprises,
            ),
            _ToggleRow(
              title: 'News spikes',
              subtitle: 'Unusual gold-news volume',
              value: state.notifyNewsSpikes,
              onChanged: state.setNotifyNewsSpikes,
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Pip x0.01 · per D-003 · v0.1 MVP',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              letterSpacing: 0.6,
              color: harborFaint,
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Font/icon license attribution (required, display only).
        const Center(
          child: Text(
            'UIcons by Flaticon',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              letterSpacing: 0.6,
              color: harborFaint,
            ),
          ),
        ),
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: harborLine)),
            ),
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: harborCobalt,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _StaticRow extends StatelessWidget {
  const _StaticRow({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  final String title;
  final String subtitle;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 10,
                    color: harborFaint,
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TargetOption extends StatelessWidget {
  const _TargetOption({
    required this.label,
    required this.value,
    required this.onSelect,
  });

  final String label;
  final TargetSelection value;
  final ValueChanged<TargetSelection> onSelect;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onSelect(value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Radio<TargetSelection>(value: value),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 10,
                    color: harborFaint,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: harborLong,
            inactiveTrackColor: harborLine,
          ),
        ],
      ),
    );
  }
}
