# Consultation brief — XV (XAU-Vote) source architecture

**For:** an independent expert. **From:** the XV project owner.
**Length budget:** please answer each numbered question directly; skip pleasantries.

---

## 1. What this product is

XV is a free, Android-first XAUUSD (spot gold) **15-minute** setup-analysis app.
It is explicitly **not** a predictor and executes no trades. Core product rules,
which are not negotiable and which the answer must respect:

1. **15M is the only signal timeframe.** 5M is confirmation only; 1H is context
   and never votes.
2. **Never fabricate.** If agreement or data is insufficient the app shows
   `NO CONSENSUS` / `NO TRADE`. It may never manufacture a direction, level, or
   probability.
3. **Consensus score is agreement, not probability.** Never render as "% chance".
4. **Independence is strict.** Copied or duplicate ideas count as ONE vote.
   Unknown independence never counts as independent.
5. **Licensing gate.** A source may only ship after its terms explicitly permit
   automated collection and redistribution. An accessible webpage is not
   permission.

## 2. The original premise, and why it no longer holds

The product was conceived as: *collect fresh intraday gold trade ideas from
multiple independent publishers, compare them, and turn the strongest agreement
into one 15M setup.*

That premise is now unbuildable. Every obvious idea publisher (signal sites,
broker commentary pages, social/forum threads, indicator communities) either
prohibits automated collection or prohibits redistribution. **Zero** of them
passed review. No publisher has been enabled, and none currently can be.

## 3. What was built instead — and it works

A separate, genuinely working engine now exists. It is a **macro-filtered
multi-timeframe technical analyser**:

- **Market data:** gold OHLC bars at 5M/15M/30M/1H, plus a genuine venue spread.
- **A rules-based confluence scorer** over 1H/30M/15M/5M: trend alignment, RSI
  regime, MACD, market structure, pullback-to-zone, 5M trigger, ADX, volatility
  suitability, overextension, confirmation floor, stop distance, reward:risk,
  plus event-calendar and spread vetoes.
- **Four weighted slow "sentiment layers"** from public-domain government data
  (weights are fixed by the methodology):
  - Fed policy — parsed from the FOMC statement's own decision sentence.
    Currently live: a 25bp hike → raw −2, decayed to −1.03 over 20 days.
  - CFTC Commitments of Traders, managed money, scored against a 156-week
    percentile. Live: +120,318 contracts net, 37.8th percentile → −1.
  - US Treasury real-yield curve. Live: 10Y real 2.95%, +5bp/5 sessions.
  - World Gold Council demand data — **not yet ingested**.
- Macro alignment currently resolves at **73% coverage**; below a 50% coverage
  gate it is deliberately withheld rather than guessed.

On live data this produces verdicts like `NO TRADE / FILTERING`, technical
5/12, final 8.0, with an explicit statement of *why*.

## 4. The problem to solve

The app therefore now has **two engines with completely different maturity**:

| Engine | State |
|---|---|
| Multi-timeframe analysis (technical + macro layers) | Real, live, working |
| Publisher consensus | **Zero inputs.** Always `NO CONSENSUS`. |

And the headline UI element — the "15M Consensus Setup" card — is permanently
empty. Users open the app to that card and see nothing.

There is also a **live-seeding** problem: a cron job seeds synthetic fixture ideas
every 15 minutes (hard-coded levels offset from price, templated reasoning,
three invented author names) to keep the pipeline exercised. These are now
correctly blocked from ever producing a published setup, but they remain in the
database and look superficially like publisher output.

**A recent bug is instructive:** the consensus engine guarded independence with
`if (ideas.length < MIN_INDEPENDENT_SOURCES)`. It counted *ideas*, not
*publishers*, and the dedupe fingerprint included the author name — so one source
posting 11 rows labelled `desk-a/b/c` passed a "2 independent sources" gate and
published a STRONG setup with entry/stop/TP and a "copy levels" button. Fixed to
count distinct source IDs, with internal seed sources excluded. The point: any
"source" surface will eventually be fed by whatever is easiest to generate, so
the gate must be structurally trustworthy rather than nominally present.

---

# Questions

**Q1 — Product identity.** Given that publisher consensus is structurally
unavailable, is it honest and commercially coherent to keep a product called
"consensus"? Or is it a bait-and-switch, and should the consensus feature be
**removed** rather than shown as permanently empty? Argue both sides, then
recommend one.

**Q2 — The empty card.** If the consensus feature stays, what should that card
show? Options: (a) remove it; (b) keep `NO CONSENSUS` and explain *why* no
publisher can legally be used; (c) repurpose the card to show the macro layers as
"what is actually informing this". Which, and what specifically should it say?

**Q3 — The Sources tab.** It currently lists publishers (all rejected/absent).
Should it instead present the methodology's **source stack** — the seven or so
P0/P1 public-domain layers with, for each: what it measures, weight, current
reading, as-of date, staleness, and licensing basis? Is that honest reframing, or
does calling macro data feeds "sources" mislead a trader?

**Q4 — Seed data.** What should happen to synthetic fixture ideas on a production
path: (a) relabel explicitly as demo fixtures, visible as such everywhere they
appear; (b) stop generating them entirely; (c) leave them but rely solely on the
gate? Consider that a trader could mistake seeded rows for a real publisher view.

**Q5 — Longest-term.** If publisher consensus is unbuildable under these
licensing constraints, is the strongest remaining moat **depth of the macro +
technical engine** (i.e. be excellent at filtering, not at aggregating)? Or is
there a category of publisher that *does* permit automated redistribution and
would change the answer? Be specific if so.

**Q6 — Risk.** What is the single most likely way this product misleads a
retail trader, given everything above? What is the one safeguard we are missing?

---

## Please answer in this shape

For each question: **Recommendation** (one line) · **Reasoning** · **Risks /
what would change the answer** · **Alternative** · **Confidence** (high /
medium / low) · **Assumptions you had to make**.

Flag clearly if you think a premise above is wrong. Disagreeing is more useful
than agreeing.