/// Market-context card for the Signal screen (mockup 13R).
///
/// Read-only regime display: summary two-panel card plus per-layer tiles with
/// gauges, timeframe pills, and a slow-sentiment section. Regime words only —
/// bullish/bearish/ranging/neutral — LONG/SHORT belong to consensus verdicts.
/// Everything derives from [AnalysisService.regime] (real bars) and
/// [AppState] indicator settings (toggles + params). Customization is display
/// only: it never reaches consensus math, the guard, or validation.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xau_core/xau_core.dart'
    show RegimeLean, RegimeReading, RegimeState, StructureState, Tf;

import '../data/analysis_service.dart';
import '../models/regime_display.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'harbor_widgets.dart';

/// Timeframe pill order on the card. 15M is the primary intraday read.
const _tfs = [Tf.m5, Tf.m15, Tf.h1];

String _tfLabel(Tf tf) => switch (tf) {
      Tf.m5 => '5M',
      Tf.m15 => '15M',
      Tf.m30 => '30M',
      Tf.h1 => '1H',
    };

/// Section owning the timeframe selection. Syncs indicator settings into the
/// service (recompute + notify only when params actually changed).
class RegimeSection extends StatefulWidget {
  const RegimeSection({super.key});

  @override
  State<RegimeSection> createState() => _RegimeSectionState();
}

class _RegimeSectionState extends State<RegimeSection> {
  Tf _tf = Tf.m15;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = context.read<AnalysisService?>();
    final state = context.read<AppState>();
    service?.setRegimeParams(state.toRegimeParams());
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AnalysisService?>();
    final state = context.watch<AppState>();
    final reading = service?.regime[_tf];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const HarborEyebrow('Market context · never votes', color: harborShort),
        const SizedBox(height: 8),
        _TimeframeBar(
          active: _tf,
          onChanged: (tf) => setState(() => _tf = tf),
        ),
        const SizedBox(height: 10),
        if (reading == null)
          const _PendingCard(text: 'Waiting for bars — regime appears after the first scan.')
        else ...[
          _SummaryCard(reading: reading, tf: _tf),
          const SizedBox(height: 10),
          _Tiles(reading: reading, tf: _tf, state: state),
          const SizedBox(height: 10),
          if (state.indSentiment) const _SentimentPendingCard(),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            'Computed from live bars. Context annotates the chart. It never votes, never confirms, never flips a setup.',
            style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim, height: 1.55),
          ),
        ),
      ],
    );
  }
}

class _TimeframeBar extends StatelessWidget {
  const _TimeframeBar({required this.active, required this.onChanged});

