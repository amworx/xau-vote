/// Skeleton loading surfaces, built on **skeletonizer** (pub.dev/packages/skeletonizer).
///
/// # Why the package rather than hand-written placeholders
///
/// A hand-written skeleton screen is a second layout of the same screen, and it
/// silently drifts: the real card gains a row, the skeleton does not, and the
/// placeholder stops resembling what it stands for. Skeletonizer converts the
/// real widget tree into a skeleton, so the two cannot disagree.
///
/// Two earlier hand-rolled attempts are why this exists:
/// * a `GestureDetector` wrapping a scrollable loses every vertical drag to the
///   list, so the pull gesture never fired;
/// * `RefreshIndicator` made transparent still painted a grey disc, because it
///   is a Material with elevation and the shadow shows through.
///
/// So the gesture is derived from scroll notifications, and the shimmer is
/// `ShimmerEffect` applied to `Bone` widgets.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../theme.dart';

/// The app's shimmer: a slow, low-contrast sweep in the Harbor palette.
///
/// Slower and softer than a typical shimmer because this is a trading app read
/// in glances, not a web page waited on - a fast flash reads as an alert.
const _shimmer = ShimmerEffect(
  baseColor: harborLine,
  highlightColor: Color(0xFFF1F4F9),
  // A slow left-to-right sweep: this app is read in glances, not waited on, and
  // a fast flash reads as an alert rather than as loading.
  begin: AlignmentDirectional(-1.0, 0),
  end: AlignmentDirectional(1.0, 0),
  duration: Duration(milliseconds: 1400),
);

/// A single shimmering placeholder block.
class SkeletonBox extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // Its own Skeletonizer rather than Skeletonizer.zone: a Bone is only shaded
    // inside an ENABLED skeletonizer, and a bare zone renders nothing. Each box
    // owning one is slightly more animations than ideal, but it keeps the
    // primitive usable anywhere without the caller having to wrap a subtree.
    return Skeletonizer(
      enabled: true,
      effect: _shimmer,
      child: Bone(
        width: width ?? double.infinity,
        height: height,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Fully-rounded pill, for chips and short labels.
class SkeletonPill extends StatelessWidget {
  const SkeletonPill({super.key, this.width = 54, this.height = 16});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: width, height: height, radius: height / 2);
}

/// Rounded square, for an icon-sized placeholder.
class SkeletonSquare extends StatelessWidget {
  const SkeletonSquare({super.key, this.size = 18, this.radius = 6});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: radius);
}

/// Circle, for a flag or an avatar.
class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) =>
      SkeletonBox(width: size, height: size, radius: size / 2);
}

/// Horizontal pill row matching a meta line: circle, short pills, trailing bar.
class SkeletonMetaRow extends StatelessWidget {
  const SkeletonMetaRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SkeletonCircle(size: 14),
        SizedBox(width: 7),
        SkeletonPill(width: 34, height: 12),
        SizedBox(width: 7),
        SkeletonPill(width: 40, height: 12),
        SizedBox(width: 7),
        SkeletonBox(width: 70, height: 11, radius: 5),
      ],
    );
  }
}

/// A stack of bones standing in for a paragraph.
///
/// The final line is short, as a paragraph's last line usually is, so the
/// placeholder has the same silhouette as the copy that replaces it and the
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

/// A generic stack of card placeholders, for lists that are not the Events
/// screen (History, Sources).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (var i = 0; i < count; i++)
            SkeletonCard(lines: i.isEven ? 3 : 2),
        ],
      );
}

/// Placeholder shaped like a real Events row.
///
/// This mirrors `_EventRow`'s structure - impact chip, two title lines of
/// different widths, a meta pill row, then a wider outlook block - rather than
/// being three generic bars. A placeholder that does not resemble the content
/// it stands in for is what makes a loading state look broken.
class SkeletonEventRow extends StatelessWidget {
  const SkeletonEventRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: harborLine),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Impact chip + its leading colour bar.
            const Row(
              children: [
                SkeletonBox(width: 4, height: 14, radius: 2),
                SizedBox(width: 7),
                SkeletonPill(width: 40, height: 14),
              ],
            ),
            const SizedBox(height: 11),
            // Title: two lines, the second shorter, as real titles wrap.
            const SkeletonBox(height: 12),
            const SizedBox(height: 7),
            const SkeletonBox(width: 168, height: 12),
            const SizedBox(height: 9),
            const SkeletonMetaRow(),
            const SizedBox(height: 12),
            // Outlook block.
            const SkeletonBox(height: 34, radius: 10),
            const SizedBox(height: 11),
            const SkeletonBox(width: 220, height: 9, radius: 4),
          ],
        ),
      ),
    );
  }
}

