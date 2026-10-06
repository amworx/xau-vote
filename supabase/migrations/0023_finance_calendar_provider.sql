-- 0023_finance_calendar_provider.sql
--
-- Admits 'finance-calendar' as an economic_events provider (D-20261006-020).
--
-- The provider CHECK previously allowed only fmp/manual/forexfactory, from the
-- era when FMP was the candidate and fixtures were the fallback. Finance
-- Calendar is now the approved convenience layer: free for any use with
-- attribution, no key, no rate limits, CORS open (provider docs read
-- 2026-10-06). No existing rows are touched; this only opens the gate for new
-- ones. Official-source precedence still applies on conflict (directive §1):
-- the stored `url` points at the provider page, which itself links the
-- official issuer release page for verification.

alter table public.economic_events
  drop constraint economic_events_provider_check;

alter table public.economic_events
  add constraint economic_events_provider_check
  check (provider = any (array['fmp', 'manual', 'forexfactory', 'finance-calendar']));