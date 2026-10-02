/// Technical indicators (expert methodology §2).
///
/// Design rules that follow directly from the methodology:
///
///   * **Closed candles only.** Every function here expects a confirmed series;
///     callers pass `closedOnly(...)` output. Nothing here reads "the current
///     candle" because doing so is Failure 5 (§27).
///   * **Indicators confirm, they never initiate** (§0, MGC §7.4). These
///     functions therefore return neutral raw measurements, never a verdict.
///     Direction is decided by [ConfluenceEngine] with structure and context.
///   * **Insufficient data yields null, not a default.** A 200-period EMA with
///     30 bars must not silently return 0 — that would read as "flat" and
///     corrupt every downstream score (MGC R8: "unknown" is a valid answer).
///
/// Period defaults follow the ratified spec (`docs/expert-integration-spec.md`
/// §1a): EMA 20/50/200, RSI 14, MACD 12/26/9, ADX 14, ATR 14, BB 20/2.
library;

import 'dart:math' as math;

import '../models/candle.dart';

/// A windowed indicator output: index-aligned with the input series, `null`
/// where the indicator is not yet defined.
class IndicatorSeries {
  const IndicatorSeries(this.values);

  final List<double?> values;

  int get length => values.length;

  /// Latest value, or null when undefined.
  double? get last {
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] != null) return values[i];
    }
    return null;
  }

  /// Value at [index], null when undefined.
  double? operator [](int index) =>
      index >= 0 && index < values.length ? values[index] : null;

  bool get isEmpty => values.every((v) => v == null);
}

/// Closes of a candle series, ascending in time.
List<double> closes(List<Candle> bars) => [for (final b in bars) b.close];

/// Highs of a candle series, ascending in time.
List<double> highs(List<Candle> bars) => [for (final b in bars) b.high];

/// Lows of a candle series, ascending in time.
List<double> lows(List<Candle> bars) => [for (final b in bars) b.low];

/// Exponential moving average.
///
/// Seeded with an SMA of the first [period] values (standard Wilder-free EMA
/// convention). Returns null for every index before [period] - 1, so callers
/// cannot mistake an undefined EMA for a real one.
IndicatorSeries ema(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0 || values.length < period) return IndicatorSeries(out);

  var sum = 0.0;
  for (var i = 0; i < period; i++) {
    sum += values[i];
  }
  var prev = sum / period;
  out[period - 1] = prev;

  final k = 2.0 / (period + 1);
  for (var i = period; i < values.length; i++) {
    prev = (values[i] - prev) * k + prev;
    out[i] = prev;
  }
  return IndicatorSeries(out);
}

/// Wilder's RSI (14-period by default).
///
/// Deliberately *not* used as an overbought/oversold reversal trigger (§2.2):
/// it is read as a momentum regime, with 52–68 preferred and >75/<25 blocking a
/// fresh entry.
IndicatorSeries rsi(List<double> values, {int period = 14}) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0 || values.length <= period) return IndicatorSeries(out);

  var gainSum = 0.0;
  var lossSum = 0.0;
  for (var i = 1; i <= period; i++) {
    final d = values[i] - values[i - 1];
    if (d >= 0) {
      gainSum += d;
    } else {
      lossSum -= d;
    }
  }
  var gain = gainSum / period;
  var loss = lossSum / period;
  out[period] = _rsiValue(gain, loss);

  for (var i = period + 1; i < values.length; i++) {
    final d = values[i] - values[i - 1];
    gain = (gain * (period - 1) + (d > 0 ? d : 0)) / period;
    loss = (loss * (period - 1) + (d < 0 ? -d : 0)) / period;
    out[i] = _rsiValue(gain, loss);
  }
  return IndicatorSeries(out);
}

double _rsiValue(double gain, double loss) {
  if (loss == 0) return gain == 0 ? 50.0 : 100.0;
  final rs = gain / loss;
  return 100.0 - (100.0 / (1.0 + rs));
}

/// MACD line, signal line and histogram (12/26/9).
class MacdResult {
  const MacdResult({required this.macd, required this.signal, required this.histogram});

  final IndicatorSeries macd;
  final IndicatorSeries signal;
  final IndicatorSeries histogram;
}

/// Moving Average Convergence/Divergence.
MacdResult macd(List<double> values, {int fast = 12, int slow = 26, int signalPeriod = 9}) {
  final ef = ema(values, fast);
  final es = ema(values, slow);
  final len = values.length;
  final line = List<double?>.filled(len, null);

  for (var i = 0; i < len; i++) {
    final f = ef[i];
    final s = es[i];
    if (f != null && s != null) line[i] = f - s;
  }

  // The signal EMA must run over defined MACD values only; feeding it a null-
  // padded series would shift it by the fast-EMA warm-up offset.
  final defined = <double>[];
  final indexOf = <int>[];
  for (var i = 0; i < len; i++) {
    final v = line[i];
    if (v != null) {
      defined.add(v);
      indexOf.add(i);
    }
  }

  final sig = List<double?>.filled(len, null);
  final hist = List<double?>.filled(len, null);
  if (defined.length >= signalPeriod) {
    final sigSeries = ema(defined, signalPeriod);
    for (var i = 0; i < indexOf.length; i++) {
      final v = sigSeries[i];
      if (v != null) {
        sig[indexOf[i]] = v;
        hist[indexOf[i]] = defined[i] - v;
      }
    }
  }
  return MacdResult(
    macd: IndicatorSeries(line),
    signal: IndicatorSeries(sig),
    histogram: IndicatorSeries(hist),
  );
}

