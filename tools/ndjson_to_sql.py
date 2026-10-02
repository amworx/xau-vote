"""Convert warm-up NDJSON into a single idempotent SQL upsert statement.

Run from the repo root:
    python tools/ndjson_to_sql.py warmup.ndjson warmup.sql

The statement upserts on (symbol, timeframe, open_time), so re-running it is
harmless: real gold-api bars overwrite warm-up rows automatically as the live
builder advances, and re-applying warm-up data cannot clobber a newer primary
bar with older history.
"""

from __future__ import annotations

import json
import sys

COLUMNS = (
    "symbol,timeframe,open_time,open,high,low,close,volume,"
    "is_closed,source,quality"
)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: ndjson_to_sql.py <in.ndjson> <out.sql>", file=sys.stderr)
        return 2
    src, dst = sys.argv[1], sys.argv[2]

    rows = [json.loads(line) for line in open(src, encoding="utf-8") if line.strip()]
    if not rows:
        print("no rows", file=sys.stderr)
        return 1

    def q(v: str) -> str:
        return "'" + str(v).replace("'", "''") + "'"

    vals = []
    for r in rows:
        vals.append(
            "({symbol},{tf},{ot},{o},{h},{l},{c},NULL,{closed},{src},{q})".format(
                symbol=q(r["symbol"]),
                tf=q(r["timeframe"]),
                ot=q(r["open_time"]),
                o=r["open"],
                h=r["high"],
                l=r["low"],
                c=r["close"],
                closed="TRUE" if r["is_closed"] else "FALSE",
                src=q(r["source"]),
                q=q(r["quality"]),
            )
        )

    sql = (
        "insert into public.market_bars "
        f"({COLUMNS})\nvalues\n"
        + ",\n".join(vals)
        + "\non conflict (symbol, timeframe, open_time) do update set\n"
        "  open = excluded.open,\n"
        "  high = excluded.high,\n"
        "  low = excluded.low,\n"
        "  close = excluded.close,\n"
        "  volume = excluded.volume,\n"
        "  is_closed = excluded.is_closed,\n"
        "  source = excluded.source,\n"
        "  quality = excluded.quality;\n"
    )

    with open(dst, "w", encoding="utf-8") as fh:
        fh.write(sql)
    print(f"{len(rows)} rows -> {dst} ({len(sql)} chars)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())