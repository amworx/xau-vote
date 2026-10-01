# XV (XAU-Vote) — Backend Runbook (Gate G2)

> Code is written and golden-tested. This runbook is the only remaining path
> to a live backend. Nothing here runs without explicit user confirmation
> (project Gate G2), and no secrets ever enter git (see root `.gitignore`).

## 0. What exists already

| Piece | Location | Verified |
|---|---|---|
| Schema (5 tables) | `supabase/migrations/0001_initial.sql` | SQL reviewed, not applied |
| RLS policies | `supabase/migrations/0002_rls_policies.sql` | SQL reviewed, not applied |
| Engine TS port | `supabase/functions/_shared/engine.ts` | 7/7 golden tests via `node engine_test.ts` |
| collect-ideas fn | `supabase/functions/collect-ideas/index.ts` | code-reviewed, needs live DB |
| build-consensus fn | `supabase/functions/build-consensus/index.ts` | code-reviewed, needs live DB |
| tick fn | `supabase/functions/tick/index.ts` | code-reviewed, needs live DB |

## 1. Provision Supabase (~5 min, user does this)

1. Create a free project at https://supabase.com/dashboard (region closest to you).
2. Open Project Settings → API and copy:
   - Project URL → `SUPABASE_URL`
   - `anon` public key → `SUPABASE_PUBLISHABLE_KEY` (Flutter `--dart-define`)
   - `service_role` secret key → server-side only, Edge Function secret.
3. Send those three values to the orchestrator (chat, never committed).

### Live project (do not commit these)

| Item | Value |
|---|---|
| Project ref | `mfrzwmqgwgcyaxehdbqh` |
| Region | **`ap-northeast-1`** (Tokyo) — discovered 2026-09-29 by probing pooler hosts |
| Pooler host | `aws-0-ap-northeast-1.pooler.supabase.com:5432` |
| Pooler user | `postgres.<project-ref>` (NOT the password — that is the common mistake) |

Because the CLI is not authenticated against this account, migrations are
applied over a **direct pooler connection** instead of `supabase link`:

```powershell
supabase db push --db-url "postgresql://postgres.<ref>:<password>@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres" --include-all
```

Status 2026-09-29: `0001_initial.sql`, `0002_rls_policies.sql` and
`0003_events_news.sql` are **applied and verified** (8 tables reachable over
PostgREST; anon `insert` correctly rejected by RLS).

Edge Function deploys, secrets and schedules still require Management API
auth — run `supabase login` once (browser flow, stores a token locally in
`~/.supabase/access-token`) or enable the Supabase MCP.

## 2. Apply migrations (orchestrator runs)

```powershell
supabase link --project-ref <ref-from-dashboard-URL>
supabase db push
```

This applies `0001_initial.sql` + `0002_rls_policies.sql`.

## 3. Secrets + deploy (orchestrator runs)

```powershell
supabase secrets set SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=...
# Gate G3 (optional): supabase secrets set GOLD_API_KEY=...
# Notifications (optional): supabase secrets set FCM_KEY=...
supabase functions deploy collect-ideas
supabase functions deploy build-consensus
supabase functions deploy tick
```

## 4. Schedules (user confirms cron expressions)

Via Dashboard → Edge Functions → Schedules, or SQL `cron.schedule`:

- `collect-ideas`: every 15 min (`*/15 * * * *`)
- `build-consensus`: every 5 min (`*/5 * * * *`)
- `tick`: every 1 min (`* * * * *`) — relax to `*/2` if free-tier egress bites.

Each function is also invokable manually for the acceptance run.

## 5. Verify live (acceptance evidence, TASK-06)

1. Invoke `collect-ideas` → expect `{"ok":true,"stored":["desk-a",...]}`.
2. Invoke `build-consensus` → expect LONG consensus, strength ≈ 82.
3. Invoke `tick` twice with a rising mock price → watch
   `developing → ready → confirmed` in `consensus_signals`.
4. SQL spot-checks (tables + RLS: anon `select` works, anon `insert` fails).

## 6. Firebase (FCM) — only when notifications are wanted

1. Create a Firebase project, add an Android app (`com.xauradar.xau_radar`).
2. Project Settings → Cloud Messaging → Server key → `FCM_KEY` secret.
3. App subscribes to the `xau-signals` topic on launch (stub exists in
   `src/app/lib/services/backend_service.dart`).

## 7. What stays OFF until reviewed

- Gold API provider (Gate G3 — terms re-verification + recorded decision).
- Real idea-source adapters (Gate G4, per source).
- FMP calendar provider (Gate G5).
