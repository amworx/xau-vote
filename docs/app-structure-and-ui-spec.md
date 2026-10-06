# XV — App Structure & UI Specification

A standalone specification for building the XV Android application from scratch.
Covers information architecture, design system, and the layout and behaviour of
every screen.

---

## 1. Product framing

**XV** is a free, mobile-first XAUUSD (spot gold) analysis app. It publishes one
15-minute setup at a time, explains what supports and blocks it, and abstains
when the evidence does not support a view.

**It does not execute trades.**

### 1.1 Governing rules

These constrain every screen and are not negotiable.

1. **15M is the only signal timeframe.** 5M provides confirmation. 1H is context
   and never votes.
2. **Never fabricate.** When data or agreement is insufficient, the app states so
   and publishes nothing. No invented direction, level, or probability.
3. **Agreement is not probability.** Consensus strength must never be rendered as
   "% chance" or any win-rate implication.
4. **Independence is strict.** Duplicate or copied material counts as one vote.
   Unknown independence never counts as independent.
5. **Silence is not neutrality.** An unmeasured input is `null`, never `0`. The
   UI must visually distinguish "not measured" from "measured as neutral".
6. **Events and news annotate; they never vote.** They may suppress, delay, or
   explain a signal, never create or flip one.
7. **Freshness is first-class.** Every reading carries an as-of time and a
   staleness state.

### 1.2 Audience

A retail day trader checking gold on a phone, often in brief sessions. Dense
information, low tolerance for filler. Every screen must be readable at a glance
and honest when it has nothing.

---

## 2. Information architecture

### 2.1 Bottom navigation — 6 destinations

A floating pill bar, detached from the screen edge, carrying the active label
inline with the active icon.

| # | Label | Icon | Destination |
|---|---|---|---|
| 1 | **Radar** | concentric target | Primary decision surface |
| 2 | **Signal** | rising line chart | Levels for the active setup |
| 3 | **Sources** | stacked layers | Provenance and method |
| 4 | **History** | clock | Past setups and measured outcomes |
| 5 | **Events** | calendar | Economic calendar |
| 6 | **Settings** | sliders | Updates, permissions, about |

### 2.2 Navigation rules

- The bar floats above content with safe-area clearance; content scrolls beneath it.
- The active slot **expands to fit its label**; inactive slots are icon-only.
  The pill re-centres on every change so the active item stays visually anchored.
- Tapping the active item again returns that tab to scroll position top.
- No screen deeper than one level. Any detail opens as a bottom sheet, not a
  pushed route.
- State is preserved per tab on switch.

### 2.3 Screen-to-screen flow

```
Radar ──► Signal        (view levels for the active setup)
      └─► Events        (tap an event caution line)
History ─► bottom sheet (open one past setup)
Sources ─► bottom sheet (open one source / method detail)
Settings ─► App Updates (check, download, install)
```

---

## 3. Design system

### 3.1 Colour

Light theme only.

| Token | Hex | Use |
|---|---|---|
| `mist` | `#E9ECEF` | App background |
| `card` | `#FFFFFF` | Card surface |
| `line` | `#D5DCE6` | Card border, chip border |
| `divider` | `#EDF0F4` | Internal separators |
| `ink` | `#0D1526` | Primary text |
| `dim` | `#5A6B84` | Secondary text |
| `faint` | `#8FA0B8` | Meta text, eyebrows |
| `cobalt` | `#2347F5` | Accent, primary action, active nav |
| `cobaltWash` | `rgba(35,71,245,.10)` | Accent tint |
| `long` | `#0E9F6E` | Bullish / positive |
| `longSoft` | `#DFF5EA` | Bullish badge background |
| `short` | `#E05252` | Bearish / negative |
| `shortSoft` | `#FBE3E3` | Bearish badge background |
| `warn` | `#B7791F` | Caution text, incomplete-input notes |
| `warnSoft` | `#F6ECD4` | Caution badge background |
| `chipBg` | `#F0F3F7` | Neutral chip background |
| `chipInk` | `#40516B` | Neutral chip text |
| `entryBg` | `#F5F7FF` | Level cell background |
| `entryBorder` | `#CFD7FF` | Level cell border |

