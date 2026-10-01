# XAU Radar — Final MVP Specification

## 1. Product

**XAU Radar** is a free mobile-first day-trading assistant focused exclusively on **XAUUSD (Gold)**.

Its job is simple:

> **Collect fresh intraday Gold trade ideas from multiple independent sources, compare them, and turn the strongest agreement into one clear 15-minute trading setup.**

It does **not** execute trades and does not pretend to predict the market.

---

# 2. Core Trading Model

### Timeframes

| TF      | Purpose                       |
| ------- | ----------------------------- |
| **15M** | **Primary signal timeframe**  |
| **5M**  | Entry confirmation/refinement |
| **1H**  | Market context                |
| 30M     | Not required initially        |
| 1M      | Excluded from MVP             |

The system must **never mix Daily/H4/Weekly trade ideas into the 15M consensus**.

Higher timeframes can provide context but cannot vote on the primary signal.

---

# 3. Main Screen

The user opens the app and immediately sees:

```text
┌──────────────────────────────┐
│ XAU RADAR             ● LIVE │
│ Gold / XAUUSD                │
├──────────────────────────────┤
│                              │
│       CURRENT PRICE          │
│          4,278.30            │
│                              │
│       15M CONSENSUS           │
│                              │
│          ▲ LONG              │
│       STRONG CONSENSUS       │
│                              │
│  Entry       4,275–4,280     │
│  Stop Loss   4,262           │
│                              │
│  TP1         4,295           │
│  TP2         4,315           │
│  TP3         4,340           │
│                              │
│  R:R         1 : 1.5 / 3.0  │
│                              │
│  4 / 5 sources agree         │
│                              │
│     [ VIEW ANALYSIS ]        │
└──────────────────────────────┘
```

If there is insufficient agreement:

```text
NO CONSENSUS

Sources are currently divided.

LONG   2
SHORT  2
NEUTRAL 1

Waiting for stronger agreement.
```

**The app must never manufacture a trade signal simply because the user expects one.**

---

# 4. Source Collection

Every source is converted into a standardized internal structure.

```text
TradeIdea {
    id
    source
    sourceUrl
    author
    publishedAt
    collectedAt

    symbol
    timeframe

    direction

    entryType
    entryLow
    entryHigh

    stopLoss

    takeProfits[]

    triggerCondition
    invalidationCondition

    reasoning

    confidence
    freshness

    sourceFingerprint
}
```

### Required filtering

Before an idea reaches the consensus engine:

```text
XAUUSD?
   ↓
Intraday?
   ↓
15M relevant?
   ↓
Fresh?
   ↓
Contains actionable levels?
   ↓
Not duplicate?
   ↓
VALID IDEA
```

---

# 5. Source Independence

This is extremely important.

If five websites copy the same analyst's idea, the engine must **not treat that as five independent votes**.

Example:

```text
Source A ─┐
Source B ─┤
Source C ─┤── same underlying idea
Source D ─┘
```

should potentially count as:

```text
1 independent idea
```

rather than:

```text
4 votes
```

The system should compare:

* direction
* entry
* SL
* TP
* wording/reasoning
* publication time
* author
* source relationships

and assign an **independence factor**.

---

# 6. Consensus Engine

The engine should not simply count LONG vs SHORT.

### Consensus components

```text
Direction agreement
        +
Entry-zone agreement
        +
SL agreement
        +
TP agreement
        +
Technical-reason agreement
        +
Freshness
        +
Source independence
        +
1H context
        +
5M confirmation
```

### Example

```text
Source A → LONG
Entry 4275–4280
SL 4262
TP 4295 / 4315

Source B → LONG
Entry 4276–4281
SL 4264
TP 4298 / 4320

Source C → LONG
Entry 4274–4279
SL 4263
TP 4296 / 4318

Source D → SHORT
Entry 4285
SL 4300
TP 4260
```

The system sees that A/B/C are highly clustered.

Result:

```text
LONG

Consensus Strength: HIGH

Entry: 4275–4280
SL: 4263

TP1: 4296
TP2: 4317
```

---

# 7. Consensus Score

Use a **Consensus Strength score**, not a claimed probability of winning.

```text
0–39     WEAK
40–59    DEVELOPING
60–74    MODERATE
75–89    STRONG
90–100   VERY STRONG
```

This score represents **agreement among the collected sources and setup characteristics**.

It must **never** be displayed as:

> "87% chance of profit."

---

# 8. Entry Calculation

Different sources may provide:

```text
4275
4277–4281
4279
4280–4283
```

The engine clusters these values.

Result:

```text
Consensus Entry Zone
4277–4281
```

Outliers should not distort the zone.

---

# 9. Stop Loss Calculation

Same principle.

Example:

```text
4260
4262
4263
4265
4300   ← outlier
```

The engine clusters the relevant SL values.

Result:

```text
Consensus SL: 4262–4265
```

The final SL should also be checked against:

* current market price
* minimum sensible distance
* setup invalidation
* risk/reward

