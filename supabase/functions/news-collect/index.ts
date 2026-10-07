/**
 * news-collect — scheduled Edge Function, every 30 min (TASK-07 T7.5).
 *
 * Collects gold-relevant macro headlines through `NewsProvider`s, dedupes by
 * URL + title fingerprint, and stores `news_articles`. Headlines + links
 * (+ short feed-supplied summaries) ONLY — never full publisher article text
 * (copyright rule, addendum §8).
 *
 * Providers:
 *   * `RssIssuerProvider` (APPROVED, D-20261007-025): official issuer + openly
 *     syndicated RSS. US federal feeds (Fed, BLS, BEA) are public domain
 *     works (17 U.S.C. § 105) — free to redistribute with citation and no
 *     endorsement implied. MINING.com expressly permits businesses/websites
 *     to serve its feed content to their own users with link-back, which the
 *     app already does for every headline. No auth, no key, poll-friendly.
 *     BLS bot-walls non-browser clients (403 observed 2026-10-07); the feed
 *     stays configured with per-feed tolerance, so a blocked BLS degrades to
 *     a warning instead of failing the run — if its rows never land, that is
 *     a visible gap, not a silent one.
 *   * `GNewsAdapter` (DEV/TEST ONLY): written for local exercise, stays
 *     DISABLED unless `GNEWS_ENABLED=true`. GNews free tier is
 *     non-commercial only — production needs a paid plan or an alternative
 *     with a recorded licensing review (Gate G5 pattern).
 *
 * There is deliberately NO invented default. `ManualNews` used to be the
 * default, writing invented "Manual Desk" headlines with example.com links
 * into production on every 30-minute run - and news-digest summarized those
 * inventions into the "macro backdrop" themes on screen (observed live
 * 2026-10-07: a "Fed policy repricing" theme evidenced only by example.com
 * seed URLs). That was fabrication wearing a pipeline uniform, the same class
 * as the retired ManualSeed calendar fixtures. The class stays below so its
 * shape remains tested, but nothing in production can reach it.
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

/**
 * One RSS feed: issuer releases and openly syndicated press, fetched raw.
 *
 * `keep` decides relevance per item (feed-level topic + keyword gate), so the
 * Fed's bank-approval noise never becomes a "headline" while FOMC material
 * always does. `queryTag` keeps the addendum §3.1 vocabulary so downstream
 * digest code reads the same tags it always has.
 */
export interface RssFeed {
  sourceName: string;
  url: string;
  queryTag: string;
  keep: (title: string, category: string) => boolean;
}

/** A polite, honest user agent: who we are and how often we ask. Never a
 *  browser impersonation — a block that needs evading is a block we obey. */
const RSS_UA = 'XV-NewsCollector/1.0 (free XAUUSD assistant; polls each feed every 30 minutes)';

/** Strip CDATA wrappers and decode the entities RSS actually uses. Anything
 *  exotic is left verbatim rather than guessed — a mangled headline is a
 *  failed parse, and failed parses are skipped, never repaired by invention. */
export function rssText(raw: string): string {
  let s = raw.replace(/<!\[CDATA\[(.*?)\]\]>/gs, '$1').trim();
  s = s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"').replace(/&#39;|&apos;/g, "'");
  return s.replace(/\s+/g, ' ').trim();
}

function rssField(block: string, tag: string): string | null {
  const m = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i'));
  return m ? rssText(m[1]) : null;
}

/** Parse an RSS 2.0 (`item`) or Atom (`entry`) document into raw items.
 *  Malformed items are skipped; a feed that yields nothing is a warning,
 *  not an error. Namespace prefixes (`atom:entry`, `dc:date`) are collapsed
 *  first — BLS serves namespaced Atom, and without this its items are
 *  invisible to the matcher while the fetch looks healthy. */
export function parseRss(xml: string): Array<{ title: string; url: string; summary: string | null; publishedAt: string | null; category: string }> {
  const doc = xml.replace(/<(\/?)(?:atom|rdf|rss|dc|content|media|sy|wfw|slash):/gi, '<$1');
  const out: Array<{ title: string; url: string; summary: string | null; publishedAt: string | null; category: string }> = [];
  // Split on entry openings rather than matching open/close pairs: some
  // issuer feeds (BLS) never close their entries, so a pair-matcher sees a
  // healthy feed with zero items. Each chunk runs to the next opening (or the
  // document end); field extraction takes the first occurrence, which is the
  // entry's own.
  const chunks = doc.split(/<(?:item|entry)[\s>]/i).slice(1);
  for (const c of chunks) {
    const b = c.split(/<(?:item|entry)[\s>]|<\/(?:feed|rss|channel)>/i)[0];
    const title = rssField(b, 'title');
    // RSS: <link>url</link> (or guid). Atom: <link href="url" /> — the href
    // fallback must ALSO run when there is no link text at all (BLS links
    // are href-only); gating it on a truthy-but-bad url dropped every BLS
    // item while the fetch looked healthy.
    let url = rssField(b, 'link') ?? rssField(b, 'guid');
    if (!url || !/^https?:\/\//i.test(url)) {
      const href = b.match(/<link[^>]*href="([^"]+)"/i);
      url = href ? href[1] : url;
    }
    if (!title || !url || !/^https?:\/\//i.test(url)) continue;
    const pubRaw = rssField(b, 'pubDate') ?? rssField(b, 'published') ??
      rssField(b, 'updated') ?? rssField(b, 'dc:date');
    let publishedAt: string | null = null;
    if (pubRaw) {
      const t = new Date(pubRaw);
      if (!Number.isNaN(t.getTime())) publishedAt = t.toISOString();
    }
    const summary = rssField(b, 'description') ?? rssField(b, 'summary');
    out.push({
      title: title.slice(0, 300),
      url,
      summary: summary ? summary.slice(0, 500) : null,
      publishedAt,
      category: rssField(b, 'category') ?? rssField(b, 'term') ?? '',
    });
  }
  return out;
}

