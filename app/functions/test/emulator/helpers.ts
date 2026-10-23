import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { Timestamp } from 'firebase-admin/firestore';

export const PROJECT_ID = 'demo-nanikiru-cam';

/** エミュレータ（FIRESTORE_EMULATOR_HOST）に繋いだ Admin Firestore。 */
export function adminDb(): Firestore {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('FIRESTORE_EMULATOR_HOST is not set. Run via `npm run test:emulator`.');
  }
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  return getFirestore();
}

/** エミュレータの全ドキュメントを消す。 */
export async function clearFirestore(): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST as string;
  const res = await fetch(
    `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  if (!res.ok) throw new Error(`failed to clear Firestore: ${res.status}`);
}

/** 公開済みの問題ドキュメントを直接作る（`publishProblemCore` を通さないテスト用）。 */
export const DEFAULT_ANSWER = {
  byAxis: { speed: ['9p'], points: ['5m'], balance: ['9p'] },
  ukeire: { kinds: 8, total: 24 },
  shanten: 1,
  engineVersion: 'test/1',
};

/**
 * 公開済みの問題ドキュメントを直接作る（`publishProblemCore` を通さないテスト用）。
 * `patch.answer` は公開ドキュメントではなく `problems/{id}/private/answer` に書く。
 */
export async function seedProblem(
  db: Firestore,
  id: string,
  patch: Record<string, unknown> = {},
): Promise<void> {
  const { answer, ...rest } = patch;
  await db
    .collection('problems')
    .doc(id)
    .collection('private')
    .doc('answer')
    .set((answer as Record<string, unknown> | undefined) ?? DEFAULT_ANSWER);
  await db.collection('problems').doc(id).set({
    tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '9p'],
    tsumo: '9p',
    melds: [],
    dora: ['3z'],
    seatWind: 'south',
    roundWind: 'east',
    turn: 6,
    authorUid: 'author-1',
    authorNickname: 'まじゃおう',
    createdAt: Timestamp.fromDate(new Date('2026-10-01T00:00:00Z')),
    locale: 'ja',
    stats: { total: 0, byTile: {}, correct: 0 },
    featured: { daily: null, posted: false },
    reports: 0,
    hidden: false,
    cardPath: `cards/${id}/1x1.png`,
    contentKey: `key-${id}`,
    ...rest,
  });
}

/** `users/{uid}` を直接作る（通報の「アカウントの古さ」判定用など）。 */
export async function seedUser(db: Firestore, uid: string, createdAt: Date): Promise<void> {
  await db.collection('users').doc(uid).set({ createdAt: Timestamp.fromDate(createdAt), locale: 'ja' });
}
