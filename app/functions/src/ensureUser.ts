import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { ENFORCE_APP_CHECK } from './config';
import { ensureUser as ensureUserCore } from './core/users';

/**
 * ユーザードキュメントと紹介コードの用意（callable）。起動時に呼ぶ。何度呼んでもよい。
 * クライアントは `users/{uid}` を自分で作れない（Firestore ルール）ので、必ずこれを先に呼ぶ。
 * `locale` は `ja|en`（省略時 ja）。
 */
export const ensureUser = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'sign in (anonymous auth) first', {
      reason: 'unauthenticated',
    });
  }
  const locale = request.data?.locale === 'en' ? 'en' : 'ja';
  const user = await ensureUserCore(getFirestore(), request.auth.uid, locale, new Date());
  return {
    referralCode: user.referralCode,
    nickname: user.nickname,
    pro: {
      active: user.pro.active,
      source: user.pro.source,
      until: user.pro.untilMs === null ? null : new Date(user.pro.untilMs).toISOString(),
    },
    created: user.created,
  };
});
