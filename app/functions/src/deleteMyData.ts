import './globals';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { ENFORCE_APP_CHECK } from './config';
import { deleteMyDataCore } from './core/deleteMyData';
import { deleteCards } from './storage';

/**
 * データ削除（callable、設計書 14 章）。呼んだ本人の users・紹介コード・回答/通報の記録を消し、
 * 出題した問題は非公開にして作者名を消し、カード画像を削除し、最後に Auth アカウントも削除する。
 * 成功後、クライアントはサインアウトして新しい匿名アカウントで始め直す。
 */
export const deleteMyData = onCall(
  { enforceAppCheck: ENFORCE_APP_CHECK, timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'sign in first', { reason: 'unauthenticated' });
    }
    const result = await deleteMyDataCore(
      {
        db: getFirestore(),
        deleteCards,
        deleteAuthUser: async (uid) => {
          try {
            await getAuth().deleteUser(uid);
          } catch (err) {
            if ((err as { code?: string }).code !== 'auth/user-not-found') throw err;
          }
        },
      },
      request.auth.uid,
    );
    return { deleted: true, ...result };
  },
);
