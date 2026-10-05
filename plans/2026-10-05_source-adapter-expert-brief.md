# Expert brief: sourcing independent intraday trade ideas for XV (XAU-Vote)

**Prepared:** 2026-10-05
**Status:** open product question, blocking the app's core value
**Repo:** `C:\Users\HP\Documents\code_repo\xau-vote`

---

## 1. What the product is

**XV (XAU-Vote)** is a free, mobile-first, Android-only assistant for **XAUUSD (Gold spot)**.
It collects fresh intraday trade ideas from multiple independent sources, compares them,
and turns the strongest agreement into **one** clear 15-minute setup.

It does **not** execute trades and does **not** predict the market.

Stack: Flutter app + Supabase (Postgres, Edge Functions, pg_cron). Pure-Dart engines
(`xau_core`, `xau_lifecycle`, `xau_data`) are the source of truth; a TypeScript port backs
the Edge Functions. Android release builds are signed and distributed in-app via a Supabase
storage bucket.

Live deployment: Supabase project `mfrzwmqgwgcyaxehdbqh`.

---

## 2. The problem

The app's entire premise is **agreement between independent sources**. In production it
currently has exactly **one** publisher, and it is our own:

| Field | Value |
|---|---|
| `sources.name` | `manual-seed` |
| `sources.enabled` | `true` |
| `sources.commercial_use_allowed` | `true` |
| `sources.automation_allowed` | `true` |
| view `eligible_external_sources.is_eligible_external` | **`false`** |

All trade ideas on every signal are attributed to `manual-seed`. Because our own model can
never count as an independent vote, eligible external sources = **0**, and the Sources screen
correctly reports `INTERNAL ONLY` with `0 / 0` agreement.

**So the consensus engine has nothing to reach consensus about.** The UI is honest about it,
which is why the problem reads as cosmetic — it is not. Every part of the machinery (15M
voting, fingerprint dedupe, independence weighting, signal lifecycle) is built, tested and
correct; the *input* is not independent.

### 2.1 Secondary symptom from the same root cause

The History screen shows **~50 identical `EXPIRED` rows, each `+1200 PIPS`, generated every
5 minutes, including while the market was closed for the weekend**. With a single internal
seed and no independent confirmation, the pipeline emits a signal on a timer rather than
because anything actually agreed. It manufactures the appearance of a trade log. This is
believed to be the same root cause rather than a separate bug, but has not been formally
diagnosed.

---

## 3. Current data state (verified against production)

| Table | Rows | Notes |
|---|---|---|
| `sources` | 1 | `manual-seed` only |
| `trade_ideas` | 64 | all `source_id = ba38d066-…` (`manual-seed`) |
| `consensus_signals` | 596 | newest every ~5 min, `strength` 76–82 |
| `signal_sources` | 3033 | 10 links per recent signal |

Recent signal statuses: `READY`, and many `EXPIRED`.

### Relevant schema

```text
sources(id, name, url, license_url, automation_allowed,
        commercial_use_allowed, enabled, created_at)

trade_ideas(id, source_id, symbol, timeframe,          -- check: M5|M15|H1
            direction, entry_low, entry_high, stop_loss,
            take_profits jsonb, trigger_condition, invalidation_condition,
            reasoning, author, published_at, collected_at,
            fingerprint, model_owner,                  -- us | third_party | unknown
            upstream_dataset_id, methodology_id, event_window, author_ref)

signal_sources(signal_id, trade_idea_id, independence_weight, contribution_score)
```

Note `model_owner`, `upstream_dataset_id` and `methodology_id` already exist and are
populated — the independence/provenance model is fully implemented, only unused in anger.

---

## 4. What the project documentation specifies

**Market data — named, implemented:**
- P1 OANDA fxTrade **Practice** API v20 (`api-fxpractice.oanda.com`, M5 candles, streaming)
- P1b MT5 · P2 Binance PAXG (cross-check only) · P3 Yahoo · P4 Twelve Data (fallback) · P5 Dukascopy (backtest)
- Source: `docs/expert-integration-spec.md:92, 128`

**Economic calendar — named, partly gated:**
- C1 ForexFactory weekly JSON `https://nfs.faireconomy.media/ff_calendar_thisweek.json`
  (impact + consensus, **contains no actuals**; Cloudflare/rate-limit risk)
- C2 BLS · C3 BEA · C4 Federal Reserve · C5 FRED — **the authority for dates/times**
- `docs/economic-calendar-news.md:225` marks ForexFactory **GATED OFF**, explicitly
  "same rule as idea sources"
- `docs/expert-integration-spec.md:93, 133, 206`

**Trade ideas — architecture only, no names:**
`docs/mvp-specification.md:649-652`
```text
IdeaSource
    ├── SourceAdapterA
    ├── SourceAdapterB
    ├── SourceAdapterC
    └── SourceAdapterD
```
`docs/mvp-specification.md:689` says only *"Free provider with compatible commercial terms."*

