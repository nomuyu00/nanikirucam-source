import { FieldPath, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import type { PostImage, SocialAdapter } from '../lib/adapters/types';
import { addDays, jstDate } from '../lib/dates';
import { axisShare, rankHardest } from '../lib/daily';
import { buildAltText, buildWeeklyPost } from '../lib/postText';
import { accuracy, normalizeStats } from '../lib/stats';
import { cardPathFor, cardPublicUrl, problemUrl } from '../lib/storeLinks';
import type { AnswerInput } from '../lib/validate';
import { loadAnswers } from './privateAnswer';
import { COLLECTIONS, toSummary } from './types';

/** 難問に数える最低回答数。 */
export const WEEKLY_MIN_ANSWERS = 10;

export interface WeeklyDeps {
  db: Firestore;
  adapters: SocialAdapter[];
  siteUrl: string;
  bucketName: string;
  loadCard: (cardPath: string) => Promise<Uint8Array | null>;
  /** 週間通知（FCM トピック weekly）を送る。 */
  notifyWeekly: (title: string, body: string, topProblemId: string) => Promise<void>;
}

export interface WeeklyResult {
  date: string;
  skipped: boolean;
  top: string[];
  postedPlatforms: string[];
  errors: string[];
}

/**
 * 週間まとめ（`weeklyDigest` の本体）。
 * 直近 7 日に今日の問題として出た問題（公式 + 選出）から、正解率の低い順に TOP3 を選ぶ。
 * 速さ軸と打点軸で解が分かれた問題の回答から「速さ派 vs 打点派」の割合も出す。
 */
export async function weeklyDigestCore(deps: WeeklyDeps, now: Date = new Date()): Promise<WeeklyResult> {
  const { db } = deps;
  const date = jstDate(now);
  const result: WeeklyResult = { date, skipped: false, top: [], postedPlatforms: [], errors: [] };

  // 二重投稿を避けるため、先に枠を確保する（すでにあれば何もしない）
  const weeklyRef = db.collection(COLLECTIONS.weekly).doc(date);
  try {
    await weeklyRef.create({ startedAt: Timestamp.fromDate(now) });
  } catch {
    result.skipped = true;
    return result;
  }

  const weekStart = addDays(date, -6);
  const dailies = await db
    .collection(COLLECTIONS.daily)
    .where(FieldPath.documentId(), '>=', weekStart)
    .where(FieldPath.documentId(), '<=', date)
    .get();
  const ids = new Set<string>();
  for (const d of dailies.docs) {
    const official = d.get('official');
    if (typeof official === 'string') ids.add(official);
    for (const id of d.get('picks') ?? []) if (typeof id === 'string') ids.add(id);
  }
  const snaps = await Promise.all(
    [...ids].map((id) => db.collection(COLLECTIONS.problems).doc(id).get()),
  );
  const found = snaps.filter((s) => s.exists);
  // 正解は private/answer にある（「速さ派 vs 打点派」の集計に使う）
  const answers = await loadAnswers(
    db,
    found.map((s) => s.id),
  );
  const summaries = found.map((s) => toSummary(s.id, s.data() ?? {}, answers.get(s.id)));
  const top = rankHardest(summaries, WEEKLY_MIN_ANSWERS, 3);
  result.top = top.map((p) => p.id);
  if (top.length === 0) {
    await weeklyRef.update({ top: [], note: 'no eligible problems' });
    return result;
  }

  const share = axisShare(
    found
      .filter((s) => s.get('hidden') !== true && answers.has(s.id))
      .map((s) => ({
        answer: { byAxis: (answers.get(s.id) as AnswerInput).byAxis },
        byTile: normalizeStats(s.get('stats')).byTile,
      })),
  );

  const items = top.map((p) => ({
    url: problemUrl(deps.siteUrl, p.id),
    rate: accuracy(p.stats) ?? 0,
    total: p.stats.total,
  }));

  // 1 位の問題のカードを添える
  const hardest = found.find((s) => s.id === top[0].id);
  const cardPath = (hardest?.get('cardPath') as string | undefined) ?? cardPathFor(top[0].id);
  const bytes = await deps.loadCard(cardPath).catch(() => null);
  const image: PostImage | undefined = bytes
    ? {
        bytes,
        mimeType: 'image/png',
        alt: buildAltText({
          tiles: hardest?.get('tiles') ?? [],
          dora: hardest?.get('dora') ?? [],
          seatWind: hardest?.get('seatWind') ?? 'south',
          roundWind: hardest?.get('roundWind') ?? 'east',
          turn: hardest?.get('turn') ?? null,
        }),
        publicUrl: cardPublicUrl(deps.bucketName, cardPath),
      }
    : undefined;

  const posts: Record<string, unknown> = {};
  for (const adapter of deps.adapters) {
    try {
      const ref = await adapter.post({
        text: buildWeeklyPost(adapter.platform, items, share.ratioSpeed),
        image,
      });
      posts[adapter.platform] = { id: ref.id };
      result.postedPlatforms.push(adapter.platform);
    } catch (err) {
      logger.error(`weekly post failed (${adapter.platform})`, err);
      result.errors.push(`post:${adapter.platform}`);
    }
  }

  const hardestRate = Math.round((accuracy(top[0].stats) ?? 0) * 100);
  await deps
    .notifyWeekly(
      '今週の難問 TOP3',
      `一番の難問は正解率${hardestRate}%。あなたは解けますか？`,
      top[0].id,
    )
    .catch((err) => logger.warn('notifyWeekly failed', err));

  await weeklyRef.update({
    top: result.top,
    share: { speed: share.speed, points: share.points },
    posts,
    finishedAt: Timestamp.fromDate(new Date()),
  });
  return result;
}
