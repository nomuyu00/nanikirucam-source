export type Lang = 'ja' | 'en';

/**
 * 言語の決定。`?lang=ja|en` を優先し、なければ `Accept-Language` で
 * 英語が日本語より先に来るときだけ英語。それ以外は日本語。
 */
export function pickLang(acceptLanguage: string | undefined | null, queryLang?: unknown): Lang {
  if (queryLang === 'en' || queryLang === 'ja') return queryLang;
  if (!acceptLanguage) return 'ja';
  const entries = acceptLanguage
    .split(',')
    .map((part, index) => {
      const [tag, ...params] = part.trim().split(';');
      const q = params.map((p) => p.trim()).find((p) => p.startsWith('q='));
      const weight = q ? Number(q.slice(2)) : 1;
      return { tag: tag.toLowerCase(), weight: Number.isFinite(weight) ? weight : 0, index };
    })
    .filter((e) => e.tag && e.weight > 0)
    .sort((a, b) => b.weight - a.weight || a.index - b.index);
  for (const e of entries) {
    if (e.tag === 'ja' || e.tag.startsWith('ja-')) return 'ja';
    if (e.tag === 'en' || e.tag.startsWith('en-')) return 'en';
  }
  return 'ja';
}

/** Web 問題ページの文言。サーバー側の HTML と、クライアント JS の両方で使う。 */
export interface Strings {
  appName: string;
  title: string;
  description: string;
  tapHint: string;
  handLabel: string;
  tsumoLabel: string;
  meldLabel: string;
  doraLabel: string;
  authorLabel: string;
  round: Record<'east' | 'south' | 'west' | 'north', string>;
  seat: Record<'east' | 'south' | 'west' | 'north', string>;
  turn: string; // {n} を置換
  correct: string;
  alternative: string; // {axis}
  incorrect: string;
  answeredBefore: string;
  distribution: string;
  answerCount: string; // {n}
  accuracy: string; // {p}
  solutions: string;
  singleAnswer: string;
  axis: Record<'speed' | 'points' | 'balance', string>;
  shanten: Record<string, string>;
  shantenN: string; // {n}
  ukeire: string; // {kinds} {total}
  ctaTitle: string;
  ctaBody: string;
  ctaButton: string;
  appStore: string;
  googlePlay: string;
  errorGeneric: string;
  disclaimer: string;
  terms: string;
  privacy: string;
  tokushoho: string;
  notFoundTitle: string;
  notFoundBody: string;
  toTop: string;
  you: string;
  noscript: string;
}

const ja: Strings = {
  appName: 'なにきるカム',
  title: 'この手、何切る？',
  description:
    'あなたならどの牌を切る？ ログイン不要で回答して、みんなの結果と3つの解（最速・高打点・バランス）を見よう。',
  tapHint: '切る牌をタップして回答（ログイン不要）',
  handLabel: '手牌',
  tsumoLabel: 'ツモ',
  meldLabel: '副露',
  doraLabel: 'ドラ表示牌',
  authorLabel: '出題',
  round: { east: '東場', south: '南場', west: '西場', north: '北場' },
  seat: { east: '東家', south: '南家', west: '西家', north: '北家' },
  turn: '{n}巡目',
  correct: '正解！',
  alternative: '別の解です（{axis}の解）',
  incorrect: 'ざんねん…',
  answeredBefore: 'この問題には回答済みです',
  distribution: 'みんなの回答',
  answerCount: '{n}人が回答',
  accuracy: '正解率 {p}%',
  solutions: '3つの解',
  singleAnswer: '3つの解が一致（一択）',
  axis: { speed: '最速', points: '高打点', balance: 'バランス' },
  shanten: { '-1': '和了', '0': 'テンパイ' },
  shantenN: '{n}向聴',
  ukeire: '受け入れ {kinds}種{total}枚',
  ctaTitle: 'なぜその牌？ どの役が狙える？',
  ctaBody:
    '狙える役・想定打点・上がりやすさの解説はアプリで。カメラをかざすだけで、実際の卓でも使えます。',
  ctaButton: '解説をアプリで見る',
  appStore: 'App Store で入手',
  googlePlay: 'Google Play で入手',
  errorGeneric: '通信に失敗しました。時間をおいてもう一度お試しください。',
  disclaimer:
    '解は受け入れ枚数と役・打点の計算に基づくもので、他家の河や状況は考慮していません。',
  terms: '利用規約',
  privacy: 'プライバシーポリシー',
  tokushoho: '特定商取引法に基づく表記',
  notFoundTitle: 'この問題は見つかりません',
  notFoundBody: '削除されたか、リンクが正しくない可能性があります。',
  toTop: 'トップページへ',
  you: 'あなた',
  noscript: '回答には JavaScript を有効にしてください。',
};

const en: Strings = {
  appName: 'Nanikiru Cam',
  title: 'What would you discard?',
  description:
    'Which tile would you discard? Answer without signing in and see everyone’s results and the three solutions (fastest, highest value, balanced).',
  tapHint: 'Tap the tile you would discard (no sign-in needed)',
  handLabel: 'Hand',
  tsumoLabel: 'Draw',
  meldLabel: 'Melds',
  doraLabel: 'Dora indicator',
  authorLabel: 'By',
  round: { east: 'East round', south: 'South round', west: 'West round', north: 'North round' },
  seat: { east: 'East seat', south: 'South seat', west: 'West seat', north: 'North seat' },
  turn: 'Turn {n}',
  correct: 'Correct!',
  alternative: 'Another valid answer ({axis})',
  incorrect: 'Not quite…',
  answeredBefore: 'You have already answered this problem',
  distribution: 'Everyone’s answers',
  answerCount: '{n} answers',
  accuracy: '{p}% correct',
  solutions: 'Three solutions',
  singleAnswer: 'All three solutions agree',
  axis: { speed: 'Fastest', points: 'Highest value', balance: 'Balanced' },
  shanten: { '-1': 'Complete', '0': 'Tenpai' },
  shantenN: '{n}-shanten',
  ukeire: 'Ukeire: {kinds} kinds, {total} tiles',
  ctaTitle: 'Why that tile? Which yaku can you aim for?',
  ctaBody:
    'See the yaku you can aim for, expected points and win chances in the app. Point the camera at your hand and use it at a real table.',
  ctaButton: 'See the explanation in the app',
  appStore: 'Download on the App Store',
  googlePlay: 'Get it on Google Play',
  errorGeneric: 'Network error. Please try again later.',
  disclaimer:
    'Solutions are based on tile acceptance, yaku and point calculations. Opponents’ discards and the table situation are not considered.',
  terms: 'Terms of Service',
  privacy: 'Privacy Policy',
  tokushoho: 'Legal notice (Japan)',
  notFoundTitle: 'Problem not found',
  notFoundBody: 'It may have been removed, or the link may be wrong.',
  toTop: 'Back to top',
  you: 'You',
  noscript: 'Please enable JavaScript to answer.',
};

export function strings(lang: Lang): Strings {
  return lang === 'en' ? en : ja;
}

/** `{n}` のようなプレースホルダを置換する。 */
export function fmt(template: string, values: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (_, key: string) =>
    key in values ? String(values[key]) : `{${key}}`,
  );
}
