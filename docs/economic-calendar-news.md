# Economic Calendar & News Intelligence — Feature Addendum

- **date:** 2026-09-27
- **status:** proposed (pending user approval + per-source licensing reviews)
- **parent spec:** `docs/mvp-specification.md` (unchanged — this doc extends it)
- **drives:** `tasks/TASK-07_economic-calendar-news.md`

> Gold doesn't move in a vacuum. NFP, CPI, and FOMC routinely invalidate
> the best 15M technical agreements. This feature makes XAU Radar aware of
> scheduled events and the news flow around them — as **context and guardrails**,
> never as direction votes.

---

## 1. Non-negotiable principles (extend AGENTS.md core rules)

1. **Events and news NEVER vote.** Direction, entry, SL, TP come only from the
   15M idea consensus (spec §6). Event/news data can suppress, delay, annotate,
   or explain a signal — never create or flip one.
2. **AI summarizes; it does not forecast.** AI may digest headlines into themes
   ("hawkish Fed repricing") and attach them as context. It must never invent a
   direction, level, or probability from news.
3. **Prefer silence over noise.** No event → no banner. No consensus + event →
   still NO CONSENSUS (never "event trade" suggestions).
4. **Every source gated.** Same licensing rule as idea sources: no production
   adapter without a recorded review in `memory/decisions.md`.

---

## 2. Event Guard (the core — works with calendar data alone)

High-impact USD events destroy intraday technical setups. The guard:

```
HIGH event (USD, impact=high: NFP, CPI, FOMC, Fed Chair, PPI, Retail Sales…)
  → BLACKOUT: no NEW consensus signals from T−30 min to T+15 min
  → OPEN signals: kept, but badged "⚠ NFP in 12m — manage risk"
  → Radar shows countdown banner, not a signal card

MEDIUM event (USD medium, or HIGH non-USD affecting gold: ECB, BoE, geopolitics)
  → CAUTION badge on any active/developing setup, no blackout

LOW event → ignored (stored only, for history/audit)
```

- Blackout windows are configurable in Settings (defaults above).
- After blackout lifts, the pipeline rebuilds consensus from fresh ideas only —
  pre-event ideas are treated as stale (freshness filter already covers this).
- Every suppression is logged (event id → suppressed signal attempt) for audit.

---

## 3. News Intelligence (enhancement layer, needs AI + news source)

Goal: a clearer read of *why* the market leans a way — displayed, not traded on.

### 3.1 Collection

- Query set (gold-relevant macro): `gold`, `XAUUSD`, `Federal Reserve`,
  `FOMC`, `CPI inflation`, `NFP payrolls`, `ECB rates`, `US dollar index`,
  plus a geopolitics watchlist (editable in Settings later; hardcoded in MVP).
- Cadence: every 30 min (fits free-tier quotas), dedupe by URL + title hash.
- Store raw: `news_articles(id, source, url, title, summary, published_at,
  collected_at, query_tag, fingerprint)` — link-out preserved (never present
  publisher text as our own).

### 3.2 Digest (AI-assisted, constrained)

- Scheduled digest (hourly): cluster today's articles → 3–5 themes with
  **USD-pressure reading per theme**: `HAWKISH / DOVISH / NEUTRAL` + one-line
  evidence (headline link). Stored in `news_digests`.
- Hard constraints (mirror spec §23):
  - output schema is fixed: `{ theme, pressure, evidence_urls[] }` — no free prose
    reaches the consensus engine;
  - pressure is **display-only context** (a "Macro backdrop" strip on Radar);
  - if extraction is uncertain → theme marked `UNCLEAR`, never forced.

### 3.3 Surprise tracking (no AI needed)

- Calendar results carry actual vs forecast. Surprises (|actual − forecast| beyond
  per-indicator threshold, e.g. NFP ±50K, CPI ±0.2pp) generate:
  - an `event surprise` entry on the Events screen,
  - optional notification,
  - a context flag on any signal formed within 60 min after ("formed post-CPI surprise").

---

## 4. Notifications (additions to spec §16)

| Trigger | Message |
|---|---|
| HIGH event in 60 min | `⚠ NFP (USD, HIGH) in 60 min — new signals paused 30 min before.` |
| HIGH event in 15 min | `⚠ NFP in 15 min — blackout active.` |
| Blackout lifted | `Event window passed — scanning for fresh 15M consensus.` |
| Surprise result | `CPI surprise: 3.4% vs 3.1% forecast — expect volatility.` |
| News spike (optional, default off) | `Unusual gold-news volume in the last hour.` |

All include timestamp; event ones include event time + impact. Respects the
existing notification toggles + adds an "Events" toggle group in Settings.

---

## 5. UI changes

### 5.1 Radar screen — event banner (replaces signal card during blackout)

```text
┌──────────────────────────────┐
│ ⚠ HIGH-IMPACT EVENT          │
│   NFP — Non-Farm Payrolls    │
│   USD · HIGH · in 00:12:41   │
│                              │
│   New signals paused until   │
│   15 min after release.      │
│                              │
│   [ VIEW EVENTS ]            │
└──────────────────────────────┘
```

- Countdown ticks (1s resolution, no animation library needed).
- Below the banner: "Macro backdrop" strip (from latest digest):
  `Hawkish Fed repricing · Dovish ECB · Neutral Asia` — tap → Events screen.
