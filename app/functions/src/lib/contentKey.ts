import { createHash } from 'node:crypto';
import { compareTiles } from './tiles';
import type { ProblemInput } from './validate';

/**
 * 同じ問題かどうかを判定するキー（SHA-256 の先頭 32 文字）。
 *
 * 手牌は並び順を無視する（ツモ牌だけは区別する）。副露・ドラ表示牌・自風・場風も含める。
 * 巡目・ニックネーム・言語・解答は含めない。
 */
export function contentKey(input: ProblemInput): string {
  const draw = input.tiles[input.tiles.length - 1];
  const closed = input.tiles.slice(0, -1).sort(compareTiles);
  const melds = input.melds
    .map((m) => `${m.kind}:${[...m.tiles].sort(compareTiles).join('')}`)
    .sort();
  const dora = [...input.dora].sort(compareTiles);
  const raw = [
    closed.join(','),
    draw,
    melds.join('|'),
    dora.join(','),
    input.seatWind,
    input.roundWind,
  ].join(';');
  return createHash('sha256').update(raw).digest('hex').slice(0, 32);
}

/** 1 日の公開数の消費。`prev` は `users/{uid}.publishQuota`。 */
export interface PublishQuota {
  date: string;
  count: number;
}

export function consumePublishQuota(
  prev: PublishQuota | undefined | null,
  today: string,
  limit: number,
): { ok: true; next: PublishQuota } | { ok: false; used: number } {
  const used = prev && prev.date === today ? prev.count : 0;
  if (used >= limit) return { ok: false, used };
  return { ok: true, next: { date: today, count: used + 1 } };
}

export const DAILY_PUBLISH_LIMIT = 20;
