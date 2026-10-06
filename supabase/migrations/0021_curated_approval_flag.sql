-- 0021_curated_approval_flag.sql
--
-- A hand-entered level must never vote on its author's word alone.
--
-- FXScalpers ideas reach XV by owner curation (D-019: no compliant automated
-- pipe exists). Transcription is error-prone, and a mistyped stop is a
-- fabricated level wearing a publisher's name. So curated rows enter in two
-- steps: INSERT with curated_ok = false, then a SECOND pass - re-reading the
-- Telegram message, checking every field and the link - flips curated_ok to
-- true. build-consensus only reads curated_ok = true.
--
-- The two passes must be separate statements, ideally separate eyes. The flag
-- defaults false so a forgotten second pass fails closed (row never votes)
-- rather than open.
--
-- Existing rows (652 seed fixtures) get curated_ok = false explicitly rather
-- than relying on NULL semantics, so the exclusion is visible in the data, not
-- just in a query filter. This is also defense-in-depth for fixture isolation:
-- even if a seed row somehow lost its internal:// source marking, it still
-- cannot vote without curated_ok = true.

alter table public.trade_ideas
  add column if not exists curated_ok boolean not null default false;

update public.trade_ideas set curated_ok = false where curated_ok is null;

comment on column public.trade_ideas.curated_ok is
  'Independent-check gate for hand-curated external ideas. build-consensus '
  'reads only curated_ok = true. Insert false, verify against the publisher '
  'message in a second pass, then flip. Defaults false so omissions fail '
  'closed. Seed fixtures are false and can never vote through this flag even '
  'if their source marking were lost.';