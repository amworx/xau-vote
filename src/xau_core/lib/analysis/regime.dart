/// Market-regime readings for the Signal screen's context card.
///
/// What this is: a read-only classification of what the market is doing —
/// direction, strength, momentum, intraday position, volatility — computed
/// from closed bars. What it is NOT: a vote, a score, or a direction for
/// trading. The consensus engine decides setups from independent sources;
/// this module never emits LONG/SHORT, never a 0–100 confidence, and never
/// feeds the consensus math.
///
/// Conventions (all honest-by-construction):
/// * Closed bars in, ascending in time. Insufficient data yields null, never
///   a default that could read as a measurement.
/// * RSI lean bands (bullish ≥ 65, bearish ≤ 35) are deliberately narrower
///   than the classic 70/30 reversal lines: a lean is a tilt, not a trigger.
/// * ADX measures strength only, never direction.
/// * Volume honesty: spot XAUUSD has no true traded volume. VWAP and activity
///   use bar volume when the venue provides it and say so (`volumeBacked`);
///   without volume they fall back to equal weights / report null rather
///   than presenting tick counts as participation.
library;

import '../models/candle.dart';
import 'indicators.dart';
import 'session.dart';

/// Tunable inputs. Defaults match the approved mockup (13R).
class RegimeParams {
  const RegimeParams({
    this.emaFast = 20,
    this.emaMid = 50,
    this.emaTrend = 200,
    this.swingLookback = 5,
    this.adxPeriod = 14,
    this.adxStrong = 25,
    this.rsiPeriod = 14,
    this.rsiBull = 65,
    this.rsiBear = 35,
    this.macdFast = 12,
    this.macdSlow = 26,
    this.macdSignal = 9,
    this.atrPeriod = 14,
    this.activityLookback = 20,
  });

  final int emaFast;
  final int emaMid;
  final int emaTrend;
  final int swingLookback;
  final int adxPeriod;
  final double adxStrong;
  final int rsiPeriod;
  final double rsiBull;
  final double rsiBear;
  final int macdFast;
  final int macdSlow;
  final int macdSignal;
  final int atrPeriod;
  final int activityLookback;

  @override
  bool operator ==(Object other) =>
      other is RegimeParams &&
      other.emaFast == emaFast &&
      other.emaMid == emaMid &&
      other.emaTrend == emaTrend &&
      other.swingLookback == swingLookback &&
      other.adxPeriod == adxPeriod &&
      other.adxStrong == adxStrong &&
      other.rsiPeriod == rsiPeriod &&
      other.rsiBull == rsiBull &&
      other.rsiBear == rsiBear &&
      other.macdFast == macdFast &&
      other.macdSlow == macdSlow &&
      other.macdSignal == macdSignal &&
      other.atrPeriod == atrPeriod &&
      other.activityLookback == activityLookback;

  @override
  int get hashCode => Object.hash(
        emaFast, emaMid, emaTrend, swingLookback, adxPeriod, adxStrong,
        rsiPeriod, rsiBull, rsiBear, macdFast, macdSlow, macdSignal,
        atrPeriod, activityLookback,
      );
}

/// A directional tilt. Neutral is a real answer, not a missing one.
enum RegimeLean { bullish, bearish, neutral }

/// Market-structure state from confirmed swings.
enum StructureState { bullish, bearish, ranging, unknown }

/// Agreement outcome across the four directional reads.
enum RegimeState { bullish, bearish, mixed }

/// Agreement across directional reads. Three or more of four in one camp
/// decides; anything else is mixed — including 2-1 with a neutral, which is
/// a split, not a lean. Pure so the rule table is tested, not eyeballed.
RegimeSummary summarizeLeans({
  required int bull,
  required int bear,
  int total = 4,
  required bool strongTrend,
}) {
  final state = bull >= 3
      ? RegimeState.bullish
      : bear >= 3
          ? RegimeState.bearish
          : RegimeState.mixed;
  return RegimeSummary(
    state: state,
    bull: bull,
    bear: bear,
    total: total,
    strongTrend: strongTrend,
  );
}

/// What the summary card shows. Counts, not a score: `fraction` is the share
/// of voting reads in the largest camp (e.g. 3 of 4 = 0.75), never a
/// probability of anything.
class RegimeSummary {
  const RegimeSummary({
    required this.state,
    required this.bull,
    required this.bear,
    required this.total,
    required this.strongTrend,
  });

