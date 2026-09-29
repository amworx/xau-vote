/**
 * news-digest — scheduled Edge Function, hourly (TASK-07 T7.6).
 *
 * Clusters the last 24h of `news_articles` into 3–5 macro themes and stores
 * ONE `news_digests` row with the FIXED output schema (addendum §3.2):
 *
 *   { theme: string, pressure: 'HAWKISH'|'DOVISH'|'NEUTRAL'|'UNCLEAR',
 *     evidence_urls: string[] }
 *
 * Hard constraints (mirror spec §23 + AGENTS.md rule 9):
 *   * No free prose reaches the consensus engine — themes + pressure enum
 *     + evidence links only.
 *   * Pressure is DISPLAY-ONLY context (Radar "Macro backdrop" strip).
 *   * Uncertain extraction → 'UNCLEAR', never forced.
 *   * AI (when wired) SUMMARIZES; it never forecasts direction or levels.
 *
 * MVP clustering: deterministic keyword heuristic (no AI key needed, fully
 * testable). An AI pass may replace `clusterArticles` later behind review —
 * the fixed schema + UNCLEAR fallback stay regardless.
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

export type Pressure = 'HAWKISH' | 'DOVISH' | 'NEUTRAL' | 'UNCLEAR';

export interface DigestTheme {
  theme: string;
  pressure: Pressure;
  evidence_urls: string[];
}

interface Article {
  url: string;
  title: string;
  summary: string | null;
  queryTag: string | null;
}

const HAWKISH_RX = /(hawkish|rate hike|higher for longer|tightening|hotter than expected|sticky inflation|fed officials warn|hawk)/i;
const DOVISH_RX = /(dovish|rate cut|easing|cooler than expected|disinflation|soft landing hopes|dove)/i;

function pressureOf(text: string): Pressure | null {
  const h = HAWKISH_RX.test(text);
  const d = DOVISH_RX.test(text);
  if (h && !d) return 'HAWKISH';
  if (d && !h) return 'DOVISH';
  if (!h && !d) return 'NEUTRAL';
  return null; // mixed signals → caller falls back to UNCLEAR
}

function bucketOf(a: Article): string {
  const t = `${a.title} ${a.summary ?? ''} ${a.queryTag ?? ''}`.toLowerCase();
  if (t.includes('fed') || t.includes('fomc') || t.includes('powell') || t.includes('federal reserve')) return 'Fed policy repricing';
  if (t.includes('cpi') || t.includes('inflation') || t.includes('ppi')) return 'US inflation path';
  if (t.includes('nfp') || t.includes('payroll') || t.includes('jobs') || t.includes('unemployment')) return 'US labor market';
  if (t.includes('ecb') || t.includes('euro') || t.includes('boe') || t.includes('central bank')) return 'Other central banks';
  if (t.includes('dollar') || t.includes('dxy') || t.includes('yield') || t.includes('treasury')) return 'Dollar & yields';
  return 'Gold flows & geopolitics';
}

/**
 * Deterministic cluster → fixed-schema themes. Pure: unit-testable without
 * any backend. Mixed/uncertain buckets collapse to UNCLEAR (never forced).
 */
export function clusterArticles(articles: Article[]): DigestTheme[] {
  const groups = new Map<string, Article[]>();
  for (const a of articles) {
    const b = bucketOf(a);
    if (!groups.has(b)) groups.set(b, []);
    groups.get(b)!.push(a);
  }
  const themes: DigestTheme[] = [];
  for (const [theme, items] of groups) {
    const votes = items.map((a) => pressureOf(`${a.title} ${a.summary ?? ''}`));
    const nonNull = votes.filter((v): v is Pressure => v !== null);
    let pressure: Pressure;
    if (nonNull.length === 0) {
      pressure = 'UNCLEAR';
    } else {
      const counts = new Map<Pressure, number>();
      for (const v of nonNull) counts.set(v, (counts.get(v) ?? 0) + 1);
      const top = [...counts.entries()].sort((a, b) => b[1] - a[1]);
      // Forced only on a strict majority; ties/mixed → UNCLEAR.
      pressure = top.length > 0 && top[0][1] > items.length / 2 ? top[0][0] : 'UNCLEAR';
    }
    themes.push({ theme, pressure, evidence_urls: items.slice(0, 3).map((a) => a.url) });
  }
  return themes.slice(0, 5);
}

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();
  const windowStart = new Date(now.getTime() - 24 * 3600 * 1000);

  const { data, error } = await db.from('news_articles')
    .select('url,title,summary,query_tag')
    .gte('collected_at', windowStart.toISOString())
    .order('collected_at', { ascending: false })
    .limit(200);
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });

  const articles = ((data ?? []) as Array<{ url: string; title: string; summary: string | null; query_tag: string | null }>)
    .map((r) => ({ url: r.url, title: r.title, summary: r.summary, queryTag: r.query_tag }));
  const themes = clusterArticles(articles);

  const { error: insErr } = await db.from('news_digests').insert({
    window_start: windowStart.toISOString(),
    window_end: now.toISOString(),
    themes,
    created_at: now.toISOString(),
  });
  if (insErr) return Response.json({ ok: false, error: insErr.message }, { status: 500 });
  console.log(`news-digest: articles=${articles.length} themes=${themes.length}`);
  return Response.json({ ok: true, articles: articles.length, themes, at: now.toISOString() });
});
