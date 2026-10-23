import type { Timestamp } from 'firebase-admin/firestore';
import type { ProblemSummary } from '../lib/daily';
import { normalizeStats } from '../lib/stats';
import type { Stats } from '../lib/stats';
import type { AnswerInput, MeldInput, Wind } from '../lib/validate';

/**
 * `problems/{problemId}` のドキュメント（API.md 参照）。
 * 正解（answer）はここに含めない。`problems/{id}/private/answer`（Functions 専用）にある。
 */
export interface ProblemDoc {
  tiles: string[];
  /** ツモ牌（`tiles` の最後）。 */
  tsumo: string;
  /** ツモ牌の添字（常に `tiles.length - 1`。アプリの `HandInput.fromJson` にそのまま渡せる）。 */
  tsumoIndex: number;
  melds: MeldInput[];
  dora: string[];
  seatWind: Wind;
  roundWind: Wind;
  turn: number | null;
  authorUid: string;
  authorNickname: string;
  createdAt: Timestamp;
  locale: 'ja' | 'en';
  stats: Stats;
  featured: { daily: string | null; posted: boolean };
  reports: number;
  hidden: boolean;
  cardPath: string;
  contentKey: string;
}

export const COLLECTIONS = {
  problems: 'problems',
  users: 'users',
  daily: 'daily',
  official: 'official',
  referrals: 'referrals',
  weekly: 'weekly',
  system: '_system',
} as const;

/**
 * Firestore から読んだドキュメントを `ProblemSummary` にする。
 * 正解は別のドキュメントなので、必要なら `loadAnswers` で読んで `answer` に渡す（無ければ空の解）。
 */
export function toSummary(
  id: string,
  data: FirebaseFirestore.DocumentData,
  answer?: Pick<AnswerInput, 'byAxis'> | null,
): ProblemSummary {
  const stats = normalizeStats(data.stats);
  return {
    id,
    authorUid: typeof data.authorUid === 'string' ? data.authorUid : '',
    hidden: data.hidden === true,
    reports: typeof data.reports === 'number' ? data.reports : 0,
    stats: { total: stats.total, correct: stats.correct },
    featuredDaily: typeof data.featured?.daily === 'string' ? data.featured.daily : null,
    posted: data.featured?.posted === true,
    answer: { byAxis: answer?.byAxis ?? { speed: [], points: [], balance: [] } },
  };
}
