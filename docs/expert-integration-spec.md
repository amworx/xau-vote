# XV Expert Integration Spec

Derived from two independent expert documents in `instruction/`:

- **MGC** — `XAUUSD_Signal_Bot_Instructions.md` (798 lines, rule-based framework)
- **METH** — `XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md` (2130 lines, implementation spec)

Both are unverified reference methodologies. Neither is a proven-profitable system
and both say so. `[INIT]` thresholds below are **starting hypotheses**, not
constants, per MGC §0.4.

---

## 0. Where the two experts AGREE (high-confidence core)

These points are stated identically by both authors, so they are the backbone
of the integration:

| # | Agreement | MGC | METH |
|---|---|---|---|
| A1 | This is a **filtering** system, not a predictor | §0/§9 | §0 "filtering system, not a forecasting engine" |
| A2 | **`NO_TRADE` is correct and frequent**, not a failure | R6, R12 | §0, §8.1 step 14 |
| A3 | Every signal needs **SL + 1–3 TPs**, never more than 3 | R1, §10.2 | §29, §12 |
| A4 | Multi-timeframe hierarchy, highest TF leads | §7.1, §8.1 | §7.1 |
| A5 | **Indicators confirm, they never initiate** | §7.4 | §0, §3 |
| A6 | **News blackout overrides everything** | R2, V1, §9 | §9 Rule 1 |
| A7 | Extreme volatility ⇒ no new signals | V4, §7.2 | §2.5, §9 Rule 2 |
| A8 | Slow sentiment (COT/WGC) cannot create an entry | §4.1 V4/V7 note | §9 Rule 4, §23 |
| A9 | Structure/levels matter more than indicator values | §7.1, §8.3 | §3 |
| A10 | Stop is **structural first, math second**, ATR-clamped | §10.1 | §11 |
| A11 | Scores describe **setup quality, never probability** | R5, §9.3 | §16 |
| A12 | Prefer **pullback/retest** over chasing | §8.3 step 5 | §7.4, §10.1 |
| A13 | **Closed candles only**, no repainting/look-ahead | R3 | §1.2 rule 9, §27 F5 |

## 1. Where they DIFFER (and how this integration resolves it)

