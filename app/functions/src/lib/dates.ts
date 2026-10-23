/** 日本時間（UTC+9、夏時間なし）での日付文字列 `YYYY-MM-DD`。 */
export function jstDate(now: Date): string {
  return new Date(now.getTime() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** `YYYY-MM-DD` に日数を足す（負数可）。 */
export function addDays(date: string, days: number): string {
  const [y, m, d] = date.split('-').map(Number);
  const t = Date.UTC(y, m - 1, d) + days * 24 * 60 * 60 * 1000;
  return new Date(t).toISOString().slice(0, 10);
}

/** 日本時間での曜日（0=日曜）。 */
export function jstWeekday(now: Date): number {
  return new Date(now.getTime() + 9 * 60 * 60 * 1000).getUTCDay();
}