  final Tf active;
  final ValueChanged<Tf> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          for (final tf in _tfs)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(tf),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: tf == active ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: tf == active
                        ? [const BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tfLabel(tf),
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tf == active ? harborInk : harborDim,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Big bold agreement card: two-panel gradient language. The side panel
/// carries the glyph + percentage; the main panel the state, the count and
/// the note. Fixed content budget — no height animation between timeframes.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.reading, required this.tf});

  final RegimeReading reading;
  final Tf tf;

  @override
  Widget build(BuildContext context) {
    final s = reading.summary;
    final bull = s.state == RegimeState.bullish;
    final bear = s.state == RegimeState.bearish;
    final side = bull
        ? const _SideGradient.bull()
        : bear
            ? const _SideGradient.bear()
            : const _SideGradient.mixed();
    final glyph = bull ? '▲' : bear ? '▼' : '●';
    final pct = '${(s.fraction * 100).round()}%';
    return Container(
      // Fixed height, per the approved mockup: switching timeframes must
      // never move the content below. (It also keeps the stretched side
      // panel legal inside scrolling lists, where the height is unbounded.)
      height: 216,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x38152126), blurRadius: 28, offset: Offset(0, 10))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 96,
            decoration: BoxDecoration(gradient: side.gradient),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(glyph, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
                const SizedBox(height: 6),
                Text(pct, style: const TextStyle(fontFamily: 'Space Mono', fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: harborInk,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TfTag(label: _tfLabel(tf)),
                  const SizedBox(height: 8),
                  Text(
                    regimeStateWord(s.state),
                    style: const TextStyle(fontFamily: 'Sora', fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Colors.white, height: 1.05),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    regimeFractionText(s),
                    style: const TextStyle(fontFamily: 'Space Mono', fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _summaryNote(reading),
                    style: const TextStyle(fontFamily: 'Space Mono', fontSize: 10, color: Color(0xFFA9B6CB), height: 1.55),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'A read of the dashboard, not a setup. Trades come from independent-source consensus only.',
                    style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: Color(0xFF7C8AA0), height: 1.55),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _summaryNote(RegimeReading r) {
    final bullAreas = <String>[];
    final bearAreas = <String>[];
    void area(RegimeLean lean, String name) {
      if (lean == RegimeLean.bullish) {
        bullAreas.add(name);
      } else if (lean == RegimeLean.bearish) {
        bearAreas.add(name);
      }
    }

    area(r.directionLean, 'direction');
    final momBull = r.rsiLean == RegimeLean.bullish || r.macdLean == RegimeLean.bullish;
    final momBear = r.rsiLean == RegimeLean.bearish || r.macdLean == RegimeLean.bearish;
    if (momBull && !momBear) bullAreas.add('momentum');
    if (momBear && !momBull) bearAreas.add('momentum');
    if (momBull && momBear) {
      bullAreas.add('momentum');
      bearAreas.add('momentum');
    }
    area(r.vwapLean, 'intraday');
    final weak = (r.adx ?? double.infinity) < 20;
    return regimeNote(
      summary: r.summary,
      bullAreas: bullAreas,
      bearAreas: bearAreas,
      strongTrend: r.summary.strongTrend,
      weakTrend: weak,
    );
  }
}

class _SideGradient {
  const _SideGradient.bull()
      : gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12B981), Color(0xFF0B6E4F)],
        );
  const _SideGradient.bear()
      : gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE05252), Color(0xFF8E2B2B)],
        );
  const _SideGradient.mixed()
      : gradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8FA0B8), Color(0xFF4A586E)],
        );

  final Gradient gradient;
}

class _TfTag extends StatelessWidget {
  const _TfTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xFFE8EEFB), borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: const TextStyle(fontFamily: 'Space Mono', fontSize: 8, fontWeight: FontWeight.w700, color: harborCobalt),
      ),
    );
  }
}

/// Layer tiles in mockup order. Hidden layers vanish entirely (toggle off);
/// null readings render as pending, never as zero.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.reading, required this.tf, required this.state});

  final RegimeReading reading;
  final Tf tf;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final tag = _tfLabel(tf);
    final tiles = <Widget>[];
    if (state.indDirection) {
      tiles.add(_DirectionTile(reading: r, paramsLabel: state));
    }
    if (state.indAdx) tiles.add(_AdxTile(reading: r, state: state));
    if (state.indRsi) tiles.add(_RsiTile(reading: r, state: state));
    if (state.indMacd) tiles.add(_MacdTile(reading: r));
    if (state.indVwap) {
      tiles.add(_VwapTile(reading: r));
      tiles.add(_ActivityTile(reading: r));
    }
    if (state.indAtr) tiles.add(_AtrTile(reading: r));
    if (tiles.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'Layers', tag: tag),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.42,
          children: tiles,
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.tag});

  final String title;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        if (tag != null) ...[
          const SizedBox(width: 8),
          _TfTag(label: tag!),
        ],
      ],
    );
  }
}

String _pillFor(RegimeLean lean) => leanWord(lean.name);

class _TileShell extends StatelessWidget {
  const _TileShell({required this.name, required this.params, required this.body, required this.pill});

