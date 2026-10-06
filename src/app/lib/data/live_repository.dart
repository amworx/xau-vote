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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:xau_core/xau_core.dart' hide Direction;

import '../models/display_models.dart';
import '../models/sentiment_layers.dart';
import '../config.dart' as config;

/// Raw row shapes as returned by PostgREST (snake_case).
typedef Row = Map<String, dynamic>;

/// XV live data, read-only from the app's perspective.
class LiveRepository {
  LiveRepository([SupabaseClient? client, http.Client? httpClient])
      : _client = client ?? Supabase.instance.client,
        _http = httpClient ?? _sharedHttp();

  final SupabaseClient _client;

  /// Used only for the direct spot-price read. Injected in tests so no network
  /// call escapes a unit test.
  final http.Client _http;

  /// One client for the whole app, created on first use.
  ///
  /// Deliberately not per-repository and deliberately not closed. The price is
  /// polled every few seconds, so a shared client keeps one warm connection
  /// instead of re-handshaking constantly, and several repositories may exist
  /// (AnalysisService builds its own). A client that nobody closes would be a
  /// leak if it were per-instance; making it app-scoped is what removes the need
  /// to close it at all.
  static http.Client? _shared;
  static http.Client _sharedHttp() => _shared ??= http.Client();

  /// Edge Functions base for this project, from the build-time URL.
  static String get _supabaseFunctionsUrl {
    if (config.supabaseUrl.isEmpty) return '';
    return '${config.supabaseUrl}/functions/v1';
  }

  static String get _anonKey => config.supabasePublishableKey;

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
        .inFilter('status', [
          'DEVELOPING',
          'READY',
          'CONFIRMED',
          'ACTIVE',
          'TP1_HIT',
          'TP2_HIT',
        ])
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (r == null) return null;
    return _toDisplaySignal(r);
  }

  /// Distinct idea and source counts behind [signalId].
  ///
  /// Two numbers, because they answer different questions and conflating them
  /// overstates agreement:
  ///
  ///   * `distinctIdeas` — distinct `trade_idea_id` link rows.
  ///   * `distinctSources` — distinct `sources.id` behind those ideas, which is
  ///     what product rule 3 actually means by "independent source".
  ///
  /// The manual seed collector writes a new idea each run with slightly
  /// different levels, so idea count alone made a single source look like broad
  /// agreement: the app once displayed "11 of 11 sources" for one source.
  /// How many sources could have voted: the enabled ones.
  ///
  /// The sources that actually contributed to [signalId], for the Sources
  /// screen's row list.
  ///
  /// Reads through `signal_sources` rather than counting rows, so the list and
  /// the agreement headline describe the same set. Each idea is attributed to
  /// its publisher via `source_id`; an idea with no publisher is attributed to
  /// its methodology, because "no source" must stay visible rather than being
  /// silently dropped from the list that explains the count.
  Future<List<DisplaySource>> contributingSources(String signalId) async {
    final links = await _client
        .from('signal_sources')
        .select('trade_idea_id')
        .eq('signal_id', signalId);
    if (links.isEmpty) return const [];

    final ids = (links as List)
        .map((row) => '${(row as Row)['trade_idea_id']}')
        .where((s) => s.isNotEmpty && s != 'null')
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];

    final ideas = await _client
        .from('trade_ideas')
        .select(
          // Targets live in the `take_profits` array column. There are no
          // target_1/2/3 columns: an earlier query used them and PostgREST
          // rejected the whole read with "column does not exist", which emptied
          // the Sources screen.
          'id,source_id,direction,entry_low,entry_high,stop_loss,'
          'take_profits,methodology_id,upstream_dataset_id,published_at,'
          'fingerprint,author_ref',
        )
        .inFilter('id', ids);
    if (ideas.isEmpty) return const [];

    final sourceIds = (ideas as List)
        .map((r) => '${(r as Row)['source_id']}')
        .where((s) => s.isNotEmpty && s != 'null')
        .toSet()
        .toList();

    // Publisher names and licence standing, keyed by source id. Levels are not
    // taken from here: several ideas can share one publisher, and the first
    // idea's levels would then be attributed to all of them. Levels are taken
    // per idea below.
    final publisherNames = <String, String>{};
    final publisherLicensed = <String, bool>{};
    if (sourceIds.isNotEmpty) {
      final src = await _client
          .from('sources')
          .select('id,name,commercial_use_allowed')
          .inFilter('id', sourceIds);
      for (final s in (src as List)) {
        final row = s as Row;
        final id = '${row['id']}';
        publisherNames[id] = '${row['name'] ?? id}';
        publisherLicensed[id] = '${row['commercial_use_allowed']}' == 'true';
      }
    }
