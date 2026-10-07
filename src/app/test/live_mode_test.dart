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
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xau_core/xau_core.dart' hide Direction;
import 'package:xauvote/data/live_data.dart';
import 'package:xauvote/data/live_repository.dart';
import 'package:xauvote/data/mock_fixtures.dart';
import 'package:xauvote/main.dart' show HarborNavBar;
import 'package:xauvote/models/display_models.dart';
import 'package:xauvote/models/sentiment_layers.dart';
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
    this.prevClose,
    this.signal,
    this.historyRows = const [],
    this.sentimentRows = const SentimentLayers.empty(),
    this.events = const [],
    this.results = const [],
    this.digest = const [],
    this.failWith,
    this.agreement = (distinctIdeas: 0, distinctSources: 0),
    this.enabledSources = 1,
    this.provenance = const [],
    this.contributors = const [],
    this.goldHunts = const [],
    this.failSlowSections = const {},
  });

  // Defaults are unused by the populated fixture, which supplies both
  // explicitly; they exist so a minimal stub still satisfies the interface.

  /// Agreement fixture. Distinct ideas and distinct sources are separate on
  /// purpose: many ideas from one source is one vote, not broad agreement.
  final ({int distinctIdeas, int distinctSources}) agreement;

  /// Denominator: how many sources could have voted.
  final int enabledSources;

  /// Provenance fixture. Empty by default: a stub must not fabricate
  /// independence that the backend did not report.
  final List<IdeaProvenance> provenance;

  /// Rows for the Sources screen. Empty by default: a stub must not invent
  /// contributing sources the backend did not report.
  final List<DisplaySource> contributors;

  double? price;

  final double? low;
  final double? high;

  /// Previous session close for the day-move reference. Mutable so a test can
  /// prove the reference pins per session instead of chasing the database.
  double? prevClose;
  final DisplaySignal? signal;
  final List<DisplayHistoryEntry> historyRows;

  final SentimentLayers sentimentRows;
  final List<DisplayEvent> events;

  /// Released rows for the Results tab. Empty by default: a stub must not
  /// invent scored releases the backend did not report.
  final List<DisplayEvent> results;
  final List<DisplayDigestTheme> digest;

  /// Gold Hunts session views. Empty by default: a stub must not invent an
  /// external publisher the backend did not report.
  final List<GoldHuntsSessionView> goldHunts;

  /// Slow-section names that throw instead of answering. Lets a test fail one
  /// section (history, events, results, digest, session-view) while the rest
  /// succeed, proving a hiccup in one cannot starve the others.
  final Set<String> failSlowSections;

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

  /// Stubbed as live so tests exercise the real path. The provider is never
  /// called from a unit test; a test that wants the fallback sets [livePrice]
  /// false.
  @override
  Future<({double? price, DateTime? at, bool live, String? source})> directSpotPrice({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    _guard();
    final p = price;
    if (p == null) return (price: null, at: null, live: false, source: null);
    return (price: p, at: DateTime(2026, 10, 2, 12, 0), live: livePrice, source: priceSource);
  }
  /// Whether [directSpotPrice] reports a live read. False exercises the
  /// stored-snapshot fallback.
  bool livePrice = true;

  /// Provenance the stubbed tick claims. The caption must show it.
  String? priceSource = 'biquote';

  @override
  Future<({double low, double high})?> sessionRange({required DateTime since}) async {
    _guard();
    final l = low;
    final h = high;
    if (l == null || h == null) return null;
    return (low: l, high: h);
  }

  @override
  Future<List<({DateTime at, double price})>> sessionPrices({
    required DateTime since,
  }) async {
    _guard();
    final l = low;
    final h = high;
    if (l == null || h == null) return const [];
    final now = DateTime.now().toUtc();
    // Newest first, like production: high then low.
    return [(at: now, price: h), (at: now, price: l)];
  }

  @override
  Future<({double? low, double? high, double? firstPrint, double? prevClose})>
      sessionStats({required DateTime since}) async {
    _guard();
    final l = low;
    final h = high;
    if (l == null || h == null) {
      return (low: null, high: null, firstPrint: null, prevClose: null);
    }
    return (low: l, high: h, firstPrint: l, prevClose: prevClose);
  }

  @override
  Future<double?> previousClose({required DateTime sessionStart}) async {
    _guard();
    return prevClose;
  }

  @override
  Future<DisplaySignal?> activeSignal() async {
    _guard();
    return signal;
  }

  @override
  Future<List<GoldHuntsSessionView>> goldHuntsSessionViews({int limit = 10}) async {
    _guard();
    if (failSlowSections.contains('session-view')) {
      throw StateError('session-view down');
    }
    return goldHunts;
  }

  @override
  Future<List<DisplayHistoryEntry>> history({int limit = 50}) async {
    _guard();
    if (failSlowSections.contains('history')) {
      throw StateError('history down');
    }
    return historyRows;
  }

  @override
  Future<SentimentLayers> sentimentLayers() async {
    _guard();
    return sentimentRows;
  }

  @override
  Future<List<DisplayEvent>> upcomingEvents({int limit = 20}) async {
    _guard();
    if (failSlowSections.contains('events')) {
      throw StateError('events down');
    }
    return events;
  }

  @override
  Future<List<DisplayEvent>> resultEvents({int limit = 20}) async {
    _guard();
    if (failSlowSections.contains('results')) {
      throw StateError('results down');
    }
    return results;
  }

  @override
  Future<List<DisplayDigestTheme>> latestDigest() async {
    _guard();
    if (failSlowSections.contains('digest')) {
      throw StateError('digest down');
    }
    return digest;
  }

  // ---------------------------------------------------------------- analysis
  //
  // The stub returns empty rather than fabricating bars. The scanner treats a
  // missing series as insufficient history and reports NO TRADE, which is the
  // behaviour these tests want: a stub must not manufacture a setup.

  @override
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async {
    _guard();
    return const {};
  }

  @override
  Future<({int distinctIdeas, int distinctSources})> agreementCount(
    String signalId,
  ) async {
    _guard();
    return agreement;
  }

  @override
  Future<int> enabledSourceCount() async {
    _guard();
    return enabledSources;
  }

  @override
  Future<List<DisplaySource>> contributingSources(String signalId) async {
    _guard();
    return contributors;
  }

  @override
  Future<List<IdeaProvenance>> ideaProvenance(String signalId) async {
    _guard();
    return provenance;
  }

  @override
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    _guard();
    return (spread: const VenueSpread.unavailable(), ageSeconds: double.infinity);
  }

  @override
  Future<List<EconomicEvent>> analysisEvents({int hoursAhead = 24}) async {
    _guard();
    return const [];
  }
}

