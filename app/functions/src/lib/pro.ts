/**
 * Pro 権利の計算（純粋ロジック）。
 *
 * `users/{uid}.pro` は次の形で持つ。
 *   active / source / until … 現在の有効な権利の要約（クライアントはこれを読む）
 *   revenuecat { active, untilMs, ... } … RevenueCat Webhook が更新する
 *   referral { untilMs }              … 紹介特典（applyReferral が更新する）
 * 要約は「RevenueCat の pro OR 紹介特典（期限内）」で決める（設計書 9 章）。
 */

export const ENTITLEMENT_ID = 'pro';
export const REFERRAL_PRO_DAYS = 7;
/** 紹介した側が特典を受け取れる人数の上限（匿名アカウントの量産対策）。 */
export const REFERRER_REWARD_CAP = 10;

export interface RevenueCatState {
  active: boolean;
  /** 権利の期限（ミリ秒）。null は期限なし。 */
  untilMs: number | null;
  productId: string | null;
  store: string | null;
  environment: string | null;
  periodType: string | null;
  lastEventId: string | null;
  lastEventAtMs: number;
}

export interface ReferralState {
  untilMs: number;
}

export interface ProSummary {
  active: boolean;
  source: 'revenuecat' | 'referral' | null;
  /** 期限（ミリ秒）。active でも null なら期限なし。 */
  untilMs: number | null;
}

export function computeEffectivePro(
  revenuecat: Pick<RevenueCatState, 'active' | 'untilMs'> | null | undefined,
  referral: ReferralState | null | undefined,
  nowMs: number,
): ProSummary {
  const rcActive =
    !!revenuecat && revenuecat.active && (revenuecat.untilMs === null || revenuecat.untilMs > nowMs);
  const refActive = !!referral && referral.untilMs > nowMs;
  if (rcActive) {
    // RevenueCat が期限なしならそれが最長。そうでなければ紹介特典の方が長いときは長い方の期限にする。
    const rcUntil = revenuecat!.untilMs;
    const until =
      rcUntil === null ? null : refActive ? Math.max(rcUntil, referral!.untilMs) : rcUntil;
    return { active: true, source: 'revenuecat', untilMs: until };
  }
  if (refActive) return { active: true, source: 'referral', untilMs: referral!.untilMs };
  return { active: false, source: null, untilMs: null };
}

/** 紹介特典の期限を `days` 日延ばす（すでに期限内ならそこから、切れていれば今から）。 */
export function extendReferral(
  current: ReferralState | null | undefined,
  nowMs: number,
  days: number,
): ReferralState {
  const base = current && current.untilMs > nowMs ? current.untilMs : nowMs;
  return { untilMs: base + days * 24 * 60 * 60 * 1000 };
}

export type ReferralPlan =
  | { ok: true; applicantDays: number; referrerDays: number }
  | { ok: false; reason: 'self_referral' | 'already_applied' };

/** 紹介コード適用の可否と付与日数。 */
export function planReferral(input: {
  applicantUid: string;
  applicantReferredBy: string | null | undefined;
  codeOwnerUid: string;
  codeUsesSoFar: number;
}): ReferralPlan {
  if (input.applicantReferredBy) return { ok: false, reason: 'already_applied' };
  if (input.applicantUid === input.codeOwnerUid) return { ok: false, reason: 'self_referral' };
  return {
    ok: true,
    applicantDays: REFERRAL_PRO_DAYS,
    referrerDays: input.codeUsesSoFar < REFERRER_REWARD_CAP ? REFERRAL_PRO_DAYS : 0,
  };
}
