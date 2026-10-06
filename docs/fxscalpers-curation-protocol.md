# FXScalpers manual curation protocol

**Status:** the ONLY compliant ingestion pipe (D-20261006-019).
No automation touches the Telegram channel. A human reads it as an ordinary
user and enters structured fields here. No prose, no images, no commentary is
copied - fields only.

## Per setup, two passes - never one

**Pass 1 - insert with `curated_ok = false`:**

```sql
-- 1. Get the source id (changes never; kept in the statement for copy-paste).
--    '39bb55fc-e5eb-4ccb-9636-3ed62c6fca85'
insert into public.trade_ideas
  (source_id, symbol, timeframe, direction,
   entry_low, entry_high, stop_loss, take_profits,
   reasoning, author, author_ref,
   published_at, collected_at, fingerprint,
   model_owner, upstream_dataset_id, methodology_id,
   event_window, curated_ok)
values (
  '39bb55fc-e5eb-4ccb-9636-3ed62c6fca85',
  'XAUUSD', 'M15', '<long|short>',          -- their buy -> long, sell -> short
  <entry_low>, <entry_high>, <stop>,        -- single price: low = high = price
  '[<tp1>, <tp2>]'::jsonb,                  -- their TP1, TP2 (TP3 if given)
  '<one-line setup thesis in your own words, never their prose>',
  'FXScalpers',
  'https://t.me/<channel>/<message_id>',    -- message link, copied from Telegram
  '<message timestamp in UTC>',             -- the MESSAGE time, not entry time
  now(),
  'fxscalpers-tg:<message_id>',             -- deterministic, one per message
  'third_party',
  'fxscalpers-telegram',
  'fxscalpers-snd-ms-v1',
  '<ASIAN|LONDON|NEW_YORK>',                -- session the call belongs to
  false
);
```

Rules for pass 1:
- XAUUSD M15 setups with entry + stop + target ONLY. Anything else
  (other pairs, no stop, vague call) is skipped, not approximated.
- `published_at` is the Telegram message timestamp, transcribed exactly.
  build-consensus ignores ideas older than 60 minutes on its own, so backfills
  are harmless - but do not backdate to force them into the window.
- One message = one row. Follow-ups (TP hit, SL moved) do NOT edit the row;
  outcomes are scored from bars, never from follow-up posts.

**Pass 2 - independent check, then flip:**

```sql
-- Re-read the Telegram message. Check EVERY field and that the link opens.
-- Only then:
update public.trade_ideas set curated_ok = true where id = '<row id>';
```

The two passes must be separate in time - walk away and come back, or a second
person. A same-minute flip is a single pass with extra steps.

## What each switch does

| Switch | State now | Effect |
|---|---|---|
| `sources.enabled` (FXScalpers) | `false` | Row counts nothing even with approved ideas |
| `curated_ok` per idea | — | Unapproved rows are invisible to consensus |
| Archived written permission | MISSING | Nothing is enabled until filed (D-20261006-017) |

Voting needs all three: archived permission, enabled source, approved rows.
Any one missing fails closed. Enabling the source is one statement:

```sql
update public.sources set enabled = true where name = 'FXScalpers';
```

## What to expect

One approved voter at threshold 2 yields `SINGLE_SOURCE` audit rows and
NO_CONSENSUS output - verified live 2026-10-06. That is the design working,
not a malfunction. A setup fires only with a second independent voter or an
explicit directive amendment.
