/**
 * Firestore / Storage ルールのテスト（エミュレータ）。実行: `npm run test:emulator`
 */
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import type { RulesTestEnvironment } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  collectionGroup,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
} from 'firebase/firestore';
import { deleteObject, getBytes, ref, uploadBytes } from 'firebase/storage';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { PROJECT_ID } from './helpers';

const root = path.resolve(__dirname, '../../..');
let env: RulesTestEnvironment;

function hostPort(value: string | undefined, fallbackPort: number) {
  const [host, port] = (value ?? `127.0.0.1:${fallbackPort}`).split(':');
  return { host, port: Number(port) };
}

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.join(root, 'firestore.rules'), 'utf8'),
      ...hostPort(process.env.FIRESTORE_EMULATOR_HOST, 8080),
    },
    storage: {
      rules: fs.readFileSync(path.join(root, 'storage.rules'), 'utf8'),
      ...hostPort(process.env.FIREBASE_STORAGE_EMULATOR_HOST, 9199),
    },
  });
});

afterAll(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'problems/PUBLIC01'), { hidden: false, authorUid: 'author', tiles: ['1m'] });
    await setDoc(doc(db, 'problems/HIDDEN01'), { hidden: true, authorUid: 'author', tiles: ['1m'] });
    await setDoc(doc(db, 'problems/PUBLIC01/answers/a1'), { tile: '1m', uid: 'u1' });
    await setDoc(doc(db, 'problems/PUBLIC01/reports/r1'), { uid: 'u1' });
    await setDoc(doc(db, 'problems/PUBLIC01/private/answer'), {
      byAxis: { speed: ['1m'], points: ['1m'], balance: ['1m'] },
      ukeire: { kinds: 1, total: 1 },
      shanten: 0,
      engineVersion: 't/1',
    });
    await setDoc(doc(db, 'problems/HIDDEN01/private/answer'), { byAxis: {} });
    await setDoc(doc(db, 'daily/2026-10-21'), { official: 'PUBLIC01', picks: [] });
    await setDoc(doc(db, 'users/u1'), {
      locale: 'ja',
      nickname: 'x',
      referralCode: 'ABCD2345',
      problemCount: 1,
      pro: { active: false, source: null, until: null },
    });
    await setDoc(doc(db, 'users/u2'), { locale: 'ja' });
    await setDoc(doc(db, 'referrals/ABCD2345'), { uid: 'u1', uses: 0 });
    await setDoc(doc(db, 'official/o1'), { problemId: 'PUBLIC01', order: 1, used: false });
    await setDoc(doc(db, 'weekly/2026-10-25'), { top: [] });
    await setDoc(doc(db, '_system/threads'), { accessToken: 'secret' });
  });
});

const anon = () => env.unauthenticatedContext().firestore();
const as = (uid: string) => env.authenticatedContext(uid).firestore();

describe('Firestore ルール: problems', () => {
  test('hidden == false の問題は誰でも（未ログインでも）読める', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'problems/PUBLIC01')));
    await assertSucceeds(getDoc(doc(as('someone'), 'problems/PUBLIC01')));
  });

  test('hidden の問題は他人・未ログインは読めない。出題者本人は読める', async () => {
    await assertFails(getDoc(doc(anon(), 'problems/HIDDEN01')));
    await assertFails(getDoc(doc(as('someone'), 'problems/HIDDEN01')));
    await assertSucceeds(getDoc(doc(as('author'), 'problems/HIDDEN01')));
  });

  test('一覧は where hidden == false が必要。出題者は authorUid で自分の問題を一覧できる', async () => {
    await assertSucceeds(getDocs(query(collection(anon(), 'problems'), where('hidden', '==', false))));
    await assertFails(getDocs(collection(anon(), 'problems')));
    await assertFails(getDocs(query(collection(as('someone'), 'problems'), where('authorUid', '==', 'author'))));
    await assertSucceeds(getDocs(query(collection(as('author'), 'problems'), where('authorUid', '==', 'author'))));
  });

  test('クライアントからは作成・更新・削除できない（出題者本人でも）', async () => {
    await assertFails(setDoc(doc(as('author'), 'problems/NEW00001'), { hidden: false, authorUid: 'author' }));
    await assertFails(updateDoc(doc(as('author'), 'problems/PUBLIC01'), { 'stats.total': 999 }));
    await assertFails(updateDoc(doc(as('author'), 'problems/PUBLIC01'), { hidden: true }));
    await assertFails(deleteDoc(doc(as('author'), 'problems/PUBLIC01')));
    await assertFails(setDoc(doc(anon(), 'problems/NEW00001'), { hidden: false }));
  });

  test('answers と reports は誰も読み書きできない', async () => {
    for (const db of [anon(), as('u1'), as('author')]) {
      await assertFails(getDoc(doc(db, 'problems/PUBLIC01/answers/a1')));
      await assertFails(getDocs(collection(db, 'problems/PUBLIC01/answers')));
      await assertFails(setDoc(doc(db, 'problems/PUBLIC01/answers/a2'), { tile: '1m' }));
      await assertFails(getDoc(doc(db, 'problems/PUBLIC01/reports/r1')));
      await assertFails(setDoc(doc(db, 'problems/PUBLIC01/reports/u1'), { uid: 'u1' }));
    }
  });
});

