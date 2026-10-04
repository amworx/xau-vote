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
import 'package:xau_core/xau_core.dart' hide Direction;

import '../models/display_models.dart';

/// Raw row shapes as returned by PostgREST (snake_case).
typedef Row = Map<String, dynamic>;

/// XV live data, read-only from the app's perspective.
class LiveRepository {
  LiveRepository([SupabaseClient? client]) : _client = client ?? Supabase.instance.client;

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
          'id,source_id,direction,entry_low,entry_high,stop_loss,'
          'target_1,target_2,target_3,methodology_id,upstream_dataset_id,'
          'published_at,fingerprint,author_ref',
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

    return (ideas as List).map((r) {
      final row = r as Row;
      final srcId = '${row['source_id']}';
      final hasPublisher = srcId.isNotEmpty && srcId != 'null';
      final method = '${row['methodology_id']}';
      final dataset = '${row['upstream_dataset_id']}';
      return DisplaySource(
        id: hasPublisher ? srcId : 'no-publisher',
        name: hasPublisher
            ? (publisherNames[srcId] ?? srcId)
            // No publisher: name the row after its own provenance so it is not
            // blank, and say plainly that it is unattributed.
            : (method.isEmpty || method == 'null' ? 'Unattributed idea' : method),
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
    }).toList();
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

  /// The targets the idea actually published, in order, skipping absent levels.
  static String _targets(Row row) {
    final parts = [
      'target_1',
      'target_2',
      'target_3',
    ].map((k) => _toDouble(row[k])).whereType<double>().map(formatLevel).toList();
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
  /// Reads `market_bars` and returns validated, closed bars in ascending time
  /// order. In-progress bars are excluded here (and again by the engine) so an
  /// unfinished candle can never influence a published level.
  Future<Map<Tf, TimeframeBars>> analysisBars({int maxPerTimeframe = 600}) async {
    final r = await _client
        .from('market_bars')
        .select('timeframe,open_time,open,high,low,close,volume,quality')
        .eq('symbol', 'XAUUSD')
        .eq('is_closed', true)
        .order('open_time', ascending: true);

    if (r.isEmpty) return const {};

    final grouped = <Tf, List<Candle>>{};
    final degraded = <Tf, bool>{};

    for (final row in r) {
      final tf = _toTf(row['timeframe']);
      if (tf == null) continue;
      final o = _toDouble(row['open']);
      final h = _toDouble(row['high']);
      final l = _toDouble(row['low']);
      final c = _toDouble(row['close']);
      if (o == null || h == null || l == null || c == null) continue;
      final at = DateTime.tryParse('${row['open_time']}')?.toUtc();
      if (at == null) continue;

      final isDegraded = '${row['quality']}' == 'degraded';
      (grouped[tf] ??= []).add(
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
      degraded[tf] = (degraded[tf] ?? true) && isDegraded;
    }

    final out = <Tf, TimeframeBars>{};
    for (final tf in Tf.values) {
      final bars = grouped[tf] ?? const <Candle>[];
      if (bars.isEmpty) continue;
      final interval = switch (tf) {
        Tf.m5 => const Duration(minutes: 5),
        Tf.m15 => const Duration(minutes: 15),
        Tf.m30 => const Duration(minutes: 30),
        Tf.h1 => const Duration(hours: 1),
      };
      final v = validateCandles(bars, interval);
      // Keep only the most recent window: the engine needs a long series for
      // EMA200 but not unbounded history.
      final accepted = v.accepted;
      final windowed = accepted.length > maxPerTimeframe
          ? accepted.sublist(accepted.length - maxPerTimeframe)
          : accepted;
      out[tf] = TimeframeBars(
        timeframe: tf,
        bars: windowed,
        allDegraded: degraded[tf] ?? false,
      );
    }
    return out;
  }

  /// Newest genuine venue spread, or an explicit UNAVAILABLE state.
  ///
  /// Ratified option (a): a spread is only ever the execution venue's
  /// Ask − Bid. A missing or stale row yields [VenueSpread.unavailable], never
  /// a difference between two price sources.
  Future<({VenueSpread spread, double ageSeconds})> venueSpread({
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final r = await _client
        .from('market_snapshots')
        .select('bid,ask,source,timestamp')
        .eq('symbol', 'XAUUSD')
        .not('bid', 'is', null)
        .not('ask', 'is', null)
        .order('timestamp', ascending: false)
        .limit(1);

    if (r.isEmpty) {
      return (spread: const VenueSpread.unavailable(), ageSeconds: double.infinity);
    }
    final row = r.first;
    final bid = _toDouble(row['bid']);
    final ask = _toDouble(row['ask']);
    final at = DateTime.tryParse('${row['timestamp']}')?.toUtc();
    final age = at == null
        ? double.infinity
        : DateTime.now().toUtc().difference(at).inMilliseconds / 1000.0;

    // A stale measurement is not a current spread. Reporting it as available
    // would be as misleading as reporting nothing.
    if (bid == null || ask == null || age > maxAge.inSeconds) {
      return (spread: const VenueSpread.unavailable(), ageSeconds: age);
    }
    return (
      spread: VenueSpread.available(
        bid: bid,
        ask: ask,
        source: '${row['source'] ?? 'unknown'}',
      ),
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

  static Tf? _toTf(Object? v) {
    switch ('$v') {
      case '5m':
        return Tf.m5;
      case '15m':
        return Tf.m15;
      case '30m':
        return Tf.m30;
      case '1h':
        return Tf.h1;
      default:
        return null;
    }
  }
}
