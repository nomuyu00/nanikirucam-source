import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { REPORT_HIDE_THRESHOLD, REPORTER_MIN_ACCOUNT_AGE_MS } from '../config';
import { isReporterEligible } from '../lib/reporters';
import { COLLECTIONS } from './types';

export const REPORT_REASONS = ['spam', 'offensive', 'wrong_answer', 'other'] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

export type ReportOutcome =
  | { kind: 'not_found' }
  | { kind: 'own_problem' }
  | {
      kind: 'reported';
      alreadyReported: boolean;
      /** この通報が `reports` に数えられたか（アカウントが新しい・users が無いと false）。 */
      counted: boolean;
      hidden: boolean;
      reports: number;
    };

/**
 * 通報の記録（`reportProblem` の本体）。同じ uid の通報は 1 件として数える。
 * 作成から `REPORTER_MIN_ACCOUNT_AGE_MS`（24 時間）未満の uid、または `users/{uid}` が無い uid の
 * 通報は、記録（`reports/{uid}` に `counted: false`）だけして `reports` には加算しない
 * （匿名アカウントを量産して問題を非表示にする荒らしの対策）。
 */
export async function reportProblemCore(
  db: Firestore,
  uid: string,
  problemId: string,
  reason: ReportReason,
  now: Date = new Date(),
): Promise<ReportOutcome> {
  const problemRef = db.collection(COLLECTIONS.problems).doc(problemId);
  const reportRef = problemRef.collection('reports').doc(uid);
  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  return db.runTransaction(async (tx): Promise<ReportOutcome> => {
    const [problemSnap, reportSnap, userSnap] = await Promise.all([
      tx.get(problemRef),
      tx.get(reportRef),
      tx.get(userRef),
    ]);
    if (!problemSnap.exists) return { kind: 'not_found' };
    if (problemSnap.get('authorUid') === uid) return { kind: 'own_problem' };
    const reports = Number(problemSnap.get('reports') ?? 0);
    const hidden = problemSnap.get('hidden') === true;
    if (reportSnap.exists) {
      return { kind: 'reported', alreadyReported: true, counted: reportSnap.get('counted') === true, hidden, reports };
    }

    const createdAt = userSnap.exists ? userSnap.get('createdAt') : null;
    const counted = isReporterEligible(
      createdAt instanceof Timestamp ? createdAt.toMillis() : null,
      now.getTime(),
      REPORTER_MIN_ACCOUNT_AGE_MS,
    );
    tx.create(reportRef, { uid, reason, counted, createdAt: Timestamp.fromDate(now) });
    if (!counted) {
      return { kind: 'reported', alreadyReported: false, counted: false, hidden, reports };
    }
    const next = reports + 1;
    const nowHidden = hidden || next >= REPORT_HIDE_THRESHOLD;
    tx.update(problemRef, { reports: FieldValue.increment(1), hidden: nowHidden });
    return { kind: 'reported', alreadyReported: false, counted: true, hidden: nowHidden, reports: next };
  });
}