| Topic | MGC | METH | Resolution |
|---|---|---|---|
| EMA periods | 21/50/200 | 20/50/200 (v1.1) | **20/50/200** — see §1a below; matches the document that also fixes the stop/score thresholds |
| RSI zones | regime bands 40–80, +1.0 if 50–65 rising | 52–68 preferred, >75 no chase | **Union of both**: 52–68 preferred; hard veto on fresh entry >75 (long) / <25 (short) |
| ATR clamp | `0.8–2.5 × ATR` | `0.8–1.8 × ATR` | **0.8–1.8 × ATR** (METH is stricter and §15 rule 9 rejects >1.8 ATR5m; the tighter cap preserves R:R) |
| Stop buffer | `max(0.15×ATR, 2×spread)` | `0.20×ATR` (v1.1; `max(·, spread*2)` only with genuine bid/ask) | **0.20 × ATR** — see §1a |
| Blackout tiers | 3 tiers: T1-A/T1-B/T2/T3 | Tier A/B/C | **MGC's granular 4-tier** (T1-A, T1-B, T2, T3) — strictly more informative and subsumes METH's A/B |
| FOMC blackout | T−60 → T+90 | T−45 → T+30 after PC | **T−60 → T+90** (MGC — a Fed decision has the longest information content) |
| Scoring | 0–100 Quality Score + A+/A/B grade | 12-point technical score + LOW/MED/HIGH | **Both, layered**: METH 12-pt technical is the *floor*, MGC 0–100 Quality drives the *grade* shown to the user |
| R:R floor | TP2 ≥ 1.8R (R7) | TP1 ≥ 1R, TP2 = 2R | **TP2 ≥ 1.8R** (MGC's explicit HARD rule) |
| TP split | 50/30/20 fast, 40/30/30 slow | 50/30/20 | **50/30/20** |

### EMA periods re-decided (2026-10-02, user-ratified)

METH v1.1 (updated file) uses **EMA 20/50/200** throughout (§2.1, §7.2, §7.4).
MGC uses 21/50/200. The difference is immaterial to the logic — both are
"fast/medium/regime" — but mixing them across layers would create an
inconsistency that is impossible to explain to a trader reading the score
breakdown.

**Decision: adopt METH's 20/50/200** so the implementation matches the document
that also supplies the concrete stop/score thresholds, and record EMA21 as a
calibration variable for §14 walk-forward rather than hardcoding two conventions.

## 1a. Spread policy — METH v1.1 §1.2 (user-ratified option (a))

The updated methodology is explicit and this integration adopts it verbatim:

- Genuine spread = **execution venue Ask − Bid only**.
- **Never** derive a spread from `gold-api` vs `xaus.com` or any cross-source
  price difference.
- When unavailable the engine must expose:

  ```text
  spread_status: UNAVAILABLE
  spread_veto_status: UNEVALUATED
  spread_source: NONE
  ```

- `UNAVAILABLE` ≠ zero and ≠ normal — it means *no trustworthy measurement*.
- The spread-dependent vetoes (`V2_SPREAD`) **do not fire**; they report
  `UNEVALUATED` and the gap is recorded as a data-quality note.
- Stop buffer defaults to **`0.20 × ATR`**. The `max(0.20*ATR, spread*2)` form
  is permitted only when a genuine bid/ask adapter exists later.

This is why `market_snapshots.bid` / `.ask` stay `NULL` in XV: populating them
from a derived difference would violate the rule both experts now encode.

## 1b. Sources — taken from the instruction files, not re-researched

Both expert documents enumerate concrete sources with IDs. They are
authoritative for XV, so no independent source search is needed.

| Group | IDs | Role |
|---|---|---|
| Price | **P1** OANDA fxTrade Practice (alt **P1b** MT5) · **P2** Binance PAXG (cross-check only) · **P3** Yahoo · **P4** Twelve Data (fallback) · **P5** Dukascopy (backtest) | P1 is the signal feed |
| Calendar | **C1** ForexFactory weekly JSON (convenience: impact + consensus, **no actuals**) · **C2** BLS · **C3** BEA · **C4** Federal Reserve · **C5** FRED · **C6** official actuals | C1 for convenience; **C2–C5 are the authority for dates/times** |
| Macro | **M-FRED** `DFII10`/`DGS10`/`DGS2`/`T10YIE`/`DFF`/`DTWEXBGS`/`VIXCLS` · **M-UST** Treasury yield curves · **M-INTRA** Yahoo · **M-FED** CME FedWatch (manual, do not scrape) | daily regime only, never intraday |
| Positioning | **F-COT** CFTC disaggregated COMEX gold `088691` · **F-ETF** GLD · **F-ETF2** IAU | slow: confidence only |
| Structural | **O-WGC** · **O-IMF** · **O-PBOC** · **O-FED** RSS · ECB/BoE/BoJ | slow structural bias |

Rights guidance (MGC §3): show **derived outputs** — signals, scores,
calculated indicator values, event times — rather than republishing raw
third-party quote streams or article text.

### Two findings that change the implementation

1. **P1 publishes genuine bid/ask.** That is exactly the condition the ratified
   option (a) rule named for activating the spread vetoes. It is a *demo*
   venue, so it qualifies as an execution-venue spread only in demo terms and
   must be labelled as such rather than implying a live execution spread.
2. **P2/P3 are proxies, never level sources.** Binance PAXG carries a small
   basis versus spot. MGC §3.1 permits it for "sanity and volatility, not
   exact levels", so PAXG bars may warm an indicator but must never publish
   entry/SL/TP levels unless basis-corrected and labelled degraded.

### Hard floor currently unmet

§3.1: *"Minimum history to load: 500 bars per timeframe (EMA200 and
baselines)."* XV had ~50 five-minute bars, so EMA200 on 1H cannot compute and
the engine would return `NO_TRADE / v3DataStale` indefinitely. Warming this
history is the critical path to any scored signal.

## 2. Data prerequisites that do NOT exist yet

Both experts require OHLCV candles. XV currently stores **single price ticks
only** (`market_snapshots`), so none of the technical engine can run until bars
are available. This is the single biggest gap.

Both authors converge on the same free sources (see §6 for the full table):

- **Candles:** Dukascopy (METH P0) / OANDA practice (MGC P1) / MT5 demo / Binance PAXG proxy
- **Macro:** US Treasury daily nominal + real yield curves, FRED (`DFII10`,
  `DGS2`, `DGS10`, `T10YIE`, `DTWEXBGS`, `VIXCLS`)
- **Positioning:** CFTC COT (disaggregated, COMEX gold `088691`), SPDR GLD holdings
- **Official calendar:** BLS / BEA / Federal Reserve schedules (authoritative for TIMES)
- **Convenience calendar:** ForexFactory weekly JSON (has consensus, **no actuals**)
- **News:** Fed/ECB/BoE/BoJ RSS, GDELT DOC 2.0, FXStreet RSS
- **Macro regime:** WGC Goldhub, EIA, ISM

## 3. Layered architecture to implement

```
market_snapshots (ticks, exists)
        │  resample into closed bars
        ▼
  OHLC bars (5m/15m/30m/1H)  ◄── NEW: needed by everything below
        │
        ├─► L1 EVENT GATE ────────► blackout? NO TRADE (V1)
        ├─► L2 DATA QUALITY ──────► stale/feed anomaly? NO TRADE (V3)
        ├─► L3 VOLATILITY ────────► ATR percentile → regime, V4/V7
        ├─► L4 TECHNICAL ─────────► indicators + structure per timeframe
        ├─► L5 MACRO (daily) ─────► R/D/I/P impulses
        ├─► L6 SENTIMENT (weekly) ► COT/ETF — confidence only, never initiates
        └─► L7 CONFLUENCE ────────► technical 12-pt + macro + sentiment
                     │
                     ▼
        NO TRADE (reason codes)  |  SIGNAL + grade A+/A/B + SL/TP + R:R
```

