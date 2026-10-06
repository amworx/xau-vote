# XV (XAU-Vote) — MVP status and the blocker

**Date:** 2026-10-06 · **Author:** project owner · **Status:** for external expert review
**Purpose:** a self-contained briefing for experts who have no prior context on this project.

Read §5 first. It is the part that matters.

---

## 1. What the product is meant to be

**XV** is a free, Android-first XAUUSD (spot gold) **15-minute** setup-analysis app.
It executes no trades. Non-negotiable product rules:

1. **15M is the only signal timeframe.** 5M confirms; 1H is context and never votes.
2. **Never fabricate.** Insufficient data → `NO CONSENSUS` / `NO TRADE`. Never
   manufacture a direction, level, or probability.
3. **Agreement is not probability.** Never rendered as "% chance".
4. **Independence is strict.** Duplicate ideas count as ONE vote. Unknown
   independence never counts as independent.
5. **Licensing gate.** A source ships only if its terms explicitly permit
   automated collection *and* redistribution. An accessible webpage is not permission.

---

## 2. The original premise — and why it collapsed

> *Collect fresh intraday gold trade ideas from multiple independent publishers,
> compare them, and turn the strongest agreement into one 15M setup.*

**Every plausible idea publisher fails rule 5.** Signal sites, broker commentary,
forums, indicator communities — all prohibit automated collection and/or
redistribution. **Zero publishers have ever been enabled.** Eight obvious
candidates were formally rejected with reasons on record.

This is not an implementation gap. It is a **structural** finding: free,
automatable, redistributable *trade-idea publishers do not exist*.

---

## 3. What is built and genuinely working

Verified on a physical phone (Android 16 / SDK 36) against live data.

### 3.1 Market data pipeline
- Gold OHLC bars at 5M / 15M / 30M / 1H, ingested continuously.
- **600 closed 15M bars**; 1,292 × 5M; 343 × 1H; zero gaps.
- Genuine venue spread measured per tick (currently ~0.41 USD), never proxied
  from two different price feeds.

### 3.2 A rules-based multi-timeframe confluence scorer
Over 1H / 30M / 15M / 5M: trend alignment, RSI regime, MACD, market structure,
pullback-to-zone, 5M trigger, ADX, volatility suitability, overextension,
confirmation floor, stop distance, reward:risk — plus event-calendar and spread
vetoes. Produces an auditable verdict with the reasons listed.

### 3.3 Four weighted slow "sentiment layers" — three live
Weights are fixed by the project's methodology (§5.1).

| Layer | Weight | Live reading | Status |
|---|---|---|---|
| Fed policy (FOMC statement) | 35% | 25bp hike → 3.75–4.00%, raw −2 → **−1.03** after 20-day decay | **LIVE** |
| CFTC COT managed money | 25% | +120,318 net, **37.8th pctile of 156 weeks** → −1 | **LIVE** |
| US Treasury real yields | 20% | 10Y real **2.95%**, +5bp / 5 sessions | **LIVE** |
| World Gold Council demand | 20% | — | **DROPPED — licensing** |

All three live layers are **US-government public-domain sources** (Fed, CFTC,
Treasury). No account, no API key, no scraping restriction.

### 3.4 A side-aware macro overlay
Macro and positioning agree/disagree is resolved **relative to the traded side**.
A bearish macro credits a short and vetoes a long — it never vetoes the short it
favours. This bug existed and was fixed; it had been silently destroying the
short side.

### 3.5 Engineering quality
281 core tests · 213 app tests · 42 backend tests · both analyzers clean.
Bug-fix velocity has been good; correctness culture is strong and defect reporting
has been honest rather than hidden.

---

## 4. What is built but structurally empty

The **consensus engine** — the original headline feature.

- 1,078 signals were produced over 5 days, all from a single internal seed source.
- A **critical defect was found and fixed**: the independence guard counted
  *ideas*, not *publishers*, and the dedupe fingerprint included the author name.
  So one source posting 11 rows labelled `desk-a`/`desk-b`/`desk-c` passed a
  "≥2 independent sources" gate and published a **STRONG** setup with
  entry/SL/TP and a **"copy levels" button**.
- Fixed to count distinct source IDs, with internal seed sources excluded.
- **Result today: the consensus card is permanently `NO CONSENSUS`.** The
  consensus path cannot ever fire.

### Also not built
- Economic calendar: approximate fixtures, no licensed provider.
- Push notifications: no FCM sender.
- No store listing, no marketing, no users.

---

## 5. THE BLOCKER — the thing that may destroy the idea

### 5.1 The one-paragraph version

**XV's differentiator is unavailable and its fallback is undifferentiated.** The
reason to use XV over a free charting platform was "multiple independent
publishers agree." That is legally impossible at zero cost. What remains is a
technical filter — and free platforms ship twenty indicators with no signup.
Meanwhile **nothing in the app demonstrates that any of its scores have ever
predicted anything**, so a rational trader has no reason to prefer it over a free
chart.

### 5.2 The three layers of the problem

**(a) The premise is gone and cannot be engineered back.**
Rule 5 rules out every real-time idea publisher. The categories that *could*
legally supply ideas all break a hard constraint:
- *Licensed/contracted providers* — exist, but cost money; the product is free.
- *Own contributors* (opt-in community under our terms) — the one viable route,
  but a different business: moderation, sybil/independence problems, and
  **advice-hosting regulatory exposure**.
