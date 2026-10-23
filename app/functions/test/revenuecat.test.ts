import {
  computeEffectivePro,
  extendReferral,
  planReferral,
  REFERRAL_PRO_DAYS,
  REFERRER_REWARD_CAP,
} from '../src/lib/pro';
import type { RevenueCatState } from '../src/lib/pro';
import {
  concernsProEntitlement,
  decideEvent,
  parseWebhookBody,
  resolveUid,
  verifyAuthorization,
} from '../src/lib/revenuecat';
import type { RevenueCatEvent } from '../src/lib/revenuecat';

const DAY = 24 * 60 * 60 * 1000;
const NOW = Date.UTC(2026, 9, 21, 12, 0, 0);

function event(patch: Partial<RevenueCatEvent> = {}): RevenueCatEvent {
  return {
    id: 'evt-1',
    type: 'INITIAL_PURCHASE',
    app_user_id: 'uid-123',
    original_app_user_id: 'uid-123',
    aliases: ['uid-123'],
    entitlement_ids: ['pro'],
    product_id: 'nanikiru_pro_monthly',
    period_type: 'TRIAL',
    store: 'APP_STORE',
    environment: 'PRODUCTION',
    event_timestamp_ms: NOW,
    expiration_at_ms: NOW + 7 * DAY,
    ...patch,
  };
}

function state(patch: Partial<RevenueCatState> = {}): RevenueCatState {
  return {
    active: true,
    untilMs: NOW + 30 * DAY,
    productId: 'nanikiru_pro_monthly',
    store: 'APP_STORE',
    environment: 'PRODUCTION',
    periodType: 'NORMAL',
    lastEventId: 'evt-0',
    lastEventAtMs: NOW - DAY,
    ...patch,
  };
}

function update(prev: RevenueCatState | null, ev: RevenueCatEvent, now = NOW): RevenueCatState {
  const d = decideEvent(prev, ev, now);
  if (d.action !== 'update') throw new Error(`expected update, got ${d.reason}`);
  return d.state;
}

describe('Webhook の Authorization 検証', () => {
  test('共有秘密と一致すれば true（Bearer 付きでも可）', () => {
    expect(verifyAuthorization('s3cret-value', 's3cret-value')).toBe(true);
    expect(verifyAuthorization('Bearer s3cret-value', 's3cret-value')).toBe(true);
  });

  test('一致しない・未設定・長さ違いは false', () => {
    expect(verifyAuthorization('wrong', 's3cret-value')).toBe(false);
    expect(verifyAuthorization('s3cret-valuX', 's3cret-value')).toBe(false);
    expect(verifyAuthorization('s3cret', 's3cret-value')).toBe(false);
    expect(verifyAuthorization(undefined, 's3cret-value')).toBe(false);
    expect(verifyAuthorization('', 's3cret-value')).toBe(false);
    expect(verifyAuthorization('anything', '')).toBe(false);
    expect(verifyAuthorization('anything', undefined)).toBe(false);
  });
});

describe('Webhook 本文の解析', () => {
  test('api_version と event を持つ本文から必要な項目を取り出す', () => {
    const parsed = parseWebhookBody({
      api_version: '1.0',
      event: {
        id: 'e1',
        type: 'RENEWAL',
        app_user_id: 'u1',
        entitlement_ids: ['pro'],
        event_timestamp_ms: 1,
        expiration_at_ms: 2,
        unknown_field: 'ignored',
      },
    });
    expect(parsed).toMatchObject({ id: 'e1', type: 'RENEWAL', app_user_id: 'u1', expiration_at_ms: 2 });
    expect(parsed).not.toHaveProperty('unknown_field');
  });

  test('不正な本文は null', () => {
    expect(parseWebhookBody(null)).toBeNull();
    expect(parseWebhookBody({})).toBeNull();
    expect(parseWebhookBody({ event: { id: 1, type: 'X' } })).toBeNull();
    expect(parseWebhookBody({ event: { id: 'a', type: 'X' } })).toBeNull();
  });

  test('uid の決定: 匿名 ID は使わず、alias から探す', () => {
    expect(resolveUid(event())).toBe('uid-123');
    expect(
      resolveUid(
        event({
          app_user_id: '$RCAnonymousID:abc',
          original_app_user_id: '$RCAnonymousID:abc',
          aliases: ['$RCAnonymousID:abc', 'uid-999'],
        }),
      ),
    ).toBe('uid-999');
    expect(
      resolveUid(
        event({ app_user_id: '$RCAnonymousID:abc', original_app_user_id: null, aliases: [] }),
      ),
    ).toBeNull();
    // Firestore のパスを壊す ID は使わない
    expect(resolveUid(event({ app_user_id: 'a/b', original_app_user_id: null, aliases: [] }))).toBeNull();
  });

  test('pro 権利に関係するイベントか', () => {
    expect(concernsProEntitlement(event())).toBe(true);
    expect(concernsProEntitlement(event({ entitlement_ids: ['other'] }))).toBe(false);
    expect(concernsProEntitlement(event({ entitlement_ids: null }))).toBe(false);
    expect(concernsProEntitlement(event({ entitlement_ids: null, entitlement_id: 'pro' }))).toBe(true);
  });
});

