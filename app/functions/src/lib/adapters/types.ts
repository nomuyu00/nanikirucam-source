import type { Platform } from '../postText';

/** 投稿済みの記事への参照。返信に使う。 */
export interface PostRef {
  id: string;
  /** Bluesky の at:// URI */
  uri?: string;
  /** Bluesky の CID */
  cid?: string;
}

export interface PostImage {
  bytes: Uint8Array;
  mimeType: 'image/png';
  alt: string;
  /** 誰でも取得できる URL（Threads・Discord は URL で画像を渡す）。 */
  publicUrl?: string;
}

export interface PostPayload {
  text: string;
  image?: PostImage;
  /** 指定すると返信として投稿する（投稿先が返信に対応する場合）。 */
  replyTo?: PostRef;
}

/** 投稿先 1 つ分のアダプタ。秘密情報はコンストラクタで受け取る。 */
export interface SocialAdapter {
  readonly platform: Platform;
  post(payload: PostPayload): Promise<PostRef>;
}

export type FetchLike = (input: string, init?: RequestInit) => Promise<Response>;

export class AdapterError extends Error {
  constructor(
    public readonly platform: Platform,
    message: string,
    public readonly status?: number,
  ) {
    super(`[${platform}] ${message}`);
    this.name = 'AdapterError';
  }
}

export async function readJson(res: Response, platform: Platform, what: string): Promise<any> {
  const text = await res.text();
  if (!res.ok) {
    throw new AdapterError(platform, `${what} failed: ${res.status} ${text.slice(0, 300)}`, res.status);
  }
  try {
    return text ? JSON.parse(text) : {};
  } catch {
    throw new AdapterError(platform, `${what} returned non-JSON: ${text.slice(0, 200)}`, res.status);
  }
}