- Normal consensus card gains a one-line event context when a MEDIUM event is
  near: `Caution: ECB decision in 42m`.

### 5.2 New screen 6 — Events (spec §24 grows 5 → 6 screens)

- **Upcoming**: chronological HIGH/MEDIUM USD (+HIGH major) events, 7-day window.
  Each row: time (local), flag/currency, title, impact pill, forecast/previous
  (when known), countdown for the next one.
- **Results**: past events with actual vs forecast + surprise highlight.
- **Macro backdrop**: latest digest themes with pressure pills + evidence links.
- **Gold news**: latest collected headlines (title + source + age + open-original).
- Out of scope: full articles in-app (always link out), custom alerts per event
  (deferred), non-USD minor events list (stored, hidden by default filter).

### 5.3 Settings additions

```text
Events
    Blackout before HIGH event      [ 30 min ]
    Blackout after HIGH event       [ 15 min ]
    Notify: 60-min warning          [ on ]
    Notify: 15-min warning          [ on ]
    Notify: surprises               [ on ]
    Notify: news spikes             [ off ]
```

---

## 6. Data model additions (extends spec §21)

```text
economic_events
───────────────
id
provider            -- 'fmp' | 'manual' | (gated: 'forexfactory')
external_id
title
currency            -- USD focus; others stored
impact              -- HIGH | MEDIUM | LOW
starts_at
actual
forecast
previous
surprise            -- computed post-release, nullable
url                 -- provider/source link
collected_at

news_articles
─────────────
id
source_name
url                 -- unique
title
summary
published_at
collected_at
query_tag
fingerprint         -- dedupe

news_digests
────────────
id
window_start
window_end
themes              -- jsonb [{ theme, pressure, evidence_urls[] }]
created_at
```

Indexes: `economic_events(currency, impact, starts_at)`,
`news_articles(collected_at)`, `news_articles(fingerprint)` unique.

---

## 7. Backend additions (extends spec §22 pipeline)

```
fetch-events (hourly + on boot)
   → FMP economic-calendar (USD + majors, 7-day window)
   → normalize → upsert economic_events
   → compute blackout windows → cache "guard state"

news-collect (every 30 min)
   → news provider search (query set §3.1)
   → dedupe → store news_articles

news-digest (hourly, AI)
   → cluster → constrained schema → store news_digests

build-consensus: reads guard state → suppresses new signals in blackout,
                 attaches event context to developing signals
tick:            drives countdowns, blackout lift, surprise detection
                 (actuals appear), dispatches event notifications
```

---

## 8. Providers & licensing status (must-read)

| Provider | Use | Free tier | Commercial? | Status |
|---|---|---|---|---|
| **FMP** economic calendar | Events (primary) | ~250 req/day — plenty (1–2 fetches/day cover a week) | Review required | **CANDIDATE — Gate G5** (verify current terms, record review before enabling) |
| **GNews** | News (dev/test) | 100 req/day, 10 articles/req, 12h delay | **Free = non-commercial only** | Dev/test only; production needs paid plan or alternative |
| **ForexFactory** calendar (scrape/XML) | Events (fallback) | N/A (no API) | Gray area + Cloudflare blocks | **GATED OFF** — same rule as idea sources; stays disabled unless a review explicitly passes it |
| **ForexNewsAPI** (news+sentiment+calendar beta) | All-in-one candidate | Unknown | Unknown | **UNVETTED** — verify pricing + terms before any use |
| **MarketAux** free | News + sentiment candidate | Free plan exists | Unknown | **UNVETTED** — verify terms before any use |
| **Manual curation** | News + events fallback | N/A | Always allowed (human pastes) | **Always available** — same fallback pattern as idea sources; keeps the feature shippable with zero providers |

Quota math (free tiers): events need ~2 req/day (FMP, well under 250).
News at 30-min cadence × ~8 queries = ~384 req/day — **over** GNews free (100/day).
Mitigations: 2–3 batched queries per cycle, hourly cadence (~72/day ✓), or fewer
queries. Final query plan fixed at implementation time against the chosen tier.

**Copyright rule:** headlines + links + our own one-line theme labels only.
Never store or display full publisher article text.

---

## 9. Acceptance criteria (extends spec §25)

```text
16. Fetch upcoming USD HIGH/MEDIUM events
        ↓
17. Display countdown + suppress new signals inside blackout
        ↓
18. Lift blackout and resume scanning automatically
        ↓
19. Notify 60m + 15m before HIGH events
        ↓
20. Record actuals; flag surprises; annotate post-event signals
        ↓
21. Collect news; dedupe; show headlines with source links
        ↓
22. Produce hourly constrained digest; display macro backdrop
        ↓
23. Prove events/news NEVER create or flip a signal
        (regression: event storm + no consensus → still NO CONSENSUS)
```

---

## 10. Rollout order (risk-first)

1. **Event Guard + Events screen with FMP** (or manual seed) — value without AI.
2. **Notifications** for events.
3. **News collection + headlines tab** (no AI yet).
4. **AI digest + macro backdrop** (last — needs the most guardrails).

Each step shippable independently; step 1 alone already prevents the
most expensive failure (trading into NFP on a technical signal).
