// Emits indicator values for a fixed synthetic series so an independent
// implementation can verify them. This is a verification tool, not app code.
//
// Run from src/xau_core:  dart run tool/dump_indicators.dart > /tmp/dump.json

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:xau_core/xau_core.dart';

/// Deterministic synthetic series: long enough for EMA200 and ADX to converge,
/// with a trend plus oscillation so trend and range behaviour both appear.
List<double> synth(int n) {
  final out = <double>[];
  var price = 4000.0;
  for (var i = 0; i < n; i++) {
    final wave = 25.0 * math.sin(i / 7.0) + 9.0 * math.sin(i / 2.3);
    final drift = i * 0.12;
    price = 4000.0 + wave + drift + ((i * 37) % 11) * 0.21 - 1.1;
    out.add(price);
  }
  return out;
}

List<Candle> barsFrom(List<double> closes) {
  return [
    for (var i = 0; i < closes.length; i++)
      Candle(
        openTime: DateTime.utc(2026, 1, 1).add(Duration(minutes: 5 * i)),
        open: closes[i] - 0.35,
        high: closes[i] + 0.9,
        low: closes[i] - 0.9,
        close: closes[i],
        volume: 100 + (i % 17).toDouble(),
      ),
  ];
}

List<double?> tail(IndicatorSeries s, int n) =>
    [for (var i = s.length - n; i < s.length; i++) s[i]];

void main(List<String> args) async {
  final closes = synth(600);
  final bars = barsFrom(closes);

  final e20 = ema(closes, 20);
  final e50 = ema(closes, 50);
  final e200 = ema(closes, 200);
  final r = rsi(closes, period: 14);
  final m = macd(closes);
  final a = atr(bars, period: 14);
  final dx = adx(bars, period: 14);
  final bb = bollinger(closes);

  // ATR percentile needs a series of ATR values.
  final List<double> atrVals = <double>[
    for (var i = 0; i < a.length; i++)
      if (a[i] != null) a[i]!,
  ];

  final payload = <String, Object?>{
    'closes': closes,
    'ema20': tail(e20, 5),
    'ema50': tail(e50, 5),
    'ema200': tail(e200, 5),
    'rsi14': tail(r, 5),
    'macd': tail(m.macd, 5),
    'macdSignal': tail(m.signal, 5),
    'macdHistogram': tail(m.histogram, 5),
    'atr14': tail(a, 5),
    'adx14': tail(dx.adx, 5),
    'plusDi': tail(dx.plusDi, 5),
    'minusDi': tail(dx.minusDi, 5),
    'bbUpper': tail(bb.upper, 5),
    'bbMiddle': tail(bb.middle, 5),
    'bbLower': tail(bb.lower, 5),
    'atrPercentile': atrPercentile(atrVals),
    'swings': [
      for (final s in swings(bars, lookback: 2))
        {'index': s.index, 'price': s.price, 'isHigh': s.isHigh},
    ],
  };

  // Written directly rather than via shell redirection: PowerShell's `>`
  // emits UTF-16 with a BOM, which json.load rejects.
  final path = args.isEmpty ? 'tool_dump.json' : args.first;
  await File(path).writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    encoding: utf8,
    flush: true,
  );
  stderr.writeln('wrote $path');
}