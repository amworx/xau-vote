# XAUUSD Intraday Signal Generation Methodology

**Instrument:** XAUUSD / Gold Spot vs USD  
**Execution timeframes:** 5m, 15m, 30m, 1H  
**Primary use:** Intraday discretionary-style signal replication by an AI trading system  
**Signal outputs:** LONG / SHORT / NO TRADE, entry zone, stop-loss, TP1, TP2, TP3, confidence score, reason codes, news-risk state  
**Reference version:** 1.0  
**Last reviewed:** 2026-10-02  

> **Important scope note**
>
> This document is an implementation specification, not a claim of personal human trading performance. No proprietary historical rule-set was supplied with the request, so the rules below are a complete, explicit reference methodology built to satisfy the requested behavior rather than a reconstruction of an undocumented private strategy. It must be backtested, forward-tested and paper-traded before any live use.

---

## 0. Operating Principle

The system does **not** try to predict every XAUUSD move. It tries to identify a narrow class of intraday setups in which:

1. the macro environment provides a directional bias;
2. positioning/sentiment does not strongly oppose that bias;
3. the 1H and 30m structures support a tradable direction;
4. the 15m chart forms a setup near a meaningful location;
5. the 5m chart supplies the actual trigger;
6. volatility is normal enough to define a rational stop;
7. there is no immediate high-impact event risk;
8. the expected reward to meaningful levels is large enough relative to the stop.

The bot should prefer **NO TRADE** to forcing a signal when any of these conditions fail.

This is a filtering system, not a forecasting engine.

---

# 1. Data Resources & Processing

## 1.1 Source policy

The source stack prioritizes public, no-account-access data and browser/CSV/XML downloads. Public web access does **not** mean a provider guarantees an unlimited production API, so the bot must use the published HTML/CSV/XML resources conservatively, cache data locally, and obey each site's terms.

For production, do not depend on a single website. Maintain a source priority and a fallback.

### Source priority

| Priority | Input | Preferred source | Fallback | Typical frequency | Main use |
|---|---|---|---|---|---|
| P0 | XAUUSD historical/intraday candles | Dukascopy public historical feed | EV Trading Labs historical OHLCV | M1-M30/H1; historical | Technical engine/backtests |
| P0 | US employment releases | BLS | — | Monthly/event-driven | News gate + macro bias |
| P0 | US inflation/PPI | BLS | — | Monthly/event-driven | News gate + macro bias |
| P0 | PCE/GDP/income | BEA | — | Monthly/quarterly | Macro bias |
| P0 | FOMC calendar/statement/SEP/minutes | Federal Reserve | — | Event-driven | Policy regime |
| P0 | Treasury nominal & real yields | US Treasury | FRED | Daily | Rates/yield regime |
| P0 | CFTC COT positioning | CFTC | — | Weekly | Positioning bias |
| P1 | Gold demand/central-bank information | World Gold Council | — | Quarterly/monthly/annual | Structural sentiment |
| P1 | ECB decisions | ECB | — | Event-driven | Global rate regime / EUR-risk channel |
| P1 | Energy/inflation shock data | EIA | — | Weekly/event-driven | Inflation impulse |
| P1 | PMI | ISM | — | Monthly | Growth/inflation regime |
| P2 | Market visualization/secondary sanity check | TradingView | Investing.com | Intraday/daily | Visual verification only |

---

## 1.2 Market data: XAUUSD candles

### Primary: Dukascopy historical data

**URL:**  
https://www.dukascopy.com/swiss/english/marketwatch/historical/

Dukascopy provides historical market data for instruments including metals. Its documentation exposes historical bars and ticks, and its public historical-data system is suitable for backtesting and candle reconstruction.

### Recommended use

- Obtain XAUUSD BID-side candles.
- Use UTC internally.
- Store raw data before transforming it.
- Derive 5m, 15m, 30m and 1H bars from the lowest reliable source available when possible.
- Keep the source identifier and download timestamp in metadata.

### Third-party convenience mirror

**EV Trading Labs:**  
https://evtradelabs.com/data

The site publishes free downloadable OHLCV candles aggregated from Dukascopy ticks and lists XAUUSD at M1, M5, M15, M30 and H1 resolutions.

Use the mirror for convenient historical backtesting, but compare a sample against the upstream Dukascopy data before trusting it for production research.

### Live-data limitation

Free public broker web pages can display delayed or broker-specific CFD prices. Do not mix a delayed public CFD quote with a live execution feed and assume they are identical. The signal engine should use the same broker/venue price feed that will be used for execution whenever possible.

### True bid/ask spread availability — explicit data gap

A genuine XAUUSD spread means the contemporaneous execution venue's **ask minus bid**. Public no-login sources used by this methodology do not provide a sufficiently reliable, unrestricted, venue-specific live bid/ask stream for the signal engine.

Therefore:

- **Do not fabricate a spread** from two independent spot-price sources.
- In particular, do **not** treat `gold-api` price vs `xaus.com` price, or any similar cross-source price difference, as bid/ask spread.
- The two spread-dependent vetoes in this document remain **UNEVALUATED** when true bid/ask data are unavailable.
- The bot must surface this explicitly as a data-quality field such as:

```text
spread_status: UNAVAILABLE
spread_veto_status: UNEVALUATED
spread_source: NONE
```

- `UNAVAILABLE` does not mean the spread is zero or normal. It means the system has no trustworthy measurement.
- A broker/execution adapter that has genuine bid/ask data may populate these fields and activate the spread vetoes.
- Until then, the absence of spread data is a **known limitation/data-quality note**, not a license to substitute a proxy.

This preserves the distinction between a measured execution cost and a cross-provider price discrepancy.

### Market-data normalized schema

```text
Bar {
    ts_utc: datetime,
    symbol: "XAUUSD",
    timeframe: "5m|15m|30m|1h",
    open: float,
    high: float,
    low: float,
    close: float,
    volume: float|null,
    source: string,
    quality: "primary|secondary|degraded"
}
```

### Processing rules

1. Reject duplicated timestamps.
2. Reject bars where `high < max(open, close)` or `low > min(open, close)`.
3. Detect missing intervals.
4. Do not forward-fill price bars.
5. If one or more bars are missing inside an indicator window, mark the affected indicator as degraded instead of silently inventing data.
6. Convert all timestamps to UTC before session calculations.
7. Preserve broker/server timezone separately for execution logic.
8. Build higher timeframes only from complete lower-timeframe bars.
9. Never use the current unfinished candle as a confirmed signal candle.

---

## 1.3 US Treasury nominal and real yields

**Nominal yield curve:**  
https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?type=daily_treasury_yield_curve

**Real yield curve:**  
https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?type=daily_treasury_real_yield_curve

Treasury publishes daily par nominal and real yield curves. The Treasury notes that the values are derived from indicative bid-side quotations and are published as constant-maturity rates.

### Inputs used

- 2Y nominal yield
- 10Y nominal yield
- 10Y real yield
- optionally 5Y real yield

