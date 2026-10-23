/**
 * 全関数の共通初期化。各関数ファイルの先頭で `import './globals'` する。
 * - Admin SDK の初期化
 * - 既定のリージョン（東京）と同時実行の上限
 */
import { getApps, initializeApp } from 'firebase-admin/app';
import { setGlobalOptions } from 'firebase-functions/v2';

if (getApps().length === 0) initializeApp();

setGlobalOptions({
  region: 'asia-northeast1',
  maxInstances: 10,
  memory: '256MiB',
});

/** Hosting の rewrite（firebase.json）と同じリージョン。 */
export const REGION = 'asia-northeast1';
