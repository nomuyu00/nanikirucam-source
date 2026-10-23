import {
  buildAltText,
  buildAnswerReply,
  buildProblemPost,
  buildWeeklyPost,
  composeText,
  graphemeLength,
  measure,
  PLATFORM_LIMITS,
  xWeightedLength,
} from '../src/lib/postText';
import type { Platform, PostProblem } from '../src/lib/postText';

const PLATFORMS: Platform[] = ['bluesky', 'threads', 'discord', 'x'];
const URL = 'https://nanikiru-cam.web.app/p/AbC12345';

const problem: PostProblem = {
  tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '9p'],
  dora: ['3z'],
  seatWind: 'south',
  roundWind: 'east',
  turn: 6,
};

describe('文字数の数え方', () => {
  test('グラフェム数（絵文字・結合文字を 1 と数える）', () => {
    expect(graphemeLength('abc')).toBe(3);
    expect(graphemeLength('あいう')).toBe(3);
    expect(graphemeLength('👨‍👩‍👧')).toBe(1);
    expect(graphemeLength('é')).toBe(1);
  });

  test('X の重み付き: 日本語は 2、ASCII は 1、URL は 23', () => {
    expect(xWeightedLength('abc')).toBe(3);
    expect(xWeightedLength('あい')).toBe(4);
    expect(xWeightedLength(URL)).toBe(23);
    expect(xWeightedLength(`あ ${URL}`)).toBe(2 + 1 + 23);
  });
});

describe('毎日の問題の投稿文', () => {
  test.each(PLATFORMS)('%s: 上限内に収まり、URL とハッシュタグを含み、答えを含まない', (platform) => {
    const text = buildProblemPost(platform, problem, URL);
    expect(measure(platform, text)).toBeLessThanOrEqual(PLATFORM_LIMITS[platform]);
    expect(text).toContain('【今日の何切る】');
    expect(text).toContain(URL);
    expect(text).toContain('東場 南家 6巡目');
    expect(text).toContain('ドラ表示牌: 西');
    expect(text).toContain('#何切る');
  });

  test('X は 280 の重みに収めるため、優先度の低い行から削る（URL は必ず残る）', () => {
    const text = buildProblemPost('x', problem, URL);
    expect(xWeightedLength(text)).toBeLessThanOrEqual(280);
    expect(text).toContain(URL);
    expect(text.startsWith('【今日の何切る】')).toBe(true);
  });

  test('タイトルを変えられる', () => {
    expect(buildProblemPost('discord', problem, URL, '今週の難問')).toContain('【今週の難問】');
  });

  test('出題の情報が無い（巡目・ドラなし）ときも崩れない', () => {
    const text = buildProblemPost('bluesky', { ...problem, turn: null, dora: [] }, URL);
    expect(text).toContain('東場 南家');
    expect(text).not.toContain('巡目');
    expect(text).not.toContain('ドラ表示牌');
  });
});

describe('翌日の答え合わせ返信', () => {
  const reply = {
    answer: { byAxis: { speed: ['9p'], points: ['5m', '0m'], balance: ['9p'] } },
    stats: { total: 132, correct: 63 },
  };

  test('3 軸の解が割れていれば軸ごとに書く。正解率と回答数を入れる', () => {
    const text = buildAnswerReply('bluesky', reply, URL);
    expect(text).toContain('【昨日の何切る 答え合わせ】');
    expect(text).toContain('バランス: 9筒');
    expect(text).toContain('最速: 9筒');
    expect(text).toContain('高打点: 5萬・赤5萬');
    expect(text).toContain('正解率 48%');
    expect(text).toContain('回答 132人');
    expect(text).toContain(URL);
    expect(graphemeLength(text)).toBeLessThanOrEqual(300);
  });

  test('一致していれば「一択」', () => {
    const text = buildAnswerReply(
      'threads',
      { ...reply, answer: { byAxis: { speed: ['9p'], points: ['9p'], balance: ['9p'] } } },
      URL,
    );
    expect(text).toContain('3つの解が一致（一択）: 9筒');
    expect(text).not.toContain('最速:');
  });

  test('回答がなければ正解率の行を出さない', () => {
    const text = buildAnswerReply('discord', { ...reply, stats: { total: 0, correct: 0 } }, URL);
    expect(text).not.toContain('正解率');
  });

  test.each(PLATFORMS)('%s: 上限内', (platform) => {
    const text = buildAnswerReply(platform, reply, URL);
    expect(measure(platform, text)).toBeLessThanOrEqual(PLATFORM_LIMITS[platform]);
    expect(text).toContain(URL);
  });
});

describe('週間まとめの投稿文', () => {
  const items = [
    { url: 'https://nanikiru-cam.web.app/p/aaaaaaaa', rate: 0.21, total: 120 },
    { url: 'https://nanikiru-cam.web.app/p/bbbbbbbb', rate: 0.33, total: 80 },
    { url: 'https://nanikiru-cam.web.app/p/cccccccc', rate: 0.4, total: 60 },
  ];

  test('TOP3 と速さ派・打点派の割合を含む', () => {
    const text = buildWeeklyPost('discord', items, 0.62);
    expect(text).toContain('【今週の難問 TOP3】');
    expect(text).toContain('1. 正解率 21%（120人）');
    expect(text).toContain('3. 正解率 40%（60人）');
    expect(text).toContain('速さ派 62% vs 打点派 38%');
  });

  test.each(PLATFORMS)('%s: 上限内。1 位の URL は必ず残る', (platform) => {
    const text = buildWeeklyPost(platform, items, 0.5);
    expect(measure(platform, text)).toBeLessThanOrEqual(PLATFORM_LIMITS[platform]);
    expect(text).toContain(items[0].url);
  });

  test('割合が null なら行を出さない', () => {
    expect(buildWeeklyPost('discord', items, null)).not.toContain('速さ派');
  });
});

describe('composeText', () => {
  test('必須行だけで上限を超えるときは先頭行を切り詰めて「…」を付ける', () => {
    const long = 'あ'.repeat(400);
    const text = composeText('bluesky', [
      { text: long, drop: 0 },
      { text: URL, drop: 0 },
    ]);
    expect(graphemeLength(text)).toBeLessThanOrEqual(300);
    expect(text).toContain('…');
    expect(text.endsWith(URL)).toBe(true);
  });
});

describe('画像の代替テキスト', () => {
  test('手牌を読み上げ用に列挙し、答えは含めない', () => {
    const alt = buildAltText(problem);
    expect(alt).toContain('1萬 2萬 3萬 5萬 6萬 4筒');
    expect(alt).toContain('東場 南家 6巡目');
    expect(alt).toContain('ドラ表示牌: 西');
  });
});
