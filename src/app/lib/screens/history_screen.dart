/// Screen 4 — History: past signals and their final status.
///
/// Newest first, covering TP-hit / invalidated / expired / no-consensus /
/// developing states from mock fixtures. Restyled onto the unified Harbor
/// language: a [HarborStat] header, dense [HarborCard] rows at radius 16,
/// Space Mono for every figure and Sora for every label, with the state tag
/// carried by [StatusPill].
///
/// Every pip figure is derived at render time from the closed setup's
/// recorded POINT distance through the trader's [PipConvention]
/// (D-20260927-003) — never from a stored pip string — so switching the
/// convention rescales the log and the net total together. The sign is a
/// recorded outcome, not a forecast, and is never presented as one.
///
/// LIVE MODE
/// Rows and the stat tiles come from the polled [LiveData] snapshot, and the
/// tiles are derived from exactly those rows — an offline build has no poller
/// and keeps the recorded window totals. An empty live log renders the honest
/// "no closed setups yet" state rather than the fixture log.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/live_data.dart';
import '../data/mock_fixtures.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

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
    // Watched so a convention change in Settings rescales the log in place.
    final convention = context.watch<AppState>().pipConvention;
    final pipFactor = convention.pipFactor;
    final live = _liveOf(context);
    // Live rows come from the pipeline; an empty log is a real answer and
    // renders the empty state below rather than fixture history.
    final entries = live != null ? live.history : MockFixtures.history;
    return ListView(
      key: const PageStorageKey<String>('history'),
      // Horizontal gutters belong to the shared chrome (header 18px, cards
      // 18px), so the list itself only owns the trailing space.
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        const HarborHeader(subtitle: 'HISTORY · 7 DAYS'),
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 2, 18, 0),
          child: HarborEyebrow('Signal log · 7 days'),
        ),
        const SizedBox(height: 11),
        _StatHeader(pipFactor: pipFactor, entries: entries, live: live != null),
        const SizedBox(height: 11),
        if (entries.isEmpty)
          const _EmptyNote('No closed setups yet.')
        else
          for (final entry in entries) ...[
            _HistoryRow(entry: entry, pipFactor: pipFactor),
            const SizedBox(height: 9),
          ],
        const SizedBox(height: 2),
        Center(
          child: Text(
            'Pips x${convention.pipSizeLabel} · per D-003',
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              letterSpacing: 0.6,
              color: harborFaint,
            ),
          ),
        ),
      ],
    );
  }
}

/// Wins / losses / TP distribution as four [HarborStat] tiles.
///
/// The row is wrapped in a scale-to-fit box because the longest eyebrow
/// (`INVALIDATED`) is wider than a quarter of a 390px page — HTML lets that
/// overflow silently, a Flutter `Row` would either wrap the label or clip it.
/// One uniform scale keeps all four tiles the same height and the labels on
/// a single line.
///
/// Offline the tiles are the recorded window totals (fixtures). Live there is
/// no recorded total to show, so every figure is derived from the rows the
/// poller actually returned — including the net, which is the sum of their
/// closed outcomes.
class _StatHeader extends StatelessWidget {
  const _StatHeader({
    required this.pipFactor,
    required this.entries,
    required this.live,
  });

  /// Points per pip for the active [PipConvention]; the tiles scale with the
  /// log rows.
  final int pipFactor;

  final List<DisplayHistoryEntry> entries;

  final bool live;

  /// Statuses that count as a target hit (spec §14).
  static const _hits = {
    DisplayStatus.tp1Hit,
    DisplayStatus.tp2Hit,
    DisplayStatus.tp3Hit,
  };

  int _count(Set<DisplayStatus> statuses) =>
      entries.where((e) => statuses.contains(e.status)).length;

  @override
  Widget build(BuildContext context) {
    final tpHits = _count(_hits);
    final invalidated = _count({DisplayStatus.invalidated});
    final expired = _count({DisplayStatus.expired});
    final net = pipsFromPoints(
      live
          ? entries.fold<double>(0, (sum, e) => sum + e.pipsPoints)
          : MockFixtures.historyNetPipsPoints,
      pipFactor: pipFactor,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            HarborStat(
              value: live ? '$tpHits' : '9',
              label: 'TP HIT',
              valueColor: harborLong,
            ),
            const SizedBox(width: 8),
            HarborStat(
              value: live ? '$invalidated' : '3',
              label: 'INVALIDATED',
              valueColor: harborShort,
            ),
            const SizedBox(width: 8),
            HarborStat(
              value: live ? '$expired' : '2',
              label: 'EXPIRED',
              valueColor: harborCobalt,
            ),
            const SizedBox(width: 8),
            HarborStat(value: '+$net', label: 'NET PIPS'),
          ],
        ),
      ),
    );
  }
}

/// Honest empty state for a live log with no closed setups yet. Silence, not a
/// signal — an empty history must never read as a result (product rule 2).
class _EmptyNote extends StatelessWidget {
  const _EmptyNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 12,
            color: harborFaint,
          ),
        ),
      ),
    );
  }
}

/// One closed setup: date/time, direction, Entry→outcome detail, pips and
/// the state tag. Dense row, so the card radius drops to 16 — the same
/// treatment the Sources list gives its rows.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.pipFactor});

  final DisplayHistoryEntry entry;

  /// Points per pip for the active [PipConvention]; the row's pip figure is
  /// derived from [DisplayHistoryEntry.pipsPoints] on every build.
  final int pipFactor;

  @override
  Widget build(BuildContext context) {
    final pips = pipsLabel(entry.pipsPoints, pipFactor: pipFactor);
    return HarborCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DirectionMark(direction: entry.direction, size: 13),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  entry.whenText,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    color: harborFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _tighten(entry.detailText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 11,
              color: harborDim,
            ),
          ),
          // Hairline above the outcome row (mockup `.hrow .bot`): the detail
          // line is the setup, this is what it produced. Indented to the card
          // edge so the rule spans the full surface. The gaps either side are
          // trimmed by 3px so the rule costs the row ~6px, not 19.
          const SizedBox(height: 7),
          const HarborDivider(indent: 14),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusPill(status: entry.status),
              const Spacer(),
              Text(
                pips,
                style: TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _pipsColor(pips),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// A closed setup's pips: gained is green, lost is red, and a flat `0 PIPS`
  /// (never confirmed, expired, no consensus) stays faint so it can never be
  /// mistaken for a result.
  static Color _pipsColor(String pips) {
    if (pips.startsWith('+')) return harborLong;
    if (pips.startsWith('-') || pips.startsWith('−')) return harborShort;
    return harborFaint;
  }

  /// Detail-line separator collapsed for every row, not just the widest.
  ///
  /// The detail line gets one line of 11px Space Mono inside a 324px card at
  /// 390px, and Space Mono is monospaced at ~7px a glyph, so the line holds
  /// about 46 characters. A fully spaced `·` separator spent two of those per
  /// break — enough to push the trailing value of the widest rows onto a
  /// second line and make the row jump in height. Dropping the padding
  /// returns three characters per row, which is the whole budget the widest
  /// row needs. Every value is kept; only the gap around the separator goes.
  static String _tighten(String detail) =>
      detail.replaceAll(_looseSeparator, _tightSeparator);

  /// Spelled with escapes because the two differ by exactly one space.
  static const _looseSeparator = ' · ';
  static const _tightSeparator = '·';
}
