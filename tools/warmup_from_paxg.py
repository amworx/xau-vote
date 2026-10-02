"""Warm the technical engine's indicator history from Binance PAXG.

Why
---
Methodology §3.1 requires "500 bars per timeframe (EMA200 and baselines)".
XV started persisting bars recently, so EMA200 on 1H could not compute and the
confluence engine would return NO_TRADE / v3DataStale indefinitely. OANDA (P1)
is unavailable from this country, so P2 (Binance PAXG) is the warm-up source.

The basis problem, and why this script exists
---------------------------------------------
PAXG is tokenised gold and trades a small basis away from spot XAUUSD. Seeding
EMA200 with *raw* PAXG closes would leave the average sitting at the PAXG price
level rather than the spot level. EMA200 moves with k = 2/201, so the error
would decay over ~100+ bars -- long enough to corrupt EMA-alignment scoring,
because price would sit on the "wrong side" of a stale EMA200 and the engine
would read a healthy uptrend as a collapse (or vice versa).

So every historical bar is shifted by the observed basis:

    basis = spot_now - paxg_now
    adjusted_paxg_price = paxg_price + basis

This cancels the constant component of the basis at the anchor point. Basis
drift over the warm-up window is small compared with the EMA initialisation
error it removes.

Honesty constraints
-------------------
* Bars are written with source='binance-paxg-warmup' and quality='degraded'.
  MGC §3.1 permits P2 for "sanity and volatility, not exact levels", so these
  bars MUST NOT be used to publish entry/SL/TP levels. The confluence engine
  and stop planner both refuse degraded input for level generation.
* PAXG klines carry no genuine XAUUSD bid/ask, so no spread is derived here.
  market_snapshots.bid/ask stay NULL (ratified option (a) rule).
* The live `build-bars` function upserts on (symbol,timeframe,open_time), so
  every real gold-api bar overwrites its warm-up counterpart as time passes.
  The warm-up set therefore decays to zero on its own.

Usage
-----
    python tools/warmup_from_paxg.py --spot 4136.40 --out warmup.ndjson
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

BINANCE = "https://api.binance.com/api/v3/klines"
TIMEFRAMES = {"5m": "5m", "15m": "15m", "30m": "30m", "1h": "1h"}
# How many warm-up bars per timeframe. 1h needs the full 500 for EMA200;
# lower timeframes only need enough for EMA50/RSI/structure, and 250 keeps the
# insert small while leaving generous headroom over the longest window used.
BARS = {"5m": 250, "15m": 250, "30m": 250, "1h": 500}


def fetch_klines(symbol: str, interval: str, limit: int, retries: int = 4) -> list:
    url = f"{BINANCE}?symbol={symbol}&interval={interval}&limit={limit}"
    delay = 1.5
    for _ in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "XV-warmup/1.0"})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        except Exception:
            time.sleep(delay)
            delay *= 1.6
    return []


def stale_threshold(bars: list) -> float:
    """Minimum bar range below which a PAXG bar counts as non-trading.

    PAXG is thinly traded outside US/European hours, so it occasionally emits a
    bar whose high == low. Those are not valid volatility samples: a 0.01-range
    bar inside an ATR(14) window drags the average down and makes the volatility
    regime read artificially calm. The threshold is 0.5% of the series median
    range (floor 0.05), which removes genuine non-trading hours without
    discarding real low-volatility bars.
    """
    ranges = sorted(float(k[2]) - float(k[3]) for k in bars)
    median = ranges[len(ranges) // 2]
    return max(0.05, median * 0.005)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--spot", type=float, required=True,
                    help="current spot XAUUSD price, used as the basis anchor")
    ap.add_argument("--symbol", default="PAXGUSDT")
    ap.add_argument("--out", default="-")
    args = ap.parse_args()

    rows: list[dict] = []
    now_ms = int(datetime.now(timezone.utc).timestamp() * 1000)

    # Fetch every timeframe first, then apply ONE global basis.
    #
    # Computing a basis per timeframe is a real bug: each timeframe's most
    # recent bar closes at a different minute, so per-timeframe bases drift
    # apart (observed: -6.85 on 5m vs -8.88 on 1h). That would make two
    # timeframes disagree about the price level at the same instant and corrupt
    # every cross-timeframe confluence comparison. One anchor, one basis.
    fetched: dict[str, list] = {}
    for tf, interval in TIMEFRAMES.items():
        raw = fetch_klines(args.symbol, interval, BARS[tf])
        # Drop the still-forming bar: it must never be treated as confirmed.
        closed = [k for k in raw if k[6] < now_ms] if raw else []
        fetched[tf] = closed
        if not closed:
            print(f"{tf:>4}: FAILED to fetch", file=sys.stderr)

    # Anchor on the freshest available PAXG close (the 5m series closes last).
    anchor_tf = "5m" if fetched.get("5m") else next(
        (t for t in TIMEFRAMES if fetched[t]), None
    )
    if anchor_tf is None:
        print("no timeframe produced closed bars", file=sys.stderr)
        return 1

    basis = args.spot - float(fetched[anchor_tf][-1][4])
    print(f"anchor={anchor_tf} basis={basis:+.2f} (applied to all timeframes)",
          file=sys.stderr)

    dropped_total = 0
    for tf in TIMEFRAMES:
        closed = fetched[tf]
        if not closed:
            continue

        thresh = stale_threshold(closed)
        keep = [k for k in closed if (float(k[2]) - float(k[3])) >= thresh]
        dropped = len(closed) - len(keep)
        dropped_total += dropped
        if dropped:
            print(f"{tf:>4}: dropped {dropped} stale bar(s) "
                  f"(range < {thresh:.2f})", file=sys.stderr)

        for k in keep:
            open_time = datetime.fromtimestamp(k[0] / 1000, tz=timezone.utc)
            rows.append({
                "symbol": "XAUUSD",
                "timeframe": tf,
                "open_time": open_time.isoformat().replace("+00:00", "Z"),
                "open": round(float(k[1]) + basis, 2),
                "high": round(float(k[2]) + basis, 2),
                "low": round(float(k[3]) + basis, 2),
                "close": round(float(k[4]) + basis, 2),
                # PAXG kline volume is token volume, not spot activity.
                "volume": None,
                "is_closed": True,
                "source": "binance-paxg-warmup",
                "quality": "degraded",
            })
        print(f"{tf:>4}: kept {len(keep)}/{len(closed)} bars", file=sys.stderr)

    print(f"stale bars dropped overall: {dropped_total}", file=sys.stderr)

    if not rows:
        print("no rows produced", file=sys.stderr)
        return 1

    rows.sort(key=lambda r: (r["timeframe"], r["open_time"]))
    out = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")
    for r in rows:
        out.write(json.dumps(r, separators=(",", ":")) + "\n")
    if out is not sys.stdout:
        out.close()
        print(f"wrote {len(rows)} warm-up bars -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())