**Direction encoding is always paired with a word.** Colour alone never carries
meaning; every long/short state also renders a text label.

### 3.2 Typography

| Family | Use |
|---|---|
| **Sora** | All UI text. Weights 400 / 600 / 700. |
| **Space Mono** | Eyebrows, meta lines, numeric readouts, timestamps. |

| Role | Size | Weight | Notes |
|---|---|---|---|
| Hero price | 34–38 | 700 | Space Mono or Sora, tight tracking |
| Screen title | 19–20 | 700 | |
| Card title | 15–16 | 600 | |
| Section eyebrow | 9–10 | 400 | Space Mono, uppercase, `.10em` tracking |
| Body | 12–13 | 400 | |
| Label | 10–11 | 600 | |
| Meta / mono | 9–10 | 400 | Space Mono, muted |
| Disclaimer | 10.5 | 400 | `dim`, 1.35 line height |

### 3.3 Shape, elevation, spacing

- Card radius **14**, inner cell radius **10**, badge **5**, pill **999**.
- Card shadow: `0 10px 15px -5px rgba(13,21,38,.12)`, 1px `line` border.
- Horizontal page padding **14**, card padding **15–16**.
- Vertical rhythm in multiples of **4**; section gaps 10–14.
- Hairline dividers use `divider`, never `line`.

### 3.4 Core components

| Component | Definition |
|---|---|
| `HarborCard` | White surface, 1px `line` border, radius 14, elevation |
| `HarborEyebrow` | Space Mono 9.5px uppercase `faint`, `.10em` tracking |
| `HarborChip` | Pill, `chipBg` fill, `chipInk` text, optional leading glyph |
| `HarborDivider` | 1px `divider` rule |
| `DirectionPill` | Rounded label: `long` / `short`, soft fill + darker text + border |
| `StatusPill` | Verdict state: `SETUP`, `WATCH`, `NO TRADE`, `FILTERING` |
| `MetaLine` | Space Mono 10px `faint` supporting line |
| `ScoreCell` | Label + value + hint, tinted neutral surface |

---

## 4. Screen specifications

### 4.1 Radar — primary decision surface

**Purpose.** Answer one question: *is there a gold setup right now, and why?*
Everything else is secondary.

**Layout, top to bottom.**

1. **App bar** — `XV` wordmark left; session status chip right (e.g. `EUROPE`
   with a live dot). Tap opens a session detail sheet.
2. **Instrument line** — `XAUUSD · SPOT GOLD`, eyebrow style.
3. **Price hero** — last price, large mono. Supporting line "Latest stored
   snapshot for XAUUSD." with the update timestamp.
4. **Session band** — dark (`ink`) rounded band, two columns:
   - **DAY MOVE** — percentage move, or `—` when no session-open reference exists.
   - **RANGE** — observed low – high for the session.
5. **Timeframe selector** — segmented control: `15M` · `5M` · `1H`. `15M` default.
   Selecting `5M`/`1H` changes the analysis context, never the signal timeframe.
6. **Setup card** — see 4.1.1.
7. **Context pills** — small outlined chips summarising adjacent context, e.g.
   `Alternate SHORT —`, `Watch 4,145.12`, `5M —`. Each opens the relevant sheet.
8. **Analysis card** — see 4.1.2.
9. **Event caution line** — icon + text, e.g. `Caution: CPI m/m in 6d 01h`.
   Tapping opens the Events tab. Only rendered when an event qualifies.
10. **Macro backdrop strip** — dark band, one line, e.g. `Fed policy repricing`,
    with a chevron. Display only; never a vote. Opens Sources → macro detail.

#### 4.1.1 Setup card states

Three mutually exclusive states.

