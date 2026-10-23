import { AdapterError, readJson } from './types';
import type { FetchLike, PostPayload, PostRef, SocialAdapter } from './types';

export interface ThreadsConfig {
  userId: string;
  accessToken: string;
  baseUrl?: string;
}

const sleepDefault = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/**
 * Threads API（Meta）での投稿。コンテナ作成 → 処理完了待ち → 公開 の 3 段階。
 * 画像は公開 URL で渡す（`image.publicUrl` が必要。無ければテキストのみ）。
 */
export class ThreadsAdapter implements SocialAdapter {
  readonly platform = 'threads' as const;
  private readonly base: string;

  constructor(
    private readonly config: ThreadsConfig,
    private readonly fetchFn: FetchLike = fetch,
    private readonly sleep: (ms: number) => Promise<void> = sleepDefault,
    private readonly pollIntervalMs = 3000,
    private readonly maxPolls = 20,
  ) {
    this.base = (config.baseUrl ?? 'https://graph.threads.net/v1.0').replace(/\/$/, '');
  }

  private async form(path: string, params: Record<string, string>, what: string) {
    const body = new URLSearchParams({ ...params, access_token: this.config.accessToken });
    const res = await this.fetchFn(`${this.base}${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    });
    return readJson(res, 'threads', what);
  }

  private async waitUntilReady(containerId: string): Promise<void> {
    for (let i = 0; i < this.maxPolls; i++) {
      const url = `${this.base}/${containerId}?fields=status,error_message&access_token=${encodeURIComponent(this.config.accessToken)}`;
      const res = await this.fetchFn(url, { method: 'GET' });
      const json = await readJson(res, 'threads', 'container status');
      if (json.status === 'FINISHED') return;
      if (json.status === 'ERROR' || json.status === 'EXPIRED') {
        throw new AdapterError('threads', `container ${json.status}: ${json.error_message ?? ''}`);
      }
      await this.sleep(this.pollIntervalMs);
    }
    throw new AdapterError('threads', 'container was not ready in time');
  }

  async post(payload: PostPayload): Promise<PostRef> {
    const params: Record<string, string> = { text: payload.text };
    if (payload.image?.publicUrl) {
      params.media_type = 'IMAGE';
      params.image_url = payload.image.publicUrl;
    } else {
      params.media_type = 'TEXT';
    }
    if (payload.replyTo) params.reply_to_id = payload.replyTo.id;

    const container = await this.form(`/${this.config.userId}/threads`, params, 'create container');
    if (!container.id) throw new AdapterError('threads', 'create container: no id');
    if (params.media_type === 'IMAGE') await this.waitUntilReady(container.id);

    const published = await this.form(
      `/${this.config.userId}/threads_publish`,
      { creation_id: container.id },
      'publish',
    );
    if (!published.id) throw new AdapterError('threads', 'publish: no id');
    return { id: published.id };
  }
}

/** 長期トークン（60 日有効）の更新。期限内に呼ぶ必要がある。 */
export async function refreshThreadsToken(
  accessToken: string,
  fetchFn: FetchLike = fetch,
  baseUrl = 'https://graph.threads.net',
): Promise<{ accessToken: string; expiresInSec: number }> {
  const url = `${baseUrl}/refresh_access_token?grant_type=th_refresh_token&access_token=${encodeURIComponent(accessToken)}`;
  const res = await fetchFn(url, { method: 'GET' });
  const json = await readJson(res, 'threads', 'refresh token');
  if (!json.access_token) throw new AdapterError('threads', 'refresh token: no access_token');
  return { accessToken: json.access_token, expiresInSec: Number(json.expires_in) || 0 };
}
