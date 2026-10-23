import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { ENFORCE_APP_CHECK } from './config';
import { applyReferralCore } from './core/referral';
import { ensureUser } from './core/users';
import { normalizeReferralCode } from './lib/referral';

/**
 * 紹介コードの適用（callable）。両者に Pro 7 日（`users.pro.source = 'referral'`）。
 * 1 人 1 回。自分のコードは使えない。入力は大文字小文字・空白・ハイフンのゆれを許す。
 */
export const applyReferral = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'sign in (anonymous auth) first', {
      reason: 'unauthenticated',
    });
  }
  const code = normalizeReferralCode(request.data?.code);
  if (!code) {
    throw new HttpsError('invalid-argument', 'invalid referral code format', {
      reason: 'invalid_code',
    });
  }
  const db = getFirestore();
  const now = new Date();
  await ensureUser(db, request.auth.uid, 'ja', now);
  const outcome = await applyReferralCore(db, request.auth.uid, code, now);
  switch (outcome.kind) {
    case 'invalid_code':
      throw new HttpsError('not-found', 'referral code not found', { reason: 'invalid_code' });
    case 'no_user':
      throw new HttpsError('failed-precondition', 'user not initialized', { reason: 'no_user' });
    case 'already_applied':
      throw new HttpsError('already-exists', 'a referral code was already applied', {
        reason: 'already_applied',
      });
    case 'self_referral':
      throw new HttpsError('failed-precondition', 'cannot use your own code', {
        reason: 'self_referral',
      });
    case 'applied':
      return {
        applied: true,
        proUntil: new Date(outcome.proUntilMs).toISOString(),
        referrerRewarded: outcome.referrerRewarded,
      };
  }
});
