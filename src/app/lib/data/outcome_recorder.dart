import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:xau_core/xau_core.dart';

/// Writes each engine decision to the outcome recorder so it can be scored.
///
/// Why this exists: the product reports a verdict and, since the levels were
/// withheld, publishes nothing else. That is a scoring engine with no
/// measurement attached, which is indistinguishable from scoring noise. This
/// service is what turns "we said LONG" into a question that can be answered
/// with data instead of argument.
///
/// Design constraints, all of them deliberate:
///
///  * **It reports the engine's parameters, not a locally computed hash.** The
///    server fingerprints the rule set itself and compares the numbers it is
///    given. Reproducing the server's canonical-JSON encoding in Dart would be a
///    formatting trap - Dart renders `9.0` as `"9.0"` where `JSON.stringify`
///    renders it `"9"` - so a client-computed hash would disagree on float
///    formatting alone and void every honest row.
///
///  * **It reports the same spread status the engine actually used**, including
///    the staleness override. Reporting the raw measurement instead would let
///    settlement subtract a spread cost for a spread the engine never saw, which
///    would quietly make every result look worse than the run that produced it.
///
///  * **It never throws.** A failed write must not break the analysis the user
///    is looking at. Recording is instrumentation; instrumentation does not get
///    to take the product down.
///
/// Protocol: docs/outcome-recorder-protocol.md
class OutcomeRecorder {
  OutcomeRecorder([SupabaseClient? client]) : _client = client;

  final SupabaseClient? _client;

  /// Resolved lazily, never in the constructor.
  ///
  /// `Supabase.instance.client` throws when the app has not been initialised,
  /// which is the case in unit tests and in any tool that merely constructs an
  /// [AnalysisService]. Touching it at construction time made merely building a
  /// service fail; touching it here means a failed lookup is caught by [record]
  /// and costs nothing.
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  /// Decision key already submitted this session. The server dedupes on
  /// `decision_key` too; this just avoids a pointless round trip every 60s.
  String? _lastSubmittedKey;

  /// The key of the most recent submission, or null if none.
  String? get lastSubmittedKey => _lastSubmittedKey;

  /// Engine version stamped on every row. Bump when scoring changes; the server
  /// derives the cohort from its own fingerprint regardless.
  static const String clientVersion = 'xv-app/1.0.8';

  /// The M15 bar close a decision is attributed to.
  ///
  /// [Candle.openTime] is the bar's OPEN, so the close is one period later. The
  /// decision was not knowable before that instant, and attributing it to the
  /// open time would let a row claim knowledge it did not have.
  static DateTime? decisionTimeFor(TimeframeBars m15) {
    final bars = m15.bars.where((c) => c.isClosed).toList();
    if (bars.isEmpty) return null;
    final last = bars.last;
    return last.openTime.add(const Duration(minutes: 15));
  }

  /// Submits one decision. Safe to call on every scan.
  ///
  /// Returns the decision key actually sent, or null if nothing was sent. The
  /// key is also readable afterwards via [lastSubmittedKey].
  Future<String?> record({
    required ScanResult scan,
    required TimeframeBars m15,
    required Thresholds thresholds,
    required StopConfig stopConfig,
    required Side? candidateDirection,
    required double? currentPrice,
    required SpreadStatus effectiveSpreadStatus,
    required String effectiveSpreadNote,
  }) async {
    try {
      final decidedAt = decisionTimeFor(m15);
      if (decidedAt == null) return null;
      // A decision dated in the future is rejected server-side, but there is no
      // point spending a request on it.
      if (decidedAt.isAfter(DateTime.now().toUtc())) return null;

      final payload = buildPayload(
        scan: scan,
        decidedAt: decidedAt,
        thresholds: thresholds,
        stopConfig: stopConfig,
        candidateDirection: candidateDirection,
        currentPrice: currentPrice,
        effectiveSpreadStatus: effectiveSpreadStatus,
        effectiveSpreadNote: effectiveSpreadNote,
      );
      if (payload == null) return null;

      // One decision per closed bar per side. Including the side means a flip
      // between bars produces a distinct row rather than colliding with the
      // earlier one, which `ignoreDuplicates` would otherwise silently drop.
      final key = payload['decisionKey']! as String;
      if (key == _lastSubmittedKey) return null;
      _lastSubmittedKey = key;

      await _db.functions.invoke('outcome-recorder', body: payload);

      return key;
    } catch (e) {
      // Never surface this to the user. A missing outcome row is a gap in the
      // record, not a reason to interrupt someone's analysis.
      debugPrint('outcome-recorder: $e');
      return null;
    }
  }

