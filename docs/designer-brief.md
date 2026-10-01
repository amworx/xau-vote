# XV (XAU-Vote) — Designer Brief

**Version:** 2026-09-29 · **Status:** ready for UI design pass
**Repo:** `xau-vote/` · Current baseline: `docs/mockups/mockup-11A-harbor.html` + `screen-2..6-*.html`

---

## 1. What the app is

**XV (XAU-Vote)** is a free, mobile-first day-trading assistant for **XAUUSD (Gold)**.
It collects fresh intraday trade ideas from multiple independent sources,
compares them, and turns the strongest agreement into **one clear 15-minute
setup**. It does not execute trades, hold accounts, or predict the market —
consensus scores measure *agreement between sources*, never win probability.

**Platform:** Flutter (Android-first, also ships as responsive web).
**Form factor:** phone portrait first; tablet/desktop must not break.

## 2. Who uses it and when

Retail Gold day-traders who check their phone between tasks. Sessions are
short (30–90 seconds): open → is there a setup? → what are the levels? →
copy → done. Everything must be glanceable; numbers must be unambiguous.

## 3. Product rules the design must respect

1. **15M is the only signal timeframe.** 5M confirms, 1H gives context and
   never votes. Never show Daily/H4/Weekly ideas inside 15M consensus.
2. **Never fabricate.** Weak agreement → an explicit `NO CONSENSUS` empty
   state; missing levels → `INSUFFICIENT DATA`. No placeholders that look
   like calls.
3. **Direction language:** LONG (green) / SHORT (red), tradable words
   ("Go long", "Go short"). Never "buy/sell" wording confusion, never
   probability framing ("82% chance").
4. **Events & news are guardrails, never signals.** They can suppress,
   delay, or annotate — never create or flip a setup.
5. **Every setup shows its receipts:** Entry/SL/TP levels, agreement counts
   (e.g. 3 of 4 sources), which sources agreed, original-source link-outs.

## 4. App structure — 6 tabs

Bottom tab bar (icons only + micro-label): **Radar · Signal · Sources ·
History · Events · Settings**.

### 4.1 Radar (home)
The glance screen. Sections top→bottom:
- **Header:** XV brand mark + "XV" wordmark, live-connection pill.
- **Price hero:** current XAUUSD price (large mono numeral), day-move card
  (inverted dark surface), spread line.
- **Timeframe switcher:** 15M / 5M / 1H segmented control (switching TF is
  view-only context; consensus stays 15M).
- **Verdict card:** the one setup — direction badge (LONG green / SHORT
  red), consensus score + strength meter, Entry / Stop / TP1–TP3 level grid,
  TP selector, agreement line ("3 of 4 sources · updated 40s ago"),
  Copy + Share actions, R:R line.
- **Scenario strip:** compact alternate-scenario preview buttons.
- **States:** `NO CONSENSUS` empty state (with vote counts), `INSUFFICIENT
  DATA` state, **event blackout banner** (inverted ink banner with red
  hairline shown when a HIGH-impact USD event is ±30/15 min away, with
  countdown + "View event" action).

### 4.2 Signal
The active-setup detail screen. Sections:
- **Lifecycle timeline:** NO SETUP → DEVELOPING → READY → CONFIRMED →
  ACTIVE → TP1/TP2/TP3 HIT (with INVALIDATED / EXPIRED branches),
  timestamped rows + countdowns.
- **Level cards:** Entry / Stop / TP1–TP3 with copy affordances.
- **Confirmation panel:** 5M confirmation status; **1H context badges**
  (supportive / neutral / caution — visually subordinate, never votes).
- **Position strip:** small position-size helper readout.
- **CTA row:** Copy + Share (same component as Radar).

### 4.3 Sources
Trust and transparency. Sections:
- **Summary header:** independent-source count + total ideas (large numeral).
- **Source cards (compact → tap to expand):** source name, direction chip,
  agree tick / disagree cross, weight, Entry/SL/TP detail grid, "View
  Original" link-out, 7-day hit-rate mini-table.