**A. Active setup**
```
[DIRECTION PILL]  15M Consensus Setup        updated just now
                                            STRONG · N of M
[ ENTRY ]
  4,155.98 – 4,160.98
  market zone
[ STOP ]            [ TP1 ]
  4,145.12          4,166.62
  −13.36            +8.14
[TP1] [TP2] [TP3]   ← target selector, active state outlined in cobalt
———————————————
No external sources yet                 R:R 1:1.0
[ COPY LEVELS ]      [ ↗ SHARE ]
```
- Strength meter: horizontal track, fill in `long` or `short`.
- **"N of M"** is agreement among *independent* sources. When no independent
  source agrees, the line reads an explicit absence — never `0%`.
- Target selector swaps which TP the Stop/TP cells display; entry and stop never change.

**B. No consensus**
```
NO VOTE
NO CONSENSUS
Sources have not reached agreement.

Waiting for stronger agreement.
```
Muted `chip` badge for `NO VOTE`. No levels, no copy action, no strength meter.

**C. Waiting / insufficient**
States that data is still accumulating. Names what is missing and roughly how
long. Never renders placeholder numbers.

#### 4.1.2 Analysis card

The methodology's own verdict. Shown separately from consensus because it answers
a different question: not *what sources agree on*, but *whether the gates permit
a setup at all*.

**Header:** `MULTI-TIMEFRAME ANALYSIS` eyebrow, `RESCAN` chip right.

**Verdict row:** status pill (`NO TRADE`, `SETUP`, `WATCH`) + grade (`Grade B`)
+ a filter badge (`FILTERING`) when vetoes are active.

**Score row:** three cells, equal flex —
- `TECHNICAL` — `5/12`, hint "setup quality, not probability"
- `FINAL` — `8.0`, hint "after macro/sentiment overlay"
- `ATR 5M` — `2.53`, hint "volatility unit for stops"

A score must never appear without its hint. `FINAL` requires the overlay to
actually have contributed.

**Sentiment layers block.** The four weighted slow layers, each with the
reading that produced its state.

```
SENTIMENT LAYERS                     MACRO COVERAGE 73%

POLICY 35%                                  [BEARISH]
Fed raised the target range to 3.75%–4%
2026-09-16 · raw −2 → −1.03 after 20d decay · no dissents
SEP projections not read (PDF only) — the path is unmeasured

POSITIONING 25%                             [BEARISH]
Managed money net +120318 contracts
37.8 pctile · of 156 weeks · 29.60% of open interest · 2026-09-29

MARKET-IMPLIED 20%                          [BEARISH]
10-year real yield 2.95%
+5bp over 5 sessions · 2026-10-05
usd and volatility of this layer are missing

GOLD-FUNDAMENTALS 20%                     [NOT MEASURED]
World Gold Council demand data — not ingested
———————————————
vs LONG    [CONFLICT]  macro opposes — would veto · positioning penalty
vs SHORT   [SUPPORTS]  macro credits · positioning credits
Agreement is not a probability and not a vote count. Layers filter
confidence only — sentiment never forbids a trade.
```

Rules this block must honour:
- Each row shows **the layer's own lean** as the badge, and **agreement with a
  trade** in the strip below. These are different facts and are never merged.
- Both `vs LONG` and `vs SHORT` are always shown, each computed independently, so
  neither depends on which side is live. The live side is indicated by a 2px
  left rule.
- Badge vocabulary: `BEARISH` / `BULLISH` / `NEUTRAL` / `NOT MEASURED` /
  `STALE`. `NOT MEASURED` uses a dashed border and `faint` ink; `NEUTRAL` is a
  real reading and must look different.
- A layer that is only partly measured states **which part is missing** in
  `warn`. A layer that is stale says so and is excluded from scoring.
- Coverage denominator counts only layers that can legally and practically be
  ingested. Mark unconnected layers explicitly rather than letting coverage
  imply a permanent shortfall.

**Levels grid** (only when a trade is valid): ENTRY full width, then STOP / TP1
side by side, with pip delta beneath each.

