/// Stats bento — a hero figure plus three supporting cards.
///
/// Design source: https://21st.dev/@uilayout.contact/components/stats-bento
///
/// Geometry is measured from that component's live preview in a browser rather
/// than eyeballed: `rounded-3xl` (24px) cards, a `p-10` hero carrying a 60px
/// figure under a pill badge, a `p-8` growth card with a series to its right,
/// and centred `p-6` number cards. The diagonal hatch on the hero is the
/// reference's own `repeating-linear-gradient`.
///
/// The reference's fourth card is a rating ("4.9 / 5.0", "G2 Peer Reviews").
/// There is no rating anywhere in this product, so no rating card exists here —
/// it would have to be invented, which product rule 2 forbids.
///
/// Palette note: the reference's dark preview is close to what this app already
/// does. `harborInk` cards are the app's existing accent (the Radar day-move
/// strip, the Events guardrail bar), so the dark supporting cards are native
/// rather than a new visual language.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Every radius in the bento, so the four cards read as one set.
const _radius = 24.0;

/// Caps eyebrow used on every card.
const _eyebrow = TextStyle(
  fontFamily: 'Sora',
  fontSize: 9,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.1,
);

class StatsBento extends StatelessWidget {
  const StatsBento({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              children[i],
            ],
          ],
        ),
      );
}

/// The dominant figure: a badge, one very large number and a caption that must
/// carry the denominator.
///
/// The caption is not decoration. A bare percentage next to a trade log reads
/// as "this is the chance this next trade wins", which product rule 4 forbids
/// (consensus is agreement, not probability) and which would be a fabrication
/// about the future. Whatever the hero shows, the caption has to say what it
/// was measured over.
class StatsHero extends StatelessWidget {
  const StatsHero({
    super.key,
    required this.badge,
    required this.figure,
    required this.suffix,
    required this.caption,
  });

  final String badge;

  /// The headline number, already formatted. Empty renders nothing rather than
  /// a placeholder, so an absent measurement is never shown as a zero.
  final String figure;

  /// A trailing unit such as `%`, shown smaller and dimmer.
  final String suffix;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 172),
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: harborLine),
      ),
      child: Stack(
        children: [
          // Hatch: painted as a repeating gradient strip, which is how the
          // reference does it, and masked by a radial fade.
          Positioned.fill(
            child: CustomPaint(painter: _HatchPainter()),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: harborMist,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge.toUpperCase(),
                  style: _eyebrow.copyWith(color: harborDim),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Two Texts rather than one Text.rich: a rich span reports `style == null`, so
                  // anything measuring the widget paints it with the ambient
                  // DefaultTextStyle and reads the 52px figure as a wrapped line.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        figure,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 52,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.8,
                          color: harborInk,
                          height: 1,
                        ),
                      ),
                      if (suffix.isNotEmpty)
                        Text(
                          suffix,
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 19,
                            fontWeight: FontWeight.w600,
                            color: harborFaint,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      caption,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        height: 1.5,
                        color: harborDim,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The reference's `repeating-linear-gradient(45deg, ...)`, drawn directly.
///
/// Faded towards the leading edge with a radial shader, which is what the
/// approved prototype does with a CSS mask. Without the fade the hatch is
/// uniform, sits on top of the caption and reads as a rendering fault rather
/// than a texture.
class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..shader = RadialGradient(
        center: const Alignment(1.6, -1.2),
        radius: 1.5,
        colors: [
          harborInk.withValues(alpha: 0.16),
          harborInk.withValues(alpha: 0.05),
          harborInk.withValues(alpha: 0.0),
        ],
        stops: const [0, 0.45, 1],
      ).createShader(rect);

    const step = 11.0;
    for (var x = -size.height; x < size.width; x += step) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchPainter oldDelegate) => false;
}

/// A dark card carrying one figure and, optionally, a series to its right.
class StatsGrowth extends StatelessWidget {
  const StatsGrowth({
    super.key,
    required this.eyebrow,
    required this.value,
    required this.sub,
    this.chart,
    this.valueColor,
  });

  final String eyebrow;
  final String value;

  /// Says what the figure is measured over, and — when a chart is present —
  /// that the chart is a per-item series rather than the total above.
  final String sub;
  final Widget? chart;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: harborInk,
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: _eyebrow.copyWith(color: harborFaint),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    value,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5,
                      height: 1,
                      color: valueColor ?? const Color(0xFF5FE3B0),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sub,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 9.5,
                      color: harborFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (chart != null) ...[const SizedBox(width: 12), chart!],
          ],
        ),
      );
}

