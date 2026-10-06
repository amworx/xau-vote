# XV Evaluation Pre-Registration

**Frozen:** 2026-10-06, before any episode was counted.
**Status:** binding. Written to be read against the results, not after them.

This document exists so that the evaluation cannot be shaped by the outcome. It
is the §10 requirement, and it is written before the first episode exists — at
the time of writing `xv_outcome_ledger` is empty.

---

## 1. The evaluation unit

**`INDEPENDENT_SETUP_EPISODE`.**

Not the scan. The app scans every 60 seconds; ten scans inside one gold move are
one observation, not ten. The merge rule is `xv_episode_merge_v1` (migration
`0014`), and its version is stored on every row as `merge_rule_version`.

### Merge rule v1, fixed now

A scan continues an existing episode when **all** of:

1. same direction
2. same `rule_hash`
3. same `engine_version`
4. the existing episode is still unresolved
5. `decided_at` is inside the episode's validity window (3h)
6. levels are materially unchanged: |entry Δ| ≤ 0.5 × `risk_distance` and
   |stop Δ| ≤ 0.5 × `risk_distance`

Otherwise a new episode is created. Abstentions never merge.

Rule 6 is what stops a drifting stop from being counted as one setup while
still collapsing the ordinary case where the same level is re-derived every
minute. A setup whose levels moved by more than half its own risk is a
different setup.

Verified by execution: 7 scans produced 5 episodes, with each negative case
merging as specified.

---

## 2. Episode states, all counted

Every episode is recorded, including the ones where nothing happened:

| State | Meaning |
|---|---|
| `SETUP` | a directional setup was generated |
| `NO_TRADE` | nothing qualified, and the information was sufficient to say so |
| `INSUFFICIENT_DATA` | a required measurement was missing or unusable |
| `NEWS_LOCK` | a high-impact release is inside the blackout |
| `VOLATILITY_BLOCK` | the volatility regime vetoed the setup |
| `DATA_QUALITY_BLOCK` | feed staleness, a gap, or degradation blocked it |

"Declined because the market was closed" and "declined because we have no
measured macro" are different facts and are not pooled.

---

## 3. The outcome rule, fixed now

Resolved against **closed M15 bars** in `market_bars`:

- **STOP_FIRST** — `low ≤ stop` (long) or `high ≥ stop` (short) resolves it
- **TARGET_FIRST** — `high ≥ tp1` (long) or `low ≤ tp1` (short) resolves it
- **BOTH_SAME_BAR** — resolves as **STOP**, always
- **NEITHER** — `TIMEOUT`, scored at the horizon close and **counted**
- **NO_OVERLAP** — bars do not cover the window; `net_outcome = cost_model_unavailable`

The same-bar rule is the pessimistic one and is not revisited. Intrabar sequence
is unknowable from OHLC, and the assumption has to be the unfavourable one.

**A TIMEOUT counts.** Dropping unresolved trades is how a losing engine reports a
winning one.

---

## 4. Pass / fold criteria, fixed now

| Parameter | Value |
|---|---|
| Minimum independent setup episodes | **200** |
| Minimum volatility regimes covered | **2** |
| Primary metric | **mean net R per independent episode** |
| Pass | 95% lower confidence bound of mean net R **> 0** |
| Fold | 95% lower confidence bound **≤ 0** |

The lower bound is the test, not the point estimate. A positive mean with a
confidence interval crossing zero is not evidence.

**Rule changes invalidate the sample.** If a threshold changes, a new `rule_hash`
cohort begins and results are **not** pooled across cohorts. `xv_ledger_evaluation`
groups by `rule_hash` for exactly this reason.

---

## 5. Cost model

- Where a genuine measured spread exists and is usable for internal research:
  `cost_model = 'measured_spread'`.
- Otherwise: `net_outcome = 'cost_model_unavailable'`.

**Slippage is not modelled**, because it is not observable from the feeds
available. This makes results optimistic by an unknown amount and is recorded as
a known limitation, not estimated away.

---

## 6. What is not claimed

- A backtest may **falsify** a bad idea early. It does not substitute for forward
  evidence.
- Forward recording began at recorder deployment and continues regardless of what
  else is built. **Collection is never paused for an integration.**
- No performance figure is shown to any user until the criteria above are met.
- The engine is not optimised repeatedly until a positive result appears. If the
  fold criterion is met, the engine is folded into another product rather than
  the goalposts being moved.

---

## 7. Recorded in advance, so it cannot be discovered later

1. **The OANDA spread is display-restricted.** Its licence grants internal use
   only and forbids transmitting rates to third parties. The public app must not
   display it. The ledger may use it for internal research; the UI may not.
2. **Slippage is unobserved**, so every net figure is optimistic.
3. **1H bars are majority warm-up.** 251 of 349 are `degraded` (Binance PAXG,
   a crypto token). EMA200 on that series rests partly on a different instrument.
4. **The recorded ~$0.41 spread is unsupported.** Measured OANDA mean is 0.9913
   across 5,566 rows; provenance of the $0.41 figure is UNKNOWN.
5. **One input price source, three instruments' worth of history.** Bars come
   from gold-api with PAXG warm-up; the spread comes from OANDA practice; the
   mid comes from gold-api. These are not the same venue.