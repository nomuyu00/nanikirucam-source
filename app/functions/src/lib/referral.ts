import { randomInt } from 'node:crypto';

/** 読み間違えやすい文字（I, O, 0, 1）を除いた 32 文字。 */
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export const REFERRAL_CODE_LENGTH = 8;

export function generateReferralCode(random: (max: number) => number = randomInt): string {
  let code = '';
  for (let i = 0; i < REFERRAL_CODE_LENGTH; i++) code += ALPHABET[random(ALPHABET.length)];
  return code;
}

const CODE_PATTERN = new RegExp(`^[${ALPHABET}]{${REFERRAL_CODE_LENGTH}}$`);

/** 入力を大文字にして空白・ハイフンを除く（入力のゆれを吸収する）。 */
export function normalizeReferralCode(input: unknown): string | null {
  if (typeof input !== 'string') return null;
  const code = input.normalize('NFKC').toUpperCase().replace(/[\s-]/g, '');
  return CODE_PATTERN.test(code) ? code : null;
}

export function isReferralCode(value: unknown): value is string {
  return typeof value === 'string' && CODE_PATTERN.test(value);
}
