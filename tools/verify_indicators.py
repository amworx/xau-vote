"""Independent reference implementation of the indicators, used to verify the
Dart engine in src/xau_core/lib/analysis/indicators.dart.

Why this exists
---------------
The Dart tests verify internal consistency (identities, invariants, obvious
maths). They cannot catch a *convention* mismatch -- e.g. seeding an EMA with an
SMA versus the first value, or using Wilder smoothing where simple smoothing
is standard. This script reimplements each indicator from the published
definitions using only the Python standard library and compares the tails.

No third-party package is used, so no install/approval is required.

Usage
-----
    cd src/xau_core
    dart run tool/dump_indicators.dart > tool_dump.json
    python ../../tools/verify_indicators.py tool_dump.json
"""

from __future__ import annotations

import json
import math
import sys

TOL = 1e-6  # relative tolerance for float comparisons


# ---------------------------------------------------------------- EMA
def ema_ref(values: list[float], period: int) -> list[float | None]:
    """Exponential MA seeded with the SMA of the first `period` values."""
    out: list[float | None] = [None] * len(values)
    if len(values) < period:
        return out
    prev = sum(values[:period]) / period
    out[period - 1] = prev
    k = 2.0 / (period + 1.0)
    for i in range(period, len(values)):
        prev = (values[i] - prev) * k + prev
        out[i] = prev
    return out


# ---------------------------------------------------------------- RSI
def rsi_ref(values: list[float], period: int = 14) -> list[float | None]:
    """Wilder's RSI."""
    out: list[float | None] = [None] * len(values)
    if len(values) <= period:
        return out
    gains = losses = 0.0
    for i in range(1, period + 1):
        d = values[i] - values[i - 1]
        if d >= 0:
            gains += d
        else:
            losses -= d
    gain = gains / period
    loss = losses / period
    out[period] = _rsi(gain, loss)
    for i in range(period + 1, len(values)):
        d = values[i] - values[i - 1]
        gain = (gain * (period - 1) + (d if d > 0 else 0.0)) / period
        loss = (loss * (period - 1) + (-d if d < 0 else 0.0)) / period
        out[i] = _rsi(gain, loss)
    return out


def _rsi(gain: float, loss: float) -> float:
    if loss == 0.0:
        return 50.0 if gain == 0.0 else 100.0
    return 100.0 - 100.0 / (1.0 + gain / loss)


# ---------------------------------------------------------------- MACD
def macd_ref(values, fast=12, slow=26, signal=9):
    ef, es = ema_ref(values, fast), ema_ref(values, slow)
    line: list[float | None] = [None] * len(values)
    for i in range(len(values)):
        if ef[i] is not None and es[i] is not None:
            line[i] = ef[i] - es[i]

    defined = [(i, v) for i, v in enumerate(line) if v is not None]
    vals = [v for _, v in defined]
    sig_vals = ema_ref(vals, signal) if len(vals) >= signal else []
    sig: list[float | None] = [None] * len(values)
    hist: list[float | None] = [None] * len(values)
    for j, (idx, v) in enumerate(defined):
        if j < len(sig_vals) and sig_vals[j] is not None:
            sig[idx] = sig_vals[j]
            hist[idx] = v - sig_vals[j]
    return line, sig, hist


# ---------------------------------------------------------------- ATR
def true_range(prev_close: float, high: float, low: float) -> float:
    return max(high - low, abs(high - prev_close), abs(low - prev_close))


def atr_ref(candles, period=14):
    """Wilder-smoothed ATR."""
    out: list[float | None] = [None] * len(candles)
    if len(candles) < period + 1:
        return out
    trs = [
        true_range(candles[i - 1]["close"], candles[i]["high"], candles[i]["low"])
        for i in range(1, len(candles))
    ]
    if len(trs) < period:
        return out
    prev = sum(trs[:period]) / period
    out[period] = prev
    for i in range(period, len(trs)):
        # trs[i] is the true range of bar i+1, which lands at out[i+1].
        prev = (prev * (period - 1) + trs[i]) / period
        out[i + 1] = prev
    return out


# ---------------------------------------------------------------- ADX
def adx_ref(candles, period=14):
    n = len(candles)
    adx: list[float | None] = [None] * n
    plus: list[float | None] = [None] * n
    minus: list[float | None] = [None] * n
    if n < period * 2 + 1:
        return adx, plus, minus

    pdm, mdm, trs = [], [], []
    for i in range(1, n):
        up = candles[i]["high"] - candles[i - 1]["high"]
        dn = candles[i - 1]["low"] - candles[i]["low"]
        pdm.append(up if (up > dn and up > 0) else 0.0)
        mdm.append(dn if (dn > up and dn > 0) else 0.0)
        trs.append(true_range(candles[i - 1]["close"], candles[i]["high"], candles[i]["low"]))

    tr = sum(trs[:period])
    p = sum(pdm[:period])
    m = sum(mdm[:period])

    def di(d, t):
        return 0.0 if t == 0 else d / t * 100.0

    def dxval(pdm_, tr_, mdm_):
        if tr_ == 0:
            return 0.0
        p_ = pdm_ / tr_ * 100.0
        m_ = mdm_ / tr_ * 100.0
        s = p_ + m_
        return 0.0 if s == 0 else abs(p_ - m_) / s * 100.0

    plus[period] = di(p, tr)
    minus[period] = di(m, tr)
    dx = [dxval(p, tr, m)]
    idx = [period]

    for i in range(period, len(trs)):
        tr = tr - tr / period + trs[i]
        p = p - p / period + pdm[i]
        m = m - m / period + mdm[i]
        j = i + 1
        plus[j] = di(p, tr)
        minus[j] = di(m, tr)
        dx.append(dxval(p, tr, m))
        idx.append(j)

    if len(dx) >= period:
        prev = sum(dx[:period]) / period
        adx[idx[period - 1]] = prev
        for i in range(period, len(dx)):
            prev = (prev * (period - 1) + dx[i]) / period
            adx[idx[i]] = prev

    return adx, plus, minus


