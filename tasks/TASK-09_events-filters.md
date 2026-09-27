# TASK-09 — Events filters (user control over signal impact)

- **status:** pending (queued 2026-09-27, user request)
- **screen:** `docs/mockups/screen-6-events.html`
- **spec:** `docs/economic-calendar-news.md` §5 (extends it)

## Requirements (user)

User has **full control over which events can impact the signal/prediction**:
filters for the Events screen that directly drive the Event Guard.

## Mockup work

- Filter bar on Events screen: currency multi-select (USD default on, others
  off), impact select (HIGH only / HIGH+MED / ALL),Toggle per event (bell on/off
  overrides), "blackout applies to" indicator per event row.
- Toggling a filter live-updates: visible event list, next-blackout countdown,
  and a guard summary line ("Guard active for: USD HIGH · 3 events this week").
- Persisted in Settings mockup (mirror the selections there).

## Backend notes (for later)

- `user_event_prefs` (currencies[], min_impact, muted_event_ids[], blackout
  windows override); guard reads prefs + event data.
- Acceptance: mute NFP → no blackout, no notifications, logged as user-muted.

## Open question (pip convention, still unanswered)

- User uses FXPro + Vantage (2-decimal gold quotes). Asked: is 4278.30→4278.40
  "1 pip" (keep 0.10) or "10 pips" (switch to 0.01)? → D-20260927-003 pending.