/**
 * RssIssuerProvider — official + openly syndicated RSS (D-20261007-025).
 *
 * Fed monetary releases + speeches (public domain), BEA releases (public
 * domain), BLS employment/CPI (public domain; bot-walled — tolerated), and
 * MINING.com gold news (explicit redistribution permission with link-back,
 * which the app gives every headline). One fetch per feed per cycle; the
 * `search` contract filters the collected items by query so the driver loop
 * and query tags keep working unchanged.
 */
export class RssIssuerProvider implements NewsProvider {
  readonly name = 'rss-issuers';

  private static readonly feeds: RssFeed[] = [
    {
      sourceName: 'Federal Reserve Board',
      url: 'https://www.federalreserve.gov/feeds/press_monetary.xml',
      queryTag: 'FOMC',
      keep: () => true, // the monetary feed is already topic-filtered
    },
    {
      sourceName: 'Federal Reserve Board',
      url: 'https://www.federalreserve.gov/feeds/speeches.xml',
      queryTag: 'Federal Reserve',
      keep: (t) => /rate|inflation|policy|economy|outlook|powell|fomc|monetary/i.test(t),
    },
    {
      sourceName: 'U.S. Bureau of Labor Statistics',
      url: 'https://www.bls.gov/feed/empsit.rss',
      queryTag: 'NFP payrolls',
      keep: () => true,
    },
    {
      sourceName: 'U.S. Bureau of Labor Statistics',
      url: 'https://www.bls.gov/feed/cpi.rss',
      queryTag: 'CPI inflation',
      keep: () => true,
    },
    {
      sourceName: 'U.S. Bureau of Economic Analysis',
      url: 'https://apps.bea.gov/rss/rss.xml',
      queryTag: 'GDP',
      keep: () => true,
    },
    {
      sourceName: 'MINING.com',
      url: 'https://www.mining.com/commodity/gold/feed/',
      queryTag: 'gold',
      keep: (t) => /gold|xau|precious|fed|fomc|rate|inflation|dollar|bullion/i.test(t),
    },
  ];

  /** Fetch every feed once. Per-feed try/catch: one blocked publisher
   *  (bot walls are common on government CDNs) degrades to a named warning,
   *  never a failed run — silence from one feed must not starve the others. */
  async collectAll(): Promise<{ articles: RawArticle[]; warnings: string[]; feedCounts: Record<string, number> }> {
    const articles: RawArticle[] = [];
    const warnings: string[] = [];
    const feedCounts: Record<string, number> = {};
    for (const f of RssIssuerProvider.feeds) {
      const key = `${f.sourceName} :: ${f.url}`;
      try {
        const r = await fetch(f.url, {
          headers: { 'user-agent': RSS_UA, accept: 'application/rss+xml, application/xml, text/xml' },
          signal: AbortSignal.timeout(20_000),
        });
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        const text = await r.text();
        const items = parseRss(text);
        let kept = 0;
        for (const it of items) {
          if (!f.keep(it.title, it.category)) continue;
          kept++;
          articles.push({
            sourceName: f.sourceName,
            url: it.url,
            title: it.title,
            summary: it.summary,
            publishedAt: it.publishedAt,
            queryTag: f.queryTag,
          });
        }
        feedCounts[key] = kept;
        if (items.length > 0 && kept === 0) {
          warnings.push(`${key}: ${items.length} items fetched, none passed the relevance gate`);
        }
        if (items.length === 0) {
          warnings.push(`${key}: fetched OK but yielded 0 kept items`);
        }
      } catch (e) {
        warnings.push(`${f.sourceName} ${f.url}: ${String(e)}`);
      }
    }
    return { articles, warnings, feedCounts };
  }

  async search(query: string): Promise<RawArticle[]> {
    const { articles } = await this.collectAll();
    const q = query.toLowerCase();
    return articles.filter(
      (a) => a.title.toLowerCase().includes(q) || a.queryTag.toLowerCase() === q,
    );
  }
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
  } else {
    // Approved default (D-20261007-025): issuer + openly syndicated RSS.
    provider = new RssIssuerProvider();
  }

  // RSS collects all feeds in one pass; query APIs are polled per query.
  let rows: RawArticle[];
  let warnings: string[] = [];
  let feedCounts: Record<string, number> = {};
  if (provider instanceof RssIssuerProvider) {
    const all = await provider.collectAll();
    rows = all.articles;
    warnings = all.warnings;
    feedCounts = all.feedCounts;
  } else {
    const queries = QUERY_SET.slice(0, MAX_QUERIES_PER_CYCLE);
    rows = [];
    for (const q of queries) {
      try {
        rows.push(...await provider.search(q));
      } catch (e) {
        return Response.json({ ok: false, error: String(e) }, { status: 500 });
      }
    }
  }

  let stored = 0;
  let dupes = 0;
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
  console.log(`news-collect: provider=${provider.name} stored=${stored} dupes=${dupes} warnings=${warnings.length}`);
  return Response.json({ ok: true, provider: provider.name, stored, dupes, warnings, feedCounts, at: now.toISOString() });
});
