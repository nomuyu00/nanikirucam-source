/**
 * Firestore エミュレータを使う結合テスト（Functions の本体 `core/` を Admin SDK で直接呼ぶ）。
 * 実行: `npm run test:emulator`
 */
import { Timestamp } from 'firebase-admin/firestore';
import { answerProblemCore } from '../../src/core/answer';
import { autoPostCore } from '../../src/core/autoPost';
import { deleteMyDataCore } from '../../src/core/deleteMyData';
import { pickDailyCore } from '../../src/core/pickDaily';
import { publishProblemCore, DailyLimitError } from '../../src/core/publish';
import { applyReferralCore } from '../../src/core/referral';
import { reportProblemCore } from '../../src/core/report';
import { applyRevenueCatEvent } from '../../src/core/revenuecat';
import { ensureUser } from '../../src/core/users';
import { weeklyDigestCore } from '../../src/core/weekly';
import type { PostPayload, PostRef, SocialAdapter } from '../../src/lib/adapters/types';
import type { Platform } from '../../src/lib/postText';
import type { RevenueCatEvent } from '../../src/lib/revenuecat';
import { sampleInput } from '../fixtures';
import { adminDb, clearFirestore, seedProblem, seedUser } from './helpers';

const db = adminDb();
const DAY = 24 * 60 * 60 * 1000;
const NOW = new Date('2026-10-21T03:00:00Z'); // JST 12:00

beforeEach(async () => {
  await clearFirestore();
});

const publishDeps = (patch: Record<string, unknown> = {}) => ({
  db,
  siteUrl: 'https://x.example',
  now: () => NOW,
  ...patch,
});

/** 牌の集合が違う問題（重複判定に引っかからない）を作るための入力。 */
function inputWithDora(dora: string) {
  return sampleInput({ dora: [dora] });
}

describe('publishProblemCore', () => {
  test('新規作成: 8 文字の ID、problems と users が書かれる', async () => {
    const r = await publishProblemCore(publishDeps(), 'u1', sampleInput());
    expect(r.existing).toBe(false);
    expect(r.problemId).toMatch(/^[0-9A-Za-z]{8}$/);
    expect(r.url).toBe(`https://x.example/p/${r.problemId}`);
    expect(r.cardUploadPath).toBe(`cards/${r.problemId}/1x1.png`);

    const p = (await db.collection('problems').doc(r.problemId).get()).data()!;
    expect(p).toMatchObject({
      tiles: sampleInput().tiles,
      tsumo: '9p',
      dora: ['3z'],
      seatWind: 'south',
      roundWind: 'east',
      turn: 6,
      authorUid: 'u1',
      authorNickname: 'まじゃおう',
      locale: 'ja',
      stats: { total: 0, byTile: {}, correct: 0 },
      featured: { daily: null, posted: false },
      reports: 0,
      hidden: false,
      cardPath: `cards/${r.problemId}/1x1.png`,
    });
    // 正解は公開ドキュメントに入れず、private/answer（Functions 専用）に置く
    expect(p).not.toHaveProperty('answer');
    const priv = await db.collection('problems').doc(r.problemId).collection('private').doc('answer').get();
    expect(priv.data()).toEqual(sampleInput().answer);
    expect(p.createdAt.toDate().toISOString()).toBe(NOW.toISOString());
    expect(p.contentKey).toMatch(/^[0-9a-f]{32}$/);

    const u = (await db.collection('users').doc('u1').get()).data()!;
    expect(u.problemCount).toBe(1);
    expect(u.publishQuota).toEqual({ date: '2026-10-21', count: 1 });
    expect(u.nickname).toBe('まじゃおう');
    expect(u.referralCode).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
  });

  test('同じ牌列は既存の問題を返し、上限を消費しない', async () => {
    const first = await publishProblemCore(publishDeps(), 'u1', sampleInput());
    const again = await publishProblemCore(publishDeps(), 'u1', sampleInput({ turn: 12 }));
    expect(again).toMatchObject({ problemId: first.problemId, existing: true });
    expect(again.cardUploadPath).toBe(`cards/${first.problemId}/1x1.png`); // 自分の問題ならカードを再アップロードできる

    const other = await publishProblemCore(publishDeps(), 'u2', sampleInput());
    expect(other).toMatchObject({ problemId: first.problemId, existing: true, cardUploadPath: null });

    const u = (await db.collection('users').doc('u1').get()).data()!;
    expect(u.problemCount).toBe(1);
    expect(u.publishQuota.count).toBe(1);
    expect((await db.collection('problems').get()).size).toBe(1);
  });

  test('1 日の上限を超えると DailyLimitError。日付が変わればリセット', async () => {
    const deps = publishDeps({ dailyLimit: 3 });
    for (const dora of ['5z', '6z', '7z']) {
      await publishProblemCore(deps, 'u1', inputWithDora(dora));
    }
    await expect(publishProblemCore(deps, 'u1', inputWithDora('4z'))).rejects.toBeInstanceOf(
      DailyLimitError,
    );
    expect((await db.collection('problems').get()).size).toBe(3);

    // 他のユーザーは影響を受けない
    await publishProblemCore(deps, 'u2', inputWithDora('4z'));

    // 翌日（JST）
    const tomorrow = publishDeps({ dailyLimit: 3, now: () => new Date(NOW.getTime() + DAY) });
    const r = await publishProblemCore(tomorrow, 'u1', inputWithDora('1z'));
    expect(r.existing).toBe(false);
    const u = (await db.collection('users').doc('u1').get()).data()!;
    expect(u.publishQuota).toEqual({ date: '2026-10-22', count: 1 });
  });

  test('hidden の問題は重複として返さない', async () => {
    const first = await publishProblemCore(publishDeps(), 'u1', sampleInput());
    await db.collection('problems').doc(first.problemId).update({ hidden: true });
    const second = await publishProblemCore(publishDeps(), 'u2', sampleInput());
    expect(second.existing).toBe(false);
    expect(second.problemId).not.toBe(first.problemId);
  });

  test('ID が衝突したら別の ID で作り直す', async () => {
    await seedProblem(db, 'AAAAAAAA');
    const ids = ['AAAAAAAA', 'AAAAAAAA', 'BBBBBBBB'];
    const r = await publishProblemCore(publishDeps({ newId: () => ids.shift() as string }), 'u1', sampleInput());
    expect(r.problemId).toBe('BBBBBBBB');
  });

  test('ニックネーム未指定なら、保存済みのニックネームを使う（なければ空）', async () => {
    await publishProblemCore(publishDeps(), 'u1', sampleInput());
    const r = await publishProblemCore(publishDeps(), 'u1', { ...inputWithDora('5z'), nickname: null });
    const p = (await db.collection('problems').doc(r.problemId).get()).data()!;
    expect(p.authorNickname).toBe('まじゃおう');

    const r2 = await publishProblemCore(publishDeps(), 'u9', { ...inputWithDora('6z'), nickname: null });
    expect((await db.collection('problems').doc(r2.problemId).get()).get('authorNickname')).toBe('');
  });
});

