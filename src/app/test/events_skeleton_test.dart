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

void main() {
  testWidgets('real rows are shown when idle', (tester) async {
    await _pumpEvents(tester, events: const [_event]);

    expect(find.text('CPI m/m'), findsWidgets);
    expect(find.byType(SkeletonEventRow), findsNothing);
  });

  testWidgets('a held refresh replaces the rows with shaped skeletons',
      (tester) async {
    final gate = Completer<void>();
    final live = await _pumpEvents(
      tester,
      events: const [_event],
      gate: gate,
    );
    expect(find.byType(SkeletonEventRow), findsNothing);

    // Start a deliberate pull and leave it in flight.
    final refreshing = live.refresh();
    await tester.pump();

    expect(live.refreshing, isTrue,
        reason: 'a manual refresh must announce itself');
    expect(find.byType(SkeletonEventRow), findsOneWidget);
    // The shaped primitives are in use, not generic grey bars.
    expect(find.byType(SkeletonPill), findsWidgets);
    expect(find.byType(SkeletonMetaRow), findsOneWidget);

    gate.complete();
    await refreshing;
    await tester.pump();

    expect(live.refreshing, isFalse);
    expect(find.byType(SkeletonEventRow), findsNothing);
    expect(find.text('CPI m/m'), findsWidgets);
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
  Future<({double low, double high})?> sessionRange() async => null;

  /// No active signal, so the independence and contributor reads are never
  /// reached.
  @override
  Future<DisplaySignal?> activeSignal() async => null;

  @override
  Future<List<DisplayHistoryEntry>> history({int limit = 50}) async => const [];

  @override
  Future<List<DisplayDigestTheme>> latestDigest() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed here');
}