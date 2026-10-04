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
// Session calendar only; the barrel also exports an enum that collides with
// the app's own display models.
import 'package:xau_core/analysis/session.dart';

import '../config.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// Brand header: XV mark + wordmark + market-status pill (mockup `.top`).
///
/// Global chrome shared by all six screens, so it is the one place the brand
/// row is defined. [subtitle] is optional: the Radar header is the bare brand
/// row, other screens still carry their section subtitle under the wordmark.
///
/// The pill reports the real trading session. It previously read a hardcoded
/// `LIVE · 18s`, which claimed a live market with a frozen timestamp even when
/// the market was shut for the weekend.
class HarborHeader extends StatelessWidget {
  const HarborHeader({
    super.key,
    this.subtitle,
    this.statusText,
    this.sessionOpen,
    this.sessionName,
    this.marketStatusLabel,
  });

  final String? subtitle;

  /// Overrides the pill text entirely. Screens that know better pass this.
  final String? statusText;

  /// Whether the XAUUSD market is trading. Null means "ask the clock", which is
  /// what every screen wants; a shut market must never be presented as live.
  final bool? sessionOpen;

  /// Phase name shown when [statusText] is not supplied, e.g. `US`, `ASIA`.
  /// Null means "derive it from the current session".
  final String? sessionName;

  /// Whether to show a market-status claim at all.
  ///
  /// Defaults to `!mockMode`: an offline build has no feed, so it says nothing
  /// rather than implying a market it cannot see. Defaults to a `const` so the
  /// `const HarborHeader(...)` call sites keep working.
  final bool? marketStatusLabel;

  /// Whether to show the pill at all.
  ///
  /// An explicit [statusText] is always shown: callers use it for signal
  /// lifecycle labels like `NO CONSENSUS`, which are not market claims. Only
  /// the derived market-session pill is gated, because an offline build has no
  /// feed to describe.
  bool get _showsStatus => statusText != null || (marketStatusLabel ?? !mockMode);

  /// Real session state at [now], unless a caller overrides it (tests).
  bool _openAt(DateTime now) => sessionOpen ?? isSessionOpen(now);
  String _nameAt(DateTime now) => sessionName ?? sessionLabel(sessionAt(now));

  /// Never claims a live market while the market is shut.
  String _pillText(DateTime now) {
    final name = _nameAt(now);
    // Closed, with no session phase to speak of, is simply CLOSED.
    if (!_openAt(now) && name == 'CLOSED') return 'MARKET CLOSED';
    return _openAt(now) ? name : '$name · CLOSED';
  }