# ---------------------------------------------------------------- Bollinger
def bb_ref(values, period=20, mult=2.0):
    mid = ema_ref(values, period)
    up: list[float | None] = [None] * len(values)
    lo: list[float | None] = [None] * len(values)
    for i in range(len(values)):
        if mid[i] is None or i < period - 1:
            continue
        m = mid[i]
        var = sum((values[j] - m) ** 2 for j in range(i - period + 1, i + 1)) / period
        sd = math.sqrt(var)
        up[i] = m + mult * sd
        lo[i] = m - mult * sd
    return up, mid, lo


# ---------------------------------------------------------------- compare
def close(a, b, tol=TOL) -> bool:
    if a is None or b is None:
        return a is None and b is None
    if a == b:
        return True
    scale = max(abs(a), abs(b), 1.0)
    return abs(a - b) / scale <= tol


def compare(name: str, mine, ref, failures: list[str]) -> None:
    for i, (a, b) in enumerate(zip(mine, ref)):
        if not close(a, b):
            failures.append(f"{name}[{i}]: dart={a!r} ref={b!r} diff={abs((a or 0)-(b or 0)):.3e}")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: verify_indicators.py <dump.json>", file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8") as fh:
        dump = json.load(fh)

    closes = dump["closes"]
    # Rebuild the same OHLC the Dart dump used.
    candles = [
        {"open": c - 0.35, "high": c + 0.9, "low": c - 0.9, "close": c}
        for c in closes
    ]

    failures: list[str] = []
    checks: list[tuple[str, object, object]] = []

    e20 = ema_ref(closes, 20)
    e50 = ema_ref(closes, 50)
    e200 = ema_ref(closes, 200)
    checks.append(("ema20", dump["ema20"], e20[-5:]))
    checks.append(("ema50", dump["ema50"], e50[-5:]))
    checks.append(("ema200", dump["ema200"], e200[-5:]))

    r = rsi_ref(closes, 14)
    checks.append(("rsi14", dump["rsi14"], r[-5:]))

    ml, ms, mh = macd_ref(closes)
    checks.append(("macd", dump["macd"], ml[-5:]))
    checks.append(("macdSignal", dump["macdSignal"], ms[-5:]))
    checks.append(("macdHistogram", dump["macdHistogram"], mh[-5:]))

    a = atr_ref(candles, 14)
    checks.append(("atr14", dump["atr14"], a[-5:]))

    ad, dp, dm = adx_ref(candles, 14)
    checks.append(("adx14", dump["adx14"], ad[-5:]))
    checks.append(("plusDi", dump["plusDi"], dp[-5:]))
    checks.append(("minusDi", dump["minusDi"], dm[-5:]))

    up, mid, lo = bb_ref(closes)
    checks.append(("bbUpper", dump["bbUpper"], up[-5:]))
    checks.append(("bbMiddle", dump["bbMiddle"], mid[-5:]))
    checks.append(("bbLower", dump["bbLower"], lo[-5:]))

    for name, mine, ref in checks:
        compare(name, mine, ref, failures)

    # ATR percentile: rank of the latest value within its own window.
    atr_vals = [v for v in a if v is not None]
    window = atr_vals[-100:]
    mine_p = dump["atrPercentile"]
    ref_p = (sum(1 for v in window if v <= window[-1]) / len(window)) * 100.0
    if not close(mine_p, ref_p, 1e-9):
        failures.append(f"atrPercentile: dart={mine_p!r} ref={ref_p!r}")

    # Swings: verify every reported swing really is a fractal pivot.
    for s in dump["swings"]:
        i, price, is_high = s["index"], s["price"], s["isHigh"]
        window_bars = candles[i - 2: i + 3]
        if is_high:
            if not all(bars["high"] < price for bars in window_bars if bars is not candles[i]):
                failures.append(f"swing high {i}@{price} is not a pivot")
        else:
            if not all(bars["low"] > price for bars in window_bars if bars is not candles[i]):
                failures.append(f"swing low {i}@{price} is not a pivot")

    print(f"indicators compared: {len(checks) + 1} series, "
          f"{len(dump['swings'])} swing pivots")
    if failures:
        print(f"\nFAIL ({len(failures)} mismatches, tol={TOL}):")
        for f in failures[:25]:
            print(f"  - {f}")
        if len(failures) > 25:
            print(f"  ... and {len(failures) - 25} more")
        return 1

    print("PASS: dart engine matches the independent reference implementation")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())