/**
 * 設定値（デプロイ時に `.env.<projectId>` や Secret Manager から注入される）。
 * 秘密情報は `defineSecret`。未使用の投稿先も、デプロイ前に Secret へ仮の値 `-` を入れる
 * （`-` と空文字は「その投稿先は使わない」として扱う）。
 */
import { defineBoolean, defineSecret, defineString } from 'firebase-functions/params';

// --- 運用ポリシー（定数）---
/** 通報がこの件数に達した問題は `hidden = true` にする。 */
export const REPORT_HIDE_THRESHOLD = 3;
/**
 * 通報が件数に数えられる最小のアカウント年齢（ミリ秒）。`users/{uid}.createdAt` からの経過時間。
 * これ未満の uid（匿名アカウントの使い捨て）の通報は記録だけして `reports` に加算しない。
 * `users/{uid}` が無い uid の通報も数えない。
 */
export const REPORTER_MIN_ACCOUNT_AGE_MS = 24 * 60 * 60 * 1000;

// --- 公開 URL・ストア ---
/** Hosting のオリジン（末尾スラッシュなし）。独自ドメインを使うならそれに変える。 */
export const SITE_URL = defineString('SITE_URL', { default: 'https://nanikiru-cam.web.app' });
export const IOS_APP_STORE_ID = defineString('IOS_APP_STORE_ID', { default: '' });
/** App Store Connect のキャンペーンリンクのプロバイダトークン（pt）。 */
export const IOS_PROVIDER_TOKEN = defineString('IOS_PROVIDER_TOKEN', { default: '' });
export const ANDROID_PACKAGE = defineString('ANDROID_PACKAGE', { default: 'jp.aile.nanikiru_cam' });

// --- 計測・セキュリティ ---
/** Web の GA4 測定 ID（G-XXXXXXXXXX）。空なら読み込まない。 */
export const GA4_MEASUREMENT_ID = defineString('GA4_MEASUREMENT_ID', { default: '' });
/**
 * App Check を必須にする（クライアントに App Check を入れてから `.env.<projectId>` に
 * `ENFORCE_APP_CHECK=true` を書いて再デプロイする）。
 * defineBoolean にしないのは、callable のオプションに Param を渡すとデプロイ時の探索で
 * `.value()` が呼ばれて警告が出るため。`.env` の値は実行時の環境変数に入っている。
 */
export const ENFORCE_APP_CHECK: boolean = process.env.ENFORCE_APP_CHECK === 'true';

// --- RevenueCat ---
/** ダッシュボードの Webhook 設定「Authorization header value」と同じ値。 */
export const REVENUECAT_WEBHOOK_SECRET = defineSecret('REVENUECAT_WEBHOOK_SECRET');

// --- 自動投稿 ---
export const BLUESKY_HANDLE = defineString('BLUESKY_HANDLE', { default: '' });
export const BLUESKY_APP_PASSWORD = defineSecret('BLUESKY_APP_PASSWORD');
export const THREADS_USER_ID = defineString('THREADS_USER_ID', { default: '' });
export const THREADS_ACCESS_TOKEN = defineSecret('THREADS_ACCESS_TOKEN');
export const DISCORD_WEBHOOK_URL = defineSecret('DISCORD_WEBHOOK_URL');
/** X への投稿（有料 API）。既定は無効。 */
export const X_ENABLED = defineBoolean('X_ENABLED', { default: false });
/** JSON 文字列 {"apiKey":"...","apiSecret":"...","accessToken":"...","accessSecret":"..."} */
export const X_CREDENTIALS = defineSecret('X_CREDENTIALS');

/** 自動投稿・週間まとめが読む Secret の一覧。 */
export const POSTING_SECRETS = [
  BLUESKY_APP_PASSWORD,
  THREADS_ACCESS_TOKEN,
  DISCORD_WEBHOOK_URL,
  X_CREDENTIALS,
];
