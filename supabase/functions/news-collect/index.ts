/**
 * news-collect — scheduled Edge Function, every 30 min (TASK-07 T7.5).
 *
 * Searches the gold-relevant macro query set (addendum §3.1) through a
 * `NewsProvider`, dedupes by URL + title fingerprint, and stores
 * `news_articles`. Headlines + links (+ short summaries) ONLY — never
 * full publisher article text (copyright rule, addendum §8).
 *
 * Providers:
 *   * `GNewsAdapter` (DEV/TEST ONLY): written for local exercise, stays
 *     DISABLED unless `GNEWS_ENABLED=true`. GNews free tier is
 *     non-commercial only — production needs a paid plan or an alternative
 *     with a recorded licensing review (Gate G5 pattern).
 *
 * There is deliberately NO default provider. `ManualNews` used to be the
 * default, writing invented "Manual Desk" headlines with example.com links
 * into production on every 30-minute run - and news-digest summarized those
 * inventions into the "macro backdrop" themes on screen (observed live
 * 2026-10-07: a "Fed policy repricing" theme evidenced only by example.com
 * seed URLs). That was fabrication wearing a pipeline uniform, the same class
 * as the retired ManualSeed calendar fixtures. The class stays below so the
 * shape remains tested, but nothing in production can reach it: with no
 * approved provider this function reports empty and writes nothing.
 * An empty news table renders honest silence; invented headlines do not.
 *
 * Query-plan note (addendum §8 quota math): 30-min × ~8 queries overruns
 * GNews free (100 req/day). Until a paid tier lands, the live path batches
 * to MAX_QUERIES_PER_CYCLE queries per cycle at an hourly cadence
 * (~72/day max, within quota).
 *
 * Env: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY,
 *      GNEWS_ENABLED (default 'false'), GNEWS_API_KEY (only when enabled)
 */
import { createClient } from 'jsr:@supabase/supabase-js@2';

/** Gold-relevant macro query set (addendum §3.1, hardcoded in MVP). */
export const QUERY_SET = [
  'gold',
  'XAUUSD',
  'Federal Reserve',
  'FOMC',
  'CPI inflation',
  'NFP payrolls',
  'ECB rates',
  'US dollar index',
] as const;

/** Max provider queries per cycle (quota guard, see header note). */
export const MAX_QUERIES_PER_CYCLE = 3;

/** Normalized article — headline + link only, never full text. */
export interface RawArticle {
  sourceName: string;
  url: string;
  title: string;
  summary: string | null;
  publishedAt: string | null;
  queryTag: string;
}

/** Provider contract — never hard-wire a news source (rule 8). */
export interface NewsProvider {
  readonly name: string;
  search(query: string): Promise<RawArticle[]>;
}

/** Simple stable fingerprint for dedupe (URL + normalized title). */
export function fingerprint(url: string, title: string): string {
  const norm = `${url.trim().toLowerCase()}|${title.trim().toLowerCase().replace(/\s+/g, ' ')}`;
  let h = 0;
  for (let i = 0; i < norm.length; i++) {
    h = (Math.imul(h, 31) + norm.charCodeAt(i)) | 0;
  }
  return `fp-${(h >>> 0).toString(16)}`;
}

/**
 * ManualNews — RETIRED from the production path (2026-10-07).
 *
 * It wrote invented "Manual Desk" headlines with example.com links into
 * production news_articles, and news-digest summarized those inventions into
 * on-screen macro themes. The class stays so its shape remains tested, but
 * nothing below constructs it: with no approved provider the function reports
 * empty and writes nothing.
 */