### Processing

Daily parser steps:

1. Fetch the current-year table or CSV.
2. Parse the date.
3. Parse numeric yield fields as percent, e.g. `4.25` means 4.25%.
4. Keep source timestamp and publication date.
5. Compute 1-day and 5-day changes.
6. Compute a rates impulse:

```text
real10_change = real10_today - real10_5d_ago
nominal2_change = nominal2_today - nominal2_5d_ago
nominal10_change = nominal10_today - nominal10_5d_ago
```

### Gold interpretation

As a **general macro relationship**, rising real yields and a rising USD tend to be headwinds for gold because gold does not pay interest. Falling real yields can be supportive. The system should not treat this as an absolute rule; geopolitical liquidation, inflation fears and liquidity events can temporarily invert the relationship.

### Daily update

Update once the US Treasury daily curve is published. Keep the previous 30-60 observations locally.

---

## 1.4 FRED macro series

FRED is useful for normalized public macro series and historical calculations.

**FRED home:**  
https://fred.stlouisfed.org/

Useful series:

- **T10YIE** — 10-year breakeven inflation rate: https://fred.stlouisfed.org/series/T10YIE
- **DTWEXBGS** — nominal broad US dollar index: https://fred.stlouisfed.org/series/DTWEXBGS
- **VIXCLS** — CBOE VIX: https://fred.stlouisfed.org/series/VIXCLS
- **DEXUSEU** — USD per EUR: https://fred.stlouisfed.org/series/DEXUSEU
- **DGS10** — 10Y Treasury yield: https://fred.stlouisfed.org/series/DGS10
- **DFII10** — 10Y TIPS yield: https://fred.stlouisfed.org/series/DFII10

### Role in the system

FRED is primarily a **regime context source**, not the intraday execution source.

Use it to calculate:

```text
real10 = DFII10
breakeven10 = T10YIE
nominal10 = DGS10
risk_vol = VIXCLS
dollar_regime = DTWEXBGS
```

### Processing

Prefer the public series table/CSV export. Cache locally. Verify the latest observation date before using it.

Do not treat stale daily data as intraday data.

---

## 1.5 US economic calendar and releases

### Bureau of Labor Statistics (BLS)

**Calendar:**  
https://www.bls.gov/schedule/2026/home.htm

**Employment Situation schedule:**  
https://www.bls.gov/schedule/news_release/empSit.htm

**Public calendar feed:**  
https://www.bls.gov/schedule/news_release/bls.ics

Main high-impact releases:

- Employment Situation / Nonfarm Payrolls
- Unemployment Rate
- Average Hourly Earnings
- CPI
- Core CPI
- PPI
- Employment Cost Index
- selected labor-market releases such as JOLTS

### BEA

**Release schedule:**  
https://www.bea.gov/news/schedule/

Important inputs:

- PCE
- Core PCE
- GDP
- Personal Income and Outlays

### Federal Reserve

**FOMC calendar/statements/minutes:**  
https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm

**September 2026 SEP example:**  
https://www.federalreserve.gov/monetarypolicy/fomcprojtabl20260916.htm

### ECB

**Policy calendar:**  
https://www.ecb.europa.eu/press/calendars/mgcgc/html/index.en.html

**Policy decisions:**  
https://www.ecb.europa.eu/press/govcdec/mopo/html/index.en.html

### EIA

**Weekly Petroleum Status Report:**  
https://www.eia.gov/petroleum/supply/weekly/

### ISM

**PMI release calendar:**  
https://www.ismworld.org/supply-management-news-and-reports/reports/rob-report-calendar/

### Event normalization schema

Every event becomes:

```text
Event {
    id: string,
    source: string,
    country: "US|EU|UK|...",
    title: string,
    scheduled_utc: datetime,
    impact: "HIGH|MEDIUM|LOW",
    actual: float|null,
    forecast: float|null,
    previous: float|null,
    revision: float|null,
    surprise: float|null,
    surprise_unit: string|null,
    xau_bias: "BULLISH|BEARISH|NEUTRAL|AMBIGUOUS",
    confidence: 0.0..1.0
}
```

---

## 1.6 CFTC Commitments of Traders (COT)

**Official source:**  
https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm

**Historical viewable reports:**  
https://www.cftc.gov/MarketReports/CommitmentsofTraders/HistoricalViewable/index.htm

CFTC COT reports are weekly and show positioning in futures/options markets. The report is based on Tuesday positions and released later in the week.

### Important interpretation

Do **not** label COT as real-time institutional sentiment. It is a delayed positioning report with trader-category classifications. Its value is as a **slow sentiment/positioning regime filter**.

### Gold fields to capture

For COMEX gold, store at least:

- non-commercial long
- non-commercial short
- managed-money long
- managed-money short
- open interest

Compute:

```text
managed_net = managed_long - managed_short
managed_net_percent = managed_net / open_interest
```

Also compute a 3-year or 156-week percentile:

```text
cot_percentile = percentile_rank(managed_net, last_156_weeks)
```

Interpretation:

- `< 20th percentile`: bearish/under-positioned gold sentiment
- `20th-80th`: neutral/mixed
- `> 80th percentile`: bullish/over-positioned gold sentiment

Extreme bullish positioning is **not** an automatic long. It can become a contrarian warning if price momentum is deteriorating.

---

## 1.7 World Gold Council (WGC)

**Gold market commentary:**  
https://www.gold.org/goldhub/research/gold-market-commentary

**Central banks:**  
https://www.gold.org/goldhub/research/central-banks

**Gold demand/supply data:**  
https://www.gold.org/goldhub/data/gold-demand-by-country

WGC provides slower-moving information about:

- central-bank purchases
- ETF flows
- investor demand
- supply
- geopolitical/macroeconomic themes
- strategic gold sentiment

### Processing

Do not convert monthly/quarterly WGC commentary directly into a 5m trade signal.

Instead create a structural score:

```text
central_bank_score = +1 / 0 / -1
investment_demand_score = +1 / 0 / -1
ETF_flow_score = +1 / 0 / -1
macro_theme_score = +1 / 0 / -1

wgc_structural_bias = sum(scores)
```

Update when a new WGC report is published, not every candle.

---

## 1.8 Energy / oil data

**EIA WPSR:**  
https://www.eia.gov/petroleum/supply/weekly/

Oil matters because a large oil move can change the inflation and rate-expectation path. A jump in oil can therefore be bearish for gold when it causes a substantial rise in expected inflation and/or yields, even though a geopolitical shock might otherwise create safe-haven demand.

This is a good example of why the bot must interpret **second-order effects** rather than applying simplistic “risk-off = gold up” rules.

---

## 1.9 Source reliability hierarchy

Use this hierarchy when sources disagree:

1. Original statistical agency or central bank release
2. US Treasury / CFTC / official exchange-related data
3. World Gold Council for gold-specific structural data
4. Established financial news for event context
5. Secondary market aggregators for convenience only
6. Social media and anonymous commentary: never a direct signal input

