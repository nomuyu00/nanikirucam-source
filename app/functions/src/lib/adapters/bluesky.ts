import { AdapterError, readJson } from './types';
import type { FetchLike, PostPayload, PostRef, SocialAdapter } from './types';

export interface BlueskyConfig {
  /** ハンドル（例: nanikiru.bsky.social）または DID。 */
  identifier: string;
  /** アプリパスワード（アカウントのパスワードは使わない）。 */
  password: string;
  service?: string;
}

/** Bluesky の画像 blob の上限は 1,000,000 バイト。余裕を見て切る。 */
export const BLUESKY_MAX_IMAGE_BYTES = 950_000;

interface Facet {
  index: { byteStart: number; byteEnd: number };
  features: Array<
    | { $type: 'app.bsky.richtext.facet#link'; uri: string }
    | { $type: 'app.bsky.richtext.facet#tag'; tag: string }
  >;
}

/**
 * 本文中の URL とハッシュタグをリンク・タグの facet にする。
 * facet の位置は UTF-8 のバイトオフセットで指定する。
 */
export function buildFacets(text: string): Facet[] {
  const encoder = new TextEncoder();
  const byteOffset = (charIndex: number) => encoder.encode(text.slice(0, charIndex)).length;
  const facets: Facet[] = [];

  for (const match of text.matchAll(/https?:\/\/[^\s]+/g)) {
    // 末尾の句読点・閉じ括弧はリンクに含めない
    const url = match[0].replace(/[.,;:!?)\]}、。）」』】]+$/u, '');
    const start = match.index as number;
    facets.push({
      index: { byteStart: byteOffset(start), byteEnd: byteOffset(start + url.length) },
      features: [{ $type: 'app.bsky.richtext.facet#link', uri: url }],
    });
  }

  for (const match of text.matchAll(/(^|\s)(#[^\s#]+)/gu)) {
    const tagWithHash = match[2].replace(/[.,;:!?)\]}、。）」』】]+$/u, '');
    const start = (match.index as number) + match[1].length;
    facets.push({
      index: {
        byteStart: byteOffset(start),
        byteEnd: byteOffset(start + tagWithHash.length),
      },
      features: [{ $type: 'app.bsky.richtext.facet#tag', tag: tagWithHash.slice(1) }],
    });
  }
  return facets.sort((a, b) => a.index.byteStart - b.index.byteStart);
}

export class BlueskyAdapter implements SocialAdapter {
  readonly platform = 'bluesky' as const;
  private readonly service: string;
  private session: { accessJwt: string; did: string } | null = null;

  constructor(
    private readonly config: BlueskyConfig,
    private readonly fetchFn: FetchLike = fetch,
  ) {
    this.service = (config.service ?? 'https://bsky.social').replace(/\/$/, '');
  }

  private async login(): Promise<{ accessJwt: string; did: string }> {
    if (this.session) return this.session;
    const res = await this.fetchFn(`${this.service}/xrpc/com.atproto.server.createSession`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identifier: this.config.identifier, password: this.config.password }),
    });
    const json = await readJson(res, 'bluesky', 'createSession');
    if (!json.accessJwt || !json.did) throw new AdapterError('bluesky', 'createSession: no session');
    this.session = { accessJwt: json.accessJwt, did: json.did };
    return this.session;
  }

  async post(payload: PostPayload): Promise<PostRef> {
    const session = await this.login();
    const auth = { Authorization: `Bearer ${session.accessJwt}` };

    let embed: unknown;
    if (payload.image && payload.image.bytes.length <= BLUESKY_MAX_IMAGE_BYTES) {
      const res = await this.fetchFn(`${this.service}/xrpc/com.atproto.repo.uploadBlob`, {
        method: 'POST',
        headers: { ...auth, 'Content-Type': payload.image.mimeType },
        body: payload.image.bytes,
      });
      const json = await readJson(res, 'bluesky', 'uploadBlob');
      if (!json.blob) throw new AdapterError('bluesky', 'uploadBlob: no blob');
      embed = {
        $type: 'app.bsky.embed.images',
        images: [{ alt: payload.image.alt, image: json.blob }],
      };
    }

    const record: Record<string, unknown> = {
      $type: 'app.bsky.feed.post',
      text: payload.text,
      createdAt: new Date().toISOString(),
      langs: ['ja'],
      facets: buildFacets(payload.text),
    };
    if (embed) record.embed = embed;
    if (payload.replyTo?.uri && payload.replyTo.cid) {
      // 返信先は自分の最上位の投稿なので root = parent
      const ref = { uri: payload.replyTo.uri, cid: payload.replyTo.cid };
      record.reply = { root: ref, parent: ref };
    }

    const res = await this.fetchFn(`${this.service}/xrpc/com.atproto.repo.createRecord`, {
      method: 'POST',
      headers: { ...auth, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        repo: session.did,
        collection: 'app.bsky.feed.post',
        record,
      }),
    });
    const json = await readJson(res, 'bluesky', 'createRecord');
    if (!json.uri || !json.cid) throw new AdapterError('bluesky', 'createRecord: no uri/cid');
    return { id: json.uri, uri: json.uri, cid: json.cid };
  }
}
