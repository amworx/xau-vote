import 'package:flutter/material.dart';
// `Direction` is hidden from xau_core: the display layer has its own Direction
// in display_models.dart, and DirectionPill expects that one. The engine's
// `Side` is the analysis type used throughout this file.
import 'package:xau_core/xau_core.dart' hide Direction;

import '../models/display_models.dart' show Direction;
import '../models/sentiment_layers.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';
import 'sentiment_layers_section.dart';

/// Renders the multi-timeframe analysis verdict: grade, scores, structural
/// levels and the reason codes behind the call.
///
/// Design intent, from the methodology rather than from taste:
///
///  * **NO TRADE is a first-class, fully explained state.** This widget is not
///    an error path or an empty placeholder. Most scans end in no trade, and the
///    app has to say *why* rather than showing a blank screen.
///  * **Scores are never shown as probability.** No percentage, no "chance".
///    The score is setup quality on a 0-12 scale and the label says so.
///  * **Data-quality gaps are visible, not hidden.** An UNEVALUATED spread is
///    disclosed rather than smoothed over, because the user is entitled to know
///    which vetoes did not run.
///  * **Degraded/proxy history can never look level-eligible.** The card refuses
///    to render entry/SL/TP when the underlying history is degraded.
class AnalysisVerdictCard extends StatelessWidget {
  const AnalysisVerdictCard({
    super.key,
    required this.scan,
    this.onRefresh,
    this.layers,
    this.error,
  });

  final ScanResult? scan;

  /// Invoked when the user asks to rescan.
  final VoidCallback? onRefresh;

  /// The §5.1 layers behind this scan. Null when the scan could not read them,
  /// in which case the block is omitted rather than shown empty — an absent
  /// layer and a measured one must not look alike.
  final SentimentLayers? layers;

  /// Why the scan produced no result, when it failed rather than never having
  /// run. Surfaced instead of being swallowed behind "waiting for history".
  final String? error;

  @override
  Widget build(BuildContext context) {
    final s = scan;
    if (s == null) {
      // A failed scan and a scan that has not run yet are different states and
      // must not read the same. Showing "waiting for enough history" while the
      // scan was actually throwing is how a broken pipeline hides behind a
      // reassuring message.
      final failed = error != null;
      return HarborCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HarborEyebrow('MULTI-TIMEFRAME ANALYSIS'),
            const SizedBox(height: 10),
            Text(
              failed ? 'Analysis failed' : 'No analysis yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: failed ? harborShort : harborInk,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              failed
                  ? 'The scan could not complete. Nothing is being inferred from the absence of a result.'
                  : 'The scan runs on closed bars only. Waiting for enough history to evaluate the 1H regime.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: harborDim),
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: harborShortSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF2C2C2)),
                ),
                child: Text(
                  error!,
                  style: const TextStyle(
                    fontFamily: 'SpaceMono',
                    fontSize: 10,
                    height: 1.4,
                    color: Color(0xFFB23A3A),
                  ),
                ),
              ),
            ],
            if (onRefresh != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onRefresh,
                child: const HarborChip('RESCAN', glyph: Icons.refresh_rounded),
              ),
            ],
          ],
        ),
      );
    }

    final isTrade = s.verdict != Verdict.noTrade;
    final plan = s.stopPlan;
    final hasLevels = isTrade && plan != null && plan.isValid;

    return HarborCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: HarborEyebrow('MULTI-TIMEFRAME ANALYSIS')),
              if (onRefresh != null)
                GestureDetector(
                  onTap: onRefresh,
                  child: const HarborChip('RESCAN', glyph: Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _VerdictLine(scan: s),
          const SizedBox(height: 12),
          _ScoreRow(scan: s),
          if (hasLevels) ...[
            const SizedBox(height: 14),
            // Withheld. The stop plan is computed and validated internally, but
            // publishing entry/stop/TP would present an unmeasured estimate as a
            // trade parameter. The verdict, the scores and the reasons stay.
            const _LevelsWithheldNote(),
          ],
          if (layers != null) ...[
            const SizedBox(height: 14),
            SentimentLayersSection(
              layers: layers!,
              macroAlignment: s.macroAlignment,
              sentimentAlignment: s.sentimentAlignment,
              hasDirection: isTrade,
              isLong: s.verdict == Verdict.long,
            ),
          ],
          const HarborDivider(),
          _ReasonSection(scan: s),
          if (s.dataQuality.isNotEmpty) ...[
            const HarborDivider(),
            _DataQualitySection(notes: s.dataQuality),
          ],
          const HarborDivider(),
          _SpreadRow(scan: s),
          const SizedBox(height: 10),
          Text(
            riskDisclaimer,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: harborDim,
                  fontSize: 10.5,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.scan});

  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    final v = scan.verdict;
    final label = switch (v) {
      Verdict.long => 'LONG',
      Verdict.short => 'SHORT',
      Verdict.noTrade => 'NO TRADE',
    };
    // Grade is only meaningful for a real setup; a vetoed scan has no grade.
    final gradeLabel = scan.verdict == Verdict.noTrade ? null : _gradeLabel(scan.grade);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (v != Verdict.noTrade)
          DirectionPill(direction: v == Verdict.long ? Direction.long : Direction.short),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: v == Verdict.noTrade ? harborDim : harborInk,
                      letterSpacing: -0.4,
                    ),
              ),
              if (gradeLabel != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    'Setup grade $gradeLabel',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: harborDim,
                          fontSize: 11,
                        ),
                  ),
                ),
            ],
          ),
        ),
        if (scan.verdict == Verdict.noTrade)
          const HarborChip('FILTERING', glyph: Icons.shield_outlined),
      ],
    );
  }

  static String _gradeLabel(Grade g) => switch (g) {
        Grade.aPlus => 'A+',
        Grade.a => 'A',
        Grade.b => 'B',
        Grade.insufficient => '—',
      };
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({required this.scan});

  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    // The score is explicitly setup quality on a fixed scale, never a
    // probability. The label prevents the number being read as a chance.
    return Row(
      children: [
        _ScoreCell(
          label: 'TECHNICAL',
          value: '${scan.technicalScore}/12',
          hint: 'setup quality, not probability',
        ),
        const SizedBox(width: 10),
        _ScoreCell(
          label: 'FINAL',
          value: scan.finalScore.toStringAsFixed(1),
          hint: 'after macro/sentiment overlay',
        ),
        if (scan.atr5m != null) ...[
          const SizedBox(width: 10),
          _ScoreCell(
            label: 'ATR 5M',
            value: scan.atr5m!.toStringAsFixed(2),
            hint: 'volatility unit for stops',
          ),
        ],
      ],
    );
  }
}

