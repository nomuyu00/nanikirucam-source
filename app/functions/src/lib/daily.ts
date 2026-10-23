import { addDays } from './dates';
import { accuracy, isSingleAnswer } from './stats';
import type { Stats } from './stats';
import type { AnswerInput } from './validate';

/** 選出・投稿の候補に必要な問題の要約。 */
export interface ProblemSummary {
  id: string;
  authorUid: string;
  hidden: boolean;
  reports: number;
  stats: Pick<Stats, 'total' | 'correct'>;
  /** 最後に今日の問題に選ばれた日（`YYYY-MM-DD`）。 */
  featuredDaily: string | null;
  posted: boolean;
  answer: Pick<AnswerInput, 'byAxis'>;
}

export interface PickOptions {
  /** 今日（JST の `YYYY-MM-DD`）。 */
  today: string;
  minAnswers: number;
  minAccuracy: number;
  maxAccuracy: number;
  cooldownDays: number;
  count: number;
  /** すでに選んだ（公式など）問題 ID。 */
  excludeIds?: readonly string[];
}

export const DEFAULT_PICK_OPTIONS = {
  minAnswers: 20,
  minAccuracy: 0.4,
  maxAccuracy: 0.6,
  cooldownDays: 30,
  count: 2,
} as const;

/** ユーザー投稿の選出条件（設計書 6 章）を満たすか。 */
export function isPickEligible(p: ProblemSummary, o: PickOptions): boolean {
  if (p.hidden || p.reports > 0) return false;
  if (o.excludeIds?.includes(p.id)) return false;
  if (p.stats.total < o.minAnswers) return false;
  const rate = accuracy(p.stats);
  if (rate === null || rate < o.minAccuracy || rate > o.maxAccuracy) return false;
  if (p.featuredDaily) {
    // 直近 cooldownDays 日以内に選ばれていれば除外
    const earliestOk = addDays(p.featuredDaily, o.cooldownDays);
    if (earliestOk > o.today) return false;
  }
  return true;
}

/**
 * ユーザー投稿から今日の問題を選ぶ。
 * 条件: 回答 20 以上、正解率 40〜60%、通報 0、直近 30 日未選出。
 * 並び: 3 軸の解が割れている問題を優先 → 正解率が 50% に近い → 回答数が多い → ID 順。
 * 同じ出題者は 1 日 1 問まで。
 */
export function selectUserPicks(
  candidates: readonly ProblemSummary[],
  options: PickOptions,
): ProblemSummary[] {
  const eligible = candidates.filter((p) => isPickEligible(p, options));
  eligible.sort((a, b) => {
    const splitA = isSingleAnswer(a.answer) ? 0 : 1;
    const splitB = isSingleAnswer(b.answer) ? 0 : 1;
    if (splitA !== splitB) return splitB - splitA;
    const distA = Math.abs((accuracy(a.stats) ?? 0) - 0.5);
    const distB = Math.abs((accuracy(b.stats) ?? 0) - 0.5);
    if (distA !== distB) return distA - distB;
    if (a.stats.total !== b.stats.total) return b.stats.total - a.stats.total;
    return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
  });
  const picked: ProblemSummary[] = [];
  const authors = new Set<string>();
  for (const p of eligible) {
    if (picked.length >= options.count) break;
    if (authors.has(p.authorUid)) continue;
    authors.add(p.authorUid);
    picked.push(p);
  }
  return picked;
}

/**
 * 自動投稿の対象を選ぶ（設計書 6 章・仕様 8.3）。
 * 候補は今日の問題（公式 + 選出 2 問）。通報なし・非表示でない・未投稿のうち、
 * 3 軸が割れている → 正解率が 50% に近い（回答が少ない公式は中立）→ 回答数が多い順。
 */
export function choosePostTarget(
  candidates: readonly ProblemSummary[],
): ProblemSummary | null {
  const eligible = candidates.filter((p) => !p.hidden && p.reports === 0 && !p.posted);
  if (eligible.length === 0) return null;
  const score = (p: ProblemSummary): [number, number, number] => {
    const split = isSingleAnswer(p.answer) ? 0 : 1;
    const rate = accuracy(p.stats);
    const dist = rate === null || p.stats.total < 5 ? 0.25 : Math.abs(rate - 0.5);
    return [split, -dist, p.stats.total];
  };
  return [...eligible].sort((a, b) => {
    const sa = score(a);
    const sb = score(b);
    for (let i = 0; i < sa.length; i++) {
      if (sa[i] !== sb[i]) return sb[i] - sa[i];
    }
    return a.id < b.id ? -1 : 1;
  })[0];
}

/** 今週の難問（正解率が低い順）。回答が `minAnswers` 未満の問題は除く。 */
export function rankHardest(
  problems: readonly ProblemSummary[],
  minAnswers: number,
  count: number,
): ProblemSummary[] {
  return problems
    .filter((p) => !p.hidden && p.reports === 0 && p.stats.total >= minAnswers)
    .sort((a, b) => {
      const ra = accuracy(a.stats) ?? 1;
      const rb = accuracy(b.stats) ?? 1;
      if (ra !== rb) return ra - rb;
      if (a.stats.total !== b.stats.total) return b.stats.total - a.stats.total;
      return a.id < b.id ? -1 : 1;
    })
    .slice(0, count);
}

/**
 * 「速さ派 vs 打点派」の割合。速さ軸と打点軸の解が異なる問題だけを対象に、
 * 速さ軸にだけ含まれる牌を選んだ人数と、打点軸にだけ含まれる牌を選んだ人数を数える。
 */
export function axisShare(
  problems: readonly { answer: Pick<AnswerInput, 'byAxis'>; byTile: Record<string, number> }[],
): { speed: number; points: number; ratioSpeed: number | null } {
  let speed = 0;
  let points = 0;
  const kind = (label: string) => (label[0] === '0' ? `5${label[1]}` : label);
  for (const p of problems) {
    const s = new Set(p.answer.byAxis.speed.map(kind));
    const pt = new Set(p.answer.byAxis.points.map(kind));
    const byKind: Record<string, number> = {};
    for (const [label, count] of Object.entries(p.byTile)) {
      byKind[kind(label)] = (byKind[kind(label)] ?? 0) + count;
    }
    for (const [k, count] of Object.entries(byKind)) {
      if (s.has(k) && !pt.has(k)) speed += count;
      if (pt.has(k) && !s.has(k)) points += count;
    }
  }
  const sum = speed + points;
  return { speed, points, ratioSpeed: sum > 0 ? speed / sum : null };
}
