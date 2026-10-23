import { Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { computeEffectivePro } from '../lib/pro';
import type { ProSummary } from '../lib/pro';
import { generateReferralCode } from '../lib/referral';
import { COLLECTIONS } from './types';

/** `users/{uid}.pro` の要約部分（active / source / until）。 */
export function proSummaryFields(summary: ProSummary) {
  return {
    active: summary.active,
    source: summary.source,
    until: summary.untilMs === null ? null : Timestamp.fromMillis(summary.untilMs),
  };
}

/** 保存済みの `pro` マップから、現在時刻での有効な権利を計算し直す。 */
export function effectiveProFromDoc(pro: FirebaseFirestore.DocumentData | undefined, nowMs: number) {
  const rc = pro?.revenuecat
    ? {
        active: pro.revenuecat.active === true,
        untilMs: pro.revenuecat.until instanceof Timestamp ? pro.revenuecat.until.toMillis() : null,
      }
    : null;
  const referral =
    pro?.referral?.until instanceof Timestamp ? { untilMs: pro.referral.until.toMillis() } : null;
  return computeEffectivePro(rc, referral, nowMs);
}

export interface EnsureUserResult {
  referralCode: string;
  nickname: string | null;
  pro: { active: boolean; source: string | null; untilMs: number | null };
  created: boolean;
}

class CodeCollision extends Error {}

function resultFrom(data: FirebaseFirestore.DocumentData, nowMs: number, created: boolean): EnsureUserResult {
  const eff = effectiveProFromDoc(data.pro, nowMs);
  return {
    referralCode: data.referralCode as string,
    nickname: typeof data.nickname === 'string' ? data.nickname : null,
    pro: { active: eff.active, source: eff.source, untilMs: eff.untilMs },
    created,
  };
}

/**
 * `users/{uid}` と自分の紹介コード（`referrals/{code}`）を用意する。何度呼んでも同じ結果を返す。
 * クライアントは users ドキュメントを作れない（ルール）ので、起動時に必ずこれを呼ぶ。
 */
export async function ensureUser(
  db: Firestore,
  uid: string,
  locale: 'ja' | 'en',
  now: Date,
  newCode: () => string = generateReferralCode,
): Promise<EnsureUserResult> {
  const userRef = db.collection(COLLECTIONS.users).doc(uid);
  const existing = await userRef.get();
  if (existing.exists && typeof existing.get('referralCode') === 'string') {
    return resultFrom(existing.data() as FirebaseFirestore.DocumentData, now.getTime(), false);
  }

  for (let attempt = 0; attempt < 5; attempt++) {
    const code = newCode();
    const codeRef = db.collection(COLLECTIONS.referrals).doc(code);
    try {
      return await db.runTransaction(async (tx) => {
        const [userSnap, codeSnap] = await Promise.all([tx.get(userRef), tx.get(codeRef)]);
        if (userSnap.exists && typeof userSnap.get('referralCode') === 'string') {
          return resultFrom(userSnap.data() as FirebaseFirestore.DocumentData, now.getTime(), false);
        }
        if (codeSnap.exists) throw new CodeCollision();
        tx.create(codeRef, { uid, uses: 0, createdAt: Timestamp.fromDate(now) });
        const data: Record<string, unknown> = { referralCode: code };
        const emptyPro = { active: false, source: null, until: null };
        if (!userSnap.exists) {
          data.createdAt = Timestamp.fromDate(now);
          data.locale = locale;
          data.nickname = null;
          data.problemCount = 0;
          data.pro = emptyPro;
        } else {
          if (!userSnap.get('locale')) data.locale = locale;
          if (!userSnap.get('pro')) data.pro = emptyPro;
        }
        tx.set(userRef, data, { merge: true });
        const base = userSnap.exists ? (userSnap.data() as FirebaseFirestore.DocumentData) : {};
        return resultFrom({ ...base, referralCode: code }, now.getTime(), !userSnap.exists);
      });
    } catch (err) {
      if (err instanceof CodeCollision) continue;
      throw err;
    }
  }
  throw new Error('could not allocate a unique referral code');
}