describe('イベントの反映（decideEvent）', () => {
  test('INITIAL_PURCHASE（トライアル）で有効になり、期限が入る', () => {
    const s = update(null, event());
    expect(s).toMatchObject({
      active: true,
      untilMs: NOW + 7 * DAY,
      productId: 'nanikiru_pro_monthly',
      periodType: 'TRIAL',
      lastEventId: 'evt-1',
      lastEventAtMs: NOW,
    });
  });

  test('RENEWAL で期限が延びる', () => {
    const s = update(state(), event({ id: 'evt-2', type: 'RENEWAL', expiration_at_ms: NOW + 60 * DAY }));
    expect(s.untilMs).toBe(NOW + 60 * DAY);
    expect(s.active).toBe(true);
  });

  test('期限がすでに過去のイベントでは有効にしない', () => {
    const s = update(null, event({ expiration_at_ms: NOW - DAY }));
    expect(s.active).toBe(false);
  });

  test('CANCELLATION（自動更新の停止）は期限まで有効のまま', () => {
    const s = update(
      state(),
      event({ id: 'evt-3', type: 'CANCELLATION', cancel_reason: 'UNSUBSCRIBE', expiration_at_ms: NOW + 10 * DAY }),
    );
    expect(s.active).toBe(true);
    expect(s.untilMs).toBe(NOW + 10 * DAY);
  });

  test('返金（CUSTOMER_SUPPORT）の CANCELLATION は即座に無効', () => {
    const s = update(
      state(),
      event({ id: 'evt-3', type: 'CANCELLATION', cancel_reason: 'CUSTOMER_SUPPORT' }),
    );
    expect(s.active).toBe(false);
  });

  test('BILLING_ISSUE は猶予期間の終わりまで有効', () => {
    const s = update(
      state({ untilMs: NOW + 1 * DAY }),
      event({
        id: 'evt-4',
        type: 'BILLING_ISSUE',
        expiration_at_ms: NOW + 1 * DAY,
        grace_period_expiration_at_ms: NOW + 4 * DAY,
      }),
    );
    expect(s.active).toBe(true);
    expect(s.untilMs).toBe(NOW + 4 * DAY);
  });

  test('EXPIRATION で無効になる', () => {
    const s = update(
      state(),
      event({ id: 'evt-5', type: 'EXPIRATION', expiration_at_ms: NOW - 1000 }),
    );
    expect(s.active).toBe(false);
    expect(s.untilMs).toBe(NOW - 1000);
  });

  test('SUBSCRIPTION_PAUSED は権利を変えない', () => {
    const prev = state();
    const s = update(prev, event({ id: 'evt-6', type: 'SUBSCRIPTION_PAUSED' }));
    expect(s.active).toBe(prev.active);
    expect(s.untilMs).toBe(prev.untilMs);
    expect(s.lastEventId).toBe('evt-6');
  });

  test('再送（同じ id）は無視', () => {
    const prev = state({ lastEventId: 'evt-1' });
    expect(decideEvent(prev, event({ id: 'evt-1' }), NOW)).toEqual({
      action: 'ignore',
      reason: 'duplicate',
    });
  });

  test('順序が入れ替わった古いイベントは無視', () => {
    const prev = state({ lastEventAtMs: NOW });
    expect(decideEvent(prev, event({ id: 'old', event_timestamp_ms: NOW - 1000 }), NOW)).toEqual({
      action: 'ignore',
      reason: 'stale',
    });
    // 同時刻は適用する
    expect(decideEvent(prev, event({ id: 'same', event_timestamp_ms: NOW }), NOW).action).toBe('update');
  });

  test('pro 以外の権利・TEST・未対応の種類は無視', () => {
    expect(decideEvent(null, event({ entitlement_ids: ['other'] }), NOW)).toEqual({
      action: 'ignore',
      reason: 'not_pro',
    });
    expect(decideEvent(null, event({ type: 'TEST', entitlement_ids: null }), NOW)).toEqual({
      action: 'ignore',
      reason: 'not_pro',
    });
    expect(decideEvent(null, event({ type: 'EXPERIMENT_ENROLLMENT' }), NOW)).toEqual({
      action: 'ignore',
      reason: 'unsupported',
    });
  });
});

