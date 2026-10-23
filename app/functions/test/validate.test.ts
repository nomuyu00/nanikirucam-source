import { parseProblemInput, ValidationError } from '../src/lib/validate';
import type { ValidationReason } from '../src/lib/validate';
import { sampleRequest } from './fixtures';

const answerOf = (...tiles: string[]) => ({
  byAxis: { speed: tiles, points: tiles, balance: tiles },
  ukeire: { kinds: 1, total: 3 },
  shanten: 0,
  engineVersion: 't/1',
});

function reasonOf(data: unknown): ValidationReason | null {
  try {
    parseProblemInput(data);
    return null;
  } catch (err) {
    if (err instanceof ValidationError) return err.reason;
    throw err;
  }
}

describe('parseProblemInput: 牌列', () => {
  test('14 枚（ツモ牌は最後）を受け付ける', () => {
    const input = parseProblemInput(sampleRequest());
    expect(input.tiles).toHaveLength(14);
    expect(input.tiles[13]).toBe('9p');
    expect(input.seatWind).toBe('south');
    expect(input.roundWind).toBe('east');
    expect(input.turn).toBe(6);
    expect(input.locale).toBe('ja');
    expect(input.nickname).toBe('まじゃおう');
  });

  test('tsumoIndex を指定すると、その牌を最後（ツモ牌の位置）に移す', () => {
    const tiles = [...(sampleRequest().tiles as string[])];
    // 4 枚目の 5m をツモ牌として指定（アプリの HandInput.toJson と同じ形）
    const input = parseProblemInput(sampleRequest({ tiles, tsumoIndex: 3 }));
    expect(input.tiles).toHaveLength(14);
    expect(input.tiles[13]).toBe('5m');
    expect(input.tiles.slice(0, 13)).toEqual(tiles.filter((_, i) => i !== 3));
    // すでに最後ならそのまま
    expect(parseProblemInput(sampleRequest({ tsumoIndex: 13 })).tiles).toEqual(tiles);
  });

  test('tsumoIndex が範囲外・整数でなければ拒否。null・省略は最後の牌をツモ牌とみなす', () => {
    expect(reasonOf(sampleRequest({ tsumoIndex: 14 }))).toBe('invalid_tiles');
    expect(reasonOf(sampleRequest({ tsumoIndex: -1 }))).toBe('invalid_tiles');
    expect(reasonOf(sampleRequest({ tsumoIndex: 1.5 }))).toBe('invalid_tiles');
    expect(parseProblemInput(sampleRequest({ tsumoIndex: null })).tiles[13]).toBe('9p');
    expect(parseProblemInput(sampleRequest()).tiles[13]).toBe('9p');
  });

  test('アプリの HandInput.toJson() をそのまま受け付ける（余分な項目は無視）', () => {
    const input = parseProblemInput({
      v: 1,
      tiles: sampleRequest().tiles,
      tsumoIndex: 13,
      dora: ['3z'],
      seatWind: 'east',
      roundWind: 'east',
      dealer: true,
      turn: 3,
      visible: ['1z'],
      answer: sampleRequest().answer,
    });
    expect(input.seatWind).toBe('east');
    expect(input.turn).toBe(3);
  });

  test('13 枚だけ（ツモ牌なし）は拒否', () => {
    const tiles = (sampleRequest().tiles as string[]).slice(0, 13);
    expect(reasonOf(sampleRequest({ tiles }))).toBe('invalid_tiles');
  });

  test('15 枚は拒否', () => {
    const tiles = [...(sampleRequest().tiles as string[]), '1s'];
    expect(reasonOf(sampleRequest({ tiles }))).toBe('invalid_tiles');
  });

  test('裏（0b）と未知のラベルは拒否', () => {
    const tiles = [...(sampleRequest().tiles as string[])];
    tiles[0] = '0b';
    expect(reasonOf(sampleRequest({ tiles }))).toBe('invalid_tiles');
    tiles[0] = '8z';
    expect(reasonOf(sampleRequest({ tiles }))).toBe('invalid_tiles');
  });

  test('tiles が配列でない・未指定は拒否', () => {
    expect(reasonOf(sampleRequest({ tiles: 'abc' }))).toBe('invalid_tiles');
    expect(reasonOf({})).toBe('invalid_tiles');
    expect(reasonOf(null)).toBe('invalid_request');
    expect(reasonOf('x')).toBe('invalid_request');
    expect(reasonOf([])).toBe('invalid_request');
  });

  test('同種 5 枚以上は拒否', () => {
    const tiles = ['1m', '1m', '1m', '1m', '1m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z'];
    expect(reasonOf(sampleRequest({ tiles, dora: [] }))).toBe('too_many_same_tile');
  });

  test('同種 4 枚までは受け付ける', () => {
    const tiles = ['1m', '1m', '1m', '1m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z'];
    expect(reasonOf(sampleRequest({ tiles, dora: [], answer: answerOf('2z') }))).toBeNull();
  });

  test('赤5 と通常の 5 は同じ種類として数える（合計 5 枚は拒否）', () => {
    const tiles = ['0m', '5m', '5m', '5m', '5m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z'];
    expect(reasonOf(sampleRequest({ tiles, dora: [] }))).toBe('too_many_same_tile');
  });

  test('赤は各色 1 枚まで（0m が 2 枚は拒否、0m と 0p は可）', () => {
    const dup = ['0m', '0m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '1z', '1z'];
    expect(reasonOf(sampleRequest({ tiles: dup, dora: [] }))).toBe('too_many_red');
    const ok = ['0m', '0p', '0s', '3m', '4p', '6p', '7s', '8s', '9s', '2z', '2z', '1z', '1z', '4z'];
    expect(reasonOf(sampleRequest({ tiles: ok, dora: [], answer: answerOf('4z') }))).toBeNull();
  });

  test('ドラ表示牌も 4 枚の上限に数える', () => {
    const tiles = ['3z', '3z', '3z', '3z', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z'];
    expect(reasonOf(sampleRequest({ tiles, dora: ['3z'] }))).toBe('too_many_same_tile');
  });
});

describe('parseProblemInput: 副露・ドラ・風・巡目', () => {
  test('副露があると手牌は 14 - 3×副露数 枚', () => {
    const melds = [{ kind: 'pon', tiles: ['5z', '5z', '5z'] }];
    const tiles = ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s'];
    const input = parseProblemInput(sampleRequest({ tiles, melds, dora: [], answer: answerOf('9s') }));
    expect(input.melds).toHaveLength(1);
    // 14 枚のままだと副露分が余る
    expect(
      reasonOf(sampleRequest({ tiles: sampleRequest().tiles, melds, dora: [] })),
    ).toBe('invalid_tiles');
  });

  test('カン（4 枚）は 3 枚ぶんとして数える', () => {
    const melds = [{ kind: 'ankan', tiles: ['5z', '5z', '5z', '5z'] }];
    const tiles = ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s'];
    expect(reasonOf(sampleRequest({ tiles, melds, dora: [], answer: answerOf('9s') }))).toBeNull();
  });

  test('順子は同色の連続した 3 枚（赤5 可）', () => {
    const ok = [{ kind: 'chi', tiles: ['3s', '0s', '4s'] }];
    const tiles = ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s'];
    expect(reasonOf(sampleRequest({ tiles, melds: ok, dora: [], answer: answerOf('9s') }))).toBeNull();
    for (const bad of [
      { kind: 'chi', tiles: ['1m', '2m', '4m'] }, // 連続していない
      { kind: 'chi', tiles: ['1m', '2m', '3p'] }, // 色が違う
      { kind: 'chi', tiles: ['1z', '2z', '3z'] }, // 字牌
      { kind: 'pon', tiles: ['1m', '1m', '2m'] },
      { kind: 'pon', tiles: ['1m', '1m', '1m', '1m'] }, // ポンは 3 枚
      { kind: 'minkan', tiles: ['1m', '1m', '1m'] }, // カンは 4 枚
      { kind: 'ankan', tiles: ['1m', '1m', '1m', '2m'] },
      { kind: 'pair', tiles: ['1m', '1m'] },
      { type: 'koutsu', tiles: ['1m', '1m', '1m'], open: true }, // 旧形式（kind がない）
    ]) {
      expect(reasonOf(sampleRequest({ tiles, melds: [bad], dora: [], answer: answerOf('9s') }))).toBe('invalid_meld');
    }
  });

  test('副露は 4 組まで', () => {
    const m = { kind: 'pon', tiles: ['5z', '5z', '5z'] };
    expect(reasonOf(sampleRequest({ melds: [m, m, m, m, m] }))).toBe('invalid_meld');
  });

  test('ドラ表示牌は 0〜5 枚の牌ラベル', () => {
    expect(reasonOf(sampleRequest({ dora: [] }))).toBeNull();
    expect(reasonOf(sampleRequest({ dora: undefined }))).toBeNull();
    expect(reasonOf(sampleRequest({ dora: ['1z', '2z', '3z', '4z', '5z', '6z'] }))).toBe(
      'invalid_dora',
    );
    expect(reasonOf(sampleRequest({ dora: ['9z'] }))).toBe('invalid_dora');
  });

  test('風は east|south|west|north、省略時は 東場・南家', () => {
    const input = parseProblemInput(sampleRequest({ seatWind: undefined, roundWind: undefined }));
    expect(input.seatWind).toBe('south');
    expect(input.roundWind).toBe('east');
    expect(reasonOf(sampleRequest({ seatWind: 'ton' }))).toBe('invalid_wind');
    expect(reasonOf(sampleRequest({ roundWind: 1 }))).toBe('invalid_wind');
  });

  test('巡目は 1〜18 の整数、省略可', () => {
    expect(parseProblemInput(sampleRequest({ turn: undefined })).turn).toBeNull();
    expect(parseProblemInput(sampleRequest({ turn: null })).turn).toBeNull();
    for (const bad of [0, 19, 1.5, '6']) {
      expect(reasonOf(sampleRequest({ turn: bad }))).toBe('invalid_turn');
    }
  });

  test('locale は ja|en、省略時 ja', () => {
    expect(parseProblemInput(sampleRequest({ locale: undefined })).locale).toBe('ja');
    expect(parseProblemInput(sampleRequest({ locale: 'en' })).locale).toBe('en');
    expect(reasonOf(sampleRequest({ locale: 'fr' }))).toBe('invalid_request');
  });
});

describe('parseProblemInput: 出題者名', () => {
  test('NG ワードは拒否', () => {
    expect(reasonOf(sampleRequest({ nickname: '運営' }))).toBe('ng_word');
    expect(reasonOf(sampleRequest({ nickname: 'ｆｕｃｋ' }))).toBe('ng_word');
    expect(reasonOf(sampleRequest({ nickname: 'http://evil.example' }))).toBe('ng_word');
  });

  test('長すぎる名前・制御文字は拒否', () => {
    expect(reasonOf(sampleRequest({ nickname: 'あ'.repeat(21) }))).toBe('invalid_nickname');
    expect(reasonOf(sampleRequest({ nickname: 'ab\u0000c' }))).toBe('invalid_nickname');
    expect(reasonOf(sampleRequest({ nickname: 'ab‮c' }))).toBe('invalid_nickname');
    expect(reasonOf(sampleRequest({ nickname: 123 }))).toBe('invalid_nickname');
  });

  test('空・省略は null（既定名はサーバーが決める）', () => {
    expect(parseProblemInput(sampleRequest({ nickname: '   ' })).nickname).toBeNull();
    expect(parseProblemInput(sampleRequest({ nickname: undefined })).nickname).toBeNull();
  });

  test('前後の空白は除く。20 文字ちょうどは可', () => {
    expect(parseProblemInput(sampleRequest({ nickname: '  たろう  ' })).nickname).toBe('たろう');
    expect(parseProblemInput(sampleRequest({ nickname: 'あ'.repeat(20) })).nickname).toHaveLength(20);
  });
});

describe('parseProblemInput: answer', () => {
  const answer = (patch: Record<string, unknown>) => ({
    ...(sampleRequest().answer as Record<string, unknown>),
    ...patch,
  });

  test('正しい answer を受け付ける', () => {
    const input = parseProblemInput(sampleRequest());
    expect(input.answer.byAxis.points).toEqual(['9p', '5m']);
    expect(input.answer.engineVersion).toBe('nanikiru-engine/0.1.0');
  });

  test('answer が無い・形が違うと拒否', () => {
    expect(reasonOf(sampleRequest({ answer: undefined }))).toBe('invalid_answer');
    expect(reasonOf(sampleRequest({ answer: answer({ byAxis: undefined }) }))).toBe('invalid_answer');
    expect(
      reasonOf(sampleRequest({ answer: answer({ byAxis: { speed: ['9p'], points: ['9p'] } }) })),
    ).toBe('invalid_answer');
  });

  test('解の牌が手牌にないと拒否（赤5 は通常の 5 と同一視）', () => {
    const byAxis = { speed: ['9p'], points: ['9p'], balance: ['1z'] };
    expect(reasonOf(sampleRequest({ answer: answer({ byAxis }) }))).toBe('invalid_answer');
    // 手牌に 5m があるので 0m も同じ種類として許す
    const red = { speed: ['0m'], points: ['0m'], balance: ['0m'] };
    expect(reasonOf(sampleRequest({ answer: answer({ byAxis: red }) }))).toBeNull();
  });

  test('解が空・重複は拒否', () => {
    expect(
      reasonOf(sampleRequest({ answer: answer({ byAxis: { speed: [], points: ['9p'], balance: ['9p'] } }) })),
    ).toBe('invalid_answer');
    expect(
      reasonOf(
        sampleRequest({
          answer: answer({ byAxis: { speed: ['9p', '9p'], points: ['9p'], balance: ['9p'] } }),
        }),
      ),
    ).toBe('invalid_answer');
  });

  test('ukeire / shanten / engineVersion の範囲', () => {
    expect(reasonOf(sampleRequest({ answer: answer({ ukeire: { kinds: 35, total: 1 } }) }))).toBe(
      'invalid_answer',
    );
    expect(reasonOf(sampleRequest({ answer: answer({ ukeire: { kinds: 1, total: -1 } }) }))).toBe(
      'invalid_answer',
    );
    expect(reasonOf(sampleRequest({ answer: answer({ shanten: -2 }) }))).toBe('invalid_answer');
    expect(reasonOf(sampleRequest({ answer: answer({ shanten: 1.5 }) }))).toBe('invalid_answer');
    expect(reasonOf(sampleRequest({ answer: answer({ engineVersion: '' }) }))).toBe('invalid_answer');
    expect(reasonOf(sampleRequest({ answer: answer({ engineVersion: 'a b' }) }))).toBe(
      'invalid_answer',
    );
    expect(reasonOf(sampleRequest({ answer: answer({ shanten: -1 }) }))).toBeNull();
  });
});