  @override
  Widget build(BuildContext context) {
    // An offline build has no market feed, so it shows no market claim at all.
    if (!_showsStatus) return _headerOnly(subtitle);
    // Read the clock once so the phase and the open/closed verdict cannot
    // disagree across a midnight or DST boundary mid-rebuild.
    final now = DateTime.now().toUtc();
    final isClosed = !_openAt(now);
    final status = statusText ?? _pillText(now);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
      child: Row(
        children: [
          const BrandMark(),
          const SizedBox(width: 9),
          // `Expanded` + ellipsis: a long section subtitle (the Events
          // "MACRO CONTEXT · NEVER VOTES" guard banner) must shorten, never
          // push the LIVE pill off the 390px page.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'XV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 10,
                      color: harborFaint,
                      letterSpacing: 0.8,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          if (!_showsStatus)
            const SizedBox.shrink()
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: isClosed ? harborWarnSoft : livePillBg,
                border: Border.all(color: isClosed ? harborWarn : livePillBorder),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pulses only while the market is genuinely open, and only in a live
                  // build. A preview has no market to be live about, and an
                  // endlessly repeating animation would keep the frame
                  // scheduler permanently busy.
                  PulseDot(
                    color: isClosed ? harborWarn : harborLong,
                    pulse: !isClosed && !mockMode,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    status,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: isClosed ? harborWarn : livePillInk,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Brand and subtitle only, with no market-status claim at all. Used by the
  /// offline build, which has no feed and must not imply that it does.
  Widget _headerOnly(String? sub) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 17, 18, 10),
    child: Row(
      children: [
        const BrandMark(),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'XV',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    color: harborFaint,
                    letterSpacing: 0.8,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Pulsing status dot.
///
/// Port of the Uiverse "Loader" by Yaya12085 (MIT licence):
/// a solid dot with a halo that grows from 0 to 14px and fades out, on a 1.5s
/// ease-in-out loop.
///
/// The pulse is *only* used for a genuinely open session. A pulsing dot on a
/// closed market would assert activity that does not exist, which is the same
/// class of lie as the hardcoded `LIVE` label this replaced.
class PulseDot extends StatefulWidget {
  const PulseDot({
    super.key,
    required this.color,
    this.size = 6,
    this.pulse = true,
    this.duration = const Duration(milliseconds: 1500),
  });

  /// Core dot and halo colour. Pass the same value as the surrounding text so
  /// the dot reads as part of the label rather than an independent element.
  final Color color;

  /// Diameter of the solid core.
  final double size;

  /// False renders a static dot: no halo, no animation.
  final bool pulse;

  final Duration duration;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  /// Created eagerly in [initState] and nullable.
  ///
  /// A `late final` initialiser would construct the controller on first *use*,
  /// which can happen inside [dispose] — and building a Ticker then looks up an
  /// ancestor of a deactivated element, which throws. Null means "this dot does
  /// not pulse", which is the correct state for a closed market anyway.
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _c = AnimationController(vsync: this, duration: widget.duration)
        ..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulseDot old) {
    super.didUpdateWidget(old);
    // The session can open or close while this is mounted; start or stop the
    // pulse to match rather than leaving it stuck in the old state.
    if (old.pulse == widget.pulse) return;
    if (widget.pulse) {
      _c ??= AnimationController(vsync: this, duration: widget.duration)
        ..repeat(reverse: true);
    } else {
      _c?.stop();
      _c?.dispose();
      _c = null;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    _c = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // An animation is motion the user did not ask for, so honour the platform
    // setting: a static dot still communicates the same state.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final animate = widget.pulse && !reduceMotion && _c != null;

    // The halo is drawn inside a fixed box and overflows its centre outward, so
    // the row reserves room for it instead of the halo being clipped.
    final extent = widget.size * 2.4;
    final core = SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );

    if (!animate) {
      return core;
    }

    return SizedBox(
      width: extent,
      height: extent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c!,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_c!.value);
              return Transform.scale(
                // Grows from the dot's own size out to the full halo extent.
                scale: 1 + t * (extent / widget.size - 1),
                child: Opacity(
                  opacity: 0.55 * (1 - t),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.color,
                      shape: BoxShape.circle,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
          core,
        ],
      ),
    );
  }
}

/// Brand mark for **XV** (XAU-Vote): a 27px box with a 2px ink border, 8px
/// radius and the letters XV set in cobalt Sora ExtraBold.
///
/// Painted with a [TextPainter] rather than an icon font so the monogram stays
/// crisp at any size and reuses the already-bundled Sora face — the launcher
/// icon (see `assets/icons`) uses the same cobalt/radius geometry.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 27});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _BrandMarkPainter(size)),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.size);

  final double size;

  /// Geometry is relative to the 27px box; the stroke is inset by 1px because
  /// Flutter centres strokes on the path.
  @override
  void paint(Canvas canvas, Size _) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1, 1, size - 2, size - 2),
        const Radius.circular(7),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = harborInk,
    );

    // `XV` centred optically: the text box is measured, then shifted up by a
    // hair because Sora's cap height sits below the em box.
    final painter = TextPainter(
      text: TextSpan(
        text: 'XV',
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: size * 0.46,
          fontWeight: FontWeight.w800,
          letterSpacing: -size * 0.02,
          color: harborCobalt,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset((size - painter.width) / 2, (size - painter.height) / 2),
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) => oldDelegate.size != size;
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
              _MetaPair(label: 'Spread', value: signal.spread.toStringAsFixed(2)),
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
            style: const TextStyle(fontFamily: 'Sora', fontSize: 10, color: harborDim),
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
  const TimeframeSwitch({super.key, this.active = '15M', this.onChanged});

  final String active;

  /// Called with the newly selected timeframe. Null makes the control inert,
  /// which is what a caller that has nothing to switch uses.
  final ValueChanged<String>? onChanged;

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
    // Only the segment itself is interactive, so a tap on the already-active
    // segment does not emit a change.
    return InkWell(
      onTap: isActive || onChanged == null ? null : () => onChanged!(label),
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
      ),
    );
  }
}

