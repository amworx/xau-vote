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
// Event outlook types only; the `xau_core` barrel also exports a Direction enum
// that collides with the app's display models.
import 'package:xau_core/analysis/event_outlook.dart';

import '../config.dart';
import '../data/live_data.dart';
import '../data/mock_fixtures.dart';
import '../icons.dart';
import '../models/display_models.dart';
import '../theme.dart';
import '../widgets/harbor_widgets.dart';
import '../widgets/skeleton.dart';

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
  final Set<String> _silenced = <String>{};

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
      _currenciesOn.contains(event.currency) && _rank(event.impact) >= _rank(_minImpact);

  bool _isSilenced(String id) => _silenced.contains(id);

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

  /// The soonest USD HIGH event — the only combination that pauses new signals.
  ///
  /// Deliberately independent of the alert bells. The blackout window exists
  /// because gold tends to move around the release, not because the trader
  /// wants to be told about it. Skipping silenced events here is what made the
  /// top card appear to "swap" to another release when the bell was tapped.
  DisplayEvent? get _nextBlackout {
    for (final event in _visibleEvents) {
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
        // Licence attribution (D-20261006-020): Finance Calendar data is free
        // for any use on condition of a visible link. Shown on every tab since
        // all three panes read the same calendar - and only the calendar panes
        // use it, so the news digest carries no misplaced credit.
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Calendar data: Finance Calendar (financecalendar.com).',
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 9,
              color: harborFaint,
            ),
          ),
        ),
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
              const SizedBox(width: 60, child: HarborEyebrow('CCY', color: harborFaint)),
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
                        onTap: () => setState(() => _minImpact = option.floor),
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
    final silenced = visible.where((e) => _isSilenced(e.id)).length;
    final watching = visible.length - silenced;
    final next = _nextBlackout;
    final scope = switch (_minImpact) {
      EventImpact.high => 'HIGH ONLY',
      EventImpact.medium => 'HIGH+MED',
      EventImpact.low => 'ALL',
    };
    // "WATCHING" counts releases whose alerts are on. The blackout countdown is
    // reported independently, because silencing an alert does not disarm the
    // guard.
    final summary = StringBuffer('$scope · $watching WATCHING');
    if (silenced > 0) summary.write(' · $silenced SILENCED');
    summary.write(
      next == null ? ' · BLACKOUT —' : ' · BLACKOUT ${formatCountdown(next.startsIn)}',
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
              decoration: BoxDecoration(color: harborShort, shape: BoxShape.circle),
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
    final live = _live;

    // While a deliberate pull is in flight the REAL pane renders as bones. It is
    // not replaced by a placeholder subtree: swapping the two painted a
    // full-width grey rectangle for a frame as they exchanged, and it left the
    // top card (the blackout countdown) un-refreshed because it sat outside the
    // swapped region.
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _nextBlackoutCard(next),
        const SizedBox(height: 10),
        if (events.isEmpty)
          (_live?.loading ?? false)
              ? const SkeletonEventList()
              : const _SilenceNote('No events match these filters.')
        else
          for (final event in events) ...[
            _EventRow(
              event: event,
              // Alerts default ON. The previous flag defaulted to muted, which
              // made the list look disabled rather than watched.
              alertsEnabled: !_silenced.contains(event.id),
              onToggleAlerts: () => setState(() {
                if (!_silenced.add(event.id)) _silenced.remove(event.id);
              }),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );

    // The skeleton wrapper is added ONLY while a deliberate pull is in
    // progress, and is otherwise absent from the tree entirely.
    //
    // It used to be here unconditionally, driven by `loading:
    // live.refreshing`. That is wrong, and it is what produced the grey block
    // over the Events pane on Android. `Skeletonizer` is not an inert wrapper:
    // it installs its shimmer shader and painting context into the subtree even
    // when `enabled` is false. So on a real device - Impeller, release build -
    // a DISABLED Skeletonizer could still paint its subtree as one opaque quad.
    // It is intermittent and poll-correlated because that is when the subtree
    // is rebuilt, not because the loading flag is ever true: poll paths pass
    // manual:false and never set `refreshing`, which is provably false here.
    //
    // Building the subtree with no Skeletonizer in it removes the failure mode
    // by construction rather than by tuning a flag. Genuine first-load still
    // shows skeletons via [SkeletonEventList], whose primitives each own an
    // explicitly enabled Skeletonizer - the pattern the package documents.
    if (live?.refreshing ?? false) {
      return Skeletonize(loading: true, child: pane);
    }
    return pane;
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
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
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
              style: TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborDim),
            ),
          ],
        ],
      ),
    );
  }

  /// Past events: actual vs forecast with the surprise flag (addendum §3.3).
  Widget _resultsPane() {
    final events = _resultEvents;
    // The provider publishes no actuals in this feed (verified: week-old
    // releases still carry actual:null), so there is nothing to score. Say
    // that instead of a bare "nothing here", which reads as broken rather
    // than as a known upstream gap.
    if (events.isEmpty) {
      return const _SilenceNote(
        'No results yet.',
        detail: 'Released events in this feed carry no actuals, '
            'so there is nothing to score against forecast.',
      );
    }
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
          child: HarborEyebrow('Macro backdrop · display only', color: harborFaint),
        ),
        const SizedBox(height: 9),
        if (themes.isEmpty)
          const _SilenceNote(
            'No digest published yet.',
            detail: 'Themes are summarized here once licensed news articles '
                'arrive. None is feeding at zero cost - GNews free is '
                'non-commercial.',
          )
        else
          for (final theme in themes) ...[
            HarborCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          theme.theme,
                          style: const TextStyle(
                            fontFamily: 'Sora',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // What the theme stands on. A pressure label without a
                        // source count reads as a verdict; the count shows it
                        // is a summary of N articles, nothing more.
                        Text(
                          theme.evidenceCount == 1
                              ? '1 linked article'
                              : '${theme.evidenceCount} linked articles',
                          style: const TextStyle(
                            fontFamily: 'Space Mono',
                            fontSize: 9,
                            color: harborFaint,
                          ),
                        ),
                      ],
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
          const _SilenceNote(
            'No headlines collected.',
            detail: 'Headlines appear here with their source once a licensed '
                'news provider runs. None is active.',
          )
        else
          for (final headline in headlines) ...[
            _NewsCard(item: headline),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

/// One scheduled release.
///
/// Layout, top to bottom:
///   * impact colour bar down the leading edge — the fastest read on the list,
///     with the text badge as the redundant cue for anyone who cannot use
///     colour;
///   * title, with a country flag as a secondary cue beside the ISO code;
///   * the outlook: expected effect on gold, or an explicit "no prediction"
///     with the reason;
///   * the figures the calendar actually holds, with absent ones as `—`.
class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.alertsEnabled,
    required this.onToggleAlerts,
  });

  final DisplayEvent event;

  /// Whether the trader wants an alert for this release. On by default.
  final bool alertsEnabled;

  final VoidCallback onToggleAlerts;

  /// Leading colour for [impact]. Also the badge colour, so the two cues can
  /// never disagree.
  static Color impactColor(EventImpact impact) => switch (impact) {
    EventImpact.high => harborShort,
    EventImpact.medium => harborWarn,
    EventImpact.low => harborFaint,
  };

  @override
  Widget build(BuildContext context) {
    final color = impactColor(event.impact);
    return HarborCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Impact colour as a compact bar plus its text badge. Two redundant
          // cues, so impact is readable without relying on colour alone.
          Row(
            children: [
              Container(
                width: 4,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 7),
              HarborChip(impactLabel(event.impact), fontSize: 8),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _MetaLine(event: event, color: color),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AlertBell(
                enabled: alertsEnabled,
                title: event.title,
                onTap: onToggleAlerts,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _OutlookLine(outlook: event.outlook),
          const SizedBox(height: 10),
          _FigureRow(event: event),
        ],
      ),
    );
  }
}

