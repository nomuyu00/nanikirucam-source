import { Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { jstDate } from '../lib/dates';
import { DEFAULT_PICK_OPTIONS, isPickEligible, selectUserPicks } from '../lib/daily';
import type { PickOptions } from '../lib/daily';
import { loadAnswers } from './privateAnswer';
import { COLLECTIONS, toSummary } from './types';

export interface PickDailyResult {
  date: string;
  skipped: boolean;
  official: string | null;
  picks: string[];
}

/** 公式の出題待ち（`official` コレクション）から、公開中の最初の 1 問を探す。 */
async function findOfficial(
  db: Firestore,
): Promise<{ problemId: string; queueRef: FirebaseFirestore.DocumentReference } | null> {
  const queue = await db
    .collection(COLLECTIONS.official)
    .where('used', '==', false)
    .orderBy('order')
    .limit(20)
    .get();
  for (const doc of queue.docs) {
    const problemId = typeof doc.get('problemId') === 'string' ? doc.get('problemId') : doc.id;
    const problem = await db.collection(COLLECTIONS.problems).doc(problemId).get();
    if (problem.exists && problem.get('hidden') !== true) return { problemId, queueRef: doc.ref };
    logger.warn(`official ${doc.id}: problem ${problemId} is missing or hidden; skipped`);
  }
  return null;
}

/**
 * 今日の問題の選出（`pickDaily` の本体）。
 * 公式 1 問 + ユーザー投稿 2 問（回答 20 以上、正解率 40〜60%、通報 0、直近 30 日未選出）を
 * `daily/{date}` に書く。すでにあれば何もしない（再実行しても二重に選ばない）。
 */
export async function pickDailyCore(db: Firestore, now: Date = new Date()): Promise<PickDailyResult> {
  const date = jstDate(now);
  const dailyRef = db.collection(COLLECTIONS.daily).doc(date);
  if ((await dailyRef.get()).exists) {
    return { date, skipped: true, official: null, picks: [] };
  }

  const official = await findOfficial(db);

  // 候補: 公開中で回答数の多い順に上位 200 件
  const candidates = await db
    .collection(COLLECTIONS.problems)
    .where('hidden', '==', false)
    .where('stats.total', '>=', DEFAULT_PICK_OPTIONS.minAnswers)
    .orderBy('stats.total', 'desc')
    .limit(200)
    .get();
  const pickOptions: PickOptions = {
    today: date,
    ...DEFAULT_PICK_OPTIONS,
    excludeIds: official ? [official.problemId] : [],
  };
  // 条件を満たす問題だけ、3 軸が割れているかの判定用に正解（private/answer）を読む
  const eligible = candidates.docs
    .map((d) => toSummary(d.id, d.data()))
    .filter((p) => isPickEligible(p, pickOptions));
  const answers = await loadAnswers(
    db,
    eligible.map((p) => p.id),
  );
  const picks = selectUserPicks(
    eligible.map((p) => ({ ...p, answer: answers.get(p.id) ?? p.answer })),
    pickOptions,
  );

  const batch = db.batch();
  batch.create(dailyRef, {
    official: official?.problemId ?? null,
    picks: picks.map((p) => p.id),
    generatedAt: Timestamp.fromDate(now),
  });
  if (official) {
    batch.update(db.collection(COLLECTIONS.problems).doc(official.problemId), {
      'featured.daily': date,
    });
    batch.update(official.queueRef, { used: true, usedDate: date });
  }
  for (const p of picks) {
    batch.update(db.collection(COLLECTIONS.problems).doc(p.id), { 'featured.daily': date });
  }
  await batch.commit();

  return {
    date,
    skipped: false,
    official: official?.problemId ?? null,
    picks: picks.map((p) => p.id),
  };
}