**Why block:** eyebrow + reason chips (`Low confluence`, `1H trend aligned`,
`Macro supports`). Chips are informational; the vetoes are called out.

**Data quality block:** bulleted notes, e.g.
- `venue spread 0.41 USD (23s old, oanda-practice)`
- `sentiment layers: policy, positioning, market_implied (macro coverage 73%, missing gold_fundamentals)`

**Spread row:** explicit. Either a measured value with venue, age and source, or
`UNAVAILABLE` with a note that spread-based vetoes are UNEVALUATED.

**Disclaimer footer:** always last, `dim`, 10.5px.

#### 4.1.3 Analysis card states

| State | Rendering |
|---|---|
| No result yet | "No analysis yet" + what is still accumulating |
| **Failed** | "Analysis failed" in `short`, the actual error in `shortSoft` panel, `RESCAN` action. Never shown as "waiting". |
| Result | Full card |

A failed scan and a scan that has not run are **different states** and must
never render the same message.

---

### 4.2 Signal — levels and chart

**Purpose.** Let the user inspect the active setup's levels on a chart.

**Layout.**
1. Timeframe tabs: `15M` · `5M` · `1H`, synced with Radar's selection.
2. Price chart with the setup's entry zone shaded `entryBg`, and stop / TP lines
   drawn in `short` / `long`.
3. Level summary mirroring the Radar setup card.
4. Target selector.
5. Actions: `COPY LEVELS`, `SHARE`.

**Rules.**
- If there is no valid setup, this tab shows the empty state, not an empty chart
  implying levels exist.
- No forecast line, no projected path, no probability overlay.

---

### 4.3 Sources — provenance and method

**Purpose.** Let the user verify where every number came from.

**Layout.** Rows grouped by role, never a flat list:

- **MARKET DATA** — price feed, venue spread.
- **EVENT RISK** — economic calendar.
- **SLOW CONTEXT** — the sentiment layers.

Each row: name · what it measures · weight · current reading and direction ·
as-of date · staleness badge · licence basis · typical horizon.

Layers that are excluded from scoring are labelled **"excluded"** with the reason
— never silently omitted.

**Detail sheet.** Per row: what it measures, the exact scoring rule, licence and
terms basis, last refresh, next refresh, and a link to the primary publication.

**Rules.**
- Grouping exists so the list cannot be misread as "N sources agree".
- State correlation where it exists: two layers driven by the same underlying
  variable are not two independent confirmations, and the UI says so.
- Licence basis is shown for every source. A source that fails licence review is
  listed as rejected, with the reason.

---

### 4.4 History — measured outcomes

**Purpose.** Show what the app published and what followed.

**Layout, top to bottom.**

1. **Stats bento** — hero stat card:
   - TP hit rate, large, with sample size
   - Window net, signed
   - A compact pips line chart
   - Two small cards: `INVALIDATED` and `EXPIRED` counts
2. **Past setups list** — newest first: direction pill, grade, outcome badge,
   timestamp, R:R.
3. **Row tap** → bottom sheet with the full published setup and what followed.

**Rules.**
- Every rate shows its sample size. A rate over a handful of samples is labelled
  as insufficient and must not be presented as a track record.
- No stat may imply a probability of future success.
- Stop distance is derived and displayed consistently; it is never stored as an
  independent figure.

---

### 4.5 Events — economic calendar

**Purpose.** Context and risk. Never a vote.

**Layout.**
1. Day-grouped list. Each row: time · title · impact · actual / forecast /
  previous once published.
2. Impact badge: `HIGH` / `MEDIUM` / `LOW`.
3. Row tap → bottom sheet with full detail.

**Rules.**
- A `HIGH` event inside its blackout window is annotated on Radar and **suppresses
  new signals**. It never creates or flips one.
- `MEDIUM` and `LOW` events render as context badges only.
- Fields that have not been published render as `—`, never as an estimate.

---

### 4.6 Settings

**Purpose.** Updates, permissions, provenance, about.

**Layout — grouped cards.**

