/// Live-mode data holder: one polling source of truth for every screen.
///
/// WHY A SINGLE POLLER
/// Edge Functions run on pg_cron, not a push feed, so the app polls. Several
/// screens need the same rows (Radar price, Signal levels, History), and one
/// poller keeps them consistent — no screen can show a price that contradicts
/// another. Polling is 15s on Radar and 60s elsewhere, well inside the free
/// tier (the anon role has unlimited API requests; only egress is metered).
///
/// NEVER FABRICATE: a failed poll keeps the previous values and sets [error];
/// it never substitutes fixture data. An empty result is a real state (the room
/// can legitimately have no consensus) and is surfaced as such.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xau_core/analysis/independence.dart';
import 'package:xau_core/analysis/session.dart';

import 'live_repository.dart';
import '../models/display_models.dart';

/// Snapshot of everything the screens read in live mode.
class LiveData extends ChangeNotifier with WidgetsBindingObserver {
  LiveData({SupabaseClient? client, LiveRepository? repository, DateTime Function()? clock})
    : _repo = repository ?? LiveRepository(client),
      _clock = clock ?? DateTime.now;

  final LiveRepository _repo;

  /// Clock seam, so tests can simulate a halt-to-open flip without waiting
  /// for Friday. Production always passes the real clock.
  final DateTime Function() _clock;

  /// Fast cadence: quote, range, active signal.
  Timer? _fastTimer;

  /// Price-only cadence, deliberately faster than [_fastTimer].
  ///
  /// The price now comes straight from the provider, which publishes with no
  /// rate limit, so it is the one value that genuinely benefits from a short
  /// interval. Everything else still moves on the order of minutes and stays on
  /// [_fastTimer], because re-reading those tables more often only rebuilds the
  /// same widgets against unchanged data.
  Timer? _priceTimer;

  /// Session flip watcher. Recomputes market open/closed on a slow beat and
  /// notifies ONLY when it flips.
  ///
  /// Reported 2026-10-07: the market reopened after the daily halt and the app
  /// kept showing MARKET CLOSED until a manual refresh. Every screen derives
  /// open/closed at build time, and builds only happen when polled data
  /// changes - on a flat price nothing rebuilds, so no build ever notices the
  /// reopen. This timer is the something that notices: two notifications a
  /// day (halt + reopen, plus weekend transitions), silence the rest of the
  /// time. It deliberately does not poll data and does not rebuild screens on
  /// a beat - that would be the Events-list churn bug all over again, on
  /// purpose this time.
  Timer? _sessionTimer;
  bool? _lastSessionOpen;

  static const _sessionWatchInterval = Duration(seconds: 10);

  /// Whether the lifecycle observer is registered. Guards double registration
  /// across repeated startPolling calls.
  bool _observingLifecycle = false;