Ordering is not arbitrary: it matches METH §21 pseudocode exactly, and MGC §2's
L1–L11 stack. Both say the same thing.

## 4. Hard rules (never break — from MGC R1–R12)

1. Never publish a signal without SL and 1–3 TPs
2. Never publish inside a news blackout
3. Closed candles only — no repainting, no look-ahead
4. Every number traces to a named source + timestamp
5. No "sure"/"risk-free"/"guaranteed"; no probability without ≥100 calibrated samples
6. ≤4 signals per UTC day
7. TP2 ≥ 1.8R
8. Never invent data — "unknown" is a valid answer
9. Separate fact / inference / opinion in explanations
10. No copyrighted article text — headline + link + time only
11. Every signal carries the disclaimer
12. Unresolved ambiguity ⇒ NO TRADE

## 5. Vetoes → NO TRADE with a reason code

MGC §9.4 V1–V10 plus METH §15's 16 skip rules, merged:

| Code | Veto | Source |
|---|---|---|
| `V1_BLACKOUT` | inside event lock, or expected hold overlaps it | MGC V1 / METH 1–2 |
| `V2_SPREAD` | spread > 1.5× normal, or > 0.15×ATR | MGC V2 / METH 4 |
| `V3_DATA_STALE` | required input stale / feed down | MGC V3 / METH 13, 16 |
| `V4_VOLATILITY_EXTREME` | ATR ratio > 2.0 (MGC) or percentile > 95 (METH) | both |
| `V5_POOR_RR` | TP2 < 1.8R, or major opposing level blocks the path | MGC V5 / METH 10 |
| `V6_DIRECTION_CONFLICT` | setup direction vs DirScore sign | MGC V6 |
| `V7_DAILY_LIMIT` | ≥4 signals today, or circuit breaker | MGC V7 / METH 14–15 |
| `V8_SESSION_CLOSED` | Friday late / rollover / weekend | MGC V8 / METH 16 |
| `V9_DUPLICATE` | overlapping signal in same zone/direction | MGC V9 |
| `V10_CONFIRMATION_LOW` | indicator confirmation Σ ≤ 1 | MGC V10 |
| `V11_H1_NEUTRAL` | 1H regime NEUTRAL ⇒ no signal | METH §8.1 step "H1 NEUTRAL" |
| `V12_LOW_CONFLUENCE` | technical < 8/12 or final < 9 | METH §15 6–7 |
| `V13_BAD_STOP_DISTANCE` | SL outside 0.8–1.8 × ATR | METH §15 9 |

**Spread-dependent vetoes** (`V2_SPREAD`, `V4` emergency conditions) require a
genuine bid/ask feed that no free source provides. Per §1a they report
`UNEVALUATED` and are recorded as a data-quality note — they never fire on a
proxy value, and they never silently pass.

## 6. Source priority (merged, MGC §3.9 + METH §1.1)

| Tier | Meaning | Rule |
|---|---|---|
| **A** | Official: BLS, BEA, Fed, Treasury, CFTC | Overrides everything on facts/timings |
| **B** | Established: FRED, Dukascopy, GDELT, RSS | Use; cross-check key numbers |
| **C** | Unofficial: ForexFactory JSON, Yahoo, Binance proxy | Only with cross-check or fallback |

MGC §3.2: "If C1 and an official schedule disagree, trust the official
schedule." MGC §3.3: FRED **no longer carries the LBMA gold price** (licensing)
— do not use FRED for gold prices.

## 7. Integration order (dependency-driven)

1. **Bars** — OHLC resample + `Candle` model + validation (reject dup
   timestamps, reject `high < max(o,c)`, detect gaps, never forward-fill)
2. **Indicators** — EMA20/50/200, RSI14, MACD 12/26/9, ADX14+DI, ATR14,
   ATR percentile, Bollinger width, swing fractal, session levels
3. **Volatility regime + ATR clamp** — needed before stop logic
4. **Event tiers + blackout + calm-down** — replace the flat HIGH-only gate
5. **Confluence scoring** — METH 12-point technical, MGC 0–100 quality, grades
6. **R:R + structural targets** — TP1/TP2/TP3 with the 1.8R floor
7. **Risk governance** — daily limits, circuit breaker, dedupe
8. **Macro/sentiment** — *last*, because it is slow-moving and only adjusts
   confidence (both experts agree it must never initiate)

## 8. What this integration will NOT do

- It will not display win probability (both experts forbid it pre-calibration)
- It will not treat COT/WGC/news as an entry trigger
- It will not publish B-grade by default (MGC: "never counter-bias + B")
- It will not fabricate a candle, spread, or macro value when a source fails
- It will not claim any of the `[INIT]` thresholds are validated — §14/§25
  require 200 backtested signals + walk-forward before live confidence