The bot should record the source of every macro fact used in a decision.

---

# 2. Technical Indicators & Interpretation

All technical indicators are calculated from **confirmed closed candles**.

## 2.1 Moving averages

Use Exponential Moving Averages (EMA):

- EMA20
- EMA50
- EMA200

Applied to: `close`.

### Purpose

- EMA200: primary regime filter
- EMA50: medium-term direction
- EMA20: short-term trend/momentum

### Bullish structure

```text
price > EMA20 > EMA50 > EMA200
```

This is the cleanest bullish alignment.

### Bearish structure

```text
price < EMA20 < EMA50 < EMA200
```

This is the cleanest bearish alignment.

### Mixed structure

Any other order is transitional/range-like and requires stronger confirmation from market structure and momentum.

### Contribution to confidence

| Condition | Score |
|---|---:|
| clean alignment with direction | +2 |
| price on correct side of EMA200 but shorter EMAs mixed | +1 |
| price crossing EMA200 repeatedly | 0 |
| strong EMA alignment against trade direction | -2 |

---

## 2.2 RSI(14)

### Formula

Use standard 14-period RSI on closing prices.

### Interpretation

The strategy does **not** use RSI as a simple overbought/oversold reversal indicator.

For a long setup:

- RSI > 50: bullish momentum regime
- RSI 52-68: preferred operating zone
- RSI > 70: strong momentum but higher chase risk
- RSI > 75: do not initiate a fresh long unless there is a controlled pullback/retest

For a short setup:

- RSI < 50: bearish momentum regime
- RSI 32-48: preferred operating zone
- RSI < 30: strong downside momentum but higher exhaustion risk
- RSI < 25: do not initiate a fresh short unless there is a controlled pullback/retest

### Stronger signal

A better long is:

```text
RSI > 50
AND RSI rising for >= 2 confirmed candles
AND price structure makes a higher high/higher low
```

A better short is the mirror image.

---

## 2.3 MACD(12,26,9)

Use standard settings on close:

- Fast EMA = 12
- Slow EMA = 26
- Signal EMA = 9

### Bullish confirmation

Prefer:

```text
MACD line > signal line
AND histogram > 0
AND preferably MACD above zero
```

### Bearish confirmation

Prefer:

```text
MACD line < signal line
AND histogram < 0
AND preferably MACD below zero
```

### Histogram interpretation

The histogram is mainly a **momentum acceleration/deceleration tool**.

For a long:

- positive and expanding histogram: momentum strengthening
- positive but shrinking histogram: momentum weakening; avoid chasing
- negative to positive transition: potential early reversal, but requires price structure confirmation

The same logic is inverted for shorts.

---

## 2.4 ADX(14): trend strength

Use Average Directional Index with period 14.

Interpretation:

| ADX | Regime |
|---:|---|
| < 18 | range/chop |
| 18-20 | transitional |
| 20-25 | usable trend |
| > 25 | strong trend |
| > 40 | very strong/possibly stretched |

ADX is **direction-neutral**. Direction comes from price/EMA/+DI/-DI.

### Preferred entries

Trend continuation setup:

```text
ADX >= 20
AND +DI > -DI for long
OR -DI > +DI for short
```

For range trades, the strategy normally produces **NO TRADE**. This document is optimized for directional intraday setups.

---

## 2.5 ATR(14): volatility and stop sizing

Use Average True Range with period 14.

ATR is measured in XAUUSD price units.

### Volatility regime

On each execution timeframe compute a rolling 100-bar percentile of ATR.

```text
atr_pct_rank = percentile_rank(ATR14, last_100_bars)
```

Classify:

- `< 20th percentile`: compressed
- 20th-80th: normal
- 80th-95th: elevated
- `> 95th`: extreme

### Decision rules

- Compressed volatility: setup may be valid but wait for a clear breakout/retest rather than forecasting a move.
- Normal: preferred.
- Elevated: reduce position size if the stop must widen.
- Extreme: NO TRADE until the regime normalizes unless the system is specifically configured for post-news breakout trading.

---

# 3. Market Structure

Indicators alone are not enough.

The system identifies:

- previous day high/low
- previous session high/low
- Asian range high/low
- London session high/low
- US session opening range
- 1H swing highs/lows
- 30m swing highs/lows
- obvious equal highs/lows
- recent impulse origin
- nearest structural support/resistance

### Swing definition

For a confirmed swing high on timeframe T:

```text
high[i] > high[i-1] and high[i] > high[i-2]
AND high[i] >= high[i+1] and high[i] >= high[i+2]
```

The right-side confirmation means the swing is known only after two subsequent completed candles.

Use equivalent logic for swing lows.

### Why structure matters

A bullish indicator reading in the middle of a large 1H resistance zone is inferior to the same reading after a 30m support reclaim. Structure tells the bot **where** the indicator signal occurs.

---

# 4. Economic Calendar & News Analysis

## 4.1 High-impact event classes

Treat the following as high impact for XAUUSD:

### Tier A — mandatory trading blackout

- FOMC rate decision
- FOMC statement
- Fed Chair press conference
- US CPI / Core CPI
- US Employment Situation / NFP
- US PCE / Core PCE when materially surprising
- major unscheduled central-bank intervention
- credible emergency geopolitical events with direct US/inflation/rate implications

### Tier B — normal high caution

- PPI / Core PPI
- GDP advance release
- Retail Sales
- ISM Manufacturing / Services when the result is materially surprising
- JOLTS when expectations are rate-sensitive
- major ECB/BoE policy decisions
- large employment/inflation surprises in other major economies
- major energy shocks

### Tier C — context only

Routine lower-impact releases without a strong historical relationship to USD rates or risk.

---

## 4.2 Blackout rules

### Scheduled high-impact US release

No new position:

```text
T - 30 minutes -> event lock begins
T + 30 minutes -> event lock ends
```

### FOMC decision + press conference

Use:

```text
T - 45 minutes -> lock
Decision -> no entry
Press conference -> maintain lock
T + 30 minutes after press conference ends -> re-enable scanning
```

### Emergency headline

If the bot detects a credible unscheduled event and any of the following occur:

- 5m ATR > 95th percentile
- **true bid/ask spread > 2x its 20-bar median, if genuine spread data are available**
- if genuine spread data are unavailable, record `spread_veto_status=UNEVALUATED` and continue to evaluate the remaining emergency conditions
- single 5m candle range > 2 x ATR14
- price gaps through a predefined structure level

then freeze new entries for at least 30 minutes and reassess.

---

## 4.3 News outcome classification

A news number should never be classified by the headline alone.

The classification path is:

```text
actual vs forecast
        ↓
actual vs previous/revised
        ↓
impact on inflation/growth/employment
        ↓
impact on Fed path / rate expectations
        ↓
impact on real yields and USD
        ↓
expected XAUUSD bias
```

### Basic examples

