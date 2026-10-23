import { isReferralCode } from './referral';

export interface StoreConfig {
  /** 例: `https://nanikiru-cam.web.app`（末尾スラッシュなし） */
  siteUrl: string;
  /** App Store の数値 ID。未設定ならトップページへ。 */
  iosAppStoreId: string;
  /** App Store Connect のキャンペーンリンクのプロバイダトークン。 */
  iosProviderToken: string;
  androidPackage: string;
}

export interface StoreLinkContext {
  /** 問題 ID（問題ページ経由のとき） */
  pid?: string;
  /** 紹介コード */
  ref?: string | null;
  /** `problem` / `referral` など */
  campaign: string;
}

/**
 * Google Play のリンク。`referrer` に流入元・問題 ID・紹介コードを入れる。
 * アプリは初回起動時に Install Referrer API から `pid` と `ref` を読む（設計書 7 章）。
 */
export function playStoreUrl(cfg: StoreConfig, ctx: StoreLinkContext): string {
  const parts = [`utm_source=share`, `utm_campaign=${ctx.campaign}`];
  if (ctx.pid) parts.push(`pid=${ctx.pid}`);
  if (ctx.ref && isReferralCode(ctx.ref)) parts.push(`ref=${ctx.ref}`);
  const referrer = encodeURIComponent(parts.join('&'));
  return `https://play.google.com/store/apps/details?id=${encodeURIComponent(cfg.androidPackage)}&referrer=${referrer}`;
}

/**
 * App Store のリンク。iOS は v1 では遅延ディープリンクを持たないので、
 * 計測用の `pt`/`ct` だけを付ける（`pid` と `ref` は付けられない）。
 * App Store の ID が未設定のときは、紹介コード付きのトップページに戻す。
 */
export function appStoreUrl(cfg: StoreConfig, ctx: StoreLinkContext): string {
  if (!cfg.iosAppStoreId) return cfg.siteUrl + '/';
  const base = `https://apps.apple.com/jp/app/id${encodeURIComponent(cfg.iosAppStoreId)}`;
  if (!cfg.iosProviderToken) return base;
  return `${base}?pt=${encodeURIComponent(cfg.iosProviderToken)}&ct=${encodeURIComponent(ctx.campaign)}&mt=8`;
}

/** 問題ページの URL。 */
export function problemUrl(siteUrl: string, problemId: string, ref?: string | null): string {
  const query = ref && isReferralCode(ref) ? `?ref=${ref}` : '';
  return `${siteUrl}/p/${problemId}${query}`;
}

/** Storage の公開 URL（カード PNG）。Storage ルールで cards/** は誰でも読める。 */
export function cardPublicUrl(bucket: string, cardPath: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${encodeURIComponent(cardPath)}?alt=media`;
}

export function cardPathFor(problemId: string): string {
  return `cards/${problemId}/1x1.png`;
}
