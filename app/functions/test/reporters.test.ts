import { isReporterEligible } from '../src/lib/reporters';

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const NOW = Date.UTC(2026, 9, 21, 12, 0, 0);

describe('通報者のアカウントの古さ（24 時間以上）', () => {
  test('24 時間以上たっていれば数える（ちょうど 24 時間も含む）', () => {
    expect(isReporterEligible(NOW - DAY, NOW, DAY)).toBe(true);
    expect(isReporterEligible(NOW - DAY - 1, NOW, DAY)).toBe(true);
    expect(isReporterEligible(NOW - 30 * DAY, NOW, DAY)).toBe(true);
  });

  test('24 時間未満は数えない', () => {
    expect(isReporterEligible(NOW - DAY + 1, NOW, DAY)).toBe(false);
    expect(isReporterEligible(NOW - HOUR, NOW, DAY)).toBe(false);
    expect(isReporterEligible(NOW, NOW, DAY)).toBe(false);
  });

  test('作成日時が未来（時計のずれ）・不明・users なしは数えない', () => {
    expect(isReporterEligible(NOW + HOUR, NOW, DAY)).toBe(false);
    expect(isReporterEligible(null, NOW, DAY)).toBe(false);
    expect(isReporterEligible(undefined, NOW, DAY)).toBe(false);
    expect(isReporterEligible(Number.NaN, NOW, DAY)).toBe(false);
  });

  test('最小年齢は引数で変えられる（config の値を渡す）', () => {
    expect(isReporterEligible(NOW - 2 * HOUR, NOW, HOUR)).toBe(true);
    expect(isReporterEligible(NOW - 2 * HOUR, NOW, 3 * HOUR)).toBe(false);
    expect(isReporterEligible(NOW - 1, NOW, 0)).toBe(true);
  });
});