describe('Firestore ルール: private/answer（正解）', () => {
  test('誰も（未ログイン・他人・出題者本人も）読み書きできない', async () => {
    for (const db of [anon(), as('u1'), as('author')]) {
      await assertFails(getDoc(doc(db, 'problems/PUBLIC01/private/answer')));
      await assertFails(getDocs(collection(db, 'problems/PUBLIC01/private')));
      await assertFails(setDoc(doc(db, 'problems/PUBLIC01/private/answer'), { byAxis: {} }));
      await assertFails(updateDoc(doc(db, 'problems/PUBLIC01/private/answer'), { shanten: 5 }));
      await assertFails(deleteDoc(doc(db, 'problems/PUBLIC01/private/answer')));
      await assertFails(setDoc(doc(db, 'problems/PUBLIC01/private/other'), { x: 1 }));
    }
  });

  test('hidden の問題の private も、出題者本人を含めて読めない', async () => {
    await assertFails(getDoc(doc(as('author'), 'problems/HIDDEN01/private/answer')));
  });

  test('コレクショングループ（private）でも読めない', async () => {
    await assertFails(getDocs(collectionGroup(anon(), 'private')));
    await assertFails(getDocs(collectionGroup(as('author'), 'private')));
  });

  test('公開の問題ドキュメントには answer が無い（問題を読んでも正解は分からない）', async () => {
    const snap = await assertSucceeds(getDoc(doc(anon(), 'problems/PUBLIC01')));
    expect(snap.data()).not.toHaveProperty('answer');
  });
});

describe('Firestore ルール: daily', () => {
  test('誰でも読めるが、書けない', async () => {
    await assertSucceeds(getDoc(doc(anon(), 'daily/2026-10-21')));
    await assertFails(setDoc(doc(as('u1'), 'daily/2026-10-22'), { official: 'x' }));
    await assertFails(updateDoc(doc(as('u1'), 'daily/2026-10-21'), { official: 'x' }));
  });
});

describe('Firestore ルール: users', () => {
  test('本人だけが読める。一覧は不可', async () => {
    await assertSucceeds(getDoc(doc(as('u1'), 'users/u1')));
    await assertFails(getDoc(doc(as('u2'), 'users/u1')));
    await assertFails(getDoc(doc(anon(), 'users/u1')));
    await assertFails(getDocs(collection(as('u1'), 'users')));
  });

  test('作成・削除はできない（ensureUser / deleteMyData だけ）', async () => {
    await assertFails(setDoc(doc(as('u9'), 'users/u9'), { locale: 'ja' }));
    await assertFails(deleteDoc(doc(as('u1'), 'users/u1')));
  });

  test('端末設定（fcmTokens・notify・streak・locale）は本人が更新できる', async () => {
    const ref = doc(as('u1'), 'users/u1');
    await assertSucceeds(updateDoc(ref, { fcmTokens: ['t1', 't2'] }));
    await assertSucceeds(updateDoc(ref, { notify: { daily: true, weekly: false, milestone: true } }));
    await assertSucceeds(updateDoc(ref, { streak: { current: 3, best: 5, lastAnsweredDate: '2026-10-21' } }));
    await assertSucceeds(updateDoc(ref, { locale: 'en' }));
    await assertFails(updateDoc(doc(as('u2'), 'users/u1'), { locale: 'en' }));
  });

  test('Pro・紹介・ニックネーム・上限カウンタは自分で書けない', async () => {
    const ref = doc(as('u1'), 'users/u1');
    await assertFails(updateDoc(ref, { 'pro.active': true }));
    await assertFails(updateDoc(ref, { pro: { active: true, source: 'revenuecat', until: null } }));
    await assertFails(updateDoc(ref, { referralCode: 'ZZZZ2222' }));
    await assertFails(updateDoc(ref, { referredBy: 'ABCD2345' }));
    await assertFails(updateDoc(ref, { nickname: 'うんえい' }));
    await assertFails(updateDoc(ref, { problemCount: 0 }));
    await assertFails(updateDoc(ref, { publishQuota: { date: '2026-10-21', count: 0 } }));
    // 許可された項目と混ぜても、禁止項目が入っていれば拒否
    await assertFails(updateDoc(ref, { locale: 'en', 'pro.active': true }));
  });

  test('値の検査: locale は ja|en、fcmTokens は 10 個まで、notify・streak は map', async () => {
    const ref = doc(as('u1'), 'users/u1');
    await assertFails(updateDoc(ref, { locale: 'fr' }));
    await assertSucceeds(updateDoc(ref, { fcmTokens: Array.from({ length: 10 }, (_, i) => `t${i}`) }));
    await assertFails(updateDoc(ref, { fcmTokens: Array.from({ length: 11 }, (_, i) => `t${i}`) }));
    await assertFails(updateDoc(ref, { fcmTokens: 'not-a-list' }));
    await assertFails(updateDoc(ref, { notify: true }));
    await assertFails(updateDoc(ref, { streak: 3 }));
  });
});