**APP UPDATES**
- Current version and build number.
- Status row: idle / checking / available / downloading / paused / verifying /
  ready / failed.
- Action buttons, rendered only when valid for the current state:
  `CHECK` · `DOWNLOAD` · `PAUSE` · `RESUME` · `CANCEL` · `INSTALL`
- Progress with percentage and transferred / total.
- Checksum line once downloaded.
- The **ready** state reads *"downloaded — restart to install"*. It must never
  read "installed"; installation is not verifiable by the app.

**INSTALL PERMISSION**
- Present on Android 8+. Explains that install permission is granted per-source
  by the user, not by the app.
- States the current grant status truthfully.
- Offers `ALLOW` which opens the system screen.
- When installation fails for want of the grant, the message offers the action
  rather than only naming the setting.

**NOTIFICATIONS**
- Runtime permission state with a request action.

**DATA & METHOD**
- Links to the Sources detail, and a short statement of what the app does and
  does not use.

**ABOUT**
- Version, disclaimer.

**Rules.**
- Failure states name the actual cause and offer the next action. A button that
  cannot work must not be rendered.
- Controls are never disabled without an adjacent explanation.

---

## 5. Responsive behaviour

| Width | Behaviour |
|---|---|
| ≥ 360 dp | Baseline, single column |
| 390 dp | Score cells stay three-across if they fit without clipping; layer readings keep their own full-width line so long source names never truncate |
| < 330 dp | Score cells reflow to two per row; agreement descriptions wrap beneath their tag |
| Landscape | Content column caps at ~520 dp and centres |

- No horizontal scrolling anywhere.
- Long source names, long tickers and long event titles truncate with ellipsis
  only in single-line contexts; multi-line contexts wrap.
- Touch targets ≥ 44 dp.

---

## 6. Accessibility

- Every interactive element has a semantic label.
- Direction and status are never colour-only — always paired with text.
- Minimum contrast 4.5:1 for body text; `faint` is reserved for non-essential
  meta text only.
- Dynamic content announces through semantics; a state change from `NO CONSENSUS`
  to a valid setup is announced.
- Support OS font scaling without clipping; meta lines may wrap to two lines.
- Support screen readers on every list and card.

---

## 7. Content rules

The copy is part of the specification.

**State vocabulary**

| Meaning | Copy |
|---|---|
| No independent agreement | `NO CONSENSUS` |
| Gates block a setup | `NO TRADE` |
| Setup present but not actionable | `WATCH` |
| Setup actionable | `SETUP` |
| Data accumulating | states what is missing and roughly how long |
| Scan failed | `Analysis failed` + the actual error |
| Input not measurable | `NOT MEASURED` |
| Input measurable but stale | `STALE` + excluded from scoring |

**Never write**
- A probability, a percentage chance, or a win rate.
- "N of M" without N being independent sources.
- A score without its denominator or its "not a probability" hint.
- A claim about data that has not been measured.
- A reason for a state that has not been established — name what is missing.

**Always write**
- The as-of time and age of every reading.
- The venue, age and source of every spread.
- The licence basis of every source.
- Which parts of a partially-ingested layer are missing.

---

## 8. Build checklist

- [ ] 6-tab floating pill nav with expanding active slot
- [ ] Design tokens implemented exactly as §3
- [ ] Radar: 10 sections per §4.1
- [ ] Setup card: active / no-consensus / waiting states
- [ ] Analysis card: result / no-result / **failed** as distinct states
- [ ] Sentiment layers block with lean-vs-agreement separation
- [ ] `NOT MEASURED` visually distinct from `NEUTRAL`
- [ ] Signal tab with entry zone + stop/TP lines
- [ ] Sources grouped by role, with licence basis per row
- [ ] History with sample sizes on every rate
- [ ] Events with impact badges, never voting
- [ ] Settings incl. install-permission request flow
- [ ] Responsive 330 / 360 / 390 / landscape
- [ ] Accessibility pass: labels, contrast, no colour-only meaning
- [ ] Copy reviewed against §7