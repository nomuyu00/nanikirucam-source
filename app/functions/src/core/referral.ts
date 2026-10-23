import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { computeEffectivePro, extendReferral, planReferral } from '../lib/pro';
import { COLLECTIONS } from './types';
import { proSummaryFields } from './users';

export type ReferralOutcome =
  | { kind: 'invalid_code' }
  | { kind: 'no_user' }
  | { kind: 'already_applied' }
  | { kind: 'self_referral' }
  | { kind: 'applied'; proUntilMs: number; referrerRewarded: boolean };

function proUpdate(
  pro: FirebaseFirestore.DocumentData | undefined,
  referralUntilMs: number,
  nowMs: number,
) {
  const rc = pro?.revenuecat
    ? {
        active: pro.revenuecat.active === true,
        untilMs: pro.revenuecat.until instanceof Timestamp ? pro.revenuecat.until.toMillis() : null,
      }
    : null;
  const summary = computeEffectivePro(rc, { untilMs: referralUntilMs }, nowMs);
  return {
    ...proSummaryFields(summary),
    referral: { until: Timestamp.fromMillis(referralUntilMs) },
  };
}

function referralUntilOf(pro: FirebaseFirestore.DocumentData | undefined): { untilMs: number } | null {
  const until = pro?.referral?.until;
  return until instanceof Timestamp ? { untilMs: until.toMillis() } : null;
}

/**
 * 紹介コードの適用（`applyReferral` の本体）。
 * 適用した側は 1 人 1 回。両者に Pro 7 日（`pro.referral`）。紹介した側は上限人数まで。
 */
export async function applyReferralCore(
  db: Firestore,
  uid: string,
  code: string,
  now: Date = new Date(),
): Promise<ReferralOutcome> {
  const nowMs = now.getTime();
  const codeRef = db.collection(COLLECTIONS.referrals).doc(code);
  const meRef = db.collection(COLLECTIONS.users).doc(uid);

  return db.runTransaction(async (tx): Promise<ReferralOutcome> => {
    const [codeSnap, meSnap] = await Promise.all([tx.get(codeRef), tx.get(meRef)]);
    if (!codeSnap.exists) return { kind: 'invalid_code' };
    if (!meSnap.exists) return { kind: 'no_user' };

    const ownerUid = String(codeSnap.get('uid'));
    const uses = Number(codeSnap.get('uses') ?? 0);
    const plan = planReferral({
      applicantUid: uid,
      applicantReferredBy: meSnap.get('referredBy'),
      codeOwnerUid: ownerUid,
      codeUsesSoFar: uses,
    });
    if (!plan.ok) return { kind: plan.reason };

    const ownerRef = db.collection(COLLECTIONS.users).doc(ownerUid);
    const ownerSnap = await tx.get(ownerRef);

    const mine = extendReferral(referralUntilOf(meSnap.get('pro')), nowMs, plan.applicantDays);
    tx.set(
      meRef,
      { referredBy: code, pro: proUpdate(meSnap.get('pro'), mine.untilMs, nowMs) },
      { merge: true },
    );

    let referrerRewarded = false;
    if (plan.referrerDays > 0 && ownerSnap.exists) {
      const theirs = extendReferral(
        referralUntilOf(ownerSnap.get('pro')),
        nowMs,
        plan.referrerDays,
      );
      tx.set(ownerRef, { pro: proUpdate(ownerSnap.get('pro'), theirs.untilMs, nowMs) }, { merge: true });
      referrerRewarded = true;
    }
    tx.update(codeRef, { uses: FieldValue.increment(1) });
    return { kind: 'applied', proUntilMs: mine.untilMs, referrerRewarded };
  });
}
