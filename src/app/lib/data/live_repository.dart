/// Live backend repository — reads XV data from Supabase (PostgREST).
///
/// SPLIT OF RESPONSIBILITY
/// `mockMode == true`  → every screen renders from [MockFixtures], offline,
///                        zero configuration. This stays the default so a
/// fresh clone runs with no credentials.
/// `mockMode == false` → screens read through this class. The *display models*
/// stay the same shape as the mock path, so no screen has to know whether it
/// is looking at fixtures or the real database. That keeps the UI layer honest:
/// the same widget tree proves both paths.
///
/// NEVER FABRICATE: a missing row yields a null/empty result and the screen
/// shows its honest empty state. No placeholder price, no invented level.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/display_models.dart';

/// Raw row shapes as returned by PostgREST (snake_case).
typedef Row = Map<String, dynamic>;

/// XV live data, read-only from the app's perspective.
class LiveRepository {
  LiveRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  // ---------------------------------------------------------------- market

  /// Newest price snapshot. Null when the ticker has not run yet — the caller
  /// must render a "waiting for first tick" state, not a fake price.
  Future<({double price, DateTime at})?> latestPrice() async {
    final r = await _client
        .from('market_snapshots')
        .select('price, timestamp')
        .eq('symbol', 'XAUUSD')
        .order('timestamp', ascending: false)
        .limit(1)
        .maybeSingle();
    if (r == null) return null;
    final price = _toDouble(r['price']);
    if (price == null) return null;
    return (price: price, at: DateTime.parse(r['timestamp'] as String));
  }

  /// Session high/low derived from stored snapshots (the DB has no range
  /// column; this is real observed data, not an estimate).
  Future<({double low, double high})?> sessionRange() async {
    final r = await _client
        .from('market_snapshots')
        .select('price')
        .eq('symbol', 'XAUUSD')
        .order('timestamp', ascending: false)
        .limit(500);
    final values = (r as List)
        .map((row) => _toDouble((row as Row)['price']))
        .whereType<double>()
        .toList();
    if (values.isEmpty) return null;
    return (
      low: values.reduce((a, b) => a < b ? a : b),
      high: values.reduce((a, b) => a > b ? a : b),
    );
  }

  // -------------------------------------------------------------- consensus

  /// The newest open signal, mapped to [DisplaySignal]. Null when the room is
  /// empty — which is a legitimate, common state (NO CONSENSUS), not an error.
  Future<DisplaySignal?> activeSignal() async {
    final r = await _client
        .from('consensus_signals')
        .select('*')
        .eq('symbol', 'XAUUSD')
        .inFilter('status',
            ['DEVELOPING', 'READY', 'CONFIRMED', 'ACTIVE', 'TP1_HIT', 'TP2_HIT'])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (r == null) return null;
    return _toDisplaySignal(r);
  }

  /// How many independent ideas contributed to [signalId].
  ///
  /// Counts DISTINCT `trade_idea_id`: re-running build-consensus can leave
  /// more than one link row per idea, and a raw row count over-reports
  /// agreement (the app once showed "11 of 11 sources" for a single setup).
  Future<int> agreeingSourceCount(String signalId) async {
    final r = await _client
        .from('signal_sources')
        .select('trade_idea_id')
        .eq('signal_id', signalId);
    final ids = (r as List)
        .map((row) => '${(row as Row)['trade_idea_id']}')
        .toSet();
    return ids.length;
  }

