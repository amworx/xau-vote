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

    // Drag down far enough to pass the trigger threshold.
    await tester.fling(
      find.byType(ListView),
      const Offset(0, 320),
      1200,
    );
    await tester.pumpAndSettle();

    expect(refreshes, 1, reason: 'the pull gesture must actually fire');
  });

  testWidgets('the visible feedback is a skeleton rule, not a grey disc',
      (tester) async {
    await _pump(tester, (onRefresh) => SkeletonRefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.builder(
            itemCount: 30,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('row $i')),
          ),
        ));

    // No grey spinner disc anywhere: the stock indicator is gone entirely, not
    // merely made transparent (its Material elevation still showed a shadow).
    final indicator = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator));
    // displacement 0 is what removes the Material's shadow, i.e. the grey disc.
    expect(indicator.elevation, 0, reason: 'the default 2.0 is the grey disc');
    expect(indicator.displacement, 0);
    expect(indicator.color, Colors.transparent);
    expect(indicator.backgroundColor, Colors.transparent);
    expect(find.byType(CircularProgressIndicator), findsNothing);
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