  final String name;
  final String params;
  final Widget body;
  final Widget pill;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))),
              pill,
            ],
          ),
          const SizedBox(height: 2),
          Text(params, style: const TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborFaint)),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        text,
        style: TextStyle(fontFamily: 'Space Mono', fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: fg),
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({
    required this.needle,
    this.fillFrom,
    this.fillTo,
    this.fillColor = harborDim,
    this.marks = const [],
    this.labels,
  });

  /// Needle position 0–1. Null hides the needle (pending).
  final double? needle;
  final double? fillFrom;
  final double? fillTo;
  final Color fillColor;
  final List<double> marks;
  final List<String>? labels;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 14,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              double px(double f) => f.clamp(0.0, 1.0) * w;
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 4,
                    child: Container(
                        height: 6,
                        decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(99))),
                  ),
                  if (fillFrom != null && fillTo != null)
                    Positioned(
                      left: px(fillFrom! < fillTo! ? fillFrom! : fillTo!),
                      width: (px(fillTo!) - px(fillFrom!)).abs(),
                      top: 4,
                      height: 6,
                      child: Container(
                        decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                  for (final m in marks)
                    Positioned(
                      left: px(m) - 1,
                      top: 1,
                      child: Container(
                          width: 2,
                          height: 12,
                          decoration: BoxDecoration(color: harborFaint, borderRadius: BorderRadius.circular(2))),
                    ),
                  if (needle != null)
                    Positioned(
                      left: px(needle!) - 2,
                      top: 0,
                      child: Container(
                        width: 4,
                        height: 14,
                        decoration: BoxDecoration(color: harborInk, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (labels != null) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final l in labels!)
                Text(l, style: const TextStyle(fontFamily: 'Space Mono', fontSize: 8, color: harborFaint)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Pending tile: the bars cannot support this reading yet. A dash, never a
/// zero — zero would read as a measured flat.
class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.name, required this.params});

  final String name;
  final String params;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      name: name,
      params: params,
      pill: const _StatePill(text: 'WAITING', bg: chipBg, fg: harborDim),
      body: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('—',
              style: TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text('Waiting for bars.',
              style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim)),
        ],
      ),
    );
  }
}

class _DirectionTile extends StatelessWidget {
  const _DirectionTile({required this.reading, required this.paramsLabel});

  final RegimeReading reading;
  final AppState paramsLabel;

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final c = r.close;
    if (c == null || r.emaFast == null || r.emaMid == null) {
      return _PendingTile(
          name: 'EMA stack + structure',
          params:
              'EMA ${paramsLabel.emaFast} / ${paramsLabel.emaMid} / ${paramsLabel.emaTrend} · swings ${paramsLabel.swings}');
    }
    final parts = <String>['Price'];
    var prev = c;
    final levels = <({double v, String n})>[
      (v: r.emaFast!, n: '${paramsLabel.emaFast}'),
      (v: r.emaMid!, n: '${paramsLabel.emaMid}'),
      if (r.emaTrend != null) (v: r.emaTrend!, n: '${paramsLabel.emaTrend}'),
    ];
    var ok = true;
    for (final l in levels) {
      if (prev == l.v) {
        ok = false;
        break;
      }
      parts.add(prev > l.v ? '>' : '<');
      parts.add(l.n);
      prev = l.v;
    }
    final stack = ok ? parts.join(' ') : '—';
    final lean = r.directionLean;
    return _TileShell(
      name: 'EMA stack + structure',
      params:
          'EMA ${paramsLabel.emaFast} / ${paramsLabel.emaMid} / ${paramsLabel.emaTrend} · swings ${paramsLabel.swings}',
      pill: _StatePill(
        text: _structWord(r),
        bg: lean == RegimeLean.bullish
            ? const Color(0xFFDFF5EA)
            : lean == RegimeLean.bearish
                ? const Color(0xFFFBE3E3)
                : chipBg,
        fg: lean == RegimeLean.bullish
            ? harborLong
            : lean == RegimeLean.bearish
                ? harborShort
                : harborDim,
      ),
      body: Text('$stack · ${r.structureDetail}',
          style: const TextStyle(fontFamily: 'Space Mono', fontSize: 10.5, height: 1.5)),
    );
  }

  String _structWord(RegimeReading r) {
    if (r.directionLean != RegimeLean.neutral) return _pillFor(r.directionLean);
    return switch (r.structure) {
      StructureState.bullish => 'BULLISH',
      StructureState.bearish => 'BEARISH',
      StructureState.ranging => 'RANGING',
      StructureState.unknown => 'NEUTRAL',
    };
  }
}

