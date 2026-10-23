import { AdapterError, readJson } from './types';
import type { FetchLike, PostPayload, PostRef, SocialAdapter } from './types';

export interface DiscordConfig {
  /** Webhook URL（トークンを含むので Secret にする）。 */
  webhookUrl: string;
  username?: string;
}

/** Discord Webhook。返信機能はないので、返信も新しいメッセージとして投稿する。 */
export class DiscordAdapter implements SocialAdapter {
  readonly platform = 'discord' as const;

  constructor(
    private readonly config: DiscordConfig,
    private readonly fetchFn: FetchLike = fetch,
  ) {}

  async post(payload: PostPayload): Promise<PostRef> {
    const body: Record<string, unknown> = {
      content: payload.text,
      username: this.config.username ?? 'なにきるカム',
      // 本文に @everyone などが紛れても通知が飛ばないようにする
      allowed_mentions: { parse: [] },
    };
    if (payload.image?.publicUrl) {
      body.embeds = [{ image: { url: payload.image.publicUrl } }];
    }
    const url = `${this.config.webhookUrl}${this.config.webhookUrl.includes('?') ? '&' : '?'}wait=true`;
    const res = await this.fetchFn(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const json = await readJson(res, 'discord', 'execute webhook');
    if (!json.id) throw new AdapterError('discord', 'execute webhook: no message id');
    return { id: String(json.id) };
  }
}
