/// MOCK_MODE fixtures replicating the Dart mock pipeline outputs.
///
/// Values mirror the approved Harbor mockups:
/// STRONG LONG 4/5, entry 4275–4280, SL 4262, TP1 4295 / TP2 4315 /
/// TP3 4340, agreement 82/100, price 4,278.30 — plus the NO CONSENSUS
/// divided state (spec §3) and developing/invalidated/expired/TP-hit
/// states for the History screen.
library;

import '../models/display_models.dart';

/// All mock fixtures served while [mockMode] is true.
abstract final class MockFixtures {
  /// Strong-consensus active setup (Radar + Signal default).
  static const DisplaySignal strongLong = DisplaySignal(
    id: '#A482',
    direction: Direction.long,
    strength: 82,
    entryLow: 4275,
    entryHigh: 4280,
    stopLoss: 4262,
    tp1: 4295,
    tp2: 4315,
    tp3: 4340,
    status: DisplayStatus.active,
    agreeCount: 4,
    totalCount: 5,
    dayLow: 4266.90,
    dayHigh: 4286.40,
  );

  /// Divided vote counts for the NO CONSENSUS state (spec §3).
  static const Map<Direction, int> dividedVotes = {
    Direction.long: 2,
    Direction.short: 2,
    Direction.neutral: 1,
  };

  /// Developing (not yet confirmed) variant for state previews.
  static const DisplaySignal developing = DisplaySignal(
    id: '#A483',
    direction: Direction.long,
    strength: 52,
    entryLow: 4275,
    entryHigh: 4280,
    stopLoss: 4262,
    tp1: 4295,
    tp2: 4315,
    tp3: 4340,
    status: DisplayStatus.developing,
    agreeCount: 3,
    totalCount: 5,
  );

  /// Per-source cards behind the consensus (spec §17).
  static const List<DisplaySource> sources = [
    DisplaySource(
      id: 'A',
      name: 'DESK A · GoldPulse',
      direction: Direction.long,
      agrees: true,
      entryText: '4,275-4,280',
      stopText: '4,262 · −1600p',
      targetsText: '4,295 / 4,315',
      freshnessText: '6m AGO',
      reasoning: 'Bounce off the 4275 shelf; momentum turning up on the 15M.',
      sourceUrl: 'https://example.com/sources/goldpulse/a482',
      tp1HitRate: 78,
      tp2HitRate: 54,
      tp3HitRate: 31,
    ),
    DisplaySource(
      id: 'B',
      name: 'DESK B · AurumNotes',
      direction: Direction.long,
      agrees: true,
      entryText: '4,276-4,281',
      stopText: '4,264 · −1500p',
      targetsText: '4,298 / 4,320',
      freshnessText: '11m AGO',
      reasoning: 'Higher low printed; entry on retest of broken intraday high.',
      sourceUrl: 'https://example.com/sources/aurumnotes/a482',
      tp1HitRate: 71,
      tp2HitRate: 48,
      tp3HitRate: 29,
    ),
    DisplaySource(
      id: 'C',
      name: 'DESK C · BullionDesk',
      direction: Direction.long,
      agrees: true,
      entryText: '4,274-4,279',
      stopText: '4,263 · −1600p',
      targetsText: '4,296 / 4,318',
      freshnessText: '14m AGO',
      reasoning: 'Cluster of bids 4274-80; invalidation clean below 4263.',
      sourceUrl: 'https://example.com/sources/bulliondesk/a482',
      tp1HitRate: 82,
      tp2HitRate: 57,
      tp3HitRate: 33,
    ),
    DisplaySource(
      id: 'E',
      name: 'DESK E · MetalWire',
      direction: Direction.long,
      agrees: true,
      entryText: '4,275-4,282',
      stopText: '4,261 · −1800p',
      targetsText: '4,294 / 4,316',
      freshnessText: '19m AGO',
      reasoning: 'Asia low holding; long dips toward the zone.',
      sourceUrl: 'https://example.com/sources/metalwire/a482',
      tp1HitRate: 64,
      tp2HitRate: 41,
      tp3HitRate: 22,
    ),
    DisplaySource(
      id: 'D',
      name: 'DESK D · BearBullion',
      direction: Direction.short,
      agrees: false,
      entryText: '4,285',
      stopText: '4,300',
      targetsText: '4,260',
      freshnessText: '22m AGO',
      reasoning: 'Excluded from cluster — entry 5+ pts outside the zone.',
      sourceUrl: 'https://example.com/sources/bearbullion/a482',
      tp1HitRate: 58,
      tp2HitRate: 36,
      tp3HitRate: 20,
    ),
  ];

