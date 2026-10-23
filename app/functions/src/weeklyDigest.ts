import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { POSTING_SECRETS, SITE_URL } from './config';
import { sendTopic } from './core/notify';
import { weeklyDigestCore } from './core/weekly';
import { runtimeAdapters } from './postRuntime';
import { bucketName, loadCard } from './storage';

/**
 * 週間まとめ（毎週日曜 20:00 JST）。今週の難問 TOP3 と「速さ派 vs 打点派」を投稿し、
 * FCM トピック `weekly` に通知する。
 */
export const weeklyDigest = onSchedule(
  {
    schedule: '0 20 * * 0',
    timeZone: 'Asia/Tokyo',
    timeoutSeconds: 300,
    secrets: POSTING_SECRETS,
  },
  async () => {
    const db = getFirestore();
    const adapters = await runtimeAdapters(db);
    const result = await weeklyDigestCore({
      db,
      adapters,
      siteUrl: SITE_URL.value().replace(/\/$/, ''),
      bucketName: bucketName(),
      loadCard,
      notifyWeekly: (title, body, topProblemId) =>
        sendTopic('weekly', { title, body }, { type: 'weekly', problemId: topProblemId }),
    });
    logger.info('weeklyDigest', result);
  },
);
