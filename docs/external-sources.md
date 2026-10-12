# External Sources — every free source XV uses, touches, or deliberately refuses

**Purpose:** one file that answers, for any URL in this project: *is it free, what
is the licence basis, what do we read from it, how is it called in code, and what
did we learn the hard way about it.* Written 2026-10-12 from a full walk of
`supabase/functions/`, `supabase/migrations/`, `memory/decisions.md`,
`memory/lessons.md`, `memory/events.md`, `docs/free-tier-research.md`,
`tools/backfill_dukascopy.py`, and the methodology document (§1.1 source
priority table).

**Standing rule (AGENTS.md #6):** an accessible endpoint is not permission. Every
production source needs a recorded licensing review in `memory/decisions.md`.
`D-...` references below are those reviews.

Conventions used in this file:

- **LIVE** — called at runtime by a deployed function.
- **GATED** — code ships but stays disabled unless an env flag + review exist.
- **TOOL** — offline/one-shot (backfill script, validator data file).
- **REFUSED** — reviewed and rejected. Do not wire up without a new decision.

---

## 1. Live price — biquote.io (PRIMARY)

- **Endpoint:** `GET https://biquote.io/api/XAUUSD` (plain REST; a SignalR stream
  exists but is not used — REST-first was the implementation decision).
- **Cost/key:** free, keyless, no signup.
- **Licence basis:** ToS reviewed 2026-10-07 (D-20261007-024). Explicit grant:
  commercial AND non-commercial use, display to end users (incl.
  paying/authenticated), cache/store quotes, 15,000 req/min/IP. Attribution
  appreciated, not required — given anyway.
- **Prohibited (we comply):** no resale of the raw feed via our own public
  API/bulk downloads; no misrepresentation as exchange-licensed data. We display
  inside the product only.
- **What we read:** `mid`, `stale`, `quoteAgeSeconds`, `lastQuoteAt`/`timestamp`.
  **MID ONLY.** `bid`/`ask`/`spread` are execution numbers from a broker feed and
  must never be stored, cached, or served (same lesson as the OANDA ladder).
- **Acceptance rule:** quote accepted only if `stale != true` AND age ≤ 20s by
  its own clock AND provider's `quoteAgeSeconds` agrees (≤ 20s). ANY doubt →
  fall through to gold-api. A closed-market quote must fail into the fallback,
  never onto the screen as live.
- **Used by:** `price-live` (server-side 5s cache in `live_price_cache`; ~12
  upstream req/min against a 15,000/min limit).
- **Residual risks on record:** data aggregated from third-party sources incl.
  broker MT5 feeds; biquote grants only what it holds and a source can be pulled
  anytime → gold-api fallback stays mandatory, and a dead feed must read as
  outage, never as flat price. No SLA; re-check terms on any integration change.
- **Lesson:** indicative only — label as reference, never as an execution quote.

## 2. Live price — gold-api.com (FALLBACK)

- **Endpoint:** `GET https://api.gold-api.com/price/XAU`. Response
  `{price, updatedAt, ...}`.
- **Cost/key:** free, anonymous, no signup. Optional `GOLD_API_KEY` sent as
  `x-access-token` **only when configured** — never hand the anonymous tier a
  bogus credential. Terms (captured 2026-10-06, effective 2026-09-10):
  *"Commercial use of the API is always permitted, including use in web
  applications, mobile apps, and third-party websites."* *"No restrictions on
  how many requests to the real time price API."*
- **What we read:** `price` + provider `updatedAt`. Age is derived from the
  **provider's** timestamp, not from the fact we just called: it republishes on
  roughly a **30s cycle** (verified by watching `updatedAt` advance in 30s
  steps), so a fresh fetch can hand back a 30s-old number. Reporting 0 would
  overstate freshness by up to half a minute.
- **Used by:** `price-live` (fallback), `tick` (primary), `build-bars` (bar
  history).
- **Lesson — the one that built `price-live` (D-20261006-015):** direct calls
  from the app returned 200 on the workstation and **429 on the phone** (16
  requests at 4s spacing: all 200 on desktop, all 429 on device). The provider
  rate-limits by client IP, so per-client polling works on a developer
  connection and fails for real users. Upstream is therefore called server-side
  at most once per cache window; any number of clients read the one result.
  Test on the device, not just the desktop.

## 3. Positioning — CFTC Commitments of Traders via Socrata API

- **Endpoint:**
  `https://publicreporting.cftc.gov/resource/72hh-3qpy.json?$select=<cols>&$where=cftc_contract_market_code='088691'&$order=report_date_as_yyyy_mm_dd DESC&$limit=156`
  Dataset `72hh-3qpy` = "Disaggregated — Futures Only". COMEX gold code `088691`.
- **Cost/key:** free, keyless. US federal data, public domain.
- **Why Socrata and not cftc.gov (D-20261005-005):** `www.cftc.gov` serves the
  weekly `.txt`/yearly `.zip` behind a bot challenge — HTTP 403 Cloudflare
  interstitial from Supabase egress, and a spoofed browser UA does **not** clear
  it. `publicreporting.cftc.gov` is CFTC's own Socrata API for the same data and
  answers normally. Bonus: one ~1.5s query instead of ~6.5MB of archives, the
  full 156-week window (§1.6), columns by name so a schema change can't silently
  shift a value into the wrong field.
- **Rejected siblings:** `kh3c-gbw2` "Combined" (folds options in, §1.6 doesn't
  ask for it), `ubmb-6exi` (frozen since 2022-07-28, missing managed-money cols).
- **Verification (don't skip this pattern):** the Socrata row for 2026-09-29
  (OI 406456, MM 131711/11393, net 120318) was matched byte-for-byte against the
  weekly `.txt`. Spot-check third-party shapes against the issuer.
- **What we read:** `report_date_as_yyyy_mm_dd`, `open_interest_all`,
  `m_money_positions_long_all`, `m_money_positions_short_all`. A week with a
  missing field is **dropped, not zeroed** — a gap is not a reading. Current net
  ranks against the 156-week window (current value stays in its own reference
  set per §1.6); ±2 extremes never claimed without the price-trend leg
  (`trend_confirmed: false`, divergence null).
- **Used by:** `sentiment-layers` → `positioning` layer, weight 25. Stale after
  10 days (`COT_STALE_DAYS`).
- **Query-shape lesson:** `$order DESC` + `$limit` matters — an ascending limit
  returns the OLDEST rows and silently ranks the current reading against stale
  history. (Same bug class as the PostgREST 1000-row cap that fed the app
  4-day-old bars: unbounded/ascending reads fail toward looking correct.)

## 4. Rates — US Treasury daily real yield curve

- **Endpoint (CSV):**
  `https://home.treasury.gov/resource-center/data-chart-center/interest-rates/daily-treasury-rates.csv/{Y}/all?type=daily_treasury_real_yield_curve&field_tdr_date_value={Y}&page&_format=csv`
  Parse header columns `Date`, `5 YR`, `10 YR` **by name**.
- **Cost/key:** free, keyless. US federal data, public domain.
- **What we read:** 5Y/10Y real yields → 5-day change impulse for the
  `market_implied` layer (weight 20). Row records which legs are actually
  measured: `legs_measured: ["real_yields"]`, `legs_missing: ["usd",
  "volatility"]` — a partial layer must read as partial, not complete.
- **Used by:** `sentiment-layers`. Stale after 5 days.
- **Performance lesson:** `home.treasury.gov` costs **~18s per request from
  Supabase egress regardless of size** (a 6.8KB CSV took 18.3s). Fetch the
  current year alone; request the prior year only when fewer than 6 usable 10Y
  observations (happens in early January). Fetching both unconditionally doubled
  a 19s run to 37s for data almost never used.

## 5. Policy — Federal Reserve FOMC calendar + statements

- **Endpoints:** calendar `https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm`
  → statement links carry the date in the URL (`monetaryYYYYMMDDa.htm`), so
  "latest" is a max over dates, no calendar parsing. Fetch latest + previous as
  plain HTML (`https://www.federalreserve.gov{path}.htm`).
- **Cost/key:** free, keyless. US federal publication, public domain.
- **What we read:** the statement's own decision sentence (the official record
  per §5.2): action verb → raise −2 / lower +2 / maintain 0; target band;
  change vs prior; dissents. Effective score decays `raw * exp(-days/30)`.
  SEP projections recorded as `sep_projection: null` — the Fed publishes them
  as **PDF only**, which the Deno runtime cannot read; never inferred from the
  target rate.
- **Deliberate non-scoring:** the two "unchanged but hawkish/dovish" bands (±1)
  require classifying free text as hawkish/dovish. An unchanged decision scores
  0 with `unchangedAction: true`. Reading a hold wrong is costlier than losing
  one point (D-20261005-008).
- **Used by:** `sentiment-layers` → `policy` layer, weight 35 (largest single
  weight; lifts macro coverage to measurable). Stale after 45 days.
- **Why not FRED:** `DFEDTARU` would be tidier, but FRED **did not respond at
  all when tried from two different hosts** — not a usable fallback.

## 6. Economic calendar — Finance Calendar (convenience layer)

- **Endpoint:**
  `https://www.financecalendar.com/wp-json/fc/v1/calendar?from={60d back}&to={14d fwd}&limit=500`
- **Cost/key:** free, keyless. Licence verbatim: *"Free for any use — commercial
  included — with one condition: link to financecalendar.com wherever the data
  appears."* Operating terms verbatim: *"No API key. No rate limits (responses
  are edge-cached for 5 minutes). CORS is open."* / *"Please cache responses on
  your side where you can; the data changes at most hourly."* Attribution:
  visible link near the data or an about/credits page.
- **Status:** APPROVED (D-20261006-020, corrected D-20261007-023). It is
  **convenience, not authority**: official BLS/Fed/BEA/Census/issuer wins every
  conflict; discrepancies get recorded (`calendar_discrepancies`), never
  auto-corrected.
- **Used by:** `fetch-events` (hourly; the cron is the client-side cache the
  provider asks for). 60-day back window is deliberate: publisher actuals print
  with multi-week lag, so forward-only reads never see a scored row.
- **Honest limits (verified live, code around each):**
  - NO currency field → derived from title markers for the majors; unrecognized
    = `UNKNOWN`, hidden by the currency chips (fail closed), never fed to the
    US blackout guard.
  - consensus/prior/actual often STRINGS (`"6.4% unemployment"`) or null → only
    real numbers stored; else null so surprise reads "unavailable".
  - `time_utc` nullable (all-day notices) → date at 00:00 UTC.
  - **Actuals arrive with MULTI-WEEK lag, as descriptive text, never numbers**
    (verified 2026-10-07: 30-Sep releases null, mid-August populated — the
    approval's "within the hour" claim was wrong). Publisher wording travels
    verbatim in `actual_text`; no parser may reduce it to a number. Numeric
    Results-tab scoring comes from BLS (§7), not from here.
  - Clobber guard: hourly upserts only touch actual-carrying columns when the
    fetch has an actual — otherwise issuer numerics written between runs would
    be erased every hour.
- **NOT approved as:** event authority over official sources, sole input to any
  trading rule, weekend/holiday oracle for gold. The `/today` market block is
  NYSE open/closed — never feed it into the session calendar; gold hours stay
  in `xau_core`.

## 7. Issuer actuals — BLS public API

- **Endpoint:** `POST https://api.bls.gov/publicAPI/v2/timeseries/data/`
  body `{seriesid: [...], startyear, endyear}`.
- **Cost/key:** free, keyless, quota **25 requests/day** on the keyless tier.
  US federal data, public domain.
- **Series mapped (the three releases that move gold most):**
  CPI `CUUR0000SA0` · Payrolls `CES0000000001` · Unemployment `LNS14000000`.
  PPI/retail/GDP/jobless have NO mapped series — those rows keep provider
  wording, never a BLS number from the wrong release.
- **Vintage rule:** BLS monthly points are reference-month values. A release on
  date D reports the newest point with reference month strictly before D's
  month; `M13` annual averages are never a release figure. Keys off the event
  date, never the title wording.
- **Scope guards:** only rows with `actual IS NULL` (first-write-wins,
  idempotent reruns); only past events; **one batched request** for all series
  (quota!); loud failure on HTTP/shape errors.
- **Used by:** `bls-actuals` (daily) → writes `actual` + `actual_source`
  (`BLS {series} (public domain, ref …)`).

## 8. News — issuer + openly syndicated RSS

- **Feeds (all keyless, poll-friendly):**
  - Fed monetary releases `https://www.federalreserve.gov/feeds/press_monetary.xml`
    (keep all — already topic-filtered)
  - Fed speeches `https://www.federalreserve.gov/feeds/speeches.xml` (keyword
    gate: rate|inflation|policy|economy|outlook|powell|fomc|monetary)
  - BLS employment `https://www.bls.gov/feed/empsit.rss` · BLS CPI
    `https://www.bls.gov/feed/cpi.rss`
  - BEA releases `https://apps.bea.gov/rss/rss.xml`
  - MINING.com gold `https://www.mining.com/commodity/gold/feed/` (keyword gate)
- **Licence basis (D-20261007-025):** US federal feeds are public-domain works
  (17 U.S.C. §105) — redistribute with citation, no endorsement implied.
  MINING.com expressly permits businesses/websites to serve feed content to
  their own users with link-back — the app links every headline to the
  original. **Headlines + feed summaries + links ONLY — never full article
  text** (copyright rule).
- **Used by:** `news-collect` (every 30 min). Polite UA
  `XV-NewsCollector/1.0 (free XAUUSD assistant; polls each feed every 30
  minutes)` — never a browser impersonation; a block that needs evading is a
  block we obey. Per-feed try/catch → named warnings, never a failed run.
- **Parser lessons (all found via in-situ diagnostics, not guessing):** BLS
  serves namespaced Atom (collapse prefixes or its items are invisible while
  the fetch looks healthy); some issuer feeds never close `<entry>` (split on
  openings, not open/close pairs); BLS links are href-only (fall back to
  `href=` when link text is absent); **BLS bot-walls non-browser clients (403
  observed)** — tolerated with a visible warning, a gap not a silence.
- **Fabrication guard:** `ManualNews` (example.com seed headlines) is RETIRED
  but kept in-file so its shape stays tested; nothing in production constructs
  it. It once wrote invented headlines that `news-digest` summarized into
  on-screen "macro backdrop" themes — fabrication in a pipeline uniform.

## 9. Spread measurement — OANDA fxTrade PRACTICE via `oanda-quote` (internal ONLY, never displayed)

> ⚠ **Status check before relying on this section:** the `oanda-quote` Edge
> Function is referenced by migrations 0005/0011/0017 and the 2026-10-03 plans,
> but **no longer exists** in `supabase/functions/` (only 16 dirs: the 15 named
> in §14 below plus `_shared`). Verify it is still deployed and the
> `xv-oanda-quote` schedule still fires before treating the spread as measured.
> If it is gone, `spread_gate` reads UNAVAILABLE and the spread vetoes are
> UNEVALUATED — honest, but the ledger's `measured_spread` cost model has no
> input.

- **Endpoint:** `GET https://api-fxpractice.oanda.com/v3/accounts/{id}/pricing?instruments=XAU_USD`
  Token in Supabase Vault, `oanda-quote` runs with `verify_jwt=true`. Writes
  `market_snapshots.bid/ask` with `source='oanda-practice'`. Practice candles
  return 404 for every instrument — it contributes spread only, never bars.
- **Cost:** practice env, token-based. No per-call charge; the cost is the
  licence constraint below.
- **Licence (D-20261006-013, hard gate):** OANDA API licence grants use of the
  FXTrade system and rates **"only for your own use" / "for Internal Use
  only"**, and forbids *"transmit, publish, disseminate, duplicate, display,
  disclose, offer, or otherwise provide, in any form whatsoever, the FXTrade
  Trading System Rates to any third party."* XV is a public app — **any
  delivery of that ladder to the app is delivery to a third party.**
- **How compliance is actually enforced (D-20261006-014):** not a UI policy
  ("we won't show it") but a database REVOKE — `market_snapshots.bid/ask`
  columns revoked from anon/authenticated (migration 0016), owner-security view
  (0017) because a security-invoker view can't read what the invoker lacks. A
  UI promise is not compliance; the rate must not arrive. **A permission is not
  a control if the caller can write the inputs** — writes stay server-side only
  (`tick`, `oanda-quote`), or anyone could invent the numbers the gate vouches.
- **What the app gets instead:** `spread_gate` (status + age, never a price).
  Three states, kept distinct because they mean different things:
  `unavailable` (nothing trustworthy / too old → vetoes UNEVALUATED),
  `AVAILABLE_FOR_INTERNAL_USE` (measured, inside limits, rate withheld — the
  engine may use it, Dart sees `VenueSpread.undisclosed`, never a number),
  fresh ≤5 min or it's UNAVAILABLE again. Publishing `ask − bid` anywhere in
  the view would reintroduce the exact breach the migration closes.
- **Kill criteria tie-in:** the outcome protocol stops the ledger if median
  spread exceeds 1.0R — currently unmeasurable without this feed.
- **What we measured while it ran:** mean spread 0.99 across 5,566 OANDA rows
  (min 0.18, max 1.55; recent hourly means ~0.45–0.51). The "~$0.41 spread
  claim" was **never supported by any aggregate** — provenance recorded UNKNOWN
  rather than estimated.
- **Lesson:** when a number can't be shown, don't flatten it to UNAVAILABLE —
  "measured but withheld" and "nothing trustworthy" are different facts and the
  engine treats them differently (veto EVALUATED vs UNEVALUATED).

## 10. Session view — Gold Hunts live endpoint (display licence OK, production dependency PENDING)

- **Endpoint (LIVE ONLY):**
  `https://ebhodyknnbdhdiezrtsk.supabase.co/functions/v1/refresh-gold-data?dataset=gold-signals`
- **Licence (D-20261006-016):** payload carries *"Free to use, including
  commercially, with visible attribution to Gold Hunts (https://goldhunts.com)"*;
  data page confirms quoting/embedding/redistributing datasets. Calling a
  published, keyless, CORS-enabled JSON API is using the offered interface, not
  scraping (ToS "no scraping" targets the site, not the API). Conditions:
  visible attribution link wherever shown; never as a guarantee of future
  results; never resold as a paid signal service; never strip timestamps or
  losing calls.
- **⚠ STILL OUTSTANDING:** the directive requires **written confirmation from
  the publisher before treating this as a production dependency**
  (suggested: info@goldhunts.com). No request sent — the agent cannot email.
  Current status covers display under the published licence only.
- **Hard limits:** **the static `gold-signals.json` file was 11 days stale on
  review day — never use it**; session calls are session-level reads
  (Asian/London/NY bias), never 15M setups, never votes, and a single publisher
  can never satisfy the two-publisher rule. Labels reproduced **verbatim**
  (BULLISH/BEARISH/RANGING/SWEEP_THEN_REVERSE) — unknown labels skipped, never
  mapped. Freshness: STALE when provider flag set OR `now − data_as_of > 6h`
  (`data_as_of` = max published_at, never fetch time).
- **Used by:** `goldhunts-sync` (hourly at :45, off the provider's ~:35
  regeneration). Raw payload archived first (`goldhunts_snapshots`) for outcome
  reconciliation; label-only rows to the view. Fetch/validation failure → loud
  500, writes NOTHING (previous rows age into STALE; stale dressed as fresh is
  worse than an error).

## 11. Calendar validator — l3vlup-skills (validation only, never leads)

- **File:**
  `https://raw.githubusercontent.com/Surojitc/l3vlup-skills/main/data/calendar.auto.json`
  (daily refresh; `macro.auto.json` exists — 11 series — but is research input
  only, methodology decision required before any layer use).
- **Licence (D-20261007-022):** code MIT; data redistributes official/
  public-domain source data with per-record source name + URL; "attribution
  appreciated, never required" — given voluntarily anyway. Collection hygiene
  verified (anti-scraping sites recorded as excluded, gaps stay gaps).
- **What it is:** US BLS schedule + FOMC + BoE MPC dates, ET wall-clock, daily
  refresh. Schedule only: no actuals, no consensus, US/Eurozone/UK only.
  Spot-check passed (CPI Oct 14 08:30 ET == Finance Calendar 12:30 UTC).
- **Used by:** `calendar-crosscheck` (daily). Compares Finance Calendar HIGH
  USD rows by keyword sets (not string equality); every finding lands in
  `calendar_discrepancies` as an OPEN question for manual issuer check —
  **never auto-correction**, both directions reported
  (MISSING_IN_FC and MISSING_IN_L3VLUP). ET→UTC via US DST rules; mismatches
  count past 60 min only. Open rows suppress re-inserts (no stacking).
- **Caveats on record:** one-person repo, no SLA, no uptime promise — it
  validates, it does not lead. Per-series staleness varies (ez-hicp ended
  2025-12) — check freshness per series, never trust file-level `generatedAt`.

## 12. History warm-up — Dukascopy tick feed (offline tool, not runtime)

- **Feed:** `https://datafeed.dukascopy.com/datafeed/{symbol}/{YYYY}/{MM}/{DD}/{HH}h_ticks.bi5`
  Free downloadable historical ticks. Convenience mirror (methodology §1.2):
  `https://evtradelabs.com/data` (Dukascopy-aggregated OHLCV, XAUUSD M1–H1) —
  compare a sample against upstream before trusting for research.
- **How used:** `tools/backfill_dukascopy.py` (`--days 21 --per-tf 500`) writes
  bars with `source='dukascopy'`, `quality='degraded'` — **excluded from
  levels**, warm-up only. Dukascopy is not spot XAUUSD execution data; the
  methodology's spread section forbids treating any of this as venue bid/ask.
- **Status:** methodology P0/P5 reference. Not called by any deployed function.

## 13. Release distribution — GitHub releases + gist manifest (app's own)

- **APK asset:** `https://github.com/amworx/xau-vote/releases/download/v{ver}/XV-v{ver}-{code}.apk`
  (public repo — private-repo assets 404 anonymously, fixed 2026-10-10).
- **Manifest:** gist `5f527027564c46236d0f5ffbad908a78`
  (`https://gist.githubusercontent.com/amworx/.../raw/xv-manifest.json`); DB
  `app_config.update_manifest_url` is authoritative; `updates/xv-manifest.json`
  is the repo mirror.
- **Lesson (paid twice):** Fastly caches the gist raw URL with `max-age=300`.
  After `gh gist edit` succeeds, the edge serves the old body for ~5 min.
  **Check `X-Cache`/`ETag`/`Content-Length` before assuming a write failed —
  the origin (gist API) is correct immediately.** No public purge path for gist
  URLs; wait out the TTL. Same discipline applies to any edge-cached provider
  response (Finance Calendar's 5-min edge cache is why the hourly cron is the
  client-side cache).

---

## Gated code — ships disabled, each needs flag + recorded review

| Source | Endpoint / shape | Why gated | Enable condition |
|---|---|---|---|
| goldprice.dev | `https://api.goldprice.dev/v1/prices?symbol=XAU-USD-SPOT` (`api.` host — bare host 404s) | Free tier = personal/non-commercial/internal, **no redistribution to third parties** (ToS S6). Live JSON also carries **no bid/ask** despite site claims. REJECTED for production display (D-20261007-024) | `GOLDPRICE_DEV_ENABLED=true`; display use needs paid Pro, research-only use needs a new decision |
| FMP calendar | `https://financialmodelingprep.com/stable/economic-calendar` | 250 calls/day free is plenty (~24/day needed), but use **requires a Data Display & Licensing Agreement** | `FMP_ENABLED=true` + `FMP_API_KEY` + review in decisions.md |
| GNews | `https://gnews.io/api/v4/search` | Free = non-commercial/dev/test only; production needs paid plan | `GNEWS_ENABLED=true` + `GNEWS_API_KEY`; dev/test only |
| xaus.com | `https://xaus.com/api/v1/spot`, `.../intraday` | Endpoint live (price + per-gram + 60×2-min points, free for dashboards/personal/OSS) but **NO licensing terms found** | Written confirmation first; commercial >10k req/day needs contact anyway |
| FRED | `https://api.stlouisfed.org/...` (DFII5/DFII10, DFEDTARU) | Would need a free key; **did not respond at all from two hosts** when tried | Key + reachability proof + decision |
| FCM push | `https://fcm.googleapis.com/fcm/send` (legacy HTTP, topic `xau-signals`) | Free Spark quota is ~0.003% of our volume; exceeding a Spark quota shuts the product off for the month (irrelevant at our volume) | `FCM_KEY` (+ `FCM_PROJECT_ID`); absent → logged skip, never a crash |
| OANDA practice spread | `api-fxpractice.oanda.com` (via `oanda-quote`; token in Vault, `verify_jwt=true`) | **Internal-use-only licence forbids transmitting rates to any third party** — see §9 for the full REVOKE-based enforcement, and note the function may no longer exist (§9 status check) | Research/ledger only; NEVER displayed; kill-criteria input when live |
| WGC / Goldhub | `gold.org` | Personal, non-commercial use only; scraping named explicitly; needs prior written authorisation we don't have. REMOVED outright 2026-10-06 (D-20261006-011), layer row purged, denominator recomputed | Do not re-add without a licence |
| Retail publishers (TradingView Ideas, FXStreet, DailyForex, Investing.com, FXCM, FX Empire, MQL5, Reddit) | various | All eight REJECTED 2026-10-05 (D-20261005-001): display-only terms, no-redistribution clauses, bot/API prohibitions | New decision required per publisher |
| FXScalpers | `fxscalpers.net` + Telegram channel | BLOCKED: no reuse licence published (D-20261006-017); publisher said yes in substance but Telegram platform terms prohibit scraping/userbot collection (D-20261006-019). Owner closed the candidacy 2026-10-07 ("forget about fxscalpers"); row kept disabled as registry history | Re-review only after written permission AND a compliant collection path |
| Tech Kick | `techkick.me` | CC BY 4.0 covers ONLY the XAUUSD spread/volatility research archive + reproducing script — not the whole site. Approved as context/research input only, NEVER a voter (D-20261006-018). Not yet integrated | Attribute visibly if used |
| FXLeaders | `fxleaders.com` | REJECTED: no commercial exploitation without written permission, no third-party automated signal-copying (D-20261006-018) | Written permission first |
| Trading Economics | via `api-evangelist/tradingeconomics` profile | NOT a data feed — a third-party spec of a commercial API. No free tier (guest:guest discontinued; Standard $149/mo). REJECTED (D-20261007-021) | Nothing to integrate |
| Currents API / NewsData.io / GDELT | various | Leads from free-tier research, terms NEVER verified | Read ToS + record review before any use |
| Treasury RSS / ECB feeds | — | Treasury RSS 406s from here; ECB secondary and unneeded (D-20261007-025) | Revisit only if a macro coverage gap appears |
| Dukascopy live use | `dukascopy.com` history | Methodology P0/P5 for historical warm-up + backtest; live signals stay on the primary feed | Research only, never execution data |

---

## 14. Schedule map — which function calls what, how often

All schedules go through `public.xv_invoke_function(name)` (service-role key
from Vault `xv_service_role_key` — dashboard key rotation does NOT propagate
there; update the vault secret separately). The allowlist is the only gate: a
job naming a function missing from it raises loudly. After adding any scheduled
function, confirm the dispatcher can name it AND that a timestamp column
actually moves on write before using it as a change signal (D-20261005-006).

| Job | Schedule | Function | External source hit |
|---|---|---|---|
| price display | on demand (client poll) | `price-live` | biquote → gold-api fallback (§1–2) |
| `xv-tick` | `* * * * *` | `tick` | gold-api (+ goldprice.dev if flagged) |
| bar builder | scheduled | `build-bars` | none (aggregates `market_snapshots`) |
| `xv-fetch-events` | `7 * * * *` | `fetch-events` | Finance Calendar (§6) |
| news | every 30 min | `news-collect` | issuer RSS (§8) |
| news digest | scheduled | `news-digest` | none (reads `news_articles`) |
| sentiment | `21 21 * * *` | `sentiment-layers` | CFTC + Treasury + Fed (§3–5) |
| actuals backfill | daily | `bls-actuals` | BLS API (§7) |
| cross-check | daily | `calendar-crosscheck` | l3vlup file (§11) |
| `xv-goldhunts-sync` | `45 * * * *` | `goldhunts-sync` | Gold Hunts live endpoint (§10) |
| `xv-settle-outcomes` | `4-59/15 * * * *` | `outcome-recorder` (settle) | none (reads bars + ledger) |
| keepalive | daily | `keepalive` | none (heartbeat + prune) |
| `xv-oanda-quote` | scheduled (?) | `oanda-quote` | OANDA practice (§9 — verify exists) |

Disabled by owner order: `xv-collect-ideas` (`*/15 * * * *`, seed generator
frozen, D-20261006-008 — schedule preserved so it resumes with one statement).
Consensus cadence was every 5 min when `build-consensus` ran.

Free-tier envelope (verified 2026-10-02): 500k Edge invocations/mo (we use
~11.5%); real ceiling is **2s CPU/request** (4–6 sequential PostgREST
round-trips per function — collapse to one read, compute locally, one write).
DB 500MB / egress 5GB/mo / 1-day log retention. **7-day idle pause stops cron
with no error and no API to query it** — `keepalive` writes a daily heartbeat
row, but an Edge write may not count as "user activity" (undocumented); if the
project still pauses, the remaining options are an external scheduler (GitHub
Actions / Cloudflare Workers) or Pro $25/mo. `keepalive` also prunes
`ops_heartbeat` (30d) and `market_snapshots` (5d — a 1-min ticker adds ~1,440
rows/day) so the 500MB DB can't fill.

---

## 15. Lessons that only exist because a source taught them

1. **Test the provider from the runtime, not your machine.** gold-api 200 on
   the workstation, 429 on the phone (§2). BLS 403 from workstation, 200 from
   edge; Treasury 406 from here (§8). "Works here" is not "works there."
2. **An accessible endpoint is not permission.** Eight retail publishers, WGC,
   FXLeaders, FXScalpers-everything — all readable in a browser, all refused at
   the gate. Read the terms before wiring, record the review, silence is not
   permission.
3. **Ascending/unbounded reads fail toward looking correct.** PostgREST 1000-row
   cap + ASC order fed the app 4-day-old bars with no error; a CFTC `$limit`
   without DESC ranks today against stale history. Order newest-first, always
   bound, and never assume you can read the platform's own limit from its
   config (`pgrst.db_max_rows` was NULL while the cap was in force).
4. **Check the screen, not the tables.** Days of "verified" DB work shipped two
   real faults: stale bars analysed as live, fixture dates rendered as a
   calendar. Green tests + right row counts say nothing about the display.
5. **A block you must evade is a block you obey.** No browser-UA spoofing
   (CFTC 403, BLS 403) — find the offered interface (Socrata API, RSS) or walk
   away.
6. **Vendor claims need live verification.** "Actuals within the hour" was
   multi-week lag (§6). "Free for dashboards" had no terms (xaus). goldprice.dev
   advertised bid/ask its JSON never carried. Verify, then write the decision.
7. **Edge caches lie for exactly 300 seconds.** Gist manifest, Finance Calendar
   responses — after a correct write, check `X-Cache`/`ETag`/`Content-Length`
   before concluding the write failed. No public purge for gist URLs; wait the
   TTL.
8. **Secrets have two copies.** Dashboard rotation does not propagate to Vault
   `xv_service_role_key`, which is what cron actually uses. Rotate both or the
   pipeline dies at the next scheduled run.
9. **Enforce licences in the database, not the UI.** A REVOKE the client can't
   route around beats a promise not to display (§9). And a permission isn't a
   control if the caller can write the inputs — keep gate inputs server-side.
10. **Missing data and refused data are different facts.** Null ≠ 0 (silence is
    not neutrality); withheld ≠ unavailable (the gate treats them differently);
    stale dressed as fresh is worse than an error — fail loudly, write nothing.
11. **Partial layers must read as partial.** `legs_measured`/`legs_missing`,
    named denominators on coverage percentages, "SEP not read" instead of a
    guessed projection. A ceiling that can never be reached (WGC's 73%) is not
    a measurement — remove the layer, don't reweight the rest.
12. **Provenance proves identity, not independence.** Two branded publishers can
    be one desk; overlapping setups in one gold move are one observation.
    Cluster before quoting sample sizes (D-20261006-006). Same trap in our own
    validation as in the publisher gate.
13. **Score expectancy in R, not win rate.** Detecting +0.15R needs ~171–384
    clustered trades; detecting a 2pp win-rate edge needs ~10k. The metric
    choice is a 4–25× sample-size decision — fix it before collecting
    (D-20261006-007).
14. **The recorder is the instrument that finds the bugs.** Stale bars, fixture
    calendars, wrong stop configs — all surfaced by running the record end to
    end, never by review. Keep it running; publish failed tests too.

---

*Decisions index: D-20261005-001 (retail REJECT) · D-20261005-005 (Socrata) ·
D-20261005-006 (allowlist+timestamp) · D-20261005-008 (policy scoring) ·
D-20261006-002/003 (independence gate, seed freeze) · D-20261006-004/011 (WGC
drop) · D-20261006-010 (stale bars) · D-20261006-012 (fixture calendar) ·
D-20261006-013/014 (OANDA licence + gate) · D-20261006-015 (price-live) ·
D-20261006-016 (Gold Hunts) · D-20261006-017/019 (FXScalpers) · D-20261006-018
(Tech Kick/FXLeaders) · D-20261006-020/023 (Finance Calendar + actuals
correction) · D-20261007-021 (TradingEconomics) · D-20261007-022 (l3vlup) ·
D-20261007-024 (biquote) · D-20261007-025 (issuer RSS) · free-tier research
2026-10-02 (quotas, pause, FCM, GNews/NewsAPI refusals).*