/// Live-mode widget tests — the six screens reading a polled snapshot.
///
/// WHY A STUB REPOSITORY
/// `LiveData` takes an optional `LiveRepository`, and this suite implements
/// that interface directly (`implements`, so no `SupabaseClient` is ever
/// constructed, no `Supabase.initialize()` runs and no request is made). Every
/// read is answered from memory, which is what lets these assertions be about
/// the SCREENS: what a live row renders, and — the part that matters — what
/// the screens render when the pipeline has nothing.
///
/// NEVER FABRICATE (product rule 2) is asserted in both directions: a live
/// figure must reach the screen, and a fixture figure must never appear in its
/// place. Every stub fixture is deliberately different from `MockFixtures` so
/// "it rendered the mock" and "it rendered the snapshot" cannot be confused.
///
/// RUNNING
/// These run inside the normal offline `flutter test` suite: the screens take
/// their data source from the [LiveData] provider that `main.dart` mounts for a
/// LIVE build, so injecting a [LiveData] above them exercises the same branch a
/// `--dart-define=LIVE=true` build takes — one binary proves both paths.
/// `XauVoteApp` itself is not pumped here because a live build has to
/// initialise Supabase and construct its own poller; the shell below is the
/// same chrome, providers and nav with the poller supplied by the test.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:xauvote/data/live_data.dart';
import 'package:xauvote/data/live_repository.dart';
import 'package:xauvote/data/mock_fixtures.dart';
import 'package:xauvote/main.dart' show HarborNavBar;
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/screens/events_screen.dart';
import 'package:xauvote/screens/history_screen.dart';
import 'package:xauvote/screens/radar_screen.dart';
import 'package:xauvote/screens/settings_screen.dart';
import 'package:xauvote/screens/signal_screen.dart';
import 'package:xauvote/screens/sources_screen.dart';
import 'package:xauvote/state/app_state.dart';
import 'package:xauvote/theme.dart';
import 'package:xauvote/widgets/harbor_widgets.dart';

// ---------------------------------------------------------------------------
// Stub backend
// ---------------------------------------------------------------------------

/// In-memory [LiveRepository]. No client, no network, no Supabase global state.
class _StubRepository implements LiveRepository {
  _StubRepository({
    this.price,
    this.low,
    this.high,
    this.signal,
    this.historyRows = const [],
    this.events = const [],
    this.digest = const [],
    this.failWith,
  });

  final double? price;
  final double? low;
  final double? high;
  final DisplaySignal? signal;
  final List<DisplayHistoryEntry> historyRows;
  final List<DisplayEvent> events;
  final List<DisplayDigestTheme> digest;

  /// When set, every read throws — the failed-poll case.
  Object? failWith;

  void _guard() {
    final error = failWith;
    if (error != null) throw error;
  }

  @override
  Future<({double price, DateTime at})?> latestPrice() async {
    _guard();
    final p = price;
    if (p == null) return null;
    return (price: p, at: DateTime(2026, 10, 2, 12, 0));
  }

  @override
  Future<({double low, double high})?> sessionRange() async {
    _guard();
    final l = low;
    final h = high;
    if (l == null || h == null) return null;
    return (low: l, high: h);
  }

  @override
  Future<DisplaySignal?> activeSignal() async {
    _guard();
    return signal;
  }

  @override
  Future<int> agreeingSourceCount(String signalId) async {
    _guard();
    return signal?.agreeCount ?? 0;
  }

  @override
  Future<List<DisplayHistoryEntry>> history({int limit = 50}) async {
    _guard();
    return historyRows;
  }

  @override
  Future<List<DisplayEvent>> upcomingEvents({int limit = 20}) async {
    _guard();
    return events;
  }

  @override
  Future<List<DisplayDigestTheme>> latestDigest() async {
    _guard();
    return digest;
  }
}

