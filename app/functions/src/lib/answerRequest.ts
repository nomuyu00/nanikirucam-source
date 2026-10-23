import { isProblemId } from './problemId';
import { FINGERPRINT_PATTERN } from './stats';
import { isTileLabel } from './tiles';

export interface ParsedAnswerBody {
  problemId: string;
  tile: string;
  source: 'web' | 'app';
  /** Web のときの端末 ID。アプリのときは null（uid を ID トークンから取る）。 */
  fingerprint: string | null;
  selfRank: number | null;
}

export type ParseAnswerResult =
  | { ok: true; value: ParsedAnswerBody }
  | { ok: false; code: string; message: string };

/** `answerProblem` のリクエスト本文を検査する。 */
export function parseAnswerBody(body: unknown): ParseAnswerResult {
  if (typeof body !== 'object' || body === null) {
    return { ok: false, code: 'invalid_request', message: 'JSON object body is required' };
  }
  const b = body as Record<string, unknown>;
  if (!isProblemId(b.problemId)) {
    return { ok: false, code: 'invalid_problem_id', message: 'problemId must be 8 base62 chars' };
  }
  if (!isTileLabel(b.tile)) {
    return { ok: false, code: 'invalid_tile', message: 'tile must be a tile label' };
  }
  if (b.source !== 'web' && b.source !== 'app') {
    return { ok: false, code: 'invalid_source', message: 'source must be web or app' };
  }
  let fingerprint: string | null = null;
  if (b.source === 'web') {
    if (typeof b.fingerprint !== 'string' || !FINGERPRINT_PATTERN.test(b.fingerprint)) {
      return {
        ok: false,
        code: 'invalid_fingerprint',
        message: 'fingerprint must match [A-Za-z0-9_-]{16,64} for web',
      };
    }
    fingerprint = b.fingerprint;
  }
  let selfRank: number | null = null;
  if (b.selfRank !== undefined && b.selfRank !== null) {
    if (!Number.isInteger(b.selfRank) || (b.selfRank as number) < 1 || (b.selfRank as number) > 14) {
      return { ok: false, code: 'invalid_self_rank', message: 'selfRank must be an integer 1..14' };
    }
    selfRank = b.selfRank as number;
  }
  return {
    ok: true,
    value: { problemId: b.problemId, tile: b.tile, source: b.source, fingerprint, selfRank },
  };
}

/** `Authorization: Bearer <token>` からトークンを取り出す。 */
export function bearerToken(header: string | undefined | null): string | null {
  if (!header) return null;
  const match = /^Bearer\s+(\S+)$/i.exec(header.trim());
  return match ? match[1] : null;
}
