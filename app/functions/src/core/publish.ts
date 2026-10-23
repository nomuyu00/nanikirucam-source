import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { consumePublishQuota, contentKey, DAILY_PUBLISH_LIMIT } from '../lib/contentKey';
import { jstDate } from '../lib/dates';
import { generateProblemId } from '../lib/problemId';
import { emptyStats } from '../lib/stats';
import { cardPathFor, problemUrl } from '../lib/storeLinks';
import type { ProblemInput } from '../lib/validate';
import { privateAnswerRef } from './privateAnswer';
import { ensureUser } from './users';
import { COLLECTIONS } from './types';
import type { ProblemDoc } from './types';

export class DailyLimitError extends Error {
  constructor(
    public readonly limit: number,
    public readonly used: number,
  ) {
    super(`daily publish limit reached (${used}/${limit})`);
    this.name = 'DailyLimitError';
  }
}

export interface PublishResult {
  problemId: string;
  /** 同じ牌列の公開済み問題があったとき true（新規作成はしない）。 */
  existing: boolean;
  url: string;
  /** カード PNG のアップロード先（Storage のパス）。他人の既存問題を返すときは null。 */
  cardUploadPath: string | null;
}

export interface PublishDeps {
  db: Firestore;
  siteUrl: string;
  now?: () => Date;
  newId?: () => string;
  dailyLimit?: number;
}

class IdCollision extends Error {}

/**
 * 問題の公開（`publishProblem` の本体）。
 * 同一牌列の公開済み問題があればそれを返し、なければ 1 日の上限を確認して作成する。
 */
export async function publishProblemCore(
  deps: PublishDeps,
  uid: string,
  input: ProblemInput,
): Promise<PublishResult> {
  const { db, siteUrl } = deps;
  const now = deps.now ?? (() => new Date());
  const newId = deps.newId ?? generateProblemId;
  const limit = deps.dailyLimit ?? DAILY_PUBLISH_LIMIT;
  const key = contentKey(input);

  // 重複: 同じ内容で hidden でない問題があれば、それを返す（上限も消費しない）
  const dup = await db
    .collection(COLLECTIONS.problems)
    .where('contentKey', '==', key)
    .where('hidden', '==', false)
    .limit(1)
    .get();
  if (!dup.empty) {
    const doc = dup.docs[0];
    const mine = doc.get('authorUid') === uid;
    return {
      problemId: doc.id,
      existing: true,
      url: problemUrl(siteUrl, doc.id),
      cardUploadPath: mine ? cardPathFor(doc.id) : null,
    };
  }

  await ensureUser(db, uid, input.locale, now());
  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  const today = jstDate(now());

  for (let attempt = 0; attempt < 5; attempt++) {
    const problemId = newId();
    const problemRef = db.collection(COLLECTIONS.problems).doc(problemId);
    try {
      await db.runTransaction(async (tx) => {
        const [problemSnap, userSnap] = await Promise.all([tx.get(problemRef), tx.get(userRef)]);
        if (problemSnap.exists) throw new IdCollision();

        const quota = consumePublishQuota(userSnap.get('publishQuota'), today, limit);
        if (!quota.ok) throw new DailyLimitError(limit, quota.used);

        const storedNickname = userSnap.get('nickname');
        const authorNickname =
          input.nickname ?? (typeof storedNickname === 'string' ? storedNickname : '');

        const doc: ProblemDoc = {
          tiles: input.tiles,
          tsumo: input.tiles[input.tiles.length - 1],
          tsumoIndex: input.tiles.length - 1,
          melds: input.melds,
          dora: input.dora,
          seatWind: input.seatWind,
          roundWind: input.roundWind,
          turn: input.turn,
          authorUid: uid,
          authorNickname,
          createdAt: Timestamp.fromDate(now()),
          locale: input.locale,
          stats: emptyStats(),
          featured: { daily: null, posted: false },
          reports: 0,
          hidden: false,
          cardPath: cardPathFor(problemId),
          contentKey: key,
        };
        tx.create(problemRef, doc);
        // 正解は公開ドキュメントとは別の、Functions 専用ドキュメントに置く
        tx.create(privateAnswerRef(db, problemId), input.answer);
        tx.set(
          userRef,
          {
            publishQuota: quota.next,
            problemCount: FieldValue.increment(1),
            // ニックネームを送ってきたときは、次回以降の既定として覚える
            ...(input.nickname ? { nickname: input.nickname } : {}),
          },
          { merge: true },
        );
      });
      return {
        problemId,
        existing: false,
        url: problemUrl(siteUrl, problemId),
        cardUploadPath: cardPathFor(problemId),
      };
    } catch (err) {
      if (err instanceof IdCollision) continue;
      throw err;
    }
  }
  throw new Error('could not allocate a unique problem id');
}