#### Bullish for gold

Typically:

- employment materially weaker than expected
- inflation materially softer than expected
- dovish Fed decision or guidance
- falling real yields
- falling USD, all else equal

#### Bearish for gold

Typically:

- inflation materially hotter than expected
- employment materially stronger than expected
- hawkish Fed repricing
- rising real yields
- rising USD, all else equal

#### Ambiguous / neutral

When the components conflict.

Example:

```text
NFP much weaker -> gold bullish
but
wages unexpectedly strong -> gold bearish
and
Fed communication remains hawkish -> gold bearish
```

Result: `AMBIGUOUS` until market pricing confirms which component dominates.

---

## 4.4 Surprise normalization

For a release with a known estimate:

```text
surprise = actual - forecast
```

For indicators where the sign is not directly comparable, define an economic direction map.

Example:

- NFP higher than forecast = hawkish pressure = bearish gold
- Unemployment lower than forecast = hawkish pressure = bearish gold
- CPI higher than forecast = hawkish pressure = bearish gold
- PCE lower than forecast = dovish pressure = bullish gold

### Surprise strength

Normalize the surprise by the historical standard deviation of surprises:

```text
z = (actual - forecast) / std(historical_surprises)
```

Classify:

- `|z| < 0.5`: small
- `0.5 <= |z| < 1.0`: moderate
- `1.0 <= |z| < 2.0`: large
- `>= 2.0`: extreme

Use event-specific history, not a generic market-wide standard deviation.

---

# 5. Institutional / Central-Bank Sentiment & Voting Integration

## 5.1 Sentiment layers

The bot should combine four different time horizons:

| Layer | Source | Horizon | Weight |
|---|---|---|---:|
| Policy | Fed/FOMC/ECB official decisions and projections | days-weeks | 35% |
| Positioning | CFTC COT | weeks | 25% |
| Gold fundamentals | WGC | months | 20% |
| Market-implied regime | USD + real yields + volatility | hours-days | 20% |

This is not a vote about whether gold is “good” or “bad”. It is an estimate of the current directional environment.

---

## 5.2 Central-bank voting / personnel integration

Use only documented statements and official voting information.

For the Fed:

1. collect the latest FOMC statement;
2. record target-rate change;
3. record voting dissents if disclosed;
4. read SEP rate projections;
5. record median policy-rate path;
6. compare current projections with the previous SEP;
7. record whether projected rates moved higher/lower;
8. record official inflation/unemployment revisions.

### Example policy score

```text
rate_hike_or_higher_path      = -2 gold
unchanged_but_hawkish         = -1 gold
neutral/uncertain              =  0
unchanged_but_dovish           = +1 gold
rate_cut_or_lower_path         = +2 gold
```

Then apply a freshness decay:

```text
policy_score_effective = raw_score * exp(-days_since_event / 30)
```

For an event directly relevant to today’s session, do not decay it aggressively before the market has repriced it.

### Critical rule

Statements from individual officials are **inputs**, not automatic truth. The system must compare them with official policy decisions, market rates and subsequent data.

---

## 5.3 COT score

Use managed-money positioning as the main slow sentiment component.

```text
cot_score =
    +2 if percentile > 80 and price trend is bullish
    +1 if percentile 60-80
     0 if percentile 20-60
    -1 if percentile 20-40
    -2 if percentile < 20 and price trend is bearish
```

When positioning is extreme but technical trend is opposite, flag:

```text
POSITIONING_DIVERGENCE = TRUE
```

This lowers confidence rather than reversing the trade automatically.

---

## 5.4 WGC structural score

Use WGC for the slowest layer.

Positive inputs:

- sustained central-bank buying
- improving investment demand
- strong gold ETF inflows
- persistent reserve-diversification demand

Negative inputs:

- persistent ETF outflows
- falling investment demand
- major supply response

A structural score should rarely change a 5m decision by itself. It can break a tie between otherwise equal setups.

---

# 6. Macro Regime Engine

Create four normalized factors:

```text
R = real-yield impulse
D = dollar impulse
I = inflation impulse
P = policy impulse
```

Each ranges from `-2` to `+2` where positive means supportive for XAUUSD.

Example:

```text
R = -2 when 10Y real yield rises sharply
R = +2 when 10Y real yield falls sharply

D = -2 when broad USD is rising strongly
D = +2 when broad USD is falling strongly

I = +1 when inflation expectations rise without a matching real-rate spike
I = -1 when inflation shock causes real rates to rise sharply

P = +2 when policy expectations become materially more dovish
P = -2 when policy expectations become materially more hawkish
```

Then:

```text
macro_score = 0.35*R + 0.25*D + 0.20*I + 0.20*P
```

Clamp to `[-2, +2]`.

### Macro interpretation

- `>= +1.0`: macro supports longs
- `+0.4 to +1.0`: mildly supportive
- `-0.4 to +0.4`: neutral/mixed
- `-1.0 to -0.4`: mildly bearish
- `<= -1.0`: macro supports shorts

---

# 7. Timeframe Integration

## 7.1 Hierarchy

The timeframe roles are:

```text
1H  -> regime
30m  -> structure/confirmation
15m  -> setup
5m   -> trigger/execution
```

The 5m chart never overrides a strong 1H structural regime by itself.

---

## 7.2 1H regime rules

Long regime requires at least 3 of 5:

1. price above EMA200;
2. EMA20 > EMA50;
3. RSI > 50;
4. MACD histogram >= 0;
5. ADX >= 20 with +DI >= -DI.

Short regime is the inverse.

If neither direction reaches 3/5, the 1H regime is `NEUTRAL`.

---

## 7.3 30m confirmation

The 30m chart should show:

- structure consistent with 1H regime;
- price respecting or reclaiming a key EMA/structure level;
- RSI aligned with direction;
- MACD aligned with direction.

At least 3 technical conditions must agree.

---

## 7.4 15m setup

The preferred pattern is:

### Long

```text
1H bullish
AND 30m bullish
AND 15m pullback into support / EMA20-EMA50 zone / prior breakout zone
AND 15m RSI holds above ~45-50
AND 15m MACD stops deteriorating
AND no immediate news lock
```

### Short

Mirror the logic.

The system should prefer a pullback/retest to a chase entry.

---

## 7.5 5m trigger

A valid 5m trigger is one of:

1. bullish/bearish engulfing close at structure;
2. break-and-retest of a local swing level;
3. rejection wick followed by a confirming close;
4. micro higher-high/higher-low or lower-high/lower-low transition;
5. continuation candle closing beyond the setup level after a compression phase.

Do not enter merely because a candle touches a level.

---

# 8. Signal Generation Logic

## 8.1 Step-by-step pipeline

```text
1. Update price data
2. Validate candles
3. Check economic-calendar lock
4. Check volatility lock and evaluate spread status
5. Update macro regime
6. Update positioning/sentiment regime
7. Classify 1H trend
8. Classify 30m structure
9. Scan 15m setup
10. Scan 5m trigger
11. Calculate confluence score
12. Calculate SL and R-multiple targets
13. Check reward-to-risk and nearby structure
14. Emit LONG / SHORT / NO TRADE
```