  /// Closed signals for the History tab.
  Future<List<DisplayHistoryEntry>> history({int limit = 50}) async {
    final r = await _client
        .from('consensus_signals')
        .select('*')
        .inFilter(
            'status', ['TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'INVALIDATED', 'EXPIRED'])
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List)
        .map((row) => _toHistoryEntry(row as Row))
        .toList();
  }

  // ----------------------------------------------------------------- events

  Future<List<DisplayEvent>> upcomingEvents({int limit = 20}) async {
    final r = await _client
        .from('economic_events')
        .select('*')
        .gte('starts_at', DateTime.now().toIso8601String())
        .order('starts_at', ascending: true)
        .limit(limit);
    return (r as List).map((row) => _toEvent(row as Row)).toList();
  }

  /// Most recent macro digest. Empty when news-digest has not run — the
  /// Events screen renders its honest "no digest yet" state.
  Future<List<DisplayDigestTheme>> latestDigest() async {
    final r = await _client
        .from('news_digests')
        .select('themes')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (r == null) return const [];
    final themes = r['themes'];
    if (themes is! List) return const [];
    return themes.whereType<Map>().map((t) {
      return DisplayDigestTheme(
        theme: '${t['theme'] ?? 'Unknown'}',
        pressure: _pressure('${t['pressure'] ?? 'UNCLEAR'}'),
        evidenceCount:
            (t['evidence_urls'] is List) ? (t['evidence_urls'] as List).length : 0,
      );
    }).toList();
  }

  static NewsPressure _pressure(String raw) {
    switch (raw) {
      case 'HAWKISH':
        return NewsPressure.hawkish;
      case 'DOVISH':
        return NewsPressure.dovish;
      case 'NEUTRAL':
        return NewsPressure.neutral;
      default:
        // Never coerce an unknown pressure into a directional claim.
        return NewsPressure.unclear;
    }
  }

  // --------------------------------------------------------------- mapping

  /// DB `SCREAMING_CASE` → display enum. Mirrors `toEngineStatus` in
  /// `_shared/engine.ts` — the same boundary rule on both sides.
  static DisplayStatus? _status(String? raw) {
    switch (raw) {
      case 'NO_SETUP':
        return DisplayStatus.noSetup;
      case 'DEVELOPING':
        return DisplayStatus.developing;
      case 'READY':
        return DisplayStatus.ready;
      case 'CONFIRMED':
        return DisplayStatus.confirmed;
      case 'ACTIVE':
        return DisplayStatus.active;
      case 'TP1_HIT':
        return DisplayStatus.tp1Hit;
      case 'TP2_HIT':
        return DisplayStatus.tp2Hit;
      case 'TP3_HIT':
        return DisplayStatus.tp3Hit;
      case 'INVALIDATED':
        return DisplayStatus.invalidated;
      case 'EXPIRED':
        return DisplayStatus.expired;
      default:
        return null;
    }
  }

  static Direction? _direction(String? raw) {
    switch (raw) {
      case 'long':
        return Direction.long;
      case 'short':
        return Direction.short;
      case 'neutral':
        return Direction.neutral;
      default:
        return null;
    }
  }

  /// A signal row is only usable when every REQUIRED field parsed; otherwise
  /// null. A half-populated signal must never reach the UI as a real setup.
  DisplaySignal? _toDisplaySignal(Row r) {
    final dir = _direction(r['direction'] as String?);
    final status = _status(r['status'] as String?);
    final entryLow = _toDouble(r['entry_low']);
    final entryHigh = _toDouble(r['entry_high']);
    final stop = _toDouble(r['stop_loss']);
    final strength = _toInt(r['strength']);
    if (dir == null ||
        status == null ||
        entryLow == null ||
        entryHigh == null ||
        stop == null ||
        strength == null) {
      return null;
    }
    return DisplaySignal(
      id: '${r['id']}',
      direction: dir,
      strength: strength,
      entryLow: entryLow,
      entryHigh: entryHigh,
      stopLoss: stop,
      tp1: _toDouble(r['tp1']),
      tp2: _toDouble(r['tp2']),
      tp3: _toDouble(r['tp3']),
      status: status,
      agreeCount: 0, // filled by the caller via agreeingSourceCount
      totalCount: 0,
    );
  }

  DisplayHistoryEntry _toHistoryEntry(Row r) {
    final dir = _direction(r['direction'] as String?);
    final status = _status(r['status'] as String?);
    final entryLow = _toDouble(r['entry_low']);
    final entryHigh = _toDouble(r['entry_high']);
    final stop = _toDouble(r['stop_loss']);
    final at = DateTime.tryParse('${r['created_at']}');

    // Distance from entry mid to stop, in POINTS (canonical unit — the pip
    // display convention is applied by the view layer). Zero when unknown.
    final outcome = (entryLow != null && entryHigh != null && stop != null)
        ? ((entryLow + entryHigh) / 2 - stop)
        : 0.0;

    return DisplayHistoryEntry(
      direction: dir,
      whenText: at == null
          ? '-'
          : '${_hhmm(at)} · ${_relativeDay(at)}',
      detailText: (entryLow != null && entryHigh != null && stop != null)
          ? 'IN ${formatLevel(entryLow)}-${formatLevel(entryHigh)}'
              ' · SL ${formatLevel(stop)}'
          : 'Levels unavailable',
      status: status,
      pipsPoints: outcome,
    );
  }

  DisplayEvent _toEvent(Row r) {
    final startsAt = DateTime.tryParse('${r['starts_at']}') ?? DateTime.now();
    return DisplayEvent(
      id: '${r['id']}',
      title: '${r['title'] ?? 'Event'}',
      currency: '${r['currency'] ?? 'USD'}',
      impact: _impact('${r['impact'] ?? 'LOW'}'),
      startsIn: startsAt.difference(DateTime.now()),
      forecast: _numText(r['forecast']),
      previous: _numText(r['previous']),
      actual: _numText(r['actual']),
      surprise: _surprise(r['surprise'] as String?),
    );
  }

  /// DB surprise flag → display model. `DisplayEvent.surprise` is a free-text
  /// String, so keep the DB vocabulary verbatim rather than inventing labels.
  static String? _surprise(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  /// PostgREST NUMERIC → the display model's String? fields. Null stays null
  /// so a missing actual/forecast renders as "-", never as "0".
  static String? _numText(Object? v) {
    final d = _toDouble(v);
    if (d == null) return null;
    return d == d.roundToDouble()
        ? d.toInt().toString()
        : d.toStringAsFixed(2);
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _relativeDay(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    if (days == 0) return 'TODAY';
    if (days == 1) return 'YESTERDAY';
    if (days < 7) return '$days DAYS AGO';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }

  static EventImpact _impact(String raw) {
    switch (raw) {
      case 'HIGH':
        return EventImpact.high;
      case 'MEDIUM':
        return EventImpact.medium;
      default:
        return EventImpact.low;
    }
  }

  // PostgREST returns NUMERIC as a JSON string or a number depending on the
  // column type — handle both, and reject anything non-finite.
  static double? _toDouble(Object? v) {
    if (v is num) return v.isFinite ? v.toDouble() : null;
    if (v is String) return double.tryParse(v);
    return null;
  }

  static int? _toInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }
}