describe('answerProblemCore', () => {
  async function newProblem() {
    const { problemId } = await publishProblemCore(publishDeps(), 'author', sampleInput());
    return problemId;
  }
  const web = (problemId: string, tile: string, fp: string) => ({
    problemId,
    tile,
    source: 'web' as const,
    fingerprintRaw: fp,
    uid: null,
    selfRank: null,
  });

  test('1 回目は集計に入り、同じ fingerprint の 2 回目は集計されない', async () => {
    const id = await newProblem();
    const a = await answerProblemCore(db, web(id, '9p', 'fingerprint-aaaaaaaa'), NOW);
    expect(a).toMatchObject({ kind: 'ok', alreadyAnswered: false, yourTile: '9p', correct: true });
    if (a.kind !== 'ok') throw new Error();
    expect(a.stats).toEqual({ total: 1, byTile: { '9p': 1 }, correct: 1 });
    expect(a.answer.byAxis.balance).toEqual(['9p']);

    // 別の牌で再回答しても、最初の回答と現在の集計が返るだけ
    const b = await answerProblemCore(db, web(id, '1m', 'fingerprint-aaaaaaaa'), NOW);
    expect(b).toMatchObject({ kind: 'ok', alreadyAnswered: true, yourTile: '9p' });

    const stats = (await db.collection('problems').doc(id).get()).get('stats');
    expect(stats).toEqual({ total: 1, byTile: { '9p': 1 }, correct: 1 });
    const answers = await db.collection('problems').doc(id).collection('answers').get();
    expect(answers.size).toBe(1);
    expect(answers.docs[0].data()).toMatchObject({ tile: '9p', source: 'web', uid: null, selfRank: null });
    // fingerprint は生の値ではなくハッシュで保存する
    expect(answers.docs[0].get('fingerprint')).not.toContain('fingerprint-aaaaaaaa');
  });

  test('正解はバランス軸。別解（打点軸）は correct にならないが judgement に出る', async () => {
    const id = await newProblem();
    const alt = await answerProblemCore(db, web(id, '5m', 'fingerprint-bbbbbbbb'), NOW);
    if (alt.kind !== 'ok') throw new Error();
    expect(alt.correct).toBe(false);
    expect(alt.judgement).toEqual({ speed: false, points: true, balance: false });
    const miss = await answerProblemCore(db, web(id, '1m', 'fingerprint-cccccccc'), NOW);
    if (miss.kind !== 'ok') throw new Error();
    expect(miss.stats).toEqual({ total: 2, byTile: { '5m': 1, '1m': 1 }, correct: 0 });
  });

  test('正解（private/answer）が無い問題は集計せずエラーにする', async () => {
    const id = await newProblem();
    await db.collection('problems').doc(id).collection('private').doc('answer').delete();
    await expect(answerProblemCore(db, web(id, '9p', 'fingerprint-zzzzzzzz'), NOW)).rejects.toThrow(/private\/answer/);
    expect((await db.collection('problems').doc(id).get()).get('stats.total')).toBe(0);
  });

  test('手牌にない牌・存在しない問題・hidden', async () => {
    const id = await newProblem();
    expect(await answerProblemCore(db, web(id, '1z', 'fingerprint-dddddddd'), NOW)).toEqual({
      kind: 'invalid_tile',
    });
    expect(await answerProblemCore(db, web('ZZZZZZZZ', '9p', 'fingerprint-dddddddd'), NOW)).toEqual({
      kind: 'not_found',
    });
    await db.collection('problems').doc(id).update({ hidden: true });
    expect(await answerProblemCore(db, web(id, '9p', 'fingerprint-dddddddd'), NOW)).toEqual({
      kind: 'not_found',
    });
  });

  test('並行して 30 件（別の端末）を受けても集計が欠けない', async () => {
    const id = await newProblem();
    const tiles = ['9p', '5m', '1m'];
    const results = await Promise.all(
      Array.from({ length: 30 }, (_, i) =>
        answerProblemCore(db, web(id, tiles[i % 3], `fingerprint-${String(i).padStart(8, '0')}`), NOW),
      ),
    );
    expect(results.every((r) => r.kind === 'ok')).toBe(true);
    const stats = (await db.collection('problems').doc(id).get()).get('stats');
    expect(stats.total).toBe(30);
    expect(stats.byTile).toEqual({ '9p': 10, '5m': 10, '1m': 10 });
    expect(stats.correct).toBe(10);
    expect((await db.collection('problems').doc(id).collection('answers').get()).size).toBe(30);
  });

  test('同じ端末からの並行リクエストは 1 件だけ集計される', async () => {
    const id = await newProblem();
    const results = await Promise.all(
      Array.from({ length: 10 }, () => answerProblemCore(db, web(id, '9p', 'fingerprint-eeeeeeee'), NOW)),
    );
    expect(results.filter((r) => r.kind === 'ok' && !r.alreadyAnswered)).toHaveLength(1);
    expect((await db.collection('problems').doc(id).get()).get('stats.total')).toBe(1);
  });

  test('10 人目で節目（10）。11 人目では出ない。出題者の uid を返す', async () => {
    const id = await newProblem();
    const milestones: Array<number | null> = [];
    for (let i = 0; i < 11; i++) {
      const r = await answerProblemCore(db, web(id, '9p', `fingerprint-m${String(i).padStart(7, '0')}`), NOW);
      if (r.kind !== 'ok') throw new Error();
      milestones.push(r.milestone?.count ?? null);
      if (i === 9) expect(r.milestone).toEqual({ authorUid: 'author', count: 10, problemId: id });
    }
    expect(milestones.filter((m) => m !== null)).toEqual([10]);
  });

  test('アプリからの回答は uid を保存し、uid ごとに二重回答を判定する', async () => {
    const id = await newProblem();
    const app = (uid: string) => ({
      problemId: id,
      tile: '9p',
      source: 'app' as const,
      fingerprintRaw: uid,
      uid,
      selfRank: 2,
    });
    await answerProblemCore(db, app('uid-A'), NOW);
    await answerProblemCore(db, app('uid-A'), NOW);
    await answerProblemCore(db, app('uid-B'), NOW);
    expect((await db.collection('problems').doc(id).get()).get('stats.total')).toBe(2);
    const answers = await db.collection('problems').doc(id).collection('answers').where('uid', '==', 'uid-A').get();
    expect(answers.size).toBe(1);
    expect(answers.docs[0].get('selfRank')).toBe(2);
    // Web と同じ文字列でも別の種類として数える
    await answerProblemCore(db, web(id, '9p', 'uid-A'), NOW);
    expect((await db.collection('problems').doc(id).get()).get('stats.total')).toBe(3);
  });
});