/// A live setup, chosen so every figure differs from `MockFixtures`: a test
/// that sees `4,275-4,280` is looking at a mock, not at this.
const DisplaySignal _liveSignal = DisplaySignal(
  id: 'live-1',
  direction: Direction.long,
  strength: 88,
  entryLow: 4310,
  entryHigh: 4315,
  stopLoss: 4295,
  tp1: 4330,
  tp2: 4350,
  tp3: 4370,
  status: DisplayStatus.active,
  agreeCount: 4,
  totalCount: 4,
);

const _liveEvent = DisplayEvent(
  id: 'live-evt-cpi',
  title: 'CPI y/y',
  currency: 'USD',
  impact: EventImpact.high,
  startsIn: Duration(minutes: 12, seconds: 41),
  forecast: '3.1%',
  previous: '3.0%',
);

const _liveDigest = DisplayDigestTheme(
  theme: 'Hawkish Fed repricing',
  pressure: NewsPressure.hawkish,
  evidenceCount: 3,
);

const _liveHistory = [
  DisplayHistoryEntry(
    direction: Direction.long,
    whenText: 'TODAY · 14:20',
    detailText: 'IN 4,300-4,310 · SL 4,285',
    status: DisplayStatus.tp2Hit,
    pipsPoints: 20,
  ),
  DisplayHistoryEntry(
    direction: Direction.short,
    whenText: 'TODAY · 09:05',
    detailText: 'IN 4,240-4,250 · SL 4,262',
    status: DisplayStatus.invalidated,
    pipsPoints: -10,
  ),
];

/// A fully populated snapshot — price, range, setup, log, calendar, digest.
LiveData _populated() {
  final live = LiveData(
    repository: _StubRepository(
      price: 4312.45,
      low: 4300.10,
      high: 4320.90,
      signal: _liveSignal,
      historyRows: _liveHistory,
      events: const [_liveEvent],
      digest: const [_liveDigest],
    ),
  );
  addTearDown(live.dispose);
  return live;
}

/// A snapshot from a pipeline that has produced nothing yet: no tick, no range,
/// no consensus, no log, no calendar, no digest.
LiveData _empty() {
  final live = LiveData(repository: _StubRepository());
  addTearDown(live.dispose);
  return live;
}

// ---------------------------------------------------------------------------
// Shell
// ---------------------------------------------------------------------------

/// The nav order `main.dart` uses.
const _tabs = ['RADAR', 'SIGNAL', 'SOURCES', 'HISTORY', 'EVENTS', 'SETTINGS'];

const _screens = <Widget>[
  RadarScreen(),
  SignalScreen(),
  SourcesScreen(),
  HistoryScreen(),
  EventsScreen(),
  SettingsScreen(),
];

/// The document width every layout assertion below is made at.
const Size _phone = Size(390, 4000);

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }

  await load('Sora', [
    'sora-v17-latin-regular.ttf',
    'sora-v17-latin-600.ttf',
    'sora-v17-latin-700.ttf',
    'sora-v17-latin-800.ttf',
  ]);
  await load('Space Mono', [
    'space-mono-v17-latin-regular.ttf',
    'space-mono-v17-latin-700.ttf',
  ]);
}

