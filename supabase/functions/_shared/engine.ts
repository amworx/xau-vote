/**
 * XV (XAU-Vote) engine port (TypeScript, dependency-free, erasable syntax).
 *
 * SOURCE OF TRUTH: the Dart implementation in src/xau_core.
 * This port exists because Supabase Edge Functions run Deno, not Dart
 * (plan decision point T4.2). Any behavior change must first land in Dart,
 * then be mirrored here, then re-validated against golden/*.json.
 *
 * Spec references: §6 consensus, §7 strength bands, §8/§9 clustering,
 * §11 R:R, §14 lifecycle, §15 freshness.
 */

export type Direction = 'long' | 'short' | 'neutral';
export type ConsensusBand = 'WEAK' | 'DEVELOPING' | 'MODERATE' | 'STRONG' | 'VERY_STRONG';
export type SignalStatus =
  | 'noSetup' | 'developing' | 'ready' | 'confirmed' | 'active'
  | 'tp1Hit' | 'tp2Hit' | 'tp3Hit' | 'invalidated' | 'expired';
export type Freshness = 'veryFresh' | 'fresh' | 'aging' | 'expired';

/**
 * Engine `camelCase` status → DB `SCREAMING_CASE` status.
 *
 * The `consensus_signals.status` CHECK constraint (migration 0001) stores
 * `TP1_HIT`, `NO_SETUP`, … while this engine speaks `tp1Hit`, `noSetup`. Every
 * write must go through this so the CHECK never rejects a row.
 */
export function toDbStatus(s: SignalStatus): string {
  return s.replace(/([a-z0-9])([A-Z])/g, '$1_$2').toUpperCase();
}

/** DB `SCREAMING_CASE` status → engine `camelCase` status. Unknown → `expired`. */
export function toEngineStatus(dbStatus: string): SignalStatus {
  const normalized = dbStatus.toLowerCase().replace(/_([a-z])/g, (_, c: string) => c.toUpperCase());
  const known: SignalStatus[] = [
    'noSetup', 'developing', 'ready', 'confirmed', 'active',
    'tp1Hit', 'tp2Hit', 'tp3Hit', 'invalidated', 'expired',
  ];
  return (known as string[]).includes(normalized) ? (normalized as SignalStatus) : 'expired';
}

export interface PriceRange { low: number; high: number; }
export interface ValueCluster {
  inliers: number[];
  outliers: number[];
  consensus: number;
  low: number;
  high: number;
}
export interface RangeCluster {
  consensus: PriceRange;
  inliers: PriceRange[];
  outliers: PriceRange[];
}

export const ENTRY_TOLERANCE = 2.0;
export const SL_TOLERANCE = 6.0;
export const TP_TOLERANCE = 4.0;
export const CONSENSUS_THRESHOLD = 60;
export const MIN_DOMINANT_SHARE = 0.6;
export const MIN_INDEPENDENT_SOURCES = 2;

