"""Backfill XAUUSD OHLC bars from Dukascopy (methodology §3.1 source P5).

Why this exists
---------------
§3.1 sets a hard floor: "Minimum history to load: 500 bars per timeframe
(EMA200 and baselines)". XV only started persisting bars recently, so the
technical engine had ~50 five-minute bars and could never compute EMA200 on
1H bars -- which means the confluence engine would have returned
NO_TRADE / v3DataStale forever. This script warms the history so the engine
can actually score.

Policy compliance
-----------------
* Dukascopy tick data is used here for *historical warm-up*, which §3.1
  designates as the backtest/research source. Live signals continue to use the
  primary feed.
* Each tick carries a real bid and ask. This script derives only the MID for
  OHLC bars; it does NOT record bid/ask as market_snapshots.bid/ask, because
  those columns represent the execution venue spread and Dukascopy is a
  historical research feed, not the execution venue. Deriving a spread from it
  would violate the ratified option (a) rule.
* Spot XAUUSD has no true volume, so volume is emitted as null rather than a
  fabricated tick count.

Output
------
NDJSON on stdout (one bar per line) so it can be piped into an ingest step, or
--out FILE to write it. Bounded to the newest N bars per timeframe.

Usage
-----
    python tools/backfill_dukascopy.py --days 21 --per-tf 500 --out backfill.ndjson
"""

from __future__ import annotations

import argparse
import json
import lzma
import struct
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

BASE = "https://datafeed.dukascopy.com/datafeed/{symbol}/{y:04d}/{m:02d}/{d:02d}/{h:02d}h_ticks.bi5"
TIMEFRAMES = {"5m": 5, "15m": 15, "30m": 30, "1h": 60}

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) XV-backfill/1.0"


def fetch(url: str, retries: int = 5, timeout: int = 30) -> tuple[str, bytes | None]:
    """GET with retries.

    Returns (status, data) where status is one of:
      'ok'    - bytes downloaded
      'empty' - HTTP 404, i.e. the market did not trade in that hour
                 (weekends/holidays). Not an error and must not be retried.
      'fail'  - connection problem after all retries
    """
    delay = 2.0
    for _ in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return ("ok", resp.read())
        except urllib.error.HTTPError as e:
            if e.code == 404:
                # Genuinely no data for this hour.
                return ("empty", None)
            time.sleep(delay)
            delay *= 1.6
        except Exception:
            # This network drops connections intermittently; retry rather than
            # silently producing a hole in the history.
            time.sleep(delay)
            delay *= 1.6
    return ("fail", None)


def decode_bi5(raw: bytes) -> list[tuple[int, float, float]]:
    """Decode .bi5 -> [(ms_offset_in_hour, ask, bid)] in instrument points."""
    for dict_size in (1 << 16, 1 << 20, 1 << 24, 1 << 25):
        try:
            dec = lzma.LZMADecompressor(
                format=lzma.FORMAT_RAW,
                filters=[{"id": lzma.FILTER_LZMA1, "dict_size": dict_size}],
            )
            out = dec.decompress(raw)
        except lzma.LZMAError:
            continue
        ticks = []
        for i in range(len(out) // 12):
            ms, ask, bid = struct.unpack(">III", out[i * 12: i * 12 + 12])
            ticks.append((ms, ask / 1000.0, bid / 1000.0))
        return ticks
    return []


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--symbol", default="XAUUSD")
    ap.add_argument("--days", type=int, default=21,
                    help="days of history to fetch (21d -> ~500 hourly bars)")
    ap.add_argument("--per-tf", type=int, default=500,
                    help="max bars kept per timeframe (methodology floor)")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--out", default="-")
    args = ap.parse_args()

    end = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)
    start = end - timedelta(days=args.days)

    hours = []
    cur = start
    while cur < end:
        hours.append(cur)
        cur += timedelta(hours=1)

    print(f"fetching {len(hours)} hourly files {start:%Y-%m-%d %H} .. {end:%Y-%m-%d %H}",
          file=sys.stderr)

    ok = skipped = failed = 0

    def job(h: datetime):
        url = BASE.format(symbol=args.symbol, y=h.year, m=h.month, d=h.day, h=h.hour)
        status, raw = fetch(url)
        if status == "fail":
            return (h, None, "fail")
        if status == "empty":
            return (h, None, "empty")
        return (h, decode_bi5(raw), "ok")

    # Bucket in one pass so every timeframe shares a single download.
    buckets: dict[str, dict[int, list[tuple[int, float]]]] = {tf: {} for tf in TIMEFRAMES}

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        for n, (h, ticks, status) in enumerate(pool.map(job, hours), 1):
            if status == "fail":
                failed += 1
            elif status == "empty":
                skipped += 1
            else:
                ok += 1
                for ms, ask, bid in ticks:
                    mid = (ask + bid) / 2.0
                    ts = h + timedelta(milliseconds=ms)
                    epoch_min = int(ts.timestamp()) // 60
                    for tf, mins in TIMEFRAMES.items():
                        key = (epoch_min // mins) * mins * 60
                        buckets[tf].setdefault(key, []).append((ms, mid))
            if n % 25 == 0 or n == len(hours):
                print(f"  {n}/{len(hours)} hours  ok={ok} empty={skipped} fail={failed}",
                      file=sys.stderr, flush=True)

    print(f"hours ok={ok} empty={skipped} unreachable={failed}", file=sys.stderr)

    rows = []
    for tf, mins in TIMEFRAMES.items():
        built = []
        for key in sorted(buckets[tf]):
            prices = [p for _, p in buckets[tf][key]]
            if not prices:
                continue
            open_time = datetime.fromtimestamp(key, tz=timezone.utc)
            # A bar is only "closed" if its own boundary has passed.
            is_closed = open_time + timedelta(minutes=mins) <= datetime.now(timezone.utc)
            built.append({
                "symbol": args.symbol,
                "timeframe": tf,
                "open_time": open_time.isoformat().replace("+00:00", "Z"),
                "open": round(prices[0], 2),
                "high": round(max(prices), 2),
                "low": round(min(prices), 2),
                "close": round(prices[-1], 2),
                "volume": None,
                "is_closed": is_closed,
                "source": "dukascopy",
                "quality": "secondary",
            })
        rows.extend(built[-args.per_tf:])
        newest = built[-1]["open_time"] if built else "n/a"
        print(f"{tf:>4}: {len(built)} built, kept {min(len(built), args.per_tf)}, "
              f"newest={newest}", file=sys.stderr)

    rows.sort(key=lambda r: (r["timeframe"], r["open_time"]))
    out = sys.stdout if args.out == "-" else open(args.out, "w", encoding="utf-8")
    for r in rows:
        out.write(json.dumps(r, separators=(",", ":")) + "\n")
    if out is not sys.stdout:
        out.close()
        print(f"wrote {len(rows)} bars -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())