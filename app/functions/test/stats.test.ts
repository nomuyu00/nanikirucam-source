import { bearerToken, parseAnswerBody } from '../src/lib/answerRequest';
import {
  accuracy,
  applyAnswerToStats,
  emptyStats,
  fingerprintHash,
  isSingleAnswer,
  judgeAnswer,
  milestoneReached,
  normalizeStats,
} from '../src/lib/stats';

const answer = {
  byAxis: { speed: ['9p'], points: ['9p', '5m'], balance: ['9p'] },
};

describe('stats の更新ロジック', () => {
  test('空の stats に回答を 1 件反映する', () => {
    const s = applyAnswerToStats(emptyStats(), '9p', true);
    expect(s).toEqual({ total: 1, byTile: { '9p': 1 }, correct: 1 });
  });

  test('不正解は correct を増やさない。引数は書き換えない', () => {
    const before = { total: 3, byTile: { '9p': 2, '1m': 1 }, correct: 2 };
    const snapshot = JSON.parse(JSON.stringify(before));
    const after = applyAnswerToStats(before, '1m', false);
    expect(after).toEqual({ total: 4, byTile: { '9p': 2, '1m': 2 }, correct: 2 });
    expect(before).toEqual(snapshot);
  });

  test('赤5 と通常の 5 は別のキーで数える', () => {
    let s = emptyStats();
    s = applyAnswerToStats(s, '5m', false);
    s = applyAnswerToStats(s, '0m', false);
    expect(s.byTile).toEqual({ '5m': 1, '0m': 1 });
  });

  test('normalizeStats は欠損や型崩れを 0 扱いにする', () => {
    expect(normalizeStats(undefined)).toEqual(emptyStats());
    expect(normalizeStats({ total: 'x', correct: -3, byTile: { a: 'z', b: 2, c: 0 } })).toEqual({
      total: 0,
      correct: 0,
      byTile: { b: 2 },
    });
  });

  test('正解率', () => {
    expect(accuracy({ total: 0, correct: 0 })).toBeNull();
    expect(accuracy({ total: 4, correct: 1 })).toBe(0.25);
  });
});

describe('judgeAnswer（3 軸）', () => {
  test('各軸の解に含まれるか', () => {
    expect(judgeAnswer(answer, '9p')).toEqual({ speed: true, points: true, balance: true });
    expect(judgeAnswer(answer, '5m')).toEqual({ speed: false, points: true, balance: false });
    expect(judgeAnswer(answer, '1z')).toEqual({ speed: false, points: false, balance: false });
  });

  test('赤5 は通常の 5 と同一視する', () => {
    expect(judgeAnswer(answer, '0m').points).toBe(true);
    expect(judgeAnswer({ byAxis: { speed: ['0p'], points: ['0p'], balance: ['0p'] } }, '5p').balance).toBe(
      true,
    );
  });

  test('3 軸が同じ牌の集合なら一択', () => {
    expect(isSingleAnswer(answer)).toBe(false);
    expect(
      isSingleAnswer({ byAxis: { speed: ['9p'], points: ['9p'], balance: ['9p'] } }),
    ).toBe(true);
    // 順序や赤5 の違いは同じ扱い
    expect(
      isSingleAnswer({ byAxis: { speed: ['5m', '9p'], points: ['9p', '0m'], balance: ['9p', '5m'] } }),
    ).toBe(true);
  });
});

describe('回答数の節目（10 / 50 / 100）', () => {
  test('到達した瞬間だけ節目を返す', () => {
    expect(milestoneReached(9, 10)).toBe(10);
    expect(milestoneReached(10, 11)).toBeNull();
    expect(milestoneReached(49, 50)).toBe(50);
    expect(milestoneReached(99, 100)).toBe(100);
    expect(milestoneReached(100, 101)).toBeNull();
    expect(milestoneReached(0, 1)).toBeNull();
  });

  test('1 件ずつ増やすと 10・50・100 でちょうど 3 回', () => {
    const hits: number[] = [];
    for (let n = 0; n < 150; n++) {
      const m = milestoneReached(n, n + 1);
      if (m) hits.push(m);
    }
    expect(hits).toEqual([10, 50, 100]);
  });
});

describe('fingerprint（二重回答の判定）', () => {
  test('同じ入力は同じハッシュ、種類（web/app）が違えば別', () => {
    const a = fingerprintHash('web', 'abcdefghijklmnop');
    expect(a).toMatch(/^[0-9a-f]{40}$/);
    expect(fingerprintHash('web', 'abcdefghijklmnop')).toBe(a);
    expect(fingerprintHash('app', 'abcdefghijklmnop')).not.toBe(a);
    expect(fingerprintHash('web', 'abcdefghijklmnoq')).not.toBe(a);
  });
});

describe('answerProblem のリクエスト検査', () => {
  const web = {
    problemId: 'AbC12345',
    tile: '9p',
    source: 'web',
    fingerprint: 'abcdefghijklmnop',
  };

  test('web: fingerprint 必須', () => {
    const ok = parseAnswerBody(web);
    expect(ok.ok).toBe(true);
    const bad = parseAnswerBody({ ...web, fingerprint: 'short' });
    expect(bad).toMatchObject({ ok: false, code: 'invalid_fingerprint' });
    expect(parseAnswerBody({ ...web, fingerprint: undefined })).toMatchObject({
      ok: false,
      code: 'invalid_fingerprint',
    });
  });

  test('app: fingerprint は不要（uid を ID トークンから取る）', () => {
    const r = parseAnswerBody({ problemId: 'AbC12345', tile: '9p', source: 'app', selfRank: 3 });
    expect(r).toEqual({
      ok: true,
      value: { problemId: 'AbC12345', tile: '9p', source: 'app', fingerprint: null, selfRank: 3 },
    });
  });

  test('不正な値を拒否する', () => {
    expect(parseAnswerBody(null)).toMatchObject({ ok: false, code: 'invalid_request' });
    expect(parseAnswerBody({ ...web, problemId: 'x' })).toMatchObject({
      ok: false,
      code: 'invalid_problem_id',
    });
    expect(parseAnswerBody({ ...web, tile: '0b' })).toMatchObject({ ok: false, code: 'invalid_tile' });
    expect(parseAnswerBody({ ...web, source: 'bot' })).toMatchObject({
      ok: false,
      code: 'invalid_source',
    });
    expect(parseAnswerBody({ ...web, selfRank: 15 })).toMatchObject({
      ok: false,
      code: 'invalid_self_rank',
    });
  });

  test('Bearer トークンの取り出し', () => {
    expect(bearerToken('Bearer abc.def')).toBe('abc.def');
    expect(bearerToken('bearer abc')).toBe('abc');
    expect(bearerToken('Basic abc')).toBeNull();
    expect(bearerToken(undefined)).toBeNull();
    expect(bearerToken('Bearer')).toBeNull();
  });
});