---

## 8.2 Technical score

Use a 12-point directional score.

### For a long

| Component | Points |
|---|---:|
| 1H EMA alignment | 0-2 |
| 1H RSI regime | 0-1 |
| 1H MACD regime | 0-1 |
| 30m structure | 0-2 |
| 15m setup quality | 0-2 |
| 5m trigger quality | 0-2 |
| ADX/trend strength | 0-1 |
| volatility suitability | 0-1 |
| **Maximum** | **12** |

Short scoring is symmetric.

### Minimum technical threshold

```text
technical_score >= 8/12
```

Below 8: `NO TRADE`.

---

## 8.3 Macro/sentiment overlay

Final directional score:

```text
final_score =
    technical_score
    + 2 * macro_alignment
    + sentiment_alignment
    - conflict_penalty
```

Where:

```text
macro_alignment = +1 when macro supports trade
                  0 when neutral/mixed
                 -1 when macro strongly opposes trade

sentiment_alignment = +1 / 0 / -1

conflict_penalty = 0-3
```

### Entry requirement

For a long:

```text
technical_score >= 8
AND final_score >= 9
AND macro_score > -0.5
AND sentiment_score > -1
```

For a short:

```text
technical_score >= 8
AND final_score >= 9
AND macro_score < +0.5
AND sentiment_score < +1
```

These are filters, not probabilities. A score of 10/10 is not a promised win rate.

---

# 9. When News, Indicators and Sentiment Conflict

The system uses a hierarchy.

## Rule 1 — News lock beats everything

If inside the blackout window:

```text
NO TRADE
```

Even perfect technical alignment does not override the lock.

## Rule 2 — Extreme volatility beats normal technical signals

If ATR percentile > 95:

    NO TRADE

If genuine bid/ask spread data exist and spread > 2x its rolling median:

```text
NO TRADE
```

until the market normalizes.

## Rule 3 — Macro regime can veto technical trades

Example:

```text
1H bullish
30m bullish
15m bullish
5m bullish
BUT
real yields +15 bps in a short period
AND broad USD accelerating higher
AND Fed repricing hawkishly
```

Do not automatically short. Instead, block new longs until the lower timeframe structure confirms a new bearish state.

This prevents the bot from immediately fading a macro shock.

## Rule 4 — Slow sentiment cannot override price

COT or WGC alone cannot create an entry.

They only increase/decrease confidence in a technically qualified setup.

---

# 10. Entry Rules

## 10.1 Long entry

All conditions:

```text
1H regime = BULLISH
30m confirmation = BULLISH
15m setup = valid pullback/reclaim
5m trigger = bullish confirmed close
technical_score >= 8
final_score >= 9
news_lock = FALSE
volatility_lock = FALSE
spread_veto = PASSED if genuine spread data are available and within limits
               UNEVALUATED if genuine spread data are unavailable
nearest_major_resistance - entry >= 1.5R
```

Entry should occur:

- on the 5m confirmation close, or
- on a controlled retest of the trigger level, if price does not become extended.

Avoid entering if the price has already moved more than `0.5 * ATR(5m)` away from the trigger before execution.

## 10.2 Short entry

Mirror the long conditions.

---

# 11. Stop-Loss Rules

The stop must be structural first and mathematical second.

## Long

Primary stop:

```text
SL = swing_low - buffer
```

where:

```text
buffer = 0.20*ATR5m

# If genuine bid/ask spread data are available, execution policy may instead use:
# buffer = max(0.20*ATR5m, spread*2)
# Never substitute a cross-source price difference for `spread`.
```

Also enforce:

```text
minimum_stop = 0.80*ATR5m
maximum_stop = 1.80*ATR5m
```

If structural stop distance > `1.80*ATR5m`, reject the setup or wait for a better entry.

## Short

```text
SL = swing_high + buffer
```

with the same volatility limits.

### Why this rule exists

A stop placed exactly on an obvious swing can be hit by normal noise. A small volatility-adjusted buffer reduces the chance of losing a technically correct setup simply because price briefly probes the level.

---

# 12. Take-Profit Rules

Let:

```text
R = abs(entry - stop)
```

### TP1

```text
TP1 = entry + 1.0R  (long)
TP1 = entry - 1.0R  (short)
```

Close **50%** at TP1.

### TP2

```text
TP2 = entry + 2.0R
```

or the nearest major 30m/1H structural level, whichever is closer.

Close **30%** at TP2.

### TP3

Target the next meaningful 1H liquidity/structure level, capped at approximately 3R for normal intraday conditions.

Close remaining **20%** at TP3.

### Structural target override

If TP2 or TP3 sits directly inside a strong opposing structure zone, move the target to the near side of the zone instead of placing the target through it.

---

# 13. Trade Management

## Break-even

Do not move to break-even immediately after entry.

Move SL to:

```text
entry + small execution buffer
```

only after:

1. TP1 has been reached, or
2. price closes beyond 1R and structure confirms continuation.

The preferred default is after TP1.

## Trailing

After TP1:

- trail behind confirmed 5m swing lows for longs;
- trail behind confirmed 5m swing highs for shorts;
- minimum trailing distance = `0.75*ATR5m`;
- never move the stop farther from price.

After TP2:

- trail using 15m structure rather than 5m noise.

## Early exit

Exit the remaining position before TP if:

- 15m closes decisively through the structural invalidation level;
- a fresh high-impact surprise changes the macro bias;
- spread becomes abnormal and liquidity conditions deteriorate;
- the trade remains stalled for an unusually long period and momentum/ADX collapses.

Define a maximum holding time parameter in the bot rather than using an arbitrary infinite hold.

---

# 14. Position Sizing

Risk per trade:

```text
0.50% of account equity
```

Maximum daily risk:

```text
1.50% of account equity
```

Maximum consecutive losses:

```text
3
```

After the third loss:

```text
STOP NEW TRADES FOR THE DAY
```

### Position size formula

Let:

```text
E = current equity
r = risk fraction (0.005 default)
D = stop distance in price units
V = account-currency value of a 1.0 price-unit move for one lot
```

Then:

```text
risk_cash = E * r
position_lots = risk_cash / (D * V)
```

Do not hardcode `V`.

Read the broker's actual:

- contract size
- tick size
- tick value
- margin rules
- quote currency

and calculate the value dynamically.

### Hard limits

The bot must refuse an order if:

- calculated size <= 0;
- free margin is insufficient;
- SL is missing;
- risk exceeds account policy;
- broker's minimum/maximum size is violated;
- genuine bid/ask spread exceeds the configured maximum, **when genuine spread data are available**; if unavailable, surface `spread_veto_status=UNEVALUATED` rather than inventing a value.

---

# 15. Trade Skip Rules

