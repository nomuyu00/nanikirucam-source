import type { Firestore } from 'firebase-admin/firestore';
import { buildAdapters, isUnset } from './lib/adapters';
import type { SocialAdapter } from './lib/adapters';
import { resolveThreadsToken } from './core/threadsToken';
import {
  BLUESKY_APP_PASSWORD,
  BLUESKY_HANDLE,
  DISCORD_WEBHOOK_URL,
  THREADS_ACCESS_TOKEN,
  THREADS_USER_ID,
  X_CREDENTIALS,
  X_ENABLED,
} from './config';

/** 実行時の設定から、設定の揃った投稿先のアダプタを作る。 */
export async function runtimeAdapters(db: Firestore, now: Date = new Date()): Promise<SocialAdapter[]> {
  const threadsSecret = THREADS_ACCESS_TOKEN.value();
  const threadsUser = THREADS_USER_ID.value();
  const threadsToken =
    !isUnset(threadsSecret) && !isUnset(threadsUser)
      ? await resolveThreadsToken(db, threadsSecret, now)
      : threadsSecret;
  return buildAdapters({
    blueskyHandle: BLUESKY_HANDLE.value(),
    blueskyAppPassword: BLUESKY_APP_PASSWORD.value(),
    threadsUserId: threadsUser,
    threadsAccessToken: threadsToken,
    discordWebhookUrl: DISCORD_WEBHOOK_URL.value(),
    xEnabled: X_ENABLED.value(),
    xCredentialsJson: X_CREDENTIALS.value(),
  });
}