/// A dark card with one centred figure.
class StatsNumber extends StatelessWidget {
  const StatsNumber({
    super.key,
    required this.value,
    required this.label,
    required this.valueColor,
  });

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Container(
        // A shared min height rather than `CrossAxisAlignment.stretch` on the
        // parent Row: this lives inside a scrolling list, where the Row's height
        // is unbounded and stretch throws. Both cards get the same floor, so a
        // one-word label wrapping on one side cannot unlevel the pair.
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: BoxDecoration(
          color: harborInk,
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 25,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
                height: 1,
                color: valueColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              style: _eyebrow.copyWith(color: harborFaint),
            ),
          ],
        ),
      );
}

/// A line chart of one series, with a dashed zero baseline.
///
/// A line rather than bars, because the series is a trend across closed
/// signals and bars implied a magnitude comparison the axis was too small to
/// support. The zero baseline is the important part: pips go negative, and
/// without it a losing run is invisible.
///
/// Negative points are ringed in red so a bad stretch reads at a glance, and
/// the final point is emphasised to mark "current". Values are drawn from
/// [values] only — the chart never invents a point.
class PipsLineChart extends StatelessWidget {
  const PipsLineChart({
    super.key,
    required this.values,
    this.size = const Size(124, 54),
    this.semanticsLabel,
  });

  /// Oldest to newest. May be empty, in which case nothing is drawn.
  final List<double> values;
  final Size size;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox.fromSize(size: size);
    return Semantics(
      label: semanticsLabel,
      image: true,
      child: SizedBox.fromSize(
        size: size,
        child: CustomPaint(painter: _PipsChartPainter(values)),
      ),
    );
  }
}

class _PipsChartPainter extends CustomPainter {
  _PipsChartPainter(this.values);

  final List<double> values;

  static const _padX = 3.0;
  static const _padTop = 7.0;
  static const _padBottom = 7.0;
  static const _positive = Color(0xFF5FE3B0);
  static const _negative = Color(0xFFFF8A8A);

  @override
  void paint(Canvas canvas, Size size) {
    // Include 0 in the domain so the baseline is always on-screen, and pad the
    // range slightly so the extremes are not flush against the edge.
    var lo = math.min(values.reduce(math.min), 0);
    var hi = values.reduce(math.max);
    if (hi - lo < 0.001) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    final span = hi - lo;

    double x(int i) => _padX + i * (size.width - _padX * 2) / (values.length - 1);
    double y(double v) =>
        _padTop + (hi - v) * (size.height - _padTop - _padBottom) / span;

    final zeroY = y(0);

    // Zero baseline.
    final base = Paint()
      ..color = harborDim.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    // Dashed by hand: a 1px dash pattern is all that is available here without
    // pulling in a dependency, and `Path..dash` is not available on Paint.
    const dash = 2.0;
    const gap = 3.0;
    for (var dx = _padX; dx < size.width - _padX; dx += dash + gap) {
      canvas.drawLine(
        Offset(dx, zeroY),
        Offset(math.min(dx + dash, size.width - _padX), zeroY),
        base,
      );
    }

    final points = <Offset>[
      for (var i = 0; i < values.length; i++) Offset(x(i), y(values[i])),
    ];

    // Area under the curve, clipped at the baseline so a negative dip does not
    // paint above it.
    final line = _smoothPath(points);
    final area = Path.from(line)
      ..lineTo(points.last.dx, zeroY)
      ..lineTo(points.first.dx, zeroY)
      ..close();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, math.min(zeroY, size.height), size.width, math.max(zeroY, 0)));
    canvas.drawPath(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x425FE3B0), Color(0x005FE3B0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.restore();

    canvas.drawPath(
      line,
      Paint()
        ..color = _positive
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Negative points ringed in red.
    for (var i = 0; i < values.length; i++) {
      if (values[i] >= 0) continue;
      canvas.drawCircle(points[i], 2.6, Paint()..color = _negative);
    }

    // Current value: solid dot with a soft halo.
    final last = points.last;
    canvas.drawCircle(last, 6, Paint()..color = _positive.withValues(alpha: 0.22));
    canvas.drawCircle(last, 3.4, Paint()..color = _positive);
  }

  /// A gentle curve through the points: a pips series is a trend, not a set of
  /// spikes, so a polyline reads as noise it does not contain.
  Path _smoothPath(List<Offset> pts) {
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      final p = pts[i - 1];
      final c = pts[i];
      final mid = (p.dx + c.dx) / 2;
      path.cubicTo(mid, p.dy, mid, c.dy, c.dx, c.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _PipsChartPainter old) => old.values != values;
}
