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

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xau_core/analysis/independence.dart';
import 'package:xau_core/analysis/session.dart';

import 'live_repository.dart';
import '../models/display_models.dart';

/// Snapshot of everything the screens read in live mode.
class LiveData extends ChangeNotifier {
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
  DisplaySignal? _signal;

  /// Three separate independence metrics. Null before the first poll.
  IndependenceResult? _independence;

  /// Provenance-derived agreement figures. Never merged into one figure.
  IndependenceResult? get independence => _independence;
  List<DisplayHistoryEntry> _history = const [];
  List<DisplayEvent> _events = const [];
  List<DisplayDigestTheme> _digest = const [];

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

  // --------------------------------------------------------------- polling

  /// Start polling. Each timer is cancelled before being replaced — a second
  /// `Timer.periodic` would otherwise leave the previous one pending, which is an
  /// easy way to silently double the request rate.
  void startPolling({int seconds = 15}) {
    _fastTimer?.cancel();
    _slowTimer?.cancel();
    _priceTimer?.cancel();
    _sessionTimer?.cancel();
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

  /// Updates the price alone.
  ///
  /// Deliberately does not go through [_refresh]: that would drag the signal,
  /// session range and independence numbers along on every 5s tick and rebuild
  /// screens whose data has not changed.
  Future<void> _pollPrice() async {
    final price = await _repo.directSpotPrice();
    if (price.price == null) return;
    if (price.price != _price) {
      _price = price.price;
      _priceAt = price.at;
      _priceIsLive = price.live;
      notifyListeners();
    } else {
      // Same price, but freshness is still a fact worth recording: a value that
      // held steady for a minute is different evidence from a value that has
      // not been re-confirmed in a minute.
      _priceIsLive = price.live;
    }
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
      final price = await _repo.directSpotPrice();
      if (price.price != null && price.price != _price) {
        _price = price.price;
        _priceAt = price.at;
        changed = true;
      }
      _priceIsLive = price.live;

      final range = await _repo.sessionRange();
      if (range != null && (range.low != _sessionLow || range.high != _sessionHigh)) {
        _sessionLow = range.low;
        _sessionHigh = range.high;
        changed = true;
      }

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

      if (includeSlowSections) {
        // Scheduled releases, the closed-setup log and the news digest. Slow
        // by nature, so they are only re-read on the slow cadence or on an
        // explicit pull.
        _history = await _repo.history();
        _events = await _repo.upcomingEvents();
        _digest = await _repo.latestDigest();
        changed = true;
      }

      _lastUpdated = DateTime.now();
      _error = null;
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
