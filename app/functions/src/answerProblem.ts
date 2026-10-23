import './globals';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onRequest } from 'firebase-functions/v2/https';
import { answerProblemCore } from './core/answer';
import { notifyAnswerMilestone } from './core/notify';
import { bearerToken, parseAnswerBody } from './lib/answerRequest';

/**
 * 回答の受け付け（HTTPS、Web とアプリ共通）。`POST /api/answer`（Hosting の rewrite）。
 * - Web: 端末ごとの `fingerprint`（ブラウザが作るランダム ID）で二重回答を判定。
 * - アプリ: `Authorization: Bearer <Firebase ID トークン>` の uid で判定。
 * 同じ fingerprint の 2 回目は集計せず、最初の回答と現在の集計を返す。
 * CORS は全許可（Cookie を使わない公開 API なので）。
 */
export const answerProblem = onRequest({ cors: true, maxInstances: 20 }, async (req, res) => {
  res.set('Cache-Control', 'no-store');
  const fail = (status: number, code: string, message: string) => {
    res.status(status).json({ error: { code, message } });
  };

  if (req.method !== 'POST') {
    res.set('Allow', 'POST');
    fail(405, 'method_not_allowed', 'Use POST');
    return;
  }

  const parsed = parseAnswerBody(req.body);
  if (!parsed.ok) {
    fail(400, parsed.code, parsed.message);
    return;
  }
  const { problemId, tile, source, selfRank } = parsed.value;

  let uid: string | null = null;
  let fingerprintRaw = parsed.value.fingerprint;
  if (source === 'app') {
    const token = bearerToken(req.get('authorization'));
    if (!token) {
      fail(401, 'unauthenticated', 'Authorization: Bearer <ID token> is required for source=app');
      return;
    }
    try {
      uid = (await getAuth().verifyIdToken(token)).uid;
    } catch {
      fail(401, 'unauthenticated', 'ID token is invalid or expired');
      return;
    }
    fingerprintRaw = uid;
  }
  if (!fingerprintRaw) {
    fail(400, 'invalid_fingerprint', 'fingerprint is required');
    return;
  }

  try {
    const db = getFirestore();
    const outcome = await answerProblemCore(db, {
      problemId,
      tile,
      source,
      fingerprintRaw,
      uid,
      selfRank,
    });
    if (outcome.kind === 'not_found') {
      fail(404, 'not_found', 'problem not found');
      return;
    }
    if (outcome.kind === 'invalid_tile') {
      fail(400, 'invalid_tile', 'tile is not in the hand of this problem');
      return;
    }
    // 節目（10/50/100 人）に達したら出題者へ通知（失敗しても回答は成功）
    if (outcome.milestone) await notifyAnswerMilestone(db, outcome.milestone);

    res.status(200).json({
      ok: true,
      alreadyAnswered: outcome.alreadyAnswered,
      yourTile: outcome.yourTile,
      correct: outcome.correct,
      judgement: outcome.judgement,
      stats: outcome.stats,
      answer: outcome.answer,
    });
  } catch (err) {
    logger.error('answerProblem failed', err);
    fail(500, 'internal', 'internal error');
  }
});