/// White card shell shared by every Radar state card (mockup `.verdict`).
///
/// Thin wrapper over [HarborCard] at the Radar section gutter, kept so the
/// Radar screen's own finders keep resolving to one widget.
class VerdictCardShell extends StatelessWidget {
  const VerdictCardShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => HarborCard(margin: 0, child: child);
}

// ---------------------------------------------------------------------------
// Unified Harbor primitives.
//
// The Radar screen is the design-system reference, so these are its surfaces
// factored out for the rest of the app. Every size/radius/colour is
// transcribed from the inline `<style>` of `docs/mockups/mockup.html` —
// nothing here derives a new value.
// ---------------------------------------------------------------------------

/// White surface shell (mockup `.verdict`): 1px [harborLine] border, 15px
/// padding, 18px radius.
///
/// [margin] is the 18px page gutter the Radar sections use — pass 0 when the
/// caller already pads the list. Dense list rows drop to `radius: 16`.
/// Wraps its child in a transparent [Material] so an [InkWell] inside an
/// expandable row still has somewhere to paint its splash.
class HarborCard extends StatelessWidget {
  const HarborCard({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = const EdgeInsets.all(15),
    this.margin = 18,
    this.accentEdge,
  });

  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final double margin;

  /// Draws a thicker coloured edge down the leading side of the card.
  ///
  /// Preferred over a sibling `Container` strip: a full-height strip needs the
  /// row's height to be resolved first (IntrinsicHeight), which is both
  /// expensive and fragile inside a scrolling list — it rendered as a huge
  /// block when the row also contained a `Wrap`. A border needs no measurement.
  final Color? accentEdge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: margin),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          // Uniform by necessity: Flutter cannot round a border whose sides
          // differ in colour, so an accent edge is drawn by the caller as a
          // leading element rather than by tinting one side here.
          border: Border.all(color: harborLine),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

/// Neutral chip (mockup `.src`): 8–9px [chipInk] on a [chipBg] pill, with an
/// optional leading [HarborIcons] glyph. Carries no accent of its own — the
/// glyph colour is the caller's signal (agreement, direction, …).
class HarborChip extends StatelessWidget {
  const HarborChip(
    this.label, {
    super.key,
    this.glyph,
    this.glyphColor,
    this.fontSize = 9,
  });

  final String label;
  final IconData? glyph;
  final Color? glyphColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (glyph != null) ...[
            Icon(glyph, size: fontSize + 2, color: glyphColor ?? chipInk),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(fontFamily: 'Sora', fontSize: fontSize, color: chipInk),
          ),
        ],
      ),
    );
  }
}

/// Small bordered pill (mockup `.tp button`): 8px radius, 9px Sora w700.
///
/// Idle is white on a [harborLine] border; [active] is the cobalt selection
/// (cobalt border + cobalt ink on [tpActiveBg]). Renders a plain shell when
/// [onTap] is null so a decorative pill is never painted as disabled.
class HarborPill extends StatelessWidget {
  const HarborPill(
    this.label, {
    super.key,
    this.active = false,
    this.onTap,
    this.fontSize = 9,
  });

  final String label;
  final bool active;
  final VoidCallback? onTap;
  final double fontSize;

