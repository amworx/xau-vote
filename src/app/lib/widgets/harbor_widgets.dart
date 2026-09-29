/// Shared Harbor building blocks used across the 6 screens.
///
/// Icons are the bundled Flaticon UIcons ([HarborIcons]); Sora is the
/// display font and Space Mono ([mono]) renders every numeral.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Brand header: cobalt mark + XAU RADAR + LIVE pill (mockup header).
class HarborHeader extends StatelessWidget {
  const HarborHeader({super.key, required this.subtitle, this.statusText});

  final String subtitle;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: harborCobalt,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            HarborIcons.chartCandlestick,
            color: Colors.white,
            size: 20,
          ),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'XAU RADAR',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                color: harborFaint,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: harborLine),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: harborLong,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                statusText ?? 'LIVE',
                style: const TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: harborLong,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small label header used above cards.
class KickLabel extends StatelessWidget {
  const KickLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Space Mono',
        fontSize: 10,
        letterSpacing: 2.2,
        color: harborFaint,
      ),
    );
  }
}

/// Agreement meter card: label + score + progress track.
///
/// Displays agreement among sources only (spec §7) — never a forecast.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({super.key, required this.signal});

  final DisplaySignal signal;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'CONSENSUS STRENGTH',
                  style: TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    letterSpacing: 2,
                    color: harborFaint,
                  ),
                ),
                Text(
                  '${signal.strength}/100',
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: signal.strength / 100,
                minHeight: 8,
                backgroundColor: const Color(0xFFDCE3EC),
                valueColor: const AlwaysStoppedAnimation<Color>(harborCobalt),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${bandLabel(signal.band)} AGREEMENT · ${signal.agreeCount}/${signal.totalCount} SOURCES',
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                letterSpacing: 0.6,
                color: harborDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One level cell (entry / stop / TP) in the 2-column grid.
class LevelCell extends StatelessWidget {
  const LevelCell({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.valueColor,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: harborFaint),
                const SizedBox(width: 7),
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2,
                    color: harborFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                color: harborFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// TP target-scope selector (spec §10), shared by Radar + Signal.
class TargetSelector extends StatelessWidget {
  const TargetSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return SegmentedButton<TargetSelection>(
      segments: const [
        ButtonSegment(value: TargetSelection.tp1Only, label: Text('TP1')),
        ButtonSegment(value: TargetSelection.tp1Tp2, label: Text('TP1 + 2')),
        ButtonSegment(
          value: TargetSelection.all,
          label: Text('TP1 + 2 + 3'),
        ),
      ],
      selected: {state.targets},
      onSelectionChanged: (selected) => state.setTargets(selected.first),
      style: const ButtonStyle(
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// Two-column level grid built from [Row]s (not a nested [GridView]:
/// shrink-wrapped scrollables inside the screen [ListView] crash the
/// semantics walk in widget tests).
class LevelGrid extends StatelessWidget {
  const LevelGrid({super.key, required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += 2) {
      final end = (i + 2).clamp(0, cells.length);
      final pair = cells.sublist(i, end);
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < pair.length; j++) ...[
              if (j > 0) const SizedBox(width: 10),
              Expanded(child: pair[j]),
            ],
            if (pair.length == 1) const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (end < cells.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }
}

/// Colored status pill for History rows.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final DisplayStatus? status;

  @override
  Widget build(BuildContext context) {
    final label = status == null ? 'NO CONSENSUS' : statusLabel(status!);
    final Color fg;
    final Color bg;
    switch (status) {
      case DisplayStatus.tp1Hit:
      case DisplayStatus.tp2Hit:
      case DisplayStatus.tp3Hit:
        fg = harborLong;
        bg = harborLongSoft;
      case DisplayStatus.invalidated:
        fg = harborShort;
        bg = harborShortSoft;
      case DisplayStatus.expired:
      case DisplayStatus.developing:
      case null:
        fg = harborDim;
        bg = const Color(0xFFE7ECF2);
      case DisplayStatus.noSetup:
      case DisplayStatus.ready:
      case DisplayStatus.confirmed:
      case DisplayStatus.active:
        fg = harborCobalt;
        bg = const Color(0xFFE3EBFF);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Space Mono',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: fg,
        ),
      ),
    );
  }
}

/// Direction arrow + label (▲ LONG / ▼ SHORT / ○ NO SIGNAL).
class DirectionMark extends StatelessWidget {
  const DirectionMark({super.key, required this.direction, this.size = 22});

  final Direction? direction;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (direction) {
      case Direction.long:
        return Text(
          '▲ LONG',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: harborLong,
          ),
        );
      case Direction.short:
        return Text(
          '▼ SHORT',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: harborShort,
          ),
        );
      case Direction.neutral:
      case null:
        return Text(
          '○ NO SIGNAL',
          style: TextStyle(
            fontFamily: 'Sora',
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: harborFaint,
          ),
        );
    }
  }
}

/// Best risk/reward line under the TP grid for the current selection.
String bestRrLine(DisplaySignal signal, TargetSelection selection) {
  String rr(double? tp) {
    if (tp == null) return '—';
    final v = riskReward(
      target: tp,
      entryLow: signal.entryLow,
      stopLoss: signal.stopLoss,
    );
    return '1 : ${v.toStringAsFixed(1)}';
  }

  switch (selection) {
    case TargetSelection.tp1Only:
      return 'TP1 ONLY · R:R ${rr(signal.tp1)}';
    case TargetSelection.tp1Tp2:
      return 'TP1 + TP2 · BEST R:R ${rr(signal.tp2)}';
    case TargetSelection.all:
      return 'TP1 + TP2 + TP3 · BEST R:R ${rr(signal.tp3)}';
  }
}

// ---------------------------------------------------------------------------
// TASK-07 — event & news widgets (addendum §5). Context only, never votes.
// ---------------------------------------------------------------------------

/// Impact pill for calendar rows (HIGH = red tint, MEDIUM = amber, LOW = dim).
class ImpactPill extends StatelessWidget {
  const ImpactPill({super.key, required this.impact});

  final EventImpact impact;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    switch (impact) {
      case EventImpact.high:
        fg = harborShort;
        bg = harborShortSoft;
      case EventImpact.medium:
        fg = harborWarn;
        bg = harborWarnSoft;
      case EventImpact.low:
        fg = harborDim;
        bg = const Color(0xFFE7ECF2);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        impactLabel(impact),
        style: TextStyle(
          fontFamily: 'Space Mono',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: fg,
        ),
      ),
    );
  }
}