describe('reportProblemCore', () => {
  const OLD = new Date(NOW.getTime() - 2 * DAY); // 作成から 2 日たったアカウント
  const seedReporters = async (...uids: string[]) => {
    for (const uid of uids) await seedUser(db, uid, OLD);
  };

  test('3 人の通報で hidden。同じ人の重複は 1 件', async () => {
    await seedProblem(db, 'PPPPPPPP');
    await seedReporters('r1', 'r2', 'r3');
    expect(await reportProblemCore(db, 'r1', 'PPPPPPPP', 'spam', NOW)).toEqual({
      kind: 'reported',
      alreadyReported: false,
      counted: true,
      hidden: false,
      reports: 1,
    });
    expect(await reportProblemCore(db, 'r1', 'PPPPPPPP', 'spam', NOW)).toMatchObject({
      alreadyReported: true,
      reports: 1,
    });
    await reportProblemCore(db, 'r2', 'PPPPPPPP', 'offensive', NOW);
    const third = await reportProblemCore(db, 'r3', 'PPPPPPPP', 'other', NOW);
    expect(third).toEqual({ kind: 'reported', alreadyReported: false, counted: true, hidden: true, reports: 3 });
    const p = (await db.collection('problems').doc('PPPPPPPP').get()).data()!;
    expect(p.hidden).toBe(true);
    expect(p.reports).toBe(3);
    const reports = await db.collection('problems').doc('PPPPPPPP').collection('reports').get();
    expect(reports.size).toBe(3);
    expect(reports.docs.every((d) => d.get('counted') === true)).toBe(true);
  });

  test('自分の問題・存在しない問題', async () => {
    await seedProblem(db, 'PPPPPPPP', { authorUid: 'me' });
    await seedReporters('me', 'r1');
    expect(await reportProblemCore(db, 'me', 'PPPPPPPP', 'spam', NOW)).toEqual({ kind: 'own_problem' });
    expect(await reportProblemCore(db, 'r1', 'QQQQQQQQ', 'spam', NOW)).toEqual({ kind: 'not_found' });
  });

  test('並行して 5 人が通報しても件数がずれない', async () => {
    await seedProblem(db, 'PPPPPPPP');
    await seedReporters('a', 'b', 'c', 'd', 'e');
    await Promise.all(['a', 'b', 'c', 'd', 'e'].map((u) => reportProblemCore(db, u, 'PPPPPPPP', 'spam', NOW)));
    const p = (await db.collection('problems').doc('PPPPPPPP').get()).data()!;
    expect(p.reports).toBe(5);
    expect(p.hidden).toBe(true);
  });

  test('作成から 24 時間未満の uid の通報は、記録だけして reports に加算しない', async () => {
    await seedProblem(db, 'PPPPPPPP');
    // 1 秒前に作られたアカウントを 5 つ（匿名アカウントの量産）
    const fresh = ['f1', 'f2', 'f3', 'f4', 'f5'];
    for (const uid of fresh) await seedUser(db, uid, new Date(NOW.getTime() - 1000));
    for (const uid of fresh) {
      expect(await reportProblemCore(db, uid, 'PPPPPPPP', 'spam', NOW)).toEqual({
        kind: 'reported',
        alreadyReported: false,
        counted: false,
        hidden: false,
        reports: 0,
      });
    }
    const p = (await db.collection('problems').doc('PPPPPPPP').get()).data()!;
    expect(p.reports).toBe(0);
    expect(p.hidden).toBe(false);
    // 記録は残る（counted: false）
    const reports = await db.collection('problems').doc('PPPPPPPP').collection('reports').get();
    expect(reports.size).toBe(5);
    expect(reports.docs.every((d) => d.get('counted') === false)).toBe(true);
  });

  test('users が無い uid の通報も数えない（記録だけ）', async () => {
    await seedProblem(db, 'PPPPPPPP');
    const r = await reportProblemCore(db, 'ghost', 'PPPPPPPP', 'spam', NOW);
    expect(r).toMatchObject({ kind: 'reported', counted: false, reports: 0 });
    expect((await db.collection('problems').doc('PPPPPPPP').collection('reports').doc('ghost').get()).exists).toBe(true);
    expect((await db.collection('problems').doc('PPPPPPPP').get()).get('reports')).toBe(0);
  });

  test('24 時間ちょうどから数える（23 時間 59 分 59 秒は数えない）', async () => {
    await seedProblem(db, 'PPPPPPPP');
    await seedUser(db, 'edge-before', new Date(NOW.getTime() - DAY + 1000));
    await seedUser(db, 'edge-exact', new Date(NOW.getTime() - DAY));
    expect(await reportProblemCore(db, 'edge-before', 'PPPPPPPP', 'spam', NOW)).toMatchObject({ counted: false, reports: 0 });
    expect(await reportProblemCore(db, 'edge-exact', 'PPPPPPPP', 'spam', NOW)).toMatchObject({ counted: true, reports: 1 });
  });

  test('新しいアカウントの通報が混ざっても、数えられる通報が 3 件になった時点で hidden', async () => {
    await seedProblem(db, 'PPPPPPPP');
    await seedReporters('o1', 'o2', 'o3');
    for (const uid of ['n1', 'n2', 'n3', 'n4']) await seedUser(db, uid, new Date(NOW.getTime() - 60 * 1000));
    for (const uid of ['n1', 'n2', 'n3', 'n4', 'o1', 'o2']) await reportProblemCore(db, uid, 'PPPPPPPP', 'spam', NOW);
    let p = (await db.collection('problems').doc('PPPPPPPP').get()).data()!;
    expect(p).toMatchObject({ reports: 2, hidden: false });
    const last = await reportProblemCore(db, 'o3', 'PPPPPPPP', 'spam', NOW);
    expect(last).toMatchObject({ counted: true, hidden: true, reports: 3 });
    p = (await db.collection('problems').doc('PPPPPPPP').get()).data()!;
    expect(p).toMatchObject({ reports: 3, hidden: true });
  });

  test('新しいアカウントが先に通報すると、24 時間後の再通報も数えない（1 uid 1 件）', async () => {
    await seedProblem(db, 'PPPPPPPP');
    await seedUser(db, 'young', new Date(NOW.getTime() - 1000));
    await reportProblemCore(db, 'young', 'PPPPPPPP', 'spam', NOW);
    const later = new Date(NOW.getTime() + 2 * DAY);
    expect(await reportProblemCore(db, 'young', 'PPPPPPPP', 'spam', later)).toMatchObject({
      alreadyReported: true,
      counted: false,
      reports: 0,
    });
  });
});

