import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:xau_core/xau_core.dart';

import 'live_repository.dart';
import 'outcome_recorder.dart';
import '../models/sentiment_layers.dart';

/// Runs the multi-timeframe analysis on demand and caches the result.
///
/// The scan lives in the client on purpose. `xau_core` is the engine source of
/// truth and the backend only stores bars, prices and the venue spread; running
/// the scan here means there is exactly one implementation of the methodology
/// instead of a Dart copy and a TypeScript copy that can silently diverge.
///
/// The scan is strictly read-only. It cannot create or flip a published signal:
/// consensus and lifecycle remain owned by the backend.
/// Session-gate helpers, exposed for testing.
///
/// The DST maths is the part most likely to rot, so it is verified directly
/// rather than only through a scan.
///
/// Both now delegate to `xau_core`'s session module: the engine already owns
/// the calendar, and a second copy here is exactly the kind of divergence that
/// lets the scanner and the header disagree about whether the market is open.
@visibleForTesting
bool sessionIsOpenAt(DateTime utc) => AnalysisService.sessionGate(utc);

class AnalysisService extends ChangeNotifier {
  AnalysisService({
    LiveRepository? repository,
    MarketScanner? scanner,
    OutcomeRecorder? recorder,
  })  : _repo = repository ?? LiveRepository(),
        _scanner = scanner ?? const MarketScanner(),
        _recorder = recorder ?? OutcomeRecorder();

  final LiveRepository _repo;
  final MarketScanner _scanner;

  /// Writes each decision to the outcome recorder. Injectable so tests can
  /// substitute a recorder and assert on what would have been submitted without
  /// touching the network.
  final OutcomeRecorder _recorder;

  /// The decision key last submitted, or null if none has been.
  ///
  /// Exposed for tests and diagnostics only. The recorder deliberately does not
  /// surface this in the UI: publishing "we logged your decision" invites the
  /// record being read as a performance claim, which it is not.
  @visibleForTesting
  String? get lastRecordedKey => _recorder.lastSubmittedKey;

  ScanResult? _cached;
  DateTime? _cachedAt;
  SentimentLayers? _layers;
  String? _error;
  Timer? _timer;

  /// Cached result, or null before the first successful scan.
  ScanResult? get result => _cached;

  /// The §5.1 layers behind the most recent scan, or null before the first one.
  ///
  /// Exposed separately from [result] because the layers carry the evidence -
  /// the percentile, the target range, the as-of dates - that lets the UI show
  /// why a score is what it is. [ScanResult] deliberately carries only the
  /// resolved numbers.
  SentimentLayers? get layers => _layers;

  /// Last error message; the UI shows it rather than pretending all is well.
  String? get error => _error;

  /// When the cached result was produced.
  DateTime? get updatedAt => _cachedAt;

  /// True when a venue spread was genuinely measured on the most recent scan.
  bool get hasGenuineSpread => _cached?.spread.isGenuine ?? false;

