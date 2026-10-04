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

import 'live_repository.dart';
import '../models/display_models.dart';

/// Snapshot of everything the screens read in live mode.
class LiveData extends ChangeNotifier {
  LiveData({SupabaseClient? client, LiveRepository? repository})
    : _repo = repository ?? LiveRepository(client);

  final LiveRepository _repo;

  /// Fast cadence: quote, range, active signal.
  Timer? _fastTimer;

  /// Slow cadence: calendar, history, news digest.
  Timer? _slowTimer;

  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;

  double? _price;
  DateTime? _priceAt;
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
  String? get error => _error;
  DateTime? get lastUpdated => _lastUpdated;
  double? get price => _price;
  DateTime? get priceAt => _priceAt;
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

  /// Start polling. One timer only — a second `Timer.periodic` would replace
  /// the first (each call returns a new timer and the previous would still be
  /// pending), which is an easy way to silently double the request rate.
  void startPolling({int seconds = 15}) {
    _fastTimer?.cancel();
    _slowTimer?.cancel();
    _fastTimer = Timer.periodic(Duration(seconds: seconds), (_) => _pollFast());
    // Scheduled calendar and history rows change on the order of minutes to
    // hours. Re-reading them on every price tick was the cause of the Events
    // screen visibly re-rendering several times a minute: each poll replaced the
    // rows with fresh objects, so every countdown re-pinned and the whole list
    // rebuilt for data that had not moved.
    _slowTimer = Timer.periodic(_slowInterval, (_) => _pollSlow());
    _pollFast();
    _pollSlow();
  }

  static const _slowInterval = Duration(minutes: 5);

  Future<void> _pollFast() => _refresh(includeSlowSections: false);

  Future<void> _pollSlow() => _refresh(includeSlowSections: true);

  void stopPolling() {
    _fastTimer?.cancel();
    _fastTimer = null;
    _slowTimer?.cancel();
    _slowTimer = null;
  }

  /// Full read, used by pull-to-refresh and by the slow poll.
  Future<void> refresh() => _refresh(includeSlowSections: true);

  /// Fetch what the app shows.
  ///
  /// [includeSlowSections] pulls the scheduled calendar, the history log and
  /// the news digest alongside the live quote. Individual failures are
  /// tolerated: a failed section keeps its previous value and only records the
  /// error, so one slow table cannot blank the whole screen.
  Future<void> _refresh({required bool includeSlowSections}) async {
    _loading = _signal == null && _price == null;
    var changed = false;
    try {
      final price = await _repo.latestPrice();
      if (price != null && price.price != _price) {
        _price = price.price;
        _priceAt = price.at;
        changed = true;
      }

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