---

# 10. Multiple Take Profits

This is a core feature.

The engine should support:

### TP1

Nearest meaningful target.

### TP2

Intermediate target.

### TP3

Extended target.

Example:

```text
Entry: 4278
SL:    4263

TP1:   4295
TP2:   4315
TP3:   4340
```

The user can select:

```text
○ TP1 only
○ TP1 + TP2
● TP1 + TP2 + TP3
```

Later, we can add allocation:

```text
TP1 → 30%
TP2 → 30%
TP3 → 40%
```

This allocation feature can be deferred if necessary.

---

# 11. Risk/Reward

Automatically calculate:

```text
Risk = Entry − SL

Reward TP1
Reward TP2
Reward TP3

R:R TP1
R:R TP2
R:R TP3
```

Example:

```text
Risk: 15 points

TP1 → 17 points → 1:1.13
TP2 → 37 points → 1:2.47
TP3 → 62 points → 1:4.13
```

No setup should be promoted simply because it has a high R:R; the consensus and technical evidence still matter.

---

# 12. 1H Context

The 1H timeframe does **not vote**.

It provides context:

```text
1H TREND

Bullish
```

or:

```text
1H TREND

Bearish
```

Then:

```text
15M → LONG
1H  → LONG

Alignment: SUPPORTIVE
```

or:

```text
15M → LONG
1H  → SHORT

Alignment: COUNTER-TREND
```

This lets the user understand the situation without contaminating the 15M consensus.

---

# 13. 5M Confirmation

Once a 15M consensus exists, the engine watches 5M price action.

Possible states:

```text
DEVELOPING
     ↓
READY
     ↓
5M CONFIRMATION
     ↓
CONFIRMED
```

Or:

```text
DEVELOPING
     ↓
INVALIDATED
```

The MVP should keep confirmation deterministic.

Possible confirmation inputs:

* price reaches entry zone
* 5M structure agrees
* breakout/retest
* rejection
* momentum
* invalidation level

---

# 14. Signal Lifecycle

```text
NO SETUP
    ↓
DEVELOPING
    ↓
READY
    ↓
CONFIRMED
    ↓
ACTIVE
    ↓
TP1 HIT
    ↓
TP2 HIT
    ↓
TP3 HIT
```

Alternative:

```text
DEVELOPING
    ↓
INVALIDATED
```

or:

```text
READY
    ↓
EXPIRED
```

Every signal gets a timestamp.

---

# 15. Signal Expiration

A 15M trade idea should not remain valid forever.

Each idea receives:

```text
publishedAt
expiresAt
```

Freshness should be one of the strongest factors in the scoring engine.

For example:

```text
< 15 min      VERY FRESH
15–30 min     FRESH
30–60 min     AGING
60+ min       EXPIRED / CONTEXT ONLY
```

Exact expiration rules should ultimately depend on the source and setup type.

---

# 16. Notifications

MVP notifications:

### Consensus forming

> XAUUSD 15M consensus is developing.

### Strong consensus

> XAUUSD LONG consensus strengthened.

### Entry approaching

> XAUUSD is approaching the consensus entry zone.

### Confirmation

> XAUUSD LONG confirmed on 5M.

### Invalidation

> XAUUSD LONG setup invalidated.

### Target

> XAUUSD TP1 reached.

Notifications must include timestamp and setup price levels.

---

# 17. Source Page

The user can inspect why the consensus exists.

```text
CONSENSUS SOURCES

✓ Source A
   LONG
   Entry 4275–4280
   SL 4262
   TP 4295 / 4315

✓ Source B
   LONG
   Entry 4276–4281
   SL 4264
   TP 4298 / 4320

✓ Source C
   LONG
   Entry 4274–4279
   SL 4263
   TP 4296 / 4318

✗ Source D
   SHORT
```

Each source should have:

**View Original**

which opens the original source.

---

# 18. Market Data

For the initial implementation, the market-data adapter should be separated from the application.

The MVP can use **Gold API** as one candidate because its current terms explicitly permit commercial use in web/mobile applications, and its free tier provides real-time gold prices. ([Gold API][1])

However, the architecture should allow another provider to replace it later.

```text
MarketDataProvider
        │
        ├── GoldApiProvider
        ├── FutureProvider
        └── MockProvider
```

Do **not** hard-wire the application directly to one provider.

---

# 19. Trading Ideas Providers

Likewise:

```text
IdeaSource
    │
    ├── SourceAdapterA
    ├── SourceAdapterB
    ├── SourceAdapterC
    └── SourceAdapterD
```

Each adapter converts external information into:

```text
TradeIdea
```

This is critical because some sources provide actual M15 ideas while others only provide broader analysis.

For example, MetaTrader currently exposes user-published XAUUSD M15 ideas containing explicit entry, TP and invalidation levels, demonstrating that this type of data exists publicly. ([MetaTrader][2])

**But an accessible webpage is not automatically permission to scrape or redistribute it.** Every production source adapter must pass the licensing/automation review before being enabled.

