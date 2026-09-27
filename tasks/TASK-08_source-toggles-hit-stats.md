# TASK-08 — Source toggles + target-hit stats

- **status:** pending (queued 2026-09-27, user request)
- **screen:** `docs/mockups/screen-3-sources.html`

## Requirements (user)

1. Each source gets a **toggle switch** — user enables/disables it; disabled
   sources are excluded from the consensus (recompute agreement live in mockup).
2. Each source shows **target-hit state/percentage** — per-source track record,
   e.g. Desk A: TP1 78% · TP2 54% · TP3 31% (last N signals), plus current
   contribution state (in-cluster / dissenting / excluded).

## Mockup work

- Add toggle to each source card header (Blueprint style, ≥48px hit area).
- Add a hit-rate block per card: TP1/TP2/TP3 hit % bars + signal count.
- Toggling updates the summary line (N/M agree, independence, strength) live.
- Disabling all-but-one → NO CONSENSUS state must render correctly.

## Backend notes (for later)

- `sources` table gains `enabled` (already in spec §21) + user override table
  (`user_source_prefs`); consensus reads enabled-only set.
- Hit stats derived from `signal_sources` join history (no new table expected).
