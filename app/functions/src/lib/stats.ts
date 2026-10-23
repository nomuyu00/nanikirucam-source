import { createHash } from 'node:crypto';
import { tileKind } from './tiles';
import type { Axis, AnswerInput } from './validate';

export interface Stats {
  total: number;
  byTile: Record<string, number>;
  /** バランス軸の解と一致した回答数。 */
  correct: number;
}

export function emptyStats(): Stats {
  return { total: 0, byTile: {}, correct: 0 };
}

/** Firestore から読んだ `stats` を安全に正規化する（欠損・型崩れを 0 扱い）。 */
export function normalizeStats(raw: unknown): Stats {
  const stats = emptyStats();
  if (typeof raw !== 'object' || raw === null) return stats;
  const r = raw as Record<string, unknown>;
  stats.total = Number.isFinite(r.total) ? Math.max(0, Math.floor(r.total as number)) : 0;
  stats.correct = Number.isFinite(r.correct) ? Math.max(0, Math.floor(r.correct as number)) : 0;
  if (typeof r.byTile === 'object' && r.byTile !== null) {
    for (const [label, count] of Object.entries(r.byTile as Record<string, unknown>)) {
      if (Number.isFinite(count) && (count as number) > 0) {
        stats.byTile[label] = Math.floor(count as number);
      }
    }
  }
  return stats;
}

/** 回答 1 件を反映した新しい `stats`（引数は変更しない）。 */
export function applyAnswerToStats(prev: Stats, tile: string, correct: boolean): Stats {
  return {
    total: prev.total + 1,
    byTile: { ...prev.byTile, [tile]: (prev.byTile[tile] ?? 0) + 1 },
    correct: prev.correct + (correct ? 1 : 0),
  };
}

export interface AxisJudgement {
  speed: boolean;
  points: boolean;
  balance: boolean;
}

/** 選んだ牌が各軸の解に含まれるか（赤5 は通常の 5 と同一視）。 */
export function judgeAnswer(answer: Pick<AnswerInput, 'byAxis'>, tile: string): AxisJudgement {
  const kind = tileKind(tile);
  const has = (axis: Axis) => answer.byAxis[axis].some((label) => tileKind(label) === kind);
  return { speed: has('speed'), points: has('points'), balance: has('balance') };
}

/** 3 軸の解がすべて同じ牌の集合か（一択）。 */
export function isSingleAnswer(answer: Pick<AnswerInput, 'byAxis'>): boolean {
  const key = (axis: Axis) => [...new Set(answer.byAxis[axis].map(tileKind))].sort().join(',');
  return key('speed') === key('points') && key('points') === key('balance');
}

/** 正解率（0..1）。回答がなければ null。 */
export function accuracy(stats: Pick<Stats, 'total' | 'correct'>): number | null {
  return stats.total > 0 ? stats.correct / stats.total : null;
}

/** 出題者へ通知する回答数。 */
export const MILESTONES: readonly number[] = [10, 50, 100];

/** `total` が節目に到達した瞬間ならその値、そうでなければ null。 */
export function milestoneReached(prevTotal: number, newTotal: number): number | null {
  for (const m of MILESTONES) {
    if (prevTotal < m && newTotal >= m) return m;
  }
  return null;
}

/**
 * 二重回答判定用の ID。Web は端末ごとのランダム ID、アプリは Firebase uid を
 * 種類ごとの接頭辞つきで SHA-256 にする。回答ドキュメントの ID と `fingerprint` に使う。
 */
export function fingerprintHash(source: 'web' | 'app', raw: string): string {
  return createHash('sha256').update(`${source}:${raw}`).digest('hex').slice(0, 40);
}

export const FINGERPRINT_PATTERN = /^[A-Za-z0-9_-]{16,64}$/;
