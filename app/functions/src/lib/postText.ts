import { accuracy, isSingleAnswer } from './stats';
import type { Stats } from './stats';
import { tileNameJa } from './tiles';
import type { Axis, AnswerInput, Wind } from './validate';

export type Platform = 'bluesky' | 'threads' | 'discord' | 'x';

/** 各投稿先の文字数上限。 */
export const PLATFORM_LIMITS: Record<Platform, number> = {
  bluesky: 300, // グラフェム数
  threads: 500,
  discord: 2000,
  x: 280, // 重み付き（日本語は 1 文字 2、URL は 23）
};

const WIND_JA: Record<Wind, string> = { east: '東', south: '南', west: '西', north: '北' };
export const AXIS_NAME_JA: Record<Axis, string> = {
  speed: '最速',
  points: '高打点',
  balance: 'バランス',
};

const HASHTAGS = '#何切る #麻雀';

const segmenter =
  typeof Intl !== 'undefined' && 'Segmenter' in Intl
    ? new Intl.Segmenter('ja', { granularity: 'grapheme' })
    : null;

/** 文字列のグラフェム数。 */
export function graphemeLength(text: string): number {
  if (!segmenter) return [...text].length;
  let n = 0;
  for (const _ of segmenter.segment(text)) {
    void _;
    n++;
  }
  return n;
}

const URL_PATTERN = /https?:\/\/\S+/g;

/** X の重み付き文字数（日本語などは 2、URL は 23 固定）。 */
export function xWeightedLength(text: string): number {
  let total = 0;
  const withoutUrls = text.replace(URL_PATTERN, () => {
    total += 23;
    return '';
  });
  for (const ch of withoutUrls) {
    const c = ch.codePointAt(0) as number;
    const light =
      c <= 0x10ff ||
      (c >= 0x2000 && c <= 0x200d) ||
      (c >= 0x2010 && c <= 0x201f) ||
      (c >= 0x2032 && c <= 0x2037);
    total += light ? 1 : 2;
  }
  return total;
}

export function measure(platform: Platform, text: string): number {
  switch (platform) {
    case 'bluesky':
      return graphemeLength(text);
    case 'x':
      return xWeightedLength(text);
    default:
      return [...text].length;
  }
}

interface Line {
  text: string;
  /** 省略できる行は大きいほど先に削る。0 は必須。 */
  drop: number;
}

/** 行を並べ、上限を超えるときは `drop` の大きい行から削る。必須行だけでも超えるなら先頭行を切り詰める。 */
export function composeText(platform: Platform, lines: readonly Line[]): string {
  const limit = PLATFORM_LIMITS[platform];
  const kept = [...lines];
  const join = (ls: readonly Line[]) => ls.map((l) => l.text).join('\n');
  while (measure(platform, join(kept)) > limit) {
    let idx = -1;
    let best = 0;
    kept.forEach((l, i) => {
      if (l.drop > best) {
        best = l.drop;
        idx = i;
      }
    });
    if (idx < 0) break;
    kept.splice(idx, 1);
  }
  let text = join(kept);
  if (measure(platform, text) > limit && kept.length > 0) {
    // 必須行だけでも超える場合は先頭行を切り詰める
    const rest = join(kept.slice(1));
    const head = [...kept[0].text];
    const build = () => `${head.join('')}…${rest ? `\n${rest}` : ''}`;
    while (head.length > 1 && measure(platform, build()) > limit) head.pop();
    text = build();
  }
  return text;
}

export interface PostProblem {
  tiles: readonly string[];
  dora: readonly string[];
  seatWind: Wind;
  roundWind: Wind;
  turn: number | null;
}

function infoLine(p: PostProblem): string {
  const parts = [`${WIND_JA[p.roundWind]}場 ${WIND_JA[p.seatWind]}家`];
  if (p.turn) parts.push(`${p.turn}巡目`);
  return parts.join(' ');
}

function doraLine(p: PostProblem): string | null {
  if (p.dora.length === 0) return null;
  return `ドラ表示牌: ${p.dora.map(tileNameJa).join(' ')}`;
}

/** 毎日の問題の投稿文（答えは書かない）。 */
export function buildProblemPost(
  platform: Platform,
  problem: PostProblem,
  url: string,
  title = '今日の何切る',
): string {
  const dora = doraLine(problem);
  return composeText(platform, [
    { text: `【${title}】`, drop: 0 },
    { text: infoLine(problem) + (dora ? ` / ${dora}` : ''), drop: 2 },
    { text: 'この手、何を切る？ 回答はリンクから。ログイン不要で、みんなの結果が見られます。', drop: 1 },
    { text: url, drop: 0 },
    { text: HASHTAGS, drop: 3 },
  ]);
}

/** 画像の代替テキスト（手牌を読み上げ用に列挙する。答えは含めない）。 */
export function buildAltText(problem: PostProblem): string {
  const dora = doraLine(problem);
  return [
    `麻雀の何切る問題。手牌: ${problem.tiles.map(tileNameJa).join(' ')}`,
    infoLine(problem),
    dora,
  ]
    .filter((s): s is string => Boolean(s))
    .join('。');
}

export interface ReplyProblem {
  answer: Pick<AnswerInput, 'byAxis'>;
  stats: Pick<Stats, 'total' | 'correct'>;
}

function axisAnswerLines(answer: Pick<AnswerInput, 'byAxis'>): string {
  const names = (axis: Axis) => answer.byAxis[axis].map(tileNameJa).join('・');
  if (isSingleAnswer(answer)) return `3つの解が一致（一択）: ${names('balance')}`;
  return (['balance', 'speed', 'points'] as const)
    .map((axis) => `${AXIS_NAME_JA[axis]}: ${names(axis)}`)
    .join(' / ');
}

/** 翌日の「答え合わせ」返信。 */
export function buildAnswerReply(
  platform: Platform,
  problem: ReplyProblem,
  url: string,
): string {
  const rate = accuracy(problem.stats);
  const rateLine =
    rate === null
      ? null
      : `正解率 ${Math.round(rate * 100)}%（回答 ${problem.stats.total}人、バランス軸の解を正解として集計）`;
  return composeText(platform, [
    { text: '【昨日の何切る 答え合わせ】', drop: 0 },
    { text: axisAnswerLines(problem.answer), drop: 0 },
    ...(rateLine ? [{ text: rateLine, drop: 1 }] : []),
    { text: 'なぜその牌か、どの役が狙えるかはアプリの解説で。', drop: 2 },
    { text: url, drop: 0 },
  ]);
}

export interface WeeklyItem {
  url: string;
  rate: number;
  total: number;
}

/** 週間まとめ（今週の難問 TOP3 と、打点派 vs 速さ派）。 */
export function buildWeeklyPost(
  platform: Platform,
  items: readonly WeeklyItem[],
  ratioSpeed: number | null,
): string {
  const lines: Line[] = [{ text: '【今週の難問 TOP3】', drop: 0 }];
  items.slice(0, 3).forEach((item, i) => {
    lines.push({
      text: `${i + 1}. 正解率 ${Math.round(item.rate * 100)}%（${item.total}人）\n${item.url}`,
      drop: i === 0 ? 0 : i + 1, // 3位 → 2位 の順に削る
    });
  });
  if (ratioSpeed !== null) {
    const speed = Math.round(ratioSpeed * 100);
    lines.push({ text: `速さ派 ${speed}% vs 打点派 ${100 - speed}%（答えが分かれた問題の回答より）`, drop: 4 });
  }
  lines.push({ text: HASHTAGS, drop: 5 });
  return composeText(platform, lines);
}