  /// Past signals, newest first, covering every terminal state.
  static const List<DisplayHistoryEntry> history = [
    DisplayHistoryEntry(
      direction: Direction.long,
      whenText: 'TODAY · 14:20',
      detailText: 'IN 4,102-07 · SL 4,088 · TP2 4,138 · STRONG 84',
      status: DisplayStatus.tp2Hit,
      pipsText: '+3100 PIPS',
    ),
    DisplayHistoryEntry(
      direction: Direction.short,
      whenText: 'TODAY · 09:05',
      detailText: 'IN 4,150-55 · SL 4,168 · OUT 4,170 · MODERATE 66',
      status: DisplayStatus.invalidated,
      pipsText: '-1500 PIPS',
    ),
    DisplayHistoryEntry(
      direction: Direction.long,
      whenText: 'YESTERDAY · 16:40',
      detailText: 'IN 4,090-95 · SL 4,078 · TP1 4,112 · STRONG 81',
      status: DisplayStatus.tp1Hit,
      pipsText: '+1700 PIPS',
    ),
    DisplayHistoryEntry(
      direction: null,
      whenText: 'YESTERDAY · 11:15',
      detailText: '2 LONG · 2 SHORT · 1 NEUTRAL — divided, correctly held',
      status: null,
      pipsText: '0 PIPS',
    ),
    DisplayHistoryEntry(
      direction: Direction.long,
      whenText: '2 DAYS AGO · 10:30',
      detailText: 'IN 4,060-65 · expired before confirmation',
      status: DisplayStatus.expired,
      pipsText: '0 PIPS',
    ),
    DisplayHistoryEntry(
      direction: Direction.short,
      whenText: '3 DAYS AGO · 13:10',
      detailText: 'IN 4,210-15 · SL 4,228 · TP3 4,150 · VERY STRONG 91',
      status: DisplayStatus.tp3Hit,
      pipsText: '+6200 PIPS',
    ),
    DisplayHistoryEntry(
      direction: Direction.long,
      whenText: '3 DAYS AGO · 08:45',
      detailText: 'IN 4,180-85 · tracking cancelled at READY',
      status: DisplayStatus.developing,
      pipsText: '0 PIPS',
    ),
  ];

  // -------------------------------------------------------------------------
  // TASK-07 — events & news fixtures (MOCK_MODE). Rule 9: context only.
  // -------------------------------------------------------------------------

  /// Upcoming HIGH/MEDIUM events, chronological (addendum §5.2).
  static const List<DisplayEvent> upcomingEvents = [
    DisplayEvent(
      id: 'evt-nfp',
      title: 'NFP — Non-Farm Payrolls',
      currency: 'USD',
      impact: EventImpact.high,
      startsIn: Duration(minutes: 12, seconds: 41),
      forecast: '180K',
      previous: '175K',
    ),
    DisplayEvent(
      id: 'evt-retail',
      title: 'Retail Sales m/m',
      currency: 'USD',
      impact: EventImpact.medium,
      startsIn: Duration(minutes: 42),
      forecast: '0.3%',
      previous: '0.1%',
    ),
    DisplayEvent(
      id: 'evt-ecb',
      title: 'ECB Rate Decision',
      currency: 'EUR',
      impact: EventImpact.high,
      startsIn: Duration(hours: 2, minutes: 15),
      forecast: '2.00%',
      previous: '2.15%',
    ),
    DisplayEvent(
      id: 'evt-fomc',
      title: 'FOMC Decision',
      currency: 'USD',
      impact: EventImpact.high,
      startsIn: Duration(days: 6, hours: 3),
      forecast: null,
      previous: '4.50%',
    ),
  ];

  /// Past events with actuals vs forecast + surprise flags (addendum §3.3).
  static const List<DisplayEvent> resultEvents = [
    DisplayEvent(
      id: 'res-cpi',
      title: 'CPI y/y',
      currency: 'USD',
      impact: EventImpact.high,
      startsIn: Duration(minutes: -130),
      forecast: '3.1%',
      previous: '3.0%',
      actual: '3.4%',
      surprise: 'hot',
    ),
    DisplayEvent(
      id: 'res-nfp',
      title: 'NFP — Non-Farm Payrolls',
      currency: 'USD',
      impact: EventImpact.high,
      startsIn: Duration(days: -3),
      forecast: '180K',
      previous: '175K',
      actual: '185K',
      surprise: 'inline',
    ),
    DisplayEvent(
      id: 'res-ppi',
      title: 'PPI m/m',
      currency: 'USD',
      impact: EventImpact.medium,
      startsIn: Duration(days: -5),
      forecast: '0.3%',
      previous: '0.2%',
      actual: '0.0%',
      surprise: 'cold',
    ),
  ];

  /// Latest digest themes → the Radar "Macro backdrop" strip (addendum §3.2).
  static const List<DisplayDigestTheme> digestThemes = [
    DisplayDigestTheme(
      theme: 'Hawkish Fed repricing',
      pressure: NewsPressure.hawkish,
      evidenceCount: 3,
    ),
    DisplayDigestTheme(
      theme: 'Dovish ECB tilt',
      pressure: NewsPressure.dovish,
      evidenceCount: 2,
    ),
    DisplayDigestTheme(
      theme: 'Neutral Asia flows',
      pressure: NewsPressure.neutral,
      evidenceCount: 2,
    ),
  ];

  /// Latest collected headlines (title + source + age + link only).
  static const List<DisplayNewsItem> headlines = [
    DisplayNewsItem(
      source: 'Manual Desk',
      title: 'Gold holds range ahead of US payrolls data',
      ageText: '12m AGO',
      url: 'https://example.com/news/gold-range-seed',
    ),
    DisplayNewsItem(
      source: 'Manual Desk',
      title: 'Fed officials reiterate data-dependent stance',
      ageText: '44m AGO',
      url: 'https://example.com/news/fed-stance-seed',
    ),
    DisplayNewsItem(
      source: 'Manual Desk',
      title: 'Dollar index steady as traders await CPI surprise fallout',
      ageText: '1h AGO',
      url: 'https://example.com/news/dollar-steady-seed',
    ),
  ];
}
