/**
 * 通報者のアカウントが、通報を件数に数えられる古さか。
 * `createdAtMs` は `users/{uid}.createdAt`（ミリ秒）。users が無い・作成日時が不明なら数えない。
 * ちょうど最小年齢になった時点から数える（以上）。
 */
export function isReporterEligible(
  createdAtMs: number | null | undefined,
  nowMs: number,
  minAgeMs: number,
): boolean {
  if (createdAtMs === null || createdAtMs === undefined || !Number.isFinite(createdAtMs)) {
    return false;
  }
  return nowMs - createdAtMs >= minAgeMs;
}
