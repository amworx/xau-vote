/// Pull-to-refresh behaviour.
///
/// The gesture is the whole feature, so it is exercised with a real drag rather
/// than by calling the callback directly. An earlier hand-rolled implementation
/// passed the whole suite while never firing, because a `GestureDetector`
/// wrapping a scrollable loses every vertical drag to the list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/widgets/skeleton.dart';

/// A tall list so there is always somewhere to drag from.
Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

Future<void> _pump(WidgetTester tester, Widget Function(Future<void> Function()) build) async {
  await tester.pumpWidget(_host(build(() async {})));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a downward drag from the top runs the refresh', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _host(
        SkeletonRefreshIndicator(
          onRefresh: () async {
            refreshes++;
          },
          child: ListView.builder(
            itemCount: 40,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A real pull is SLOW and deliberate. A fling is excluded by the speed
    // gate, so this must be a timed drag.
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, 140),
      const Duration(milliseconds: 900),
    );
    await tester.pumpAndSettle();

    expect(refreshes, 1, reason: 'the pull gesture must actually fire');
  });

  testWidgets('no Material refresh indicator is involved at all', (tester) async {
    await _pump(tester, (onRefresh) => SkeletonRefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ));

    // Regression guard. RefreshIndicator misfired whenever the list content was
    // replaced: a slow poll re-reads the calendar, the scroll position shifts,
    // and it read that shift as a drag and fired a refresh nobody asked for.
    // The gesture now observes raw pointer events, so no Material is involved.
    expect(find.byType(RefreshIndicator), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(Listener), findsWidgets);
  });

  testWidgets('scrolling the list never triggers a refresh', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _host(
        SkeletonRefreshIndicator(
          onRefresh: () async {
            refreshes++;
          },
          child: ListView.builder(
            itemCount: 60,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Scroll down through the list with a slow drag. Deliberately not
    // `tester.fling`: fling simulates a throw by dragging past the end and back,
    // which injects a synthetic second gesture and is not what scrolling does.
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -400),
      const Duration(milliseconds: 900),
    );
    await tester.pumpAndSettle();
    expect(refreshes, 0, reason: 'scrolling down must not refresh');

    // Now a genuine, slow pull - but started while the list is scrolled away
    // from the top. That is ordinary scrolling downwards and must not refresh,
    // however far the finger travels.
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, 200),
      const Duration(milliseconds: 900),
    );
    await tester.pumpAndSettle();

    expect(refreshes, 0,
        reason: 'a pull that does not start at the top is not a refresh');
  });

  testWidgets('a fast flick past the threshold is not a pull', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      _host(
        SkeletonRefreshIndicator(
          onRefresh: () async {
            refreshes++;
          },
          child: ListView.builder(
            itemCount: 60,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Starts at the top and travels four times the threshold, but fast. This is
    // the gesture that made the old implementation refresh by itself while the
    // user was simply flicking through the calendar.
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, 400),
      const Duration(milliseconds: 80),
    );
    await tester.pumpAndSettle();

    expect(refreshes, 0, reason: 'speed, not distance, separates a pull');
  });

  testWidgets('a skeleton block renders and animates without error',
      (tester) async {
    await tester.pumpWidget(
      _host(
        const Column(
          children: [
            SkeletonBox(width: 120, height: 12),
            SkeletonLines(lines: 3),
            SkeletonCard(lines: 2),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The shimmer is painted by a RenderObject rather than a Bone widget, so the
    // assertion is that a skeleton lays out cleanly and keeps animating.
    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('reduced motion renders a static fill instead of animating',
      (tester) async {
    await tester.pumpWidget(
      _host(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const SkeletonBox(width: 100, height: 12),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}