  final RegimeState state;
  final int bull;
  final int bear;
  final int total;

  /// Share of voting reads in the largest camp, 0–1.
  double get fraction {
    if (total <= 0) return 0;
    final top = bull > bear ? bull : bear;
    return top / total;
  }

  /// Whether the trend-strength read supports follow-through.
  final bool strongTrend;
}

/// One timeframe's full regime reading. Every nullable field is null when
/// the bars cannot support it — the UI renders pending, never zero.
class RegimeReading {
  const RegimeReading({
    required this.close,
    required this.emaFast,
    required this.emaMid,
    required this.emaTrend,
    required this.structure,
    required this.structureDetail,
    required this.adx,
    required this.rsi,
    required this.macdHist,
    required this.vwap,
    required this.volumeBacked,
    required this.activityRatio,
    required this.atr,
    required this.directionLean,
    required this.rsiLean,
    required this.macdLean,
    required this.vwapLean,
    required this.summary,
  });

  final double? close;
  final double? emaFast;
  final double? emaMid;
  final double? emaTrend;
  final StructureState structure;
  final String structureDetail;
  final double? adx;
  final double? rsi;
  final double? macdHist;
  final double? vwap;

  /// True when real bar volume backed the VWAP. False means equal weights —
  /// a session average, not a volume-weighted one.
  final bool volumeBacked;

  /// Recent mean volume over the prior mean. Null without volume data.
  final double? activityRatio;
  final double? atr;

  final RegimeLean directionLean;
  final RegimeLean rsiLean;
  final RegimeLean macdLean;
  final RegimeLean vwapLean;
  final RegimeSummary summary;
}

/// Session volume-weighted average price over bars at/after [sessionStart].
/// Falls back to equal weights when no bar carries volume, and says so via
/// [VwapResult.volumeBacked]. Null when no bars qualify.
class VwapResult {
  const VwapResult({required this.value, required this.volumeBacked});

  final double value;
  final bool volumeBacked;
}

VwapResult? vwap(List<Candle> bars, {required DateTime sessionStart}) {
  var pvSum = 0.0;
  var volSum = 0.0;
  var eqSum = 0.0;
  var n = 0;
  var backed = false;
  for (final b in bars) {
    if (b.openTime.isBefore(sessionStart)) continue;
    final typical = (b.high + b.low + b.close) / 3.0;
    final v = b.volume;
    if (v != null && v > 0) {
      backed = true;
      pvSum += typical * v;
      volSum += v;
    }
    eqSum += typical;
    n++;
  }
  if (n == 0) return null;
  if (backed && volSum > 0) return VwapResult(value: pvSum / volSum, volumeBacked: true);
  return VwapResult(value: eqSum / n, volumeBacked: false);
}

/// Recent mean bar volume over the prior mean (both windows [lookback]
/// bars). Null unless both windows are fully volume-backed — a ratio built
/// on partial volume would read as participation that was never measured.
double? activityRatio(List<Candle> bars, {int lookback = 20}) {
  if (lookback < 1 || bars.length < lookback * 2) return null;
  var recent = 0.0;
  var prior = 0.0;
  for (var i = 0; i < lookback; i++) {
    final r = bars[bars.length - 1 - i].volume;
    final p = bars[bars.length - 1 - lookback - i].volume;
    if (r == null || r <= 0 || p == null || p <= 0) return null;
    recent += r;
    prior += p;
  }
  if (prior <= 0) return null;
  return (recent / lookback) / (prior / lookback);
}

/// Structure state from the last two swing highs and lows.
({StructureState state, String detail}) structureState(List<Swing> swings) {
  Swing? h1;
  Swing? h2;
  Swing? l1;
  Swing? l2;
  for (final s in swings) {
    if (s.isHigh) {
      h1 = h2;
      h2 = s;
    } else {
      l1 = l2;
      l2 = s;
    }
  }
  if (h1 == null || h2 == null || l1 == null || l2 == null) {
    return (state: StructureState.unknown, detail: '—');
  }
  final hh = h2.price > h1.price;
  final hl = l2.price > l1.price;
  final lh = h2.price < h1.price;
  final ll = l2.price < l1.price;
  if (hh && hl) return (state: StructureState.bullish, detail: 'HH / HL');
  if (lh && ll) return (state: StructureState.bearish, detail: 'LH / LL');
  return (state: StructureState.ranging, detail: 'mixed');
}