describe('ensureUser / applyReferralCore', () => {
  test('ensureUser は何度呼んでも同じ紹介コードを返し、referrals を作る', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    expect(a.created).toBe(true);
    expect(a.referralCode).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
    expect(a.pro).toEqual({ active: false, source: null, untilMs: null });
    const again = await ensureUser(db, 'uA', 'en', NOW);
    expect(again.referralCode).toBe(a.referralCode);
    expect(again.created).toBe(false);
    const ref = (await db.collection('referrals').doc(a.referralCode).get()).data()!;
    expect(ref).toMatchObject({ uid: 'uA', uses: 0 });
    const user = (await db.collection('users').doc('uA').get()).data()!;
    expect(user.locale).toBe('ja'); // 最初の言語を保つ
  });

  test('コードが衝突したら別のコードで作り直す', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    const codes = [a.referralCode, a.referralCode, 'ZZZZ2222'];
    const b = await ensureUser(db, 'uB', 'ja', NOW, () => codes.shift() as string);
    expect(b.referralCode).toBe('ZZZZ2222');
  });

  test('紹介コードの適用: 両者に 7 日', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    await ensureUser(db, 'uB', 'ja', NOW);
    const r = await applyReferralCore(db, 'uB', a.referralCode, NOW);
    expect(r).toEqual({ kind: 'applied', proUntilMs: NOW.getTime() + 7 * DAY, referrerRewarded: true });

    const b = (await db.collection('users').doc('uB').get()).data()!;
    expect(b.referredBy).toBe(a.referralCode);
    expect(b.pro.active).toBe(true);
    expect(b.pro.source).toBe('referral');
    expect(b.pro.until.toMillis()).toBe(NOW.getTime() + 7 * DAY);
    expect(b.pro.referral.until.toMillis()).toBe(NOW.getTime() + 7 * DAY);

    const aDoc = (await db.collection('users').doc('uA').get()).data()!;
    expect(aDoc.pro).toMatchObject({ active: true, source: 'referral' });
    expect((await db.collection('referrals').doc(a.referralCode).get()).get('uses')).toBe(1);
  });

  test('1 人 1 回・自分のコード・存在しないコード・ユーザー未作成', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    const c = await ensureUser(db, 'uC', 'ja', NOW);
    await ensureUser(db, 'uB', 'ja', NOW);
    await applyReferralCore(db, 'uB', a.referralCode, NOW);
    expect(await applyReferralCore(db, 'uB', c.referralCode, NOW)).toEqual({ kind: 'already_applied' });
    expect(await applyReferralCore(db, 'uA', a.referralCode, NOW)).toEqual({ kind: 'self_referral' });
    expect(await applyReferralCore(db, 'uC', 'ZZZZ2222', NOW)).toEqual({ kind: 'invalid_code' });
    expect(await applyReferralCore(db, 'nobody', a.referralCode, NOW)).toEqual({ kind: 'no_user' });
    expect((await db.collection('referrals').doc(a.referralCode).get()).get('uses')).toBe(1);
  });

  test('紹介した側の特典は上限人数まで。複数回は期限を延ばす', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    await ensureUser(db, 'uB', 'ja', NOW);
    await applyReferralCore(db, 'uB', a.referralCode, NOW);
    await ensureUser(db, 'uC', 'ja', NOW);
    await applyReferralCore(db, 'uC', a.referralCode, NOW);
    const aDoc = (await db.collection('users').doc('uA').get()).data()!;
    expect(aDoc.pro.referral.until.toMillis()).toBe(NOW.getTime() + 14 * DAY);

    await db.collection('referrals').doc(a.referralCode).update({ uses: 10 });
    await ensureUser(db, 'uD', 'ja', NOW);
    const r = await applyReferralCore(db, 'uD', a.referralCode, NOW);
    expect(r).toMatchObject({ kind: 'applied', referrerRewarded: false });
    const after = (await db.collection('users').doc('uA').get()).data()!;
    expect(after.pro.referral.until.toMillis()).toBe(NOW.getTime() + 14 * DAY);
  });

  test('並行して同じ人が 2 回適用しても 1 回だけ', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    await ensureUser(db, 'uB', 'ja', NOW);
    const rs = await Promise.all([
      applyReferralCore(db, 'uB', a.referralCode, NOW),
      applyReferralCore(db, 'uB', a.referralCode, NOW),
    ]);
    expect(rs.filter((r) => r.kind === 'applied')).toHaveLength(1);
    expect((await db.collection('referrals').doc(a.referralCode).get()).get('uses')).toBe(1);
  });
});

