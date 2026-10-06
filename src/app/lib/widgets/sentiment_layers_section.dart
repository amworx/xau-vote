import 'package:flutter/material.dart';

import '../models/sentiment_layers.dart';
import '../theme.dart';
import 'harbor_widgets.dart';

/// How an overlay relates to a side.
///
/// `neutral` and `unweighed` are deliberately distinct states: a measured zero
/// opinion is not the absence of one.
enum _Kind { supports, conflict, neutral, unweighed }

/// The §5.1 sentiment layers, as approved in the browser prototype.
///
/// Two facts are shown separately on purpose:
///
///  * a layer's OWN lean — `SentimentLayerRow.alignment` — as the badge
///  * whether that lean agreed with the candidate trade — `macroAgrees` /
///    `sentimentAgrees` — in the strip underneath
///
/// Merging them into one number would be the easy option and a lie: with the
/// Fed hiking and a short on the table, the same bearish macro reading is a
/// credit, and on a long it is a veto.
///
/// A layer that could not be measured reads `NOT MEASURED`, never `NEUTRAL`.
/// Silence is not neutrality, and the two are visually distinct so they cannot
/// be read as the same thing.
class SentimentLayersSection extends StatelessWidget {
const SentimentLayersSection({
    super.key,
    required this.layers,
    required this.macroAlignment,
    required this.sentimentAlignment,
    required this.hasDirection,
    required this.isLong,
  });

  final SentimentLayers layers;

  /// The macro layer's OWN lean, or null when unmeasured.
  ///
  /// Deliberately the raw alignment, not the engine's `macroAgrees`. The
  /// agreement value is already relative to the traded side, so feeding it in
  /// here and then flipping it again per row inverted both rows whenever there
  /// was no candidate direction to orient against. Deriving both rows from the
  /// raw reading makes each row independently correct and lets the active side
  /// be highlighted rather than baked into the arithmetic.
  final int? macroAlignment;

  /// The sentiment layer's own lean, same convention.
  final int? sentimentAlignment;

  /// False when the scan produced no candidate direction at all.
  final bool hasDirection;

  final bool isLong;

  static const _order = ['policy', 'positioning', 'market_implied', 'gold_fundamentals'];

  @override
  Widget build(BuildContext context) {
    final rows = <SentimentLayerRow?>[
      for (final key in _order) layers[key],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: HarborEyebrow('SENTIMENT LAYERS'),
            ),
            Text(
              'MACRO COVERAGE ${(layers.macroCoverage * 100).round()}%',
              style: const TextStyle(
                fontFamily: 'SpaceMono',
                fontSize: 9.5,
                color: harborDim,
                backgroundColor: Color(0xFFF5F7FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final row in rows)
          if (row == null)
            _MissingLayer(name: 'UNBUILT LAYER', weight: null)
          else
_LayerRow(row: row),
const HarborDivider(),
        _AgreementStrip(
          macroAlignment: macroAlignment,
          sentimentAlignment: sentimentAlignment,
          hasDirection: hasDirection,
          isLong: isLong,
        ),
        const SizedBox(height: 8),
        Text(
          'Agreement is not a probability and not a vote count. Layers filter '
          'confidence only — sentiment never forbids a trade.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: harborFaint,
                fontSize: 9.5,
                height: 1.4,
              ),
        ),
      ],
    );
  }
}

/// One layer: name, weight, its own lean, and the reading behind it.
class _LayerRow extends StatelessWidget {
  const _LayerRow({required this.row});

  final SentimentLayerRow row;