/** Median. Throws on empty input (mirrors Dart ArgumentError). */
export function median(values: number[]): number {
  if (values.length === 0) throw new Error('Cannot take median of empty list.');
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/** Median-based clustering with fixed tolerance + closest-point fallback. */
export function clusterValues(values: number[], tolerance: number = SL_TOLERANCE): ValueCluster {
  if (values.length === 0) throw new Error('Cannot cluster an empty value list.');
  const med = median(values);
  let inliers = values.filter((v) => Math.abs(v - med) <= tolerance);
  let outliers = values.filter((v) => Math.abs(v - med) > tolerance);
  if (inliers.length === 0) {
    let closest = values[0];
    let best = Math.abs(closest - med);
    for (const v of values.slice(1)) {
      const d = Math.abs(v - med);
      if (d < best) { best = d; closest = v; }
    }
    inliers = [closest];
    outliers = values.filter((v) => v !== closest);
  }
  return {
    inliers, outliers,
    consensus: median(inliers),
    low: Math.min(...inliers),
    high: Math.max(...inliers),
  };
}

const rangeMid = (r: PriceRange): number => (r.low + r.high) / 2;

/** Cluster entry zones by mids; consensus = median low / median high. */
export function clusterRanges(ranges: PriceRange[], tolerance: number = ENTRY_TOLERANCE): RangeCluster {
  if (ranges.length === 0) throw new Error('Cannot cluster an empty range list.');
  const mids = ranges.map(rangeMid);
  const med = median(mids);
  let inliers = ranges.filter((_, i) => Math.abs(mids[i] - med) <= tolerance);
  let outliers = ranges.filter((_, i) => Math.abs(mids[i] - med) > tolerance);
  if (inliers.length === 0) {
    let bestIdx = 0;
    let best = Math.abs(mids[0] - med);
    for (let i = 1; i < mids.length; i++) {
      const d = Math.abs(mids[i] - med);
      if (d < best) { best = d; bestIdx = i; }
    }
    inliers = [ranges[bestIdx]];
    outliers = ranges.filter((_, i) => i !== bestIdx);
  }
  return {
    consensus: { low: median(inliers.map((r) => r.low)), high: median(inliers.map((r) => r.high)) },
    inliers, outliers,
  };
}

/** Cluster TP quotes per 1-based TP index. */
export function clusterTakeProfits(byIndex: Record<number, number[]>, tolerance: number = TP_TOLERANCE): Record<number, ValueCluster> {
  const out: Record<number, ValueCluster> = {};
  for (const key of Object.keys(byIndex)) {
    const values = byIndex[Number(key)];
    if (values.length > 0) out[Number(key)] = clusterValues(values, tolerance);
  }
  return out;
}

/** Spec §7 strength bands. Agreement only, never win probability. */
export function strengthBand(score: number): ConsensusBand {
  if (score < 40) return 'WEAK';
  if (score < 60) return 'DEVELOPING';
  if (score < 75) return 'MODERATE';
  if (score < 90) return 'STRONG';
  return 'VERY_STRONG';
}

export interface RiskReward { risk: number; rewards: number[]; ratios: number[] }

/** Spec §11. Throws on non-positive risk (mirrors Dart). */
export function riskReward(entry: number, stopLoss: number, takeProfits: number[]): RiskReward {
  const risk = Math.abs(entry - stopLoss);
  if (risk <= 0) throw new Error('Risk must be positive.');
  const rewards = takeProfits.map((tp) => Math.abs(tp - entry));
  return { risk, rewards, ratios: rewards.map((r) => r / risk) };
}

/** Spec §15 freshness bands from age in minutes. */
export function freshnessBand(ageMinutes: number): Freshness {
  if (ageMinutes < 15) return 'veryFresh';
  if (ageMinutes < 30) return 'fresh';
  if (ageMinutes < 60) return 'aging';
  return 'expired';
}

const LEGAL_TRANSITIONS: Record<SignalStatus, SignalStatus[]> = {
  noSetup: ['developing'],
  developing: ['ready', 'invalidated', 'expired'],
  ready: ['confirmed', 'invalidated', 'expired'],
  confirmed: ['active', 'invalidated', 'expired'],
  active: ['tp1Hit', 'invalidated'],
  tp1Hit: ['tp2Hit', 'invalidated'],
  tp2Hit: ['tp3Hit', 'invalidated'],
  tp3Hit: [],
  invalidated: [],
  expired: [],
};

/** Spec §14. Returns the next status or throws on illegal transitions. */
export function transition(from: SignalStatus, to: SignalStatus): SignalStatus {
  if (!LEGAL_TRANSITIONS[from].includes(to)) {
    throw new Error(`Illegal signal transition: ${from} -> ${to}`);
  }
  return to;
}

/** Event-guard blackout: no NEW signals from 30 min before to 15 min after a HIGH event. */
export function isBlackout(nowMs: number, eventStartMs: number, impact: string): boolean {
  if (impact !== 'HIGH') return false;
  return nowMs >= eventStartMs - 30 * 60 * 1000 && nowMs <= eventStartMs + 15 * 60 * 1000;
}
