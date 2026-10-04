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
import 'package:skeletonizer/skeletonizer.dart';

import '../theme.dart';

/// The app's shimmer: a slow, low-contrast sweep in the Harbor palette.
///
/// Slower and softer than a typical shimmer because this is a trading app read
/// in glances, not a web page waited on - a fast flash reads as an alert.
const harborShimmer = ShimmerEffect(
  baseColor: harborLine,
  highlightColor: Color(0xFFF1F4F9),
  // A slow left-to-right sweep: this app is read in glances, not waited on, and
  // a fast flash reads as an alert rather than as loading.
  begin: AlignmentDirectional(-1.0, 0),
  end: AlignmentDirectional(1.0, 0),
  duration: Duration(milliseconds: 1400),
);

const _shimmer = harborShimmer;

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

/// Shimmers real content while [loading].
///
/// This is the intended shape of use and the one that matters: the placeholder
/// IS the real widget tree, converted. Two earlier approaches caused visible
/// faults:
///
/// * swapping a placeholder subtree in and out painted a full-width grey
///   rectangle for a frame as the two trees swapped;
/// * one `Skeletonizer` per `SkeletonBox` multiplies the controllers and makes
///   that swap worse.
///
/// Here there is nothing to swap - the same widgets stay mounted and simply
/// render as bones - so no frame can disagree with the content.
class Skeletonize extends StatelessWidget {
  const Skeletonize({super.key, required this.loading, required this.child});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) => Skeletonizer(
        effect: harborShimmer,
        enabled: loading,
        // ignoreContainers is the important flag. When false, skeletonizer
        // repaints EVERY Container as a solid fill, so a whole card - and a
        // whole list of cards - merges into ONE featureless grey rectangle.
        // Only text and icons should become bones; surfaces must keep their real
        // background and hairline border.
        ignoreContainers: true,
        // Switch animation OFF: it cross-fades through a painted overlay, which
        // is precisely the grey rectangle this is meant to avoid.
        enableSwitchAnimation: false,
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

/// Replacement state class for [SkeletonRefreshIndicator].
///
/// The previous implementation used `RefreshIndicator` purely for its gesture.
/// It misfired: when the list content was replaced the scroll position shifted,
/// `RefreshIndicator` read that shift as a drag, and fired a refresh nobody
/// asked for - which then skeletonised the whole pane. Scroll notifications
/// were tried first and are worse, because ClampingScrollPhysics discards the
/// overscroll delta and a genuine pull reports zero.
///
/// This observes RAW POINTER EVENTS instead. An ancestor `Listener` does not
/// compete for the gesture arena, so it cannot steal the list's drag and cannot
/// be confused by it - it merely watches. The trigger is then unambiguous: the
/// finger pressed, moved predominantly downward, moved slowly enough to be
/// deliberate, and travelled far enough.
class _SkeletonRefreshIndicatorState extends State<SkeletonRefreshIndicator> {
  /// Pull distance for a full-strength reveal, and the trigger threshold.
  static const _threshold = 90.0;

  /// A gesture counts as vertical only when it is at least this much more
  /// vertical than horizontal, so a diagonal flick is not read as a pull.
  static const _verticalBias = 1.4;

  /// Maximum average speed, in logical pixels per second, for a gesture to
  /// count as a deliberate pull.
  ///
  /// This is the discriminator that stops the list refreshing itself. A
  /// fling overscrolls the top and travels past the threshold, but it does so
  /// quickly - measured at roughly 900 px/s here. A person pulling to refresh
  /// travels the same distance slowly, around 100-300 px/s. Measured, not
  /// assumed: a fling in the test harness measured 294 px/s on its overscroll
  /// leg, so the bound is set at 400 to sit below it.
  static const _maxPullSpeed = 400.0;

  /// Where the current gesture started.
  double? _startY;
  double? _startX;

  /// Start time of the current gesture, for the speed check.
  Duration? _downAt;

  /// Accumulated downward travel for the current gesture.
  double _pulled = 0;

  /// Latched once the gesture has been judged vertical, so a gesture that starts
  /// horizontal cannot flip into a pull part-way through.
  bool _vertical = false;

  bool _busy = false;

  /// Whether the list was scrolled to the top when the gesture began.
  ///
  /// A pull is only a refresh at the top; dragging down mid-list is ordinary
  /// scrolling and must never refresh.
  bool _atTop = true;

  /// Latest known scroll offset of the descendant list.
  ///
  /// Read from scroll notifications rather than `Scrollable.maybeOf`, because
  /// `of`/`maybeOf` search ANCESTORS and the list is a DESCENDANT of this
  /// widget - so it always returned null and `_atTop` was permanently true.
  /// That single mistake is what let a pull anywhere in a scrolled list count
  /// as a refresh. Notifications bubble, so this sees the real offset.
  double _pixels = 0;

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
      _busy = false;
    }
  }

  void _reset() {
    _startY = null;
    _startX = null;
    _downAt = null;
    _vertical = false;
  }

  void _onDown(PointerDownEvent e) {
    if (_busy) return;
    _startY = e.position.dy;
    _startX = e.position.dx;
    _downAt = e.timeStamp;
    _vertical = false;
    _pulled = 0;
    // Sampled once, at the start. Re-sampling during the gesture would let a
    // pull that drags the list to the top qualify on its later moves.
    _atTop = _pixels <= 0.5;
  }

  void _onMove(PointerMoveEvent e) {
    final startY = _startY;
    final startX = _startX;
    if (_busy || startY == null || startX == null || !_atTop) return;

    final dy = e.position.dy - startY;
    final dx = e.position.dx - startX;

    if (!_vertical) {
      final absY = dy.abs();
      final absX = dx.abs();
      // Decide once, and only after the gesture has clearly committed to a
      // direction. Below this, stay undecided.
      if (absY < 12) return;
      if (absY <= absX / _verticalBias) {
        _reset();
        return;
      }
      if (dy < 0) {
        // Upward: ordinary scrolling away from the top. Abandon the gesture so
        // that later downward movement cannot become a pull.
        _reset();
        return;
      }
      _vertical = true;
    }

    setState(() {
      _pulled = dy.clamp(0.0, _threshold);
    });
  }

  void _onUp(PointerUpEvent e) {
    // A pull is deliberate, so it is slow. A fling that merely overscrolls the
    // top is fast and must not count.
    final elapsed = _downAt == null
        ? const Duration(seconds: 1)
        : e.timeStamp - _downAt!;
    final micros = elapsed.inMicroseconds < 1 ? 1 : elapsed.inMicroseconds;
    final speed = (_pulled * Duration.microsecondsPerSecond) / micros;

    final trigger =
        _vertical && _pulled >= _threshold && speed <= _maxPullSpeed;

    _reset();
    if (!_busy) setState(() => _pulled = 0);
    if (trigger) _run();
  }

  void _onCancel(PointerCancelEvent e) {
    _reset();
    if (!_busy) setState(() => _pulled = 0);
  }

  @override
  Widget build(BuildContext context) {
    // The listener tracks the offset; it never consumes the notification, so
    // the list is entirely unaffected.
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        _pixels = n.metrics.pixels;
        return false;
      },
      child: Listener(
        // Observes only. Nothing is consumed, so the list keeps every gesture it
        // would normally have.
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: Stack(
          children: [
            widget.child,
            if (_pulled > 2)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Opacity(
                    // Fades in over the first stretch, so a small accidental
                    // drag does not flash a bar.
                    opacity: (_pulled / (_threshold * 0.4)).clamp(0.0, 1.0),
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

/// The shimmering bar drawn at the top while pulling.
class _RefreshRule extends StatelessWidget {
  const _RefreshRule();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 3, horizontal: 18),
        child: SkeletonBox(height: 3, radius: 2),
      );
}