  @override
  Widget build(BuildContext context) {
    final stale = row.isStale;
    final unmeasured = row.isUnmeasured;
    // A stale reading is not shown as a direction: it exists but cannot act.
    final label = unmeasured
        ? 'NOT MEASURED'
        : stale
            ? 'STALE'
            : switch (row.alignment) {
                -1 => 'BEARISH',
                1 => 'BULLISH',
                _ => 'NEUTRAL',
              };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 9),
decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFEDF0F4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '${row.layer.toUpperCase().replaceAll('_', '-')}  '
                  '${row.weight.round()}%',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .3,
                    color: harborInk,
                  ),
                ),
              ),
              _Badge(label: label, bearish: row.alignment == -1, muted: unmeasured || stale),
            ],
          ),
          const SizedBox(height: 4),
          if (_headline(row) != null)
            Text(
              _headline(row)!,
              style: const TextStyle(fontSize: 11, height: 1.4, color: harborInk),
            ),
          if (_meta(row) != null) ...[
            const SizedBox(height: 3),
            Text(
              _meta(row)!,
              style: const TextStyle(
                fontFamily: 'SpaceMono',
                fontSize: 9.5,
                height: 1.5,
                color: harborDim,
              ),
            ),
          ],
          if (_caveat(row) != null) ...[
            const SizedBox(height: 3),
            Text(
              _caveat(row)!,
              style: const TextStyle(fontSize: 9.5, height: 1.4, color: harborWarn),
            ),
          ],
        ],
      ),
    );
  }

  /// The headline sentence: the measured fact, in plain words.
  String? _headline(SentimentLayerRow r) {
    final d = r.detail;
    switch (r.layer) {
      case 'policy':
        final action = d['action'];
        final lo = d['target_low_pct'];
        final hi = d['target_high_pct'];
        if (action == null || lo == null || hi == null) return null;
        final verb = switch (action) {
          'raise' => 'raised',
          'lower' => 'cut',
          'maintain' => 'held',
          _ => null,
        };
        if (verb == null) return null;
        return 'Fed $verb the target range to ${_pct(lo)}–${_pct(hi)}';
      case 'positioning':
        final net = d['managed_net_contracts'];
        if (net == null) return null;
        return 'Managed money net ${_signed(num.tryParse('$net'))} contracts';
      case 'market_implied':
        final y = d['real10y'];
        if (y == null) return null;
        return '10-year real yield ${_pct(y)}';
      case 'gold_fundamentals':
        return 'World Gold Council demand data — not ingested';
      default:
        return null;
    }
  }

  String? _meta(SentimentLayerRow r) {
    final d = r.detail;
    final bits = <String>[];
    switch (r.layer) {
      case 'policy':
        final asOf = d['as_of'] ?? _date(d['measured_at']);
        if (asOf != null) bits.add('$asOf');
        final raw = d['raw_score'];
        final eff = d['effective_score'];
        final days = d['decay_days'];
        if (raw != null && eff != null) {
          bits.add('raw $raw → $eff');
          if (days != null) bits.add('after ${days}d decay');
        }
        final dissents = d['dissents'];
        bits.add(dissents is List && dissents.isNotEmpty
            ? '${dissents.length} dissent${dissents.length == 1 ? '' : 's'}'
            : 'no dissents');
      case 'positioning':
        final pctile = d['percentile_156w'];
        final weeks = d['sample_weeks'];
        final oi = d['managed_net_percent_of_oi'];
        final asOf = d['as_of'];
        if (pctile != null) {
          bits.add('${_pctile(pctile)} pctile');
          if (weeks != null) bits.add('of $weeks weeks');
        }
        if (oi != null) bits.add('${_pct(_ratio(oi))} of open interest');
        if (asOf != null) bits.add('$asOf');
      case 'market_implied':
        final bp = d['change5d_bp'];
        final asOf = d['as_of'];
        if (bp != null) bits.add('${_signed(num.tryParse('$bp'))}bp over 5 sessions');
        if (asOf != null) bits.add('$asOf');
      case 'gold_fundamentals':
        return null;
    }
    return bits.isEmpty ? null : bits.join(' · ');
  }

  /// A layer that is partly missing must say which part, so it cannot be read
  /// as complete.
  String? _caveat(SentimentLayerRow r) {
    final d = r.detail;
    final missing = d['legs_missing'];
    if (missing is List && missing.isNotEmpty) {
      return '${_list(missing)} of this layer are missing';
    }
    if (d['sep_projection'] == null && r.layer == 'policy') {
      return 'SEP projections not read (PDF only) — the path is unmeasured';
    }
    if (r.isStale && r.measuredAt != null) {
      return 'Past its window — ignored rather than read as current';
    }
    return null;
  }
}

/// A layer that has no row at all, which is different from a row with no score.
class _MissingLayer extends StatelessWidget {
  const _MissingLayer({required this.name, this.weight});

  final String name;
  final num? weight;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFEDF0F4))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                weight == null ? '$name  —' : '$name  ${weight!.round()}%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: harborFaint,
                ),
              ),
            ),
            const _Badge(label: 'NOT MEASURED', muted: true),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.bearish = false, this.muted = false});

  final String label;
  final bool bearish;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final BoxBorder border;
    if (muted) {
      bg = Colors.transparent;
      fg = harborFaint;
      border = Border.all(color: harborLine);
    } else if (bearish) {
      bg = harborShortSoft;
      fg = const Color(0xFFB23A3A);
      border = Border.all(color: const Color(0xFFF2C2C2));
    } else {
      bg = harborLongSoft;
      fg = const Color(0xFF0A7A56);
      border = Border.all(color: const Color(0xFFB7E5CE));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        border: border,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'SpaceMono',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: .7,
          color: fg,
        ),
      ),
    );
  }
}

