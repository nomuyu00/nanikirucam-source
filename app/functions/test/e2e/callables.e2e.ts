/**
 * Functions エミュレータ（Auth・Firestore・Storage 込み）を使った、callable / HTTPS の通しテスト。
 * 匿名ユーザーを作り、実際に関数を呼ぶ。実行: `npm run test:e2e`（先にビルドされる）
 */
import { getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';

const PROJECT_ID = 'demo-nanikiru-cam';
const FN = `http://127.0.0.1:5001/${PROJECT_ID}/asia-northeast1`;
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099';

if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
const db = getFirestore();

interface TestUser {
  uid: string;
  token: string;
}

async function signUp(): Promise<TestUser> {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const json = (await res.json()) as { localId: string; idToken: string };
  return { uid: json.localId, token: json.idToken };
}

async function callable(name: string, token: string | null, data: unknown) {
  const res = await fetch(`${FN}/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ data }),
  });
  return (await res.json()) as { result?: any; error?: { status: string; details?: any } };
}

async function answer(body: unknown, token?: string) {
  const res = await fetch(`${FN}/answerProblem`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body),
  });
  return { status: res.status, body: (await res.json()) as any };
}

const request = (extra: Record<string, unknown> = {}) => ({
  tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '9p'],
  tsumoIndex: 13,
  melds: [],
  dora: ['3z'],
  seatWind: 'south',
  roundWind: 'east',
  turn: 6,
  nickname: 'まじゃおう',
  locale: 'ja',
  answer: {
    byAxis: { speed: ['9p'], points: ['9p', '5m'], balance: ['9p'] },
    ukeire: { kinds: 8, total: 24 },
    shanten: 1,
    engineVersion: 'nanikiru-engine/0.1.0',
  },
  ...extra,
});

let a: TestUser;
let b: TestUser;
let c: TestUser;
let d: TestUser;
let codeA: string;
let problemId: string;

beforeAll(async () => {
  [a, b, c, d] = await Promise.all([signUp(), signUp(), signUp(), signUp()]);
});

describe('ensureUser / publishProblem', () => {
  test('未ログインは UNAUTHENTICATED', async () => {
    const r = await callable('publishProblem', null, request());
    expect(r.error?.status).toBe('UNAUTHENTICATED');
  });

  test('ensureUser は紹介コードを返し、何度呼んでも同じ', async () => {
    const first = await callable('ensureUser', a.token, { locale: 'ja' });
    expect(first.result.referralCode).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    expect(first.result.pro).toEqual({ active: false, source: null, until: null });
    codeA = first.result.referralCode;
    const again = await callable('ensureUser', a.token, { locale: 'en' });
    expect(again.result).toMatchObject({ referralCode: codeA, created: false });
  });

  test('公開 → 重複は既存の ID → 他人には cardUploadPath が null', async () => {
    const r = await callable('publishProblem', a.token, request());
    expect(r.result).toMatchObject({ existing: false });
    problemId = r.result.problemId;
    expect(problemId).toMatch(/^[0-9A-Za-z]{8}$/);
    expect(r.result.cardUploadPath).toBe(`cards/${problemId}/1x1.png`);

    const dup = await callable('publishProblem', a.token, request({ turn: 12 }));
    expect(dup.result).toMatchObject({ existing: true, problemId });
    const other = await callable('publishProblem', b.token, request());
    expect(other.result).toMatchObject({ existing: true, problemId, cardUploadPath: null });
  });

  test('正解は公開ドキュメントに入らず、private/answer にある', async () => {
    const doc = (await db.collection('problems').doc(problemId).get()).data()!;
    expect(doc).not.toHaveProperty('answer');
    const priv = await db.collection('problems').doc(problemId).collection('private').doc('answer').get();
    expect(priv.data()).toMatchObject({ engineVersion: 'nanikiru-engine/0.1.0', shanten: 1 });
    expect(priv.get('byAxis.balance')).toEqual(['9p']);
  });

  test('検証エラーは INVALID_ARGUMENT と details.reason', async () => {
    const tooMany = request({
      tiles: ['1m', '1m', '1m', '1m', '1m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z'],
      dora: [],
    });
    const r1 = await callable('publishProblem', a.token, tooMany);
    expect(r1.error).toMatchObject({ status: 'INVALID_ARGUMENT', details: { reason: 'too_many_same_tile' } });
    const r2 = await callable('publishProblem', a.token, request({ nickname: '運営', dora: ['4z'] }));
    expect(r2.error?.details?.reason).toBe('ng_word');
    const r3 = await callable('publishProblem', a.token, request({ tiles: ['1m'], tsumoIndex: undefined }));
    expect(r3.error?.details).toMatchObject({ reason: 'invalid_tiles', field: 'tiles' });
  });

  test('1 日 20 問の上限（RESOURCE_EXHAUSTED / daily_limit）', async () => {
    const heavy = await signUp();
    // 自風・場風・ドラ表示牌を変えて、重複にならない問題を 21 個作る
    const variants: Array<Record<string, unknown>> = [];
    for (const seatWind of ['east', 'south', 'west', 'north']) {
      for (const roundWind of ['east', 'south', 'west', 'north']) {
        for (const dora of ['5z', '6z']) variants.push({ seatWind, roundWind, dora: [dora] });
      }
    }
    let created = 0;
    let limited: { status: string; details?: any } | undefined;
    for (const v of variants.slice(0, 21)) {
      const r = await callable('publishProblem', heavy.token, request(v));
      if (r.result && !r.result.existing) created++;
      if (r.error?.status === 'RESOURCE_EXHAUSTED') limited = r.error;
    }
    expect(created).toBe(20);
    expect(limited?.details).toMatchObject({ reason: 'daily_limit', limit: 20, used: 20 });
  });
});

describe('answerProblem（アプリ）', () => {
  test('ID トークンの uid で回答でき、2 回目は集計されない', async () => {
    const first = await answer({ problemId, tile: '9p', source: 'app', selfRank: 1 }, c.token);
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({ ok: true, alreadyAnswered: false, correct: true });
    expect(first.body.stats.total).toBe(1);
    const second = await answer({ problemId, tile: '1m', source: 'app' }, c.token);
    expect(second.body).toMatchObject({ alreadyAnswered: true, yourTile: '9p' });
    expect(second.body.stats.total).toBe(1);
  });

  test('トークンなし・不正なトークンは 401、手牌にない牌は 400、存在しない問題は 404', async () => {
    expect((await answer({ problemId, tile: '9p', source: 'app' })).status).toBe(401);
    expect((await answer({ problemId, tile: '9p', source: 'app' }, 'not-a-token')).status).toBe(401);
    const web = { source: 'web', fingerprint: 'abcdefghijklmnopqrstu' };
    expect((await answer({ problemId, tile: '1z', ...web })).body.error.code).toBe('invalid_tile');
    expect((await answer({ problemId: 'ZZZZZZZZ', tile: '9p', ...web })).status).toBe(404);
  });
});

describe('applyReferral / reportProblem / deleteMyData', () => {
  test('紹介コード: 適用・1 人 1 回・自分のコード・存在しないコード', async () => {
    await callable('ensureUser', b.token, { locale: 'ja' });
    const ok = await callable('applyReferral', b.token, { code: codeA.toLowerCase() });
    expect(ok.result).toMatchObject({ applied: true, referrerRewarded: true });
    expect((await callable('applyReferral', b.token, { code: codeA })).error?.status).toBe('ALREADY_EXISTS');
    const self = await callable('applyReferral', a.token, { code: codeA });
    expect(self.error).toMatchObject({ status: 'FAILED_PRECONDITION', details: { reason: 'self_referral' } });
    expect((await callable('applyReferral', c.token, { code: 'ZZZZ2222' })).error?.status).toBe('NOT_FOUND');
    expect((await callable('applyReferral', c.token, { code: 'bad' })).error?.status).toBe('INVALID_ARGUMENT');
    const user = (await db.collection('users').doc(b.uid).get()).data()!;
    expect(user.pro).toMatchObject({ active: true, source: 'referral' });
  });

  test('作成から 24 時間未満のアカウントの通報は、数えられない', async () => {
    const fresh = await signUp();
    await callable('ensureUser', fresh.token, { locale: 'ja' });
    const r = await callable('reportProblem', fresh.token, { problemId, reason: 'spam' });
    expect(r.result).toMatchObject({ reported: true, hidden: false });
    expect((await db.collection('problems').doc(problemId).get()).get('reports')).toBe(0);
    // users が無い uid（ensureUser を呼んでいない）も数えない
    const ghost = await signUp();
    await callable('reportProblem', ghost.token, { problemId, reason: 'spam' });
    expect((await db.collection('problems').doc(problemId).get()).get('reports')).toBe(0);
  });

  test('通報 3 件（24 時間以上たったアカウント）で hidden になり、以後は回答も 404', async () => {
    for (const u of [b, c, d]) {
      await callable('ensureUser', u.token, { locale: 'ja' });
      await db.collection('users').doc(u.uid).update({ createdAt: Timestamp.fromMillis(Date.now() - 2 * 86400000) });
    }
    for (const u of [b, c]) {
      const r = await callable('reportProblem', u.token, { problemId, reason: 'spam' });
      expect(r.result).toMatchObject({ reported: true, hidden: false });
    }
    const third = await callable('reportProblem', d.token, { problemId, reason: 'offensive' });
    expect(third.result).toMatchObject({ reported: true, hidden: true });
    expect((await callable('reportProblem', a.token, { problemId })).error?.status).toBe('PERMISSION_DENIED');
    expect((await callable('reportProblem', a.token, { problemId: 'x' })).error?.status).toBe('INVALID_ARGUMENT');
    const gone = await answer({ problemId, tile: '9p', source: 'web', fingerprint: 'abcdefghijklmnopqrstu' });
    expect(gone.status).toBe(404);
  });

  test('deleteMyData: 問題を非公開にして作者を消し、users・紹介コード・Auth を削除', async () => {
    const mine = await db.collection('problems').where('authorUid', '==', a.uid).get();
    const count = mine.size;
    expect(count).toBeGreaterThan(0);
    const r = await callable('deleteMyData', a.token, {});
    expect(r.result).toMatchObject({ deleted: true, problems: count });
    const after = await db.collection('problems').doc(problemId).get();
    expect(after.data()).toMatchObject({ hidden: true, authorNickname: '', authorUid: 'deleted' });
    expect((await db.collection('users').doc(a.uid).get()).exists).toBe(false);
    expect((await db.collection('referrals').doc(codeA).get()).exists).toBe(false);
    await expect(getAuth().getUser(a.uid)).rejects.toMatchObject({ code: 'auth/user-not-found' });
  });
});
