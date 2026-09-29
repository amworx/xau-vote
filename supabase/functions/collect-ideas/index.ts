/**
 * collect-ideas — scheduled Edge Function (TASK-04 T4.2).
 *
 * Runs per enabled IdeaSource adapter, normalizes external data into the
 * TradeIdea shape (spec §4), applies the pre-consensus filter chain
 * (spec §4 order), dedupes on (source_id, fingerprint), and upserts
 * trade_ideas. Service-role key only; never exposed to clients.
 *
 * MVP reality: real source adapters arrive in Phase 7 (each behind its
 * licensing review). Until then this function seeds MANUAL fixture ideas
 * so the pipeline is exercisable end to end.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { freshnessBand } from '../_shared/engine.ts';

interface SeedIdea {
  source: string;
  author: string;
  direction: 'long' | 'short' | 'neutral';
  entryLow: number;
  entryHigh: number;
  stopLoss: number;
  takeProfits: number[];
  publishedMinutesAgo: number;
  reasoning: string;
}

// Manual seed only. Replaced by licensed adapters in Phase 7.
const SEED_IDEAS: SeedIdea[] = [
  { source: 'manual-seed', author: 'desk-a', direction: 'long', entryLow: 4275, entryHigh: 4280, stopLoss: 4262, takeProfits: [4295, 4315, 4340], publishedMinutesAgo: 6, reasoning: 'Bounce off the 4275 shelf; momentum turning up.' },
  { source: 'manual-seed', author: 'desk-b', direction: 'long', entryLow: 4276, entryHigh: 4281, stopLoss: 4264, takeProfits: [4298, 4320], publishedMinutesAgo: 11, reasoning: 'Higher low printed; retest of broken high.' },
  { source: 'manual-seed', author: 'desk-c', direction: 'long', entryLow: 4274, entryHigh: 4279, stopLoss: 4263, takeProfits: [4296, 4318], publishedMinutesAgo: 14, reasoning: 'Bid cluster 4274-80; clean invalidation below.' },
  { source: 'manual-seed', author: 'desk-d', direction: 'short', entryLow: 4285, entryHigh: 4285, stopLoss: 4300, takeProfits: [4260], publishedMinutesAgo: 22, reasoning: 'Overextended into supply; fade the push.' },
];

const fingerprint = (s: SeedIdea): string =>
  [s.direction, s.entryLow, s.entryHigh, s.stopLoss, s.takeProfits.join(','), s.author].join('|');

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();
  const stored: string[] = [];
  const rejected: { author: string; reason: string }[] = [];

  for (const s of SEED_IDEAS) {
    // Spec §4 filter chain: symbol → intraday → 15M → fresh → actionable.
    const fresh = freshnessBand(s.publishedMinutesAgo);
    if (fresh === 'expired') { rejected.push({ author: s.author, reason: 'STALE' }); continue; }
    if (s.takeProfits.length === 0) { rejected.push({ author: s.author, reason: 'INSUFFICIENT DATA' }); continue; }
    const row = {
      source_id: null as string | null,
      symbol: 'XAUUSD',
      timeframe: 'm15',
      direction: s.direction,
      entry_low: s.entryLow,
      entry_high: s.entryHigh,
      stop_loss: s.stopLoss,
      take_profits: s.takeProfits,
      trigger_condition: null,
      invalidation_condition: null,
      reasoning: s.reasoning,
      author: s.author,
      published_at: new Date(now.getTime() - s.publishedMinutesAgo * 60000).toISOString(),
      collected_at: now.toISOString(),
      fingerprint: fingerprint(s),
    };
    // Resolve the manual-seed source row once per run (cheap, scheduled rarely).
    const { data: src } = await db.from('sources').select('id').eq('name', s.source).maybeSingle();
    if (src) row.source_id = (src as { id: string }).id;
    const { error } = await db.from('trade_ideas').upsert(row, { onConflict: 'source_id,fingerprint' });
    if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
    stored.push(s.author);
  }
  return Response.json({ ok: true, stored, rejected, at: now.toISOString() });
});
