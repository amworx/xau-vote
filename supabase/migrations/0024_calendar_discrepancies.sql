-- 0024_calendar_discrepancies.sql
--
-- Discrepancy log for the Finance Calendar vs l3vlup cross-check (D-20261007-022,
-- directive step 8: official-source validation).
--
-- Each row is a QUESTION, never a correction. When the two calendars disagree
-- about a HIGH US release, the resolution is a manual check against the
-- official issuer page - never an automatic switch, because a third party's
-- error must not flap the blackout guard, and never silent dismissal.
--
-- `status` lifecycle: OPEN (needs a human) -> CONFIRMED_* (human checked the
-- issuer) or DISMISSED (human judged it noise, with notes saying why).
-- Service-only table: this is pipeline operations, not app content.

create table if not exists public.calendar_discrepancies (
  id              uuid primary key default gen_random_uuid(),
  checked_at      timestamptz not null default now(),
  kind            text not null,
  fc_external_id  text,
  fc_title        text,
  fc_starts_at    timestamptz,
  l3vlup_title    text,
  l3vlup_date     text,
  l3vlup_time     text,
  detail          text,
  status          text not null default 'OPEN'
    check (status in ('OPEN', 'CONFIRMED_FC', 'CONFIRMED_L3VLUP', 'DISMISSED')),
  notes           text
);

comment on table public.calendar_discrepancies is
  'Calendar cross-check findings (step 8). Questions for manual issuer check, '
  'never auto-corrections. Service-only.';

alter table public.calendar_discrepancies enable row level security;

revoke all on table public.calendar_discrepancies from anon, authenticated;
grant all on table public.calendar_discrepancies to service_role;