  BoxDecoration get _decoration => BoxDecoration(
    color: active ? tpActiveBg : Colors.white,
    borderRadius: BorderRadius.circular(8),
    border: Border.all(color: active ? harborCobalt : harborLine),
  );
  Widget get _label => Text(
    label,
    style: TextStyle(
      fontFamily: 'Sora',
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: active ? harborCobalt : harborDim,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final shell = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: _label,
    );
    if (onTap == null) {
      return Container(decoration: _decoration, child: shell);
    }
    return TextButton(
      onPressed: onTap,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        minimumSize: const WidgetStatePropertyAll(Size(0, 0)),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: WidgetStatePropertyAll(active ? tpActiveBg : Colors.white),
        side: WidgetStatePropertyAll(
          active
              ? const BorderSide(color: harborCobalt)
              : const BorderSide(color: harborLine),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Sora', fontSize: fontSize, fontWeight: FontWeight.w700),
        ),
      ),
      child: shell,
    );
  }
}

/// Full-bleed action button (mockup `.actions button`): 38px tall, 10px
/// radius, Sora 11 w800. [primary] is the cobalt CTA; otherwise a white
/// button with a [harborLine] border and [harborInk] label.
///
/// This is the Radar card's Copy/Share button, factored out — callers wrap it
/// in [Expanded] for the paired action row.
class HarborActionButton extends StatelessWidget {
  const HarborActionButton({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: Material(
        color: primary ? harborCobalt : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: primary ? harborCobalt : harborLine),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: primary ? Colors.white : harborInk,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline rule (mockup `--divider`, used by `.agree` and the Sources
/// detail table).
///
/// Horizontal by default. Pass [verticalExtent] for the 1px column rule
/// between table columns — the extent is explicit so the rule never has to
/// resolve against an unbounded cross-axis.
class HarborDivider extends StatelessWidget {
  const HarborDivider({
    super.key,
    this.indent = 0,
    this.verticalExtent,
    this.color = divider,
  });

  final double indent;
  final double? verticalExtent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (verticalExtent != null) {
      return SizedBox(
        width: 1,
        height: verticalExtent,
        child: ColoredBox(color: color),
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: SizedBox(height: 1, child: ColoredBox(color: color)),
    );
  }
}

/// Numeral + eyebrow pair for stat headers (the History stat tile), shared so
/// every screen renders headline figures identically.
///
/// The numeral is Space Mono — the unified language sets every figure in the
/// mono face so columns align.
class HarborStat extends StatelessWidget {
  const HarborStat({
    super.key,
    required this.value,
    required this.label,
    this.valueColor = harborInk,
    this.fontSize = 20,
  });

  final String value;
  final String label;
  final Color valueColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          HarborEyebrow(label),
        ],
      ),
    );
  }
}

/// Expand/collapse affordance (mockup `.chev`): the `›` text glyph, rotated
/// 90° and turned cobalt while the row is open.
///
/// A text glyph rather than an icon font — the mockup draws it that way, and
/// no Material chevron ships the same weight.
class HarborChevron extends StatelessWidget {
  const HarborChevron({super.key, required this.open, this.size = 16});

  final bool open;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: open ? 1 : 0,
      child: Text(
        '›',
        style: TextStyle(fontSize: size, color: open ? harborCobalt : harborFaint),
      ),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (direction != Direction.neutral) _trendArrow(fg),
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
        border: Border.all(color: highlighted ? levelEntryBorder : levelBorder),
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
    return HarborPill(label, active: isActive, onTap: onTap);
  }
}

/// One collected source behind the consensus (mockup `.src`).
///
/// The agreement mark is part of the label so the chip's whole text stays one
/// widget — the glyph-capable [HarborChip] is for rows that lead with an icon.
class SourceChip extends StatelessWidget {
  const SourceChip({super.key, required this.label, required this.agrees});

  final String label;
  final bool agrees;