describe('applyRevenueCatEvent', () => {
  const rc = (patch: Partial<RevenueCatEvent> = {}): RevenueCatEvent => ({
    id: 'e1',
    type: 'INITIAL_PURCHASE',
    app_user_id: 'uA',
    original_app_user_id: 'uA',
    aliases: ['uA'],
    entitlement_ids: ['pro'],
    product_id: 'nanikiru_pro_monthly',
    period_type: 'TRIAL',
    store: 'APP_STORE',
    environment: 'SANDBOX',
    event_timestamp_ms: NOW.getTime(),
    expiration_at_ms: NOW.getTime() + 7 * DAY,
    ...patch,
  });

  test('購入で有効、期限切れイベントで無効', async () => {
    await ensureUser(db, 'uA', 'ja', NOW);
    expect(await applyRevenueCatEvent(db, rc(), NOW)).toEqual({ status: 'applied', uid: 'uA' });
    let pro = (await db.collection('users').doc('uA').get()).get('pro');
    expect(pro).toMatchObject({ active: true, source: 'revenuecat' });
    expect(pro.until.toMillis()).toBe(NOW.getTime() + 7 * DAY);
    expect(pro.revenuecat).toMatchObject({ productId: 'nanikiru_pro_monthly', environment: 'SANDBOX', lastEventId: 'e1' });

    await applyRevenueCatEvent(
      db,
      rc({ id: 'e2', type: 'EXPIRATION', event_timestamp_ms: NOW.getTime() + 8 * DAY, expiration_at_ms: NOW.getTime() + 7 * DAY }),
      new Date(NOW.getTime() + 8 * DAY),
    );
    pro = (await db.collection('users').doc('uA').get()).get('pro');
    expect(pro).toMatchObject({ active: false, source: null, until: null });
  });

  test('再送（同じ id）と古いイベントは無視。他の項目（紹介特典）は消えない', async () => {
    const a = await ensureUser(db, 'uA', 'ja', NOW);
    await ensureUser(db, 'uB', 'ja', NOW);
    await applyReferralCore(db, 'uB', a.referralCode, NOW); // uA に紹介特典 7 日
    await applyRevenueCatEvent(db, rc(), NOW);
    expect(await applyRevenueCatEvent(db, rc(), NOW)).toEqual({ status: 'ignored', reason: 'duplicate' });
    expect(
      await applyRevenueCatEvent(db, rc({ id: 'old', event_timestamp_ms: NOW.getTime() - 1000 }), NOW),
    ).toEqual({ status: 'ignored', reason: 'stale' });

    // RevenueCat が切れても紹介特典が残っていれば有効
    await applyRevenueCatEvent(
      db,
      rc({ id: 'e3', type: 'EXPIRATION', event_timestamp_ms: NOW.getTime() + 1000, expiration_at_ms: NOW.getTime() }),
      NOW,
    );
    const pro = (await db.collection('users').doc('uA').get()).get('pro');
    expect(pro).toMatchObject({ active: true, source: 'referral' });
    expect(pro.referral.until.toMillis()).toBe(NOW.getTime() + 7 * DAY);
  });

  test('未知のユーザー・匿名 ID・pro 以外', async () => {
    expect(await applyRevenueCatEvent(db, rc({ app_user_id: 'nobody', original_app_user_id: null, aliases: [] }), NOW)).toEqual({
      status: 'unknown_user',
    });
    expect(
      await applyRevenueCatEvent(
        db,
        rc({ app_user_id: '$RCAnonymousID:x', original_app_user_id: null, aliases: [] }),
        NOW,
      ),
    ).toEqual({ status: 'ignored', reason: 'anonymous_user' });
    await ensureUser(db, 'uA', 'ja', NOW);
    expect(await applyRevenueCatEvent(db, rc({ entitlement_ids: ['other'] }), NOW)).toEqual({
      status: 'ignored',
      reason: 'not_pro',
    });
  });

  test('TRANSFER: 移動元の権利を無効にする', async () => {
    await ensureUser(db, 'uA', 'ja', NOW);
    await applyRevenueCatEvent(db, rc(), NOW);
    const r = await applyRevenueCatEvent(
      db,
      rc({ id: 't1', type: 'TRANSFER', transferred_from: ['uA'], transferred_to: ['uZ'], event_timestamp_ms: NOW.getTime() + 1 }),
      NOW,
    );
    expect(r).toEqual({ status: 'applied', uid: 'uA' });
    expect((await db.collection('users').doc('uA').get()).get('pro.active')).toBe(false);
  });
});

