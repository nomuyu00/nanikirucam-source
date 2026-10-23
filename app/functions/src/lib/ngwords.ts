/**
 * 出題者名（ニックネーム）の検査。
 *
 * 公開問題には出題者名が載る。荒らし・なりすまし・リンクスパムを防ぐため、
 * 正規化（全角半角・大文字小文字・カタカナ→ひらがな・記号と空白の除去）した上で
 * NG ワードの部分一致を見る。ここは最低限の一覧で、運用で追加していく前提。
 */

/** 暴力・性的・差別的な語（正規化後のひらがな／小文字／漢字のまま書く）。 */
const OFFENSIVE_WORDS: readonly string[] = [
  '死ね',
  '氏ね',
  '殺す',
  '殺害',
  '自殺',
  '強姦',
  '朝鮮人',
  '非国民',
  '池沼',
  '基地外',
  'しんじまえ',
  'しねよ',
  'しにやがれ',
  'ころす',
  'ころされ',
  'じさつ',
  'れいぷ',
  'せっくす',
  'ちんこ',
  'ちんぽ',
  'まんこ',
  'おっぱい',
  'がいじ',
  'きちがい',
  'ちょうせんじん',
  'ひこくみん',
  'ひとらー',
  'fuck',
  'shit',
  'nigg',
  'cunt',
  'whore',
  'bitch',
  'killyou',
];

/** 運営・公式になりすます語、連絡先や誘導の語。 */
const RESERVED_AND_SPAM_WORDS: readonly string[] = [
  '公式',
  '運営',
  '管理人',
  '事務局',
  '副業',
  '出会い',
  '稼げ',
  '儲か',
  'こうしき',
  'うんえい',
  'かんりにん',
  'じむきょく',
  'さぽーと',
  'official',
  'admin',
  'moderator',
  'support',
  'staff',
  'なにきるかむ',
  'nanikiru',
  'http',
  'どっとこむ',
  'ふくぎょう',
  'もうかる',
  'かせげ',
  'であい',
  'らいんこうかん',
  'らいんid',
  'らいんあどれす',
];

const ALL_WORDS: readonly string[] = [...OFFENSIVE_WORDS, ...RESERVED_AND_SPAM_WORDS];

/** URL・メール・メンションに見える文字列（正規化前の文字列に対して検査する）。 */
const LINK_LIKE = /(@|＠|https?:|www\.|\.(com|net|org|jp|co|io|me|ly|gg)\b)/i;

/** 全角半角をそろえ、カタカナをひらがなにし、文字と数字以外（空白・記号・ゼロ幅）を落とす。 */
export function normalizeForNgCheck(input: string): string {
  const nfkc = input.normalize('NFKC').toLowerCase();
  let out = '';
  for (const ch of nfkc) {
    const code = ch.codePointAt(0) as number;
    // カタカナ（ァ..ヶ）→ ひらがな
    const folded =
      code >= 0x30a1 && code <= 0x30f6 ? String.fromCodePoint(code - 0x60) : ch;
    // 文字・数字以外は捨てる（長音符は残さない）
    if (/[\p{L}\p{N}]/u.test(folded)) out += folded;
  }
  return out;
}

export function containsNgWord(input: string): boolean {
  if (LINK_LIKE.test(input.normalize('NFKC'))) return true;
  const normalized = normalizeForNgCheck(input);
  return ALL_WORDS.some((word) => normalized.includes(word));
}

/** ニックネームの最大文字数（コードポイント数）。 */
export const NICKNAME_MAX_LENGTH = 20;

export type NicknameCheck =
  | { ok: true; value: string }
  | { ok: false; reason: 'too_long' | 'control_chars' | 'ng_word' };

/** 前後の空白を除き、長さ・制御文字・NG ワードを検査する。空文字は呼び出し側で扱う。 */
export function checkNickname(raw: string): NicknameCheck {
  const value = raw.normalize('NFC').trim();
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2066-\u2069\ufeff]/.test(value)) {
    return { ok: false, reason: 'control_chars' };
  }
  if ([...value].length > NICKNAME_MAX_LENGTH) return { ok: false, reason: 'too_long' };
  if (containsNgWord(value)) return { ok: false, reason: 'ng_word' };
  return { ok: true, value };
}