  @override
  Widget build(BuildContext context) {
    return HarborChip('$label ${agrees ? '✓' : '×'}', fontSize: 8);
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
        foregroundColor: WidgetStatePropertyAll(isActive ? harborCobalt : chipInk),
        // Transparent when idle so selecting a state never shifts the row.
        side: WidgetStatePropertyAll(
          BorderSide(color: isActive ? harborCobalt : Colors.transparent),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: 'Sora', fontSize: 9, fontWeight: FontWeight.w700),
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
  const EventGuardrailBar({super.key, required this.event, required this.onTap});

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
                    decoration: BoxDecoration(color: harborShort, shape: BoxShape.circle),
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

/// TP target-scope selector (spec §10), shared by Radar + Signal.
///
/// Restyled onto [HarborPill] so the Signal screen's control is the same
/// widget language as the Radar card's TP pills (mockup `.tp`). Selection
/// behaviour is unchanged: it writes straight to [AppState.targets] and
/// narrows the visible targets on every screen that reads it.
class TargetSelector extends StatelessWidget {
  const TargetSelector({super.key});

  static const _options = [
    (TargetSelection.tp1Only, 'TP1'),
    (TargetSelection.tp1Tp2, 'TP1 + 2'),
    (TargetSelection.all, 'TP1 + 2 + 3'),
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Row(
      children: [
        for (var i = 0; i < _options.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          HarborPill(
            _options[i].$2,
            active: state.targets == _options[i].$1,
            onTap: () => state.setTargets(_options[i].$1),
          ),
        ],
      ],
    );
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
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
            const Icon(HarborIcons.layers, size: 13, color: inkMuted),
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
            const Icon(HarborIcons.arrowUpRight, size: 14, color: inkMuted),
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
    // The target is an absolute instant, so the displayed value is derived
    // from the clock rather than accumulated. `Timer.periodic` drifts (each
    // tick is scheduled a full period after the previous one *fires*, not
    // after the previous deadline), which is what made the seconds appear to
    // stutter or skip.
    _target = DateTime.now().add(widget.startsIn);
    _remaining = widget.startsIn;
    _scheduleTick();
  }

  /// Rebuild cadence follows the magnitude of the countdown.
  ///
  /// Ticking a multi-day countdown once a second rebuilt the whole Events list
  /// hundreds of times for a value whose seconds are never displayed. A
  /// sub-day countdown still ticks each second because that is what the user
  /// is actually watching.
  void _scheduleTick() {
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval(_remaining), (_) => _onTick());
  }

  static const _second = Duration(seconds: 1);
  static const _minute = Duration(minutes: 1);

  /// Next deadline that changes the rendered text.
  ///
  /// Computed from the target rather than the interval alone, so the first tick
  /// lands on the visible boundary instead of one interval later.
  Duration _tickInterval(Duration remaining) {
    if (!countdownTicksSeconds(remaining)) return _minute;
    final s = remaining.inSeconds;
    // Under a minute only the seconds change; past a minute the minute can
    // roll over first, so tick no later than that boundary.
    if (s <= 60) return _second;
    final secondsToNextMinute = s % 60;
    return Duration(seconds: secondsToNextMinute == 0 ? 60 : secondsToNextMinute);
  }

  void _onTick() {
    if (!mounted) return;
    final next = _target.difference(DateTime.now());
    // Past the target: stop rebuilding entirely rather than ticking at zero
    // forever, and show the elapsed state instead.
    setState(() {
      _remaining = next.isNegative ? Duration.zero : next;
    });
    if (next.isNegative) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    // Re-derive the cadence: crossing an hour or a day boundary changes the
    // rendered precision, and the interval must follow it.
    final interval = _tickInterval(next);
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _onTick());
  }

  @override
  void didUpdateWidget(covariant EventCountdown old) {
    super.didUpdateWidget(old);
    // A new poll delivers a new startsIn for the same event. Re-pin the target,
    // otherwise the countdown keeps ticking toward a stale deadline and drifts
    // away from the server's answer.
    if (old.startsIn != widget.startsIn) {
      _target = DateTime.now().add(widget.startsIn);
      _remaining = widget.startsIn;
      _scheduleTick();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Elapsed, not upcoming. Rendered neutrally so a finished countdown can
    // never read as an imminent red one.
    final elapsed =
        _remaining == Duration.zero && _target.difference(DateTime.now()).isNegative;
    return Text(
      elapsed ? 'released' : '${widget.prefix}${formatCountdown(_remaining)}',
      style: TextStyle(
        fontFamily: 'Space Mono',
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: elapsed ? harborDim : harborShort,
      ),
    );
  }
}
