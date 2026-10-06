-- 0009_outcome_recorder_notrade_side.sql
--
-- Three corrections to the recorder, all found by running 0008 against a real
-- NO_TRADE decision instead of only against happy-path trades.
--
-- 1. A NO_TRADE row needs a side value of NO_TRADE. 0008's CHECK constraint only
--    allowed directional sides, because the first version of the function
--    assumed every recorded row was a trade. Abstentions are the whole point of
--    the recorder, so the constraint was wrong, not the row.
--
-- 2. NO_TRADE rows must never be marked is_repeat. Clustering collapses
--    overlapping setups in one gold move into a single observation, and that
--    rule only makes sense when there is a direction to overlap. Two
--    abstentions three hours apart are two separate decisions to abstain from,
--    and collapsing them would discard exactly the rows the record depends on.
--
-- 3. A counterfactual must name the abstention it was forced out of. Without
--    that link a synthetic trade could enter the record with no real abstention
--    beside it, which is how a benchmark gets quietly manufactured. An earlier
--    draft of this file tried to enforce this with a CHECK on verdict, which
--    was simply wrong: a counterfactual's verdict is the forced direction, not
--    NO_TRADE.
--
-- Never edit an applied migration. This file is new; do not amend it after deploy.

alter table public.scan_decisions
  drop constraint if exists scan_decisions_side_check;

alter table public.scan_decisions
  add constraint scan_decisions_side_check
    check (side in ('LONG','SHORT','FORCED_LONG','FORCED_SHORT','NO_TRADE'));

alter table public.scan_decisions
  add column if not exists parent_decision_key text;

alter table public.scan_decisions
  drop constraint if exists scan_decisions_counterfactual_linked;

alter table public.scan_decisions
  add constraint scan_decisions_counterfactual_linked
    check (not is_counterfactual or parent_decision_key is not null);

create index if not exists scan_decisions_parent_idx
  on public.scan_decisions (parent_decision_key)
  where parent_decision_key is not null;

create or replace function public.scan_decisions_prepare()
returns trigger
language plpgsql
as $$
declare
  open_episode public.scan_decisions;
begin
  new.resolve_at := new.decided_at + interval '3 hours';

  if new.status = 'VOID' then
    new.cluster_id := new.id;
    return new;
  end if;

  -- Only directional rows cluster. A NO_TRADE row is always its own episode.
  if new.side = 'NO_TRADE' then
    new.cluster_id := new.id;
    new.is_repeat  := false;
    return new;
  end if;

  select d.* into open_episode
  from public.scan_decisions d
  where d.side = new.side
    and d.status = 'PENDING'
    and d.decided_at > new.decided_at - interval '3 hours'
    and d.decided_at <= new.decided_at
    and d.is_repeat = false
  order by d.decided_at asc
  limit 1;

  if found then
    new.cluster_id  := open_episode.id;
    new.is_repeat   := true;
  else
    new.cluster_id  := new.id;
    new.is_repeat   := false;
  end if;

  return new;
end;
$$;