- **Per-source toggles:** enabling/disabling a source recomputes the
  consensus live (design the recompute transition — no jarring jumps).
- **Independence note:** a quiet explainer that copied ideas count once.

### 4.4 History
Past setups ledger. Sections:
- **Stat header:** win/loss counts, TP-hit distribution (Sora numerals).
- **Setup rows:** date/time, direction chip, Entry→outcome, pips gained/lost
  (mono numerals, green/red), state tag (TP1 HIT / INVALIDATED / EXPIRED).
- Rows are 16px-radius cards; density matters (dozens of rows, must scan).

### 4.5 Events (6th tab)
Economic calendar + news guardrails. Sections:
- **Guard-line banner:** "TRADING PAUSED — NFP in 12:40" style live line.
- **Tabs:** Upcoming / Results / News (min-height 48px touch targets).
- **Event cards:** time (mono countdown), USD badge, impact pill (HIGH red /
  MEDIUM amber / LOW gray), title, mute bell per event, currency filter chips
  (USD default), impact filter.
- **Results rows:** actual vs forecast with surprise flags.
- **News cards:** headline, source, age, link-out (headlines only — no full
  text, licensing constraint).
- **Macro backdrop strip:** one-line regime note (risk-on/off, USD tone).

### 4.6 Settings
Configuration. Groups:
- **Alerts:** push on/off, signal types, quiet hours.
- **Sources:** mirror of per-source toggles + hit-stats link.
- **Display:** pip-size convention A/B selector (0.10 vs 0.01 — changes all
  pip readouts), theme note.
- **Data:** refresh interval, provider status.
- **About:** version micro-copy, "UIcons by Flaticon" attribution line,
  license/disclaimer ("Not financial advice").

## 5. Design system (current — critique freely)

| Token | Value | Usage |
|---|---|---|
| `--bg` | `#E9ECEF` mist | page background |
| `--card` | `#FFFFFF` | cards, 1px `#D5DCE6` hairline, radius 12–18px, zero elevation |
| `--ink` | `#0D1526` | text + inverted surfaces |
| `--dim` / `--faint` | `#5A6B84` / `#8FA0B8` | secondary / tertiary text |
| `--accent` | `#2347F5` cobalt | active states, CTAs, links |
| `--long` / `--short` | `#0E9F6E` / `#E05252` | direction (soft tints `#DFF5EA` / `#FBE3E3`) |
| `--warn` | `#B7791F` | MEDIUM impact, caution |
| Display font | **Sora** 400–800 | headings, labels, body |
| Number font | **Space Mono** 400/700, tabular | ALL prices/levels/pips/countdowns |
| Icons | **UIcons Regular Rounded** | 20px nav glyphs, 14–24px inline |
| Eyebrows | 9–11px, uppercase, tracked 1–2px | section labels |

Type scale (root 16px): micro 9–11 · body 12–16 · titles 16–20 · hero 23–34.
Touch targets ≥ 44px. Rounded, calm, light-first; dark ink only for inverted
moments (day-move card, blackout banner).

## 6. What we need from you

1. **Critique of the current Harbor baseline** (the 6 HTML mockups) — what
   breaks at a glance, what won't scale, what's inconsistent.
2. **Revised component spec** per screen: exact type ramp, spacing scale,
   radii, states (loading / empty / error / blackout / no-consensus), and
   the toggle-recompute + mute + TP-selector micro-interactions.
3. **A comparison checklist** we can verify build-against (screen × element ×
   token), so engineering can prove pixel fidelity instead of eyeballing it.
4. Flag anything in §3 or §5 that fights good design — product rules are
   firm, but tokens are negotiable if you justify the change.

## 7. Reference files (in repo)

- `docs/mockups/mockup-11A-harbor.html` — Radar baseline (locked direction)
- `docs/mockups/screen-2-signal.html` … `screen-6-events.html` — tab baselines
- `docs/mockups/preview-*.png` — quick-look screenshots of each
- `docs/mvp-specification.md` — authoritative product spec (§24 UI scope)
- `src/app/` — current Flutter implementation (what your spec will correct)