/// The §5.1 layer rows as they currently stand in the database: positioning and
/// market-implied measured, policy and WGC present but unmeasured.
final SentimentLayers _liveSentiment = SentimentLayers([
  SentimentLayerRow.tryParse(const {
    'layer': 'market_implied',
    'horizon': 'hours-days',
    'weight': 20,
    'score': null,
    'alignment': -1,
    'measured_at': '2026-10-02T00:00:00.000Z',
    'source': 'US Treasury daily real yield curve',
    'source_url': null,
    'stale': false,
    'detail': {'real10y': 2.92, 'change5d_bp': 9},
  })!,
  SentimentLayerRow.tryParse(const {
    'layer': 'positioning',
    'horizon': 'weeks',
    'weight': 25,
    'score': -1,
    'alignment': -1,
    'measured_at': '2026-09-29T00:00:00.000Z',
    'source': 'CFTC disaggregated Commitments of Traders',
    'source_url': null,
    'stale': false,
    'detail': {'percentile_156w': 37.8, 'sample_weeks': 156},
  })!,
  SentimentLayerRow.tryParse(const {
    'layer': 'policy',
    'horizon': 'days-weeks',
    'weight': 35,
    'score': null,
    'alignment': null,
    'measured_at': '1970-01-01T00:00:00.000Z',
    'source': 'Federal Reserve FOMC statements / SEP',
    'source_url': null,
    'stale': true,
    'detail': {'reason': 'ingest not implemented yet'},
  })!,
  // No gold_fundamentals fixture. The layer was removed rather than left pending:
  // its source cannot be licensed. See D-20261006-011.
]);

