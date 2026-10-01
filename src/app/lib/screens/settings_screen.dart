/// Screen 5 — Settings (spec §24 controls).
///
/// Fixed timeframe display (15M/5M/1H), pip convention, target selection and
/// notification toggles. Persisted in-memory via [AppState] for the MVP;
/// Supabase user preferences arrive with live wiring (T5.7).
///
/// Restyled onto the unified Harbor language: [HarborEyebrow] group headings
/// on a [HarborCard] container, [HarborDivider] between rows, Sora titles and
/// subtitles, Space Mono values, and [HarborPill] for every selector. A toggle
/// track reads [harborLine] off and [harborLong] on, because every switch here
/// gates participation or alerting — never a direction — and the thumb is a
/// constant white so only the track carries the state.
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
      // Horizontal gutters belong to the shared chrome (header 18px, cards
      // 18px), so the list itself only owns the trailing space.
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        // Matches the bottom-nav label: one name for the tab, whatever is on
        // screen (D-20260929-004).
        const HarborHeader(subtitle: 'SETTINGS'),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
          child: HarborEyebrow('Control panel'),
        ),
        const SizedBox(height: 12),
        const _Group(
          title: 'Timeframes',
          children: [
            _SettingRow(
              title: 'Signal / Confirm / Context',
              subtitle: 'Fixed by product spec',
              value: '15M / 5M / 1H',
            ),
            _SettingRow(
              title: 'Default view',
              subtitle: 'Screen shown on launch',
              value: 'RADAR',
            ),
          ],
        ),
        const _Group(
          title: 'Targets',
          children: [_TargetPills()],
        ),
        const _Group(
          title: 'Display',
          children: [_PipConventionPills()],
        ),
        _Group(
          title: 'Notifications · signals',
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
          title: 'Events · context only',
          children: [
            _SettingRow(
              title: 'Blackout before HIGH event',
              subtitle: 'No new signals in this window',
              value: '${state.blackoutBeforeMin} min',
            ),
            _SettingRow(
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
        const SizedBox(height: 4),
        // Display-only micro-copy. The pip convention note, the icon
        // attribution and the not-financial-advice line are all required:
        // the UIcons licence demands attribution and the app must not read as
        // a recommendation. The pip figure follows the selected convention.
        _Micro(text: 'Pip x${state.pipConvention.pipSizeLabel} · per D-003 · v0.1 MVP'),
        const _Micro(text: 'UIcons by Flaticon'),
        const _Micro(text: 'Not financial advice · never executes trades'),
      ],
    );
  }
}

/// Card container for one settings group: an [HarborEyebrow] heading and
/// hairline-separated rows (mockup `.group` / `.srow`).
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: HarborCard(
        margin: 0,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
              child: HarborEyebrow(title, color: harborCobalt),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const HarborDivider(),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only row: Sora title, Sora dim subtitle, Space Mono value.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(child: _RowLabels(title, subtitle)),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Title + subtitle block shared by the read-only and toggle rows.
class _RowLabels extends StatelessWidget {
  const _RowLabels(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: harborInk,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 10.5,
            color: harborDim,
          ),
        ),
      ],
    );
  }
}

/// Target-scope selector (spec §10). [HarborPill] is the same control the
/// Radar card and the Signal screen use, so one selection is mirrored on all
/// three: it writes straight to [AppState.targets] and narrows the visible
/// targets everywhere it is read.
class _TargetPills extends StatelessWidget {
  const _TargetPills();

  static const _options = [
    (label: 'TP1 + TP2 + TP3', value: TargetSelection.all),
    (label: 'TP1 + TP2', value: TargetSelection.tp1Tp2),
    (label: 'TP1 ONLY', value: TargetSelection.tp1Only),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final option in _options)
            HarborPill(
              option.label,
              fontSize: 10,
              active: state.targets == option.value,
              onTap: () => state.setTargets(option.value),
            ),
        ],
      ),
    );
  }
}

/// Pip-size selector (D-20260927-003), in its own DISPLAY group.
///
/// Same [HarborPill] language as every other selector in the app, active
/// cobalt. The labels state the convention itself (`A · 0.10` / `B · 0.01`)
/// because "pip size" alone is ambiguous, and the subtitle promises the one
/// thing the setting may do: rescale pip readouts, never a price, a level or
/// an R:R. Convention B is the default (the user trades FXPro/Vantage).
class _PipConventionPills extends StatelessWidget {
  const _PipConventionPills();

  static const _options = [
    (value: PipConvention.a, label: 'A · 0.10'),
    (value: PipConvention.b, label: 'B · 0.01'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const _RowLabels(
            'Pip size',
            'Display unit only · prices and levels never change',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final option in _options)
                HarborPill(
                  option.label,
                  fontSize: 10,
                  active: state.pipConvention == option.value,
                  onTap: () => state.setPipConvention(option.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Toggle row. Off track is [harborLine], on track [harborLong]: every switch
/// on this screen gates participation or alerting, never a trade direction.
/// A `null` [onChanged] is a safety-critical always-on alert, so it is drawn
/// in the same tokens at reduced weight rather than a Material grey.
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
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Expanded(child: _RowLabels(title, subtitle)),
          const SizedBox(width: 10),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: harborLong,
            inactiveTrackColor: harborLine,
            // The always-on invalidation alert is still a Harbor surface, so it
            // dims through the same tokens instead of a Material grey — but it
            // dims as a GREEN track, not a pale one. It is a safety-critical
            // alert that is permanently on, so it must never render in the
            // OFF palette just because it cannot be tapped.
            trackColor: WidgetStateProperty.resolveWith<Color?>(
              (states) {
                if (!states.contains(WidgetState.disabled)) return null;
                return states.contains(WidgetState.selected)
                    ? harborLong.withValues(alpha: 0.45)
                    : harborLine;
              },
            ),
            // The thumb is CONSTANT (white) in both states, so the track alone
            // carries on/off. An OFF thumb in a tinted neutral ([harborFaint]
            // #8FA0B8) painted a blue-grey disc on the [harborLine] track that
            // read as "partially on". White recedes against the pale track and
            // cannot be mistaken for the ON state, which stays unmistakably
            // [harborLong] — the one place green means an active switch.
            thumbColor: const WidgetStatePropertyAll<Color?>(Colors.white),
          ),
        ],
      ),
    );
  }
}

/// Centred mono micro-copy (mockup `.micro`).
class _Micro extends StatelessWidget {
  const _Micro({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            letterSpacing: 0.6,
            color: harborFaint,
          ),
        ),
      ),
    );
  }
}