class _ScoreCell extends StatelessWidget {
  const _ScoreCell({required this.label, required this.value, required this.hint});

  final String label;
  final String value;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: harborDim,
                  fontSize: 9,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: harborDim,
                  fontSize: 9,
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }
}

/// The grid is retained so the stop-plan formatting stays testable; it is not
/// rendered.
@visibleForTesting
class LevelGrid extends StatelessWidget {
  const LevelGrid({super.key, required this.plan});

  final StopPlan plan;

  @override
  Widget build(BuildContext context) {
    // The R:R chip shows TP2 reward-to-risk, which is the number the
    // methodology floors at 1.8R.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: HarborEyebrow('STRUCTURAL LEVELS')),
            HarborChip(
              'R:R ${plan.tp2R.toStringAsFixed(2)}',
              glyph: Icons.trending_up_rounded,
            ),
          ],
        ),
        const SizedBox(height: 8),
        VerdictLevelGrid(
          entry: VerdictLevelCell(
            label: 'Entry',
            value: plan.entry.toStringAsFixed(2),
            sub: 'market',
          ),
          cells: [
            VerdictLevelCell(
              label: 'Stop',
              value: plan.stopLoss.toStringAsFixed(2),
              sub: 'structural',
              highlighted: true,
            ),
            VerdictLevelCell(
              label: 'TP1',
              value: plan.tp1.toStringAsFixed(2),
              sub: '1R',
            ),
            VerdictLevelCell(
              label: 'TP2',
              value: plan.tp2.toStringAsFixed(2),
              sub: '2R',
            ),
            VerdictLevelCell(
              label: 'TP3',
              value: plan.tp3.toStringAsFixed(2),
              sub: '3R',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Stop ${plan.riskDistanceAtr.toStringAsFixed(2)}x ATR · '
          'buffer ${plan.bufferSource}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: harborDim,
                fontSize: 10,
              ),
        ),
      ],
    );
  }
}