/// Average True Range (Wilder, 14-period).
IndicatorSeries atr(List<Candle> bars, {int period = 14}) {
  final out = List<double?>.filled(bars.length, null);
  if (bars.length < period + 1) return IndicatorSeries(out);

  final trs = <double>[];
  for (var i = 1; i < bars.length; i++) {
    trs.add(trueRange(bars[i - 1], bars[i]));
  }
  if (trs.length < period) return IndicatorSeries(out);

  var sum = 0.0;
  for (var i = 0; i < period; i++) {
    sum += trs[i];
  }
  var prev = sum / period;
  out[period] = prev;

  for (var i = period + 1; i < bars.length; i++) {
    prev = (prev * (period - 1) + trs[i - 1]) / period;
    out[i] = prev;
  }
  return IndicatorSeries(out);
}

/// True range for a bar given its predecessor.
double trueRange(Candle prev, Candle cur) {
  final hl = cur.high - cur.low;
  final hc = (cur.high - prev.close).abs();
  final lc = (cur.low - prev.close).abs();
  return [hl, hc, lc].reduce((a, b) => a > b ? a : b);
}

/// Average Directional Index with +DI / -DI.
class AdxResult {
  const AdxResult({required this.adx, required this.plusDi, required this.minusDi});

  final IndicatorSeries adx;
  final IndicatorSeries plusDi;
  final IndicatorSeries minusDi;
}

/// ADX(14) + directional indicators.
///
/// Only meaningful when ADX is high enough to imply a trend; a flat ADX must
/// not be read as a directional vote.
AdxResult adx(List<Candle> bars, {int period = 14}) {
  final len = bars.length;
  final adxOut = List<double?>.filled(len, null);
  final plusOut = List<double?>.filled(len, null);
  final minusOut = List<double?>.filled(len, null);
  if (len < period * 2 + 1) {
    return AdxResult(
      adx: IndicatorSeries(adxOut),
      plusDi: IndicatorSeries(plusOut),
      minusDi: IndicatorSeries(minusOut),
    );
  }

  final plusDm = <double>[];
  final minusDm = <double>[];
  final trs = <double>[];
  for (var i = 1; i < len; i++) {
    final up = bars[i].high - bars[i - 1].high;
    final down = bars[i - 1].low - bars[i].low;
    plusDm.add(up > down && up > 0 ? up : 0.0);
    minusDm.add(down > up && down > 0 ? down : 0.0);
    trs.add(trueRange(bars[i - 1], bars[i]));
  }

  double smoothSum(List<double> src, int n) {
    var s = 0.0;
    for (var i = 0; i < n; i++) {
      s += src[i];
    }
    return s;
  }

  var tr = smoothSum(trs, period);
  var pdm = smoothSum(plusDm, period);
  var mdm = smoothSum(minusDm, period);

  final dx = <double>[];
  final dxIndex = <int>[];
  double di(double d, double t) => t == 0 ? 0.0 : (d / t) * 100.0;

  plusOut[period] = di(pdm, tr);
  minusOut[period] = di(mdm, tr);
  final firstDx = _dx(pdm, tr, mdm);
  dx.add(firstDx);
  dxIndex.add(period);

  for (var i = period; i < trs.length; i++) {
    tr = tr - (tr / period) + trs[i];
    pdm = pdm - (pdm / period) + plusDm[i];
    mdm = mdm - (mdm / period) + minusDm[i];
    final idx = i + 1;
    plusOut[idx] = di(pdm, tr);
    minusOut[idx] = di(mdm, tr);
    final d = _dx(pdm, tr, mdm);
    dx.add(d);
    dxIndex.add(idx);
  }

  if (dx.length >= period) {
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += dx[i];
    }
    var prev = sum / period;
    adxOut[dxIndex[period - 1]] = prev;
    for (var i = period; i < dx.length; i++) {
      prev = (prev * (period - 1) + dx[i]) / period;
      adxOut[dxIndex[i]] = prev;
    }
  }

  return AdxResult(
    adx: IndicatorSeries(adxOut),
    plusDi: IndicatorSeries(plusOut),
    minusDi: IndicatorSeries(minusOut),
  );
}

double _dx(double pdm, double tr, double mdm) {
  if (tr == 0) return 0.0;
  final p = (pdm / tr) * 100.0;
  final m = (mdm / tr) * 100.0;
  final sum = p + m;
  if (sum == 0) return 0.0;
  return ((p - m).abs() / sum) * 100.0;
}

