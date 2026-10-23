import type { DocumentReference, Firestore } from 'firebase-admin/firestore';
import type { AnswerInput } from '../lib/validate';
import { COLLECTIONS } from './types';

/**
 * 問題の正解（3 軸の解・受け入れ・シャンテン・engineVersion）は、公開ドキュメント
 * `problems/{id}` には置かず、サブコレクション `problems/{id}/private/answer` に保存する。
 * Firestore ルールでクライアントからの読み書きをすべて拒否し、Functions（Admin SDK）だけが扱う。
 * これにより、問題を直接読んでも正解は分からない。回答後は `answerProblem` のレスポンスで返す。
 */
export function privateAnswerRef(db: Firestore, problemId: string): DocumentReference {
  return db.collection(COLLECTIONS.problems).doc(problemId).collection('private').doc('answer');
}

/** 複数の問題の正解をまとめて読む。ドキュメントが無い問題はマップに入らない。 */
export async function loadAnswers(
  db: Firestore,
  problemIds: readonly string[],
): Promise<Map<string, AnswerInput>> {
  const result = new Map<string, AnswerInput>();
  if (problemIds.length === 0) return result;
  const snaps = await db.getAll(...problemIds.map((id) => privateAnswerRef(db, id)));
  snaps.forEach((snap, i) => {
    if (snap.exists) result.set(problemIds[i], snap.data() as AnswerInput);
  });
  return result;
}
