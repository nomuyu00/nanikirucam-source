import type { Firestore } from 'firebase-admin/firestore';
import { FieldValue } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { getMessaging } from 'firebase-admin/messaging';
import { COLLECTIONS } from './types';

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/** 出題者への「回答が n 人に達しました」通知（設計書 6・12 章）。 */
export async function notifyAnswerMilestone(
  db: Firestore,
  milestone: { authorUid: string; count: number; problemId: string },
): Promise<void> {
  try {
    const userRef = db.collection(COLLECTIONS.users).doc(milestone.authorUid);
    const snap = await userRef.get();
    if (!snap.exists) return;
    // 通知設定が OFF なら送らない（`notify.milestone` が false のとき）
    if (snap.get('notify.milestone') === false) return;
    const tokens: string[] = (snap.get('fcmTokens') ?? []).filter(
      (t: unknown): t is string => typeof t === 'string' && t.length > 0,
    );
    if (tokens.length === 0) return;

    const lang = snap.get('locale') === 'en' ? 'en' : 'ja';
    const title = lang === 'en' ? 'Your problem is popular' : 'あなたの問題が回答されています';
    const body =
      lang === 'en'
        ? `${milestone.count} people have answered. Share it again!`
        : `${milestone.count}人が回答しました。もう一度シェアしてみませんか？`;

    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: {
        type: 'answer_milestone',
        problemId: milestone.problemId,
        count: String(milestone.count),
      },
    });

    // 無効になったトークンを掃除する
    const dead: string[] = [];
    res.responses.forEach((r, i) => {
      if (!r.success && r.error && INVALID_TOKEN_CODES.has(r.error.code)) dead.push(tokens[i]);
    });
    if (dead.length > 0) await userRef.update({ fcmTokens: FieldValue.arrayRemove(...dead) });
  } catch (err) {
    // 通知の失敗で回答自体を失敗させない
    logger.warn('notifyAnswerMilestone failed', err);
  }
}

/** トピック（`daily` / `weekly`）への通知。 */
export async function sendTopic(
  topic: 'daily' | 'weekly',
  notification: { title: string; body: string },
  data: Record<string, string>,
): Promise<void> {
  try {
    await getMessaging().send({ topic, notification, data });
  } catch (err) {
    logger.warn(`sendTopic(${topic}) failed`, err);
  }
}
