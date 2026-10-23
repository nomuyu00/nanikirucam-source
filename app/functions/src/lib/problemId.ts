import { randomInt } from 'node:crypto';

const BASE62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

export const PROBLEM_ID_LENGTH = 8;

/**
 * 8 文字の base62 の問題 ID を作る。62^8 ≒ 2.2e14 通り。
 * `random` は [0, max) の整数を返す関数（テストで差し替える）。
 */
export function generateProblemId(random: (max: number) => number = randomInt): string {
  let id = '';
  for (let i = 0; i < PROBLEM_ID_LENGTH; i++) {
    id += BASE62[random(BASE62.length)];
  }
  return id;
}

const PROBLEM_ID_PATTERN = /^[0-9A-Za-z]{8}$/;

export function isProblemId(value: unknown): value is string {
  return typeof value === 'string' && PROBLEM_ID_PATTERN.test(value);
}

/**
 * リクエストのパスから問題 ID を取り出す。`/p/AbC12345`、`/p/AbC12345/` のほか、
 * エミュレータの関数 URL のように前に別のパスが付く場合にも対応する。
 */
export function extractProblemIdFromPath(path: string): string | null {
  const match = /(?:^|\/)p\/([0-9A-Za-z]{8})\/?$/.exec(path);
  return match ? match[1] : null;
}
