/// Screen 4 — History: past signals and their final status.
///
/// Newest first, covering TP-hit / invalidated / expired / no-consensus /
/// developing states from mock fixtures.
library;

import 'package:flutter/material.dart';

import '../data/mock_fixtures.dart';
import '../models/display_models.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('history'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const HarborHeader(subtitle: 'HISTORY · 7 DAYS'),
        const SizedBox(height: 12),
        const KickLabel('SIGNAL LOG · 7 DAYS'),
        const SizedBox(height: 10),
        Row(
          children: const [
            Expanded(child: _Stat(value: '9', label: 'TP HIT', color: harborLong)),
            SizedBox(width: 8),
            Expanded(
              child: _Stat(
                value: '3',
                label: 'INVALIDATED',
                color: harborShort,
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: _Stat(
                value: '2',
                label: 'EXPIRED',
                color: harborCobalt,
              ),
            ),
            SizedBox(width: 8),
            Expanded(child: _Stat(value: '+8400', label: 'NET PIPS')),
          ],
        ),
        const SizedBox(height: 6),
        for (final entry in MockFixtures.history) _HistoryRow(entry: entry),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            'Pips x0.01 · per D-003',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: harborFaint,
            ),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: color ?? harborInk,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
              color: harborFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final DisplayHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final pipsColor = entry.pipsText.startsWith('+')
        ? harborLong
        : entry.pipsText.startsWith('-')
            ? harborShort
            : harborFaint;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DirectionMark(direction: entry.direction, size: 13),
                const Spacer(),
                Text(
                  entry.whenText,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: harborFaint,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              entry.detailText,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: harborDim,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusPill(status: entry.status),
                Text(
                  entry.pipsText,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: pipsColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