class _ReasonSection extends StatelessWidget {
  const _ReasonSection({required this.scan});

  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    // Vetoes first: when nothing can be published, the blocking reason is what
    // the user actually needs to read.
    final vetoes = scan.vetoes;
    final supports = scan.reasonCodes.where((c) => !vetoes.contains(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HarborEyebrow(vetoes.isEmpty ? 'WHY IT QUALIFIED' : 'WHY NO TRADE'),
        const SizedBox(height: 7),
        if (vetoes.isEmpty && supports.isEmpty)
          Text(
            'No reason codes recorded.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: harborDim),
          ),
        if (vetoes.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in vetoes) HarborChip(_humanCode(c), glyphColor: harborShort),
            ],
          ),
          if (supports.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in supports) HarborChip(_humanCode(c)),
              ],
            ),
          ],
        ] else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in supports) HarborChip(_humanCode(c)),
            ],
          ),
        ],
      ],
    );
  }
}

class _DataQualitySection extends StatelessWidget {
  const _DataQualitySection({required this.notes});

  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HarborEyebrow('DATA QUALITY'),
        const SizedBox(height: 6),
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 4, right: 5),
                  child: Icon(Icons.info_outline_rounded, size: 11, color: harborDim),
                ),
                Expanded(
                  child: Text(
                    n,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: harborDim,
                          fontSize: 10.5,
                          height: 1.35,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SpreadRow extends StatelessWidget {
  const _SpreadRow({required this.scan});

  final ScanResult scan;

  @override
  Widget build(BuildContext context) {
    final s = scan.spread;
    // UNAVAILABLE is stated explicitly. It is not a pass: the spread vetoes did
    // not run, and the user should know that.
    final label = s.isGenuine
        ? 'VENUE SPREAD ${s.value?.toStringAsFixed(2)} USD · ${s.source ?? 'unknown'}'
        : 'SPREAD UNAVAILABLE · SPREAD VETOES UNEVALUATED';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          s.isGenuine ? Icons.check_circle_outline_rounded : Icons.remove_circle_outline_rounded,
          size: 13,
          color: s.isGenuine ? harborCobalt : harborWarn,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: harborDim,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

/// Turns a reason-code enum into language a trader can act on.
String _humanCode(ReasonCode c) => switch (c) {
      ReasonCode.h1TrendAligned => '1H trend aligned',
      ReasonCode.h1RsiFavorable => '1H RSI zone',
      ReasonCode.h1MacdAligned => '1H MACD',
      ReasonCode.m30StructureAligned => '30m structure',
      ReasonCode.m15PullbackToZone => '15m pullback',
      ReasonCode.m15CandleConfirmation => '15m candle confirm',
      ReasonCode.m5TriggerPresent => '5m trigger',
      ReasonCode.adxConfirmsTrend => 'Trend strength',
      ReasonCode.volatilitySuitable => 'Volatility OK',
      ReasonCode.macroSupports => 'Macro supports',
      ReasonCode.sentimentSupports => 'Positioning supports',
      ReasonCode.v1Blackout => 'News blackout',
      ReasonCode.v2SpreadUnevaluated => 'Spread unmeasured',
      ReasonCode.v3DataStale => 'Insufficient data',
      ReasonCode.v4VolatilityExtreme => 'Extreme volatility',
      ReasonCode.v5PoorRewardRisk => 'Poor R:R',
      ReasonCode.v6DirectionConflict => 'Macro conflict',
      ReasonCode.v7DailyLimit => 'Daily limit',
      ReasonCode.v8SessionClosed => 'Session closed',
      ReasonCode.v9Duplicate => 'Duplicate setup',
      ReasonCode.v10ConfirmationLow => 'Weak confirmation',
      ReasonCode.v11H1Neutral => '1H neutral',
      ReasonCode.v12LowConfluence => 'Low confluence',
      ReasonCode.v13BadStopDistance => 'Stop distance',
      ReasonCode.v14RsiExhausted => 'RSI exhausted',
      ReasonCode.v15ExtendedEntry => 'Entry too extended',
    };

/// Replaces the level grid wherever a valid stop plan exists.
///
/// The plan is computed and range-checked, but it is not published: there is no
/// forward record yet, and a badge does not stop a number being acted on. The
/// verdict, score decomposition, macro layers and reasons are unaffected.
class _LevelsWithheldNote extends StatelessWidget {
  const _LevelsWithheldNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: harborWarnSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: harborLine),
      ),
      child: const Text(
        'Entry, stop and targets withheld — not yet validated against a forward '
        'record. The verdict and its reasons are shown instead.',
        style: TextStyle(fontSize: 10.5, height: 1.45, color: harborInk),
      ),
    );
  }
}