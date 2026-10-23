import { checkNickname } from './ngwords';
import {
  countKinds,
  isRedFive,
  isTileLabel,
  tileKind,
} from './tiles';

/** 公開リクエストの検証エラー。`reason` は API.md に載せる機械可読のコード。 */
export class ValidationError extends Error {
  constructor(
    public readonly reason: ValidationReason,
    message: string,
    public readonly field?: string,
  ) {
    super(message);
    this.name = 'ValidationError';
  }
}

export type ValidationReason =
  | 'invalid_request'
  | 'invalid_tiles'
  | 'too_many_same_tile'
  | 'too_many_red'
  | 'invalid_meld'
  | 'invalid_dora'
  | 'invalid_wind'
  | 'invalid_turn'
  | 'invalid_answer'
  | 'invalid_nickname'
  | 'ng_word';

export type Wind = 'east' | 'south' | 'west' | 'north';
export const WINDS: readonly Wind[] = ['east', 'south', 'west', 'north'];

/** アプリの `MeldInput`（lib/analysis/hand_input.dart）と同じ種類名。 */
export type MeldKind = 'chi' | 'pon' | 'minkan' | 'ankan';
export const MELD_KINDS: readonly MeldKind[] = ['chi', 'pon', 'minkan', 'ankan'];

export interface MeldInput {
  kind: MeldKind;
  tiles: string[];
}

export type Axis = 'speed' | 'points' | 'balance';
export const AXES: readonly Axis[] = ['speed', 'points', 'balance'];

export interface AnswerInput {
  byAxis: Record<Axis, string[]>;
  ukeire: { kinds: number; total: number };
  shanten: number;
  engineVersion: string;
}

export interface ProblemInput {
  /** 手牌（副露を除く）。ツモ牌が最後（`tsumoIndex` で指定されたら最後に移す）。長さは 14 - 3×副露数。 */
  tiles: string[];
  /** ドラ表示牌（ドラそのものではない）。0〜5 枚。 */
  dora: string[];
  seatWind: Wind;
  roundWind: Wind;
  turn: number | null;
  melds: MeldInput[];
  locale: 'ja' | 'en';
  nickname: string | null;
  answer: AnswerInput;
}

/** 同種（赤5 は通常の 5 と同じ）の最大枚数。 */
export const MAX_SAME_TILE = 4;
export const MAX_DORA_INDICATORS = 5;
export const MAX_TURN = 18;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function fail(reason: ValidationReason, message: string, field?: string): never {
  throw new ValidationError(reason, message, field);
}

function parseLabels(
  value: unknown,
  field: string,
  reason: ValidationReason,
  min: number,
  max: number,
): string[] {
  if (!Array.isArray(value)) fail(reason, `${field} must be an array`, field);
  if (value.length < min || value.length > max) {
    fail(reason, `${field} must have ${min}..${max} items`, field);
  }
  for (const item of value) {
    if (!isTileLabel(item)) fail(reason, `${field} has an invalid tile label`, field);
  }
  return [...(value as string[])];
}

function parseWind(value: unknown, field: string, fallback: Wind): Wind {
  if (value === undefined || value === null) return fallback;
  if (typeof value !== 'string' || !(WINDS as readonly string[]).includes(value)) {
    fail('invalid_wind', `${field} must be one of ${WINDS.join('|')}`, field);
  }
  return value as Wind;
}

function parseMelds(value: unknown): MeldInput[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) fail('invalid_meld', 'melds must be an array', 'melds');
  if (value.length > 4) fail('invalid_meld', 'melds must have at most 4 items', 'melds');
  return value.map((raw, i) => {
    const field = `melds[${i}]`;
    if (!isRecord(raw)) fail('invalid_meld', `${field} must be an object`, field);
    const kind = raw.kind;
    if (typeof kind !== 'string' || !(MELD_KINDS as readonly string[]).includes(kind)) {
      fail('invalid_meld', `${field}.kind must be one of ${MELD_KINDS.join('|')}`, field);
    }
    const isKan = kind === 'minkan' || kind === 'ankan';
    const size = isKan ? 4 : 3;
    const tiles = parseLabels(raw.tiles, `${field}.tiles`, 'invalid_meld', size, size);
    const kinds = tiles.map(tileKind);
    if (kind === 'chi') {
      const suit = kinds[0][1];
      if (suit === 'z' || kinds.some((k) => k[1] !== suit)) {
        fail('invalid_meld', `${field} chi must be one numbered suit`, field);
      }
      const nums = kinds.map((k) => Number(k[0])).sort((a, b) => a - b);
      if (nums[1] !== nums[0] + 1 || nums[2] !== nums[1] + 1) {
        fail('invalid_meld', `${field} chi must be consecutive`, field);
      }
    } else if (kinds.some((k) => k !== kinds[0])) {
      fail('invalid_meld', `${field} must be the same tile`, field);
    }
    return { kind: kind as MeldKind, tiles };
  });
}

