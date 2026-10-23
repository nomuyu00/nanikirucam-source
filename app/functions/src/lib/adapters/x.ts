import { createHmac, randomBytes } from 'node:crypto';
import { AdapterError, readJson } from './types';
import type { FetchLike, PostPayload, PostRef, SocialAdapter } from './types';

export interface XCredentials {
  apiKey: string;
  apiSecret: string;
  accessToken: string;
  accessSecret: string;
}

/** RFC 3986 のパーセントエンコード（OAuth 1.0a 用）。 */
export function percentEncode(value: string): string {
  return encodeURIComponent(value).replace(
    /[!'()*]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

/**
 * OAuth 1.0a (HMAC-SHA1) の署名を計算する。
 * `params` には OAuth のパラメータとクエリ・フォームのパラメータを含める
 * （JSON 本文は署名に含めない）。
 */
export function oauthSignature(
  method: string,
  url: string,
  params: Record<string, string>,
  apiSecret: string,
  tokenSecret: string,
): string {
  const normalized = Object.entries(params)
    .map(([k, v]) => [percentEncode(k), percentEncode(v)] as const)
    .sort((a, b) => (a[0] === b[0] ? (a[1] < b[1] ? -1 : 1) : a[0] < b[0] ? -1 : 1))
    .map(([k, v]) => `${k}=${v}`)
    .join('&');
  const base = [method.toUpperCase(), percentEncode(url), percentEncode(normalized)].join('&');
  const key = `${percentEncode(apiSecret)}&${percentEncode(tokenSecret)}`;
  return createHmac('sha1', key).update(base).digest('base64');
}

export function buildOauthHeader(
  method: string,
  url: string,
  creds: XCredentials,
  nonce: string = randomBytes(16).toString('hex'),
  timestamp: string = String(Math.floor(Date.now() / 1000)),
): string {
  const oauth: Record<string, string> = {
    oauth_consumer_key: creds.apiKey,
    oauth_nonce: nonce,
    oauth_signature_method: 'HMAC-SHA1',
    oauth_timestamp: timestamp,
    oauth_token: creds.accessToken,
    oauth_version: '1.0',
  };
  const signature = oauthSignature(method, url, oauth, creds.apiSecret, creds.accessSecret);
  const all = { ...oauth, oauth_signature: signature };
  return (
    'OAuth ' +
    Object.entries(all)
      .map(([k, v]) => `${percentEncode(k)}="${percentEncode(v)}"`)
      .join(', ')
  );
}

/**
 * X (Twitter) API v2 での投稿。有料プランが必要で、既定では無効。
 * 画像は直接アップロードせず、本文の問題ページ URL の OGP カード
 * （twitter:card=summary_large_image）に任せる。
 */
export class XAdapter implements SocialAdapter {
  readonly platform = 'x' as const;

  constructor(
    private readonly creds: XCredentials,
    private readonly fetchFn: FetchLike = fetch,
    private readonly endpoint = 'https://api.x.com/2/tweets',
  ) {}

  async post(payload: PostPayload): Promise<PostRef> {
    const body: Record<string, unknown> = { text: payload.text };
    if (payload.replyTo) body.reply = { in_reply_to_tweet_id: payload.replyTo.id };
    const res = await this.fetchFn(this.endpoint, {
      method: 'POST',
      headers: {
        Authorization: buildOauthHeader('POST', this.endpoint, this.creds),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    });
    const json = await readJson(res, 'x', 'create tweet');
    const id = json?.data?.id;
    if (!id) throw new AdapterError('x', 'create tweet: no id');
    return { id: String(id) };
  }
}
