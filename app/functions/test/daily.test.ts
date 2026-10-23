import {
  axisShare,
  choosePostTarget,
  DEFAULT_PICK_OPTIONS,
  isPickEligible,
  rankHardest,
  selectUserPicks,
} from '../src/lib/daily';
import type { PickOptions, ProblemSummary } from '../src/lib/daily';

const SPLIT = { byAxis: { speed: ['9p'], points: ['5m'], balance: ['9p'] } };
const SINGLE = { byAxis: { speed: ['9p'], points: ['9p'], balance: ['9p'] } };

function problem(id: string, patch: Partial<ProblemSummary> = {}): ProblemSummary {
  return {
    id,
    authorUid: `u-${id}`,
    hidden: false,
    reports: 0,
    stats: { total: 30, correct: 15 },
    featuredDaily: null,
    posted: false,
    answer: SPLIT,
    ...patch,
  };
}

const opts = (patch: Partial<PickOptions> = {}): PickOptions => ({
  today: '2026-10-21',
  ...DEFAULT_PICK_OPTIONS,
  ...patch,
});

describe('pickDaily の選出条件', () => {
  test('条件を満たす問題は選べる', () => {
    expect(isPickEligible(problem('a'), opts())).toBe(true);
  });

  test('回答 20 未満は除外、20 ちょうどは可', () => {
    expect(isPickEligible(problem('a', { stats: { total: 19, correct: 10 } }), opts())).toBe(false);
    expect(isPickEligible(problem('a', { stats: { total: 20, correct: 10 } }), opts())).toBe(true);
  });

  test('正解率は 40〜60%（両端を含む）', () => {
    const at = (correct: number) => problem('a', { stats: { total: 100, correct } });
    expect(isPickEligible(at(39), opts())).toBe(false);
    expect(isPickEligible(at(40), opts())).toBe(true);
    expect(isPickEligible(at(60), opts())).toBe(true);
    expect(isPickEligible(at(61), opts())).toBe(false);
  });

  test('通報が 1 件でもあれば除外。hidden も除外', () => {
    expect(isPickEligible(problem('a', { reports: 1 }), opts())).toBe(false);
    expect(isPickEligible(problem('a', { hidden: true }), opts())).toBe(false);
  });

  test('直近 30 日に選ばれた問題は除外、30 日たてば可', () => {
    expect(isPickEligible(problem('a', { featuredDaily: '2026-10-20' }), opts())).toBe(false);
    expect(isPickEligible(problem('a', { featuredDaily: '2026-09-22' }), opts())).toBe(false);
    expect(isPickEligible(problem('a', { featuredDaily: '2026-09-21' }), opts())).toBe(true);
    expect(isPickEligible(problem('a', { featuredDaily: '2025-01-01' }), opts())).toBe(true);
  });

  test('除外 ID（公式に選んだ問題）は選ばない', () => {
    expect(isPickEligible(problem('a'), opts({ excludeIds: ['a'] }))).toBe(false);
  });

  test('2 問を選ぶ。3 軸の解が割れている問題を優先し、次に 50% に近い順', () => {
    const picks = selectUserPicks(
      [
        problem('single', { answer: SINGLE, stats: { total: 100, correct: 50 } }),
        problem('split-far', { stats: { total: 100, correct: 58 } }),
        problem('split-near', { stats: { total: 40, correct: 20 } }),
        problem('split-mid', { stats: { total: 40, correct: 18 } }),
      ],
      opts(),
    );
    expect(picks.map((p) => p.id)).toEqual(['split-near', 'split-mid']);
  });

  test('同じ出題者は 1 日 1 問まで', () => {
    const picks = selectUserPicks(
      [
        problem('a', { authorUid: 'same', stats: { total: 50, correct: 25 } }),
        problem('b', { authorUid: 'same', stats: { total: 40, correct: 20 } }),
        problem('c', { authorUid: 'other', stats: { total: 30, correct: 15 } }),
      ],
      opts(),
    );
    expect(picks.map((p) => p.id)).toEqual(['a', 'c']);
  });

  test('候補が足りなければ少ない数を返す。空でもよい', () => {
    expect(selectUserPicks([problem('a')], opts())).toHaveLength(1);
    expect(selectUserPicks([], opts())).toEqual([]);
    expect(
      selectUserPicks([problem('a', { stats: { total: 5, correct: 2 } })], opts()),
    ).toEqual([]);
  });

  test('同条件なら ID 順で決定的', () => {
    const list = ['d', 'b', 'c', 'a'].map((id) => problem(id));
    expect(selectUserPicks(list, opts({ count: 4 })).map((p) => p.id)).toEqual(['a', 'b', 'c', 'd']);
  });
});

describe('自動投稿の対象選び', () => {
  test('割れている問題 > 50% に近い > 回答数', () => {
    const target = choosePostTarget([
      problem('single', { answer: SINGLE }),
      problem('split-30', { stats: { total: 30, correct: 15 } }),
      problem('split-100', { stats: { total: 100, correct: 50 } }),
    ]);
    expect(target?.id).toBe('split-100');
  });

  test('投稿済み・hidden・通報ありは対象外', () => {
    expect(
      choosePostTarget([
        problem('a', { posted: true }),
        problem('b', { hidden: true }),
        problem('c', { reports: 2 }),
      ]),
    ).toBeNull();
  });

  test('回答の少ない公式問題も選べる', () => {
    expect(
      choosePostTarget([problem('official', { stats: { total: 0, correct: 0 }, authorUid: 'ops' })])?.id,
    ).toBe('official');
  });
});

describe('週間まとめ', () => {
  test('難問 TOP3 は正解率の低い順。回答が少ないものは除く', () => {
    const list = [
      problem('easy', { stats: { total: 50, correct: 45 } }),
      problem('hard', { stats: { total: 50, correct: 5 } }),
      problem('mid', { stats: { total: 50, correct: 20 } }),
      problem('few', { stats: { total: 3, correct: 0 } }),
      problem('hidden', { stats: { total: 50, correct: 0 }, hidden: true }),
      problem('harder', { stats: { total: 80, correct: 4 } }),
    ];
    expect(rankHardest(list, 10, 3).map((p) => p.id)).toEqual(['harder', 'hard', 'mid']);
  });

  test('速さ派 vs 打点派: 解が分かれた問題で、片方の軸にだけある牌の回答数を数える', () => {
    const share = axisShare([
      { answer: SPLIT, byTile: { '9p': 30, '5m': 10, '1z': 5 } },
      // 同じ解の問題は数えない
      { answer: SINGLE, byTile: { '9p': 100 } },
      // 赤5 は通常の 5 と同じ
      { answer: SPLIT, byTile: { '0m': 10, '9p': 10 } },
    ]);
    expect(share).toEqual({ speed: 40, points: 20, ratioSpeed: 40 / 60 });
  });

  test('対象がなければ割合は null', () => {
    expect(axisShare([{ answer: SINGLE, byTile: { '9p': 3 } }]).ratioSpeed).toBeNull();
  });
});
