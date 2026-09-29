/// Screen 3 — Sources (spec §17): why the consensus exists.
///
/// Per-source cards with agreement tick, direction, levels, freshness age,
/// and a "View Original" action. No url_launcher dependency in the MVP:
/// the action shows a placeholder `SnackBar` (`Opens <url>`) until live
/// wiring (T5.7) opens the URL externally.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mock_fixtures.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sources = MockFixtures.sources;
    final enabled =
        sources.where((s) => state.isSourceEnabled(s.id)).toList();
    final agreeing =
        enabled.where((s) => s.agrees).length;
    return ListView(
      key: const PageStorageKey<String>('sources'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const HarborHeader(subtitle: 'SOURCES · #A482'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: harborInk,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                '$agreeing / ${enabled.length} agree',
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              const Text(
                'INDEPENDENCE 0.80 · STRONG 82',
                style: TextStyle(
                  fontFamily: 'Space Mono',
                  fontSize: 10,
                  color: Color(0xFF93A1B8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Tap a card for full details · toggle to include',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              letterSpacing: 1,
              color: harborFaint,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final source in sources) _SourceCard(source: source),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: harborLine),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'INDEPENDENCE CHECK — A/B/C/E cluster tightly on levels but differ in author, wording and timing → counted as 3.2 independent votes. No copy-paste detected.',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              height: 1.7,
              color: harborDim,
            ),
          ),
        ),
        const SizedBox(height: 8),
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
}

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
      child: Card(
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: s.agrees ? harborLongSoft : harborShortSoft,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        s.agrees
                            ? HarborIcons.check
                            : HarborIcons.cross,
                        size: 14,
                        color: s.agrees ? harborLong : harborShort,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(height: 3),
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
                    const SizedBox(width: 8),
                    Switch(
                      value: enabled,
                      activeTrackColor: harborLong,
                      inactiveTrackColor: harborLine,
                      onChanged: (value) => context
                          .read<AppState>()
                          .setSourceEnabled(s.id, value),
                    ),
                    // Mockup `.chev` is a text glyph (›, 16px) that rotates
                    // 90° and turns cobalt when open — not a Material icon.
                    RotatedBox(
                      quarterTurns: _open ? 1 : 0,
                      child: Text(
                        '›',
                        style: TextStyle(
                          fontSize: 16,
                          color: _open ? harborCobalt : harborFaint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_open) ...[
              const Divider(height: 1, color: harborLine),
              _row('ENTRY', s.entryText),
              _row('STOP', s.stopText),
              _row('TARGETS', s.targetsText),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'HIT RATE · LAST 40 SIGNALS',
                      style: TextStyle(
                        fontFamily: 'Space Mono',
                        fontSize: 9,
                        letterSpacing: 1.6,
                        color: harborFaint,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _hitBar('TP1', s.tp1HitRate),
                    _hitBar('TP2', s.tp2HitRate),
                    _hitBar('TP3', s.tp3HitRate),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '"${s.reasoning}"',
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 12,
                    height: 1.55,
                    color: harborDim,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1, color: harborLine),
              TextButton.icon(
                onPressed: () {
                  // Placeholder until T5.7 opens sourceUrl externally.
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Opens ${s.sourceUrl}')),
                  );
                },
                icon: const Icon(HarborIcons.arrowUpRight, size: 14),
                label: const Text('VIEW ORIGINAL'),
                style: TextButton.styleFrom(
                  foregroundColor: harborCobalt,
                  textStyle: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            key,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 10,
              letterSpacing: 1.6,
              color: harborFaint,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hitBar(String label, int percent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: harborDim,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 6,
                backgroundColor: const Color(0xFFE0E7F0),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(harborLong),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '$percent%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
