/// Screen 2 — Signal: full setup detail.
///
/// Lifecycle timeline (spec §14), the level grid with per-TP R:R, the
/// deliberately subordinate 1H/5M/position row (product rule 1: 1H is context
/// and never votes, 5M only confirms) and the target-scope control
/// (spec §10). Every surface comes from the shared Harbor primitives so the
/// screen reads as the same product as Radar. Strength is an agreement label
/// only — never rendered as a forecast (spec §7).
///
/// LIVE MODE
/// Direction, strength, levels and lifecycle come from the polled [LiveData]
/// snapshot. What the pipeline has not published is shown as `—`, never filled
/// from a fixture: the lifecycle has state but no transition timestamps, and
/// there is no 5M confirmation, 1H read or open position in the snapshot — so
/// no consensus renders the honest empty state and copy/share stay available
/// whenever there is a real setup to copy.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
// Session calendar only; the barrel also exports a Direction enum that collides
// with the app's display models.
import 'package:xau_core/analysis/session.dart';

import '../config.dart';
import '../data/live_data.dart';
import '../data/mock_fixtures.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';
import '../widgets/skeleton.dart';

class SignalScreen extends StatelessWidget {
  const SignalScreen({super.key, this.sessionOpenOverride});

  /// Pins the session state instead of reading the clock. Only tests pass this;
  /// a test that depended on the real calendar would pass midweek and fail at
  /// the weekend.
  @visibleForTesting
  final bool? sessionOpenOverride;