Return `NO TRADE` when any of these are true:

1. High-impact event lock active.
2. Emergency-news lock active.
3. ATR percentile > 95.
4. True bid/ask spread > 2x rolling median **when genuine spread data are available**. If unavailable, do not apply this veto; record the data-quality gap.
5. 1H direction is neutral and 30m is conflicting.
6. Technical score < 8/12.
7. Final score < 9.
8. Entry is too close to a major opposing level.
9. Required stop is > 1.8 ATR5m.
10. Expected TP1 is < 1R away after accounting for structure.
11. Price is already extended by > 0.5 ATR5m beyond the trigger.
12. COT/sentiment conflict is extreme and price structure is unstable.
13. Data-quality flag is degraded on any critical input.
14. Three consecutive losses already occurred today.
15. Daily loss limit has been reached.
16. Market is closed or the broker feed is stale.

The bot should report the exact reason code, e.g.:

```text
NO_TRADE_NEWS_LOCK
NO_TRADE_VOLATILITY_EXTREME
NO_TRADE_LOW_CONFLUENCE
NO_TRADE_POOR_RR
NO_TRADE_DATA_STALE
NO_TRADE_DAILY_RISK_LIMIT
```

---

# 16. Confidence Levels

Confidence should describe **setup quality**, not probability of profit.

| Confidence | Requirements | Action |
|---|---|---|
| LOW | 8-9 score or mixed macro | Normally skip |
| MEDIUM | 9-10, normal volatility, clear structure | Eligible |
| HIGH | 11+, strong multi-timeframe alignment, no macro conflict | Eligible |
| BLOCKED | any hard veto | No trade |

Never output statements such as “90% chance of winning.”

Instead output:

```text
confidence = HIGH
reason = "Strong 1H/30m alignment + 15m pullback + 5m trigger; macro neutral-to-supportive; no event lock"
```

---

# 17. Sessions

The preferred intraday windows are:

1. London/European active hours
2. London-New York overlap
3. US session around major liquidity windows, excluding event blackouts

Avoid treating every minute of the 24-hour market as equally tradable.

Use session-aware historical statistics because:

- spread varies;
- liquidity varies;
- volatility varies;
- XAUUSD behavior changes around major market opens.

The bot should retain UTC internally but map sessions using an explicit timezone configuration that accounts for daylight-saving changes.

---

# 18. News Processing Details

## 18.1 Required event fields

Every important release should include:

```text
scheduled_time
actual
forecast
previous
revision
surprise
surprise_zscore
initial_gold_bias
post_release_market_confirmation
```

## 18.2 Initial bias vs confirmed bias

Immediately after a release, produce both:

```text
fundamental_bias = based on economic surprise
market_response_bias = based on actual USD/yield/gold movement
```

Do not treat these as identical.

Example:

```text
weak NFP -> fundamental gold bias = bullish
BUT
10Y yield rises and USD rises -> market response = bearish
```

The signal engine should wait for market confirmation rather than automatically buying the headline.

---

# 19. Recent Case Study / Replay

This section demonstrates how the methodology should interpret a recent event. It is a **historical replay**, not a claim that a specific trade was actually executed by this system.

## Case A: September 28, 2026 — macro shock and gold selloff

Reported market data showed gold falling sharply on September 28, with Reuters reporting spot gold reaching about $4,110.55 before settling near $4,136.81. The report linked the move to rising oil prices, higher Treasury yields, a stronger US dollar and increased expectations for further Federal Reserve tightening. citeturn993179news64

Investing.com's daily XAU/USD history also records a September 28 low near $4,110.95 and a roughly 4% daily decline. citeturn350008search0

### How the methodology would process it

#### Step 1 — Event/context layer

The geopolitical development was not treated as “risk-off = buy gold.”

Instead:

```text
geopolitical shock
    -> oil higher
    -> inflation concern higher
    -> expected policy rate higher
    -> Treasury yields higher
    -> USD stronger
    -> gold opportunity cost higher
```

Macro conclusion: `BEARISH / HIGH CONVICTION`.

#### Step 2 — Market confirmation

The observed gold decline confirmed that the rate/yield channel was dominating the safe-haven channel at that moment. Reuters explicitly described stronger yields and dollar strength as pressure on gold. citeturn993179news64

#### Step 3 — Technical response

The technical engine should **not** sell the first giant 5m red candle.

It should wait for:

```text
1H bearish regime
30m lower high / failed reclaim
15m pullback into broken support
5m bearish rejection or break-retest
ATR returns below extreme percentile
```

#### Step 4 — Entry model

Illustrative—not historical execution:

```text
Direction: SHORT
Entry: after 5m failed reclaim of broken 15m support
SL: above confirmed 5m/15m swing high + volatility buffer
TP1: 1R
TP2: 2R / nearest 30m support
TP3: next 1H support, capped near 3R
```

The key lesson is not the exact price; it is the sequence:

```text
macro shock -> yields/USD confirmation -> structure break -> pullback -> 5m trigger
```

---

## Case B: October 2, 2026 — weak payrolls but conflicting second-order effects

The official BLS release reported September nonfarm payroll employment up only 29,000 and unemployment at 4.2%. Average hourly earnings were up 3.0% over 12 months, while July and August payroll gains were revised down by a combined 60,000. citeturn466510view0

BLS had scheduled the Employment Situation release for 8:30 a.m. ET on October 2, 2026. citeturn993179search0turn993179search3

### Fundamental first-order reading

```text
weaker labor data
-> normally less hawkish Fed expectations
-> normally lower yields/USD
-> normally supportive for gold
```

### But the actual gold response was not a simple one-way move

Reuters reported that gold initially reacted to the weak jobs data but remained under pressure during the session while the dollar and Treasury-yield backdrop remained important. citeturn993179news58

### Bot behavior

From 30 minutes before the release through the scheduled blackout:

```text
NO TRADE
```

After the event:

1. parse NFP, unemployment, wages and revisions;
2. compute the surprise score;
3. observe 5m/15m behavior for at least several confirmed candles;
4. compare USD and yields;
5. only then allow a new setup.

This prevents the classic failure mode:

```text
weak NFP -> immediate BUY GOLD -> reversal -> stop out
```

The methodology intentionally separates **economic interpretation** from **execution confirmation**.

---

# 20. Example of a Full Signal Record

The bot should emit machine-readable output like:

```json
{
  "symbol": "XAUUSD",
  "timestamp_utc": "2026-10-02T13:25:00Z",
  "signal": "SHORT",
  "state": "ELIGIBLE",
  "entry": 4188.20,
  "stop_loss": 4200.80,
  "take_profit": {
    "tp1": 4175.60,
    "tp2": 4162.99,
    "tp3": 4149.40
  },
  "risk_reward": {
    "tp1": 1.0,
    "tp2": 2.0,
    "tp3": 3.08
  },
  "technical_score": 10,
  "macro_score": -1.1,
  "sentiment_score": -0.5,
  "confidence": "HIGH",
  "news_lock": false,
  "volatility_regime": "NORMAL",
  "spread_status": "UNAVAILABLE",
  "spread_veto_status": "UNEVALUATED",
  "reason_codes": [
    "H1_BEARISH",
    "M30_STRUCTURE_CONFIRM",
    "M15_PULLBACK",
    "M5_BREAK_RETEST",
    "USD_SUPPORTIVE_TO_SHORT",
    "REAL_YIELD_SUPPORTIVE_TO_SHORT",
    "NO_HIGH_IMPACT_EVENT_LOCK"
  ]
}
```

