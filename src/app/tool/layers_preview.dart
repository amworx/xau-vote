import 'package:flutter/material.dart';
import 'package:xau_core/xau_core.dart';
import 'package:xauvote/models/sentiment_layers.dart';
import 'package:xauvote/widgets/analysis_verdict_card.dart';

/// Renders the real AnalysisVerdictCard with the live 2026-10-05 layer rows, so
/// the new block can be inspected in the app's own theme rather than only in the
/// browser prototype.
void main() => runApp(const _Preview());

SentimentLayerRow row(String layer, double weight,
    {int? alignment,
    num? score,
    bool stale = false,
    String measuredAt = '2026-10-05T00:00:00.000Z',
    Map<String, dynamic> detail = const {}}) =>
    SentimentLayerRow.tryParse({
      'layer': layer,
      'horizon': 'hours-days',
      'weight': weight,
      'score': score,
      'alignment': alignment,
      'measured_at': measuredAt,
      'source': 'preview',
      'source_url': null,
      'stale': stale,
      'detail': detail,
    })!;

final live = SentimentLayers([
  row('policy', 35,
      alignment: -1,
      score: -1.03,
      measuredAt: '2026-09-16T00:00:00.000Z',
      detail: const {
        'action': 'raise',
        'target_low_pct': 3.75,
        'target_high_pct': 4,
        'raw_score': -2,
        'effective_score': -1.03,
        'decay_days': 20,
        'dissents': <String>[],
        'sep_projection': null,
        'as_of': '2026-09-16',
      }),
  row('positioning', 25,
      alignment: -1,
      score: -1,
      measuredAt: '2026-09-29T00:00:00.000Z',
      detail: const {
        'managed_net_contracts': 120318,
        'percentile_156w': 37.8,
        'sample_weeks': 156,
        'managed_net_percent_of_oi': 0.296,
        'as_of': '2026-09-29',
      }),
  row('market_implied', 20,
      alignment: -1,
      detail: const {
        'real10y': 2.92,
        'change5d_bp': 9,
        'as_of': '2026-10-05',
        'legs_missing': ['usd', 'volatility'],
      }),
  // No gold_fundamentals: removed because its source cannot be licensed.
  // D-20261006-011.
]);

ScanResult scan({
  required Verdict verdict,
  int? macroAgrees,
  int? sentimentAgrees,
  int? macroAlignment,
  int? sentimentAlignment,
}) =>
    ScanResult(
      verdict: verdict,
      grade: verdict == Verdict.noTrade ? Grade.insufficient : Grade.b,
      reasonCodes: const [ReasonCode.h1TrendAligned, ReasonCode.m5TriggerPresent],
      vetoes: verdict == Verdict.noTrade ? const [ReasonCode.v6DirectionConflict] : const [],
      technicalScore: 9,
      finalScore: verdict == Verdict.noTrade ? 6.0 : 11.0,
      macroAlignment: macroAlignment,
      macroAgrees: macroAgrees,
      sentimentAlignment: sentimentAlignment,
      sentimentAgrees: sentimentAgrees,
      conflictPenalty: verdict == Verdict.noTrade ? 2 : 0,
      spread: const VenueSpread.available(bid: 4140.77, ask: 4141.21, source: 'oanda-practice'),
      dataQuality: const ['sentiment layers: policy, positioning, market_implied (macro coverage 73%)'],
      lockSummary: 'OPEN',
      stopPlan: null,
      atr5m: 4.12,
    );

class _Preview extends StatelessWidget {
  const _Preview();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: const Color(0xFFE9ECEF),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              const Text('LONG candidate — macro conflicts',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              AnalysisVerdictCard(
                scan: scan(
                  verdict: Verdict.noTrade,
                  macroAgrees: -1,
                  sentimentAgrees: -1,
                  macroAlignment: -1,
                  sentimentAlignment: -1,
                ),
                layers: live,
              ),
              const SizedBox(height: 22),
              const Text('SHORT candidate — same layers, macro supports',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              AnalysisVerdictCard(
                scan: scan(
                  verdict: Verdict.short,
                  macroAgrees: 1,
                  sentimentAgrees: 1,
                  macroAlignment: -1,
                  sentimentAlignment: -1,
                ),
                layers: live,
              ),
              const SizedBox(height: 22),
              const Text('Thin layers — below the gate',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 8),
              AnalysisVerdictCard(
                scan: scan(verdict: Verdict.noTrade),
                layers: SentimentLayers([row('market_implied', 20, alignment: -1)]),
              ),
            ],
          ),
        ),
      );
}