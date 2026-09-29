/// Screen 6 — Events (addendum §5.2, TASK-07).
///
/// Upcoming (chronological HIGH/MEDIUM events, 7-day window) · Results
/// (actuals vs forecast + surprise flags) · News (macro-backdrop themes +
/// headlines, title + source + link only). Context and guardrails — never
/// votes (rule 9): no banner here suggests a trade, and an empty calendar
/// renders silence, not a signal.
library;

import 'package:flutter/material.dart';

import '../data/mock_fixtures.dart';
import '../models/display_models.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('events'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        const HarborHeader(subtitle: 'MACRO CONTEXT · NEVER VOTES'),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 0, label: Text('UPCOMING')),
            ButtonSegment(value: 1, label: Text('RESULTS')),
            ButtonSegment(value: 2, label: Text('NEWS')),
          ],
          selected: {_tab},
          onSelectionChanged: (selected) =>
              setState(() => _tab = selected.first),
          style: const ButtonStyle(
            textStyle: WidgetStatePropertyAll(
              TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        switch (_tab) {
          0 => const _UpcomingTab(),
          1 => const _ResultsTab(),
          _ => const _NewsTab(),
        },
      ],
    );
  }
}

/// Upcoming HIGH/MEDIUM events with countdowns + blackout note.
class _UpcomingTab extends StatelessWidget {
  const _UpcomingTab();

  @override
  Widget build(BuildContext context) {
    final events = MockFixtures.upcomingEvents;
    final next = events.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEXT HIGH-IMPACT',
                  style: TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    letterSpacing: 2.2,
                    color: harborFaint,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  next.title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                EventCountdown(startsIn: next.startsIn),
                const SizedBox(height: 8),
                const Text(
                  'New signals paused from 30 min before until 15 min after release.',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 12,
                    color: harborDim,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (final e in events) _EventRow(event: e),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final DisplayEvent event;

  @override
  Widget build(BuildContext context) {
    return Card(
      // Mockup `.erow` radius is 16px (not the theme default 18px).
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: harborLine),
      ),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${event.currency} · F ${event.forecast ?? '—'} · P ${event.previous ?? '—'}',
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 10,
                      color: harborDim,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'in ${formatCountdown(event.startsIn)}',
                    style: const TextStyle(
                      fontFamily: 'Space Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: harborDim,
                    ),
                  ),
                ],
              ),
            ),
            ImpactPill(impact: event.impact),
          ],
        ),
      ),
    );
  }
}

/// Past events: actual vs forecast with surprise highlights (§3.3).
class _ResultsTab extends StatelessWidget {
  const _ResultsTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final e in MockFixtures.resultEvents)
          Card(
            // Mockup `.erow` radius is 16px (not the theme default 18px).
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: harborLine),
            ),
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A ${e.actual ?? '—'} · F ${e.forecast ?? '—'} · P ${e.previous ?? '—'}',
                          style: const TextStyle(
                            fontFamily: 'Space Mono',
                            fontSize: 10,
                            color: harborDim,
                          ),
                        ),
                        if (e.isSurprise) ...[
                          const SizedBox(height: 6),
                          Text(
                            e.surprise == 'hot'
                                ? '▲ SURPRISE — hotter than forecast, expect volatility'
                                : '▼ SURPRISE — cooler than forecast, expect volatility',
                            style: const TextStyle(
                              fontFamily: 'Space Mono',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: harborShort,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 6),
                          const Text(
                            '○ IN LINE — near forecast',
                            style: TextStyle(
                              fontFamily: 'Space Mono',
                              fontSize: 10,
                              color: harborDim,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ImpactPill(impact: e.impact),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Macro backdrop (latest digest) + gold-news headlines (links only).
class _NewsTab extends StatelessWidget {
  const _NewsTab();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KickLabel('MACRO BACKDROP · DISPLAY ONLY'),
        const SizedBox(height: 8),
        for (final t in MockFixtures.digestThemes)
          Card(
            // Mockup `.news` radius is 16px (not the theme default 18px).
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: harborLine),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.theme,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PressurePill(pressure: t.pressure),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        const KickLabel('GOLD NEWS · HEADLINES ONLY'),
        const SizedBox(height: 8),
        for (final n in MockFixtures.headlines)
          Card(
            // Mockup `.news` radius is 16px (not the theme default 18px).
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: harborLine),
            ),
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Opens ${n.url}')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      n.title,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${n.source.toUpperCase()} · ${n.ageText} · OPEN ORIGINAL ↗',
                      style: const TextStyle(
                        fontFamily: 'Space Mono',
                        fontSize: 10,
                        letterSpacing: 0.4,
                        color: harborFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