/// Bollinger Bands (20, 2) with the bandwidth used for squeeze detection.
class BollingerResult {
  const BollingerResult({
    required this.upper,
    required this.middle,
    required this.lower,
    required this.bandwidth,
  });

  final IndicatorSeries upper;
  final IndicatorSeries middle;
  final IndicatorSeries lower;

  /// (upper - lower) / middle, as a fraction. Falls as volatility compresses,
  /// which is the squeeze condition the methodology looks for.
  final IndicatorSeries bandwidth;
}

BollingerResult bollinger(List<double> values, {int period = 20, double mult = 2.0}) {
  final mid = ema(values, period);
  final len = values.length;
  final up = List<double?>.filled(len, null);
  final lo = List<double?>.filled(len, null);
  final bw = List<double?>.filled(len, null);

  for (var i = 0; i < len; i++) {
    final m = mid[i];
    if (m == null || i < period - 1) continue;
    final sd = _stdDev(values, i, period, m);
    up[i] = m + mult * sd;
    lo[i] = m - mult * sd;
    bw[i] = m == 0 ? null : ((mult * 2 * sd) / m);
  }

  return BollingerResult(
    upper: IndicatorSeries(up),
    middle: mid,
    lower: IndicatorSeries(lo),
    bandwidth: IndicatorSeries(bw),
  );
}

/// Population standard deviation of the trailing [period] values ending at
/// [endIndex], around their own mean.
double _stdDev(List<double> values, int endIndex, int period, double mean) {
  var sumSq = 0.0;
  for (var j = endIndex - period + 1; j <= endIndex; j++) {
    final d = values[j] - mean;
    sumSq += d * d;
  }
  final variance = sumSq / period;
  return variance <= 0 ? 0.0 : math.sqrt(variance);
}

/// A confirmed swing point.
class Swing {
  const Swing({required this.index, required this.price, required this.isHigh});

  final int index;
  final double price;
  final bool isHigh;

  @override
  String toString() => 'Swing($index, $price, ${isHigh ? 'high' : 'low'})';
}

/// Fractal swing highs/lows with [lookback] bars on each side.
///
/// A swing at index `i` needs `i - lookback` and `i + lookback` bars, so the
/// last `lookback` bars can never produce a confirmed swing. That lag is
/// intentional — it is the same closed-candle discipline as rule 9.
List<Swing> swings(List<Candle> bars, {int lookback = 2}) {
  if (lookback < 1 || bars.length < lookback * 2 + 1) return const [];
  final out = <Swing>[];
  for (var i = lookback; i < bars.length - lookback; i++) {
    var isHigh = true;
    var isLow = true;
    for (var j = i - lookback; j <= i + lookback; j++) {
      if (j == i) continue;
      if (bars[j].high >= bars[i].high) isHigh = false;
      if (bars[j].low <= bars[i].low) isLow = false;
    }
    if (isHigh) out.add(Swing(index: i, price: bars[i].high, isHigh: true));
    if (isLow) out.add(Swing(index: i, price: bars[i].low, isHigh: false));
  }
  out.sort((a, b) => a.index.compareTo(b.index));
  return out;
}

/// Most recent swing low at or before [upToIndex]; null when none is confirmed.
Swing? lastSwingLow(List<Swing> all, int upToIndex) {
  for (var i = all.length - 1; i >= 0; i--) {
    final s = all[i];
    if (!s.isHigh && s.index <= upToIndex) return s;
  }
  return null;
}

/// Most recent swing high at or before [upToIndex]; null when none is confirmed.
Swing? lastSwingHigh(List<Swing> all, int upToIndex) {
  for (var i = all.length - 1; i >= 0; i--) {
    final s = all[i];
    if (s.isHigh && s.index <= upToIndex) return s;
  }
  return null;
}

/// Percentile rank (0–100) of the latest ATR within its own recent history.
///
/// Feeds the volatility regime and the extreme-volatility veto (§2.5, V4):
/// a percentile is robust to the fact that gold's absolute ATR changes with
/// the macro regime, whereas a fixed ratio does not.
double? atrPercentile(List<double> atrHistory, {int lookback = 100}) {
  final vals = atrHistory.where((v) => v.isFinite && v > 0).toList();
  if (vals.length < 20) return null;
  final window = vals.length > lookback ? vals.sublist(vals.length - lookback) : vals;
  final latest = window.last;
  var below = 0;
  for (final v in window) {
    if (v <= latest) below++;
  }
  return (below / window.length) * 100.0;
}

/// Price distance expressed in USD, never in broker-dependent "pips".
///
/// XAUUSD pip conventions vary between venues, so the methodology mandates
/// absolute USD distance. Gold at 4000.00 has a $0.01 tick, which makes pips
/// meaningless as a shared unit.
double usdDistance(double a, double b) => (a - b).abs();