import type { ProblemInput } from '../src/lib/validate';

/** 14 枚（ツモ牌は最後の 9p）の標準的な問題。 */
export function sampleRequest(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '9p'],
    dora: ['3z'],
    seatWind: 'south',
    roundWind: 'east',
    turn: 6,
    melds: [],
    locale: 'ja',
    nickname: 'まじゃおう',
    answer: {
      byAxis: {
        speed: ['9p'],
        points: ['9p', '5m'],
        balance: ['9p'],
      },
      ukeire: { kinds: 8, total: 24 },
      shanten: 1,
      engineVersion: 'nanikiru-engine/0.1.0',
    },
    ...overrides,
  };
}

export function sampleInput(overrides: Partial<ProblemInput> = {}): ProblemInput {
  return {
    tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '9p'],
    dora: ['3z'],
    seatWind: 'south',
    roundWind: 'east',
    turn: 6,
    melds: [],
    locale: 'ja',
    nickname: 'まじゃおう',
    answer: {
      byAxis: { speed: ['9p'], points: ['9p', '5m'], balance: ['9p'] },
      ukeire: { kinds: 8, total: 24 },
      shanten: 1,
      engineVersion: 'nanikiru-engine/0.1.0',
    },
    ...overrides,
  };
}