// One row per PUBLISHER, not per idea. Several ideas from one desk are one
    // vote (product rule 3): listing six rows all named "manual-seed" made one
    // source look like six, which is the exact miscount the independence model
    // exists to prevent. The first idea per publisher supplies the levels.
    final bySource = <String, DisplaySource>{};
    for (final r in ideas as List) {
      final row = r as Row;
      final srcId = '${row['source_id']}';
      final hasPublisher = srcId.isNotEmpty && srcId != 'null';
      final method = '${row['methodology_id']}';
      final key = hasPublisher ? srcId : 'no-publisher';
      if (bySource.containsKey(key)) continue;
      final dataset = '${row['upstream_dataset_id']}';
      bySource[key] = DisplaySource(
        id: key,
        name: hasPublisher
            ? (publisherNames[srcId] ?? srcId)
            // No publisher: name the row after its own provenance so it is not
            // blank, and say plainly that it is unattributed.
            : (method.isEmpty || method == 'null'
                  ? 'Unattributed idea'
                  : method),
        direction: directionOf('${row['direction']}'),
        agrees: true,
        entryText: _zone(row, 'entry_low', 'entry_high'),
        stopText: _level(row['stop_loss']),
        targetsText: _targets(row),
        freshnessText: _age(row['published_at']),
        // Never invent a rationale: the row states what it can prove and shows
        // a dash where the pipeline has nothing.
        reasoning: dataset.isEmpty || dataset == 'null'
            ? 'No upstream dataset recorded'
            : 'Upstream dataset: $dataset',
        sourceUrl: '',
        tp1HitRate: 0,
        tp2HitRate: 0,
        tp3HitRate: 0,
      );
    }
    return bySource.values.toList(growable: false);
  }
  /// DB direction text → the display enum, defaulting to neutral.
  ///
  /// Neutral is the safe default rather than a guess: an unrecognised value
  /// means the pipeline stored something this build does not understand, and
  /// claiming a side would be inventing one.
  static Direction directionOf(String? raw) => _direction(raw) ?? Direction.neutral;

  /// `4,138.16-4,143.16` from a low/high pair; `-` when either is absent.
  static String _zone(Row row, String lowKey, String highKey) {
    final low = _toDouble(row[lowKey]);
    final high = _toDouble(row[highKey]);
    if (low == null || high == null) return '-';
    return '${formatLevel(low)}-${formatLevel(high)}';
  }

  static String _level(Object? v) {
    final d = _toDouble(v);
    return d == null ? '-' : formatLevel(d);
  }

  /// The targets the idea actually published, in order.
  ///
  /// `take_profits` is a numeric ARRAY column, so it arrives as a List. There
  /// are no per-target columns.
  static String _targets(Row row) {
    final raw = row['take_profits'];
    if (raw is! List) return '-';
    final parts = raw.map(_toDouble).whereType<double>().map(formatLevel).toList();
    return parts.isEmpty ? '-' : parts.join(' · ');
  }

  /// Relative age of an idea, e.g. `12m`. Absent → `-`, never a guess.
  static String _age(Object? publishedAt) {
    final at = DateTime.tryParse('${publishedAt ?? ''}');
    if (at == null) return '-';
    final s = DateTime.now().difference(at.toLocal()).inSeconds;
    if (s < 0) return 'now';
    if (s < 3600) return '${(s / 60).floor()}m';
    if (s < 86400) return '${(s / 3600).floor()}h';
    return '${(s / 86400).floor()}d';
  }

  /// Eligible publishers: sources whose license permits commercial use.
  ///
  /// This is the denominator for "N of M". Using the agreement count as its own
  /// denominator made the figure a tautology, so a lone source could never be
  /// distinguished from broad consensus.
  Future<int> enabledSourceCount() async {
    final r = await _client
        .from('eligible_external_sources')
        .select('id')
        .eq('is_eligible_external', true);
    return (r as List).length;
  }

  /// Provenance for the ideas behind [signalId], for independence scoring.
  ///
  /// Reads `model_owner` rather than inferring it: a `us` model is never an
  /// independent source no matter how many datasets it reads.
  Future<List<IdeaProvenance>> ideaProvenance(String signalId) async {
    final links = await _client
        .from('signal_sources')
        .select('trade_idea_id')
        .eq('signal_id', signalId);
    if (links.isEmpty) return const [];
    final ids = (links as List)
        .map((row) => '${(row as Row)['trade_idea_id']}')
        .toSet()
        .toList();
    if (ids.isEmpty) return const [];

    final rows = await _client
        .from('trade_ideas')
        .select(
          'id,direction,model_owner,source_id,author_ref,upstream_dataset_id,'
          'methodology_id,event_window,published_at,fingerprint',
        )
        .inFilter('id', ids);
    if (rows.isEmpty) return const [];

    // Publisher id comes from the joined source, not the idea, so two ideas
    // from one desk collapse to one voice.
    final sourceIds = (rows as List)
        .map((r) => '${(r as Row)['source_id']}')
        .where((s) => s.isNotEmpty && s != 'null')
        .toSet()
        .toList();
    final names = <String, String>{};
    if (sourceIds.isNotEmpty) {
      final src = await _client
          .from('sources')
          .select('id,name,commercial_use_allowed')
          .inFilter('id', sourceIds);
      for (final s in (src as List)) {
        names['${(s as Row)['id']}'] = '${s['name'] ?? s['id']}';
      }
    }

    return rows.map((row) {
      final at = DateTime.tryParse('${row['published_at']}')?.toUtc();
      final owner = switch ('${row['model_owner']}') {
        'third_party' => ModelOwner.thirdParty,
        'us' => ModelOwner.us,
        _ => ModelOwner.unknown,
      };
      final srcId = '${row['source_id']}';
      return IdeaProvenance(
        ideaId: '${row['id']}',
        direction: '${row['direction']}',
        modelOwner: owner,
        publisherId: names[srcId],
        authorId: _blankToNull(row['author_ref']),
        upstreamDataset: _blankToNull(row['upstream_dataset_id']),
        methodologyId: _blankToNull(row['methodology_id']),
        publishedAt: at ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        eventWindow: _blankToNull(row['event_window']),
        derived: owner != ModelOwner.thirdParty,
      );
    }).toList();
  }

  static String? _blankToNull(Object? v) {
    final s = '$v';
    return (s.isEmpty || s == 'null') ? null : s;
  }

  Future<({int distinctIdeas, int distinctSources})> agreementCount(
    String signalId,
  ) async {
    final r = await _client
        .from('signal_sources')
        .select('trade_idea_id')
        .eq('signal_id', signalId);
    final ids = (r as List).map((row) => '${(row as Row)['trade_idea_id']}').toSet();
    if (ids.isEmpty) return (distinctIdeas: 0, distinctSources: 0);

    // Distinct INDEPENDENT sources, not distinct ideas. Product rule 3: a
    // source that posts eleven variants of one view is one vote. The manual
    // seed currently produces a new idea per run, so counting ideas alone made
    // a single source look like broad agreement.
    final ideas = await _client
        .from('trade_ideas')
        .select('source_id')
        .inFilter('id', ids.toList());
    final sources = (ideas as List).map((row) => '${(row as Row)['source_id']}').toSet();
    return (distinctIdeas: ids.length, distinctSources: sources.length);
  }

  /// §5.1 sentiment layers measured by the `sentiment-layers` function
  /// (US Treasury real yields, CFTC managed money).
  ///
  /// Returns every row the table holds, including layers that exist but carry
  /// no measurement, so the caller can tell "not built yet" from "reads zero".
  /// An empty result yields [SentimentLayers.empty] rather than a partial set.
  Future<SentimentLayers> sentimentLayers() async {
    final r = await _client
        .from('sentiment_layers')
        .select(
          'layer,horizon,weight,score,alignment,measured_at,source,source_url,stale,detail',
        );
    if (r.isEmpty) return const SentimentLayers.empty();
    final rows = <SentimentLayerRow>[];
    for (final raw in r) {
      final parsed = SentimentLayerRow.tryParse(raw);
      if (parsed != null) rows.add(parsed);
    }
    return SentimentLayers(rows);
  }

  /// Closed signals for the History tab.
  Future<List<DisplayHistoryEntry>> history({int limit = 50}) async {
    final r = await _client
        .from('consensus_signals')
        .select('*')
        .inFilter('status', ['TP1_HIT', 'TP2_HIT', 'TP3_HIT', 'INVALIDATED', 'EXPIRED'])
        .order('created_at', ascending: false)
        .limit(limit);
    return (r as List).map((row) => _toHistoryEntry(row as Row)).toList();
  }

  // ----------------------------------------------------------------- events

  Future<List<DisplayEvent>> upcomingEvents({int limit = 20}) async {
    final r = await _client
        .from('economic_events')
        .select('*')
        .gte('starts_at', DateTime.now().toIso8601String())
        .order('starts_at', ascending: true)
        .limit(limit);
    return _toEvents((r as List).cast<Row>());
  }

  /// Maps rows to events, evaluating the outlook across the WHOLE window.
  ///
  /// Coincidence is a relationship between releases, so each row must be able
  /// to see its siblings; evaluating one row at a time would never detect that
  /// two high-impact releases land together.
  List<DisplayEvent> _toEvents(List<Row> rows) {
    final now = DateTime.now().toUtc();
    final inputs = rows.map((r) {
      final startsAt = DateTime.tryParse('${r['starts_at']}')?.toUtc() ?? now;
      return ReleaseInput(
        id: '${r['id']}',
        title: '${r['title'] ?? 'Event'}',
        currency: '${r['currency'] ?? 'USD'}',
        impact: _releaseImpact('${r['impact'] ?? 'LOW'}'),
        figures: ReleaseFigures(
          actual: _toDouble(r['actual']),
          forecast: _toDouble(r['forecast']),
          previous: _toDouble(r['previous']),
        ),
        startsAtUtc: startsAt,
        now: now,
      );
    }).toList();
    final outs = const EventOutlookEngine().evaluateAll(inputs);

    return [
      for (var i = 0; i < rows.length; i++) _toEvent(rows[i], outlook: outs[i], now: now),
    ];
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
        evidenceCount: (t['evidence_urls'] is List)
            ? (t['evidence_urls'] as List).length
            : 0,
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
      whenText: at == null ? '-' : '${_hhmm(at)} · ${_relativeDay(at)}',
      detailText: (entryLow != null && entryHigh != null && stop != null)
          ? 'IN ${formatLevel(entryLow)}-${formatLevel(entryHigh)}'
                ' · SL ${formatLevel(stop)}'
          : 'Levels unavailable',
      status: status,
      pipsPoints: outcome,
    );
  }

  DisplayEvent _toEvent(Row r, {EventOutlook? outlook, DateTime? now}) {
    final clock = now ?? DateTime.now().toUtc();
    final startsAt = DateTime.tryParse('${r['starts_at']}')?.toUtc() ?? clock;
    return DisplayEvent(
      id: '${r['id']}',
      title: '${r['title'] ?? 'Event'}',
      currency: '${r['currency'] ?? 'USD'}',
      impact: _impact('${r['impact'] ?? 'LOW'}'),
      startsIn: startsAt.difference(clock),
      forecast: _numText(r['forecast']),
      previous: _numText(r['previous']),
      actual: _numText(r['actual']),
      surprise: _surprise(r['surprise'] as String?),
      outlook: outlook,
    );
  }

  /// DB impact text → the engine's tier.
  static ReleaseImpact _releaseImpact(String raw) => switch (raw.toUpperCase()) {
    'HIGH' => ReleaseImpact.high,
    'MEDIUM' || 'MED' => ReleaseImpact.medium,
    _ => ReleaseImpact.low,
  };

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
    return d == d.roundToDouble() ? d.toInt().toString() : d.toStringAsFixed(2);
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _relativeDay(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(t.year, t.month, t.day)).inDays;
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

  // ------------------------------------------------------------- analysis

  /// Closed OHLC bars per timeframe for the technical engine.
  ///
  /// Returns validated, closed bars in ascending time order. In-progress bars
  /// are excluded here (and again by the engine) so an unfinished candle can
  /// never influence a published level.
  ///
  /// **One request per timeframe, newest first.** This is not a style choice.
  /// Supabase caps a PostgREST response at 1000 rows per request, and that cap
  /// is invisible to `current_setting('pgrst.db_max_rows')`. The previous
  /// implementation made ONE request covering every timeframe ordered by
  /// `open_time` ASCENDING, so the cap kept the OLDEST 1000 rows of the whole
  /// table and discarded every recent bar. With ~2,800 rows present, all four
  /// timeframes were truncated at the same instant and the app analysed bars
  /// roughly four days stale while presenting them as live, with no error
  /// anywhere to explain it.
  ///
  /// Ordering DESCENDING with a per-timeframe limit means each series receives
  /// the newest N bars it asked for, so a cap can only ever cost extra history
  /// rather than the most recent price. It also stops the failure growing worse
  /// as the table fills, which is what the ascending version did.
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async {
    validateBarLimit(maxPerTimeframe);

    final out = <Tf, TimeframeBars>{};

    for (final tf in Tf.values) {
      final interval = switch (tf) {
        Tf.m5 => const Duration(minutes: 5),
        Tf.m15 => const Duration(minutes: 15),
        Tf.m30 => const Duration(minutes: 30),
        Tf.h1 => const Duration(hours: 1),
      };

      final r = await _client
          .from('market_bars')
          .select('open_time,open,high,low,close,volume,quality')
          .eq('symbol', 'XAUUSD')
          .eq('timeframe', dbTf(tf))
          .eq('is_closed', true)
          .order('open_time', ascending: false)
          .limit(maxPerTimeframe);

      if (r.isEmpty) continue;

      final bars = <Candle>[];
      var allDegraded = true;

      for (final row in r) {
        final o = _toDouble(row['open']);
        final h = _toDouble(row['high']);
        final l = _toDouble(row['low']);
        final c = _toDouble(row['close']);
        if (o == null || h == null || l == null || c == null) continue;
        final at = DateTime.tryParse('${row['open_time']}')?.toUtc();
        if (at == null) continue;

        final isDegraded = '${row['quality']}' == 'degraded';
        bars.add(
          Candle(
            openTime: at,
            open: o,
            high: h,
            low: l,
            close: c,
            volume: _toDouble(row['volume']),
            source: 'supabase',
            quality: isDegraded ? CandleQuality.degraded : CandleQuality.primary,
          ),
        );
        // Sticky: a timeframe counts as degraded only if EVERY bar is degraded,
        // so one primary bar is enough to make the series level-eligible.
        allDegraded = allDegraded && isDegraded;
      }

      if (bars.isEmpty) continue;

      // validateCandles sorts ascending, so the descending fetch order never
      // leaks into the engine, which expects oldest-first everywhere.
      final accepted = validateCandles(bars, interval).accepted;
      if (accepted.isEmpty) continue;

      out[tf] = TimeframeBars(
        timeframe: tf,
        bars: accepted,
        allDegraded: allDegraded,
      );
    }

    return out;
  }

  /// PostgREST's per-response row cap.
  ///
  /// Set here rather than read from `current_setting('pgrst.db_max_rows')`
  /// because on this project that setting is NULL while the cap is
  /// demonstrably in force: a live request returned exactly 1000 rows with no
  /// error and no warning. Anything that assumes it can discover the cap by
  /// asking the database will silently mis-truncate.
  static const int postgrestRowCap = 1000;

  /// Rejects a bar limit the server would silently truncate.
  ///
  /// A limit above the cap produces a short response with no error, which is
  /// how the original bug stayed invisible. Failing loudly at the call site is
  /// the only defence.
  @visibleForTesting
  static void validateBarLimit(int maxPerTimeframe) {
    if (maxPerTimeframe > postgrestRowCap) {
      throw ArgumentError.value(
        maxPerTimeframe,
        'maxPerTimeframe',
        'must be <= $postgrestRowCap; PostgREST caps responses at $postgrestRowCap '
            'rows and a larger request would be silently truncated',
      );
    }
  }

  /// Database spelling of a timeframe.
  ///
  /// Kept explicit rather than derived from the enum name: `Tf.m15` is `m15`
  /// here but `15m` in `market_bars.timeframe`, and getting it wrong yields an
  /// empty series rather than an error.
  ///
  /// There is deliberately no reverse mapping any more. It existed only to
  /// recognise whichever timeframes an unfiltered query happened to return, and
  /// that query is exactly the thing being removed.
  static String dbTf(Tf tf) => switch (tf) {
        Tf.m5 => '5m',
        Tf.m15 => '15m',
        Tf.m30 => '30m',
        Tf.h1 => '1h',
      };

  /// Live spot price, via the server-side cache.
  ///
  /// WHY THIS GOES THROUGH AN EDGE FUNCTION
  ///
  /// `tick` writes a snapshot once a minute and pg_cron cannot run sub-minute, so
  /// polling the database faster than that cannot beat a producer that only moves
  /// once a minute. A price that refreshes on a timer the data cannot beat is not
  /// a live price.
  ///
  /// Fetching upstream directly from the phone does not work either, and this was
  /// measured rather than assumed: the provider rate-limits by client IP. Sixteen
  /// requests at 4s spacing from a workstation all returned 200, while the same
  /// cadence from the phone returned 429 every time. A design that only works on
  /// the developer's connection fails for most real users.
  ///
  /// So `price-live` holds a shared cache: upstream is contacted at most once per
  /// window from our own infrastructure, and any number of clients read that one
  /// result. See migration 0018 and D-20261006-015.
  ///
  /// HONEST LIMITS
  ///
  /// The provider republishes on roughly a 30-second cycle, so that is the real
  /// ceiling on how live this number can be. The app reports the age the
  /// function returns rather than implying tick-level freshness.
  ///
  /// If this call fails, the stored snapshot is still better than an empty
  /// screen, but it is NOT live and is reported as such (product rule 2).
  Future<({double? price, DateTime? at, bool live})> directSpotPrice({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    try {
      final res = await _http
          .get(Uri.parse('$_supabaseFunctionsUrl/price-live'),
              headers: {'apikey': _anonKey})
          .timeout(timeout);
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final price = _toDouble(body['price']);
      if (price == null || price <= 0) throw StateError('no usable price');
      final live = body['live'] == true;
      final at = DateTime.tryParse('${body['measuredAt']}')?.toUtc() ??
          DateTime.now().toUtc();
      return (price: price, at: at, live: live);
    } catch (err) {
      // Log the reason rather than swallowing it. A bare `catch (_)` here is
      // what made a real on-device failure look like a design decision: the app
      // fell back to the stored snapshot and nothing anywhere said why.
      // debugPrint matches how the rest of this app reports failures, and the
      // string carries nothing sensitive.
      debugPrint('directSpotPrice: live read failed, using stored snapshot: $err');
      final stored = await latestPrice();
      return (price: stored?.price, at: stored?.at, live: false);
    }
  }

  /// Whether the venue spread is currently acceptable — WITHOUT the rate.
  ///
  /// Ratified option (a) holds: a spread is only ever the execution venue's
  /// Ask − Bid. That is still true, and it is still how the number in
  /// `market_snapshots` was produced. What changed is that the number may not be
  /// delivered to this app.
  ///
  /// The OANDA fxTrade PRACTICE licence grants INTERNAL USE ONLY and forbids
  /// transmitting FXTrade rates to any third party. XV is a public app, so the
  /// ladder itself is revoked from the client roles at the database level
  /// (migration 0016) and cannot be queried at all. See D-20261006-013.
  ///
  /// So the app reads `spread_gate`, which answers the only question the engine
  /// actually needs — is the spread inside its own acceptability limit — and
  /// carries no price. The engine still applies its veto honestly; nobody learns
  /// the rate.
  ///
  /// This is NOT a cross-source difference and NOT a synthesised spread. When the
  /// gate cannot vouch, the honest answer is UNAVAILABLE and the engine says its
  /// spread veto was UNEVALUATED rather than inventing a number.
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final r = await _client.from('spread_gate').select('status,age_seconds').limit(1);

    if (r.isEmpty) {
      return (spread: const VenueSpread.unavailable(), ageSeconds: double.infinity);
    }

    final row = r.first;
    final status = '${row['status'] ?? 'UNAVAILABLE'}';
    final age = num.tryParse('${row['age_seconds']}')?.toDouble() ?? double.infinity;

    if (status != 'AVAILABLE_FOR_INTERNAL_USE' || age > maxAge.inSeconds) {
      return (spread: const VenueSpread.unavailable(), ageSeconds: age);
    }

    // Acceptable, but undisclosed. No bid, no ask, no width — the engine's
    // veto sees "measured and inside limits" while the number stays server-side.
    return (
      spread: const VenueSpread.undisclosed(source: 'venue-internal'),
      ageSeconds: age,
    );
  }

  /// Calendar events for the event gate, mapped to the analysis tier model.
  Future<List<EconomicEvent>> analysisEvents({int hoursAhead = 24}) async {
    final now = DateTime.now().toUtc();
    final r = await _client
        .from('economic_events')
        .select('title,currency,impact,starts_at,actual,forecast,previous')
        .gte('starts_at', now.subtract(const Duration(hours: 2)).toIso8601String())
        .lte('starts_at', now.add(Duration(hours: hoursAhead)).toIso8601String());

    if (r.isEmpty) return const [];
    final out = <EconomicEvent>[];
    for (final row in r) {
      final at = DateTime.tryParse('${row['starts_at']}')?.toUtc();
      // An event with no parseable time cannot be scheduled, and guessing a
      // time would put a blackout window in the wrong place. Skip it.
      if (at == null) continue;
      out.add(
        EconomicEvent(
          name: '${row['title'] ?? 'Event'}',
          currency: '${row['currency'] ?? 'USD'}',
          tier: tierFromImpact('${row['impact'] ?? 'LOW'}'),
          releaseTime: at,
          actual: _toDouble(row['actual']),
          forecast: _toDouble(row['forecast']),
          previous: _toDouble(row['previous']),
          source: 'supabase',
        ),
      );
    }
    return out;
  }
}