describe('pickDailyCore', () => {
  async function seedCandidate(id: string, total: number, correct: number, patch: Record<string, unknown> = {}) {
    await seedProblem(db, id, {
      authorUid: `author-${id}`,
      stats: { total, byTile: { '9p': correct, '5m': total - correct }, correct },
      ...patch,
    });
  }

  test('公式 1 問 + 条件を満たすユーザー投稿 2 問を選び、featured を更新する', async () => {
    await seedProblem(db, 'OFFICIAL', { authorUid: 'ops' });
    await db.collection('official').doc('o1').set({ problemId: 'OFFICIAL', order: 1, used: false, usedDate: null });
    await seedCandidate('GOOD0001', 40, 20);
    await seedCandidate('GOOD0002', 100, 55);
    await seedCandidate('FEWANS01', 10, 5); // 回答が少ない
    await seedCandidate('EASY0001', 50, 45); // 正解率が高すぎる
    await seedCandidate('REPORTED', 50, 25, { reports: 1 });
    await seedCandidate('HIDDEN01', 50, 25, { hidden: true });
    await seedCandidate('RECENT01', 50, 25, { featured: { daily: '2026-10-10', posted: false } });

    const r = await pickDailyCore(db, NOW);
    expect(r.skipped).toBe(false);
    expect(r.date).toBe('2026-10-21');
    expect(r.official).toBe('OFFICIAL');
    expect([...r.picks].sort()).toEqual(['GOOD0001', 'GOOD0002']);

    const daily = (await db.collection('daily').doc('2026-10-21').get()).data()!;
    expect(daily.official).toBe('OFFICIAL');
    expect([...daily.picks].sort()).toEqual(['GOOD0001', 'GOOD0002']);
    expect(daily.generatedAt).toBeInstanceOf(Timestamp);

    expect((await db.collection('problems').doc('GOOD0001').get()).get('featured.daily')).toBe('2026-10-21');
    expect((await db.collection('problems').doc('OFFICIAL').get()).get('featured.daily')).toBe('2026-10-21');
    expect((await db.collection('official').doc('o1').get()).data()).toMatchObject({ used: true, usedDate: '2026-10-21' });
  });

  test('再実行しても二重に選ばない。翌日は選出済みの問題が 30 日除外される', async () => {
    await seedProblem(db, 'OFFICIAL', { authorUid: 'ops' });
    await db.collection('official').doc('o1').set({ problemId: 'OFFICIAL', order: 1, used: false });
    await db.collection('official').doc('o2').set({ problemId: 'OFFICIAL2', order: 2, used: false });
    await seedProblem(db, 'OFFICIAL2', { authorUid: 'ops' });
    await seedCandidate('GOOD0001', 40, 20);
    await seedCandidate('GOOD0002', 100, 55);
    await seedCandidate('GOOD0003', 60, 30);

    const first = await pickDailyCore(db, NOW);
    expect(first.picks).toHaveLength(2);
    expect(await pickDailyCore(db, NOW)).toMatchObject({ skipped: true });

    const next = await pickDailyCore(db, new Date(NOW.getTime() + DAY));
    expect(next.skipped).toBe(false);
    expect(next.official).toBe('OFFICIAL2'); // 次の未出題
    // 初日に選ばれた 2 問は 30 日間除外されるので、残りの 1 問だけが選ばれる
    expect(next.picks).toHaveLength(1);
    for (const id of first.picks) expect(next.picks).not.toContain(id);
    expect([...first.picks, ...next.picks].sort()).toEqual(['GOOD0001', 'GOOD0002', 'GOOD0003']);

    // 31 日後には、初日の問題がまた選べる
    const later = await pickDailyCore(db, new Date(NOW.getTime() + 31 * DAY));
    expect(later.picks.length).toBeGreaterThan(0);
  });

  test('3 軸が割れている問題を優先する（正解は private/answer から読む）', async () => {
    const single = {
      byAxis: { speed: ['9p'], points: ['9p'], balance: ['9p'] },
      ukeire: { kinds: 1, total: 1 },
      shanten: 0,
      engineVersion: 't',
    };
    await seedCandidate('SINGLE01', 100, 50, { answer: single }); // 正解率は 50% ちょうどだが、解が 1 つ
    await seedCandidate('SPLIT001', 100, 52);
    await seedCandidate('SPLIT002', 100, 55);
    const r = await pickDailyCore(db, NOW);
    expect([...r.picks].sort()).toEqual(['SPLIT001', 'SPLIT002']);
  });

  test('公式の候補が無く、条件を満たす投稿も無くても daily を書く', async () => {
    const r = await pickDailyCore(db, NOW);
    expect(r).toMatchObject({ skipped: false, official: null, picks: [] });
    expect((await db.collection('daily').doc('2026-10-21').get()).data()).toMatchObject({ official: null, picks: [] });
  });

  test('非表示の公式問題はとばして次を使う', async () => {
    await seedProblem(db, 'HIDDENOF', { hidden: true });
    await seedProblem(db, 'OFFICIAL', { authorUid: 'ops' });
    await db.collection('official').doc('o1').set({ problemId: 'HIDDENOF', order: 1, used: false });
    await db.collection('official').doc('o2').set({ problemId: 'OFFICIAL', order: 2, used: false });
    expect((await pickDailyCore(db, NOW)).official).toBe('OFFICIAL');
  });
});