/// Pressure pill for digest themes (display-only macro context).
class PressurePill extends StatelessWidget {
  const PressurePill({super.key, required this.pressure});

  final NewsPressure pressure;

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    switch (pressure) {
      case NewsPressure.hawkish:
        fg = harborShort;
        bg = harborShortSoft;
      case NewsPressure.dovish:
        fg = harborLong;
        bg = harborLongSoft;
      case NewsPressure.neutral:
        fg = harborCobalt;
        bg = const Color(0xFFE3EBFF);
      case NewsPressure.unclear:
        fg = harborDim;
        bg = const Color(0xFFE7ECF2);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        pressureLabel(pressure),
        style: TextStyle(
          fontFamily: 'Space Mono',
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: fg,
        ),
      ),
    );
  }
}

/// "Macro backdrop" strip (addendum §5.1): one-line digest summary shown
/// under the Radar card. Tap navigates to the Events tab. Display only.
class MacroBackdropStrip extends StatelessWidget {
  const MacroBackdropStrip({super.key, required this.themes, this.onTap});

  final List<DisplayDigestTheme> themes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = themes.map((t) => t.theme).join(' · ');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: harborInk,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              HarborIcons.layers,
              size: 15,
              color: Color(0xFF93A1B8),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(
              HarborIcons.arrowUpRight,
              size: 16,
              color: Color(0xFF93A1B8),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live 1-second countdown to [startsIn] from first build (addendum §5.1).
///
/// The target is pinned in [initState] so rebuilds don't shift it. Tests
/// must use `tester.pump()` (not `pumpAndSettle`) while this is mounted —
/// the periodic timer never lets the frame scheduler settle.
class EventCountdown extends StatefulWidget {
  const EventCountdown({super.key, required this.startsIn, this.prefix = 'in '});

  final Duration startsIn;
  final String prefix;

  @override
  State<EventCountdown> createState() => _EventCountdownState();
}

class _EventCountdownState extends State<EventCountdown> {
  late final DateTime _target;
  late Duration _remaining;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _target = DateTime.now().add(widget.startsIn);
    _remaining = widget.startsIn;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = _target.difference(DateTime.now());
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      '${widget.prefix}${formatCountdown(_remaining)}',
      style: const TextStyle(
        fontFamily: 'Space Mono',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: harborShort,
      ),
    );
  }
}
