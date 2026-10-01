# XV (XAU-Vote)

Free, mobile-first day-trading assistant for **XAUUSD (Gold)** — collects fresh
intraday trade ideas from multiple independent sources, compares them, and
turns the strongest agreement into one clear 15-minute setup.

> It does **not** execute trades and does **not** predict the market.
> Consensus scores measure **agreement between sources**, never win probability.

## Repo map

```
xau-vote/
├── AGENTS.md                  Project rules (read before contributing)
├── docs/
│   ├── mvp-specification.md   Authoritative product spec
│   ├── economic-calendar-news.md   Phase 7 feature addendum
│   ├── backend-runbook.md     Live-backend provisioning (Gate G2)
│   ├── acceptance-run-*.md    Dated acceptance evidence
│   └── mockups/               Interactive HTML design mockups + previews
├── plans/  tasks/             Build plan + per-phase task files
├── src/
│   ├── xau_core/      Pure-Dart domain models + consensus engine (tested)
│   ├── xau_lifecycle/ Pure-Dart lifecycle, freshness, 5M confirm, 1H context (tested)
│   ├── xau_data/      Provider interfaces, mocks, offline pipeline (tested)
│   └── app/           Flutter app, Harbor design, MOCK_MODE default (tested)
├── supabase/
│   ├── migrations/    0001 schema · 0002 RLS · 0003 events/news (paper until G2)
│   ├── functions/     collect-ideas · build-consensus · tick (+ events/news fns)
│   └── config.toml
└── memory/            events / lessons / patterns / decisions / playbooks
```

## Quickstart (no accounts, no keys, fully offline)

Prerequisites: Flutter SDK 3.44+ (includes Dart 3.12+), Node 22.6+, Supabase CLI
only if you touch the backend.

```powershell
# 1. Engine tests (127 total: 51 core + 36 lifecycle + 18 data + 7 TS golden + 15 app)
dart test                                  # in src/xau_core, src/xau_lifecycle, src/xau_data
node engine_test.ts                        # in supabase/functions/_shared
flutter test                               # in src/app (15 widget tests)

# 2. Run the app in mock mode (no backend, no Firebase)
flutter run                                # src/app; MOCK_MODE=true in lib/config.dart

# 3. Lint everything
dart analyze                               # each src/xau_* package
flutter analyze                            # src/app
```

Current test totals: **51** (xau_core) + **36** (xau_lifecycle) + **18**
(xau_data) + **7** (TS golden port) + **15** (Flutter) = **127 green**.

## Going live (requires explicit gates)

1. **Supabase project** (Gate G2) — follow `docs/backend-runbook.md`.
   Code + migrations + functions are written and golden-tested; only project
   creation, `supabase db push`, secrets, deploy, and schedules remain.
2. **Gold API key** (Gate G3) — terms re-verification first.
3. **Real idea sources** (Gate G4) — one licensing review each.
4. **FMP calendar / news providers** (Gate G5) — licensing reviews first.
5. **Firebase project** — only for push notifications (FCM topic `xau-signals`).

Until then the app runs end-to-end on mocks, which is also how CI works.

## Core product rules (see AGENTS.md)

- 15M signals only. 5M confirms. 1H provides context and **never votes**.
- Never fabricate: weak agreement → `NO CONSENSUS`, missing levels → `INSUFFICIENT DATA`.
- Copied ideas count once (independence weighting + dedupe).
- Events/news are context and guardrails, never direction votes.
- Every external source needs a recorded licensing review before production use.

## Fonts & icons (bundled offline)

- Sora + Space Mono (SIL Open Font License 1.1) in `src/app/assets/fonts/`
- UIcons Regular Rounded 2.6.0 by Flaticon — free use **with attribution**
  ("UIcons by Flaticon", shown in Settings → About)

## Contributing

1. Read `AGENTS.md`, then the task file for your phase in `tasks/`.
2. Pure-Dart logic first with unit tests; UI reads the same fixtures.
3. `dart analyze` / `flutter analyze` clean, tests green, one commit per unit.
4. Record decisions in `memory/decisions.md`, events in `memory/events.md`.
5. Never commit secrets (root `.gitignore` blocks `.env`, keystores, credentials).

## License

TBD — no license chosen yet. Do not redistribute until one is added.
