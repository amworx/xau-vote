/**
 * build-consensus — scheduled Edge Function (TASK-04 T4.3).
 *
 * Reads fresh, valid trade_ideas (XAUUSD/m15, published <60 min ago),
 * weights direction by independence (duplicate fingerprints collapse to one
 * vote — spec §5), clusters entry/SL/TP (spec §8/§9), scores agreement
 * (spec §6/§7 via the shared TS engine port), checks the event-guard
 * blackout (spec addendum docs/economic-calendar-news.md §2), and writes
 * consensus_signals + signal_sources — or a NO CONSENSUS record.
 *
 * It NEVER fabricates: divided rooms, single sources, stale-only input,
 * and blackout windows all produce explicit non-signal rows.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  clusterRanges,
  clusterValues,
  clusterTakeProfits,
  strengthBand,
  isBlackout,
  toDbStatus,
  CONSENSUS_THRESHOLD,
  MIN_DOMINANT_SHARE,
  MIN_INDEPENDENT_SOURCES,
  type Direction,
  type SignalStatus,
} from '../_shared/engine.ts';

interface Idea {
  id: string;
  source_id: string;
  direction: Direction;
  entry_low: number;
  entry_high: number;
  stop_loss: number;
  take_profits: number[];
  reasoning: string | null;
  author: string | null;
  published_at: string;
}

const dirWeight = { long: 30, entry: 15, stopLoss: 15, takeProfit: 10, reasoning: 10, freshness: 10, independence: 10 };

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();

  // Guard state: any HIGH event inside its blackout window suppresses emission.
  // (TASK-07: also fetch nearby MEDIUM events as display-only context badges.
  // Neither path votes — rule 9. Every suppression is logged with event id.)
  const { data: events } = await db.from('economic_events')
    .select('id,title,starts_at,impact')
    .eq('impact', 'HIGH')
    .gte('starts_at', new Date(now.getTime() - 60 * 60000).toISOString())
    .lte('starts_at', new Date(now.getTime() + 60 * 60000).toISOString());
  const blocker = (events ?? []).find((e: { starts_at: string; impact: string }) =>
    isBlackout(now.getTime(), new Date(e.starts_at).getTime(), e.impact));

  // MEDIUM-event context: nearest MEDIUM USD event within ±60 min, badge only.
  const { data: mediumEvents } = await db.from('economic_events')
    .select('id,title,starts_at,impact')
    .eq('impact', 'MEDIUM')
    .gte('starts_at', new Date(now.getTime() - 60 * 60000).toISOString())
    .lte('starts_at', new Date(now.getTime() + 60 * 60000).toISOString())
    .order('starts_at', { ascending: true })
    .limit(1);
  const mediumCtx = (mediumEvents ?? [])[0] as
    | { id: string; title: string; starts_at: string }
    | undefined;
  const eventContext = mediumCtx
    ? {
        eventId: mediumCtx.id,
        title: mediumCtx.title,
        minutesTo: Math.round((new Date(mediumCtx.starts_at).getTime() - now.getTime()) / 60000),
      }
    : null;

  // curated_ok = true: the independent-check gate (migration 0021). Curated
  // rows are hand-entered and transcription is error-prone, so nothing votes on
  // the author's first pass alone - a second pass against the publisher message
  // flips the flag. Defaults false, so omissions fail closed. Seed fixtures are
  // false explicitly and can never vote through this flag even if their
  // internal:// source marking were ever lost.
  const { data: ideas, error } = await db.from('trade_ideas')
    .select('*')
    .eq('symbol', 'XAUUSD')
    .eq('timeframe', 'M15')
    .eq('curated_ok', true)
    .gte('published_at', new Date(now.getTime() - 60 * 60000).toISOString())
    .order('published_at', { ascending: false });
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
  const rows = (ideas ?? []) as Idea[];

  // Every run leaves exactly one audit row. The NO_CONSENSUS rows carry no
  // levels (direction neutral, strength 0) - inventing levels for a non-signal
  // would be fabrication, and the level columns are nullable precisely so this
  // insert is honest.
  //
  // The insert error is CHECKED, not ignored. On 2026-10-06 the level columns
  // were NOT NULL and every audit write failed for ten hours while the function
  // kept returning HTTP 200 - the outage was invisible until postgres_logs was
  // read. A run that cannot leave its audit trail has not completed, so it
  // fails loudly.
  const fail = async (reason: string, counts: Record<string, number>) => {
    const { error: auditErr } = await db.from('consensus_signals').insert({
      symbol: 'XAUUSD', timeframe: 'M15', direction: 'neutral', strength: 0,
      status: toDbStatus('expired'), created_at: now.toISOString(), updated_at: now.toISOString(),
      expires_at: now.toISOString(),
    });
    if (auditErr) {
      console.error(`build-consensus: audit write failed (${reason}): ${auditErr.message}`);
      return Response.json({ ok: false, consensus: 'NO_CONSENSUS', reason, counts, eventContext, auditWritten: false, error: auditErr.message }, { status: 500 });
    }
    return Response.json({ ok: true, consensus: 'NO_CONSENSUS', reason, counts, eventContext, auditWritten: true });
  };

  if (blocker) {
    // Audit log: suppressed signal attempt → blocking event id (addendum §2).
    const b = blocker as { id: string; title: string; starts_at: string };
    console.log(`build-consensus: BLACKOUT suppressed by event ${b.id} (${b.title} @ ${b.starts_at})`);
    const { error: blackoutErr } = await db.from('consensus_signals').insert({
      symbol: 'XAUUSD', timeframe: 'M15', direction: 'neutral', strength: 0,
      status: toDbStatus('expired'), created_at: now.toISOString(), updated_at: now.toISOString(),
      expires_at: now.toISOString(),
    });
    if (blackoutErr) {
      console.error(`build-consensus: blackout audit write failed: ${blackoutErr.message}`);
      return Response.json({ ok: false, consensus: 'NO_CONSENSUS', reason: 'BLACKOUT', auditWritten: false, error: blackoutErr.message }, { status: 500 });
    }
    return Response.json({
      ok: true, consensus: 'NO_CONSENSUS', reason: 'BLACKOUT',
      counts: { long: 0, short: 0, neutral: 0 },
      suppressedBy: b.id, eventContext,
    });
  }

  // Independence: identical fingerprints collapse (earliest keeps full weight).
  const seen = new Set<string>();
  const weighted: { idea: Idea; w: number }[] = [];
  for (const idea of rows) {
    const fp = [idea.direction, idea.entry_low, idea.entry_high, idea.stop_loss, idea.take_profits.join(','), idea.author].join('|');
    if (seen.has(fp)) { weighted.push({ idea, w: 0.05 }); continue; }
    seen.add(fp);
    weighted.push({ idea, w: 1 });
  }
  const eligible = weighted.filter((x) => x.w >= 1);
  const counts = { long: 0, short: 0, neutral: 0 };
  for (const x of eligible) counts[x.idea.direction] += 1;

  const totalW = eligible.reduce((s, x) => s + x.w, 0) || 1;
  const longW = eligible.filter((x) => x.idea.direction === 'long').reduce((s, x) => s + x.w, 0);
  const shortW = eligible.filter((x) => x.idea.direction === 'short').reduce((s, x) => s + x.w, 0);
  const direction: Direction = longW >= shortW ? 'long' : 'short';
  const domShare = Math.max(longW, shortW) / totalW;
  const camp = eligible.filter((x) => x.idea.direction === direction);

  // INDEPENDENCE IS COUNTED IN SOURCES, NOT IN IDEAS.
  //
  // This previously compared `camp.length` against MIN_INDEPENDENT_SOURCES. That
  // count is DISTINCT FINGERPRINTS, not publishers, so one source emitting nine
  // differently-worded ideas satisfied "at least two independent sources" and
  // produced a live DEVELOPING setup with entry/SL/TP and a COPY LEVELS button.
  // Observed live 2026-10-06: 11 ideas, 1 distinct source_id, strength 86.
  //
  // Fingerprints include `author`, so a single source that labels its rows
  // "desk-a", "desk-b", "desk-c" defeats a fingerprint check entirely — which is
  // exactly the divided-room case spec §5 tells us to collapse.
  //
  // Sources whose url is `internal://` are the pipeline's own seed data. They
  // are excluded from the independence count so they can never stand in for an
  // external publisher, per D-20261005-001: "1-of-1 is not consensus".
  //
  // Sources with enabled = false are likewise excluded. Registration is not
  // permission: FXScalpers is registered (migration 0020) but stays disabled
  // until its written permission is archived (D-20261006-017), and a disabled
  // source counts nothing even if approved idea rows somehow existed for it.
  // Voting needs BOTH an enabled source AND curated_ok rows - either switch
  // alone fails closed.
  const { data: sourceRows } = await db.from('sources').select('id, url, name, enabled');
  const srcList = ((sourceRows ?? []) as { id: string; url: string | null; enabled: boolean | null }[]);
  const internalSourceIds = new Set(
    srcList.filter((s) => (s.url ?? '').startsWith('internal://')).map((s) => s.id),
  );
  const disabledSourceIds = new Set(
    srcList.filter((s) => s.enabled === false).map((s) => s.id),
  );
  const campSourceIds = new Set(camp.map((x) => x.idea.source_id));
  const externalSourceIds = [...campSourceIds].filter((id) => !internalSourceIds.has(id) && !disabledSourceIds.has(id));
  const distinctExternalSources = externalSourceIds.length;

  if (distinctExternalSources < MIN_INDEPENDENT_SOURCES || domShare < MIN_DOMINANT_SHARE) {
    const reason = distinctExternalSources < MIN_INDEPENDENT_SOURCES
      ? (campSourceIds.size === 0 ? 'NO_SOURCES' : 'SINGLE_SOURCE')
      : 'DIVIDED';
    const { error: noConsensusErr } = await db.from('consensus_signals').insert({
      symbol: 'XAUUSD', timeframe: 'M15', direction: 'neutral', strength: 0,
      status: toDbStatus('expired'), created_at: now.toISOString(), updated_at: now.toISOString(),
      expires_at: now.toISOString(),
    });
    if (noConsensusErr) {
      console.error(`build-consensus: no-consensus audit write failed (${reason}): ${noConsensusErr.message}`);
      return Response.json({ ok: false, consensus: 'NO_CONSENSUS', reason, auditWritten: false, error: noConsensusErr.message }, { status: 500 });
    }
    return Response.json({
      ok: true,
      consensus: 'NO_CONSENSUS',
      reason,
      counts,
      eventContext,
      // Reported so the UI and the logs can say WHY, instead of leaving a
      // "0 of 0 sources" number that looks like an absence rather than a refusal.
      independence: {
        ideas: camp.length,
        distinct_sources: campSourceIds.size,
        distinct_external_sources: distinctExternalSources,
        internal_seed_sources: campSourceIds.size - distinctExternalSources,
      },
    });
  }

  const entry = clusterRanges(camp.map((x) => ({ low: x.idea.entry_low, high: x.idea.entry_high })));
  const sl = clusterValues(camp.map((x) => x.idea.stop_loss));
  const byTp: Record<number, number[]> = {};
  for (const x of camp) {
    x.idea.takeProfits.forEach((tp, i) => {
      (byTp[i + 1] ??= []).push(tp);
    });
  }
  const tps = clusterTakeProfits(byTp);
  const tpList = [tps[1]?.consensus, tps[2]?.consensus, tps[3]?.consensus].filter((v): v is number => v !== undefined);

  // Agreement score (same weights as Dart ScoreBreakdown).
  const dirAgree = domShare;
  const entryAgree = Math.min(1, entry.inliers.length / camp.length);
  const slAgree = Math.min(1, sl.inliers.length / camp.length);
  const tpAgree = tpList.length > 0 ? 1 : 0;
  const withReason = camp.filter((x) => (x.idea.reasoning ?? '').length > 0).length / camp.length;
  const freshW = camp.reduce((s, x) => {
    const ageMin = (now.getTime() - new Date(x.idea.published_at).getTime()) / 60000;
    return s + (ageMin < 15 ? 1 : ageMin < 30 ? 0.66 : 0.33);
  }, 0) / camp.length;
  // Independence is scored in SOURCES. Using the idea count here would let one
  // publisher posting nine variants reach full marks on the independence
  // component of the score.
  const indepW = Math.min(1, distinctExternalSources / 4);
  const score = Math.round(
    dirAgree * dirWeight.long + entryAgree * dirWeight.entry + slAgree * dirWeight.stopLoss +
    tpAgree * dirWeight.takeProfit + withReason * dirWeight.reasoning +
    freshW * dirWeight.freshness + indepW * dirWeight.independence,
  );
  if (score < CONSENSUS_THRESHOLD) return fail('WEAK', counts);

  // XV presents ONE active setup. Without this, every 5-minute run stacked a
  // fresh DEVELOPING row on top of the previous one and the table accumulated
  // 11 simultaneously-ACTIVE signals (observed live 2026-10-02). Supersede
  // the open rows first so the newest consensus is the only live setup and
  // "N of M agree" resolves to exactly one signal.
  await db.from('consensus_signals')
    .update({ status: toDbStatus('expired'), updated_at: now.toISOString() })
    .eq('symbol', 'XAUUSD')
    .in('status', ['DEVELOPING', 'READY', 'CONFIRMED', 'ACTIVE', 'TP1_HIT', 'TP2_HIT']);

  const { data: signal, error: sigErr } = await db.from('consensus_signals').insert({
    symbol: 'XAUUSD',
    timeframe: 'M15',
    direction,
    strength: score,
    entry_low: entry.consensus.low,
    entry_high: entry.consensus.high,
    stop_loss: sl.consensus,
    tp1: tpList[0] ?? null,
    tp2: tpList[1] ?? null,
    tp3: tpList[2] ?? null,
    status: toDbStatus('developing'),
    created_at: now.toISOString(),
    updated_at: now.toISOString(),
    expires_at: new Date(now.getTime() + 60 * 60000).toISOString(),
  }).select('id').single();
  if (sigErr) return Response.json({ ok: false, error: sigErr.message }, { status: 500 });

  await db.from('signal_sources').insert(
    camp.map((x) => ({
      signal_id: (signal as { id: string }).id,
      trade_idea_id: x.idea.id,
      independence_weight: x.w,
      contribution_score: Math.round((x.w / totalW) * 100),
    })),
  );
  return Response.json({
    ok: true, consensus: direction.toUpperCase(), strength: score,
    band: strengthBand(score), counts, eventContext,
  });
});
