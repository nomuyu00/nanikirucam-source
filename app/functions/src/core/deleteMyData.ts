import type { Firestore } from 'firebase-admin/firestore';
import { COLLECTIONS } from './types';

/** 削除済みユーザーの出題に付ける作者 ID（本人の uid との紐付けを切る）。 */
export const DELETED_AUTHOR = 'deleted';

export interface DeleteDeps {
  db: Firestore;
  /** Storage の `cards/{problemId}/` 以下を削除する。 */
  deleteCards: (problemId: string) => Promise<void>;
  /** Firebase Auth のユーザーを削除する（存在しなければ何もしない）。 */
  deleteAuthUser: (uid: string) => Promise<void>;
}

export interface DeleteResult {
  problems: number;
  answers: number;
  reports: number;
}

async function deleteInChunks(
  db: Firestore,
  refs: FirebaseFirestore.DocumentReference[],
): Promise<void> {
  for (let i = 0; i < refs.length; i += 400) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + 400)) batch.delete(ref);
    await batch.commit();
  }
}

/**
 * データ削除（`deleteMyData` の本体、設計書 14 章）。
 * - 本人の問題は `hidden` にして作者名と uid を消す（他の人の回答統計は壊さない）。カード画像は削除。
 * - 本人の回答・通報の記録、紹介コード、`users/{uid}` を削除。
 * - 最後に Firebase Auth のユーザーを削除する。
 * 集計済みの `stats`（匿名の合計）には本人の回答が数字として残る。
 */
export async function deleteMyDataCore(deps: DeleteDeps, uid: string): Promise<DeleteResult> {
  const { db } = deps;

  // 1. 本人の問題を非公開にして作者情報を消す
  const problems = await db.collection(COLLECTIONS.problems).where('authorUid', '==', uid).get();
  for (let i = 0; i < problems.docs.length; i += 400) {
    const batch = db.batch();
    for (const doc of problems.docs.slice(i, i + 400)) {
      batch.update(doc.ref, { hidden: true, authorNickname: '', authorUid: DELETED_AUTHOR });
    }
    await batch.commit();
  }
  for (const doc of problems.docs) await deps.deleteCards(doc.id);

  // 2. 本人の回答・通報の記録
  const answers = await db.collectionGroup('answers').where('uid', '==', uid).get();
  await deleteInChunks(
    db,
    answers.docs.map((d) => d.ref),
  );
  const reports = await db.collectionGroup('reports').where('uid', '==', uid).get();
  await deleteInChunks(
    db,
    reports.docs.map((d) => d.ref),
  );

  // 3. 紹介コードと users ドキュメント（サブコレクションごと）
  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  const userSnap = await userRef.get();
  const code = userSnap.get('referralCode');
  if (typeof code === 'string') {
    await db.collection(COLLECTIONS.referrals).doc(code).delete();
  }
  await db.recursiveDelete(userRef);

  // 4. Auth アカウント
  await deps.deleteAuthUser(uid);

  return { problems: problems.size, answers: answers.size, reports: reports.size };
}
