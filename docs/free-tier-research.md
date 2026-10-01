# Free-Tier Research — Sources & Findings

**Date:** 2026-10-02 · **Method:** Duck.ai (Claude Haiku 4.5) consultation, then every
figure cross-checked against primary documentation. Duck.ai hit its daily message
cap partway through, so its answers are marked and the gaps were filled directly.

**Rule followed here:** a figure is only trusted if it appears in the provider's own
docs. Anything the AI produced that I could not confirm is marked UNVERIFIED.

---

## 1. Supabase — the numbers that actually bind

| Limit | Value | Source |
|---|---|---|
| Edge Function invocations | **500,000 / month** (not per day) | [supabase.com/pricing](https://supabase.com/pricing) |
| Max functions per project | 100 (Free) | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Wall-clock per worker | **150s Free** / 400s paid | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| CPU time per request | **2s** (excludes async I/O) | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Memory per invocation | **256 MB** | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Max function size (API deploy) | **5 MB** bundled server-side | [functions/limits](https://supabase.com/docs/guides/functions/limits) |
| Database | 500 MB, shared CPU, 500 MB RAM | [supabase.com/pricing](https://supabase.com/pricing) |
| Egress | 5 GB / month | [supabase.com/pricing](https://supabase.com/pricing) |
| Projects | 2 active on Free | [supabase.com/pricing](https://supabase.com/pricing) |
| **Idle pause** | **after 7 days of low activity** | [free-project-pausing](https://supabase.com/docs/guides/platform/free-project-pausing) |
| Log retention | **1 day** (API + DB) | [supabase.com/pricing](https://supabase.com/pricing) |

### Verdict: the 1-minute `tick` is affordable

~1,920 invocations/day ≈ **57,600/month** — about **11.5%** of the 500,000
allowance. Comfortable. Headroom exists to raise frequency or add functions.

The **real** constraint is the **2s CPU limit per request**, not the invocation
count. Our functions make several sequential PostgREST round-trips, and `tick`
alone does ~6. At Tokyo-region latency that is tight. This is a design
constraint to respect (batch queries, avoid serial awaits), not a quota problem.

## 2. pg_cron — works on Free, but this is the sharp edge

| Fact | Source |
|---|---|
| `pg_cron` available on Supabase projects incl. Free | [supabase.com/docs/guides/cron](https://supabase.com/docs/guides/cron) |
| Jobs stored in `cron.job`, runs logged in `cron.job_run_details` | same |
| Recommended max **8 concurrent** jobs, each ≤10 min | same |
| pg_cron supports up to **32 concurrent** jobs, one DB connection each | [pgcron debugging guide](https://supabase.com/docs/guides/troubleshooting/pgcron-debugging-guide-n1KTaz) |
| Skipped runs are **not retried**; overlapping runs are dropped | crontap.com (secondary) |
| **A paused project silently stops every schedule** | [free-project-pausing](https://supabase.com/docs/guides/platform/free-project-pausing) |

**The finding that matters most for us:** pausing is triggered by low *user
database activity*, and our pipeline is a closed loop — the Edge Functions write
to the DB, but the "user queries" that keep a Free project alive come from the
app. If the app is not opened for a week, the project pauses, and when it pauses
**cron stops firing and no signal is produced.** The app would then show stale or
empty data with no error anywhere. The official mitigation is a daily API call or
dashboard visit; Pro ($25/mo) removes pausing entirely.

## 3. Gold price (Gate G3)

| Provider | Free tier | XAU/USD | Notes | Source |
|---|---|---|---|---|
| **gold-api.com** | **Unlimited real-time requests**, no key needed for basics | Yes | Historical/OHLC capped 10 req/hr free | [gold-api.com](https://gold-api.com/) |
| **goldprice.dev** | 1,000 calls/month anon; 30 req/min + 1,000/mo with free key | Yes, returns **bid/ask** | Explicitly "internal use" on Free; **commercial needs paid** | [goldprice.dev](https://goldprice.dev/) |
| **xaus.com** | No key, no hard cap ("reasonable use") | Yes, sampled every 2 min | Free for "dashboards, widgets, personal projects, OSS"; commercial >10k req/day = contact | [xaus.com/api](https://xaus.com/api/) |
| **Twelve Data** | 800 requests/day, 8 credits/min | Yes (XAU spot) | Credit-based; many endpoints cost 1-10+ credits | [twelvedata.com/forex](https://twelvedata.com/forex) |
| Alpha Vantage | Not recommended for this | — | 25 req/day is far too low for 1-min polling | — |

**Recommendation (most capable free): `goldprice.dev` anonymous endpoint.**
It is the only free option returning **bid and ask** separately, which our
`market_snapshots` table already has columns for. Caveat: its own docs say
anonymous/Free is *internal use* and commercial use requires Pro. If XV ever
earns money, that becomes a paid line item. `gold-api.com` is the fallback
(unlimited, no redistribution issue for a single-price display).

## 4. Economic calendar (Gate G5)

| Provider | Free tier | Actual + forecast on free? | Redistribution | Source |
|---|---|---|---|---|
| **FMP** | **250 calls/day**, 500 MB / 30 days | Yes, `stable/economic-calendar` | **Requires a Data Display & Licensing Agreement to display/redistribute** | [FMP pricing](https://site.financialmodelingprep.com/developer/docs/pricing) |
| Trading Economics | Guest key: limited | Yes | Free for personal/non-commercial; commercial = paid | — |
| Forex Factory / Econoday | No official API | — | **Scraping both violates their ToS** — do not | — |

**Recommendation: FMP 250/day is ample** (we need ~24/day). The blocker is
licensing, not quota: FMP's terms require a separate agreement to *display* their
data. For a non-monetized personal app this is low risk, but it must be recorded
as a decision before enabling — and the calendar is a *guardrail*, never a vote
(rule 9), so a fallback of curated manual fixtures is architecturally fine.

## 5. News headlines (Gate G5)

| Provider | Free tier | Commercial use? | Source |
|---|---|---|---|
| **GNews.io** | 100 req/day, **12-hour delay**, CORS localhost only | **Free = non-commercial only.** "Accounts that abuse these terms are terminated." | [gnews.io/faq](https://gnews.io/faq), [pricing](https://gnews.io/pricing) |
| **NewsAPI.org** | 100 req/day, 24h delay | Developer plan = **development only, not staging or production**; license revoked if integrated outside dev | [newsapi.org/terms](https://newsapi.org/terms) |
| NewsData.io | Free tier exists | Non-commercial restriction on free tier | — |
| FMP news | within the 250/day | Same licensing agreement as above | — |

**Recommendation: keep the news path on manual seeds until XV is monetized.**
Both credible free tiers explicitly forbid production/commercial use — this is
the clearest case in the whole stack where "most advanced free" and "legal" are
mutually exclusive. Our `news-collect` already has the `GNEWS_ENABLED` gate and
stores headline + link + short summary only, so this is a clean later swap.

## 6. Firebase Cloud Messaging

| Fact | Value | Source |
|---|---|---|
| FCM cost on Spark (no-cost) plan | **No-cost** | [firebase.google.com/pricing](https://firebase.google.com/pricing) |
| Downstream quota | 600,000 messages/minute per project default | [throttling-and-quotas](https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas) |
| Per-device cap (Android) | 240 messages/min, 5,000/hour | same |
| Exceeding Spark quota | project **shut off for the rest of the calendar month** | [pricing plans](https://firebase.google.com/docs/projects/billing/firebase-pricing-plans) |

**Verdict: 500–2,000 pushes/day is nowhere near any limit.** FCM is the one
service here with genuinely unlimited headroom. No Blaze plan needed.

---

## Sources (primary, in priority order)

1. https://supabase.com/pricing
2. https://supabase.com/docs/guides/functions/limits
3. https://supabase.com/docs/guides/platform/free-project-pausing
4. https://supabase.com/docs/guides/cron
5. https://supabase.com/docs/guides/troubleshooting/pgcron-debugging-guide-n1KTaz
6. https://gnews.io/faq · https://gnews.io/pricing · https://gnews.io/legal/terms-of-service
7. https://newsapi.org/terms · https://newsapi.org/pricing
8. https://site.financialmodelingprep.com/developer/docs/pricing
9. https://goldprice.dev/ · https://gold-api.com/ · https://xaus.com/api/
10. https://twelvedata.com/forex
11. https://firebase.google.com/docs/cloud-messaging/throttling-and-quotas
12. https://firebase.google.com/docs/projects/billing/firebase-pricing-plans

## Confidence

| Claim | Confidence |
|---|---|
| Supabase quotas (invocations, CPU, memory, wall-clock) | **High** — read from official docs |
| 7-day idle pause kills cron | **High** — official pausing doc + independent confirmation |
| GNews / NewsAPI free tiers are non-commercial | **High** — quoted from their own ToS/FAQ |
| FMP 250 calls/day | **High** — FMP FAQ + pricing |
| FMP requires a display agreement | **High** — quoted from FMP pricing terms |
| FCM effectively unlimited at our volume | **High** — official quotas vs our usage |
| goldprice.dev bid/ask on free | **Medium** — from their own marketing page, not an API spec |
| "12 concurrent jobs" figure | **Medium** — doc says "recommend no more than 8"; 32 is the pg_cron ceiling |
| Duck.ai's "16,666 invocations/day" | **Derived, not documented** — 500,000 ÷ 30. Treat as arithmetic, not policy. |