- *Open-licence institutional data* (US-gov, OGL, CC-BY) — legal, but yields
  research context, **not** 15M setups.
- *Broker positioning / prediction-market data* — usually restricts
  redistribution; and it is not publisher opinion anyway.

**(b) The fallback has no demonstrated edge, and cannot get one yet.**
The scoring engine is unvalidated. A 25bp Fed hike that was *already priced in*
is not mechanically bearish for gold; the −2 mapping and the 20-day linear decay
are **hypotheses inherited from a design document**, not measured facts.

Measurable history today:
```
600 closed 15M bars   ≈ 6 days
1,078 signals over 5 days (all from the now-blocked seed path)
```
**Six days cannot calibrate anything.** No backtest, no walk-forward, no
out-of-sample check has been performed because the data does not exist yet.

**(c) The UI still signals "act on this."**
Entry, stop, TP and a **"copy levels"** button function as a trade
recommendation, whatever the "not financial advice" disclaimer says. A green
`SETUP` with "technical 8/12, macro coverage 73%" reads as many independent
confirmations and implicitly as a high win rate. **Neither is true.**

### 5.3 A compounding honesty defect just confirmed

Counting 9–12 technical checks that all derive from the **same OHLC series**
(EMA, MACD, RSI, ADX, swings are near-duplicates) presents correlated inputs as
independent confirmations. **This is structurally the same error as the
`desk-a/b/c` bug, one level up** — the kind that erodes trust with anyone who
looks closely.

Two of the three live macro layers are also correlated: Fed policy and real
yields are not two independent confirmations.

### 5.4 The honest self-assessment

| Question | Honest answer |
|---|---|
| Does the technical engine work? | **Yes**, mechanically. |
| Does it have edge? | **Unknown. Untestable on current data.** |
| Is the consensus feature viable? | **No.** Structurally, not temporarily. |
| Is there a reason to use XV over a free chart? | **Not currently demonstrated.** |
| Could it be a real product? | **Yes — but only via one of two pivots (§6).** |

---

## 6. What would change the verdict

Only two paths survive:

**Path A — Own the filter.** Drop the consensus identity entirely. Be
*excellent* at one defensible thing: a transparent, timestamped, net-of-spread
record of what the engine said and what price then did — **including its
`NO TRADE` calls**. The moat is not indicator logic (commoditised); it is an
auditable track record nobody else publishes. Requires: 3+ months of outcome
recording, an honest `UNVALIDATED` state until the record exists, and removal of
the "copy levels" action.

**Path B — Become a venue.** Build the contributor community that makes real
independent ideas legally obtainable. Higher ceiling, much higher operating and
regulatory risk, and a different company.

**Path C — Fold it.** Treat the engine as a component inside someone else's
product, where it is one filter among many and needs no differentiation.

Everything else is incremental work on a product whose reason to exist is
unresolved.

---

## 7. Decisions already locked (for reference)

| # | Decision |
|---|---|
| D-20261005-001 | 8 publisher candidates rejected on licensing grounds |
| D-20261005-003 | Methodology document is the implementation base |
| D-20261005-007 | Macro/sentiment overlay must be side-aware |
| D-20261006-002 | **Independence counted in sources, not ideas** (critical fix) |
| D-20261006-004 | **WGC fails the licensing gate — layer dropped.** Personal non-commercial use only; scraping/redistribution need written authorisation; 2010–13 data synthesised from Thomson Reuters |
| — | Seed fixture data can never satisfy the independence gate |

---

## 8. What we need from you

Please answer these directly. Disagreeing with the framing above is more useful
than agreeing with it.

1. **Is §5 honest?** Is there a reason to use XV over free charting that we have
   failed to see? If not, should the project be paused or pivoted?
2. **Path A, B or C** — or a fourth option? What would change your answer?
3. **Is Path A's moat real?** Is "public, timestamped, net-of-spread track
   record including NO TRADE calls" defensible, or is that table also free?
4. **Should we suppress levels entirely** until there is data to validate them?
   Is "ship as research, no copy action, `UNVALIDATED` badge" honest enough, or
   is publishing levels at all premature?
5. **Is six days of history fixable?** Roughly how much 15M history with spread
   would be needed before any claim of edge is credible — and can it be
   backfilled, or must it be collected forward?
6. **The `desk-a/b/c` class of error** — what structural safeguard, beyond tests
   and code review, prevents a fabricated feed from ever being published again?
7. **If you were the owner: continue, pause, or pivot?** One line, then the
   single reason that decides it.

---

## Appendix — verification snapshot (2026-10-06)

```
app version installed   1.0.8 (code 9), Android 16 / SDK 36
live price              4,162.98
15M closed bars         600   (from 2026-09-30, zero gaps)
1H / 30M / 5M bars      343 / 424 / 1,292
sources registered      1  (manual-seed, internal:// — a placeholder)
publishers enabled      0
consensus outcome       NO_CONSENSUS / SINGLE_SOURCE
  independence          {ideas:10, distinct_sources:1,
                         distinct_external_sources:0, internal_seed_sources:1}
macro coverage          73% of 75 (will become 100% of 55 once WGC's 20 is removed)
tests                   281 core · 213 app · 42 backend · analyzers clean
```