describe('Firestore ルール: サーバー専用のコレクション', () => {
  test('referrals / official / weekly / _system は誰も読み書きできない', async () => {
    for (const p of ['referrals/ABCD2345', 'official/o1', 'weekly/2026-10-25', '_system/threads']) {
      await assertFails(getDoc(doc(as('u1'), p)));
      await assertFails(getDoc(doc(anon(), p)));
      await assertFails(setDoc(doc(as('u1'), p), { x: 1 }));
    }
  });

  test('未定義のコレクションも拒否（デフォルト拒否）', async () => {
    await assertFails(getDoc(doc(as('u1'), 'anything/else')));
    await assertFails(setDoc(doc(as('u1'), 'anything/else'), { x: 1 }));
  });
});

describe('Storage ルール: cards', () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
  const storageOf = (uid: string | null) =>
    (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();
  const png1x1 = (problemId: string, file = '1x1.png') => `cards/${problemId}/${file}`;
  const meta = { contentType: 'image/png' };

  test('出題者本人は自分の問題のカードをアップロードできる（作り直しも可）', async () => {
    const r = ref(storageOf('author'), png1x1('PUBLIC01'));
    await assertSucceeds(uploadBytes(r, png, meta));
    await assertSucceeds(uploadBytes(r, png, meta));
  });

  test('他人・未ログインは、他人の問題のカードを書けない', async () => {
    await assertFails(uploadBytes(ref(storageOf('someone'), png1x1('PUBLIC01')), png, meta));
    await assertFails(uploadBytes(ref(storageOf(null), png1x1('PUBLIC01')), png, meta));
  });

  test('存在しない問題（publishProblem 前）のカードは書けない', async () => {
    await assertFails(uploadBytes(ref(storageOf('author'), png1x1('NOPROBLEM')), png, meta));
  });

  test('ファイル名は 1x1.png のみ、PNG のみ、900KB まで', async () => {
    const s = storageOf('author');
    await assertFails(uploadBytes(ref(s, png1x1('PUBLIC01', 'other.png')), png, meta));
    await assertFails(uploadBytes(ref(s, png1x1('PUBLIC01')), png, { contentType: 'image/jpeg' }));
    await assertFails(uploadBytes(ref(s, png1x1('PUBLIC01')), new Uint8Array(900 * 1024 + 1), meta));
    await assertSucceeds(uploadBytes(ref(s, png1x1('PUBLIC01')), new Uint8Array(900 * 1024), meta));
  });

  test('読み取りは誰でも。削除はクライアントからはできない', async () => {
    await assertSucceeds(uploadBytes(ref(storageOf('author'), png1x1('PUBLIC01')), png, meta));
    await assertSucceeds(getBytes(ref(storageOf(null), png1x1('PUBLIC01'))));
    await assertFails(deleteObject(ref(storageOf('author'), png1x1('PUBLIC01'))));
  });

  test('cards 以外のパスは読み書きできない', async () => {
    await assertFails(uploadBytes(ref(storageOf('author'), 'misc/a.png'), png, meta));
    await assertFails(getBytes(ref(storageOf('author'), 'misc/a.png')));
  });
});