describe('deleteMyDataCore', () => {
  test('本人の情報を消し、出題は非公開＋作者名を消す。他人のデータは残す', async () => {
    const me = await ensureUser(db, 'me', 'ja', NOW);
    await ensureUser(db, 'other', 'ja', NOW);
    await seedProblem(db, 'MINE0001', { authorUid: 'me', authorNickname: 'わたし' });
    await seedProblem(db, 'MINE0002', { authorUid: 'me', authorNickname: 'わたし' });
    await seedProblem(db, 'OTHER001', { authorUid: 'other' });
    await answerProblemCore(db, { problemId: 'OTHER001', tile: '9p', source: 'app', fingerprintRaw: 'me', uid: 'me', selfRank: 1 }, NOW);
    await answerProblemCore(db, { problemId: 'OTHER001', tile: '9p', source: 'app', fingerprintRaw: 'other', uid: 'other', selfRank: 1 }, NOW);
    await reportProblemCore(db, 'me', 'OTHER001', 'spam', NOW);
    await db.collection('problems').doc('MINE0001').collection('answers').doc('x').set({ tile: '9p', uid: 'other' });

    const deletedCards: string[] = [];
    const deletedAuth: string[] = [];
    const result = await deleteMyDataCore(
      {
        db,
        deleteCards: async (id) => void deletedCards.push(id),
        deleteAuthUser: async (uid) => void deletedAuth.push(uid),
      },
      'me',
    );

    expect(result).toEqual({ problems: 2, answers: 1, reports: 1 });
    expect(deletedCards.sort()).toEqual(['MINE0001', 'MINE0002']);
    expect(deletedAuth).toEqual(['me']);

    for (const id of ['MINE0001', 'MINE0002']) {
      expect((await db.collection('problems').doc(id).get()).data()).toMatchObject({
        hidden: true,
        authorNickname: '',
        authorUid: 'deleted',
      });
    }
    expect((await db.collection('users').doc('me').get()).exists).toBe(false);
    expect((await db.collection('referrals').doc(me.referralCode).get()).exists).toBe(false);
    // 他人の回答・ユーザー・問題は残る
    expect((await db.collection('users').doc('other').get()).exists).toBe(true);
    expect((await db.collection('problems').doc('OTHER001').get()).get('hidden')).toBe(false);
    const remaining = await db.collection('problems').doc('OTHER001').collection('answers').get();
    expect(remaining.docs.map((d) => d.get('uid'))).toEqual(['other']);
    expect((await db.collection('problems').doc('OTHER001').collection('reports').get()).size).toBe(0);
    expect((await db.collection('problems').doc('MINE0001').collection('answers').doc('x').get()).exists).toBe(true);
  });
});

/** 投稿内容を記録する偽のアダプタ。 */
function fakeAdapter(platform: Platform, opts: { failPost?: boolean } = {}) {
  const posts: Array<PostPayload & { ref: PostRef }> = [];
  const adapter: SocialAdapter = {
    platform,
    async post(payload) {
      if (opts.failPost) throw new Error(`${platform} is down`);
      const n = posts.length + 1;
      const ref: PostRef =
        platform === 'bluesky' ? { id: `at://${n}`, uri: `at://${n}`, cid: 'cid' } : { id: `${platform}-${n}` };
      posts.push({ ...payload, ref });
      return ref;
    },
  };
  return { adapter, posts };
}

describe('autoPostCore', () => {
  const siteUrl = 'https://x.example';
  const loadCard = async () => new Uint8Array([1, 2, 3]);
  const day1 = new Date('2026-10-21T10:00:00Z'); // JST 19:00
  const day2 = new Date(day1.getTime() + DAY);

  async function setupDaily(date: string, official: string, picks: string[] = []) {
    await db.collection('daily').doc(date).set({ official, picks, generatedAt: Timestamp.now() });
  }

  test('今日の問題を各投稿先にカード付きで投稿し、結果を保存する。再実行しても二重投稿しない', async () => {
    await seedProblem(db, 'OFFICIAL', { authorUid: 'ops' });
    await setupDaily('2026-10-21', 'OFFICIAL');
    const bsky = fakeAdapter('bluesky');
    const discord = fakeAdapter('discord');
    const deps = { db, adapters: [bsky.adapter, discord.adapter], siteUrl, bucketName: 'bkt', loadCard };

    const r = await autoPostCore(deps, day1);
    expect(r).toMatchObject({ postedProblemId: 'OFFICIAL', postedPlatforms: ['bluesky', 'discord'], errors: [] });
    expect(bsky.posts).toHaveLength(1);
    expect(bsky.posts[0].text).toContain('https://x.example/p/OFFICIAL');
    expect(bsky.posts[0].text).toContain('【今日の何切る】');
    expect(bsky.posts[0].image?.bytes).toEqual(new Uint8Array([1, 2, 3]));
    expect(bsky.posts[0].image?.publicUrl).toBe(
      'https://firebasestorage.googleapis.com/v0/b/bkt/o/cards%2FOFFICIAL%2F1x1.png?alt=media',
    );
    expect(bsky.posts[0].replyTo).toBeUndefined();

    const daily = (await db.collection('daily').doc('2026-10-21').get()).data()!;
    expect(daily.postedProblemId).toBe('OFFICIAL');
    expect(daily.posts.bluesky).toEqual({ id: 'at://1', uri: 'at://1', cid: 'cid' });
    expect(daily.posts.discord).toEqual({ id: 'discord-1' });
    expect((await db.collection('problems').doc('OFFICIAL').get()).get('featured.posted')).toBe(true);

    const again = await autoPostCore(deps, day1);
    expect(again.postedPlatforms).toEqual([]);
    expect(bsky.posts).toHaveLength(1);
    expect(discord.posts).toHaveLength(1);
  });

  test('投稿先の 1 つが失敗しても他は投稿され、失敗した先だけ再実行で投稿される', async () => {
    await seedProblem(db, 'OFFICIAL', { authorUid: 'ops' });
    await setupDaily('2026-10-21', 'OFFICIAL');
    const bad = fakeAdapter('threads', { failPost: true });
    const good = fakeAdapter('discord');
    const r = await autoPostCore({ db, adapters: [bad.adapter, good.adapter], siteUrl, bucketName: 'b', loadCard }, day1);
    expect(r.postedPlatforms).toEqual(['discord']);
    expect(r.errors).toEqual(['post:threads']);

    const recovered = fakeAdapter('threads');
    const r2 = await autoPostCore({ db, adapters: [recovered.adapter, good.adapter], siteUrl, bucketName: 'b', loadCard }, day1);
    expect(r2.postedPlatforms).toEqual(['threads']);
    expect(good.posts).toHaveLength(1);
  });

  test('翌日、昨日の投稿への返信（答え合わせ）を付ける。返信は 1 回だけ', async () => {
    await seedProblem(db, 'OFFICIAL', {
      authorUid: 'ops',
      stats: { total: 10, byTile: { '9p': 5, '5m': 5 }, correct: 5 },
    });
    await seedProblem(db, 'NEXTONE1', { authorUid: 'ops' });
    await setupDaily('2026-10-21', 'OFFICIAL');
    await setupDaily('2026-10-22', 'NEXTONE1');
    const bsky = fakeAdapter('bluesky');
    const deps = { db, adapters: [bsky.adapter], siteUrl, bucketName: 'b', loadCard };

    await autoPostCore(deps, day1);
    const r = await autoPostCore(deps, day2);
    expect(r.repliedPlatforms).toEqual(['bluesky']);
    expect(r.postedProblemId).toBe('NEXTONE1');
    // 1 件目は日 1 の投稿、2 件目は返信、3 件目は日 2 の投稿
    expect(bsky.posts).toHaveLength(3);
    const reply = bsky.posts[1];
    expect(reply.replyTo).toEqual({ id: 'at://1', uri: 'at://1', cid: 'cid' });
    expect(reply.text).toContain('【昨日の何切る 答え合わせ】');
    expect(reply.text).toContain('正解率 50%');
    expect(reply.text).toContain('https://x.example/p/OFFICIAL');
    expect(reply.image).toBeUndefined();

    expect((await db.collection('daily').doc('2026-10-21').get()).get('answerReplies.bluesky')).toBe(true);
    const again = await autoPostCore(deps, day2);
    expect(again.repliedPlatforms).toEqual([]);
    expect(bsky.posts).toHaveLength(3);
  });

  test('3 軸が割れている問題を優先して投稿する。非表示・通報ありは除く', async () => {
    await seedProblem(db, 'SINGLE01', { authorUid: 'a', answer: { byAxis: { speed: ['9p'], points: ['9p'], balance: ['9p'] }, ukeire: { kinds: 1, total: 1 }, shanten: 0, engineVersion: 't' }, stats: { total: 50, byTile: {}, correct: 25 } });
    await seedProblem(db, 'SPLIT001', { authorUid: 'b', stats: { total: 50, byTile: {}, correct: 25 } });
    await seedProblem(db, 'REPORT01', { authorUid: 'c', reports: 2 });
    await setupDaily('2026-10-21', 'SINGLE01', ['SPLIT001', 'REPORT01']);
    const d = fakeAdapter('discord');
    const r = await autoPostCore({ db, adapters: [d.adapter], siteUrl, bucketName: 'b', loadCard }, day1);
    expect(r.postedProblemId).toBe('SPLIT001');
  });

  test('daily が無い・投稿先が無い・カードが無い場合', async () => {
    const d = fakeAdapter('discord');
    const none = await autoPostCore({ db, adapters: [d.adapter], siteUrl, bucketName: 'b', loadCard }, day1);
    expect(none.postedProblemId).toBeNull();
    expect(d.posts).toHaveLength(0);

    await seedProblem(db, 'OFFICIAL', { authorUid: 'ops' });
    await setupDaily('2026-10-21', 'OFFICIAL');
    await autoPostCore({ db, adapters: [d.adapter], siteUrl, bucketName: 'b', loadCard: async () => null }, day1);
    expect(d.posts[0].image).toBeUndefined();
    expect(d.posts[0].text).toContain('/p/OFFICIAL');
  });
});

