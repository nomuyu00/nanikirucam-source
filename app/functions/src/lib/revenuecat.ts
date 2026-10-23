import { timingSafeEqual } from 'node:crypto';
import { ENTITLEMENT_ID } from './pro';
import type { RevenueCatState } from './pro';

/**
 * RevenueCat Webhook の `Authorization` ヘッダ検証。
 * ダッシュボードに設定した値がそのまま送られてくる。`Bearer ` 付きで設定した場合にも対応。
 */
export function verifyAuthorization(
  header: string | undefined | null,
  secret: string | undefined | null,
): boolean {
  if (!header || !secret) return false;
  const expected = Buffer.from(secret);
  const candidates = [header, header.replace(/^Bearer\s+/i, '')];
  return candidates.some((candidate) => {
    const got = Buffer.from(candidate);
    return got.length === expected.length && timingSafeEqual(got, expected);
  });
}

/** Webhook の `event`（使う項目だけ）。 */
export interface RevenueCatEvent {
  id: string;
  type: string;
  app_user_id?: string | null;
  original_app_user_id?: string | null;
  aliases?: string[] | null;
  entitlement_ids?: string[] | null;
  entitlement_id?: string | null;
  product_id?: string | null;
  period_type?: string | null;
  store?: string | null;
  environment?: string | null;
  event_timestamp_ms: number;
  expiration_at_ms?: number | null;
  grace_period_expiration_at_ms?: number | null;
  cancel_reason?: string | null;
  transferred_from?: string[] | null;
  transferred_to?: string[] | null;
}

/** 本文 `{api_version, event}` から必要な項目を取り出す。不正なら null。 */
export function parseWebhookBody(body: unknown): RevenueCatEvent | null {
  if (typeof body !== 'object' || body === null) return null;
  const event = (body as { event?: unknown }).event;
  if (typeof event !== 'object' || event === null) return null;
  const e = event as Record<string, unknown>;
  if (typeof e.id !== 'string' || typeof e.type !== 'string') return null;
  if (typeof e.event_timestamp_ms !== 'number') return null;
  const strOrNull = (v: unknown) => (typeof v === 'string' ? v : null);
  const numOrNull = (v: unknown) => (typeof v === 'number' ? v : null);
  const strArr = (v: unknown) =>
    Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : null;
  return {
    id: e.id,
    type: e.type,
    app_user_id: strOrNull(e.app_user_id),
    original_app_user_id: strOrNull(e.original_app_user_id),
    aliases: strArr(e.aliases),
    entitlement_ids: strArr(e.entitlement_ids),
    entitlement_id: strOrNull(e.entitlement_id),
    product_id: strOrNull(e.product_id),
    period_type: strOrNull(e.period_type),
    store: strOrNull(e.store),
    environment: strOrNull(e.environment),
    event_timestamp_ms: e.event_timestamp_ms,
    expiration_at_ms: numOrNull(e.expiration_at_ms),
    grace_period_expiration_at_ms: numOrNull(e.grace_period_expiration_at_ms),
    cancel_reason: strOrNull(e.cancel_reason),
    transferred_from: strArr(e.transferred_from),
    transferred_to: strArr(e.transferred_to),
  };
}

const ANONYMOUS_PREFIX = '$RCAnonymousID:';

/** Firebase uid として使える ID（RevenueCat の匿名 ID を除く）。 */
export function resolveUid(event: RevenueCatEvent): string | null {
  const candidates = [event.app_user_id, event.original_app_user_id, ...(event.aliases ?? [])];
  for (const id of candidates) {
    if (id && !id.startsWith(ANONYMOUS_PREFIX) && !id.includes('/')) return id;
  }
  return null;
}

/** この購入が `pro` 権利に関係するか。 */
export function concernsProEntitlement(event: RevenueCatEvent): boolean {
  const ids = event.entitlement_ids ?? (event.entitlement_id ? [event.entitlement_id] : null);
  return !!ids && ids.includes(ENTITLEMENT_ID);
}

const GRANTING_TYPES = new Set([
  'INITIAL_PURCHASE',
  'RENEWAL',
  'PRODUCT_CHANGE',
  'UNCANCELLATION',
  'NON_RENEWING_PURCHASE',
  'SUBSCRIPTION_EXTENDED',
  'REFUND_REVERSED',
  'TEMPORARY_ENTITLEMENT_GRANT',
]);

export type EventDecision =
  | { action: 'update'; state: RevenueCatState }
  | { action: 'ignore'; reason: 'duplicate' | 'stale' | 'not_pro' | 'no_effect' | 'unsupported' };

/**
 * イベントを `users/{uid}.pro.revenuecat` に反映した結果を返す（純粋関数）。
 * - 同じ `id`（再送）は無視。`event_timestamp_ms` が保存済みより古いもの（順序入れ替わり）も無視。
 * - CANCELLATION は自動更新の停止なので期限までは有効のまま。返金（CUSTOMER_SUPPORT）のときだけ即無効。
 * - BILLING_ISSUE は猶予期間があるため無効にしない（期限は猶予終了まで延ばす）。
 * - EXPIRATION で無効にする。
 */
export function decideEvent(
  prev: RevenueCatState | null | undefined,
  event: RevenueCatEvent,
  nowMs: number,
): EventDecision {
  if (prev && prev.lastEventId === event.id) return { action: 'ignore', reason: 'duplicate' };
  if (prev && event.event_timestamp_ms < prev.lastEventAtMs) {
    return { action: 'ignore', reason: 'stale' };
  }
  if (!concernsProEntitlement(event)) return { action: 'ignore', reason: 'not_pro' };

  const base: RevenueCatState = {
    active: prev?.active ?? false,
    untilMs: prev?.untilMs ?? null,
    productId: event.product_id ?? prev?.productId ?? null,
    store: event.store ?? prev?.store ?? null,
    environment: event.environment ?? prev?.environment ?? null,
    periodType: event.period_type ?? prev?.periodType ?? null,
    lastEventId: event.id,
    lastEventAtMs: event.event_timestamp_ms,
  };

  if (GRANTING_TYPES.has(event.type)) {
    const until = event.expiration_at_ms ?? null;
    return {
      action: 'update',
      state: { ...base, active: until === null || until > nowMs, untilMs: until },
    };
  }

  switch (event.type) {
    case 'CANCELLATION': {
      if (event.cancel_reason === 'CUSTOMER_SUPPORT') {
        // 返金: 即座に権利を失う
        return { action: 'update', state: { ...base, active: false } };
      }
      const until = event.expiration_at_ms ?? base.untilMs;
      return {
        action: 'update',
        state: { ...base, untilMs: until, active: until === null || until > nowMs },
      };
    }
    case 'BILLING_ISSUE': {
      const until = event.grace_period_expiration_at_ms ?? event.expiration_at_ms ?? base.untilMs;
      return {
        action: 'update',
        state: { ...base, untilMs: until, active: until === null || until > nowMs },
      };
    }
    case 'EXPIRATION':
      return {
        action: 'update',
        state: { ...base, active: false, untilMs: event.expiration_at_ms ?? base.untilMs },
      };
    case 'SUBSCRIPTION_PAUSED':
      return { action: 'update', state: base };
    default:
      return { action: 'ignore', reason: 'unsupported' };
  }
}