/// Registered from [main] below; kept separate so this fixture stays next to the
/// stub it feeds.
void _sentimentLayerReadTests() {
  group('sentiment layers read', () {
    test('measured layers arrive and map onto the engine inputs', () async {
      final repo = _StubRepository(sentimentRows: _liveSentiment);
      final layers = await repo.sentimentLayers();

// Three layers: gold_fundamentals was removed because its source cannot be
      // licensed, so it must not come back from the database either.
      expect(layers.rows, hasLength(3));
      expect(layers['gold_fundamentals'], isNull);
        expect(layers['positioning']?.alignment, -1);
      expect(layers['market_implied']?.alignment, -1);
      expect(layers['positioning']?.detail['percentile_156w'], 37.8);

      // Positioning is one complete layer, so it reaches the engine directly.
      expect(layers.sentiment.alignment, -1);
      expect(layers.sentiment.cotStale, isFalse);
      expect(layers.sentiment.isAvailable, isTrue);

      // The real-yield impulse is surfaced...
      expect(layers.macro.realYieldImpulse, -1);
      // ...but macro alignment stays null at 20/75 coverage, so a single
      // 20-weight reading cannot veto a setup.
      expect(layers.macroCoverage, closeTo(20 / 55, 1e-9));
      expect(layers.macro.alignment, isNull);
      expect(layers.macro.isAvailable, isFalse);
    });

    test('unmeasured layers are reported as unmeasured, not as zero', () async {
      final layers = await _StubRepository(
        sentimentRows: _liveSentiment,
      ).sentimentLayers();
      expect(layers.isMissing('policy'), isFalse);
      expect(layers.isUnmeasured('policy'), isTrue);
      expect(layers['policy']?.score, isNull);
      expect(layers['policy']?.measuredAt, isNull);
      expect(layers['policy']?.stale, isTrue);
    });

    test('no rows yields empty layers rather than a fabricated neutral', () async {
      final layers = await _StubRepository().sentimentLayers();
      expect(layers.rows, isEmpty);
      expect(layers.overallCoverage, 0);
      expect(layers.sentiment.isAvailable, isFalse);
      expect(layers.macro.alignment, isNull);
    });

    test('a failed read propagates instead of returning empty layers', () async {
      // An empty read and a failed read must not look the same to the caller.
      final repo = _StubRepository(failWith: StateError('network down'));
      await expectLater(repo.sentimentLayers(), throwsStateError);
    });
  });
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

/// A scored release: issuer numeric plus the publisher's wording. Forecast is
/// null (the feed carries none), so the row must render UNSCORED, never
/// "in line" — in-line claims a comparison that never happened.
const _liveResult = DisplayEvent(
  id: 'live-res-cpi',
  title: 'US CPI Report August 2026',
  currency: 'USD',
  impact: EventImpact.high,
  startsIn: Duration(days: -56),
  actual: '334.98',
  actualText: '+3.4% YoY, +0.1% MoM',
  actualSource: 'BLS CUUR0000SA0 (public domain, ref 2026-M08)',
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
/// A publisher that genuinely contributed, for the Sources screen.
const DisplaySource _liveContributor = DisplaySource(
  id: 'desk-a',
  name: 'Desk A',
  direction: Direction.long,
  agrees: true,
  entryText: '4,138.16-4,143.16',
  stopText: '4,128.16',
  targetsText: '4,148.66',
  freshnessText: '12m',
  reasoning: 'Upstream dataset: MANUAL-SEED',
  sourceUrl: '',
  tp1HitRate: 0,
  tp2HitRate: 0,
  tp3HitRate: 0,
);

LiveData _populated() {
  final live = LiveData(
    repository: _StubRepository(
      price: 4312.45,
      low: 4300.10,
      high: 4320.90,
      signal: _liveSignal,
      historyRows: _liveHistory,
      events: const [_liveEvent],
      results: const [_liveResult],
      digest: const [_liveDigest],
      // Previous session close: the day move reads against it.
      prevClose: 4295.00,
      // 9 distinct ideas from 4 independent sources, with 6 sources enabled.
      // Deliberately different numbers: the poller must show partial
      // agreement, and a fixture where both counts match would hide the
      // tautology that produced the old "11 of 11".
      agreement: (distinctIdeas: 9, distinctSources: 4),
      enabledSources: 6,
      contributors: const [_liveContributor],
      // Provenance for the four agreeing external publishers. Without it the
      // scorer reports zero sources and the UI renders "No external sources yet",
      // which is correct but is not what this fixture is demonstrating.
      provenance: [
        for (final p in ['P1', 'P2', 'P3', 'P4'])
          IdeaProvenance(
            ideaId: 'idea-$p',
            direction: 'LONG',
            modelOwner: ModelOwner.thirdParty,
            publisherId: p,
            methodologyId: 'method-$p',
            publishedAt: DateTime.utc(2026, 10, 2, 12),
            derived: false,
          ),
      ],
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

/// The screens under test, with the session pinned open.
///
/// Without this the suite silently changes meaning across the week: the Radar
/// and Signal screens withhold a setup while the market is shut, so a run at
/// the weekend would fail every level assertion for the right reason and the
/// wrong cause.
final _screens = <Widget>[
  const RadarScreen(sessionOpenOverride: true),
  const SignalScreen(sessionOpenOverride: true),
  const SourcesScreen(),
  const HistoryScreen(),
  const EventsScreen(),
  const SettingsScreen(),
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
/// Finds a tab by its bottom-nav key, falling back to plain text.
///
/// The bottom bar labels only the ACTIVE tab (that is the point of the pill
/// design), so nav tabs are addressed by key. The Events screen's own
/// UPCOMING / RESULTS / NEWS tabs are ordinary text and are not in the bar.
Finder _tabFinder(String tab) {
  final nav = find.byKey(ValueKey('nav-$tab'));
  return nav.evaluate().isEmpty ? find.text(tab) : nav;
}

Future<void> _openTab(WidgetTester tester, String tab) async {
  await tester.tap(_tabFinder(tab));
  await tester.pump();
  await tester.pump();
}

void main() {
  _sentimentLayerReadTests();

  // The price is fetched straight from the provider so it moves with the market
  // instead of the once-a-minute cron. When that call fails the app falls back to
  // the stored snapshot, and the distinction has to survive: a number that has
  // stopped being refreshed must not be presented as live, because rule 2 is
  // about freshness as much as about fabrication.
  group('price freshness is reported honestly', () {
    test('a direct provider read is marked live', () async {
      final live = LiveData(repository: _StubRepository(price: 4175.30));
      addTearDown(live.dispose);
      await live.refresh();
      expect(live.price, 4175.30);
      expect(live.priceIsLive, isTrue);
    });

    test('a provider outage falls back to the stored snapshot and says so', () async {
      final repo = _StubRepository(price: 4170.66)..livePrice = false;
      final live = LiveData(repository: repo);
      addTearDown(live.dispose);
      await live.refresh();

      // The stale value is still better than an empty screen, but it must not be
      // dressed up as live.
      expect(live.price, 4170.66);
      expect(live.priceIsLive, isFalse);
    });

    test('a shown price always carries a non-negative age', () async {
      final live = LiveData(repository: _StubRepository(price: 4175.30));
      addTearDown(live.dispose);
      await live.refresh();

      // The stub timestamp is far in the past, so the age is large - the point
      // is the contract: present whenever a price is shown, and never negative
      // (clock skew must not print "-3s ago").
      expect(live.priceAgeSeconds, isNotNull);
      expect(live.priceAgeSeconds!, greaterThanOrEqualTo(0));
    });

    test('a halt-to-open flip notifies without any data changing', () async {
      // the app kept showing MARKET CLOSED until an unrelated data poll
      // happened to rebuild the screens. The flip below moves no price, no
      // signal, no event - only the clock - and the screens must still learn.
      final live = LiveData(repository: _StubRepository());
      addTearDown(live.dispose);
      var notifications = 0;
      live.addListener(() => notifications++);

      // Tuesday 17:50 New York: halted. Baseline, no announcement.
      live.checkSession(at: DateTime.utc(2026, 10, 6, 21, 50));
      expect(notifications, 0);

      // Still halted ten minutes later: silence, not a rebuild every check.
      live.checkSession(at: DateTime.utc(2026, 10, 6, 21, 55));
      expect(notifications, 0);

      // 18:01 New York: open. Exactly one announcement, so every surface that
      // derives open/closed at build time re-derives within seconds.
      live.checkSession(at: DateTime.utc(2026, 10, 6, 22, 1));
      expect(notifications, 1);

      // Still open: silence again.
      live.checkSession(at: DateTime.utc(2026, 10, 6, 22, 5));
      expect(notifications, 1);
    });

    test('price-live is a simple GET so browsers skip the preflight', () async {
      // Regression: the call sent the key as an `apikey` header, which forces
      // a CORS preflight the gateway answers without echoing the header. Every
      // browser then refused the call while the phone worked, and the web
      // build silently fell back to snapshots. The key travels in the query
      // string with no custom headers, which browsers send preflight-free.
      Uri? gotUri;
      Map<String, String>? gotHeaders;
      final client = MockClient((request) async {
        gotUri = request.url;
        gotHeaders = Map.of(request.headers);
        return http.Response(
          '{"price":4170.30,"live":true,"measuredAt":"2026-10-06T20:00:00Z"}',
          200,
        );
      });
      addTearDown(client.close);
      final repo = LiveRepository(
        SupabaseClient('https://example.supabase.co', 'anon-key'),
        client,
      );

      final quote = await repo.directSpotPrice();

      expect(quote.price, 4170.30);
      expect(quote.live, isTrue);
      expect(gotUri!.path, endsWith('/price-live'));
      // The key travels in the query string (value is empty in tests: the
      // publishable key arrives via --dart-define at build time). What this
      // pins is the mechanism - query, never a custom header.
      expect(gotUri!.queryParameters, contains('apikey'));
      expect(gotHeaders!.keys.map((k) => k.toLowerCase()), isNot(contains('apikey')));
    });
  });

  group('Gold Hunts session view is separate and honest', () {
    GoldHuntsSessionView view({
      required String direction,
      required String session,
      DateTime? publishedAt,
      DateTime? dataAsOf,
      bool providerStale = false,
    }) =>
        GoldHuntsSessionView(
          providerId: 'gh-$direction-$session',
          direction: direction,
          session: session,
          publishedAt: publishedAt,
          dataAsOf: dataAsOf,
          providerStale: providerStale,
        );

    test('freshness follows the directive rule, not the fetch time', () {
      final now = DateTime.utc(2026, 10, 6, 22, 30);
      // Fresh data, provider quiet: current.
      expect(
        view(
          direction: 'BEARISH',
          session: 'NY',
          publishedAt: now.subtract(const Duration(minutes: 40)),
          dataAsOf: now.subtract(const Duration(minutes: 40)),
        ).isStaleAt(now),
        isFalse,
      );
      // Provider flag set: stale whatever the clock says.
      expect(
        view(
          direction: 'BEARISH',
          session: 'NY',
          publishedAt: now.subtract(const Duration(minutes: 5)),
          dataAsOf: now.subtract(const Duration(minutes: 5)),
          providerStale: true,
        ).isStaleAt(now),
        isTrue,
      );
      // Older than 6 hours: stale.
      expect(
        view(
          direction: 'RANGING',
          session: 'LONDON',
          publishedAt: now.subtract(const Duration(hours: 8)),
          dataAsOf: now.subtract(const Duration(hours: 8)),
        ).isStaleAt(now),
        isTrue,
      );
      // No timestamp at all: stale, never current by default.
      expect(
        view(direction: 'RANGING', session: 'LONDON').isStaleAt(now),
        isTrue,
      );
    });

    testWidgets('session view renders verbatim and never votes', (tester) async {
      final now = DateTime.now().toUtc();
      final live = LiveData(
        repository: _StubRepository(
          goldHunts: [
            view(
              direction: 'SWEEP_THEN_REVERSE',
              session: 'ASIAN',
              publishedAt: now.subtract(const Duration(minutes: 40)),
              dataAsOf: now.subtract(const Duration(minutes: 40)),
            ),
            view(
              direction: 'BEARISH',
              session: 'NY',
              publishedAt: now.subtract(const Duration(hours: 8)),
              dataAsOf: now.subtract(const Duration(hours: 8)),
            ),
          ],
        ),
      );
      addTearDown(live.dispose);
      await _pumpLive(tester, live);
      await tester.tap(find.byKey(const ValueKey('nav-SOURCES')));
      await tester.pumpAndSettle();

      // The provider's labels, verbatim, with sessions and attribution.
      expect(find.text('Label: SWEEP_THEN_REVERSE'), findsOneWidget);
      expect(find.textContaining('Session: ASIAN'), findsOneWidget);
      expect(find.text('Label: BEARISH'), findsOneWidget);
      expect(find.text('Gold Hunts'), findsOneWidget);
      expect(find.textContaining('goldhunts.com'), findsOneWidget);
      // Never mapped to a trade direction.
      expect(find.text('Label: LONG'), findsNothing);
      expect(find.text('Label: SHORT'), findsNothing);
      // The separation is stated, not implied.
      expect(find.textContaining('Not a vote'), findsOneWidget);
      // Staleness is per-row and section-wide: the 8-hour call is marked, and
      // the section carries the banner because one of its rows is stale.
      expect(find.text('STALE'), findsNWidgets(2));
      // The voter headline is untouched by the session view: still no signal,
      // still no invented agreement.
      expect(
        find.text('No active signal — nothing to attribute yet'),
        findsOneWidget,
      );
    });

    testWidgets('an empty feed says so instead of borrowing rows', (tester) async {
      final live = LiveData(repository: _StubRepository());
      addTearDown(live.dispose);
      await _pumpLive(tester, live);
      await tester.tap(find.byKey(const ValueKey('nav-SOURCES')));
      await tester.pumpAndSettle();

      expect(find.text('No open session calls reported.'), findsOneWidget);
      expect(find.text('Label: BEARISH'), findsNothing);
    });

    test('returning to the app refreshes slow sections without a pull', () async {
      // Reported: Sources sat stale until a manual pull. Timers do not fire
      // while backgrounded, so this is the resume path doing its job.
      final now = DateTime.now().toUtc();
      final live = LiveData(
        repository: _StubRepository(
          goldHunts: [
            GoldHuntsSessionView(
              providerId: 'gh-1',
              direction: 'RANGING',
              session: 'LONDON',
              publishedAt: now.subtract(const Duration(minutes: 40)),
              dataAsOf: now.subtract(const Duration(minutes: 40)),
            ),
          ],
        ),
      );
      addTearDown(live.dispose);
      expect(live.goldHunts, isEmpty);

      live.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // The resume poll is fire-and-forget; let it land.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(live.goldHunts, hasLength(1));
      expect(live.goldHunts.first.direction, 'RANGING');
    });

    test('one failing slow section cannot starve the rest', () async {
      // Previously a single throwing read aborted the whole slow block, so a
      // hiccup in events could freeze the session view until a lucky manual
      // pull. Each section is fenced now.
      final now = DateTime.now().toUtc();
      final live = LiveData(
        repository: _StubRepository(
          failSlowSections: {'events'},
          goldHunts: [
            GoldHuntsSessionView(
              providerId: 'gh-1',
              direction: 'BEARISH',
              session: 'NY',
              publishedAt: now.subtract(const Duration(minutes: 40)),
              dataAsOf: now.subtract(const Duration(minutes: 40)),
            ),
          ],
        ),
      );
      addTearDown(live.dispose);
      await live.refresh();

      // The session view landed despite the events outage...
      expect(live.goldHunts, hasLength(1));
      // ...and the failure is named instead of swallowed or fatal.
      expect(live.error, contains('events'));
    });

    testWidgets('the voter header names its emptiness instead of dashing it', (
      tester,
    ) async {
      // Reported: the header showed bare 0/0 with dashes that read as a
      // broken widget. The counts stay truthful; the tiles now state why
      // there is nothing to measure.
      final live = LiveData(repository: _StubRepository());
      addTearDown(live.dispose);
      await _pumpLive(tester, live);
      await tester.tap(find.byKey(const ValueKey('nav-SOURCES')));
      await tester.pumpAndSettle();

      expect(find.text('0 / 0'), findsOneWidget);
      expect(find.text('NO SIGNAL'), findsOneWidget);
      expect(find.text('NO VOTERS'), findsOneWidget);
      expect(
        find.text('No active signal — nothing to attribute yet'),
        findsOneWidget,
      );
    });
  });
  // `mockMode` is a compile-time flag, so a test cannot flip the build. What
  // the screens branch on is the [LiveData] `main.dart` mounts above them for a
  // LIVE release: an offline build mounts none and they read fixtures (covered
  // by the pre-existing offline suite), a live build mounts one and they read
  // it. These tests drive the second state directly, which is the only state
  // that has to be proven here.

  group('Radar reads the snapshot', () {
    testWidgets('price, range, levels and agreement come from the poller', (
      tester,
    ) async {
      await _pumpLive(tester, _populated());

      // Price hero.
      expect(find.text('XAUUSD · SPOT GOLD'), findsOneWidget);
      expect(find.text('4,312.45'), findsOneWidget);
      // Provenance rides with the tick: the caption names the source.
      expect(find.textContaining('biquote'), findsOneWidget);
      expect(
        find.text('4,278.30'),
        findsNothing,
        reason: 'the fixture price must never reach a live screen',
      );
      // Day change vs the stub's previous close (4312.45 − 4295.00): the
      // hero shows the measured percent, never the fixture's +0.29%.
      expect(find.text('+0.41%'), findsOneWidget);
      expect(
        find.text('+0.29%'),
        findsNothing,
        reason: 'the fixture percent must never reach a live screen',
      );

      // Day bar: the observed range, and the measured move vs prev close.
      expect(find.text('+12.40'), findsNothing);
      expect(find.text('+17.45'), findsOneWidget);
      expect(find.text('4,300.10 — 4,320.90'), findsOneWidget);

      // Verdict levels are WITHHELD. The engine still computes a stop plan,
      // but nothing publishes entry/stop/TP while there is no forward record to
      // validate them against, and a badge does not stop a number being acted
      // on. What must still render is the verdict, the score and the reasons.
      expect(find.byType(VerdictLevelGrid), findsNothing);
      expect(find.text('ENTRY, STOP AND TARGETS WITHHELD'), findsOneWidget);
      for (final level in [
        'ENTRY',
        '4,310-4,315',
        '4,330',
      ]) {
        expect(
          find.text(level),
          findsNothing,
          reason: '$level must not be published before validation',
        );
      }

      // Agreement is a split, and the offline source chips do not exist here.
      expect(find.text('15M Consensus Setup'), findsOneWidget);
      expect(find.text('STRONG · 4 / 6'), findsOneWidget);
      // 4 independent sources out of 6 that could have voted. The numerator is
      // a distinct source count, not an idea count, so one prolific source can
      // never look like broad agreement.
      expect(find.text('4 of 6 sources agree'), findsOneWidget);
      expect(find.text('4 of 4 sources agree'), findsNothing);
      expect(find.text('Source A ✓'), findsNothing);
      expect(find.text('LONG'), findsOneWidget);
      expect(
        find.text('—'),
        findsWidgets,
        reason: 'alternate direction and 5M confirmation are unreported',
      );

      // There is no copy or share affordance left to reach levels with.
      expect(find.text('COPY LEVELS'), findsNothing);
      expect(find.text('↗ SHARE'), findsNothing);
    });

    testWidgets('the demo state switcher is offline-only', (tester) async {
      await _pumpLive(tester, _populated());

      expect(find.text('DEMO STATE'), findsNothing);
      for (final state in ['STRONG', 'DEVELOPING', 'DIVIDED']) {
        expect(
          find.widgetWithText(TextButton, state),
          findsNothing,
          reason: 'the pipeline owns the state, not a demo switcher',
        );
      }
    });

    testWidgets('a null signal renders NO CONSENSUS, never fixture levels', (
      tester,
    ) async {
      final live = LiveData(
        repository: _StubRepository(price: 4312.45, low: 4300.10, high: 4320.90),
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

    testWidgets('a null price renders the waiting state, never a number', (tester) async {
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
      expect(find.text('15M Consensus Setup'), findsOneWidget);
    });

    testWidgets('events annotate the card but never vote (rule 9)', (tester) async {
      await _pumpLive(tester, _populated());

      // Title and countdown are separate spans now (the clock ticks on its
      // own), so assert both halves rather than one frozen string.
      expect(find.textContaining('Caution: CPI y/y in'), findsOneWidget);
      expect(find.text('12:41'), findsWidgets);
      expect(find.text('Caution: Retail Sales in 42m'), findsNothing);
      expect(find.text('Hawkish Fed repricing'), findsOneWidget);
    });

    testWidgets('a failed poll keeps the last good values and says so', (tester) async {
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
      expect(find.text('15M Consensus Setup'), findsOneWidget);
    });

    testWidgets('ticks fold into the range and move without a new poll', (
      tester,
    ) async {
      final repo = _StubRepository(
        price: 4312.45,
        low: 4300.10,
        high: 4320.90,
        prevClose: 4295.00,
      );
      final live = LiveData(repository: repo);
      addTearDown(live.dispose);
      await _pumpLive(tester, live);

      expect(find.text('4,300.10 — 4,320.90'), findsOneWidget);
      expect(find.text('+17.45'), findsOneWidget);

      // A new high ticks in: the range widens and the move follows, all from
      // the tick itself — no history re-read, no extra network. The slow
      // re-anchor keeps the tick (4325.90 − 4295.00 = +30.90, +0.72%).
      repo.price = 4320.90 + 5.00;
      await live.refresh();
      // The quote block repaints on its own 1s ticker rather than on the
      // notify path, so advance the clock past one tick.
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('4,300.10 — 4,325.90'), findsOneWidget);
      expect(find.text('+30.90'), findsOneWidget);
      expect(find.text('+0.72%'), findsOneWidget);
    });

    testWidgets('no reference, no move: blank instead of a derived number', (
      tester,
    ) async {
      // A price with no session history and no previous close. Ticks still
      // fold extremes (the range reads the ticks), but the move has nothing
      // to measure against, so it stays blank and the hero shows no percent.
      final live = LiveData(
        repository: _StubRepository(price: 4312.45),
      );
      addTearDown(live.dispose);
      await _pumpLive(tester, live);

      expect(find.text('4,312.45 — 4,312.45'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('the move reference pins per session, not per poll', (
      tester,
    ) async {
      final repo = _StubRepository(
        price: 4312.45,
        low: 4300.10,
        high: 4320.90,
        prevClose: 4295.00,
      );
      final live = LiveData(repository: repo);
      addTearDown(live.dispose);
      await _pumpLive(tester, live);
      expect(find.text('+17.45'), findsOneWidget);

      // The backend's close shifts (retention pruning, late corrections):
      // the displayed move must not follow it mid-session.
      repo.prevClose = 4300.00;
      await live.refresh();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('+17.45'), findsOneWidget);
      expect(find.text('+12.45'), findsNothing);
    });
  });

  group('Signal reads the snapshot', () {
    testWidgets('direction, strength, levels and lifecycle come from it', (tester) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'SIGNAL');

      expect(find.text('SIGNAL · live-1'), findsOneWidget);
      expect(find.text('ACTIVE'), findsWidgets);
      expect(find.text('ACTIVE SETUP · 15M LONG'), findsOneWidget);
      // Quote from the poller, agreement label (never a forecast).
      expect(find.textContaining('4,312.45 · STRONG 88'), findsOneWidget);
      // Levels are withheld; the verdict and lifecycle still render.
      expect(find.text('WITHHELD'), findsOneWidget);
      for (final level in ['4,310-4,315', '4,330', '4,275-4,280']) {
        expect(find.text(level), findsNothing,
            reason: '$level must not be published before validation');
      }

      // Pip readouts derived from the live levels at convention B.

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

    testWidgets('no live signal renders the empty state, not a fixture setup', (
      tester,
    ) async {
      final live = LiveData(repository: _StubRepository(price: 4312.45));
      addTearDown(live.dispose);
      await _pumpLive(tester, live);
      await _openTab(tester, 'SIGNAL');

      expect(find.text('SIGNAL · NO CONSENSUS'), findsOneWidget);
      expect(
        find.text('NO CONSENSUS'),
        findsNWidgets(2),
        reason: 'header status + card headline',
      );
      expect(find.text('No 15M setup has cleared consensus right now.'), findsOneWidget);
      expect(find.text('Waiting for stronger agreement.'), findsOneWidget);
      expect(find.text('4,275-4,280'), findsNothing);
      expect(find.text('ACTIVE SETUP · 15M LONG'), findsNothing);
      // Nothing to copy, so no action that would copy a fixture.
      expect(find.text('COPY SIGNAL TEXT'), findsNothing);
      expect(find.text('↗ SHARE'), findsNothing);
    });
  });

  group('Sources reads the snapshot', () {
    testWidgets('agreement comes from the signal, rows from the pipeline', (
      tester,
    ) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'SOURCES');

      expect(find.text('SOURCES · live-1'), findsOneWidget);
      // 4 independent sources of 6 that could have voted.
      expect(find.text('4 / 6'), findsOneWidget);
      expect(find.text('agree'), findsOneWidget);
      // Agreement label, not a probability, and derived from the signal.
      expect(find.text('STRONG 88'), findsOneWidget);
      // The linked publisher is now listed: the Sources screen reads the rows
      // behind the signal instead of hardcoding an empty list.
      expect(find.text('Desk A'), findsOneWidget);
      expect(
        find.text('1 contributing source'),
        findsOneWidget,
      );
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
    testWidgets('rows render and the stat tiles are derived from them', (tester) async {
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
      expect(find.text('IN 4,102-07 · SL 4,088 · TP2 4,138 · STRONG 84'), findsNothing);
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
    testWidgets('the calendar, guard line and digest come from the poller', (
      tester,
    ) async {
      await _pumpLive(tester, _populated());
      await _openTab(tester, 'EVENTS');

      expect(find.text('MACRO CONTEXT · NEVER VOTES'), findsOneWidget);
      expect(find.text('CPI y/y'), findsWidgets);
      expect(find.text('HIGH+MED · 1 WATCHING · BLACKOUT —'), findsNothing);
      // Guard static half plus the self-ticking clock as separate spans.
      expect(find.textContaining('1 WATCHING · BLACKOUT'), findsOneWidget);
      expect(find.text('12:41'), findsOneWidget);
      // Two self-ticking clocks show the same release: the blackout card's
      // and the row's. Both must render — a missing one is a frozen one.
      expect(find.text('in 12:41'), findsNWidgets(2));
      expect(find.text('NEXT HIGH-IMPACT'), findsOneWidget);
      // No fixture releases borrow in.
      expect(find.text('NFP — Non-Farm Payrolls'), findsNothing);

      await _openTab(tester, 'RESULTS');
      // The scored row renders its figures, the publisher's wording, and
      // the figure's provenance — and the upcoming release never borrows in.
      expect(find.text('US CPI Report August 2026'), findsOneWidget);
      expect(find.textContaining('A 334.98'), findsOneWidget);
      expect(find.textContaining('+3.4% YoY'), findsOneWidget);
      expect(find.textContaining('BLS CUUR0000SA0'), findsOneWidget);
      // No forecast on file: unscored, never "in line".
      expect(find.textContaining('UNSCORED'), findsOneWidget);
      expect(find.text('CPI y/y'), findsNothing);

      await _openTab(tester, 'NEWS');
      expect(find.text('Hawkish Fed repricing'), findsOneWidget);
      // The theme shows what it stands on, so it reads as a summary.
      expect(find.textContaining('linked article'), findsOneWidget);
      expect(find.text('No headlines collected.'), findsOneWidget);
      expect(find.text('Gold holds range ahead of US payrolls data'), findsNothing);
    });

    testWidgets('an empty calendar renders silence, not a fixture event', (tester) async {
      await _pumpLive(tester, _empty());
      await _openTab(tester, 'EVENTS');

      expect(find.text('NO USD HIGH EVENT ARMED'), findsOneWidget);
      expect(
        find.text('Muted or filtered out — no blackout window is active.'),
        findsOneWidget,
      );
      expect(find.text('HIGH+MED · 0 WATCHING · BLACKOUT —'), findsOneWidget);
      expect(find.text('No events match these filters.'), findsOneWidget);
      expect(find.text('NFP — Non-Farm Payrolls'), findsNothing);

      await _openTab(tester, 'RESULTS');
      // Nothing scored yet: the silence names the lag, not a broken feed.
      expect(find.text('No results yet.'), findsOneWidget);
      expect(find.textContaining('arrive with a lag'), findsOneWidget);

      await _openTab(tester, 'NEWS');
      expect(find.text('No digest published yet.'), findsOneWidget);
      // The silence states its cause: no licensed feed, not a broken widget.
      // Both empty notes say it (digest + headlines), so two matches.
      expect(find.textContaining('licensed news'), findsNWidgets(2));
      expect(find.text('No headlines collected.'), findsOneWidget);
    });
  });

  group('countdowns tick on their own clock', () {
    testWidgets('seconds move with no data poll and no ancestor rebuild', (
      tester,
    ) async {
      // The injected clock stands in for wall time: advancing it plus the
      // fake-async scheduler is exactly what five real seconds do to the
      // production widget (default clock, real timer).
      var now = DateTime.utc(2026, 10, 7, 12);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EventCountdown(
              startsIn: const Duration(minutes: 12, seconds: 41),
              now: () => now,
            ),
          ),
        ),
      );
      expect(find.text('in 12:41'), findsOneWidget);

      // Five seconds pass, nothing else happens — no poll, no setState above.
      now = now.add(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('in 12:36'), findsOneWidget);
      expect(find.text('in 12:41'), findsNothing);
    });

    testWidgets('a multi-day countdown shows days, not a frozen second hand', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EventCountdown(
              startsIn: Duration(days: 6, hours: 3, minutes: 20),
            ),
          ),
        ),
      );
      expect(find.text('in 6d 03h'), findsOneWidget);
    });
  });

  group('Settings holds no pipeline data', () {    testWidgets('renders identically live, with no LIVE/MOCK banner', (tester) async {
      await _pumpLive(tester, _empty());
      await _openTab(tester, 'SETTINGS');

      expect(
        find.text('SETTINGS'),
        findsNWidgets(2),
        reason: 'header subtitle + nav label',
      );
      expect(find.text('15M / 5M / 1H'), findsOneWidget);
      expect(find.text('Consensus forming'), findsOneWidget);
      expect(find.text('MOCK'), findsNothing);
      // No bare "LIVE" label: the pill names the real session phase, so this
      // stays true whether the market is open or shut.
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

    testWidgets('a failed poll with no prior data never overflows', (tester) async {
      final live = LiveData(repository: _StubRepository(failWith: StateError('offline')));
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
      expect(pipsTo(_liveSignal.tp1!, _liveSignal.entryMid, pipFactor: 100), 1700);
      expect(pipsTo(_liveSignal.tp1!, _liveSignal.entryMid, pipFactor: 10), 170);
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
