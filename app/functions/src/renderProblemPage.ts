import './globals';
import { getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions/v2';
import { onRequest } from 'firebase-functions/v2/https';
import { ANDROID_PACKAGE, GA4_MEASUREMENT_ID, IOS_APP_STORE_ID, IOS_PROVIDER_TOKEN, SITE_URL } from './config';
import { COLLECTIONS } from './core/types';
import { contentSecurityPolicy, renderNotFoundPage, renderProblemPage as render } from './lib/html';
import { pickLang } from './lib/i18n';
import { extractProblemIdFromPath } from './lib/problemId';
import { normalizeReferralCode } from './lib/referral';
import { cardPathFor, cardPublicUrl } from './lib/storeLinks';
import { bucketName, cardExists } from './storage';

function securityHeaders(res: import('express').Response) {
  res.set('Content-Type', 'text/html; charset=utf-8');
  res.set('Content-Security-Policy', contentSecurityPolicy());
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  res.set('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  res.set('Vary', 'Accept-Language');
}

/**
 * Web 問題ページの SSR（HTTPS、Hosting の rewrite `/p/**`）。
 * OGP メタ（`og:image` は Storage のカード、無ければ既定画像）付きの HTML を返す。
 * 答えと統計は HTML に含めない（回答後に `answerProblem` が返す）ので、CDN にキャッシュできる。
 */
export const renderProblemPage = onRequest({ maxInstances: 20 }, async (req, res) => {
  const lang = pickLang(req.get('accept-language'), req.query.lang);
  securityHeaders(res);

  const problemId = extractProblemIdFromPath(req.path);
  if (!problemId) {
    res.set('Cache-Control', 'public, max-age=60, s-maxage=60');
    res.status(404).send(renderNotFoundPage(lang));
    return;
  }

  try {
    const snap = await getFirestore().collection(COLLECTIONS.problems).doc(problemId).get();
    if (!snap.exists || snap.get('hidden') === true) {
      res.set('Cache-Control', 'public, max-age=60, s-maxage=60');
      res.status(404).send(renderNotFoundPage(lang));
      return;
    }

    const siteUrl = SITE_URL.value().replace(/\/$/, '');
    const cardPath: string = snap.get('cardPath') ?? cardPathFor(problemId);
    const bucket = bucketName();
    const hasCard = bucket !== '' && (await cardExists(cardPath));
    const ref = normalizeReferralCode(req.query.ref);

    const html = render({
      problemId,
      problem: {
        tiles: snap.get('tiles') ?? [],
        melds: snap.get('melds') ?? [],
        dora: snap.get('dora') ?? [],
        seatWind: snap.get('seatWind') ?? 'south',
        roundWind: snap.get('roundWind') ?? 'east',
        turn: snap.get('turn') ?? null,
        authorNickname: snap.get('authorNickname') ?? '',
      },
      lang,
      siteUrl,
      ogImageUrl: hasCard ? cardPublicUrl(bucket, cardPath) : `${siteUrl}/assets/og-default.png`,
      ogImageIsCard: hasCard,
      ref,
      stores: {
        siteUrl,
        iosAppStoreId: IOS_APP_STORE_ID.value(),
        iosProviderToken: IOS_PROVIDER_TOKEN.value(),
        androidPackage: ANDROID_PACKAGE.value(),
      },
      ga4Id: GA4_MEASUREMENT_ID.value(),
      appleAppId: IOS_APP_STORE_ID.value(),
    });
    // カードが未アップロードの間は短く、あれば長くキャッシュする
    res.set(
      'Cache-Control',
      hasCard ? 'public, max-age=300, s-maxage=3600' : 'public, max-age=60, s-maxage=120',
    );
    res.status(200).send(html);
  } catch (err) {
    logger.error('renderProblemPage failed', err);
    res.set('Cache-Control', 'no-store');
    res.status(500).send(renderNotFoundPage(lang));
  }
});