class _AdxTile extends StatelessWidget {
  const _AdxTile({required this.reading, required this.state});

  final RegimeReading reading;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final adx = reading.adx;
    final strong = state.adxStrong;
    if (adx == null) {
      return _PendingTile(name: 'ADX', params: '${state.adxPeriod} · strong ≥ ${strong.toStringAsFixed(0)}');
    }
    final label = adx >= strong ? 'STRONG' : adx >= 20 ? 'FIRM' : 'WEAK';
    final colors = adx >= strong
        ? [const Color(0xFFDFF5EA), harborLong]
        : adx >= 20
            ? [const Color(0xFFE8EEFB), harborCobalt]
            : [chipBg, harborDim];
    return _TileShell(
      name: 'ADX',
      params: '${state.adxPeriod} · strong ≥ ${strong.toStringAsFixed(0)}',
      pill: _StatePill(text: label, bg: colors[0], fg: colors[1]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(adx.toStringAsFixed(1),
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          _Gauge(
            needle: adx / 50,
            marks: [20 / 50, strong / 50],
            labels: const ['0', '20 weak', '25', '50'],
          ),
          const SizedBox(height: 6),
          const Text('Strength only — direction comes from above.',
              style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim)),
        ],
      ),
    );
  }
}

class _RsiTile extends StatelessWidget {
  const _RsiTile({required this.reading, required this.state});

  final RegimeReading reading;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final rsi = reading.rsi;
    if (rsi == null) {
      return _PendingTile(
          name: 'RSI',
          params:
              '${state.rsiPeriod} · OB ${state.rsiOb.toStringAsFixed(0)} / OS ${state.rsiOs.toStringAsFixed(0)}');
    }
    final ob = state.rsiOb;
    final os = state.rsiOs;
    final label = rsi >= ob ? 'OVERBOUGHT' : rsi <= os ? 'OVERSOLD' : 'NEUTRAL';
    final colors = rsi >= ob
        ? [const Color(0xFFFBF3DF), harborWarn]
        : rsi <= os
            ? [const Color(0xFFE8EEFB), harborCobalt]
            : [chipBg, harborDim];
    return _TileShell(
      name: 'RSI',
      params: '${state.rsiPeriod} · OB ${ob.toStringAsFixed(0)} / OS ${os.toStringAsFixed(0)}',
      pill: _StatePill(text: label, bg: colors[0], fg: colors[1]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rsi.toStringAsFixed(1),
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          _Gauge(
            needle: rsi / 100,
            fillFrom: os / 100,
            fillTo: ob / 100,
            fillColor: const Color(0xFFC7D0DD),
            marks: [os / 100, ob / 100],
            labels: ['0', os.toStringAsFixed(0), '50', ob.toStringAsFixed(0), '100'],
          ),
        ],
      ),
    );
  }
}

class _MacdTile extends StatelessWidget {
  const _MacdTile({required this.reading});

  final RegimeReading reading;

  @override
  Widget build(BuildContext context) {
    final hist = reading.macdHist;
    if (hist == null) {
      return const _PendingTile(name: 'MACD', params: '12 · 26 · 9');
    }
    final label = hist > 0 ? 'BUILDING' : hist < 0 ? 'FADING' : 'NEUTRAL';
    final colors = hist > 0
        ? [const Color(0xFFDFF5EA), harborLong]
        : hist < 0
            ? [const Color(0xFFFBE3E3), harborShort]
            : [chipBg, harborDim];
    final rawScale = (reading.atr ?? 1.0) * 2.0;
    final scale = rawScale < 0.5 ? 0.5 : rawScale;
    final pos = 0.5 + (hist / scale).clamp(-1.0, 1.0) * 0.48;
    final sign = hist > 0 ? '+' : '';
    return _TileShell(
      name: 'MACD',
      params: '12 · 26 · 9',
      pill: _StatePill(text: label, bg: colors[0], fg: colors[1]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$sign${hist.toStringAsFixed(2)}',
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          _Gauge(
            needle: pos,
            fillFrom: hist > 0 ? 0.5 : pos,
            fillTo: hist > 0 ? pos : 0.5,
            fillColor: hist >= 0 ? harborLong : harborShort,
            marks: const [0.5],
            labels: const ['−histo', '0', '+histo'],
          ),
        ],
      ),
    );
  }
}

