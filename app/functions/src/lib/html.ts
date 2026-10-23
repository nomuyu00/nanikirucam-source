import { fmt, strings } from './i18n';
import type { Lang, Strings } from './i18n';
import { appStoreUrl, playStoreUrl } from './storeLinks';
import type { StoreConfig } from './storeLinks';
import { isTileLabel, tileImagePath, tileName } from './tiles';
import { MELD_KINDS } from './validate';
import type { MeldInput, Wind } from './validate';

/** HTML の本文・属性値に安全に埋め込めるようにエスケープする。 */
export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * `<script type="application/json">` に埋め込む JSON。
 * `</script>` で閉じられないよう `<` `>` `&` と行区切り文字をエスケープする。
 */
export function jsonForScript(value: unknown): string {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

/** 公開してよい問題の項目（答えは含めない）。 */
export interface PublicProblem {
  tiles: string[];
  melds: MeldInput[];
  dora: string[];
  seatWind: Wind;
  roundWind: Wind;
  turn: number | null;
  authorNickname: string;
}

export interface PageContext {
  problemId: string;
  problem: PublicProblem;
  lang: Lang;
  siteUrl: string;
  /** OGP 画像の絶対 URL */
  ogImageUrl: string;
  /** OGP 画像が共有カード（1080×1080）なら true、既定画像（1200×630）なら false */
  ogImageIsCard: boolean;
  /** 検証済みの紹介コード */
  ref: string | null;
  stores: StoreConfig;
  /** GA4 の測定 ID。空なら読み込まない。 */
  ga4Id: string;
  /** Smart App Banner 用の App Store ID。空なら出さない。 */
  appleAppId: string;
}

function metaLine(p: PublicProblem, s: Strings): string {
  const parts = [s.round[p.roundWind], s.seat[p.seatWind]];
  if (p.turn) parts.push(fmt(s.turn, { n: p.turn }));
  return parts.join(' ');
}

function tileImg(label: string, lang: Lang, cls: string): string {
  const name = tileName(label, lang);
  return `<img class="${cls}" src="${escapeHtml(tileImagePath(label))}" alt="${escapeHtml(name)}" width="160" height="208" decoding="async">`;
}

function handHtml(ctx: PageContext, s: Strings): string {
  const { tiles } = ctx.problem;
  const last = tiles.length - 1;
  const items = tiles
    .map((label, i) => {
      const name = tileName(label, ctx.lang);
      const isTsumo = i === last;
      const cls = isTsumo ? 'tile tsumo' : 'tile';
      return `<li><button type="button" class="${cls}" data-tile="${escapeHtml(label)}" aria-label="${escapeHtml(
        ctx.lang === 'en' ? `Discard ${name}` : `${name}を切る`,
      )}">${tileImg(label, ctx.lang, 'tile-img')}${
        isTsumo ? `<span class="tsumo-label">${escapeHtml(s.tsumoLabel)}</span>` : ''
      }</button></li>`;
    })
    .join('');
  return `<ol class="hand" aria-label="${escapeHtml(s.handLabel)}">${items}</ol>`;
}

function meldsHtml(ctx: PageContext, s: Strings): string {
  const { melds } = ctx.problem;
  if (melds.length === 0) return '';
  const groups = melds
    .map((m) => {
      const imgs = m.tiles
        .map((label, i) => {
          // 開いた副露は先頭の牌を横向きに倒して示す（鳴いた牌の位置は保存していない）
          const sideways = m.kind !== 'ankan' && i === 0 ? ' sideways' : '';
          return tileImg(label, ctx.lang, `meld-img${sideways}`);
        })
        .join('');
      return `<li class="meld">${imgs}</li>`;
    })
    .join('');
  return `<div class="melds"><span class="label">${escapeHtml(s.meldLabel)}</span><ul>${groups}</ul></div>`;
}

function doraHtml(ctx: PageContext, s: Strings): string {
  const { dora } = ctx.problem;
  if (dora.length === 0) return '';
  const imgs = dora.map((label) => tileImg(label, ctx.lang, 'dora-img')).join('');
  return `<div class="dora"><span class="label">${escapeHtml(s.doraLabel)}</span>${imgs}</div>`;
}

/**
 * DB の値が壊れていても HTML を壊さないよう、牌ラベルと副露の種類を検査して不正なものを落とす
 * （公開時にも検査しているので、通常は何も落ちない）。
 */
export function withValidTiles(ctx: PageContext): PageContext {
  const p = ctx.problem;
  return {
    ...ctx,
    problem: {
      ...p,
      tiles: p.tiles.filter(isTileLabel),
      dora: p.dora.filter(isTileLabel),
      melds: p.melds
        .filter((m) => (MELD_KINDS as readonly string[]).includes(m.kind))
        .map((m) => ({ kind: m.kind, tiles: m.tiles.filter(isTileLabel) })),
    },
  };
}

/** 問題ページ（SSR）。`og:image` は共有カード、無ければ既定画像。 */
export function renderProblemPage(rawCtx: PageContext): string {
  const ctx = withValidTiles(rawCtx);
  const s = strings(ctx.lang);
  const url = `${ctx.siteUrl}/p/${ctx.problemId}`;
  const title = `${s.title} | ${s.appName}`;
  const info = metaLine(ctx.problem, s);
  const description = s.description;
  const iosUrl = appStoreUrl(ctx.stores, { pid: ctx.problemId, ref: ctx.ref, campaign: 'problem' });
  const androidUrl = playStoreUrl(ctx.stores, {
    pid: ctx.problemId,
    ref: ctx.ref,
    campaign: 'problem',
  });
  // App Store の ID が未設定のうちは（公開前）、リンク先がないので iOS のボタンは出さない
  const iosButton = ctx.stores.iosAppStoreId
    ? `<a class="btn store" data-store="ios" href="${escapeHtml(iosUrl)}" rel="noopener">${escapeHtml(s.appStore)}</a>
`
    : '';
  const imageW = ctx.ogImageIsCard ? 1080 : 1200;
  const imageH = ctx.ogImageIsCard ? 1080 : 630;
  const ogLocale = ctx.lang === 'en' ? 'en_US' : 'ja_JP';

  const data = {
    problemId: ctx.problemId,
    lang: ctx.lang,
    answerEndpoint: '/api/answer',
    ga4Id: ctx.ga4Id,
    tiles: ctx.problem.tiles,
    t: s,
  };

  const author = ctx.problem.authorNickname
    ? `<span class="author">${escapeHtml(s.authorLabel)}: ${escapeHtml(ctx.problem.authorNickname)}</span>`
    : '';

  const smartBanner = ctx.appleAppId
    ? `\n<meta name="apple-itunes-app" content="app-id=${escapeHtml(ctx.appleAppId)}, app-argument=${escapeHtml(url)}">`
    : '';

  return `<!doctype html>
<html lang="${ctx.lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta name="robots" content="noindex,follow">
<link rel="canonical" href="${escapeHtml(url)}">
<link rel="icon" href="/assets/icon-192.png">
<meta property="og:type" content="website">
<meta property="og:site_name" content="${escapeHtml(s.appName)}">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:url" content="${escapeHtml(url)}">
<meta property="og:locale" content="${ogLocale}">
<meta property="og:image" content="${escapeHtml(ctx.ogImageUrl)}">
<meta property="og:image:width" content="${imageW}">
<meta property="og:image:height" content="${imageH}">
<meta property="og:image:alt" content="${escapeHtml(s.title)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="${escapeHtml(title)}">
<meta name="twitter:description" content="${escapeHtml(description)}">
<meta name="twitter:image" content="${escapeHtml(ctx.ogImageUrl)}">${smartBanner}
<link rel="stylesheet" href="/assets/site.css">
</head>
<body class="problem-page">
<header class="site-header"><a class="brand" href="/">${escapeHtml(s.appName)}</a></header>
<main class="problem" id="nk-root">
<h1>${escapeHtml(s.title)}</h1>
<p class="info"><span>${escapeHtml(info)}</span>${author}</p>
${doraHtml(ctx, s)}
${handHtml(ctx, s)}
${meldsHtml(ctx, s)}
<p class="hint" id="nk-hint">${escapeHtml(s.tapHint)}</p>
<noscript><p class="error">${escapeHtml(s.noscript)}</p></noscript>
<section id="nk-result" class="result" aria-live="polite" hidden></section>
<section class="cta" id="nk-cta">
<h2>${escapeHtml(s.ctaButton)}</h2>
<p class="lead">${escapeHtml(s.ctaTitle)}</p>
<p>${escapeHtml(s.ctaBody)}</p>
<div class="stores">
${iosButton}<a class="btn store" data-store="android" href="${escapeHtml(androidUrl)}" rel="noopener">${escapeHtml(s.googlePlay)}</a>
</div>
</section>
<p class="disclaimer">${escapeHtml(s.disclaimer)}</p>
</main>
<footer class="site-footer">
<a href="/terms">${escapeHtml(s.terms)}</a>
<a href="/privacy">${escapeHtml(s.privacy)}</a>
<a href="/tokushoho">${escapeHtml(s.tokushoho)}</a>
</footer>
<script type="application/json" id="nk-data">${jsonForScript(data)}</script>
<script src="/assets/problem.js" defer></script>
</body>
</html>
`;
}

/** 404 の HTML（`noindex`）。 */
export function renderNotFoundPage(lang: Lang): string {
  const s = strings(lang);
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(s.notFoundTitle)} | ${escapeHtml(s.appName)}</title>
<meta name="robots" content="noindex">
<link rel="icon" href="/assets/icon-192.png">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>
<header class="site-header"><a class="brand" href="/">${escapeHtml(s.appName)}</a></header>
<main class="problem">
<h1>${escapeHtml(s.notFoundTitle)}</h1>
<p>${escapeHtml(s.notFoundBody)}</p>
<p><a class="btn" href="/">${escapeHtml(s.toTop)}</a></p>
</main>
</body>
</html>
`;
}

/** 問題ページのレスポンスに付ける CSP。インラインのスクリプト・スタイルは使わない。 */
export function contentSecurityPolicy(): string {
  return [
    "default-src 'self'",
    "script-src 'self' https://www.googletagmanager.com",
    "style-src 'self'",
    "img-src 'self' data: https://firebasestorage.googleapis.com https://www.google-analytics.com https://*.google-analytics.com https://www.googletagmanager.com",
    "connect-src 'self' https://www.google-analytics.com https://*.google-analytics.com https://*.analytics.google.com https://www.googletagmanager.com",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join('; ');
}
