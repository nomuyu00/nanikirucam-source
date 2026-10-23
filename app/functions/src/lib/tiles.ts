/**
 * 牌ラベルの定義と補助関数。
 *
 * ラベルは assets/labels/tiles_labels.txt の 38 クラスと同じ表記:
 * `1m`..`9m`（萬）、`1p`..`9p`（筒）、`1s`..`9s`（索）、`1z`..`7z`（東南西北白發中）、
 * `0m` `0p` `0s`（赤5）、`0b`（裏）。
 * サーバーが受け付けるのは裏（`0b`）を除く 37 種。
 */

export const BACK_LABEL = '0b';

/** 受け付ける牌ラベル 37 種（萬・筒・索は 1..9 の後ろに赤5 `0x`）。 */
export const TILE_LABELS: readonly string[] = [
  ...(['m', 'p', 's'] as const).flatMap((suit) => [
    ...Array.from({ length: 9 }, (_, i) => `${i + 1}${suit}`),
    `0${suit}`,
  ]),
  ...Array.from({ length: 7 }, (_, i) => `${i + 1}z`),
];

/** 赤を普通の 5 と同一視した 34 種。並びは萬・筒・索・字。 */
export const TILE_KINDS: readonly string[] = [
  ...(['m', 'p', 's'] as const).flatMap((suit) =>
    Array.from({ length: 9 }, (_, i) => `${i + 1}${suit}`),
  ),
  ...Array.from({ length: 7 }, (_, i) => `${i + 1}z`),
];

const LABEL_SET: ReadonlySet<string> = new Set(TILE_LABELS);

export function isTileLabel(value: unknown): value is string {
  return typeof value === 'string' && LABEL_SET.has(value);
}

/** 赤5（`0m` など）を通常の 5 にそろえた種類キー。 */
export function tileKind(label: string): string {
  return label[0] === '0' ? `5${label[1]}` : label;
}

export function isRedFive(label: string): boolean {
  return label.length === 2 && label[0] === '0' && label[1] !== 'b';
}

/** 牌の並び順（萬・筒・索・字の順、同じ種類では赤5が通常の5の前）。 */
export function tileOrder(label: string): number {
  const kind = tileKind(label);
  const index = TILE_KINDS.indexOf(kind);
  return index * 2 + (isRedFive(label) ? 0 : 1);
}

export function compareTiles(a: string, b: string): number {
  return tileOrder(a) - tileOrder(b);
}

const HONORS_JA = ['東', '南', '西', '北', '白', '發', '中'] as const;
const HONORS_EN = ['East', 'South', 'West', 'North', 'White', 'Green', 'Red'] as const;
const SUIT_JA: Record<string, string> = { m: '萬', p: '筒', s: '索' };
const SUIT_EN: Record<string, string> = { m: 'Man', p: 'Pin', s: 'Sou' };

/** 例: `5m` → 5萬、`0p` → 赤5筒、`7z` → 中。 */
export function tileNameJa(label: string): string {
  if (label.length !== 2) return label;
  const [num, suit] = [label[0], label[1]];
  if (suit === 'z') {
    const n = Number(num);
    return n >= 1 && n <= 7 ? HONORS_JA[n - 1] : label;
  }
  const suitName = SUIT_JA[suit];
  if (!suitName) return label;
  return num === '0' ? `赤5${suitName}` : `${num}${suitName}`;
}

/** 例: `5m` → 5 Man、`0p` → Red 5 Pin、`7z` → Red。 */
export function tileNameEn(label: string): string {
  if (label.length !== 2) return label;
  const [num, suit] = [label[0], label[1]];
  if (suit === 'z') {
    const n = Number(num);
    return n >= 1 && n <= 7 ? HONORS_EN[n - 1] : label;
  }
  const suitName = SUIT_EN[suit];
  if (!suitName) return label;
  return num === '0' ? `Red 5 ${suitName}` : `${num} ${suitName}`;
}

export function tileName(label: string, lang: 'ja' | 'en'): string {
  return lang === 'en' ? tileNameEn(label) : tileNameJa(label);
}

/** Hosting 上の牌画像パス（`hosting/public/tiles/<label>.png`）。 */
export function tileImagePath(label: string): string {
  return `/tiles/${label}.png`;
}

/** ラベル配列を種類キーごとに数える（赤5 は通常の 5 と同じ種類）。 */
export function countKinds(labels: readonly string[]): Map<string, number> {
  const map = new Map<string, number>();
  for (const label of labels) {
    const kind = tileKind(label);
    map.set(kind, (map.get(kind) ?? 0) + 1);
  }
  return map;
}
