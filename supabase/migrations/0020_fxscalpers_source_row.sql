-- 0020_fxscalpers_source_row.sql
--
-- Registers FXScalpers as a potential Voter #1 WITHOUT enabling it.
--
-- State of play (D-20261006-017, D-20261006-019):
--   * Content fit: PASS. Free Telegram channel, XAUUSD-first, London/New York,
--     entry/stop/target before price arrives, losers kept on a public
--     scorecard, methodology genuinely independent of Gold Hunts.
--   * Licence: publisher permission RECEIVED IN SUBSTANCE (fast friendly reply)
--     but the verbatim wording is NOT yet archived, so scope (automated
--     collection + redistribution + commercial use) is unconfirmed. D-017's
--     block stands until the reply text is filed.
--   * Collection: publisher offers no API/bot/feed. Bot API needs channel-admin
--     cooperation (declined: "nothing else"). MTProto scraping violates
--     Telegram's platform terms (D-019) and is rejected. The only compliant
--     pipe is owner-curated manual entry - see
--     docs/fxscalpers-curation-protocol.md.
--
-- Therefore this row is inserted with enabled = false. The consensus engine
-- needs no code change: build-consensus already excludes only `internal://`
-- sources from the independence count, so the day this row is enabled (one
-- UPDATE, after the reply is archived) its ideas start counting as an
-- external publisher voice with zero deploys. Until then it counts nothing.
--
-- Threshold note: MIN_INDEPENDENT_SOURCES = 2 is unchanged. One voter at a
-- threshold of two still yields NO_CONSENSUS - honestly. Nothing fires until
-- voter #2 exists or the directive is explicitly amended. Wiring a voter is
-- not the same as lowering the bar.

insert into public.sources (name, url, license_url, automation_allowed, commercial_use_allowed, enabled)
select 'FXScalpers', 'https://fxscalpers.net', 'https://fxscalpers.net', false, false, false
where not exists (select 1 from public.sources where name = 'FXScalpers');

comment on table public.sources is
  'Publisher registry. Only rows with enabled = true AND a non-internal URL can '
  'vote in build-consensus. FXScalpers is registered disabled pending archived '
  'written permission (D-20261006-017). manual-seed stays internal:// so fixtures '
  'can never count (D-20261005-001).';