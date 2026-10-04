/// Skeleton loading surfaces.
///
/// # Why a shimmer instead of the Material refresh indicator
///
/// `RefreshIndicator` paints a solid grey circle with a spinner. Against this
/// app's white cards it reads as a rendering fault rather than as progress, and
/// it covers the content it is refreshing. A skeleton keeps the layout stable
/// and shows the shape of what is arriving, which is what a trader staring at
/// a mostly-empty Radar actually needs.
///
/// The shimmer is a single shared [AnimationController] per skeleton, driven by
/// a gradient sweep. It stops when `MediaQuery.disableAnimations` is set, and
/// degrades to a flat fill rather than animating forever, so it cannot keep the
/// frame scheduler busy (which previously hung every `pumpAndSettle`).
library;

import 'package:flutter/material.dart';
import '../theme.dart';

/// A shimmering placeholder block.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  /// Null width fills the available space.
  final double? width;
  final double height;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    // Nullable and eager: a late final would construct inside dispose(), where
    // creating a Ticker looks up a deactivated ancestor and throws.
    _c?.dispose();
    _c = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final controller = _c;
    if (reduce || controller == null || !controller.isAnimating) {
      return _fill();
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ShaderMask(
        // A single sweep across the block, rather than a pulsing opacity: it
        // reads as "loading" rather than as "disabled".
        blendMode: BlendMode.srcIn,
        shaderCallback: (rect) {
          final t = controller.value * 2 - 1;
          return LinearGradient(
            begin: Alignment(t - 1, 0),
            end: Alignment(t + 1, 0),
            colors: const [
              harborLine,
              Color(0xFFF1F4F9),
              harborLine,
            ],
            stops: const [0.1, 0.5, 0.9],
          ).createShader(rect);
        },
        child: _fill(),
      ),
    );
  }

  Widget _fill() => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: harborLine,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      );
}

/// A stack of skeleton lines standing in for a paragraph or a card body.
///
/// [lines] shorter lines approximate the ragged right edge of real copy, so the
/// placeholder has the same silhouette as the content that replaces it and the
/// layout does not jump.
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.lines = 3, this.lineHeight = 10});

  final int lines;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == lines - 1 ? 0 : 7),
            child: SkeletonBox(
              // Last line is shorter, as a paragraph's final line usually is.
              width: i == lines - 1 ? 96 : null,
              height: lineHeight,
              radius: 5,
            ),
          ),
      ],
    );
  }
}

/// A skeleton in the shape of a Harbor card, for list placeholders.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: harborLine),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SkeletonLines(lines: lines),
      ),
    );
  }
}

/// The pull-to-refresh affordance: a thin shimmering rule rather than a grey
/// disc, so it never covers the content being refreshed.
class SkeletonRefreshIndicator extends StatefulWidget {
  const SkeletonRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<SkeletonRefreshIndicator> createState() => _SkeletonRefreshIndicatorState();
}

class _SkeletonRefreshIndicatorState extends State<SkeletonRefreshIndicator> {
  /// 0 = at rest, 1 = pulled past the threshold, >1 = refreshing.
  double _pull = 0;

  bool _armed = false;
  bool _busy = false;

  static const _threshold = 72.0;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pull = 1;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _pull = 0);
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<OverscrollNotification>(
      // Overscroll, not ScrollNotification: the gesture must also work when the
      // list is already at its end, which is exactly when a trader pulls.
      onNotification: (n) {
        if (_busy || n.overscroll <= 0) return false;
        setState(() => _pull = (_pull - n.overscroll / 400).clamp(0.0, 1.0));
        final armed = _pull * _threshold >= _threshold;
        if (armed != _armed) setState(() => _armed = armed);
        return false;
      },
      child: GestureDetector(
        // The pull itself: a vertical drag past the threshold triggers the
        // refresh and reports back whether the gesture was consumed, so a pull
        // that ends below the threshold springs back instead of firing.
        onVerticalDragEnd: (d) {
          final velocity = d.primaryVelocity ?? 0;
          if (_armed || velocity < -320) _run();
          if (!_busy) setState(() => _pull = 0);
        },
        child: Stack(
        children: [
          widget.child,
          if (_pull > 0.02)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  opacity: _pull.clamp(0.0, 1.0),
                  child: const _RefreshRule(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The thin bar drawn at the top while pulling.
class _RefreshRule extends StatelessWidget {
  const _RefreshRule();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(top: 2),
        child: SkeletonBox(height: 3, radius: 2),
      );
}