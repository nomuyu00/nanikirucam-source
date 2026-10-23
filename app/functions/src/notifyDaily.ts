import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { sendTopic } from './core/notify';
import { COLLECTIONS } from './core/types';
import { jstDate } from './lib/dates';

/** 今日の問題の通知（毎日 07:30 JST、FCM トピック `daily`）。 */
export const notifyDaily = onSchedule(
  { schedule: '30 7 * * *', timeZone: 'Asia/Tokyo', timeoutSeconds: 60 },
  async () => {
    const date = jstDate(new Date());
    const snap = await getFirestore().collection(COLLECTIONS.daily).doc(date).get();
    if (!snap.exists) {
      logger.warn(`notifyDaily: daily/${date} does not exist`);
      return;
    }
    const count =
      (typeof snap.get('official') === 'string' ? 1 : 0) + (snap.get('picks') ?? []).length;
    if (count === 0) return;
    await sendTopic(
      'daily',
      { title: '今日の何切る', body: `今日の問題が${count}問届いています。あなたならどれを切る？` },
      { type: 'daily', date },
    );
  },
);
