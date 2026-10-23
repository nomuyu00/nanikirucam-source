import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { POSTING_SECRETS, SITE_URL } from './config';
import { autoPostCore } from './core/autoPost';
import { runtimeAdapters } from './postRuntime';
import { bucketName, loadCard } from './storage';

/**
 * 毎日 19:00 JST の自動投稿。Bluesky・Threads・Discord（X は設定で有効にしたときだけ）。
 * 昨日の問題の答え合わせを返信し、今日の問題をカード PNG 付きで投稿する。
 * ユーザーのアカウントでは投稿せず、公式アカウントの Secret だけを使う。
 */
export const autoPost = onSchedule(
  {
    schedule: '0 19 * * *',
    timeZone: 'Asia/Tokyo',
    timeoutSeconds: 300,
    secrets: POSTING_SECRETS,
  },
  async () => {
    const db = getFirestore();
    const adapters = await runtimeAdapters(db);
    if (adapters.length === 0) {
      logger.info('autoPost: no posting destination is configured');
      return;
    }
    const result = await autoPostCore({
      db,
      adapters,
      siteUrl: SITE_URL.value().replace(/\/$/, ''),
      bucketName: bucketName(),
      loadCard,
    });
    logger.info('autoPost', result);
  },
);
