# XAU Radar — Project Instructions

**XAU Radar** is a free, mobile-first day-trading assistant focused exclusively on
**XAUUSD (Gold)**. It collects fresh intraday Gold trade ideas from multiple
independent sources, compares them, and turns the strongest agreement into one
clear 15-minute trading setup.

It does **not** execute trades and does **not** predict the market.

The authoritative product definition is `docs/mvp-specification.md` — read it
before any feature work. When code and spec disagree, the spec wins unless the
user explicitly decides otherwise.

Inherits the global doctrine in `~/.config/opencode/AGENTS.md` and the container
map in `C:\Users\HP\Documents\code_repo\AGENTS.md`.

---

## Stack

| Layer | Choice | Notes |
|---|---|---|
| Mobile | Flutter | Single codebase, Android-first |
| Backend | Supabase Free | Postgres, Edge Functions, scheduled jobs |
| Market data | Gold API (initial) | Behind a `MarketDataProvider` interface — never hard-wire |
| Idea sources | Source adapters | Behind an `IdeaSource` interface; each must pass licensing/automation review before being enabled |
| Notifications | Firebase Cloud Messaging | |
| Charts | TradingView Lightweight Charts or permissively licensed alternative | Subject to final license verification |
| Repo | Git (local, no remote yet) | |

## Structure

```
xau-radar/
├── AGENTS.md          ← this file
├── docs/
│   └── mvp-specification.md   ← authoritative spec
├── plans/             ← dated plan files (YYYY-MM-DD_name.md)
├── tasks/             ← task breakdowns
├── src/               ← code (flutter app, supabase functions) — created on explicit request
└── memory/            ← events / lessons / patterns / decisions / playbooks (append-only)
```

## Core product rules (from spec — do not violate)

1. **Timeframes:** 15M is the only signal timeframe. 5M is confirmation only.
   1H is context only and **never votes**. Daily/H4/Weekly ideas must never
   enter the 15M consensus.
2. **Never fabricate.** If agreement is insufficient or data is missing, show
   `NO CONSENSUS` / `INSUFFICIENT DATA`. Never manufacture a signal.
3. **Source independence.** Copied/duplicate ideas count as ONE independent
   vote. Deduplicate by direction, levels, wording, author, timing, source
   relationships (fingerprint + independence factor).
4. **Consensus score is agreement, not probability.** Never display it as
   "X% chance of profit".
5. **AI is not the trading engine.** AI may summarize/extract/detect copies,
   but must never invent Entry, SL, TP, or direction. Unextractable values →
   mark `INSUFFICIENT DATA`.
6. **Licensing gate.** Every production source adapter must pass a
   licensing/automation review before being enabled. An accessible webpage is
   not permission to scrape or redistribute.
7. **Freshness is a first-class factor.** Ideas carry `publishedAt`/`expiresAt`;
   stale ideas are rejected or demoted to context-only.
8. **Provider abstraction.** Market data and idea sources live behind
   interfaces with mock providers for dev/test.

## Data model (minimum, from spec §21)

- `sources`, `trade_ideas`, `consensus_signals`, `signal_sources`,
  `market_snapshots` — see spec for fields.

## Signal lifecycle (from spec §14)

```
NO SETUP → DEVELOPING → READY → CONFIRMED → ACTIVE → TP1/TP2/TP3 HIT
DEVELOPING → INVALIDATED
READY      → EXPIRED
```

Every state change is timestamped.

## MVP UI scope (spec §24) — 5 screens, nothing more

Radar · Signal · Sources · History · Settings

Explicitly out of scope: social features, chat, broker connection, copy
trading, account management, indicator dashboards.

## Safety & workflow

- No `flutter create`, package installs, or Supabase provisioning without
  explicit user request.
- No scraping code against a source until its licensing/automation review is
  recorded in `memory/decisions.md`.
- Record every meaningful action in `memory/events.md`; append-only.
- Do not modify unrelated projects in the container (note: `telegram-trade-feed/`
  is a separate Gold-levels project — do not conflate the two).
