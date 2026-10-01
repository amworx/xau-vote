# Free-Tier Research — Sources & Findings (v2, empirically verified)

**Date:** 2026-10-02 · **Supersedes** v1 of the same file.
**Method:** Duck.ai consultation → ROK Chat (rok-hermes) second opinion → **every provider
tested live from this machine** → doc cross-check. Claims are marked by how they were verified.

**v2 exists because live testing overturned two v1 recommendations.** Both are noted below.

---

## 1. Supabase limits (verified from official docs)

| Limit | Value | Source |
|---|---|---|
| Edge Function invocations | **500,000 / month** | [pricing](https://supabase.com/pricing) |
| Max functions per project | 100 (Free) | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Wall clock per worker | 150s Free / 400s paid | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| **CPU time per request** | **2s** (excludes async I/O) | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Memory | 256 MB | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Function size via API deploy | 5 MB | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| DB / egress / log retention | 500 MB · 5 GB/mo · **1 day** | [pricing](https://supabase.com/pricing) |
| Idle pause | **7 days** of low activity | [free-project-pausing](https://supabase.com/docs/guides/platform/free-project-pausing) |
| pg_cron concurrency | ~8 recommended, 32 max; **skipped runs not retried** | [cron](https://supabase.com/docs/guides/cron), [debug guide](https://supabase.com/docs/guides/troubleshooting/pgcron-debugging-guide-n1KTaz) |

**Confirmed by both consultations:** invocation quota is *not* the constraint (57,600/mo =
11.5% of 500k). The **2s CPU ceiling** is the real one, because our functions make 4–6
sequential PostgREST round-trips (`tick` alone makes ~6).

**Action (agreed by both advisors):** collapse round-trips — one read query, compute locally,
one write. Longer term, move the consensus/lifecycle logic into Postgres functions so Edge
Functions become thin triggers. That also makes the CPU cost independent of network latency.

## 2. The 7-day pause — biggest operational risk, both advisors agreed

- Pausing **stops cron**, so the pipeline dies and the app shows stale/empty data with no error.
- Pause is driven by low **user-initiated** DB activity. Background writes from Edge Functions
  may not count — our pipeline is a closed loop, so it can talk to itself forever and still
  be judged inactive.
- **No API exposes the paused state.** Only detectable via logs or a failed cron call.
- **Mitigations:** (a) daily heartbeat write to a small table; (b) external scheduler
  (GitHub Actions / Cloudflare Workers) calling the function URLs; (c) Pro $25/mo removes pause.

**Decision:** implement the heartbeat now (trivial, free). Revisit Pro when the app has real users.

## 3. Gold price (Gate G3) — **v1 was wrong twice**

Live tests from this machine, 2026-10-01:

| Provider | Endpoint tested | Result |
|---|---|---|
| gold-api.com | `api.gold-api.com/price/XAU` | ✅ **200, live price 4178.5**, no key, no signup |
| xaus.com | `xaus.com/api/v1/spot` | ✅ 200, price + per_gram + gold/silver ratio |
| xaus.com | `xaus.com/api/v1/intraday?hours=2` | ✅ 60 points, 2-min interval, `data_state: fresh` |
| **goldprice.dev** | `goldprice.dev/v1/prices/...` | ❌ **404 — wrong host** |
| goldprice.dev | `api.goldprice.dev/v1/prices?symbol=XAU-USD-SPOT` | ✅ 200 → `{"price":"4177.80","is_stale":false,"computed_at":...}` |
| Alpha Vantage | `GOLD_SILVER_SPOT&symbol=GOLD` | ⚠️ endpoint exists (`GOLD`/`XAU` accepted) but demo key refused; endpoint is tagged **Premium** in their docs |

### Two corrections to v1

1. **goldprice.dev does NOT return bid/ask.** Its site advertises "price, bid, ask"; the actual
   JSON is `{symbol, quote_currency, unit, contract_type, price, is_stale, computed_at}` —
   **no bid/ask fields**. My v1 claim that it was the only free source with bid+ask was wrong.
2. **The correct host is `api.goldprice.dev`**, not `goldprice.dev` (v1 had the wrong host; a
   literal implementation of the v1 recommendation would have 404'd on first call).

### Recommendation for G3

**Primary: `gold-api.com`.** Verified working with no key, unlimited real-time calls, and
`tick` already has a `GOLD_API_KEY`-gated code path for it — zero new code. Set `GOLD_API_KEY`
once a key is issued; without a key the existing snapshot fallback keeps working.

Bid/ask stays **null** in `market_snapshots`. That is honest, not a gap: our consensus engine
uses a single mid price, and fabricating a spread would violate the never-fabricate rule.

**Secondary: `xaus.com`** — adds a genuine intraday series (2-min points) and per-gram
conversion, no key, and states it is free for "dashboards, widgets, personal projects, OSS"
with commercial >10k req/day requiring contact. Good future upgrade if we need history.

## 4. Economic calendar (Gate G5)

| Provider | Free quota | Actual+forecast | Redisplay allowed? |
|---|---|---|---|
| **FMP** | 250 calls/day | Yes | **Requires a Data Display & Licensing Agreement** |
| Trading Economics | guest key, limited | Yes | free = non-commercial |
| Forex Factory / Econoday | no official API | — | **scraping violates ToS — excluded** |

Quota is not the issue (we need ~24/day). **FMP stays gated** until the licensing position is
recorded in `memory/decisions.md`. The manual `ManualSeed` provider already covers the
guardrail path, and events never vote (rule 9), so this gate can stay closed safely.

## 5. News headlines (Gate G5) — ROK found what I missed

Both free *APIs* are unusable in production, confirmed from their own terms:
- **GNews** — "Free plan is for non-commercial projects, development and testing only."
- **NewsAPI** — "cannot be used in a staging or production environment (**including
  internally**)" and the license is revoked if integrated outside dev.

**The gap in my v1 analysis: I assumed there was no clean free option. ROK pointed out
publisher RSS/Atom feeds**, which are public, free, and aggregation-friendly. Headline + link
+ pubdate is exactly our `news_articles` shape.

Candidates raised by ROK to verify before adopting: **Currents API** and **NewsData.io**
(claimed free tiers permitting commercial use), plus **GDELT** (free global news stream) and
publisher RSS. I have **not** verified their terms — treat as leads, not facts.

**Decision unchanged in direction, better in option:** keep manual seeds now; the next step is
a `RssNewsProvider` behind the existing `GNEWS_ENABLED`-style gate, with the provider's terms
recorded before enabling.

## 6. Firebase Cloud Messaging — no action

No-cost on Spark, 600k msgs/min default quota, per-device cap 240/min. At 500–2,000/day we are
~0.003% of quota. Note: exceeding a Spark *no-cost quota* shuts the product off for the rest
of that calendar month — irrelevant at our volume.

---

## Open questions I could not settle

| Question | Why unresolved |
|---|---|
| Does an Edge Function write count as "user activity" against the 7-day pause? | Not documented; ROK asserts no, Supabase docs are silent. Empirically testable after 7 days. |
| Currents / NewsData / GDELT commercial-use terms | Not yet read from their ToS. |
| gold-api.com paid-tier price & whether a key is needed for higher rates | Not checked; irrelevant while anonymous access works. |

## Sources

Supabase: [pricing](https://supabase.com/pricing) · [functions/limits](https://supabase.com/docs/guides/functions/limits) · [free-project-pausing](https://supabase.com/docs/guides/platform/free-project-pausing) · [cron](https://supabase.com/docs/guides/cron) · [pgcron debugging](https://supabase.com/docs/guides/troubleshooting/pgcron-debugging-guide-n1KTaz)
News: [gnews.io/faq](https://gnews.io/faq) · [gnews.io/pricing](https://gnews.io/pricing) · [gnews.io/terms](https://gnews.io/legal/terms-of-service) · [newsapi.org/terms](https://newsapi.org/terms) · [newsapi.org/pricing](https://newsapi.org/pricing)
Calendar: [FMP pricing](https://site.financialmodelingprep.com/developer/docs/pricing) · [FMP economic-calendar](https://site.financialmodelingprep.com/developer/docs/stable/economics-calendar)
Gold: [gold-api.com](https://gold-api.com/) · [goldprice.dev](https://goldprice.dev/) · [xaus.com/api](https://xaus.com/api/) · [alphavantage.co/documentation](https://www.alphavantage.co/documentation/)
Push: [FCM throttling-and-quotas](https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas) · [Firebase pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans)
Second opinion: rok.rokteam.org/chat (rok-hermes) and Duck.ai (Claude Haiku 4.5)
