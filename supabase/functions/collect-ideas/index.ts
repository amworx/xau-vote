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

/**
 * Manual seed only — replaced by licensed adapters once Gate G4 clears.
 *
 * Levels are expressed as OFFSETS FROM THE LIVE PRICE, not absolute numbers.
 * Hardcoding 4275/4262 worked while the pipeline was fed a mock price of
 * 4278.30, but the moment gold-api.com supplied a real quote (4178.50, then
 * 4139.60 the next day) every seeded idea sat above the market and `tick`
 * correctly invalidated all of them — 215 dead signals in one night.
 *
 * Anchoring to the quote keeps the demo pipeline honest against a moving
 * market: the levels are always near price, so the lifecycle can actually be
 * observed. They are still clearly labelled seed data, never a real desk view.
 */
const SEED_TEMPLATES: Array<
  Omit<SeedIdea, 'entryLow' | 'entryHigh' | 'stopLoss' | 'takeProfits'> & {
    entryLowOff: number; entryHighOff: number; stopOff: number; tpOffs: number[];
  }
> = [
  { source: 'manual-seed', author: 'desk-a', direction: 'long', entryLowOff: -3, entryHighOff: 2, stopOff: -13, tpOffs: [7, 15, 24], publishedMinutesAgo: 6, reasoning: 'Bounce off the shelf; momentum turning up.' },
  { source: 'manual-seed', author: 'desk-b', direction: 'long', entryLowOff: -2, entryHighOff: 3, stopOff: -12, tpOffs: [8, 17], publishedMinutesAgo: 11, reasoning: 'Higher low printed; retest of broken high.' },
  { source: 'manual-seed', author: 'desk-c', direction: 'long', entryLowOff: -4, entryHighOff: 1, stopOff: -14, tpOffs: [7, 16], publishedMinutesAgo: 14, reasoning: 'Bid cluster just below; clean invalidation beneath.' },
  { source: 'manual-seed', author: 'desk-d', direction: 'short', entryLowOff: 6, entryHighOff: 6, stopOff: 16, tpOffs: [-14], publishedMinutesAgo: 22, reasoning: 'Overextended into supply; fade the push.' },
];

/** Build seed ideas around a reference price (the newest snapshot). */
function seedIdeas(base: number): SeedIdea[] {
  const r = (n: number) => Math.round((base + n) * 100) / 100;
  return SEED_TEMPLATES.map((t) => ({
    source: t.source,
    author: t.author,
    direction: t.direction,
    entryLow: r(t.entryLowOff),
    entryHigh: r(t.entryHighOff),
    stopLoss: r(t.stopOff),
    takeProfits: t.tpOffs.map(r),
    publishedMinutesAgo: t.publishedMinutesAgo,
    reasoning: t.reasoning,
  }));
}

const fingerprint = (s: SeedIdea): string =>
  [s.direction, s.entryLow, s.entryHigh, s.stopLoss, s.takeProfits.join(','), s.author].join('|');

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();
  const stored: string[] = [];
  const rejected: { author: string; reason: string }[] = [];

  // Anchor the seed to the newest known price. Never invent one: if no
  // snapshot exists the function declines rather than seeding around a guess.
  const { data: snap } = await db.from('market_snapshots')
    .select('price').eq('symbol', 'XAUUSD')
    .order('timestamp', { ascending: false }).limit(1).maybeSingle();
  const base = (snap as { price?: unknown } | null)?.price;
  if (typeof base !== 'number' || !Number.isFinite(base) || base <= 0) {
    return Response.json({ ok: false, error: 'No market snapshot to anchor seed ideas to.' }, { status: 503 });
  }
  const ideas = seedIdeas(base);

  for (const s of ideas) {
    // Spec §4 filter chain: symbol → intraday → 15M → fresh → actionable.
    const fresh = freshnessBand(s.publishedMinutesAgo);
    if (fresh === 'expired') { rejected.push({ author: s.author, reason: 'STALE' }); continue; }
    if (s.takeProfits.length === 0) { rejected.push({ author: s.author, reason: 'INSUFFICIENT DATA' }); continue; }
    const row = {
      source_id: null as string | null,
      symbol: 'XAUUSD',
      timeframe: 'M15',
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
  return Response.json({ ok: true, anchoredTo: base, stored, rejected, at: now.toISOString() });
});