---

# 20. $0 Infrastructure

### Mobile

**Flutter**

### Backend

**Supabase Free**

Use for:

* cached signals
* source records
* signal history
* user preferences
* notification state

### Market data

Free provider with compatible commercial terms.

### Source collection

Scheduled backend jobs / serverless functions where permitted.

### Notifications

**Firebase Cloud Messaging**

### Charts

**TradingView Lightweight Charts** or another permissively licensed chart library, subject to final license verification.

### Repository

**GitHub Free**

---

# 21. Database

Minimum schema:

```text
sources
───────
id
name
url
license_url
automation_allowed
commercial_use_allowed
enabled
created_at

trade_ideas
───────────
id
source_id
symbol
timeframe
direction
entry_low
entry_high
stop_loss
take_profits
trigger_condition
invalidation_condition
reasoning
author
published_at
collected_at
fingerprint

consensus_signals
──────────────────
id
symbol
timeframe
direction
strength
entry_low
entry_high
stop_loss
tp1
tp2
tp3
status
created_at
updated_at
expires_at

signal_sources
───────────────
signal_id
trade_idea_id
independence_weight
contribution_score

market_snapshots
────────────────
symbol
price
bid
ask
timestamp
```

---

# 22. Backend Architecture

```text
                 ┌─────────────────┐
                 │ External Sources│
                 └────────┬────────┘
                          ↓
                 ┌─────────────────┐
                 │ Source Adapters │
                 └────────┬────────┘
                          ↓
                 ┌─────────────────┐
                 │ Normalizer      │
                 └────────┬────────┘
                          ↓
                 ┌─────────────────┐
                 │ Freshness Filter│
                 └────────┬────────┘
                          ↓
                 ┌─────────────────┐
                 │ Duplicate Filter│
                 └────────┬────────┘
                          ↓
                 ┌─────────────────┐
                 │ Cluster Engine  │
                 └────────┬────────┘
                          ↓
                 ┌─────────────────┐
                 │ Consensus Engine│
                 └────────┬────────┘
                          ↓
              ┌───────────┴───────────┐
              ↓                       ↓
       1H Context              5M Confirmation
              │                       │
              └───────────┬───────────┘
                          ↓
                 ┌─────────────────┐
                 │ Signal Manager  │
                 └────────┬────────┘
                          ↓
                ┌───────────────────┐
                │ Flutter Application│
                └───────────────────┘
```

---

# 23. AI's Role

AI is **not the trading engine**.

AI may be used for:

* summarizing source reasoning
* identifying common themes
* explaining why sources agree
* detecting potential copied ideas
* converting messy natural language into structured fields when deterministic extraction fails

AI must **not invent**:

* Entry
* Stop Loss
* Take Profit
* direction

If those values cannot be reliably extracted, the source should be marked:

```text
INSUFFICIENT DATA
```

rather than hallucinating missing levels.

---

# 24. MVP UI

Keep the first version extremely focused.

### Screen 1 — Radar

The primary screen.

### Screen 2 — Signal

Complete current setup.

### Screen 3 — Sources

Why the consensus exists.

### Screen 4 — History

Previous signals and their eventual status.

### Screen 5 — Settings

```text
Primary timeframe
    15M

Confirmation
    5M

Context
    1H

Targets
    TP1
    TP1 + TP2
    TP1 + TP2 + TP3

Notifications
    Consensus
    Entry
    Confirmation
    Invalidation
    Targets
```

No social network.

No chat.

No broker connection.

No copy trading.

No account management.

No complicated indicators dashboard.

---

# 25. MVP Acceptance Criteria

The MVP is finished only when it can do this end-to-end:

```text
1. Get current XAUUSD price
        ↓
2. Collect permitted free trading ideas
        ↓
3. Identify their timeframe
        ↓
4. Keep relevant 15M ideas
        ↓
5. Reject stale ideas
        ↓
6. Detect duplicates
        ↓
7. Determine LONG / SHORT agreement
        ↓
8. Cluster Entry / SL / TP
        ↓
9. Calculate consensus strength
        ↓
10. Check 1H context
        ↓
11. Monitor 5M confirmation
        ↓
12. Produce one clear setup
        ↓
13. Update its lifecycle
        ↓
14. Notify the user
        ↓
15. Preserve the original sources
```

If any of these fails, the system should show **NO CONSENSUS / INSUFFICIENT DATA**, not fabricate a result.

---

# 26. The Product's Core Promise

The entire MVP can be reduced to one sentence:

> **You don't need to read 10 Gold analyses — XAU Radar finds the relevant 15-minute ideas, compares them, and shows you where the strongest agreement is.**

That's the MVP I would build first.

[1]: https://gold-api.com/terms?utm_source=chatgpt.com "Terms of Service :: Gold API"
[2]: https://www.metatrader.com/en/ideas/charts/metals/15?utm_source=chatgpt.com "Page 15 — Chart-Based Trading Ideas for Metals | MetaTrader"
