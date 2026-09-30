/// Shared Harbor building blocks used across the 6 screens.
///
/// Icons are the bundled Flaticon UIcons ([HarborIcons]); Sora is the
/// display font and Space Mono ([mono]) renders every numeral. Sizes,
/// colors, radii and tracking are transcribed from the inline `<style>` of
/// `docs/mockups/mockup.html`.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Brand header: mark + XAU RADAR wordmark + LIVE pill (mockup `.top`).
///
/// Global chrome shared by all six screens, so it is the one place the brand
/// row is defined. [subtitle] is optional: the Radar header is the bare brand
/// row, other screens still carry their section subtitle under the wordmark.
class HarborHeader extends StatelessWidget {
  const HarborHeader({super.key, this.subtitle, this.statusText});

  final String? subtitle;
  final String? statusText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
      child: Row(
        children: [
          const BrandMark(),
          const SizedBox(width: 9),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'XAU RADAR',
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
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
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: livePillBg,
              border: Border.all(color: livePillBorder),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 6,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: harborLong,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  statusText ?? 'LIVE · 18s',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: livePillInk,
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

/// Ink-bordered brand mark (mockup `.mark`): a 27px box with a 2px ink
/// border, 8px radius and two cobalt bars.
///
/// Painted rather than set in an icon font — the mockup draws it with
/// pseudo-elements, so the geometry is reproduced with a [CustomPainter].
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 27});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: const _BrandMarkPainter()),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter();

  /// Bar geometry is relative to the 27px box the mockup specifies; the
  /// stroke is inset by 1px because Flutter centres strokes on the path.
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
        const Radius.circular(7),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = harborInk,
    );
    final bar = Paint()..color = harborCobalt;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8, 7, 4, 14),
        const Radius.circular(2),
      ),
      bar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(15, 4, 4, 20),
        const Radius.circular(2),
      ),
      bar,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => false;
}

/// Uppercase tracked micro-label (mockup `.eyebrow`).
class HarborEyebrow extends StatelessWidget {
  const HarborEyebrow(this.text, {super.key, this.color = harborDim});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Sora',
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.6,
        color: color,
      ),
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

/// Spot quote block (mockup `.price`): eyebrow, quote row and meta row.
class SpotPriceBlock extends StatelessWidget {
  const SpotPriceBlock({super.key, required this.signal});

  final DisplaySignal signal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('XAUUSD · Spot Gold'),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatPrice(signal.price),
                style: const TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 32,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  movePercent(signal),
                  style: TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: signal.dayMove < 0 ? harborShort : harborLong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // `Wrap` rather than a `Row`: the mockup's flex row stays on one
          // line at 390px, but oversized text must wrap, not overflow.
          Wrap(
            spacing: 13,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _MetaPair(
                label: 'Spread',
                value: signal.spread.toStringAsFixed(2),
              ),
              const _MetaPair(label: 'Session', value: 'NY'),
              _MetaPair(label: 'Updated', value: clockLabel()),
            ],
          ),
        ],
      ),
    );
  }
}

/// `HH:MM` from the device clock — the feed stamps its own refresh, so the
/// meta row reads the clock live instead of freezing a literal timestamp.
String clockLabel() {
  final now = DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
}

/// `LABEL value` meta pair (mockup `.meta`): Sora label, Space Mono value.
class _MetaPair extends StatelessWidget {
  const _MetaPair({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: label,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 10,
              color: harborDim,
            ),
          ),
          TextSpan(text: ' '),
          TextSpan(
            text: value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// Day change as a percentage of the implied open (`price - dayMove`).
String movePercent(DisplaySignal signal) {
  final open = signal.price - signal.dayMove;
  if (open <= 0) return '—';
  final pct = signal.dayMove / open * 100;
  final sign = pct < 0 ? '−' : '+';
  return '$sign${pct.abs().toStringAsFixed(2)}%';
}

/// Inverted day bar (mockup `.day`): day move on the left, session range on
/// the right.
class DayMoveBar extends StatelessWidget {
  const DayMoveBar({super.key, required this.signal, this.range});

  final DisplaySignal signal;

  /// Session high/low override. When omitted the bar derives the range from
  /// [DisplaySignal.dayLow] / [DisplaySignal.dayHigh]; if the provider has
  /// not supplied either, the bar renders `—` rather than inventing numbers
  /// (rule 2: never fabricate).
  final String? range;

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HarborEyebrow('Day Move', color: inkMuted),
                  const SizedBox(height: 3),
                  Text(
                    '${signal.dayMove < 0 ? '−' : '+'}'
                    '${signal.dayMove.abs().toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const HarborEyebrow('Range', color: inkMuted),
                const SizedBox(height: 3),
                Text(
                  range ?? _rangeFromSignal(signal),
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// `3,721.10 — 3,748.90` from the signal's session range, or `—` when the
/// market-data provider has not supplied a high/low yet.
String _rangeFromSignal(DisplaySignal signal) {
  final low = signal.dayLow;
  final high = signal.dayHigh;
  if (low == null || high == null) return '—';
  return '${formatPrice(low)} — ${formatPrice(high)}';
}

/// Timeframe segment display (mockup `.switch`).
///
/// View-only by product rule 1: 15M is the only signal timeframe, 5M is
/// confirmation and 1H is context. Tapping a segment must never change the
/// consensus, so the control deliberately has no gesture handler.
class TimeframeSwitch extends StatelessWidget {
  const TimeframeSwitch({super.key, this.active = '15M'});

  final String active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 11),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: switchTrack,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            for (final tf in const ['15M', '5M', '1H'])
              Expanded(child: _segment(tf, tf == active)),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        color: isActive ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        // Mockup `box-shadow:0 1px 3px #0001` on the active segment.
        boxShadow: isActive
            ? const [
                BoxShadow(
                  color: Color(0x01000000),
                  offset: Offset(0, 1),
                  blurRadius: 3,
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isActive ? harborInk : harborDim,
        ),
      ),
    );
  }
}

/// White card shell shared by every Radar state card (mockup `.verdict`).
class VerdictCardShell extends StatelessWidget {
  const VerdictCardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(18),
      ),
      child: child,
    );
  }
}

