/// The pill bottom bar's geometry contract.
///
/// WHY THESE ASSERTIONS EXIST
/// The bar gives the active tab a WIDER slot than the others so its label fits
/// (the reference component is content-sized and overflowed at every phone
/// width). That extra width is exactly the thing that can drift: the icon+label
/// group has to stay centred inside it. It was once aligned `centerLeft` so the
/// label would clip on the right during the animation, which left the group
/// hugging the leading edge of the wide active slot - wrong, and invisible to a
/// test that only checked the label was findable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xauvote/main.dart';

/// Pumps the real bar at a given logical width.
Future<void> _pumpBar(
  WidgetTester tester,
  int width, {
  int selected = 0,
  ValueChanged<int>? onSelected,
}) async {
  tester.view.physicalSize = Size(width.toDouble(), 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: const SizedBox(),
        bottomNavigationBar: HarborNavBar(
          selectedIndex: selected,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Centre of the icon+label group, and of the tab it sits in.
({double group, double slot}) _centres(WidgetTester tester, String label) {
  final slotFinder = find.byKey(ValueKey('nav-$label'));
  final slotCentre = tester.getRect(slotFinder).center.dx;

  // The group is the Row inside the item's Stack; find it via the icon so the
  // measurement does not depend on the label being present.
  final row = find.descendant(
    of: slotFinder,
    matching: find.byType(Row),
  );
  final groupCentre = tester.getRect(row.first).center.dx;
  return (group: groupCentre, slot: slotCentre);
}

void main() {
  testWidgets('the active tab centres its icon and label', (tester) async {
    // "SOURCES" is active: a long-ish label in a slot noticeably wider than
    // the others, which is the case that exposed the left-alignment.
    await _pumpBar(tester, 393, selected: 2);

    final c = _centres(tester, 'SOURCES');
    expect(
      (c.group - c.slot).abs(),
      lessThan(1.0),
      reason: 'the icon+label group must be centred in the active tab',
    );
  });

  testWidgets('every tab centres its icon, active or not', (tester) async {
    await _pumpBar(tester, 393, selected: 5);

    for (final label in const [
      'RADAR',
      'SIGNAL',
      'SOURCES',
      'HISTORY',
      'EVENTS',
      'SETTINGS',
    ]) {
      final c = _centres(tester, label);
      expect(
        (c.group - c.slot).abs(),
        lessThan(1.0),
        reason: '$label must be centred in its own tab',
      );
    }
  });

  testWidgets('the label is never clipped by the tab it sits in', (tester) async {
    // The whole reason the active slot is wider: every label has to fit when
    // its own tab is the active one.
    const labels = [
      'RADAR',
      'SIGNAL',
      'SOURCES',
      'HISTORY',
      'EVENTS',
      'SETTINGS',
    ];
    for (final width in const [412, 393, 375, 360]) {
      for (var i = 0; i < labels.length; i++) {
        await _pumpBar(tester, width, selected: i);

        final slot = tester.getRect(find.byKey(ValueKey('nav-${labels[i]}'))).width;
        final label = tester.getRect(find.text(labels[i]));
        expect(
          label.width,
          lessThanOrEqualTo(slot - 22 - 6 + 0.5),
          reason: '${labels[i]} must fit its own slot at ${width}dp',
        );
      }
    }
  });

  testWidgets('the bar reports the tapped tab', (tester) async {
    int? picked;
    await _pumpBar(tester, 393, selected: 0, onSelected: (i) => picked = i);

    await tester.tap(find.byKey(const ValueKey('nav-EVENTS')));
    await tester.pumpAndSettle();

    expect(picked, 4);
  });

  testWidgets('only the active tab renders its label', (tester) async {
    await _pumpBar(tester, 393, selected: 1);

    expect(find.text('SIGNAL'), findsOneWidget);
    expect(find.text('RADAR'), findsNothing);
    expect(find.text('SETTINGS'), findsNothing);
  });

  testWidgets('switching tabs settles without overflowing', (tester) async {
    await _pumpBar(tester, 360, selected: 0);
    expect(tester.takeException(), isNull);

    for (final index in [5, 0, 4, 2]) {
      await _pumpBar(tester, 360, selected: index);
      expect(
        tester.takeException(),
        isNull,
        reason: 'tab $index must lay out cleanly at 360dp',
      );
    }
  });
}