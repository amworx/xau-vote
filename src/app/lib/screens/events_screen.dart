/// Screen 6 — Events (addendum §5.2, TASK-07).
///
/// Upcoming (chronological HIGH/MEDIUM events, 7-day window) · Results
/// (actuals vs forecast + surprise flags) · News (macro-backdrop themes +
/// headlines, title + source + link only). Context and guardrails — never
/// votes (rule 9): no banner here suggests a trade, and an empty calendar
/// renders silence, not a signal.
///
/// Restyled onto the unified Harbor language: [HarborCard] rows at radius 16,
/// [HarborPill] tabs and filters, [HarborChip] currency badges, [ImpactPill]
/// impact, and a guard line that mirrors the Radar [EventGuardrailBar]
/// surface exactly. Headlines stay title + source + age + link — never full
/// article text (licensing constraint).
///
/// LIVE MODE
/// The calendar, the blackout card and the digest themes come from the polled
/// [LiveData] snapshot; an offline build mounts no poller and keeps the
/// fixtures. The snapshot carries scheduled releases and digest themes only,
/// so a live build reports no released rows and no headlines and says so —
/// an upcoming release is never restyled as a result, and an empty calendar
/// stays silence rather than borrowing a fixture row.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config.dart';
import '../data/live_data.dart';
import '../data/mock_fixtures.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  static const _tabs = ['UPCOMING', 'RESULTS', 'NEWS'];

  /// Currencies the guard watches. Every row is filterable, so a currency
  /// switch can only ever *narrow* what the guard reacts to.
  static const _currencies = ['USD', 'EUR', 'GBP'];

  /// Impact floor: HIGH only, HIGH+MED (default, matching the stored-window
  /// rule), or everything including the stored-only LOW rows.
  static const _impactOptions = [
    (label: 'HIGH', floor: EventImpact.high),
    (label: 'HIGH+', floor: EventImpact.medium),
    (label: 'ALL', floor: EventImpact.low),
  ];

  int _tab = 0;
  final Set<String> _currenciesOn = {'USD', 'EUR', 'GBP'};
  EventImpact _minImpact = EventImpact.medium;
  final Set<String> _muted = <String>{};

  /// The polled snapshot for this build, or null in an offline build. See
  /// [RadarScreen._liveOf] for why this is the single seam between the two.
  LiveData? get _live {
    try {
      return context.watch<LiveData>();
    } on ProviderNotFoundException {
      // A live build without its poller must fail loudly, never fall back to
      // fixtures (product rule 2).
      if (!mockMode) rethrow;
      return null;
    }
  }

  int _rank(EventImpact impact) => switch (impact) {
    EventImpact.high => 3,
    EventImpact.medium => 2,
    EventImpact.low => 1,
  };

  /// Currency chips start on and a row is hidden only when it falls outside
  /// both the currency set and the impact floor.
  bool _visible(DisplayEvent event) =>
      _currenciesOn.contains(event.currency) &&
      _rank(event.impact) >= _rank(_minImpact);

  bool _isMuted(String id) => _muted.contains(id);

  /// Scheduled releases the guard can see: the polled calendar in a live
  /// build, the fixture calendar offline.
  List<DisplayEvent> get _allEvents {
    final live = _live;
    return live != null ? live.events : MockFixtures.upcomingEvents;
  }

  List<DisplayEvent> get _visibleEvents => _allEvents.where(_visible).toList();

  /// Released events with an actual. The live calendar read is scheduled-only,
  /// so there is no released row to show and the tab renders its honest empty
  /// state — it never reuses an upcoming release as a result.
  List<DisplayEvent> get _resultEvents {
    final live = _live;
    return live != null ? const <DisplayEvent>[] : MockFixtures.resultEvents;
  }

  /// Latest macro digest: the polled themes in a live build, the fixture
  /// themes offline.
  List<DisplayDigestTheme> get _digestThemes {
    final live = _live;
    return live != null ? live.digest : MockFixtures.digestThemes;
  }

  /// Collected headlines. The snapshot carries the digest themes only, so a
  /// live build reports no headlines rather than the fixture set.
  List<DisplayNewsItem> get _headlines {
    final live = _live;
    return live != null ? const <DisplayNewsItem>[] : MockFixtures.headlines;
  }

  /// The soonest armed USD HIGH event — the only combination that pauses new
  /// signals. `null` when the trader muted or filtered it out, and the guard
  /// line then says so rather than borrowing another event's countdown.
  DisplayEvent? get _nextBlackout {
    for (final event in _visibleEvents) {
      if (_isMuted(event.id)) continue;
      if (event.impact == EventImpact.high && event.currency == 'USD') {
        return event;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey<String>('events'),
      // Horizontal gutters belong to the shared chrome (header 18px, cards
      // 18px), so the list itself only owns the trailing space.
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        const HarborHeader(subtitle: 'MACRO CONTEXT · NEVER VOTES'),
        _tabBar(),
        const SizedBox(height: 11),
        _filterCard(),
        const SizedBox(height: 10),
        _guardLine(),
        const SizedBox(height: 10),
        switch (_tab) {
          0 => _upcomingPane(),
          1 => _resultsPane(),
          _ => _newsPane(),
        },
      ],
    );
  }

  /// Upcoming / Results / News. [HarborPill] carries the selection, the
  /// 48px minimum is the mockup's touch target (`.tabs button{min-height:48px}`).
  Widget _tabBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: HarborPill(
                  _tabs[i],
                  active: _tab == i,
                  fontSize: 10,
                  onTap: () => setState(() => _tab = i),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Currency chips + impact floor. Both are guards: they decide which
  /// releases the guard watches, never which direction is taken.
  Widget _filterCard() {
    return HarborCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 60,
                child: HarborEyebrow('CCY', color: harborFaint),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ccy in _currencies)
                      HarborPill(
                        ccy,
                        fontSize: 10,
                        active: _currenciesOn.contains(ccy),
                        onTap: () => setState(() {
                          _currenciesOn.contains(ccy)
                              ? _currenciesOn.remove(ccy)
                              : _currenciesOn.add(ccy);
                        }),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                width: 60,
                child: HarborEyebrow('IMPACT', color: harborFaint),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final option in _impactOptions)
                      HarborPill(
                        option.label,
                        fontSize: 10,
                        active: _minImpact == option.floor,
                        onTap: () =>
                            setState(() => _minImpact = option.floor),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Guard line (mockup `.guard`), rendered with the Radar
  /// [EventGuardrailBar] language: ink surface, 6px [harborShort] dot and a
  /// 9px two-line block. It reports what the current filters arm — with no
  /// blackout window it prints an honest `—` rather than borrowing one.
  Widget _guardLine() {
    final visible = _visibleEvents;
    final armed = visible.where((e) => !_isMuted(e.id)).length;
    final muted = visible.where((e) => _isMuted(e.id)).length;
    final next = _nextBlackout;
    final scope = switch (_minImpact) {
      EventImpact.high => 'HIGH ONLY',
      EventImpact.medium => 'HIGH+MED',
      EventImpact.low => 'ALL',
    };
    final summary = StringBuffer('$scope · $armed ARMED');
    if (muted > 0) summary.write(' · $muted MUTED');
    summary.write(
      next == null
          ? ' · BLACKOUT —'
          : ' · BLACKOUT ${formatCountdown(next.startsIn)}',
    );
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: harborInk,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: harborShort,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'EVENT GUARDRAIL',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 9,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  summary.toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    fontSize: 9,
                    height: 1.35,
                    color: inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Upcoming pane: the next blackout card plus every armed/stored release
  /// that survived the current filters.
  Widget _upcomingPane() {
    final next = _nextBlackout;
    final events = _visibleEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nextBlackoutCard(next),
        const SizedBox(height: 10),
        if (events.isEmpty)
          const _SilenceNote('No events match these filters.')
        else
          for (final event in events) ...[
            _EventRow(
              event: event,
              muted: _isMuted(event.id),
              onToggleMute: () => setState(() {
                _isMuted(event.id)
                    ? _muted.remove(event.id)
                    : _muted.add(event.id);
              }),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// The blackout card. With no armed USD HIGH event the countdown is
  /// replaced by an honest empty state rather than a stale timer (rule 2).
  Widget _nextBlackoutCard(DisplayEvent? next) {
    return HarborCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next == null) ...[
            const HarborEyebrow('No USD high event armed'),
            const SizedBox(height: 8),
            const Text(
              'Muted or filtered out — no blackout window is active.',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 12,
                color: harborDim,
              ),
            ),
          ] else ...[
            const HarborEyebrow('Next high-impact'),
            const SizedBox(height: 8),
            Text(
              next.title,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
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
        ],
      ),
    );
  }

  /// Past events: actual vs forecast with the surprise flag (addendum §3.3).
  Widget _resultsPane() {
    final events = _resultEvents;
    if (events.isEmpty) return const _SilenceNote('No results yet.');
    return Column(
      children: [
        for (final event in events) ...[
          HarborCard(
            radius: 16,
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ImpactPill(impact: event.impact),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        event.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'Sora',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const HarborChip('DONE', fontSize: 8),
                  ],
                ),
                const SizedBox(height: 9),
                Text(
                  'A ${event.actual ?? '—'} · F ${event.forecast ?? '—'} · '
                  'P ${event.previous ?? '—'}',
                  style: const TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    color: harborDim,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  _surpriseLine(event),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Space Mono',
                    fontSize: 10,
                    fontWeight: event.isSurprise ? FontWeight.w700 : null,
                    color: event.isSurprise ? harborShort : harborDim,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  /// A released figure that beat or missed its forecast is volatility
  /// context. An in-line print is a neutral fact, so it keeps [harborDim] and
  /// never borrows the direction colours.
  static String _surpriseLine(DisplayEvent event) {
    if (!event.isSurprise) return '○ IN LINE — near forecast';
    return event.surprise == 'hot'
        ? '▲ SURPRISE — hotter than forecast, expect volatility'
        : '▼ SURPRISE — cooler than forecast, expect volatility';
  }

  /// News pane: the macro-backdrop themes (display only) and the collected
  /// headlines. Headline + source + age + link only — never article text.
  Widget _newsPane() {
    final themes = _digestThemes;
    final headlines = _headlines;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, 0),
          child: HarborEyebrow(
            'Macro backdrop · display only',
            color: harborFaint,
          ),
        ),
        const SizedBox(height: 9),
        if (themes.isEmpty)
          const _SilenceNote('No digest published yet.')
        else
          for (final theme in themes) ...[
            HarborCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.theme,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PressurePill(pressure: theme.pressure),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 6),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: HarborEyebrow('Gold news · headlines only', color: harborFaint),
        ),
        const SizedBox(height: 9),
        if (headlines.isEmpty)
          const _SilenceNote('No headlines collected.')
        else
          for (final headline in headlines) ...[
            _NewsCard(item: headline),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// One scheduled release. Impact + title + mute bell on the top line, the
/// currency badge and the forecast/previous figures below.
///
/// A muted row dims to 45% (mockup `.erow.muted`) so the guard's armed count
/// and the calendar never disagree about what is actually watched.
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.muted,
    required this.onToggleMute,
  });

  final DisplayEvent event;
  final bool muted;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: muted ? 0.45 : 1,
      child: HarborCard(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ImpactPill(impact: event.impact),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _MuteBell(
                  muted: muted,
                  label: '${muted ? 'Unmute' : 'Mute'} ${event.title} alerts',
                  onTap: onToggleMute,
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                HarborChip(event.currency, fontSize: 8),
                _figure('FCAST', event.forecast),
                _figure('PREV', event.previous),
              ],
            ),
            const SizedBox(height: 8),
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
    );
  }

  /// `KEY value`, or `KEY —` when the calendar has not published a figure.
  /// Never a made-up number (rule 2).
  static Widget _figure(String key, String? value) {
    return Text(
      '$key ${value ?? '—'}',
      style: const TextStyle(
        fontFamily: 'Space Mono',
        fontSize: 10,
        color: harborDim,
      ),
    );
  }
}

/// Per-event mute (mockup `.bell`): a 44px bordered square holding the
/// bundled UIcons bell, cobalt while armed and faint once muted.
class _MuteBell extends StatelessWidget {
  const _MuteBell({
    required this.muted,
    required this.label,
    required this.onTap,
  });

  final bool muted;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: !muted,
      label: label,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: harborLine),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              HarborIcons.bell,
              size: 18,
              color: muted ? harborFaint : harborCobalt,
            ),
          ),
        ),
      ),
    );
  }
}

/// One collected headline. Title + source + age + a cobalt link-out — the
/// full article is never fetched or shown (licensing constraint), and the
/// MVP has no `url_launcher`, so the link confirms with a placeholder toast.
class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item});

  final DisplayNewsItem item;

  @override
  Widget build(BuildContext context) {
    return HarborCard(
      radius: 16,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Opens ${item.url}')),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  fontFamily: 'Sora',
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${item.source.toUpperCase()} · ${item.ageText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Space Mono',
                        fontSize: 10,
                        letterSpacing: 0.4,
                        color: harborFaint,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    HarborIcons.arrowUpRight,
                    size: 12,
                    color: harborCobalt,
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    'OPEN ORIGINAL',
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty state for a filtered or not-yet-published slice. Silence, not a
/// signal — an empty calendar must never read as an instruction (rule 9).
class _SilenceNote extends StatelessWidget {
  const _SilenceNote(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'Sora',
          fontSize: 12,
          color: harborFaint,
        ),
      ),
    );
  }
}
