import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { ENFORCE_APP_CHECK } from './config';
import { REPORT_REASONS, reportProblemCore } from './core/report';
import type { ReportReason } from './core/report';
import { isProblemId } from './lib/problemId';

/**
 * 問題の通報（callable）。同じ uid の通報は 1 件として数え、3 件で `hidden = true`。
 * 自分の問題は通報できない。
 */
export const reportProblem = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'sign in (anonymous auth) first', {
      reason: 'unauthenticated',
    });
  }
  const problemId = request.data?.problemId;
  if (!isProblemId(problemId)) {
    throw new HttpsError('invalid-argument', 'problemId is invalid', { reason: 'invalid_problem_id' });
  }
  const reasonRaw = request.data?.reason ?? 'other';
  if (!(REPORT_REASONS as readonly unknown[]).includes(reasonRaw)) {
    throw new HttpsError('invalid-argument', `reason must be one of ${REPORT_REASONS.join('|')}`, {
      reason: 'invalid_reason',
    });
  }
  const outcome = await reportProblemCore(
    getFirestore(),
    request.auth.uid,
    problemId,
    reasonRaw as ReportReason,
  );
  switch (outcome.kind) {
    case 'not_found':
      throw new HttpsError('not-found', 'problem not found', { reason: 'not_found' });
    case 'own_problem':
      throw new HttpsError('permission-denied', 'cannot report your own problem', {
        reason: 'own_problem',
      });
    case 'reported':
      return { reported: true, alreadyReported: outcome.alreadyReported, hidden: outcome.hidden };
  }
});
