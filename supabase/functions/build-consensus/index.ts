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
  CONSENSUS_THRESHOLD,
  MIN_DOMINANT_SHARE,
  MIN_INDEPENDENT_SOURCES,
  type Direction,
} from '../_shared/engine.ts';

interface Idea {
  id: string;
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

  const { data: ideas, error } = await db.from('trade_ideas')
    .select('*')
    .eq('symbol', 'XAUUSD')
    .eq('timeframe', 'm15')
    .gte('published_at', new Date(now.getTime() - 60 * 60000).toISOString())
    .order('published_at', { ascending: false });
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
  const rows = (ideas ?? []) as Idea[];

  const fail = async (reason: string, counts: Record<string, number>) => {
    await db.from('consensus_signals').insert({
      symbol: 'XAUUSD', timeframe: 'm15', direction: 'neutral', strength: 0,
      status: 'expired', created_at: now.toISOString(), updated_at: now.toISOString(),
      expires_at: now.toISOString(),
    });
    return Response.json({ ok: true, consensus: 'NO_CONSENSUS', reason, counts, eventContext });
  };

  if (blocker) {
    // Audit log: suppressed signal attempt → blocking event id (addendum §2).
    const b = blocker as { id: string; title: string; starts_at: string };
    console.log(`build-consensus: BLACKOUT suppressed by event ${b.id} (${b.title} @ ${b.starts_at})`);
    await db.from('consensus_signals').insert({
      symbol: 'XAUUSD', timeframe: 'm15', direction: 'neutral', strength: 0,
      status: 'expired', created_at: now.toISOString(), updated_at: now.toISOString(),
      expires_at: now.toISOString(),
    });
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

  if (camp.length < MIN_INDEPENDENT_SOURCES || domShare < MIN_DOMINANT_SHARE) {
    return fail(camp.length < MIN_INDEPENDENT_SOURCES ? 'SINGLE_SOURCE' : 'DIVIDED', counts);
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
  const indepW = Math.min(1, camp.length / 4);
  const score = Math.round(
    dirAgree * dirWeight.long + entryAgree * dirWeight.entry + slAgree * dirWeight.stopLoss +
    tpAgree * dirWeight.takeProfit + withReason * dirWeight.reasoning +
    freshW * dirWeight.freshness + indepW * dirWeight.independence,
  );
  if (score < CONSENSUS_THRESHOLD) return fail('WEAK', counts);

  const { data: signal, error: sigErr } = await db.from('consensus_signals').insert({
    symbol: 'XAUUSD',
    timeframe: 'm15',
    direction,
    strength: score,
    entry_low: entry.consensus.low,
    entry_high: entry.consensus.high,
    stop_loss: sl.consensus,
    tp1: tpList[0] ?? null,
    tp2: tpList[1] ?? null,
    tp3: tpList[2] ?? null,
    status: 'developing',
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