**Explicitly NOT signal sources:**
`instruction/XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md:58` lists TradingView and
Investing.com as **"Visual verification only"**.

**Conclusion:** market-data and calendar providers were specified and largely built. The
**trade-idea publisher roster was never named**. That is the gap.

---

## 5. Hard constraints (non-negotiable, from the spec)

1. **15M is the only voting timeframe.** 5M confirms. 1H/30M/daily/news are context and
   must **never** vote. So an M5/M15 idea publisher is required; a weekly source cannot help.
2. **Never fabricate.** Missing data renders `NO CONSENSUS` / `INSUFFICIENT DATA`. Levels,
   spread, probability and independence must never be invented.
3. **Source independence (rule 3).** Copied or duplicate ideas count as **one** vote.
   Dedupe by direction, levels, wording, author, timing and source relationships
   (fingerprint + independence factor).
4. **Consensus score is agreement, not probability.** It must never be displayed as
   "X% chance of profit".
5. **AI is not the trading engine.** AI may summarise, extract or detect copies. It must
   never invent Entry, SL, TP or direction. Unextractable values → `INSUFFICIENT DATA`.
6. **Licensing gate (rule 6).** Every production source adapter must pass a
   **licensing/automation review recorded in `memory/decisions.md`** before it is enabled.
   *"An accessible webpage is not automatically permission to scrape or redistribute it."*
7. **Freshness is first-class.** Ideas carry `publishedAt`/`expiresAt`; stale ideas are
   rejected or demoted to context.
8. **Provider abstraction.** Sources live behind interfaces with mock providers for dev/test.
9. **Events and news are context, never votes.**

---

## 6. What is being asked of you

### Primary question

**Which XAUUSD intraday (M5/M15) trade-idea publishers can legally and practically be
collected automatically and redistributed inside a free consumer mobile app?**

For each candidate, please state:

- Provider name and what it actually publishes (free social posts? paid terminal? broker
  research? community forum?)
- **Licence / Terms of Service position** on: automated collection, scraping, and
  redistribution of derived signals to third parties
- Whether an **official API** exists, and whether it is free or paid
- Whether it is genuinely **independent** (i.e. separate model owner / methodology), or a
  syndication of one upstream source — this matters more than the count
- Practical limits: rate limits, Cloudflare/anti-bot, paywall, geographic restriction,
  auth/registration burden, data latency vs the 15M bar
- Indicative cost if paid, and whether a free tier is viable for an alpha

### Secondary question

If genuinely independent intraday idea publishers are **not obtainable** legally or
practically — which is our working assumption — then **how should the product be repositioned
so it is still honest and useful?**

Specifically:

- Is a **multi-strategy internal ensemble** a legitimate substitute? e.g. several distinct
  internal models (trend / mean-reversion / breakout / structure) each publishing an opinion,
  compared against each other and labelled `INTERNAL ONLY`, never as independent consensus?
  What would that be honestly called in the UI, and what must it **not** be allowed to claim?
- Which **public-domain or officially-published** gold datasets could add genuinely
  independent *context* (e.g. CFTC Commitments of Traders, LBMA prices, central-bank
  disclosures)? Please note these cannot vote under rule 1 — we want to know what is
  legitimately available anyway.
- What is the minimum honest set of adapters before the product's core claim is defensible?

### Deliverable requested

A prioritised shortlist with licence reasoning, plus a recommended path. Please **cite
licence/ToS sources** and flag anything you are uncertain about rather than asserting it.
We would rather have "unverified, needs legal review" than a confident guess — a wrong
answer here puts the whole product at risk.

---

## 7. Where to look in the repo

```text
AGENTS.md                                  project rules
docs/mvp-specification.md                 authoritative spec (esp. §4, §17, §18, §19)
docs/expert-integration-spec.md            ratified integration decisions (:92, :93, :128)
docs/economic-calendar-news.md             calendar decision + gating (:157, :225)
instruction/XAUUSD_IMPLEMENTATION_READY_METHODOLOGY.md   expert methodology
memory/decisions.md                        licensing/automation reviews live here
src/xau_core/                              pure-Dart engines (source of truth)
src/app/lib/data/live_repository.dart      Supabase reads
src/app/lib/screens/sources_screen.dart    Sources screen
supabase/functions/                        analysis-scan, warm-bars, oanda-quote, app-release
```

---

## 8. Important framing

We are **not** asking for help scraping. We are asking which sources may lawfully be used
automatically. If the honest answer is "independent intraday consensus is not legally
obtainable at this scale", we want to hear that plainly so the product can be repositioned
truthfully — the app already refuses to display agreement as probability and refuses to
count our own model as independent, and we would rather reposition than compromise that.