  /// The polled snapshot for this build, or null in an offline build. See
  /// [RadarScreen._liveOf] for why this is the single seam between the two.
  static LiveData? _liveOf(BuildContext context) {
    try {
      return context.watch<LiveData>();
    } on ProviderNotFoundException {
      // A live build without its poller must fail loudly, never fall back to
      // fixtures (product rule 2).
      if (!mockMode) rethrow;
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final live = _liveOf(context);
    final signal = live != null
        ? live.signal
        : state.scenario == RadarScenario.noConsensus
        ? MockFixtures.developing
        : state.scenario == RadarScenario.developing
        ? MockFixtures.developing
        : MockFixtures.strongLong;
    final show = visibleTps(state.targets);
    // Points are canonical; every pip readout on this screen derives from them
    // through the trader's pip convention (D-20260927-003). Read once here so
    // the whole screen shares one convention per build.
    final pipFactor = state.pipConvention.pipFactor;
    // A closed market cannot be entered, so a setup is not offered as one. The
    // record stays in the log; only the actionable framing is withheld.
    // The offline build previews fixtures and makes no market claim (its header
    // hides the pill), so gating the preview on the real calendar would only
    // blank the design at the weekend. A live build always reads the clock.
    final sessionOpen =
        sessionOpenOverride ?? (mockMode ? true : isSessionOpen(DateTime.now().toUtc()));
    // Recent closed setups, shown while the market is shut. Offline falls back
    // to the fixture log so the preview still demonstrates the section.
    final recentHistory = live != null
        ? live.history.take(5).toList(growable: false)
        : MockFixtures.history.take(5).toList(growable: false);
    // `DisplaySignal.price` carries a fixture default; live the quote comes
    // from the poller, so an absent tick prints `—`.
    final quote = live == null
        ? formatPrice(signal!.price)
        : live.price == null
        ? '—'
        : formatPrice(live.price!);
    return ListView(
      key: const PageStorageKey<String>('signal'),
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        HarborHeader(
          subtitle: 'SIGNAL · ${signal?.id ?? 'NO CONSENSUS'}',
          sessionOpen: sessionOpen,
          statusText: signal == null ? 'NO CONSENSUS' : statusLabel(signal.status),
        ),
        if (!sessionOpen) ...[
          const _MarketClosedNotice(),
          // A closed market is not an empty record. The closed setups still
          // happened and the trader still wants to review them, so the recent
          // history is listed underneath rather than leaving the screen bare.
          if (recentHistory.isEmpty && (live?.loading ?? false))
            const Column(
              children: [
                SkeletonCard(lines: 3),
                SkeletonCard(lines: 2),
              ],
            )
          else if (recentHistory.isNotEmpty)
            _ClosedSetupHistory(entries: recentHistory, pipFactor: pipFactor),
        ] else if (signal == null && (live?.loading ?? false))
          // First read in flight: hold the level grid's shape instead of
          // flashing "NO CONSENSUS", which reads as a verdict rather than as
          // "not loaded yet".
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: SkeletonCard(lines: 4),
          )
        else if (signal == null) const _NoSetupCard() else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HarborEyebrow('Active setup · 15M ${_directionWord(signal.direction)}'),
                const SizedBox(height: 9),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DirectionPill(direction: signal.direction, fontSize: 15),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          '$quote · '
                          '${bandLabel(signal.band)} ${signal.strength}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Space Mono',
                            fontSize: 11,
                            color: harborDim,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          _lifecycleCard(signal, pipFactor, live: live != null),
          const SizedBox(height: 10),
          _levelsCard(signal, show, pipFactor),
          const SizedBox(height: 10),
          _contextRow(pipFactor, live: live != null),
          const SizedBox(height: 11),
          _targetScope(),
          const SizedBox(height: 11),
          _positionStrip(pipFactor, live: live != null),
          const SizedBox(height: 13),
          _actions(context, signal, state.targets, pipFactor),
          const SizedBox(height: 11),
          // The open/expiry stamps are fixture-pinned; the snapshot carries
          // neither, so the line is dropped rather than dated falsely.
          if (live == null)
            const Center(
              child: Text(
                'Opened 21:44:03 · expires 22:44',
                style: TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 9,
                  letterSpacing: 0.6,
                  color: harborFaint,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// `LONG` / `SHORT` / `NO SIGNAL` — the only place direction is spelled out
  /// as a word rather than carried by [DirectionPill].
  String _directionWord(Direction direction) => switch (direction) {
    Direction.long => 'LONG',
    Direction.short => 'SHORT',
    Direction.neutral => 'NO SIGNAL',
  };

  /// Which lifecycle step the reported status sits on, or -1 for a state the
  /// walk-through does not cover. Used to mark the live current step without
  /// inventing transition timestamps.
  static int _lifecycleStep(DisplayStatus status) => switch (status) {
    DisplayStatus.developing => 0,
    DisplayStatus.ready => 1,
    DisplayStatus.confirmed => 2,
    DisplayStatus.active ||
    DisplayStatus.tp1Hit ||
    DisplayStatus.tp2Hit ||
    DisplayStatus.tp3Hit => 3,
    DisplayStatus.noSetup || DisplayStatus.invalidated || DisplayStatus.expired => -1,
  };

  /// Lifecycle timeline through ACTIVE (spec §14) plus the still-open target
  /// step.
  ///
  /// Offline the state timestamps are fixture-pinned. Live the current step is
  /// derived from the status the pipeline reported and every timestamp prints
  /// `—`, because the snapshot records the state, not the moments it changed.
  Widget _lifecycleCard(DisplaySignal signal, int pipFactor, {required bool live}) {
    const steps = [
      ('DEVELOPING', '21:31'),
      ('READY', '21:36'),
      ('CONFIRMED · 5M', '21:41'),
      ('ACTIVE', 'SINCE 21:44'),
    ];
    final current = live ? _lifecycleStep(signal.status) : steps.length - 1;
    return HarborCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('Lifecycle'),
          const SizedBox(height: 10),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const HarborDivider(),
            _lifecycleRow(
              label: steps[i].$1,
              timestamp: live ? '—' : steps[i].$2,
              isCurrent: i == current,
            ),
          ],
          const HarborDivider(),
          _targetRow(signal, pipFactor),
        ],
      ),
    );
  }

