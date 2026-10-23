import { Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import {
  applyAnswerToStats,
  fingerprintHash,
  judgeAnswer,
  milestoneReached,
  normalizeStats,
} from '../lib/stats';
import type { AxisJudgement, Stats } from '../lib/stats';
import type { AnswerInput } from '../lib/validate';
import { privateAnswerRef } from './privateAnswer';
import { COLLECTIONS } from './types';

export interface AnswerRequest {
  problemId: string;
  tile: string;
  source: 'web' | 'app';
  /** Web: 端末ごとのランダム ID。アプリ: Firebase uid。 */
  fingerprintRaw: string;
  uid: string | null;
  selfRank: number | null;
}

export type AnswerOutcome =
  | { kind: 'not_found' }
  | { kind: 'invalid_tile' }
  | {
      kind: 'ok';
      alreadyAnswered: boolean;
      yourTile: string;
      judgement: AxisJudgement;
      /** バランス軸の解と一致したか（`stats.correct` に数える基準）。 */
      correct: boolean;
      stats: Stats;
      answer: AnswerInput;
      /** この回答で節目（10/50/100）に到達したとき、出題者へ通知する情報。 */
      milestone: { authorUid: string; count: number; problemId: string } | null;
    };

/**
 * 回答の記録と `stats` の更新（`answerProblem` の本体）。
 * 回答ドキュメント ID は fingerprint のハッシュなので、同じ端末・同じ uid の二重回答は
 * トランザクション内の存在確認で弾ける（集計は増えない）。
 */
export async function answerProblemCore(
  db: Firestore,
  req: AnswerRequest,
  now: Date = new Date(),
): Promise<AnswerOutcome> {
  const problemRef = db.collection(COLLECTIONS.problems).doc(req.problemId);
  const fp = fingerprintHash(req.source, req.fingerprintRaw);
  const answerRef = problemRef.collection('answers').doc(fp);

  return db.runTransaction(async (tx): Promise<AnswerOutcome> => {
    const [problemSnap, answerSnap, privateSnap] = await Promise.all([
      tx.get(problemRef),
      tx.get(answerRef),
      tx.get(privateAnswerRef(db, req.problemId)),
    ]);
    if (!problemSnap.exists || problemSnap.get('hidden') === true) return { kind: 'not_found' };
    // 正解は公開ドキュメントではなく private/answer にある（無いのは書き込みの不整合）
    if (!privateSnap.exists) throw new Error(`problems/${req.problemId}/private/answer is missing`);

    const tiles: string[] = problemSnap.get('tiles') ?? [];
    const answer = privateSnap.data() as AnswerInput;
    const stats = normalizeStats(problemSnap.get('stats'));

    if (answerSnap.exists) {
      const prevTile = String(answerSnap.get('tile'));
      const judgement = judgeAnswer(answer, prevTile);
      return {
        kind: 'ok',
        alreadyAnswered: true,
        yourTile: prevTile,
        judgement,
        correct: judgement.balance,
        stats,
        answer,
        milestone: null,
      };
    }

    // 選べるのは手牌（副露を除く）にある牌だけ
    if (!tiles.includes(req.tile)) return { kind: 'invalid_tile' };

    const judgement = judgeAnswer(answer, req.tile);
    const correct = judgement.balance;
    const next = applyAnswerToStats(stats, req.tile, correct);

    tx.create(answerRef, {
      tile: req.tile,
      source: req.source,
      fingerprint: fp,
      uid: req.uid,
      createdAt: Timestamp.fromDate(now),
      selfRank: req.selfRank,
    });
    tx.update(problemRef, { stats: next });

    const count = milestoneReached(stats.total, next.total);
    const authorUid = problemSnap.get('authorUid');
    return {
      kind: 'ok',
      alreadyAnswered: false,
      yourTile: req.tile,
      judgement,
      correct,
      stats: next,
      answer,
      milestone:
        count !== null && typeof authorUid === 'string' && authorUid !== 'deleted'
          ? { authorUid, count, problemId: req.problemId }
          : null,
    };
  });
}