/// A stack of event-row placeholders.
class SkeletonEventList extends StatelessWidget {
  const SkeletonEventList({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) => Column(
        children: [for (var i = 0; i < count; i++) const SkeletonEventRow()],
      );
}

/// Wraps real content so it renders as a skeleton while [loading].
///
/// Preferred over [SkeletonCard] wherever the real widget is available: the
/// placeholder is then the genuine layout, tinted, rather than a guess at it.
class Skeletonize extends StatelessWidget {
  const Skeletonize({super.key, required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) => Skeletonizer(
        // A slow fade between states stops the switch from snapping.
        enableSwitchAnimation: true,
        effect: _shimmer,
        // Containers are kept so cards keep their silhouette; only their fill
        // is replaced.
        ignoreContainers: false,
        enabled: loading,
        child: child,
      );
}

/// The pull-to-refresh affordance: a thin shimmering rule at the top edge.
///
/// It never covers the content being refreshed, and there is no grey spinner
/// disc anywhere.
class SkeletonRefreshIndicator extends StatefulWidget {
  const SkeletonRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<SkeletonRefreshIndicator> createState() =>
      _SkeletonRefreshIndicatorState();
}

class _SkeletonRefreshIndicatorState extends State<SkeletonRefreshIndicator> {
  /// Logical pixels pulled past the top, capped for the opacity ramp.
  double _pulled = 0;

  bool _busy = false;

  /// Pull distance for a full-strength reveal, and the trigger threshold.
  static const _threshold = 90.0;

  /// Whether the user is currently dragging downwards at the top.
  bool _draggingDown = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _pulled = _threshold;
    });
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _pulled = 0);
      _draggingDown = false;
      _busy = false;
    }
  }

  bool _handle(ScrollNotification n) {
    if (_busy) return false;

    if (n is UserScrollNotification) {
      // forward == dragging the content downward, i.e. towards the top.
      _draggingDown = n.direction == ScrollDirection.forward;
      return false;
    }

    if (n is ScrollUpdateNotification) {
      // At the very top only. Without this an ordinary downward scroll would
      // trigger a refresh.
      if (_draggingDown && n.metrics.pixels <= 0) {
        final delta = (n.scrollDelta ?? 0).abs();
        if (delta > 0) {
          setState(() {
            _pulled = (_pulled + delta).clamp(0.0, _threshold);
          });
        }
      }
      return false;
    }

    // Clamping scroll physics DISCARDS the overscroll delta, so
    // ScrollUpdateNotification can arrive with zero. `overscroll` is the
    // un-applied amount, which is the only reliable measure of the pull.
    if (n is OverscrollNotification) {
      if (n.overscroll > 0 && _draggingDown && !_busy) {
        setState(() {
          _pulled = (_pulled + n.overscroll).clamp(0.0, _threshold);
        });
      } else if (n.overscroll < 0 && !_busy) {
        setState(() => _pulled = 0);
      }
      return false;
    }

    if (n is ScrollEndNotification) {
      final trigger = _pulled >= _threshold;
      setState(() => _pulled = 0);
      _draggingDown = false;
      if (trigger) _run();
      return false;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handle,
      child: Stack(
        children: [
          // RefreshIndicator is kept purely for its GESTURE, and made entirely
          // invisible: `displacement: 0` is the important part, because
          // RefreshIndicator builds a Material whose ELEVATION scales with
          // displacement — that elevation is what painted the grey disc, and it
          // shows through even with fully transparent colours.
          //
          // A hand-rolled gesture cannot replace it: a GestureDetector wrapping
          // a scrollable loses every vertical drag to the list, and the
          // scroll-notification route is defeated by ClampingScrollPhysics
          // discarding the overscroll delta.
          RefreshIndicator(
            onRefresh: _run,
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            // elevation 0 is what actually removes the grey disc. It is a
            // separate parameter from displacement, and it defaults to 2.0 -
            // so the indicator's Material casts a shadow that shows through
            // even with fully transparent colours.
            elevation: 0,
            displacement: 0,
            child: widget.child,
          ),
          if (_pulled > 2)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Opacity(
                  // Fades in over the first stretch of the pull, so a small
                  // accidental drag does not flash a bar.
                  opacity: (_pulled / (_threshold * 0.4)).clamp(0.0, 1.0),
                  child: const _RefreshRule(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The shimmering bar drawn at the top while pulling.
class _RefreshRule extends StatelessWidget {
  const _RefreshRule();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 3, horizontal: 18),
        child: SkeletonBox(height: 3, radius: 2),
      );
}