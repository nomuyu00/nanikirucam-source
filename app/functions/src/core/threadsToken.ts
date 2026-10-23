import { Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { refreshThreadsToken } from '../lib/adapters/threads';
import type { FetchLike } from '../lib/adapters/types';
import { COLLECTIONS } from './types';

const REFRESH_AFTER_MS = 30 * 24 * 60 * 60 * 1000;

/**
 * Threads の長期アクセストークンは 60 日で失効するため、30 日ごとに更新して
 * `_system/threads`（Functions からのみアクセス可能）に保存する。
 * 保存済みのトークンがあればそれを使い、なければ Secret の初期値を使う。
 */
export async function resolveThreadsToken(
  db: Firestore,
  secretToken: string,
  now: Date = new Date(),
  fetchFn?: FetchLike,
): Promise<string> {
  const ref = db.collection(COLLECTIONS.system).doc('threads');
  const snap = await ref.get();
  const stored = snap.exists && typeof snap.get('accessToken') === 'string' ? snap.get('accessToken') : null;
  const refreshedAt = snap.exists && snap.get('refreshedAt') instanceof Timestamp
    ? (snap.get('refreshedAt') as Timestamp).toMillis()
    : 0;
  const token: string = stored ?? secretToken;
  if (now.getTime() - refreshedAt < REFRESH_AFTER_MS) return token;
  try {
    const refreshed = await refreshThreadsToken(token, fetchFn);
    await ref.set({ accessToken: refreshed.accessToken, refreshedAt: Timestamp.fromDate(now) });
    return refreshed.accessToken;
  } catch (err) {
    logger.error('Threads token refresh failed; using the current token', err);
    return token;
  }
}
