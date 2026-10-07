/// Events list placeholders during a deliberate refresh.
///
/// The refresh finishes in about a second on a real device, far too fast to
/// photograph reliably, so the behaviour is pinned here instead: a controlled
/// refresh that is held open must show shaped skeleton rows, and the real rows
/// must come back when it completes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xauvote/data/live_data.dart';
import 'package:xauvote/data/live_repository.dart';
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/screens/events_screen.dart';
import 'package:xauvote/widgets/skeleton.dart';

const _event = DisplayEvent(
  id: 'e1',
  title: 'CPI m/m',
  currency: 'USD',
  impact: EventImpact.high,
  startsIn: Duration(days: 7),
);

/// Wraps [EventsScreen] above a snapshot whose refresh can be held open.
Future<LiveData> _pumpEvents(
  WidgetTester tester, {
  required List<DisplayEvent> events,
  Completer<void>? gate,
}) async {
  final live = LiveData(
    repository: _SlowRepository(events: events, gate: gate),
  );
  addTearDown(live.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<LiveData>.value(
      value: live,
      child: const MaterialApp(home: Scaffold(body: EventsScreen())),
    ),
  );
  await live.refresh();
  await tester.pump();
  return live;
}

// Skeletonizer replaces its child with a render object, so it cannot be found
// by type. Matching on the runtime type name is the stable way to assert it.
Finder skeletonizerInTree() => find.byWidgetPredicate(
      (w) => w.runtimeType.toString().contains('Skeletonizer'),
      description: 'a Skeletonizer in the tree',
    );

void main() {
  testWidgets('real rows are shown when idle', (tester) async {
    await _pumpEvents(tester, events: const [_event]);

    expect(find.text('CPI m/m'), findsWidgets);
    expect(find.byType(SkeletonEventRow), findsNothing);
  });

  testWidgets('a held refresh turns the real rows into bones in place',
      (tester) async {
    final gate = Completer<void>();
    final live = await _pumpEvents(
      tester,
      events: const [_event],
      gate: gate,
    );

    // Start a deliberate pull and leave it in flight.
    final refreshing = live.refresh();
    await tester.pump();

    expect(live.refreshing, isTrue,
        reason: 'a manual refresh must announce itself');
    // The skeletonizer wraps the REAL pane, so the real rows are still mounted
    // and the placeholder subtree is never swapped in.
    expect(skeletonizerInTree(), findsWidgets);
    expect(find.text('CPI m/m'), findsNWidgets(2),
        reason: 'the real rows must stay mounted - swapping in a placeholder '
            'subtree painted a full-width grey rectangle for a frame');
    expect(find.byType(SkeletonEventRow), findsNothing,
        reason: 'placeholder rows are no longer used during a pull');

    gate.complete();
    await refreshing;
    await tester.pump();

    expect(live.refreshing, isFalse);
// Both the blackout card and the row carry the title, so it appears twice.
    expect(find.text('CPI m/m'), findsNWidgets(2));
  });

  testWidgets('the top blackout card refreshes too', (tester) async {
    // Regression: the blackout card sits above the list, so a swap that only
    // covered the rows left the first item on screen looking untouched.
    final gate = Completer<void>();
    final live = await _pumpEvents(
      tester,
      events: const [_event],
      gate: gate,
    );

    final refreshing = live.refresh();
    await tester.pump();

    expect(skeletonizerInTree(), findsWidgets);
    // The blackout card AND the rows are covered, so the first item on
    // screen refreshes with the rest rather than looking untouched.
    expect(find.text('CPI m/m'), findsNWidgets(2),
        reason: 'both the blackout card and the row are inside the skeleton');

    gate.complete();
    await refreshing;
    await tester.pump();
  });

  testWidgets('skeletons are not shown by a background poll', (tester) async {
    // Regression guard: if polling also set `refreshing`, the list would strobe
    // skeletons every 15 seconds.
    final live = await _pumpEvents(tester, events: const [_event]);

    expect(live.loading, isFalse);
    expect(live.refreshing, isFalse);
    expect(find.byType(SkeletonEventRow), findsNothing);
  });
}

/// Repository that returns events, blocking on [gate] when one is supplied.
///
/// Every read `LiveData.refresh` performs is implemented, returning the honest
/// empty answer. A `noSuchMethod` that throws would abort the whole refresh
/// before the events were ever assigned, which is a test-fixture failure that
/// looks exactly like a product bug.
class _SlowRepository implements LiveRepository {
  _SlowRepository({required this.events, this.gate});

  final List<DisplayEvent> events;
  final Completer<void>? gate;

  /// The first read is the initial load and must NOT block, otherwise awaiting
  /// it before the test starts would deadlock against its own gate.
  int _calls = 0;

  @override
  Future<List<DisplayEvent>> upcomingEvents({int limit = 20}) async {
    _calls++;
    final g = gate;
    if (g != null && _calls > 1 && !g.isCompleted) await g.future;
    return events;
  }

  @override
  Future<({double price, DateTime at})?> latestPrice() async => null;

  @override
  Future<({double? price, DateTime? at, bool live})> directSpotPrice({
    Duration timeout = const Duration(seconds: 12),
  }) async =>
      (price: null, at: null, live: false);
  @override
  Future<({double low, double high})?> sessionRange({required DateTime since}) async => null;

  @override
  Future<List<({DateTime at, double price})>> sessionPrices({
    required DateTime since,
  }) async => const [];

  @override
  Future<double?> previousClose({required DateTime sessionStart}) async => null;

  @override
  Future<({double? low, double? high, double? firstPrint, double? prevClose})>
      sessionStats({required DateTime since}) async =>
          (low: null, high: null, firstPrint: null, prevClose: null);

  /// No active signal, so the independence and contributor reads are never
  /// reached.
  @override
  Future<DisplaySignal?> activeSignal() async => null;

  @override
  Future<List<GoldHuntsSessionView>> goldHuntsSessionViews({int limit = 10}) async => const [];

  @override
  Future<List<DisplayHistoryEntry>> history({int limit = 50}) async => const [];

  @override
  Future<List<DisplayDigestTheme>> latestDigest() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}