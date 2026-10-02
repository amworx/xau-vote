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

import 'live_repository.dart';
import '../models/display_models.dart';

/// Snapshot of everything the screens read in live mode.
class LiveData extends ChangeNotifier {
  LiveData({SupabaseClient? client, LiveRepository? repository})
      : _repo = repository ?? LiveRepository(client);

  final LiveRepository _repo;
  Timer? _timer;

  bool _loading = true;
  String? _error;
  DateTime? _lastUpdated;

  double? _price;
  DateTime? _priceAt;
  double? _sessionLow;
  double? _sessionHigh;
  DisplaySignal? _signal;
  List<DisplayHistoryEntry> _history = const [];
  List<DisplayEvent> _events = const [];
  List<DisplayDigestTheme> _digest = const [];

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
  List<DisplayEvent> get events => _events;
  List<DisplayDigestTheme> get digest => _digest;

  // --------------------------------------------------------------- polling

  /// Start polling. One timer only — a second `Timer.periodic` would replace
  /// the first (each call returns a new timer and the previous would still be
  /// pending), which is an easy way to silently double the request rate.
  void startPolling({int seconds = 15}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: seconds), (_) => refresh());
    refresh();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fetch everything the app shows. Individual failures are tolerated: a
  /// failed section keeps its previous value and only records the error, so
  /// one slow table cannot blank the whole screen.
  Future<void> refresh() async {
    _loading = _signal == null && _price == null;
    try {
      final price = await _repo.latestPrice();
      if (price != null) {
        _price = price.price;
        _priceAt = price.at;
      }

      final range = await _repo.sessionRange();
      if (range != null) {
        _sessionLow = range.low;
        _sessionHigh = range.high;
      }

      // A null signal is a legitimate "no setup right now" — clear it rather
      // than keeping a stale signal on screen.
      final signal = await _repo.activeSignal();
      _signal = signal;
      if (signal != null) {
        final agree = await _repo.agreeingSourceCount(signal.id);
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
          agreeCount: agree,
          totalCount: agree,
        );
      }

      _history = await _repo.history();
      _events = await _repo.upcomingEvents();
      _digest = await _repo.latestDigest();

      _lastUpdated = DateTime.now();
      _error = null;
    } catch (e) {
      // Keep the last good values on screen and surface the failure, rather
      // than replacing real data with nothing (or with fixtures).
      _error = '$e';
    } finally {
      _loading = false;
      notifyListeners();
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