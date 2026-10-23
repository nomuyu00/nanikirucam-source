import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { DailyLimitError, publishProblemCore } from './core/publish';
import type { PublishResult } from './core/publish';
import { ENFORCE_APP_CHECK, SITE_URL } from './config';
import { parseProblemInput, ValidationError } from './lib/validate';

/**
 * 何切る問題の公開（callable）。匿名認証でよい。
 * 牌列の検証・NG ワード・1 日 20 問の制限・重複判定を行い、`problems/{id}` を作る。
 * クライアントは返ってきた `cardUploadPath` にカード PNG（1080x1080）を Storage SDK で置く。
 */
export const publishProblem = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK },
  async (request): Promise<PublishResult> => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'sign in (anonymous auth) first', {
        reason: 'unauthenticated',
      });
    }
    let input;
    try {
      input = parseProblemInput(request.data);
    } catch (err) {
      if (err instanceof ValidationError) {
        throw new HttpsError('invalid-argument', err.message, {
          reason: err.reason,
          field: err.field ?? null,
        });
      }
      throw err;
    }
    try {
      return await publishProblemCore(
        { db: getFirestore(), siteUrl: SITE_URL.value() },
        request.auth.uid,
        input,
      );
    } catch (err) {
      if (err instanceof DailyLimitError) {
        throw new HttpsError('resource-exhausted', err.message, {
          reason: 'daily_limit',
          limit: err.limit,
          used: err.used,
        });
      }
      throw err;
    }
  },
);