describe('有効な Pro の計算（RevenueCat OR 紹介特典）', () => {
  test('どちらも無ければ無効', () => {
    expect(computeEffectivePro(null, null, NOW)).toEqual({ active: false, source: null, untilMs: null });
  });

  test('RevenueCat が有効ならその期限', () => {
    expect(computeEffectivePro({ active: true, untilMs: NOW + DAY }, null, NOW)).toEqual({
      active: true,
      source: 'revenuecat',
      untilMs: NOW + DAY,
    });
  });

  test('RevenueCat の期限切れ・inactive は無効扱い', () => {
    expect(computeEffectivePro({ active: true, untilMs: NOW - 1 }, null, NOW).active).toBe(false);
    expect(computeEffectivePro({ active: false, untilMs: NOW + DAY }, null, NOW).active).toBe(false);
  });

  test('期限なし（null）の RevenueCat 権利は有効で、期限も null', () => {
    expect(computeEffectivePro({ active: true, untilMs: null }, { untilMs: NOW + DAY }, NOW)).toEqual({
      active: true,
      source: 'revenuecat',
      untilMs: null,
    });
  });

  test('紹介特典だけなら source は referral', () => {
    expect(computeEffectivePro(null, { untilMs: NOW + 3 * DAY }, NOW)).toEqual({
      active: true,
      source: 'referral',
      untilMs: NOW + 3 * DAY,
    });
    expect(computeEffectivePro(null, { untilMs: NOW - 1 }, NOW).active).toBe(false);
  });

  test('RevenueCat が切れても紹介特典が残っていれば有効', () => {
    expect(
      computeEffectivePro({ active: false, untilMs: NOW - DAY }, { untilMs: NOW + 2 * DAY }, NOW),
    ).toEqual({ active: true, source: 'referral', untilMs: NOW + 2 * DAY });
  });

  test('両方有効なら長い方の期限', () => {
    expect(
      computeEffectivePro({ active: true, untilMs: NOW + DAY }, { untilMs: NOW + 5 * DAY }, NOW)
        .untilMs,
    ).toBe(NOW + 5 * DAY);
  });
});

describe('紹介特典', () => {
  test('期限内ならそこから、切れていれば今から 7 日延ばす', () => {
    expect(extendReferral(null, NOW, 7)).toEqual({ untilMs: NOW + 7 * DAY });
    expect(extendReferral({ untilMs: NOW - DAY }, NOW, 7)).toEqual({ untilMs: NOW + 7 * DAY });
    expect(extendReferral({ untilMs: NOW + 3 * DAY }, NOW, 7)).toEqual({ untilMs: NOW + 10 * DAY });
  });

  test('1 人 1 回・自分のコードは不可', () => {
    expect(
      planReferral({ applicantUid: 'a', applicantReferredBy: 'ABCD2345', codeOwnerUid: 'b', codeUsesSoFar: 0 }),
    ).toEqual({ ok: false, reason: 'already_applied' });
    expect(
      planReferral({ applicantUid: 'a', applicantReferredBy: null, codeOwnerUid: 'a', codeUsesSoFar: 0 }),
    ).toEqual({ ok: false, reason: 'self_referral' });
  });

  test('両者に 7 日。紹介した側は上限人数まで', () => {
    expect(REFERRAL_PRO_DAYS).toBe(7);
    expect(
      planReferral({ applicantUid: 'a', applicantReferredBy: undefined, codeOwnerUid: 'b', codeUsesSoFar: 0 }),
    ).toEqual({ ok: true, applicantDays: 7, referrerDays: 7 });
    expect(
      planReferral({
        applicantUid: 'a',
        applicantReferredBy: null,
        codeOwnerUid: 'b',
        codeUsesSoFar: REFERRER_REWARD_CAP - 1,
      }),
    ).toEqual({ ok: true, applicantDays: 7, referrerDays: 7 });
    expect(
      planReferral({
        applicantUid: 'a',
        applicantReferredBy: null,
        codeOwnerUid: 'b',
        codeUsesSoFar: REFERRER_REWARD_CAP,
      }),
    ).toEqual({ ok: true, applicantDays: 7, referrerDays: 0 });
  });
});