class _VwapTile extends StatelessWidget {
  const _VwapTile({required this.reading});

  final RegimeReading reading;

  @override
  Widget build(BuildContext context) {
    final v = reading.vwap;
    final c = reading.close;
    if (v == null || c == null || v == 0) {
      return const _PendingTile(name: 'VWAP', params: 'session · RTH');
    }
    final pct = (c - v) / v * 100;
    final above = c > v;
    return _TileShell(
      name: 'VWAP',
      params: reading.volumeBacked ? 'session · volume' : 'session avg · no volume',
      pill: _StatePill(
        text: above ? 'ABOVE' : 'BELOW',
        bg: above ? const Color(0xFFDFF5EA) : const Color(0xFFFBE3E3),
        fg: above ? harborLong : harborShort,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${above ? '+' : ''}${pct.toStringAsFixed(2)}%',
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Price vs session fair value.',
              style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim)),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.reading});

  final RegimeReading reading;

  @override
  Widget build(BuildContext context) {
    final a = reading.activityRatio;
    if (a == null) {
      return const _PendingTile(name: 'Activity', params: 'rel. 20-bar · tick counts');
    }
    final label = a >= 1.3 ? 'ELEVATED' : a < 0.7 ? 'QUIET' : 'NORMAL';
    final colors = a >= 1.3
        ? [const Color(0xFFE8EEFB), harborCobalt]
        : [chipBg, harborDim];
    return _TileShell(
      name: 'Activity',
      params: 'rel. 20-bar · tick counts',
      pill: _StatePill(text: label, bg: colors[0], fg: colors[1]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${a.toStringAsFixed(1)}×',
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Tick activity, not traded volume.',
              style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim)),
        ],
      ),
    );
  }
}

class _AtrTile extends StatelessWidget {
  const _AtrTile({required this.reading});

  final RegimeReading reading;

  @override
  Widget build(BuildContext context) {
    final atr = reading.atr;
    if (atr == null) {
      return const _PendingTile(name: 'ATR', params: '14');
    }
    return _TileShell(
      name: 'ATR',
      params: '14',
      pill: const _StatePill(text: 'RANGE INFO', bg: Color(0xFFE8EEFB), fg: harborCobalt),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(atr.toStringAsFixed(2),
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Typical excursion — sizes stops, never direction.',
              style: TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim)),
        ],
      ),
    );
  }
}

/// Slow sentiment until Phase 2 feeds land (COT weekly job + FRED key).
/// The layout matches the mockup; the values honestly wait.
class _SentimentPendingCard extends StatelessWidget {
  const _SentimentPendingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(title: 'Slow sentiment', tag: 'W1 / D1'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.9,
          children: const [
            _SentimentMini(title: 'COT positioning', note: 'Weekly job pending'),
            _SentimentMini(title: 'DXY pressure', note: 'Feed pending'),
            _SentimentMini(title: '10Y real yield', note: 'FRED key pending'),
            _SentimentMini(title: 'VIX regime', note: 'FRED key pending'),
          ],
        ),
      ],
    );
  }
}

class _SentimentMini extends StatelessWidget {
  const _SentimentMini({required this.title, required this.note});

  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(note,
              style: const TextStyle(fontFamily: 'Space Mono', fontSize: 9, color: harborDim)),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: harborLine),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(text,
          style: const TextStyle(fontFamily: 'Space Mono', fontSize: 10, color: harborDim)),
    );
  }
}