  /// Refresh slow sections when the app comes back to the foreground.
  ///
  /// Reported: Sources (and every slow section) sat stale until a manual
  /// pull. Timers do not fire while the app is backgrounded, so a returning
  /// user reads whatever was last fetched - possibly hours old - until the
  /// next 5-minute beat happens to land. Resuming with a slow refresh closes
  /// that gap without touching the fast cadences.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _pollSlow();
  }

  /// Slow cadence: calendar, history, news digest.
  Timer? _slowTimer;

  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;

  double? _price;
  DateTime? _priceAt;

  /// False when the price came from the stored snapshot because the provider was
  /// unreachable. The UI must not present a stale number as live.
  bool _priceIsLive = false;

  /// Who priced the current tick (biquote, gold-api, ...). Shown next to the
  /// age so the provenance is on screen. Null for the stored fallback and
  /// before the first tick.
  String? _priceSource;

  /// The tick's provenance for the caption. Null reads as the generic
  /// provider line so a missing source never blanks the caption.
  String? get priceSource => _priceSource;

  /// Age of [price] against the provider's own timestamp, in whole seconds.
  ///
  /// This is what makes a slow-moving price verifiably alive: gold can sit
  /// nearly flat for minutes, and a bare number then looks frozen whether the
  /// feed is healthy or dead. The age ticks on every 5s poll from the
  /// provider's own clock, so "Live - 8s ago" proves freshness while "Live -
  /// 4m ago" would expose a stall. Never derived from the poll time, which
  /// would claim freshness the provider never stated.
  int? get priceAgeSeconds {
    final at = _priceAt;
    if (at == null) return null;
    final age = DateTime.now().toUtc().difference(at).inSeconds;
    return age < 0 ? 0 : age;
  }
  double? _sessionLow;
  double? _sessionHigh;

  /// Previous session's close: the honest reference for the day move. Falls
  /// back to the session's first stored print when the database holds no
  /// prior session; null when neither exists, and the UI says so. Pinned for
  /// the session (see the slow poll): retention pruning must never march it
  /// forward mid-session.
  double? _dayReference;
  DateTime? _refSince;

  /// Whether the reference is a real previous close (true) or the session's
  /// first print (false). The caption names which so the move is auditable.
  bool _refIsClose = false;

  /// The reference the day move is measured against, for the caption.
  double? get dayReference => _dayReference;

  /// True when [dayReference] is the previous close, false for first-print.
  bool get dayReferenceIsClose => _refIsClose;

  /// Day move in price points, or null when no reference exists. Never
  /// derived from the range: low/high extremes are not an open or a close.
  double? get dayMove {
    final p = _price;
    final ref = _dayReference;
    if (p == null || ref == null) return null;
    return p - ref;
  }

  /// Day move as a fraction of the reference (e.g. -0.0123 for -1.23%).
  double? get dayMoveFraction {
    final move = dayMove;
    final ref = _dayReference;
    if (move == null || ref == null || ref == 0) return null;
    return move / ref;
  }
  DisplaySignal? _signal;

  /// Three separate independence metrics. Null before the first poll.
  IndependenceResult? _independence;

  /// Provenance-derived agreement figures. Never merged into one figure.
  IndependenceResult? get independence => _independence;
  List<DisplayHistoryEntry> _history = const [];
  List<DisplayEvent> _events = const [];
  List<DisplayDigestTheme> _digest = const [];

  /// Released events with actuals, newest first — the Results tab's data.
  List<DisplayEvent> _results = const [];

  /// Gold Hunts open session calls, labels only (D-20261006-016).
  ///
  /// Read-only context for the Sources screen's EXTERNAL SESSION VIEW section.
  /// Nothing here votes, confirms, or feeds the agreement math - it is a
  /// separate publisher's published read, shown with attribution, and the
  /// staleness decision travels with each row rather than being recomputed
  /// from a fetch timestamp the UI never sees.
  List<GoldHuntsSessionView> _goldHunts = const [];

  /// Publishers behind the active signal's ideas.
  List<DisplaySource> _contributors = const [];

  // ------------------------------------------------------------------ state

  bool get loading => _loading;

  /// True while an EXPLICIT refresh (pull-to-refresh) is in flight.
  ///
  /// Separate from [loading] on purpose: [loading] means "no data yet", which
  /// only happens on the very first read. Showing skeletons on that basis would
  /// mean flashing the whole list every 15 seconds, so poll-driven reads stay
  /// silent and only a deliberate pull animates the list.
  bool get refreshing => _refreshing;
  bool _refreshing = false;
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  double? get price => _price;
  DateTime? get priceAt => _priceAt;

  /// True when [price] came straight from the provider this poll rather than
  /// from the once-a-minute stored snapshot.
  bool get priceIsLive => _priceIsLive;
  double? get sessionLow => _sessionLow;
  double? get sessionHigh => _sessionHigh;

  /// Newest open signal, or null when there is genuinely none. Null is a
  /// meaningful state, NOT an error: the room may hold no consensus.
  DisplaySignal? get signal => _signal;
  bool get hasSignal => _signal != null;

  List<DisplayHistoryEntry> get history => _history;

  /// Sources that contributed to the active signal, for the Sources screen.
  ///
  /// Empty is a real answer: a signal with no linked idea rows explains
  /// nothing, and showing fixture desks next to live levels would be a lie.
  List<DisplaySource> get contributors => _contributors;
  List<DisplayEvent> get events => _events;
  List<DisplayDigestTheme> get digest => _digest;

  /// Released events carrying actuals, newest first. The Results tab reads
  /// these - never the scheduled rows. An event without an actual is not a
  /// result, and reusing an upcoming release as one would present a forecast
  /// as history.
  List<DisplayEvent> get results => _results;

  /// Gold Hunts open session calls for the Sources screen's external session
  /// view. Context only - never an input to agreement, confirmation, or votes.
  List<GoldHuntsSessionView> get goldHunts => _goldHunts;

  // --------------------------------------------------------------- polling

  /// Start polling. Each timer is cancelled before being replaced — a second
  /// `Timer.periodic` would otherwise leave the previous one pending, which is an
  /// easy way to silently double the request rate.
  void startPolling({int seconds = 15}) {
    _fastTimer?.cancel();
    _slowTimer?.cancel();
    _priceTimer?.cancel();
    _sessionTimer?.cancel();
    // Registered once: startPolling is idempotent and addObserver would
    // otherwise stack duplicate callbacks.
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    _fastTimer = Timer.periodic(Duration(seconds: seconds), (_) => _pollFast());
    // Scheduled calendar and history rows change on the order of minutes to
    // hours. Re-reading them on every price tick was the cause of the Events
    // screen visibly re-rendering several times a minute: each poll replaced the
    // rows with fresh objects, so every countdown re-pinned and the whole list
    // rebuilt for data that had not moved.
    _slowTimer = Timer.periodic(_slowInterval, (_) => _pollSlow());
    _priceTimer =
        Timer.periodic(_priceInterval, (_) => _pollPrice());
    // Baseline without notifying: the screens already render the current
    // state from their first build, so announcing it again would rebuild
    // everything ten seconds into the session for no visible change.
    _lastSessionOpen = isSessionOpen(DateTime.now().toUtc());
    _sessionTimer =
        Timer.periodic(_sessionWatchInterval, (_) => _watchSession());
    _pollFast();
    _pollSlow();
  }

  static const _slowInterval = Duration(minutes: 5);

  /// Price-only refresh interval. One HTTPS GET against a provider that places
  /// no limit on the real-time endpoint, so this is cheap and stays independent
  /// of how often the database-backed sections are read.
  static const _priceInterval = Duration(seconds: 5);

  /// Applies one price tick to the quote and the session extremes.
  ///
  /// Shared by the 5s price ticker and the full refresh so both paths fold
  /// ticks identically (tests drive it through [refresh]). Returns whether
  /// anything the screens show actually moved.
  bool _applyPrice(double? price, DateTime? at, bool live, String? source) {
    if (price == null) return false;
    var moved = false;
    if (price != _price) {
      _price = price;
      _priceAt = at;
      _priceIsLive = live;
      moved = true;
    } else {
      // Same price, but freshness is still a fact worth recording: a value that
      // held steady for a minute is different evidence from a value that has
      // not been re-confirmed in a minute.
      _priceIsLive = live;
    }
    // A provider flip (biquote to gold-api fallback) changes the caption even
    // when the number holds still.
    if (source != _priceSource) {
      _priceSource = source;
      moved = true;
    }
    if (_sessionLow == null || price < _sessionLow!) {
      _sessionLow = price;
      moved = true;
    }
    if (_sessionHigh == null || price > _sessionHigh!) {
      _sessionHigh = price;
      moved = true;
    }
    return moved;
  }

  Future<void> _pollPrice() async {
    final price = await _repo.directSpotPrice();
    if (_applyPrice(price.price, price.at, price.live, price.source)) notifyListeners();
  }

  Future<void> _pollFast() =>
      _refresh(includeSlowSections: false, manual: false);

  Future<void> _pollSlow() =>
      _refresh(includeSlowSections: true, manual: false);

  /// One session check. Notifies listeners if and only if the market flipped
  /// since the last check, so the open/closed surfaces (pill, closed card,
  /// gated actions) re-derive within seconds of a halt or reopen instead of
  /// waiting for an unrelated data change.
  ///
  /// [at] is the clock seam: production passes nothing and reads the real
  /// clock, tests pass fixed instants on either side of a boundary.
  void checkSession({DateTime? at}) {
    final open = isSessionOpen((at ?? _clock()).toUtc());
    if (_lastSessionOpen == null) {
      _lastSessionOpen = open;
      return;
    }
    if (open != _lastSessionOpen) {
      _lastSessionOpen = open;
      notifyListeners();
    }
  }

  void _watchSession() => checkSession();

  void stopPolling() {
    _fastTimer?.cancel();
    _fastTimer = null;
    _slowTimer?.cancel();
    _slowTimer = null;
    _priceTimer?.cancel();
    _priceTimer = null;
    _sessionTimer?.cancel();
    _sessionTimer = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
  }

  /// Full read, used by pull-to-refresh and by the slow poll.
  Future<void> refresh() => _refresh(includeSlowSections: true, manual: true);

  /// Fetch what the app shows.
  ///
  /// [includeSlowSections] pulls the scheduled calendar, the history log and
  /// the news digest alongside the live quote. Individual failures are
  /// tolerated: a failed section keeps its previous value and only records the
  /// error, so one slow table cannot blank the whole screen.
  Future<void> _refresh({
    required bool includeSlowSections,
    required bool manual,
  }) async {
    // Notify immediately, before the first await. Otherwise the UI only learns
    // about the refresh when it finishes, and the skeletons never appear at all.
    if (manual) {
      _refreshing = true;
      notifyListeners();
    }
    _loading = _signal == null && _price == null;
    var changed = false;
    try {
      // Direct provider read, so the price moves with the market rather than
      // with the once-a-minute cron. Falls back to the stored snapshot inside
      // directSpotPrice, which reports `live: false` so the UI can say so.
      // Folds through the same tick path as the price ticker (extremes move
      // with it, no extra network).
      final price = await _repo.directSpotPrice();
      if (_applyPrice(price.price, price.at, price.live, price.source)) changed = true;
      _priceIsLive = price.live;

      // A null signal is a legitimate "no setup right now" — clear it rather
      // than keeping a stale signal on screen.
      final signal = await _repo.activeSignal();
      if (signal?.id != _signal?.id || signal?.status != _signal?.status) {
        changed = true;
      }
      _signal = signal;
      if (signal != null) {
        final eligible = await _repo.enabledSourceCount();
        _contributors = await _repo.contributingSources(signal.id);

        // Independence is scored from provenance, never from row counts. The
        // three metrics stay separate and are never merged: a derived reader
        // contributes to methods and datasets, never to sources.
        final provenance = await _repo.ideaProvenance(signal.id);
        final scored = const IndependenceScorer().score(
          IdeaAgreement(
            direction: signal.direction == Direction.long ? 'LONG' : 'SHORT',
            ideas: provenance,
          ),
          eligiblePublishers: eligible,
        );
        // When no eligible external source exists the UI must say so rather
        // than render "0 of 0". That is a state, not an error, and the scorer
        // already exposes it via isAwaitingExternalSources.
        _independence = scored;

        _signal = DisplaySignal(
          id: signal.id,
          direction: signal.direction,
          strength: signal.strength,
          entryLow: signal.entryLow,
          entryHigh: signal.entryHigh,
          stopLoss: signal.stopLoss,
          tp1: signal.tp1,
          tp2: signal.tp2,
          tp3: signal.tp3,
          status: signal.status,
          agreeCount: scored.externalVoices,
          totalCount: eligible,
        );
      } else {
        _independence = null;
        _contributors = const [];
      }

      var slowFailed = false;
      if (includeSlowSections) {
        // Scheduled releases, the closed-setup log, the news digest and the
        // external session view. Slow by nature, so they are only re-read on
        // the slow cadence, on resume, or on an explicit pull.
        //
        // Each section is fenced: previously one failing read aborted the
        // rest, so a hiccup in history could starve the session view (or vice
        // versa) until a manual pull happened to succeed end to end. A failed
        // section keeps its previous value and is named in the error line.
        var slowFailures = <String>[];
        Future<void> guarded(String name, Future<void> Function() fn) async {
          try {
            await fn();
          } catch (e) {
            slowFailed = true;
            slowFailures.add('$name: $e');
          }
        }

        await guarded('history', () async { _history = await _repo.history(); });
        await guarded('events', () async { _events = await _repo.upcomingEvents(); });
        await guarded('results', () async { _results = await _repo.resultEvents(); });
        await guarded('digest', () async { _digest = await _repo.latestDigest(); });
        // Session extremes + day-move reference, re-anchored against full
        // session history. Between these runs the price ticker folds ticks in
        // locally, so the range is never older than the newest tick; this
        // pass corrects any drift (a bad print can only widen the folded
        // extremes, never narrow them back).
        await guarded('session-range', () async {
          final since = sessionStartUtc(DateTime.now().toUtc());
          final stats = await _repo.sessionStats(since: since);
          if (stats.low != null && stats.high != null) {
            var lo = stats.low!;
            var hi = stats.high!;
            // The stats read is older than the newest tick by construction:
            // fold the live quote back in so a fresh extreme is never
            // clobbered by the re-anchor.
            final p = _price;
            if (p != null) {
              if (p < lo) lo = p;
              if (p > hi) hi = p;
            }
            _sessionLow = lo;
            _sessionHigh = hi;
          }
          // The reference pins per session: re-resolving it every poll lets
          // retention pruning march it forward mid-session, and the day move
          // would drift with no price movement at all.
          if (_dayReference == null || _refSince != since) {
            _dayReference = stats.prevClose ?? stats.firstPrint;
            _refIsClose = stats.prevClose != null;
            _refSince = since;
          }
        });
        // External session view, same slow cadence: the provider regenerates
        // hourly, so reading it faster only rebuilds the section against
        // unchanged rows.
        await guarded('session-view',
            () async { _goldHunts = await _repo.goldHuntsSessionViews(); });
        if (slowFailed) {
          _error = 'Slow refresh partial: ${slowFailures.join(' · ')}';
        }
        changed = true;
      }

      _lastUpdated = DateTime.now();
      // A partial slow failure above already wrote an honest _error; clearing
      // it here would report success for a run that was not one. A fully
      // successful run still clears a stale error as before.
      if (!includeSlowSections || !slowFailed) _error = null;
      // Deliberately NOT marked as changed. Bumping the freshness stamp alone
      // is not a data change, and notifying on it rebuilt every screen - the
      // Events list visibly several times a minute - for a timestamp that had
      // moved by a second. Screens that show "updated Xs ago" re-read it on the
      // next real change or the next pull.
    } catch (e) {
      // Keep the last good values on screen and surface the failure, rather
      // than replacing real data with nothing (or with fixtures).
      _error = '$e';
      // Notify anyway: the error line must appear.
      changed = true;
} finally {
      _loading = false;
      if (manual) {
        _refreshing = false;
        // A deliberate pull must always repaint, even if nothing changed, so
        // the skeleton resolves back to the real rows.
        changed = true;
      }
      // Only wake listeners when something actually moved. Notifying on every
      // poll rebuilt every screen several times a minute for identical data,
      // which is what made the Events list look like it was constantly
      // refreshing.
      if (changed) notifyListeners();
    }
  }

  /// Live stream of the active signal (Realtime), used by the Signal screen
  /// when available so lifecycle changes appear without waiting for a poll.
  Stream<Map<String, Object?>> activeSignalStream() {
    return Supabase.instance.client
        .from('consensus_signals')
        .stream(primaryKey: ['id'])
        .map((rows) => rows.isEmpty ? <String, Object?>{} : rows.first);
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
