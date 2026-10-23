import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { pickDailyCore } from './core/pickDaily';

/**
 * 今日の問題の選出（毎日 00:00 JST）。公式 1 問 + ユーザー投稿 2 問を `daily/{date}` に書く。
 * 通知は夜中に鳴らさないよう、別の関数 `notifyDaily`（07:30 JST）が送る。
 */
export const pickDaily = onSchedule(
  { schedule: '0 0 * * *', timeZone: 'Asia/Tokyo', timeoutSeconds: 120 },
  async () => {
    const result = await pickDailyCore(getFirestore());
    logger.info('pickDaily', result);
  },
);