/// Direction badge (mockup `.dir`): tinted pill, trend arrow + LONG/SHORT.
///
/// The bundled UIcons set ships only the up-trend glyph, so SHORT rotates it
/// 180° to keep the direction semantics.
class DirectionPill extends StatelessWidget {
  const DirectionPill({super.key, required this.direction, this.fontSize = 12});

  final Direction direction;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final (String label, Color fg, Color bg) = switch (direction) {
      Direction.long => ('LONG', harborLong, harborLongSoft),
      Direction.short => ('SHORT', harborShort, harborShortSoft),
      Direction.neutral => ('NO SIGNAL', harborFaint, const Color(0xFFE7ECF2)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (direction != Direction.neutral)
            _trendArrow(fg),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trendArrow(Color color) {
    final arrow = Icon(HarborIcons.arrowTrendUp, size: 14, color: color);
    if (direction != Direction.short) return arrow;
    return Transform.rotate(angle: math.pi, child: arrow);
  }
}

/// Agreement strength block (mockup `.strength`): band label + meter.
///
/// Renders agreement only (spec §7) — never a forecast of outcome.
class ConsensusMeter extends StatelessWidget {
  const ConsensusMeter({super.key, required this.signal, this.width = 104});

  final DisplaySignal signal;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      // `stretch` (not `start`): with loose constraints the track DecoratedBox
      // shrink-wraps to the fill width, so the unfilled remainder is
      // invisible and the meter always reads as 100%.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${bandLabel(signal.band)} · ${signal.agreeCount} / ${signal.totalCount}',
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: harborDim,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: DecoratedBox(
              decoration: const BoxDecoration(color: meterTrack),
              child: SizedBox(
                height: 6,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: signal.strength.clamp(0, 100) / 100,
                  child: const ColoredBox(color: harborLong),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One level cell (mockup `.level`): label, value, sub-line. No icons.
class VerdictLevelCell extends StatelessWidget {
  const VerdictLevelCell({
    super.key,
    required this.label,
    required this.value,
    required this.sub,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final String sub;

  /// The Entry cell spans the grid and carries the tinted fill.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted ? levelEntryBg : Colors.white,
        border: Border.all(
          color: highlighted ? levelEntryBorder : levelBorder,
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: harborDim,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 15,
              color: harborInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 9,
              color: harborFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// Two-column level grid (mockup `.levels`) with a full-width Entry cell.
///
/// Built from [Row]s rather than a nested grid: shrink-wrapped scrollables
/// inside the screen [ListView] crash the semantics walk in widget tests.
class VerdictLevelGrid extends StatelessWidget {
  const VerdictLevelGrid({
    super.key,
    required this.entry,
    required this.cells,
    this.gap = 7,
  });

  final Widget entry;
  final List<Widget> cells;
  final double gap;

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
              if (j > 0) SizedBox(width: gap),
              Expanded(child: pair[j]),
            ],
            if (pair.length == 1) Expanded(child: SizedBox()),
          ],
        ),
      );
      if (end < cells.length) rows.add(SizedBox(height: gap));
    }
    // `stretch` is required so the Entry cell fills the full row width
    // (mockup `.level:nth-child(1){grid-column:span 2}`). With
    // `CrossAxisAlignment.start` the cell would shrink-wrap to its content
    // and leave the right half of the row empty.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        entry,
        SizedBox(height: gap),
        for (final row in rows) row,
      ],
    );
  }
}

/// Price distance from [from] to [to], e.g. `+8.40` / `−5.60`.
String levelDistance(double from, double to) {
  final delta = to - from;
  final sign = delta < 0 ? '−' : '+';
  return '$sign${delta.abs().toStringAsFixed(2)}';
}

/// Target-scope selector (mockup `.tp`, spec §10) for the Radar card.
///
/// Shares [AppState.targets] with [TargetSelector], so the Signal screen
/// stays in sync with whatever scope the trader picked here.
class TargetScopePills extends StatelessWidget {
  const TargetScopePills({super.key});