describe('weeklyDigestCore', () => {
  const sunday = new Date('2026-10-25T11:00:00Z'); // JST 日曜 20:00
  const loadCard = async () => null;

  test('今週の難問 TOP3 を投稿し、通知を送り、結果を保存する。再実行は何もしない', async () => {
    // 今週（10-19〜10-25）の daily
    await db.collection('daily').doc('2026-10-20').set({ official: 'HARD0001', picks: ['MID00001'] });
    await db.collection('daily').doc('2026-10-23').set({ official: 'EASY0001', picks: ['HARD0002'] });
    // 範囲外の daily
    await db.collection('daily').doc('2026-10-18').set({ official: 'OLD00001', picks: [] });
    const stat = (total: number, correct: number) => ({ total, correct, byTile: { '9p': correct, '5m': total - correct } });
    await seedProblem(db, 'HARD0001', { stats: stat(100, 10) });
    await seedProblem(db, 'HARD0002', { stats: stat(50, 15) });
    await seedProblem(db, 'MID00001', { stats: stat(40, 20) });
    await seedProblem(db, 'EASY0001', { stats: stat(40, 36) });
    await seedProblem(db, 'OLD00001', { stats: stat(100, 1) });

    const d = fakeAdapter('discord');
    const notified: Array<[string, string, string]> = [];
    const deps = {
      db,
      adapters: [d.adapter],
      siteUrl: 'https://x.example',
      bucketName: 'b',
      loadCard,
      notifyWeekly: async (title: string, body: string, pid: string) => void notified.push([title, body, pid]),
    };
    const r = await weeklyDigestCore(deps, sunday);
    expect(r.top).toEqual(['HARD0001', 'HARD0002', 'MID00001']);
    expect(r.postedPlatforms).toEqual(['discord']);
    expect(d.posts[0].text).toContain('【今週の難問 TOP3】');
    expect(d.posts[0].text).toContain('1. 正解率 10%（100人）');
    expect(d.posts[0].text).toContain('/p/HARD0001');
    expect(d.posts[0].text).not.toContain('OLD00001');
    // 速さ軸の解 9p を選んだ人 vs 打点軸の解 5m を選んだ人
    expect(d.posts[0].text).toContain('速さ派');
    expect(notified).toHaveLength(1);
    expect(notified[0][2]).toBe('HARD0001');

    const weekly = (await db.collection('weekly').doc('2026-10-25').get()).data()!;
    expect(weekly.top).toEqual(['HARD0001', 'HARD0002', 'MID00001']);
    expect(weekly.posts.discord).toEqual({ id: 'discord-1' });

    expect((await weeklyDigestCore(deps, sunday)).skipped).toBe(true);
    expect(d.posts).toHaveLength(1);
  });

  test('対象の問題が無ければ投稿しない', async () => {
    const d = fakeAdapter('discord');
    const r = await weeklyDigestCore(
      { db, adapters: [d.adapter], siteUrl: 'https://x.example', bucketName: 'b', loadCard, notifyWeekly: async () => {} },
      sunday,
    );
    expect(r.top).toEqual([]);
    expect(d.posts).toHaveLength(0);
  });
});