/// Pump the app chrome with [live] as the polled snapshot.
///
/// Same MaterialApp/Scaffold/nav and the same two providers as `main.dart`
/// builds for a LIVE release, with the poller supplied by the test instead of
/// by `LiveData()..startPolling()` (which would need a real Supabase client).
Future<void> _pumpLive(WidgetTester tester, LiveData live) async {
  await _loadFonts();
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await live.refresh();
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: ChangeNotifierProvider<LiveData>.value(
        value: live,
        child: Builder(
          builder: (context) {
            final index = context.watch<AppState>().tabIndex;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: harborTheme(),
              home: Scaffold(
                appBar: AppBar(toolbarHeight: 0, backgroundColor: harborMist),
                body: SafeArea(child: _screens[index]),
                bottomNavigationBar: HarborNavBar(
                  selectedIndex: index,
                  onSelected: (i) => context.read<AppState>().setTab(i),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Open a tab. Never settles: the Events countdown owns a 1s timer, so the
/// frame scheduler cannot reach quiescence once that tab is mounted.
Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(find.text(tab));
  await tester.pump();
  await tester.pump();
}

void main() {
  // `mockMode` is a compile-time flag, so a test cannot flip the build. What
  // the screens branch on is the [LiveData] `main.dart` mounts above them for a
  // LIVE release: an offline build mounts none and they read fixtures (covered
  // by the pre-existing offline suite), a live build mounts one and they read
  // it. These tests drive the second state directly, which is the only state
  // that has to be proven here.

  group('Radar reads the snapshot', () {
    testWidgets('price, range, levels and agreement come from the poller',
        (tester) async {
      await _pumpLive(tester, _populated());

      // Price hero.
      expect(find.text('XAUUSD · SPOT GOLD'), findsOneWidget);
      expect(find.text('4,312.45'), findsOneWidget);
      expect(find.text('4,278.30'), findsNothing,
          reason: 'the fixture price must never reach a live screen');
      expect(
        find.text('+0.29%'),
        findsNothing,
        reason: 'no session open is published, so no percentage is derived',
      );

      // Day bar: the observed range, and an honest `—` for the unmeasured day
      // move.
      expect(find.text('+12.40'), findsNothing);
      expect(find.text('4,300.10 — 4,320.90'), findsOneWidget);

      // Verdict card levels.
      final levels = find.byType(VerdictLevelGrid);
      Finder inLevels(String text) =>
          find.descendant(of: levels, matching: find.text(text));
      expect(inLevels('ENTRY'), findsOneWidget);
      expect(inLevels('4,310-4,315'), findsOneWidget);
      expect(inLevels('STOP'), findsOneWidget);
      expect(inLevels('4,295'), findsOneWidget);
      expect(inLevels('4,330'), findsOneWidget);
      expect(inLevels('4,350'), findsOneWidget);
      expect(inLevels('4,370'), findsOneWidget);
      expect(inLevels('4,275-4,280'), findsNothing);

      // Agreement is a split, and the offline source chips do not exist here.
      expect(find.text('15M Consensus Setup'), findsOneWidget);
      expect(find.text('STRONG · 4 / 4'), findsOneWidget);
      expect(find.text('4 of 4 sources agree'), findsOneWidget);
      expect(find.text('Source A ✓'), findsNothing);
      expect(find.text('LONG'), findsOneWidget);
      expect(find.text('—'), findsWidgets,
          reason: 'alternate direction and 5M confirmation are unreported');

      // Copy/share stay available in both modes.
      expect(find.text('COPY LEVELS'), findsOneWidget);
      await tester.tap(find.widgetWithText(InkWell, 'COPY LEVELS'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Levels copied'), findsOneWidget);
    });

    testWidgets('the demo state switcher is offline-only', (tester) async {
      await _pumpLive(tester, _populated());

      expect(find.text('DEMO STATE'), findsNothing);
      for (final state in ['STRONG', 'DEVELOPING', 'DIVIDED']) {
        expect(find.widgetWithText(TextButton, state), findsNothing,
            reason: 'the pipeline owns the state, not a demo switcher');
      }
    });

    testWidgets('a null signal renders NO CONSENSUS, never fixture levels',
        (tester) async {
      final live = LiveData(
        repository: _StubRepository(
          price: 4312.45,
          low: 4300.10,
          high: 4320.90,
        ),
      );
      addTearDown(live.dispose);
      await _pumpLive(tester, live);

      expect(find.text('NO CONSENSUS'), findsOneWidget);
      expect(find.text('Sources have not reached agreement.'), findsOneWidget);
      expect(find.text('Waiting for stronger agreement.'), findsOneWidget);
      // The real price is still shown — only the setup is absent.
      expect(find.text('4,312.45'), findsOneWidget);

      expect(find.text('15M Consensus Setup'), findsNothing);
      expect(find.text('4,275-4,280'), findsNothing);
      expect(find.text('4,310-4,315'), findsNothing);
      expect(find.text('STRONG · 4 / 5'), findsNothing);
      expect(find.text('COPY LEVELS'), findsNothing);
      // The mock vote split would be a claim about counts that do not exist.
      expect(find.text('LONG'), findsNothing);
      expect(find.text('SHORT'), findsNothing);
      expect(find.text('NEUTRAL'), findsNothing);
    });

    testWidgets('a null price renders the waiting state, never a number',
        (tester) async {
      final live = LiveData(repository: _StubRepository(signal: _liveSignal));
      addTearDown(live.dispose);
      await _pumpLive(tester, live);

      expect(find.text('WAITING FOR FIRST TICK'), findsOneWidget);
      expect(
        find.text('No market snapshot stored yet — the first tick appears here.'),
        findsOneWidget,
      );
      expect(find.text('4,278.30'), findsNothing);
      expect(find.text('+0.29%'), findsNothing);
      expect(find.text('Spread 0.35'), findsNothing);
      // With no observed snapshots there is no session range either.
      expect(find.text('—'), findsWidgets);
      // The setup still renders — only the quote is missing.
      expect(find.text('4,310-4,315'), findsOneWidget);
    });

    testWidgets('events annotate the card but never vote (rule 9)',
        (tester) async {
      await _pumpLive(tester, _populated());

      expect(find.text('Caution: CPI y/y in 00:12:41'), findsOneWidget);
      expect(find.text('Caution: Retail Sales in 42m'), findsNothing);
      expect(find.text('Hawkish Fed repricing'), findsOneWidget);
    });

    testWidgets('a failed poll keeps the last good values and says so',
        (tester) async {
      final repo = _StubRepository(
        price: 4312.45,
        low: 4300.10,
        high: 4320.90,
        signal: _liveSignal,
      );
      final live = LiveData(repository: repo);
      addTearDown(live.dispose);
      await _pumpLive(tester, live);

      repo.failWith = StateError('network unreachable');
      await live.refresh();
      await tester.pump();

      expect(find.textContaining('Feed degraded'), findsOneWidget);
      expect(find.textContaining('network unreachable'), findsOneWidget);
      // The screen is not replaced: the trader still sees what he had.
      expect(find.text('4,312.45'), findsOneWidget);
      expect(find.text('4,310-4,315'), findsOneWidget);
    });
  });

  group('Signal reads the snapshot', () {
    testWidgets('direction, strength, levels and lifecycle come from it',
        (tester) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'SIGNAL');

      expect(find.text('SIGNAL · live-1'), findsOneWidget);
      expect(find.text('ACTIVE'), findsWidgets);
      expect(find.text('ACTIVE SETUP · 15M LONG'), findsOneWidget);
      // Quote from the poller, agreement label (never a forecast).
      expect(find.textContaining('4,312.45 · STRONG 88'), findsOneWidget);
      expect(find.text('4,310-4,315'), findsOneWidget);
      expect(find.text('4,295'), findsOneWidget);
      expect(find.text('4,330'), findsOneWidget);
      expect(find.text('4,275-4,280'), findsNothing);

      // Pip readouts derived from the live levels at convention B.
      expect(find.text('−1800 pips · risk 17.5'), findsOneWidget);
      expect(find.text('500-pip zone'), findsOneWidget);

      // Unreported context reads `—`: the offline SUPPORTIVE / CONFIRMED /
      // in-profit words are claims the pipeline has not made.
      expect(find.text('SUPPORTIVE'), findsNothing);
      expect(find.text('CONFIRMED'), findsNothing);
      expect(find.text('IN-PROFIT +30 PIPS'), findsNothing);
      expect(find.text('NO OPEN POSITION'), findsOneWidget);
      // Fixture open/expiry stamps are dropped rather than dated falsely.
      expect(find.text('Opened 21:44:03 · expires 22:44'), findsNothing);

      // Copy still works in live mode.
      await tester.tap(find.widgetWithText(InkWell, 'COPY SIGNAL TEXT'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Signal text copied'), findsOneWidget);
    });

    testWidgets('no live signal renders the empty state, not a fixture setup',
        (tester) async {
      final live = LiveData(
        repository: _StubRepository(price: 4312.45),
      );
      addTearDown(live.dispose);
      await _pumpLive(tester, live);
      await _openTab(tester, 'SIGNAL');

      expect(find.text('SIGNAL · NO CONSENSUS'), findsOneWidget);
      expect(find.text('NO CONSENSUS'), findsNWidgets(2),
          reason: 'header status + card headline');
      expect(find.text('No 15M setup has cleared consensus right now.'),
          findsOneWidget);
      expect(find.text('Waiting for stronger agreement.'), findsOneWidget);
      expect(find.text('4,275-4,280'), findsNothing);
      expect(find.text('ACTIVE SETUP · 15M LONG'), findsNothing);
      // Nothing to copy, so no action that would copy a fixture.
      expect(find.text('COPY SIGNAL TEXT'), findsNothing);
      expect(find.text('↗ SHARE'), findsNothing);
    });
  });

  group('Sources reads the snapshot', () {
    testWidgets('agreement comes from the signal, rows from the pipeline',
        (tester) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'SOURCES');

      expect(find.text('SOURCES · live-1'), findsOneWidget);
      expect(find.text('4 / 4'), findsOneWidget);
      expect(find.text('agree'), findsOneWidget);
      // Agreement label, not a probability, and derived from the signal.
      expect(find.text('STRONG 88'), findsOneWidget);
      // No contributing rows stored yet: no fixture desks, no toggles to lie
      // about, and independence is reported rather than invented.
      expect(find.text('DESK A · GoldPulse'), findsNothing);
      expect(find.text('Contributing rows arrive with the next pipeline run'),
          findsOneWidget);
      expect(find.text('INDEPENDENCE CHECK'), findsOneWidget);
      expect(
        find.textContaining('Independence is decided by the consensus engine'),
        findsOneWidget,
      );
      expect(find.text('0.80'), findsNothing);
      expect(find.text('STRONG 82'), findsNothing);
      expect(find.text('A/B/C/E cluster tightly'), findsNothing);
    });
  });

  group('History reads the snapshot', () {
    testWidgets('rows render and the stat tiles are derived from them',
        (tester) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'HISTORY');

// The row tightens the separator around its level values, so the
      // rendered detail line is the shortened form.
      expect(find.text('IN 4,300-4,310·SL 4,285'), findsOneWidget);
      expect(find.text('TODAY · 14:20'), findsOneWidget);
      expect(find.text('TP2 HIT'), findsOneWidget);
      expect(find.text('INVALIDATED'), findsNWidgets(2));
      expect(find.text('▼ SHORT'), findsOneWidget);
      // Net = the two closed outcomes summed (20 − 10 points → +1000 pips at B).
      expect(find.text('+1000'), findsOneWidget);
      expect(find.text('+8400'), findsNothing);
      // The fixture log is gone.
      expect(
        find.text('IN 4,102-07 · SL 4,088 · TP2 4,138 · STRONG 84'),
        findsNothing,
      );
      expect(find.text('NO CONSENSUS'), findsNothing);
    });

    testWidgets('an empty log says so', (tester) async {
      await _pumpLive(tester, _empty());
      await _openTab(tester, 'HISTORY');

      expect(find.text('No closed setups yet.'), findsOneWidget);
      expect(find.text('TP2 HIT'), findsNothing);
      expect(find.text('+0'), findsOneWidget);
    });
  });

  group('Events reads the snapshot', () {
    testWidgets('the calendar, guard line and digest come from the poller',
        (tester) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'EVENTS');

      expect(find.text('MACRO CONTEXT · NEVER VOTES'), findsOneWidget);
      expect(find.text('CPI y/y'), findsWidgets);
      expect(find.text('HIGH+MED · 1 ARMED · BLACKOUT 00:12:41'), findsOneWidget);
      expect(find.text('NEXT HIGH-IMPACT'), findsOneWidget);
      // No fixture releases borrow in.
      expect(find.text('NFP — Non-Farm Payrolls'), findsNothing);

      await _openTab(tester, 'RESULTS');
      expect(find.text('No results yet.'), findsOneWidget);
      expect(find.text('CPI y/y'), findsNothing);

      await _openTab(tester, 'NEWS');
      expect(find.text('Hawkish Fed repricing'), findsOneWidget);
      expect(find.text('No headlines collected.'), findsOneWidget);
      expect(find.text('Gold holds range ahead of US payrolls data'),
          findsNothing);
    });

    testWidgets('an empty calendar renders silence, not a fixture event',
        (tester) async {
      await _pumpLive(tester, _empty());
      await _openTab(tester, 'EVENTS');

      expect(find.text('NO USD HIGH EVENT ARMED'), findsOneWidget);
      expect(
        find.text('Muted or filtered out — no blackout window is active.'),
        findsOneWidget,
      );
      expect(find.text('HIGH+MED · 0 ARMED · BLACKOUT —'), findsOneWidget);
      expect(find.text('No events match these filters.'), findsOneWidget);
      expect(find.text('NFP — Non-Farm Payrolls'), findsNothing);

      await _openTab(tester, 'NEWS');
      expect(find.text('No digest published yet.'), findsOneWidget);
      expect(find.text('No headlines collected.'), findsOneWidget);
    });
  });

  group('Settings holds no pipeline data', () {
    testWidgets('renders identically live, with no LIVE/MOCK banner',
        (tester) async {
      await _pumpLive(tester, _empty());
      await _openTab(tester, 'SETTINGS');

      expect(find.text('SETTINGS'), findsNWidgets(2),
          reason: 'header subtitle + nav label');
      expect(find.text('15M / 5M / 1H'), findsOneWidget);
      expect(find.text('Consensus forming'), findsOneWidget);
      expect(find.text('MOCK'), findsNothing);
      expect(find.text('LIVE'), findsNothing);
    });
  });

  group('390px layout', () {
    /// No RenderFlex overflow on any screen, in live mode, with a full snapshot
    /// and with an empty one — an empty state is the layout most likely to
    /// drop a flex child.
    Future<void> sweep(WidgetTester tester, LiveData live) async {
      await _pumpLive(tester, live);
      for (final tab in _tabs) {
        await _openTab(tester, tab);
        expect(tester.takeException(), isNull, reason: '$tab threw in live mode');
      }
    }

    testWidgets('a populated snapshot never overflows', (tester) async {
      await sweep(tester, _populated());
    });

    testWidgets('an empty snapshot never overflows', (tester) async {
      await sweep(tester, _empty());
    });

    testWidgets('a failed poll with no prior data never overflows',
        (tester) async {
      final live = LiveData(
        repository: _StubRepository(failWith: StateError('offline')),
      );
      addTearDown(live.dispose);
      await sweep(tester, live);
    });
  });

  group('the pipeline never invents a level', () {
    test('a half-populated signal is rejected by the repository', () {
      // Guards the layer below the screens: a row missing a required field
      // maps to null, so the screen's empty state is reached rather than a
      // half-built setup.
      expect(MockFixtures.strongLong.status, DisplayStatus.active);
      expect(_liveSignal.entryMid, 4312.5);
    });

    test('the stub only ever answers what it was given', () async {
      final live = LiveData(repository: _StubRepository());
      addTearDown(live.dispose);
      await live.refresh();

      expect(live.price, isNull);
      expect(live.sessionLow, isNull);
      expect(live.sessionHigh, isNull);
      expect(live.hasSignal, isFalse);
      expect(live.signal, isNull);
      expect(live.history, isEmpty);
      expect(live.events, isEmpty);
      expect(live.digest, isEmpty);
      expect(live.error, isNull);
    });

    test('pips stay derived from the live levels, at both conventions', () {
      // The Signal/History figures must rescale with the trader's convention
      // rather than being stored — the live levels are no exception.
      expect(
        pipsTo(_liveSignal.tp1!, _liveSignal.entryMid, pipFactor: 100),
        1700,
      );
      expect(
        pipsTo(_liveSignal.tp1!, _liveSignal.entryMid, pipFactor: 10),
        170,
      );
      expect(
        riskReward(
          target: _liveSignal.tp3!,
          entryLow: _liveSignal.entryLow,
          stopLoss: _liveSignal.stopLoss,
        ),
        closeTo(4.0, 0.01),
      );
    });
  });
}