/// Full regime read for one timeframe's closed bars.
RegimeReading computeRegime(
  List<Candle> bars, {
  RegimeParams params = const RegimeParams(),
  required DateTime sessionStart,
}) {
  final cs = closes(bars);
  final last = cs.isEmpty ? null : cs.last;

  double? emaLast(IndicatorSeries s) => s.values.isEmpty ? null : s.values.last;

  final eFast = ema(cs, params.emaFast);
  final eMid = ema(cs, params.emaMid);
  final eTrend = ema(cs, params.emaTrend);
  final f = emaLast(eFast);
  final m = emaLast(eMid);
  final t = emaLast(eTrend);

  // Rising check needs a few defined values; absent history means no claim.
  bool rising(IndicatorSeries s) {
    final v = s.values.whereType<double>().toList();
    if (v.length < 4) return false;
    return v.last > v[v.length - 4];
  }

  final sw = swingsFromBars(bars, lookback: params.swingLookback);
  final st = structureState(sw);

  RegimeLean directionLean;
  if (last == null || f == null || m == null) {
    directionLean = RegimeLean.neutral;
  } else {
    final up = last > f && f > m && (t == null || m > t) && rising(eFast);
    final down = last < f && f < m && (t == null || m < t) && !rising(eFast) && _falling(eFast);
    final structUp = st.state == StructureState.bullish;
    final structDown = st.state == StructureState.bearish;
    if (up && structUp) {
      directionLean = RegimeLean.bullish;
    } else if (down && structDown) {
      directionLean = RegimeLean.bearish;
    } else {
      directionLean = RegimeLean.neutral;
    }
  }

  final rsiSeries = rsi(cs, period: params.rsiPeriod);
  final rsiLast = emaLast(rsiSeries);
  final rsiLean = rsiLast == null
      ? RegimeLean.neutral
      : rsiLast >= params.rsiBull
          ? RegimeLean.bullish
          : rsiLast <= params.rsiBear
              ? RegimeLean.bearish
              : RegimeLean.neutral;

  final macdRes = macd(cs,
      fast: params.macdFast, slow: params.macdSlow, signalPeriod: params.macdSignal);
  final histLast =
      macdRes.histogram.values.isEmpty ? null : macdRes.histogram.values.last;
  final macdLean = histLast == null
      ? RegimeLean.neutral
      : histLast > 0
          ? RegimeLean.bullish
          : histLast < 0
              ? RegimeLean.bearish
              : RegimeLean.neutral;

  final v = vwap(bars, sessionStart: sessionStart);
  final vwapLean = (v == null || last == null)
      ? RegimeLean.neutral
      : last > v.value
          ? RegimeLean.bullish
          : last < v.value
              ? RegimeLean.bearish
              : RegimeLean.neutral;

  final adxRes = adx(bars, period: params.adxPeriod);
  final adxLast = adxRes.adx.values.isEmpty ? null : adxRes.adx.values.last;

  final atrSeries = atr(bars, period: params.atrPeriod);
  final atrLast = atrSeries.values.isEmpty ? null : atrSeries.values.last;

  final votes = [directionLean, rsiLean, macdLean, vwapLean];
  var bull = 0;
  var bear = 0;
  for (final x in votes) {
    if (x == RegimeLean.bullish) bull++;
    if (x == RegimeLean.bearish) bear++;
  }
  final summary = summarizeLeans(
    bull: bull,
    bear: bear,
    total: votes.length,
    strongTrend: adxLast != null && adxLast >= params.adxStrong,
  );

  return RegimeReading(
    close: last,    emaFast: f,
    emaMid: m,
    emaTrend: t,
    structure: st.state,
    structureDetail: st.detail,
    adx: adxLast,
    rsi: rsiLast,
    macdHist: histLast,
    vwap: v?.value,
    volumeBacked: v?.volumeBacked ?? false,
    activityRatio: activityRatio(bars, lookback: params.activityLookback),
    atr: atrLast,
    directionLean: directionLean,
    rsiLean: rsiLean,
    macdLean: macdLean,
    vwapLean: vwapLean,
    summary: summary,
  );
}

bool _falling(IndicatorSeries s) {
  final v = s.values.whereType<double>().toList();
  if (v.length < 4) return false;
  return v.last < v[v.length - 4];
}

/// Fractal swings helper kept next to its only consumer (regime structure).
List<Swing> swingsFromBars(List<Candle> bars, {int lookback = 5}) =>
    swings(bars, lookback: lookback);
