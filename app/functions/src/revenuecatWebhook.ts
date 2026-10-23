import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onRequest } from 'firebase-functions/v2/https';
import { REVENUECAT_WEBHOOK_SECRET } from './config';
import { applyRevenueCatEvent } from './core/revenuecat';
import { parseWebhookBody, verifyAuthorization } from './lib/revenuecat';

/**
 * RevenueCat の Webhook（HTTPS）。ダッシュボードの Authorization header に設定した共有秘密で検証し、
 * `users/{uid}.pro` を更新する（uid は RevenueCat の App User ID = Firebase uid）。
 * 失敗時は 5xx を返し、RevenueCat の再送（最大 5 回）に任せる。再送は event.id で二重適用しない。
 */
export const revenuecatWebhook = onRequest(
  { secrets: [REVENUECAT_WEBHOOK_SECRET], cors: false, maxInstances: 5 },
  async (req, res) => {
    res.set('Cache-Control', 'no-store');
    if (req.method !== 'POST') {
      res.set('Allow', 'POST');
      res.status(405).json({ error: 'method_not_allowed' });
      return;
    }
    if (!verifyAuthorization(req.get('authorization'), REVENUECAT_WEBHOOK_SECRET.value())) {
      res.status(401).json({ error: 'unauthorized' });
      return;
    }
    const event = parseWebhookBody(req.body);
    if (!event) {
      res.status(400).json({ error: 'invalid_body' });
      return;
    }
    try {
      const outcome = await applyRevenueCatEvent(getFirestore(), event);
      if (outcome.status === 'unknown_user') {
        logger.warn('revenuecatWebhook: unknown user', { type: event.type, id: event.id });
      }
      // 無視した場合も 200（再送されても結果は変わらないため）
      res.status(200).json({ ok: true, ...outcome });
    } catch (err) {
      logger.error('revenuecatWebhook failed', err);
      res.status(500).json({ error: 'internal' });
    }
  },
);