The numbers above are illustrative. Production values must be calculated from the live feed at the signal timestamp.

---

# 21. Pseudocode

```python
def generate_signal(market, macro, sentiment, calendar, account):
    # -----------------------------------------
    # 1. Data validation
    # -----------------------------------------
    if not market.is_healthy():
        return no_trade("NO_TRADE_DATA_STALE")

    # -----------------------------------------
    # 2. News gate
    # -----------------------------------------
    if calendar.high_impact_lock_active():
        return no_trade("NO_TRADE_NEWS_LOCK")

    # -----------------------------------------
    # 3. Market-condition gate
    # -----------------------------------------
    if market.true_spread_available():
        if market.spread_ratio_to_median() > 2.0:
            return no_trade("NO_TRADE_SPREAD_EXTREME")
    else:
        market.data_quality.add("SPREAD_UNAVAILABLE")
        market.veto_status["spread"] = "UNEVALUATED"

    if market.atr_percentile("5m") > 95:
        return no_trade("NO_TRADE_VOLATILITY_EXTREME")

    # -----------------------------------------
    # 4. Multi-timeframe state
    # -----------------------------------------
    h1 = analyze_1h(market.h1)
    m30 = analyze_30m(market.m30, h1)
    m15 = analyze_15m(market.m15, m30)
    m5 = analyze_5m(market.m5, m15)

    if h1.direction == "NEUTRAL":
        return no_trade("NO_TRADE_H1_NEUTRAL")

    # -----------------------------------------
    # 5. Score both directions
    # -----------------------------------------
    long_technical = score_long(h1, m30, m15, m5, market)
    short_technical = score_short(h1, m30, m15, m5, market)

    # -----------------------------------------
    # 6. Add macro + sentiment
    # -----------------------------------------
    long_score = combine(long_technical, macro, sentiment, "LONG")
    short_score = combine(short_technical, macro, sentiment, "SHORT")

    candidate = choose_candidate(long_score, short_score)

    if candidate is None:
        return no_trade("NO_TRADE_LOW_CONFLUENCE")

    if candidate.technical_score < 8:
        return no_trade("NO_TRADE_TECHNICAL_SCORE")

    if candidate.final_score < 9:
        return no_trade("NO_TRADE_FINAL_SCORE")

    # -----------------------------------------
    # 7. Entry and stop
    # -----------------------------------------
    entry = calculate_entry(candidate, market)
    stop = calculate_structural_stop(candidate, market)

    if not valid_stop_distance(entry, stop, market.atr("5m")):
        return no_trade("NO_TRADE_BAD_STOP_DISTANCE")

    # -----------------------------------------
    # 8. Targets
    # -----------------------------------------
    tp1 = target_at_R(entry, stop, 1.0, candidate.direction)
    tp2 = structural_or_R_target(entry, stop, market.m30, 2.0, candidate.direction)
    tp3 = structural_or_R_target(entry, stop, market.h1, 3.0, candidate.direction)

    if not acceptable_reward_to_structure(entry, stop, tp1, tp2, tp3):
        return no_trade("NO_TRADE_POOR_RR")

    # -----------------------------------------
    # 9. Position size
    # -----------------------------------------
    size = calculate_position_size(
        equity=account.equity,
        risk_fraction=0.005,
        entry=entry,
        stop=stop,
        contract_metadata=account.instrument_metadata
    )

    if not account.risk_limits_allow(size, entry, stop):
        return no_trade("NO_TRADE_RISK_LIMIT")

    return build_signal(candidate, entry, stop, tp1, tp2, tp3, size)
```

---

# 22. Data Refresh Schedule

## Tick/intraday market data

- Feed continuously.
- Rebuild indicators whenever a 5m candle closes.
- Higher-timeframe states update only when those candles close.

## Calendar

- Refresh on startup.
- Refresh at least every 15 minutes during active sessions.
- Force-refresh 60 minutes before any expected high-impact event.

## Macro rates

- Refresh daily.
- Immediate refresh after significant US policy/news events if a new official observation exists.

## COT

- Refresh weekly after the new report becomes available.

## WGC

- Refresh when a new report/data release appears.

---

# 23. Conflict Resolution Matrix

| Situation | Action |
|---|---|
| Technical + macro + sentiment agree | Eligible if risk/reward passes |
| Technical strong, macro neutral | Eligible with normal risk |
| Technical strong, macro strongly opposite | Usually wait; require structural reversal before taking opposite trade |
| Technical weak, macro strong | No trade |
| COT opposite but price trend strong | Reduce confidence, do not automatically reverse |
| WGC opposite intraday signal | Ignore for entry; retain as structural context |
| News blackout | No trade |
| Extreme volatility | No trade |
| Strong trend but entry too extended | Wait for pullback |
| Strong setup but TP blocked by major level | No trade or wait for break/retest |

---

# 24. Required Logging

Every scan should be logged, not only trades.

Example:

```text
SCAN 2026-10-02 13:30 UTC

H1: BULLISH
M30: BULLISH
M15: PULLBACK
M5: NO_TRIGGER
Macro: +0.4
COT: +0.5
WGC: +1
News: CLEAR
ATR5: 72nd percentile
Spread: UNAVAILABLE
Spread Veto: UNEVALUATED
Technical Score: 7/12
Final State: NO_TRADE_LOW_CONFLUENCE
```

This logging is essential for later determining which filters actually improve performance.

---

# 25. Backtesting Requirements

Do not evaluate this methodology on win rate alone.

Record:

- total trades
- win rate
- average R
- expectancy in R
- profit factor
- maximum drawdown
- maximum consecutive losses
- average holding time
- TP1 hit rate
- TP2 hit rate
- TP3 hit rate
- stop-out rate after reaching +0.5R
- results by session
- results by timeframe regime
- results before/after news events
- results by volatility percentile
- results by macro regime

### Primary metric

Use expectancy:

```text
Expectancy_R =
    (WinRate * AvgWin_R)
    - (LossRate * AvgLoss_R)
```

Do not optimize parameters until the strategy has been evaluated out-of-sample.

---

# 26. Walk-Forward Validation

Use at least:

```text
Training: 6-12 months
Validation: 2-3 months
Test: 2-3 months
```

Then roll the window forward.

Do not tune EMA/RSI/ATR parameters on the entire historical data set and report the result as if it were out-of-sample.

Also test across:

