import { BlueskyAdapter } from './bluesky';
import { DiscordAdapter } from './discord';
import { ThreadsAdapter } from './threads';
import type { FetchLike, SocialAdapter } from './types';
import { XAdapter } from './x';
import type { XCredentials } from './x';

export * from './types';
export { BlueskyAdapter, buildFacets } from './bluesky';
export { DiscordAdapter } from './discord';
export { ThreadsAdapter, refreshThreadsToken } from './threads';
export { XAdapter } from './x';

/** 実行時に読み取った設定値。空文字・未設定・`-` は「その投稿先は使わない」。 */
export interface AdapterEnv {
  blueskyHandle?: string;
  blueskyAppPassword?: string;
  threadsUserId?: string;
  threadsAccessToken?: string;
  discordWebhookUrl?: string;
  xEnabled?: boolean;
  /** JSON 文字列 `{apiKey,apiSecret,accessToken,accessSecret}` */
  xCredentialsJson?: string;
}

/** 未設定扱いの値（Secret に仮の `-` を入れた場合も未設定とみなす）。 */
export function isUnset(value: string | undefined | null): boolean {
  const v = (value ?? '').trim();
  return v === '' || v === '-';
}

export function parseXCredentials(json: string | undefined): XCredentials | null {
  if (isUnset(json)) return null;
  try {
    const raw = JSON.parse(json as string);
    if (
      typeof raw.apiKey === 'string' &&
      typeof raw.apiSecret === 'string' &&
      typeof raw.accessToken === 'string' &&
      typeof raw.accessSecret === 'string'
    ) {
      return raw as XCredentials;
    }
  } catch {
    // 不正な JSON は無効扱い
  }
  return null;
}

/** 設定の揃った投稿先だけのアダプタ一覧を作る。 */
export function buildAdapters(env: AdapterEnv, fetchFn?: FetchLike): SocialAdapter[] {
  const adapters: SocialAdapter[] = [];
  if (!isUnset(env.blueskyHandle) && !isUnset(env.blueskyAppPassword)) {
    adapters.push(
      new BlueskyAdapter(
        { identifier: env.blueskyHandle as string, password: env.blueskyAppPassword as string },
        fetchFn,
      ),
    );
  }
  if (!isUnset(env.threadsUserId) && !isUnset(env.threadsAccessToken)) {
    adapters.push(
      new ThreadsAdapter(
        { userId: env.threadsUserId as string, accessToken: env.threadsAccessToken as string },
        fetchFn,
      ),
    );
  }
  if (!isUnset(env.discordWebhookUrl)) {
    adapters.push(new DiscordAdapter({ webhookUrl: env.discordWebhookUrl as string }, fetchFn));
  }
  if (env.xEnabled) {
    const creds = parseXCredentials(env.xCredentialsJson);
    if (creds) adapters.push(new XAdapter(creds, fetchFn));
  }
  return adapters;
}