  Widget _lifecycleRow({
    required String label,
    required String timestamp,
    required bool isCurrent,
  }) {
    return Container(
      // Mockup `.life .lrow.now` wash — 5% cobalt marks the live step
      // without painting a state as if it were a direction.
      color: isCurrent ? harborCobalt.withValues(alpha: 0.05) : null,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          _LifecyclePill(label, isCurrent: isCurrent),
          const Spacer(),
          Text(
            timestamp,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 9,
              color: harborFaint,
            ),
          ),
        ],
      ),
    );
  }

  /// The open target step. With no TP1 from the pipeline the level is an
  /// honest `—` and the pip distance is omitted rather than invented
  /// (product rule 2).
  ///
  /// Label and level share one text span so the row stays a single text
  /// widget — the level grid above is the only place a bare level appears.
  Widget _targetRow(DisplaySignal signal, int pipFactor) {
    final tp = signal.tp1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE7ECF2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(
                      text: 'TP1',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.9,
                        color: harborDim,
                      ),
                    ),
                    TextSpan(
                      text: ' ${tp == null ? '—' : formatLevel(tp)}',
                      style: const TextStyle(
                        fontFamily: 'Space Mono',
                        fontSize: 11,
                        color: harborFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (tp != null)
            Text(
              '+${pipsTo(tp, signal.entryMid, pipFactor: pipFactor)} PIPS',
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 9,
                color: harborFaint,
              ),
            ),
        ],
      ),
    );
  }

  Widget _levelsCard(DisplaySignal signal, List<int> show, int pipFactor) {
    // Entry, stop and targets are no longer published. The engine still
    // computes them, but no forward record shows they were ever right, and an
    // UNVALIDATED badge does not stop a number from being traded. The screen
    // keeps the verdict, the reasons and the observed spread, and states here
    // that the numbers are withheld rather than showing a gap that reads as a
    // rendering fault.
    return HarborCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('Levels'),
          const SizedBox(height: 10),
          Text(
            'WITHHELD',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
              color: harborWarn,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'XV does not publish entry, stop or targets. No out-of-sample record '
            'exists yet showing a level of this kind was ever right, and a '
            'label does not stop a number being acted on. Levels return only '
            'once that record exists.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: harborInk),
          ),
        ],
      ),
    );
  }

  /// Entry zone spans the grid, then stop + the selected targets in two
  /// columns — the Radar level language, with the Signal sub-lines (pip
  /// distance, per-TP R:R) kept in the cell's sub slot.
  ///
  /// Retained for fixtures and for the day levels return. Not rendered.
  @visibleForTesting
  Widget levelGrid(DisplaySignal signal, List<int> show, int pipFactor) {
    final tps = {1: signal.tp1, 2: signal.tp2, 3: signal.tp3};
    final cells = <Widget>[
      VerdictLevelCell(
        label: 'Stop loss',
        value: formatLevel(signal.stopLoss),
        // The sub-line drops its unit on purpose: a half-grid cell is ~135px
        // wide at 390px, and `−1600 pips · risk 15.5 pts` overflowed it and
        // pushed this cell a line taller than its neighbour. The neighbouring
        // TP cells are already unit-free (`+1700 · 1:1.5`), and the risk
        // figure reads as points in this layout.
        sub:
            '−${pipsTo(signal.stopLoss, signal.entryMid, pipFactor: pipFactor).abs()} pips · '
            'risk ${(signal.entryMid - signal.stopLoss).toStringAsFixed(1)}',
      ),
    ];
    for (final n in show) {
      final tp = tps[n];
      if (tp == null) continue;
      final rr = riskReward(
        target: tp,
        entryLow: signal.entryLow,
        stopLoss: signal.stopLoss,
      );
      cells.add(
        VerdictLevelCell(
          label: 'TP$n',
          value: formatLevel(tp),
          sub:
              '+${pipsTo(tp, signal.entryMid, pipFactor: pipFactor)} · '
              '1:${rr.toStringAsFixed(1)}',
        ),
      );
    }
    return VerdictLevelGrid(
      entry: VerdictLevelCell(
        label: 'Entry zone',
        value:
            '${formatLevel(signal.entryLow)}-'
            '${formatLevel(signal.entryHigh)}',
        sub:
            '${zonePips(signal.entryLow, signal.entryHigh, pipFactor: pipFactor)}-pip zone',
        highlighted: true,
      ),
      cells: cells,
    );
  }

  /// 1H context, 5M confirmation and open P/L. Intentionally the quietest row
  /// on the screen: soft neutral fill, no border, no accent colour. 1H never
  /// votes (product rule 1), so it must never read like a directional call —
  /// green/red stays reserved for direction and agreement.
  ///
  /// Live all three print `—`: the snapshot carries no 1H read, no 5M
  /// confirmation and no position, and the offline words are claims the live
  /// pipeline has not made.
  Widget _contextRow(int pipFactor, {required bool live}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: _ContextBadge(title: '1H TREND', value: live ? '—' : 'SUPPORTIVE'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ContextBadge(title: '5M CONFIRM', value: live ? '—' : 'CONFIRMED'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ContextBadge(
              title: 'POSITION',
              value: live
                  ? '—'
                  : '+${pipsFromMove(MockFixtures.openPositionPoints, pipFactor: pipFactor)} PIPS',
            ),
          ),
        ],
      ),
    );
  }

  Widget _targetScope() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [HarborEyebrow('Target scope'), SizedBox(height: 9), TargetSelector()],
      ),
    );
  }

  /// Open-position strip. An in-profit position is a direction outcome, so it
  /// keeps the LONG green language from the mockup `.pstrip`.
  ///
  /// Live there is no position to report — XV does not place trades and the
  /// snapshot carries no fill — so the strip drops the green language and says
  /// so neutrally instead of claiming a profit that was never made.
  Widget _positionStrip(int pipFactor, {required bool live}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: live ? chipBg : harborLongSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: HarborEyebrow('Position status', color: live ? harborDim : harborLong),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: live ? harborLine : harborLong,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            live
                ? 'NO OPEN POSITION'
                : 'IN-PROFIT +${pipsFromMove(MockFixtures.openPositionPoints, pipFactor: pipFactor)} PIPS',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: live ? harborDim : harborLong,
            ),
          ),
        ],
      ),
    );
  }

  /// Copy / share the setup. The MVP has no platform share channel (no extra
  /// packages), so both paths hand the summary to the clipboard and confirm
  /// with the same toast the Radar card's action row uses.
  Widget _actions(
    BuildContext context,
    DisplaySignal signal,
    TargetSelection selection,
    int pipFactor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: HarborActionButton(
              label: 'COPY SIGNAL TEXT',
              onTap: () =>
                  _publish(context, signal, selection, pipFactor, 'Signal text copied'),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: HarborActionButton(
              label: '↗ SHARE',
              primary: false,
              onTap: () => _publish(
                context,
                signal,
                selection,
                pipFactor,
                'Signal text copied — paste to share',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _publish(
    BuildContext context,
    DisplaySignal signal,
    TargetSelection selection,
    int pipFactor,
    String toast,
  ) {
    // Raised synchronously so the feedback never waits on the clipboard.
    unawaited(
      Clipboard.setData(ClipboardData(text: _summary(signal, selection, pipFactor))),
    );
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toast)));
  }

  /// Agreement-first setup summary (spec §4) — score reads as the source
  /// split, never as a probability of profit (rule 4).
  String _summary(DisplaySignal signal, TargetSelection selection, int pipFactor) {
    final tps = {1: signal.tp1, 2: signal.tp2, 3: signal.tp3};
    final lines = <String>[
      'XAUUSD 15M ${_directionWord(signal.direction)} — '
          '${bandLabel(signal.band)} ${signal.agreeCount}/${signal.totalCount}',
      'Entry ${formatLevel(signal.entryLow)}-${formatLevel(signal.entryHigh)}'
          ' (market zone)',
      'Stop ${formatLevel(signal.stopLoss)} '
          '(${levelDistance(signal.entryMid, signal.stopLoss)})',
    ];
    for (var n = 1; n <= 3; n++) {
      final tp = tps[n];
      if (tp == null) continue;
      lines.add(
        'TP$n ${formatLevel(tp)} '
        '(+${pipsTo(tp, signal.entryMid, pipFactor: pipFactor)} pips)',
      );
    }
    lines.add('R:R ${bestRrValue(signal, selection)}');
    return lines.join('\n');
  }
}