/// Whether each overlay would agree with a long and with a short.
///
/// Both rows are always shown and each is computed independently from the raw
/// reading, so neither depends on which side happens to be live. The live side
/// is only highlighted.
class _AgreementStrip extends StatelessWidget {
  const _AgreementStrip({
    required this.macroAlignment,
    required this.sentimentAlignment,
    required this.hasDirection,
    required this.isLong,
  });

  final int? macroAlignment;
  final int? sentimentAlignment;
  final bool hasDirection;
  final bool isLong;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFCFD7FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('LONG', _flip(macroAlignment, 1), _flip(sentimentAlignment, 1),
              active: hasDirection && isLong),
          const SizedBox(height: 5),
          _row('SHORT', _flip(macroAlignment, -1), _flip(sentimentAlignment, -1),
              active: hasDirection && !isLong),
        ],
      ),
    );
  }

  static int? _flip(int? raw, int sign) => raw == null ? null : raw * sign;

  Widget _row(String label, int? macro, int? sentiment, {required bool active}) {
    // Macro decides the verdict tag; sentiment only adds a confidence note, so
    // when macro is absent a supporting sentiment still reads as support.
    final effective = macro ?? sentiment;
final (tag, kind) = switch (effective) {
      null => ('NOT WEIGHED', _Kind.unweighed),
      > 0 => ('SUPPORTS', _Kind.supports),
      0 => ('NEUTRAL', _Kind.neutral),
      _ => ('CONFLICT', _Kind.conflict),
    };

final detail = _detail(macro, sentiment);

    return Container(
      // A hair of extra weight marks the side actually on the table, so the
      // reader does not have to infer it from the verdict line above.
      padding: const EdgeInsets.symmetric(vertical: 1),
      foregroundDecoration: active
          ? const BoxDecoration(
              border: Border(
                left: BorderSide(color: Color(0xFFCFD7FF), width: 2),
              ),
            )
          : null,
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            'vs $label',
            style: const TextStyle(
              fontFamily: 'SpaceMono',
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: harborInk,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: switch (kind) {
              _Kind.supports => harborLongSoft,
              _Kind.conflict => harborShortSoft,
              _ => Colors.transparent,
            },
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: switch (kind) {
                _Kind.supports => const Color(0xFFB7E5CE),
                _Kind.conflict => const Color(0xFFF2C2C2),
                _ => harborLine,
              },
            ),
          ),
          child: Text(
            tag,
            style: TextStyle(
              fontFamily: 'SpaceMono',
              fontSize: 9,
              letterSpacing: .5,
              color: switch (kind) {
                _Kind.supports => const Color(0xFF0A7A56),
                _Kind.conflict => const Color(0xFFB23A3A),
                _ => harborFaint,
              },
            ),
          ),
        ),
const SizedBox(width: 7),
        Expanded(
          child: Text(
            detail,
            style: const TextStyle(fontSize: 10, height: 1.35, color: harborDim),
          ),
        ),
      ],
      ),
    );
  }

  String _detail(int? macro, int? sentiment) {
    if (macro == null && sentiment == null) {
      return 'below the coverage gate — no veto, no credit';
    }
    final parts = <String>[];
    if (macro != null) {
      parts.add(macro == 0
          ? 'macro neutral'
          : macro > 0
              ? 'macro credits'
              : 'macro opposes — would veto');
    } else {
      parts.add('macro not weighed');
    }
    if (sentiment != null) {
      parts.add(sentiment > 0 ? 'positioning credits' : 'positioning penalty');
    } else {
      parts.add('positioning not weighed');
    }
    return parts.join(' · ');
  }
}

String _date(Object? v) {
  if (v == null) return '';
  final s = v.toString();
  return s.length >= 10 ? s.substring(0, 10) : s;
}

String _pct(Object? v) {
  final d = num.tryParse('$v');
  if (d == null) return '$v';
  return d == d.roundToDouble() ? '${d.round()}%' : '${d.toStringAsFixed(2)}%';
}

/// open-interest share arrives as a ratio, not a percentage.
String _ratio(num v) => _pct(v * 100);

String _signed(num? v) {
  if (v == null) return '$v';
  final s = v == v.roundToDouble() ? v.round().toString() : v.toString();
  return v > 0 ? '+$s' : s;
}

String _pctile(Object? v) {
  final d = num.tryParse('$v');
  if (d == null) return '$v';
  return d == d.roundToDouble() ? d.round().toString() : d.toStringAsFixed(1);
}

String _list(List<Object?> items) => items.map((e) => '$e').join(' and ');