/// Flag · currency code · countdown, on one line.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.event, required this.color});

  final DisplayEvent event;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final flag = event.flagEmoji;
    return Wrap(
      spacing: 7,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (flag != null)
          Text(flag, style: const TextStyle(fontSize: 13))
        else
          Text(
            '·',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        Text(
          event.currency,
          style: TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: color,
          ),
        ),
        HarborChip(impactLabel(event.impact), fontSize: 8),
        Text(
          event.isPast ? 'released' : 'in ${formatCountdown(event.startsIn)}',
          style: const TextStyle(
            fontFamily: 'Space Mono',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: harborDim,
          ),
        ),
      ],
    );
  }
}

/// The engine's expected effect on gold, or why it declined to say.
///
/// Deliberately never rendered as a probability: this is a tendency, and the
/// wording says so.
class _OutlookLine extends StatelessWidget {
  const _OutlookLine({required this.outlook});

  final EventOutlook? outlook;

  @override
  Widget build(BuildContext context) {
    final o = outlook;
    if (o == null) return const SizedBox.shrink();

    final (label, color) = switch (o.bias) {
      EventBias.bullish => ('BULLISH', harborLong),
      EventBias.bearish => ('BEARISH', harborShort),
      EventBias.neutral => ('NEUTRAL', harborDim),
      EventBias.none => ('NO PREDICTION', harborFaint),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: o.hasNoPrediction ? harborMist : color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Space Mono',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              o.hasNoPrediction && o.confoundedBy.isNotEmpty
                  ? 'Coincides with ${o.confoundedBy.join(', ')}'
                  : o.explanation,
              style: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 11,
                height: 1.3,
                color: harborDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Forecast / previous / actual, showing only what the calendar holds.
///
/// A released event shows its actual alongside the forecast it is measured
/// against; an upcoming one has no actual yet, and prints `—` rather than a
/// borrowed number.
class _FigureRow extends StatelessWidget {
  const _FigureRow({required this.event});

  final DisplayEvent event;

  @override
  Widget build(BuildContext context) {
    // Anything the calendar has not published is simply absent, and saying so
    // is the honest row. The calendar currently holds no figures at all, so
    // this explains itself rather than looking broken.
    final published =
        event.forecast != null || event.previous != null || event.actual != null;

    if (!published) {
      return const Text(
        'No forecast, previous or actual published for this release yet',
        style: TextStyle(
          fontFamily: 'Space Mono',
          fontSize: 9.5,
          height: 1.35,
          color: harborFaint,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _figure('ACTUAL', event.actual, emphasised: true),
        _figure('FORECAST', event.forecast),
        _figure('PREV', event.previous),
      ],
    );
  }

  static Widget _figure(String key, String? value, {bool emphasised = false}) {
    return Text(
      '$key ${value ?? '—'}',
      style: TextStyle(
        fontFamily: 'Space Mono',
        fontSize: 10,
        fontWeight: emphasised ? FontWeight.w700 : FontWeight.w400,
        color: value == null ? harborFaint : harborDim,
      ),
    );
  }
}

/// Per-event alert toggle.
///
/// The bell **enables** alerts. It starts armed, because a bell that begins
/// muted reads as "this event is disabled" — the opposite of what the icon
/// means. Turning it off silences the alert only; the row is never hidden or
/// dimmed, so silencing one release can never be mistaken for removing it.
class _AlertBell extends StatelessWidget {
  const _AlertBell({required this.enabled, required this.title, required this.onTap});

  final bool enabled;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      checked: enabled,
      label: enabled
          ? 'Alerts on for $title. Double tap to silence.'
          : 'Alerts off for $title. Double tap to turn on.',
      child: Tooltip(
        message: enabled ? 'Alerts on · tap to silence' : 'Alerts off · tap to enable',
        child: Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: enabled ? harborCobalt : harborLine),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    HarborIcons.bell,
                    size: 18,
                    color: enabled ? harborCobalt : harborFaint,
                  ),
                  // A slash is the visual language for "silenced", so the state
                  // does not depend on colour alone.
                  if (!enabled)
                    const Positioned.fill(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: harborShort,
                            shape: BoxShape.circle,
                          ),
                          child: SizedBox.shrink(),
                        ),
                      ),
                    ),
                ],
              ),
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
        onTap: () => ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Opens ${item.url}'))),
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
                  const Icon(HarborIcons.arrowUpRight, size: 12, color: harborCobalt),
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
  const _SilenceNote(this.message, {this.detail});

  final String message;

  /// Second line saying WHY there is nothing, so an empty tab reads as an
  /// explained state rather than a broken widget. Null when the message alone
  /// is self-explanatory.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Sora', fontSize: 12, color: harborFaint),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Space Mono',
                fontSize: 9,
                height: 1.5,
                color: harborFaint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