/// No active setup (product rule 2: insufficient agreement is a real answer).
///
/// Closed setups listed while the market is shut.
///
/// Read-only on purpose: a closed setup cannot be entered, so this deliberately
/// offers no copy/share action that would hand the trader levels to act on.
class _ClosedSetupHistory extends StatelessWidget {
  const _ClosedSetupHistory({required this.entries, required this.pipFactor});

  final List<DisplayHistoryEntry> entries;
  final int pipFactor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('Recent closed setups · 7 days'),
          const SizedBox(height: 9),
          for (final entry in entries) ...[
            HarborCard(
              radius: 16,
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              child: Row(
                children: [
                  DirectionMark(direction: entry.direction, size: 13),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          entry.detailText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Space Mono',
                            fontSize: 10.5,
                            color: harborDim,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.whenText,
                          style: const TextStyle(
                            fontFamily: 'Space Mono',
                            fontSize: 9.5,
                            color: harborFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(status: entry.status),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Stand-in for the setup card while the spot market is closed.
///
/// Withholding the levels is the point: an entry, stop and target presented
/// over a shut market read as actionable, and the trader cannot act on any of
/// them. The setup is not deleted, it simply is not offered as a trade.
class _MarketClosedNotice extends StatelessWidget {
  const _MarketClosedNotice();

  @override
  @override
  Widget build(BuildContext context) {
    final reopens = nextOpenUtc(DateTime.now().toUtc());
    final wait = reopens?.difference(DateTime.now().toUtc());
    // Same distinction as the Radar closed card: a Tuesday-evening halt is not
    // "the weekend", and the wait differs by two days.
    final halted =
        closureAt(DateTime.now().toUtc()) == MarketClosure.dailyHalt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: HarborCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HarborEyebrow('Market status', color: harborWarn),
            const SizedBox(height: 8),
            const Text(
              'MARKET CLOSED',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              halted
                  ? 'Gold spot is halted for the daily rollover break. Entry, '
                      'stop and targets are withheld until quotes resume.'
                  : 'Gold spot is closed for the weekend. Entry, stop and targets '
                      'are withheld until the session reopens.',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                height: 1.45,
                color: harborDim,
              ),
            ),
            if (wait != null && !wait.isNegative) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const HarborEyebrow('Reopens in', color: harborFaint),
                  const SizedBox(width: 9),
                  Text(
                    formatCountdown(wait),
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: harborWarn,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The offline preview states the same thing through the Radar card, so the
/// copy matches: the room has not agreed, and XV waits. There is nothing to
/// copy here, so the copy/share actions are absent rather than pointing at a
/// signal that does not exist.
class _NoSetupCard extends StatelessWidget {
  const _NoSetupCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: HarborCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HarborEyebrow('No active setup'),
            const SizedBox(height: 8),
            const Text(
              'NO CONSENSUS',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'No 15M setup has cleared consensus right now.',
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
            ),
            const SizedBox(height: 6),
            const Text(
              'Waiting for stronger agreement.',
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
            ),
          ],
        ),
      ),
    );
  }
}

/// One lifecycle state as a small pill.
///
/// A lifecycle step is a state, not a direction, so it never takes the
/// green/red language — a neutral state is [harborDim] on a neutral fill and
/// the live step is the only accent. Anything that actually carries direction
/// stays with [DirectionPill].
class _LifecyclePill extends StatelessWidget {
  const _LifecyclePill(this.label, {required this.isCurrent});

  final String label;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isCurrent ? tpActiveBg : const Color(0xFFE7ECF2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Sora',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: isCurrent ? harborCobalt : harborDim,
        ),
      ),
    );
  }
}

/// 1H / 5M / position badge: the quietest surface on the screen. Soft neutral
/// fill, no border, no accent — 1H is context only and must not look like a
/// vote (product rule 1). Values are mono so the pip figure aligns.
class _ContextBadge extends StatelessWidget {
  const _ContextBadge({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: harborFaint,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }
}