  /// Builds the recorder payload, or null when the decision is not submittable.
  ///
  /// Pure and separate from [record] so the mapping can be tested without a
  /// network or a Supabase client. Everything the server needs to score the
  /// decision and audit the run that produced it lives here.
  @visibleForTesting
  static Map<String, Object?>? buildPayload({
    required ScanResult scan,
    required DateTime decidedAt,
    required Thresholds thresholds,
    required StopConfig stopConfig,
    required Side? candidateDirection,
    required double? currentPrice,
    required SpreadStatus effectiveSpreadStatus,
    required String effectiveSpreadNote,
  }) {
    final side = scan.verdict == Verdict.noTrade
        ? 'NO_TRADE'
        : scan.verdict == Verdict.long ? 'LONG' : 'SHORT';

    final payload = <String, Object?>{
      'action': 'record',
      'decisionKey': '$clientVersion:${decidedAt.toIso8601String()}:$side',
      'decidedAt': decidedAt.toIso8601String(),
      'verdict': _verdictDb(scan.verdict),
      'side': side,
      'grade': _gradeDb(scan.grade),
      'technicalScore': scan.technicalScore,
      'finalScore': scan.finalScore,
      'reasonCodes': scan.reasonCodes.map((c) => c.name).toList(),
      'vetoes': scan.vetoes.map((c) => c.name).toList(),
      'dataQuality': [
        ...scan.dataQuality,
        effectiveSpreadNote,
        'client=$clientVersion',
      ],
      'macroAlignment': scan.macroAlignment,
      'sentimentAlignment': scan.sentimentAlignment,
      'conflictPenalty': scan.conflictPenalty,
      'clientParameters': _parameters(thresholds, stopConfig),
      'spreadStatus': effectiveSpreadStatus == SpreadStatus.available ? 'available' : 'unavailable',
      'spreadValue': scan.spread.value,
      'atr5m': scan.atr5m,
    };

    if (scan.verdict != Verdict.noTrade) {
      final plan = scan.stopPlan;
      // A trade with no usable plan cannot be scored, so it is not pretended
      // into existence. The server rejects it too; this avoids the round trip.
      if (plan == null || plan.riskDistance <= 0) return null;
      payload['entry'] = plan.entry;
      payload['stopLoss'] = plan.stopLoss;
      payload['tp1'] = plan.tp1;
      payload['tp2'] = plan.tp2;
      payload['tp3'] = plan.tp3;
      payload['riskDistance'] = plan.riskDistance;
      payload['riskDistanceAtr'] = plan.riskDistanceAtr;
    } else {
      // The forced-trade twin of this abstention. Without it the record cannot
      // answer whether the engine's caution was worth anything.
      final cf = _counterfactual(
        candidateDirection: candidateDirection,
        currentPrice: currentPrice,
        atr5m: scan.atr5m,
      );
      if (cf != null) payload['counterfactual'] = cf;
    }

    return payload;
  }

  /// The parameters the engine actually ran with, for server-side verification.
  static Map<String, double> _parameters(Thresholds t, StopConfig s) => {
        'minTechnical': t.minTechnical.toDouble(),
        'minFinal': t.minFinal,
        'rsiPreferredLow': t.rsiPreferredLow.toDouble(),
        'rsiPreferredHigh': t.rsiPreferredHigh.toDouble(),
        'rsiExhaustedLong': t.rsiExhaustedLong.toDouble(),
        'rsiExhaustedShort': t.rsiExhaustedShort.toDouble(),
        'adxTrending': t.adxTrending.toDouble(),
        'atrPercentileLow': t.atrPercentileLow.toDouble(),
        'atrPercentileHigh': t.atrPercentileHigh.toDouble(),
        'atrPercentileExtreme': t.atrPercentileExtreme.toDouble(),
        'stopMinAtr': t.stopMinAtr,
        'stopMaxAtr': t.stopMaxAtr,
        'tp2FloorR': t.tp2FloorR,
        'maxDailySignals': t.maxDailySignals.toDouble(),
        'atrBufferMultiple': s.atrBufferMultiple,
        'minStopAtr': s.minStopAtr,
        'maxStopAtr': s.maxStopAtr,
        'tp1R': s.tp1R,
        'tp2R': s.tp2R,
        'tp3R': s.tp3R,
      };

  /// Pre-registered forced-trade construction: 1xATR5m risk, exactly 1R target.
  ///
  /// Direction is the engine's own candidate lean. There is no fallback that
  /// invents one - a benchmark built on a guessed side is worse than none.
  static Map<String, Object?>? _counterfactual({
    required Side? candidateDirection,
    required double? currentPrice,
    required double? atr5m,
  }) {
    if (candidateDirection == null) return null;
    if (currentPrice == null || currentPrice <= 0) return null;
    if (atr5m == null || atr5m <= 0) return null;
    return {
      'side': candidateDirection == Side.long ? 'FORCED_LONG' : 'FORCED_SHORT',
      'entry': currentPrice,
      'riskDistance': atr5m,
      'atr5m': atr5m,
    };
  }

  static String _verdictDb(Verdict v) => switch (v) {
        Verdict.long => 'LONG',
        Verdict.short => 'SHORT',
        Verdict.noTrade => 'NO_TRADE',
      };

  static String _gradeDb(Grade g) => switch (g) {
        Grade.aPlus => 'A_PLUS',
        Grade.a => 'A',
        Grade.b => 'B',
        Grade.insufficient => 'INSUFFICIENT',
      };
}