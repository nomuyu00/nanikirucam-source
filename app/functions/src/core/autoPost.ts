import { Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import type { PostImage, PostRef, SocialAdapter } from '../lib/adapters/types';
import { addDays, jstDate } from '../lib/dates';
import { choosePostTarget } from '../lib/daily';
import { buildAltText, buildAnswerReply, buildProblemPost } from '../lib/postText';
import { cardPathFor, cardPublicUrl, problemUrl } from '../lib/storeLinks';
import type { AnswerInput } from '../lib/validate';
import { normalizeStats } from '../lib/stats';
import { loadAnswers, privateAnswerRef } from './privateAnswer';
import { COLLECTIONS, toSummary } from './types';

export interface AutoPostDeps {
  db: Firestore;
  adapters: SocialAdapter[];
  siteUrl: string;
  bucketName: string;
  /** Storage からカード PNG を読む。無ければ null。 */
  loadCard: (cardPath: string) => Promise<Uint8Array | null>;
}

export interface AutoPostResult {
  date: string;
  repliedPlatforms: string[];
  postedProblemId: string | null;
  postedPlatforms: string[];
  errors: string[];
}

function refOf(raw: unknown): PostRef | null {
  if (typeof raw !== 'object' || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (typeof r.id !== 'string') return null;
  return {
    id: r.id,
    ...(typeof r.uri === 'string' ? { uri: r.uri } : {}),
    ...(typeof r.cid === 'string' ? { cid: r.cid } : {}),
  };
}

/** Firestore に保存できる形（undefined を含めない）。 */
function storableRef(ref: PostRef): Record<string, string> {
  return { id: ref.id, ...(ref.uri ? { uri: ref.uri } : {}), ...(ref.cid ? { cid: ref.cid } : {}) };
}

/**
 * 毎日 19:00 の自動投稿（`autoPost` の本体）。
 * 1. 昨日投稿した問題の答え合わせを、投稿先ごとに返信する。
 * 2. 今日の問題（公式 + 選出 2 問）から 1 問を選び、カード PNG 付きで投稿する。
 * 投稿先ごとの結果は `daily/{date}.posts.<platform>` に保存するので、再実行しても
 * 投稿済みの先には二重投稿しない。
 */
export async function autoPostCore(deps: AutoPostDeps, now: Date = new Date()): Promise<AutoPostResult> {
  const { db, adapters } = deps;
  const date = jstDate(now);
  const result: AutoPostResult = {
    date,
    repliedPlatforms: [],
    postedProblemId: null,
    postedPlatforms: [],
    errors: [],
  };

  // --- 1. 昨日の答え合わせ ---
  const yesterday = addDays(date, -1);
  const yRef = db.collection(COLLECTIONS.daily).doc(yesterday);
  const ySnap = await yRef.get();
  const yPid = ySnap.get('postedProblemId');
  if (ySnap.exists && typeof yPid === 'string') {
    const pSnap = await db.collection(COLLECTIONS.problems).doc(yPid).get();
    const answerSnap = pSnap.exists ? await privateAnswerRef(db, yPid).get() : null;
    if (pSnap.exists && pSnap.get('hidden') !== true && answerSnap?.exists) {
      const url = problemUrl(deps.siteUrl, yPid);
      const problem = {
        answer: answerSnap.data() as AnswerInput,
        stats: normalizeStats(pSnap.get('stats')),
      };
      for (const adapter of adapters) {
        const platform = adapter.platform;
        const parent = refOf(ySnap.get(`posts.${platform}`));
        if (!parent || ySnap.get(`answerReplies.${platform}`) === true) continue;
        try {
          await adapter.post({ text: buildAnswerReply(platform, problem, url), replyTo: parent });
          await yRef.update({ [`answerReplies.${platform}`]: true });
          result.repliedPlatforms.push(platform);
        } catch (err) {
          logger.error(`reply failed (${platform})`, err);
          result.errors.push(`reply:${platform}`);
        }
      }
    }
  }

  // --- 2. 今日の問題を投稿 ---
  const dailyRef = db.collection(COLLECTIONS.daily).doc(date);
  const daily = await dailyRef.get();
  if (!daily.exists) {
    logger.warn(`autoPost: daily/${date} does not exist; nothing to post`);
    return result;
  }

  let pid: string | null = typeof daily.get('postedProblemId') === 'string' ? daily.get('postedProblemId') : null;
  if (!pid) {
    const ids: string[] = [daily.get('official'), ...(daily.get('picks') ?? [])].filter(
      (x): x is string => typeof x === 'string',
    );
    const snaps = await Promise.all(ids.map((id) => db.collection(COLLECTIONS.problems).doc(id).get()));
    const existing = snaps.filter((s) => s.exists);
    const answers = await loadAnswers(
      db,
      existing.map((s) => s.id),
    );
    const summaries = existing.map((s) => toSummary(s.id, s.data() ?? {}, answers.get(s.id)));
    pid = choosePostTarget(summaries)?.id ?? null;
    if (!pid) {
      logger.info('autoPost: no eligible problem to post');
      return result;
    }
    await dailyRef.update({ postedProblemId: pid });
  }

  const problemRef = db.collection(COLLECTIONS.problems).doc(pid);
  const problemSnap = await problemRef.get();
  if (!problemSnap.exists || problemSnap.get('hidden') === true) {
    logger.warn(`autoPost: problem ${pid} is gone or hidden`);
    return result;
  }
  result.postedProblemId = pid;

  const postedAlready = (daily.get('posts') ?? {}) as Record<string, unknown>;
  const targets = adapters.filter((a) => !postedAlready[a.platform]);
  if (targets.length === 0) return result;

  const url = problemUrl(deps.siteUrl, pid);
  const postProblem = {
    tiles: problemSnap.get('tiles') as string[],
    dora: (problemSnap.get('dora') ?? []) as string[],
    seatWind: problemSnap.get('seatWind'),
    roundWind: problemSnap.get('roundWind'),
    turn: (problemSnap.get('turn') ?? null) as number | null,
  };
  const cardPath = (problemSnap.get('cardPath') as string | undefined) ?? cardPathFor(pid);
  const bytes = await deps.loadCard(cardPath).catch(() => null);
  const image: PostImage | undefined = bytes
    ? {
        bytes,
        mimeType: 'image/png',
        alt: buildAltText(postProblem),
        publicUrl: cardPublicUrl(deps.bucketName, cardPath),
      }
    : undefined;

  for (const adapter of targets) {
    const platform = adapter.platform;
    try {
      const ref = await adapter.post({ text: buildProblemPost(platform, postProblem, url), image });
      await dailyRef.update({ [`posts.${platform}`]: storableRef(ref) });
      result.postedPlatforms.push(platform);
    } catch (err) {
      logger.error(`post failed (${platform})`, err);
      result.errors.push(`post:${platform}`);
    }
  }
  if (result.postedPlatforms.length > 0) {
    await problemRef.update({ 'featured.posted': true });
    await dailyRef.update({ postedAt: Timestamp.fromDate(now) });
  }
  return result;
}