- low volatility
- high volatility
- inflation shocks
- rate-cycle changes
- geopolitical stress
- strong USD regimes
- weak USD regimes

---

# 27. Failure Modes the Bot Must Avoid

## Failure 1 — Chasing news candles

Bad:

```text
NFP misses -> BUY immediately
```

Correct:

```text
NFP misses
-> classify surprise
-> wait through event lock
-> observe USD/yields
-> wait for 15m/5m structure
-> enter only after confirmation
```

## Failure 2 — Indicator voting without context

Bad:

```text
RSI bullish + MACD bullish = buy
```

Correct:

```text
location + structure + trend + volatility + macro + news + trigger
```

## Failure 3 — Fighting a macro shock

Bad:

```text
Gold fell a lot -> must bounce
```

Correct:

```text
Ask whether the fall was caused by a durable regime change.
If yes, wait for structure to reverse before fading it.
```

## Failure 4 — Treating COT as current

COT is delayed. It cannot replace current price/yield/USD data.

## Failure 5 — Using an unfinished candle

Do not generate confirmed signals from an incomplete 5m, 15m, 30m or 1H candle.

## Failure 6 — Ignoring revisions

NFP, GDP, PCE and similar releases can be revised. Store the original and revised value and calculate the impact of both.

---

# 28. Minimum Production Architecture

```text
                +----------------------+
                | Public Data Sources  |
                +----------+-----------+
                           |
              +------------+-------------+
              |                          |
       Market Data                   Macro/News
              |                          |
              +------------+-------------+
                           |
                    Normalization Layer
                           |
              +------------+-------------+
              |                          |
        Technical Engine          Macro Engine
              |                          |
              +------------+-------------+
                           |
                     Sentiment Engine
                           |
                     News Risk Gate
                           |
                Multi-Timeframe Engine
                           |
                   Confluence Scorer
                           |
                  Risk / Position Size
                           |
                    Signal Generator
                           |
                 LONG / SHORT / NO TRADE
```

Each layer should expose structured output instead of free-form text.

---

# 29. Final Decision Contract

The signal engine should never return only “BUY” or “SELL”.

It must return:

```text
SIGNAL
DIRECTION
ENTRY
STOP LOSS
TP1
TP2
TP3
POSITION SIZE
TECHNICAL SCORE
MACRO SCORE
SENTIMENT SCORE
VOLATILITY REGIME
NEWS STATE
CONFIDENCE
REASON CODES
DATA QUALITY
INVALIDATION CONDITION
```

If any required field is missing, return `NO TRADE`.

---

# 30. Public Source Directory

## Market data

- Dukascopy historical data: https://www.dukascopy.com/swiss/english/marketwatch/historical/
- EV Trading Labs historical OHLCV mirror: https://evtradelabs.com/data
- TradingView XAUUSD visualization: https://www.tradingview.com/symbols/XAUUSD/
- Investing.com XAU/USD history: https://www.investing.com/currencies/xau-usd-historical-data

## Macro / rates

- US Treasury nominal yields: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?type=daily_treasury_yield_curve
- US Treasury real yields: https://home.treasury.gov/resource-center/data-chart-center/interest-rates/TextView?type=daily_treasury_real_yield_curve
- FRED: https://fred.stlouisfed.org/
- FRED T10YIE: https://fred.stlouisfed.org/series/T10YIE
- FRED DTWEXBGS: https://fred.stlouisfed.org/series/DTWEXBGS
- FRED VIXCLS: https://fred.stlouisfed.org/series/VIXCLS

## Economic calendar / official releases

- BLS release calendar: https://www.bls.gov/schedule/2026/home.htm
- BLS Employment Situation schedule: https://www.bls.gov/schedule/news_release/empSit.htm
- BLS ICS calendar: https://www.bls.gov/schedule/news_release/bls.ics
- BEA release schedule: https://www.bea.gov/news/schedule/
- Federal Reserve FOMC calendars: https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm
- Federal Reserve SEP: https://www.federalreserve.gov/monetarypolicy/fomcprojtabl20260916.htm
- ECB calendar: https://www.ecb.europa.eu/press/calendars/mgcgc/html/index.en.html
- ECB decisions: https://www.ecb.europa.eu/press/govcdec/mopo/html/index.en.html
- EIA WPSR: https://www.eia.gov/petroleum/supply/weekly/
- ISM release calendar: https://www.ismworld.org/supply-management-news-and-reports/reports/rob-report-calendar/

## Positioning / gold fundamentals

- CFTC COT: https://www.cftc.gov/MarketReports/CommitmentsofTraders/index.htm
- CFTC historical reports: https://www.cftc.gov/MarketReports/CommitmentsofTraders/HistoricalViewable/index.htm
- World Gold Council commentary: https://www.gold.org/goldhub/research/gold-market-commentary
- World Gold Council central banks: https://www.gold.org/goldhub/research/central-banks
- World Gold Council demand/supply data: https://www.gold.org/goldhub/data/gold-demand-by-country

---

# 31. Implementation Checklist

Before enabling live signals, verify that the bot can answer “yes” to every item:

```text
[ ] XAUUSD feed is synchronized to UTC.
[ ] 5m/15m/30m/1H bars are complete and validated.
[ ] The market/execution layer explicitly reports whether genuine bid/ask spread data are available.
[ ] EMA20/50/200 are calculated from close.
[ ] RSI14 is calculated from close.
[ ] MACD12/26/9 is calculated from close.
[ ] ADX14 and DI are calculated.
[ ] ATR14 is calculated.
[ ] ATR percentile is available.
[ ] Previous-day/session levels are calculated.
[ ] Economic calendar is loaded.
[ ] High-impact blackout rules are active.
[ ] NFP/CPI/PCE/FOMC events are parsed correctly.
[ ] US nominal and real yields are available.
[ ] USD regime is available.
[ ] COT positioning is up to date and age-tagged.
[ ] WGC structural bias is available and age-tagged.
[ ] Position-size calculation uses broker contract metadata.
[ ] Daily loss limit is enforced.
[ ] Consecutive-loss limit is enforced.
[ ] Every signal has SL + TP1 + TP2 + TP3.
[ ] Every NO TRADE has a reason code.
[ ] Critical data-quality failures force NO TRADE.
[ ] Genuine bid/ask spread status is explicitly reported; when unavailable, spread vetoes are marked UNEVALUATED rather than replaced with a proxy.
[ ] Backtest and walk-forward validation completed.
[ ] Paper trading completed before live deployment.
```

---

# 32. Core Rule in One Sentence

> **Trade only when the 1H regime, 30m structure, 15m setup, and 5m trigger agree with a supportive macro environment, while news risk and volatility are controlled; otherwise return NO TRADE.**

---

## Source verification notes

The implementation above is based on publicly accessible sources checked on/around 2026-10-02. Examples used in the case-study section are explicitly labeled as historical replays or illustrative execution logic rather than claims of executed proprietary trades.