  /// Runs one scan and replaces the cache.
  Future<ScanResult?> refresh() async {
    try {
      final bars = await _repo.analysisBars();
      final spreadRow = await _repo.venueSpread();
      final events = await _repo.analysisEvents();

      // §5.1 layers, measured server-side by the `sentiment-layers` function.
      // Read here so the scan can actually weigh them: the Fed's policy decision,
      // CFTC managed money, and the Treasury real-yield impulse. A layer that
      // could not be measured arrives as null, which the engine treats as
      // "nothing to weigh" rather than as support.
      final layers = await _repo.sentimentLayers();

      final h1Bars = bars[Tf.h1];
      final m30Bars = bars[Tf.m30] ?? const TimeframeBars(timeframe: Tf.m30, bars: [], allDegraded: false);
      final m15Bars = bars[Tf.m15] ?? const TimeframeBars(timeframe: Tf.m15, bars: [], allDegraded: false);
      final m5Bars = bars[Tf.m5] ?? const TimeframeBars(timeframe: Tf.m5, bars: [], allDegraded: false);

      // The candidate direction comes from the 1H regime, which is context
      // rather than a vote. A flat or ambiguous 1H offers no direction and the
      // scan reports NO TRADE rather than guessing a side.
      final direction = _candidateDirection(h1Bars, m5Bars);

      final now = DateTime.now().toUtc();
      final spread = spreadRow.spread;

      // Freshness gate: a stale spread must not be treated as current.
      final spreadStatus =
          spread.isAcceptable && spreadRow.ageSeconds <= 300 ? SpreadStatus.available : SpreadStatus.unavailable;

      // Never print the number. The spread provider grants internal use only,
      // and this string is surfaced in the app, so a rate here is a
      // redistribution. The three states are kept distinct because they mean
      // different things and the user must be able to tell them apart:
      //   - unavailable        -> the measurement itself could not be trusted
      //   - undisclosed        -> measured and acceptable, rate withheld
      //   - (numeric case)     -> no longer reachable for this provider
      // The note must key off the SAME freshness gate as spreadStatus, not off the
      // spread object alone. Otherwise a stale measurement reports "unavailable"
      // in one field while the note still prints its number — the two would
      // disagree, and the stale number is the one the user reads.
      final spreadNote = spreadStatus == SpreadStatus.unavailable
          ? 'spread UNAVAILABLE: spread-based vetoes UNEVALUATED'
          : spread.isUndisclosed
              ? 'venue spread measured and within limits '
                  '(${spreadRow.ageSeconds.toStringAsFixed(0)}s old); rate withheld '
                  'under provider licence'
              : 'venue spread ${spread.value?.toStringAsFixed(2)} USD '
                  '(${spreadRow.ageSeconds.toStringAsFixed(0)}s old, ${spread.source})';

      // Say which layers actually carried weight. A scan that silently ignored
      // macro because nothing was measured must not look identical to one that
      // weighed a live reading.
      final measured = SentimentLayers.expectedWeights.keys
          .where((l) => layers[l]?.alignment != null)
          .toList();
      final unmeasured = SentimentLayers.expectedWeights.keys
          .where((l) => layers[l] == null || layers[l]!.alignment == null)
          .toList();
      final layerNote = measured.isEmpty
          ? 'sentiment layers: none measured (${unmeasured.join(', ')})'
          : 'sentiment layers: ${measured.join(', ')} '
              '(macro coverage ${(layers.macroCoverage * 100).toStringAsFixed(0)}%'
              '${unmeasured.isEmpty ? '' : ', missing ${unmeasured.join(', ')}'})';

      // Extracted because the outcome recorder needs the same price the scan
      // used. Recomputing it at send time would let the two disagree if a bar
      // landed mid-scan, which would score the decision against a price the
      // engine never saw.
      final currentPrice =
          m5Bars.bars.isNotEmpty ? m5Bars.bars.last.close : h1Bars?.bars.lastOrNull?.close;

      final scan = _scanner.scan(
        ScanRequest(
          direction: direction,
          h1: h1Bars ?? const TimeframeBars(timeframe: Tf.h1, bars: [], allDegraded: false),
          m30: m30Bars,
          m15: m15Bars,
          m5: m5Bars,
          spread: spread,
          spreadStatusOverride: spreadStatus,
          events: events,
          now: now,
          currentPrice: currentPrice,
          sessionOpen: isSessionOpen(now),
          // The two §5.1 inputs the §8.3 overlay consumes. Supplying them is
          // what makes the overlay reachable at all.
          macro: layers.macro,
          sentiment: layers.sentiment,
        ),
      );

      _error = null;
      _layers = layers;
      _cached = ScanResult(
        verdict: scan.verdict,
        grade: scan.grade,
        reasonCodes: scan.reasonCodes,
        vetoes: scan.vetoes,
        technicalScore: scan.technicalScore,
        finalScore: scan.finalScore,
        macroAlignment: scan.macroAlignment,
        sentimentAlignment: scan.sentimentAlignment,
        conflictPenalty: scan.conflictPenalty,
        spread: spread,
        dataQuality: [spreadNote, layerNote, ...scan.dataQuality],
        lockSummary: scan.lockSummary,
        stopPlan: scan.stopPlan,
        atr5m: scan.atr5m,
        macroAgrees: scan.macroAgrees,
        sentimentAgrees: scan.sentimentAgrees,
      );
      _cachedAt = DateTime.now();
      // Notify after the state is fully written so a listener never observes a
      // half-updated snapshot.
      notifyListeners();

      // Measurement, not a user-facing feature. Fire-and-forget, and
      // guaranteed not to throw, so a failed write can never interfere with the
      // analysis the user is looking at. Nothing here changes what the app shows.
      unawaited(
        _recorder.record(
          scan: scan,
          m15: m15Bars,
          thresholds: _scanner.engine.thresholds,
          stopConfig: _scanner.stopConfig,
          candidateDirection: direction,
          currentPrice: currentPrice,
          effectiveSpreadStatus: spreadStatus,
          effectiveSpreadNote: spreadNote,
          inputBars: bars,
        ),
      );

      return _cached;
    } catch (e) {
      _error = '$e';
      return null;
    }
  }

  /// Starts periodic rescanning. Callers must [dispose] to cancel the timer.
  ///
  /// Runs one scan immediately rather than waiting a full interval first. With a
  /// 60-second period the card used to sit empty for a minute after launch,
  /// showing "waiting for enough history" when the history was already there —
  /// a delay that read exactly like missing data.
  void startPolling({Duration interval = const Duration(seconds: 60)}) {
    _timer?.cancel();
    unawaited(refresh());
    _timer = Timer.periodic(interval, (_) => refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  /// Gold trades from Sunday 18:00 ET to Friday 17:00 ET. Outside that window
  /// the market is closed, and a "no trade" is the correct answer rather than a
  /// stale setup.
  /// Whether the spot-gold market is open at [utc].
  ///
  /// Gold (XAUUSD) runs from Sunday 18:00 New York to Friday 17:00 New York.
  ///
  /// The offset is computed from the US DST rules rather than hard-coded to -4h:
  /// a fixed offset is wrong for roughly eight months of the year, which would
  /// open the gate an hour early in winter and shut it an hour late, letting a
  /// scan evaluate a "live" setup against a stale last bar.
  ///
  /// DST runs from the second Sunday in March to the first Sunday in November.
  @visibleForTesting
  static bool sessionGate(DateTime utc) => isSessionOpen(utc);

  /// 1H regime decides the candidate direction; nothing narrower does.
  static Side? _candidateDirection(TimeframeBars? h1, TimeframeBars m5) {
    if (h1 == null || h1.bars.isEmpty) return null;
    final closes = h1.bars.map((b) => b.close).toList();
    if (closes.length < 50) return null;
    final last = closes.last;
    final ema50 = closes.sublist(closes.length - 50).reduce((a, b) => a + b) / 50;
    // A dead-flat 1H offers no candidate at all.
    if (last > ema50 * 1.0005) return Side.long;
    if (last < ema50 * 0.9995) return Side.short;
    return null;
  }
}

extension _LastOrNull<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}