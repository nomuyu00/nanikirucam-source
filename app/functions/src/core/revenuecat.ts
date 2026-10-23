import { Timestamp } from 'firebase-admin/firestore';
import type { Firestore } from 'firebase-admin/firestore';
import { computeEffectivePro } from '../lib/pro';
import type { RevenueCatState } from '../lib/pro';
import { decideEvent, resolveUid } from '../lib/revenuecat';
import type { RevenueCatEvent } from '../lib/revenuecat';
import { COLLECTIONS } from './types';
import { proSummaryFields } from './users';

export type WebhookOutcome =
  | { status: 'applied'; uid: string }
  | { status: 'ignored'; reason: string }
  | { status: 'unknown_user' };

function stateFromDoc(raw: FirebaseFirestore.DocumentData | undefined): RevenueCatState | null {
  if (!raw) return null;
  return {
    active: raw.active === true,
    untilMs: raw.until instanceof Timestamp ? raw.until.toMillis() : null,
    productId: raw.productId ?? null,
    store: raw.store ?? null,
    environment: raw.environment ?? null,
    periodType: raw.periodType ?? null,
    lastEventId: raw.lastEventId ?? null,
    lastEventAtMs: typeof raw.lastEventAtMs === 'number' ? raw.lastEventAtMs : 0,
  };
}

function stateToDoc(state: RevenueCatState) {
  return {
    active: state.active,
    until: state.untilMs === null ? null : Timestamp.fromMillis(state.untilMs),
    productId: state.productId,
    store: state.store,
    environment: state.environment,
    periodType: state.periodType,
    lastEventId: state.lastEventId,
    lastEventAtMs: state.lastEventAtMs,
  };
}

/** RevenueCat のイベントを `users/{uid}.pro` に反映する（`revenuecatWebhook` の本体）。 */
export async function applyRevenueCatEvent(
  db: Firestore,
  event: RevenueCatEvent,
  now: Date = new Date(),
): Promise<WebhookOutcome> {
  const nowMs = now.getTime();

  // ダッシュボードのテスト送信。ユーザーに紐づかないので何もしない。
  if (event.type === 'TEST') return { status: 'ignored', reason: 'test' };

  if (event.type === 'TRANSFER') {
    // 権利が別の App User ID へ移った。移動元は無効にする（移動先には続けてイベントが届く）。
    const from = (event.transferred_from ?? []).filter((id) => id && !id.startsWith('$RCAnonymousID:'));
    let touched = 0;
    for (const uid of from) {
      const ref = db.collection(COLLECTIONS.users).doc(uid);
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists) return;
        const prev = stateFromDoc(snap.get('pro.revenuecat'));
        if (!prev || !prev.active) return;
        const next: RevenueCatState = { ...prev, active: false };
        const summary = computeEffectivePro(next, referralOf(snap.get('pro')), nowMs);
        tx.set(
          ref,
          { pro: { ...proSummaryFields(summary), revenuecat: stateToDoc(next) } },
          { merge: true },
        );
        touched++;
      });
    }
    return touched > 0 ? { status: 'applied', uid: from[0] } : { status: 'ignored', reason: 'transfer' };
  }

  const uid = resolveUid(event);
  if (!uid) return { status: 'ignored', reason: 'anonymous_user' };

  const ref = db.collection(COLLECTIONS.users).doc(uid);
  return db.runTransaction(async (tx): Promise<WebhookOutcome> => {
    const snap = await tx.get(ref);
    if (!snap.exists) return { status: 'unknown_user' };

    const prev = stateFromDoc(snap.get('pro.revenuecat'));
    const decision = decideEvent(prev, event, nowMs);
    if (decision.action === 'ignore') return { status: 'ignored', reason: decision.reason };

    const summary = computeEffectivePro(decision.state, referralOf(snap.get('pro')), nowMs);
    tx.set(
      ref,
      { pro: { ...proSummaryFields(summary), revenuecat: stateToDoc(decision.state) } },
      { merge: true },
    );
    return { status: 'applied', uid };
  });
}

function referralOf(pro: FirebaseFirestore.DocumentData | undefined) {
  const until = pro?.referral?.until;
  return until instanceof Timestamp ? { untilMs: until.toMillis() } : null;
}