function parseAnswer(value: unknown, handKinds: ReadonlySet<string>): AnswerInput {
  if (!isRecord(value)) fail('invalid_answer', 'answer must be an object', 'answer');
  const byAxisRaw = value.byAxis;
  if (!isRecord(byAxisRaw)) fail('invalid_answer', 'answer.byAxis must be an object', 'answer.byAxis');
  const byAxis = {} as Record<Axis, string[]>;
  for (const axis of AXES) {
    const labels = parseLabels(byAxisRaw[axis], `answer.byAxis.${axis}`, 'invalid_answer', 1, 14);
    if (new Set(labels).size !== labels.length) {
      fail('invalid_answer', `answer.byAxis.${axis} has duplicates`, `answer.byAxis.${axis}`);
    }
    if (labels.some((label) => !handKinds.has(tileKind(label)))) {
      fail(
        'invalid_answer',
        `answer.byAxis.${axis} must be tiles in the hand`,
        `answer.byAxis.${axis}`,
      );
    }
    byAxis[axis] = labels;
  }
  const ukeire = value.ukeire;
  if (
    !isRecord(ukeire) ||
    !Number.isInteger(ukeire.kinds) ||
    !Number.isInteger(ukeire.total) ||
    (ukeire.kinds as number) < 0 ||
    (ukeire.kinds as number) > 34 ||
    (ukeire.total as number) < 0 ||
    (ukeire.total as number) > 136
  ) {
    fail('invalid_answer', 'answer.ukeire must be {kinds:0..34,total:0..136}', 'answer.ukeire');
  }
  const shanten = value.shanten;
  if (!Number.isInteger(shanten) || (shanten as number) < -1 || (shanten as number) > 8) {
    fail('invalid_answer', 'answer.shanten must be an integer -1..8', 'answer.shanten');
  }
  const engineVersion = value.engineVersion;
  if (typeof engineVersion !== 'string' || !/^[A-Za-z0-9._+/:@-]{1,40}$/.test(engineVersion)) {
    fail('invalid_answer', 'answer.engineVersion is invalid', 'answer.engineVersion');
  }
  return {
    byAxis,
    ukeire: { kinds: ukeire.kinds as number, total: ukeire.total as number },
    shanten: shanten as number,
    engineVersion: engineVersion as string,
  };
}

/**
 * 同種 5 枚以上・赤5 の重複を検査する。手牌・副露・ドラ表示牌をすべて数える。
 * 赤5 は通常の 5 と同じ種類として数え、各色（萬・筒・索）の赤5 は 1 枚まで。
 */
export function checkTileCounts(groups: readonly (readonly string[])[]): void {
  const all = groups.flat();
  for (const [kind, count] of countKinds(all)) {
    if (count > MAX_SAME_TILE) {
      fail('too_many_same_tile', `${kind} appears ${count} times (max ${MAX_SAME_TILE})`);
    }
  }
  const redCount = new Map<string, number>();
  for (const label of all) {
    if (isRedFive(label)) redCount.set(label, (redCount.get(label) ?? 0) + 1);
  }
  for (const [label, count] of redCount) {
    if (count > 1) fail('too_many_red', `${label} appears ${count} times (max 1)`);
  }
}

/** `publishProblem` のリクエスト本文を検証して正規化する。 */
export function parseProblemInput(data: unknown): ProblemInput {
  if (!isRecord(data)) fail('invalid_request', 'request must be an object');

  const melds = parseMelds(data.melds);
  const expected = 14 - 3 * melds.length;

  let tiles = parseLabels(data.tiles, 'tiles', 'invalid_tiles', 1, 14);
  // ツモ牌の位置（アプリの `tsumoIndex`）。指定があればその牌を最後に移す。
  if (data.tsumoIndex !== undefined && data.tsumoIndex !== null) {
    const idx = data.tsumoIndex;
    if (!Number.isInteger(idx) || (idx as number) < 0 || (idx as number) >= tiles.length) {
      fail('invalid_tiles', 'tsumoIndex is out of range', 'tsumoIndex');
    }
    const draw = tiles[idx as number];
    tiles = [...tiles.slice(0, idx as number), ...tiles.slice((idx as number) + 1), draw];
  }
  if (tiles.length !== expected) {
    fail(
      'invalid_tiles',
      `tiles must have ${expected} items (14 - 3 x melds), got ${tiles.length}`,
      'tiles',
    );
  }

  const dora = data.dora === undefined || data.dora === null
    ? []
    : parseLabels(data.dora, 'dora', 'invalid_dora', 0, MAX_DORA_INDICATORS);

  checkTileCounts([tiles, melds.flatMap((m) => m.tiles), dora]);

  const seatWind = parseWind(data.seatWind, 'seatWind', 'south');
  const roundWind = parseWind(data.roundWind, 'roundWind', 'east');

  let turn: number | null = null;
  if (data.turn !== undefined && data.turn !== null) {
    if (!Number.isInteger(data.turn) || (data.turn as number) < 1 || (data.turn as number) > MAX_TURN) {
      fail('invalid_turn', `turn must be an integer 1..${MAX_TURN}`, 'turn');
    }
    turn = data.turn as number;
  }

  const locale = data.locale === 'en' ? 'en' : 'ja';
  if (data.locale !== undefined && data.locale !== null && data.locale !== 'ja' && data.locale !== 'en') {
    fail('invalid_request', 'locale must be ja|en', 'locale');
  }

  let nickname: string | null = null;
  if (data.nickname !== undefined && data.nickname !== null) {
    if (typeof data.nickname !== 'string') {
      fail('invalid_nickname', 'nickname must be a string', 'nickname');
    }
    const checked = checkNickname(data.nickname);
    if (!checked.ok) {
      fail(
        checked.reason === 'ng_word' ? 'ng_word' : 'invalid_nickname',
        `nickname rejected: ${checked.reason}`,
        'nickname',
      );
    }
    nickname = checked.value === '' ? null : checked.value;
  }

  const handKinds = new Set(tiles.map(tileKind));
  const answer = parseAnswer(data.answer, handKinds);

  return {
    tiles,
    dora,
    seatWind,
    roundWind,
    turn,
    melds,
    locale,
    nickname,
    answer,
  };
}
