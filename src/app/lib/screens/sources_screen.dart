/// Screen 3 — Sources (spec §17): why the consensus exists.
///
/// An agreement summary, then one compact row per source that expands into
/// the full detail: agree tick, direction, entry/stop/targets, freshness
/// age, hit-rate table and a "View Original" action. Toggling a source
/// recomputes the agreement summary live. No url_launcher dependency in the
/// MVP: the link-out shows a placeholder `SnackBar` (`Opens <url>`) until
/// live wiring (T5.7) opens the URL externally.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mock_fixtures.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

/// Independence factor reported by the consensus engine for the active setup
/// (spec §3). Fixture-pinned in MOCK_MODE; live values arrive with T5.7.
const String _independence = '0.80';

/// Agreement band + score for the active setup. Agreement, not a forecast
/// (rule 4) — never rendered as a probability.
const String _agreement = 'STRONG 82';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sources = MockFixtures.sources;
    final enabled = sources.where((s) => state.isSourceEnabled(s.id)).toList();
    final agreeing = enabled.where((s) => s.agrees).length;
    return ListView(
      key: const PageStorageKey<String>('sources'),
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        const HarborHeader(subtitle: 'SOURCES · #A482'),
        _summary(agreeing, enabled.length, enabled),
        const SizedBox(height: 11),
        const Center(
          child: Text(
            'Tap a card for full details · toggle to include',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              letterSpacing: 0.6,
              color: harborFaint,
            ),
          ),
        ),
        const SizedBox(height: 5),
        for (final source in sources) _SourceCard(source: source),
        const SizedBox(height: 13),
        const _IndependenceNote(),
        const SizedBox(height: 9),
        const Center(
          child: Text(
            'Fingerprints verified · 21:47:12',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              color: harborFaint,
            ),
          ),
        ),
      ],
    );
  }

  /// Inverted summary surface (mockup `.sumcard`) followed by the engine's
  /// independence / agreement report.
  ///
  /// Only the enabled sources are listed, so flipping a toggle is visible in
  /// both the headline split and the chip row — the consensus recomputes on
  /// every toggle, it is never a stale figure.
  Widget _summary(int agreeing, int total, List<DisplaySource> enabled) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 18),
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: harborInk,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$agreeing / $total',
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 30,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 9),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 3),
                    child: Text(
                      'agree',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final source in enabled)
                    HarborChip(
                      'DESK ${source.id}',
                      glyph: source.agrees
                          ? HarborIcons.check
                          : HarborIcons.cross,
                      glyphColor: source.agrees ? harborLong : harborShort,
                      fontSize: 8,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: const [
              Expanded(
                child: HarborStat(value: _independence, label: 'Independence'),
              ),
              SizedBox(width: 8),
              Expanded(
                child: HarborStat(value: _agreement, label: 'Agreement'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One collected source. Dense row, so the card radius drops to 16 (the same
/// treatment the History log gives its rows) and the header supplies its own
/// padding; the expanded detail is hairline-separated.
class _SourceCard extends StatefulWidget {
  const _SourceCard({required this.source});

  final DisplaySource source;

  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final enabled = context.select<AppState, bool>(
      (state) => state.isSourceEnabled(s.id),
    );
    final dirColor = s.direction == Direction.long ? harborLong : harborShort;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: HarborCard(
        radius: 16,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    _tick(s.agrees),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.name,
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'TP1 ${s.tp1HitRate}% · ${s.freshnessText}',
                            style: const TextStyle(
                              fontFamily: 'Space Mono',
                              fontSize: 10,
                              color: harborFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      s.direction == Direction.long ? 'LONG' : 'SHORT',
                      style: TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: dirColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Switch(
                      value: enabled,
                      activeTrackColor: harborLong,
                      inactiveTrackColor: harborLine,
                      onChanged: (value) => context
                          .read<AppState>()
                          .setSourceEnabled(s.id, value),
                    ),
                    HarborChevron(open: _open),
                  ],
                ),
              ),
            ),
            if (_open) ...[
              const HarborDivider(),
              _detailRow('Entry', s.entryText),
              const HarborDivider(),
              // The desk quotes a stop LEVEL; the pip distance beside it is
              // derived from [DisplaySource.stopPoints] through the trader's
              // [PipConvention] (D-20260927-003), so a convention change
              // rescales every desk instead of leaving a stale one behind.
              // A source that quotes no distance shows the bare level.
              _detailRow('Stop', _stopValue(context, s)),
              const HarborDivider(),
              _detailRow('Targets', s.targetsText),
              const HarborDivider(),
              _hitTable(s),
              _reasoning(s),
              const HarborDivider(),
              _viewOriginal(context, s),
            ],
          ],
        ),
      ),
    );
  }

  /// Agreement tick (green check) or disagreement cross (red). The only
  /// place on this screen where the two marks appear, so agreement always
  /// reads the same way (rule 4: agreement, not probability).
  Widget _tick(bool agrees) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: agrees ? harborLongSoft : harborShortSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        agrees ? HarborIcons.check : HarborIcons.cross,
        size: 14,
        color: agrees ? harborLong : harborShort,
      ),
    );
  }

  /// A desk's stop as `LEVEL · −Npips`, with the pip figure scaled by the
  /// active convention. Falls back to the bare level when the source quoted
  /// no distance, so an absent figure is never invented (product rule 2).
  String _stopValue(BuildContext context, DisplaySource s) {
    final points = s.stopPoints;
    if (points == null) return s.stopText;
    final factor = context.select<AppState, PipConvention>(
      (state) => state.pipConvention,
    ).pipFactor;
    final pips = pipsFromPoints(points, pipFactor: factor).abs();
    return '${s.stopText} · −${pips}p';
  }

  /// ENTRY / STOP / TARGETS line: eyebrow key, Space Mono value.
  Widget _detailRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          HarborEyebrow(key),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ],
      ),
    );
  }

  /// TP1–TP3 hit rates as a small table: faint caption header, hairline rules
  /// between the columns, Space Mono numerals.
  ///
  /// The meter fill is cobalt, not green — a source's track record is neither
  /// agreement nor direction, so it must not borrow that colour language.
  Widget _hitTable(DisplaySource s) {
    final rows = <(String, int)>[
      ('TP1', s.tp1HitRate),
      ('TP2', s.tp2HitRate),
      ('TP3', s.tp3HitRate),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('Hit rate · last 40 signals', color: harborFaint),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const HarborDivider(),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(rows[i].$1, style: _hitLabel),
                ),
                const HarborDivider(verticalExtent: 12),
                const SizedBox(width: 9),
                Expanded(child: _meter(rows[i].$2)),
                const SizedBox(width: 9),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${rows[i].$2}%',
                    style: _hitValue,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Same geometry as the Radar consensus meter, so the two never disagree.
  Widget _meter(int percent) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: DecoratedBox(
        decoration: const BoxDecoration(color: meterTrack),
        child: SizedBox(
          height: 6,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: percent.clamp(0, 100) / 100,
            child: const ColoredBox(color: harborCobalt),
          ),
        ),
      ),
    );
  }

  /// The source's own wording, quoted. Display only — the UI never rewrites
  /// or extrapolates a source's reasoning (rule 5).
  Widget _reasoning(DisplaySource s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Text(
        '"${s.reasoning}"',
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 12,
          height: 1.55,
          color: harborDim,
        ),
      ),
    );
  }

  /// Link-out row (mockup `.orig`): cobalt label + outbound arrow. Placeholder
  /// until T5.7 opens [DisplaySource.sourceUrl] externally.
  Widget _viewOriginal(BuildContext context, DisplaySource s) {
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Opens ${s.sourceUrl}')),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(HarborIcons.arrowUpRight, size: 13, color: harborCobalt),
            SizedBox(width: 7),
            Text(
              'VIEW ORIGINAL',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: harborCobalt,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Independence explainer — a trust note, not a call to action, so it stays
/// the quietest block on the screen: no border, no accent, no button. It
/// explains how many independent votes the cluster is worth (rule 3).
class _IndependenceNote extends StatelessWidget {
  const _IndependenceNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HarborEyebrow('Independence check'),
          const SizedBox(height: 7),
          Text(
            'A/B/C/E cluster tightly on levels but differ in author, wording '
            'and timing → counted as 3.2 independent votes. '
            'No copy-paste detected.',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 9.5,
              height: 1.7,
              color: harborDim,
            ),
          ),
        ],
      ),
    );
  }
}

/// Table cell styles: mono labels and values, never Sora.
const TextStyle _hitLabel = TextStyle(
  fontFamily: 'Space Mono',
  fontSize: 9,
  fontWeight: FontWeight.w700,
  color: harborDim,
);

const TextStyle _hitValue = TextStyle(
  fontFamily: 'Space Mono',
  fontSize: 10,
  fontWeight: FontWeight.w700,
  color: harborInk,
);