export class ManualNews implements NewsProvider {
  readonly name = 'manual';
  async search(query: string): Promise<RawArticle[]> {
    const now = Date.now();
    const iso = (minAgo: number) => new Date(now - minAgo * 60000).toISOString();
    const seed: RawArticle[] = [
      {
        sourceName: 'Manual Desk',
        url: 'https://example.com/news/fed-stance-seed',
        title: 'Seed: Fed officials reiterate data-dependent stance (manual seed)',
        summary: 'Curated placeholder headline for offline development.',
        publishedAt: iso(42),
        queryTag: query,
      },
      {
        sourceName: 'Manual Desk',
        url: 'https://example.com/news/gold-steady-seed',
        title: 'Seed: Gold holds range ahead of US data (manual seed)',
        summary: 'Curated placeholder headline for offline development.',
        publishedAt: iso(95),
        queryTag: query,
      },
    ];
    return seed;
  }
}

/**
 * GNewsAdapter — DEV/TEST ONLY (free tier = non-commercial).
 * Never enabled in production without a paid plan or alternative +
 * recorded review.
 */
export class GNewsAdapter implements NewsProvider {
  readonly name = 'gnews';
  constructor(private apiKey: string) {}

  async search(query: string): Promise<RawArticle[]> {
    const url =
      `https://gnews.io/api/v4/search?q=${encodeURIComponent(query)}&max=10&lang=en&apikey=${this.apiKey}`;
    const r = await fetch(url);
    if (!r.ok) throw new Error(`GNews HTTP ${r.status}`);
    const j = (await r.json()) as { articles?: Array<Record<string, unknown>> };
    return (j.articles ?? []).map((a) => ({
      sourceName: String((a['source'] as Record<string, unknown> | undefined)?.['name'] ?? 'unknown'),
      url: String(a['url'] ?? ''),
      title: String(a['title'] ?? '').slice(0, 300),
      // Headline + short description only — never the full content field.
      summary: typeof a['description'] === 'string' ? a['description'].slice(0, 500) : null,
      publishedAt: typeof a['publishedAt'] === 'string' ? a['publishedAt'] : null,
      queryTag: query,
    })).filter((a) => a.url && a.title);
  }
}

Deno.serve(async (_req) => {
  const url = Deno.env.get('SUPABASE_URL')!;
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const db = createClient(url, key);
  const now = new Date();

  let provider: NewsProvider | null = null;
  if (Deno.env.get('GNEWS_ENABLED') === 'true') {
    const gkey = Deno.env.get('GNEWS_API_KEY');
    if (!gkey) return Response.json({ ok: false, error: 'GNEWS_ENABLED but no GNEWS_API_KEY.' }, { status: 500 });
    provider = new GNewsAdapter(gkey);
  }
  if (provider === null) {
    return Response.json({
      ok: true,
      provider: 'none',
      stored: 0,
      dupes: 0,
      note: 'no approved news provider is configured; reporting empty rather than invented headlines.',
      at: now.toISOString(),
    });
  }

  const queries = QUERY_SET.slice(0, MAX_QUERIES_PER_CYCLE);
  let stored = 0;
  let dupes = 0;
  for (const q of queries) {
    let rows: RawArticle[];
    try {
      rows = await provider.search(q);
    } catch (e) {
      return Response.json({ ok: false, error: String(e) }, { status: 500 });
    }
    for (const a of rows) {
      const fp = fingerprint(a.url, a.title);
      const { error } = await db.from('news_articles').upsert(
        {
          source_name: a.sourceName,
          url: a.url,
          title: a.title,
          summary: a.summary,
          published_at: a.publishedAt,
          collected_at: now.toISOString(),
          query_tag: a.queryTag,
          fingerprint: fp,
        },
        { onConflict: 'fingerprint' },
      );
      if (error) {
        // Unique-url race (same URL, retitled) → count as dupe, keep moving.
        if (error.message.includes('duplicate') || error.message.includes('unique')) { dupes++; continue; }
        return Response.json({ ok: false, error: error.message }, { status: 500 });
      }
      stored++;
    }
  }
  console.log(`news-collect: provider=${provider.name} stored=${stored} dupes=${dupes}`);
  return Response.json({ ok: true, provider: provider.name, stored, dupes, at: now.toISOString() });
});