  static const _options = [
    (TargetSelection.tp1Only, 'TP1'),
    (TargetSelection.tp1Tp2, 'TP2'),
    (TargetSelection.all, 'TP3'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _pill(
            label: _options[i].$2,
            isActive: state.targets == _options[i].$1,
            onTap: () => state.setTargets(_options[i].$1),
          ),
        ],
      ],
    );
  }

  Widget _pill({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 0)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStatePropertyAll(
          isActive ? tpActiveBg : Colors.white,
        ),
        foregroundColor: WidgetStatePropertyAll(
          isActive ? harborCobalt : harborDim,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: isActive ? harborCobalt : harborLine),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Sora',
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: Text(label),
    );
  }
}

/// One collected source behind the consensus (mockup `.src`).
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.label, required this.agrees});

  final String label;
  final bool agrees;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label ${agrees ? '✓' : '×'}',
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 8,
          color: chipInk,
        ),
      ),
    );
  }
}

/// Horizontally scrollable context strip under the Radar card
/// (mockup `.scenario`).
class ScenarioStrip extends StatelessWidget {
  const ScenarioStrip({super.key, required this.pills});

  final List<({String label, String value})> pills;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 13, 18, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < pills.length; i++) ...[
              if (i > 0) const SizedBox(width: 7),
              _pill(pills[i].label, pills[i].value),
            ],
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: harborDim,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }
}

/// MOCK_MODE-only state switcher, demoted out of the designed layout.
///
/// Every required Radar state has to be reviewable, so the switcher stays —
/// but as a discreet pill row under the scenario strip rather than a
/// segmented control inside the design. Callers must gate it on
/// `config.mockMode`.
class DemoStateRow extends StatelessWidget {
  const DemoStateRow({super.key});

  static const _options = [
    (RadarScenario.strong, 'STRONG'),
    (RadarScenario.developing, 'DEVELOPING'),
    (RadarScenario.noConsensus, 'DIVIDED'),
    (RadarScenario.blackout, 'EVENT'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        children: [
          const Text(
            'DEMO STATE',
            style: TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: harborFaint,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < _options.length; i++) ...[
                    if (i > 0) const SizedBox(width: 5),
                    _pill(
                      label: _options[i].$2,
                      isActive: state.scenario == _options[i].$1,
                      onTap: () => state.setScenario(_options[i].$1),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 0)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: const WidgetStatePropertyAll(chipBg),
        foregroundColor: WidgetStatePropertyAll(
          isActive ? harborCobalt : chipInk,
        ),
        // Transparent when idle so selecting a state never shifts the row.
        side: WidgetStatePropertyAll(
          BorderSide(
            color: isActive ? harborCobalt : Colors.transparent,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Sora',
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      child: Text(label),
    );
  }
}

/// Event guardrail bar (mockup `.blackout`) — the compact blackout state.
///
/// Replaces the signal card during a HIGH-event window. The whole bar is the
/// hit target and routes to the Events tab; there is no separate button.
/// Context only: events never vote (rule 9).
class EventGuardrailBar extends StatelessWidget {
  const EventGuardrailBar({
    super.key,
    required this.event,
    required this.onTap,
  });

  final DisplayEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Material(
        color: harborInk,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 6,
                  height: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: harborShort,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'EVENT GUARDRAIL',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 9,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${event.currency} ${impactLabel(event.impact)} '
                        'impact event in ${formatCountdown(event.startsIn)}'
                        ' · View event',
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 9,
                          height: 1.35,
                          color: inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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

/// Bare `1:x` risk/reward for the furthest target in [selection] — the form
/// the Radar agreement row shows next to the `R:R` label.
String bestRrValue(DisplaySignal signal, TargetSelection selection) {
  final tp = switch (selection) {
    TargetSelection.tp1Only => signal.tp1,
    TargetSelection.tp1Tp2 => signal.tp2,
    TargetSelection.all => signal.tp3,
  };
  if (tp == null) return '—';
  final value = riskReward(
    target: tp,
    entryLow: signal.entryLow,
    stopLoss: signal.stopLoss,
  );
  return '1:${value.toStringAsFixed(1)}';
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
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: harborInk,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            const Icon(
              HarborIcons.layers,
              size: 13,
              color: inkMuted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 10,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(
              HarborIcons.arrowUpRight,
              size: 14,
              color: inkMuted,
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
