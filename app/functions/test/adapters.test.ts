import {
  AdapterError,
  BlueskyAdapter,
  buildAdapters,
  buildFacets,
  DiscordAdapter,
  ThreadsAdapter,
  XAdapter,
} from '../src/lib/adapters';
import type { FetchLike } from '../src/lib/adapters';
import { isUnset, parseXCredentials } from '../src/lib/adapters';
import { refreshThreadsToken } from '../src/lib/adapters/threads';
import { buildOauthHeader, oauthSignature, percentEncode } from '../src/lib/adapters/x';

interface Call {
  url: string;
  init?: RequestInit;
}

/** 呼び出しを記録し、順に用意した応答を返す fetch。 */
function mockFetch(responses: Array<{ status?: number; body: unknown }>): {
  fetch: FetchLike;
  calls: Call[];
} {
  const calls: Call[] = [];
  let i = 0;
  const fetchFn: FetchLike = async (url, init) => {
    calls.push({ url, init });
    const r = responses[Math.min(i++, responses.length - 1)];
    return new Response(typeof r.body === 'string' ? r.body : JSON.stringify(r.body), {
      status: r.status ?? 200,
    });
  };
  return { fetch: fetchFn, calls };
}

const bodyOf = (c: Call) => JSON.parse(c.init?.body as string);
const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

describe('Bluesky: facet（UTF-8 バイト位置）', () => {
  test('URL とハッシュタグの位置はバイトオフセット', () => {
    const text = '問題 https://example.com/p/AbC12345 #何切る';
    const facets = buildFacets(text);
    expect(facets).toHaveLength(2);
    const enc = new TextEncoder();
    const urlStart = enc.encode('問題 ').length; // 日本語 2 文字(6 byte) + 空白 1 byte
    expect(urlStart).toBe(7);
    expect(facets[0]).toEqual({
      index: { byteStart: 7, byteEnd: 7 + enc.encode('https://example.com/p/AbC12345').length },
      features: [{ $type: 'app.bsky.richtext.facet#link', uri: 'https://example.com/p/AbC12345' }],
    });
    const tagStart = enc.encode('問題 https://example.com/p/AbC12345 ').length;
    expect(facets[1]).toEqual({
      index: { byteStart: tagStart, byteEnd: tagStart + enc.encode('#何切る').length },
      features: [{ $type: 'app.bsky.richtext.facet#tag', tag: '何切る' }],
    });
  });

  test('URL 末尾の句読点はリンクに含めない', () => {
    const [facet] = buildFacets('見て https://example.com/a。');
    expect(facet.features[0]).toMatchObject({ uri: 'https://example.com/a' });
  });

  test('複数のタグと URL なしの本文', () => {
    const facets = buildFacets('#何切る #麻雀');
    expect(facets.map((f) => f.features[0])).toEqual([
      { $type: 'app.bsky.richtext.facet#tag', tag: '何切る' },
      { $type: 'app.bsky.richtext.facet#tag', tag: '麻雀' },
    ]);
    expect(buildFacets('リンクなし')).toEqual([]);
  });
});

describe('Bluesky: 投稿の流れ', () => {
  const session = { accessJwt: 'jwt-1', did: 'did:plc:abc' };

  test('ログイン → 画像アップロード → 投稿（画像・facet 付き）', async () => {
    const { fetch, calls } = mockFetch([
      { body: session },
      { body: { blob: { $type: 'blob', ref: { $link: 'bafk' }, mimeType: 'image/png', size: 7 } } },
      { body: { uri: 'at://did:plc:abc/app.bsky.feed.post/3k', cid: 'bafyreic' } },
    ]);
    const adapter = new BlueskyAdapter({ identifier: 'nanikiru.bsky.social', password: 'app-pass' }, fetch);
    const ref = await adapter.post({
      text: '今日の問題 https://example.com/p/AbC12345',
      image: { bytes: png, mimeType: 'image/png', alt: '説明' },
    });

    expect(ref).toEqual({
      id: 'at://did:plc:abc/app.bsky.feed.post/3k',
      uri: 'at://did:plc:abc/app.bsky.feed.post/3k',
      cid: 'bafyreic',
    });
    expect(calls.map((c) => c.url)).toEqual([
      'https://bsky.social/xrpc/com.atproto.server.createSession',
      'https://bsky.social/xrpc/com.atproto.repo.uploadBlob',
      'https://bsky.social/xrpc/com.atproto.repo.createRecord',
    ]);
    expect(bodyOf(calls[0])).toEqual({ identifier: 'nanikiru.bsky.social', password: 'app-pass' });
    const upload = calls[1].init!;
    expect((upload.headers as Record<string, string>)['Content-Type']).toBe('image/png');
    expect((upload.headers as Record<string, string>).Authorization).toBe('Bearer jwt-1');
    expect(upload.body).toBe(png);

    const create = bodyOf(calls[2]);
    expect(create.repo).toBe('did:plc:abc');
    expect(create.collection).toBe('app.bsky.feed.post');
    expect(create.record.$type).toBe('app.bsky.feed.post');
    expect(create.record.embed.images[0].alt).toBe('説明');
    expect(create.record.embed.images[0].image.ref.$link).toBe('bafk');
    expect(create.record.facets[0].features[0].uri).toBe('https://example.com/p/AbC12345');
    expect(create.record.reply).toBeUndefined();
  });

  test('返信は root と parent に親の uri/cid を入れる。画像なしならアップロードしない', async () => {
    const { fetch, calls } = mockFetch([
      { body: session },
      { body: { uri: 'at://did:plc:abc/app.bsky.feed.post/4k', cid: 'cid2' } },
    ]);
    const adapter = new BlueskyAdapter({ identifier: 'h', password: 'p' }, fetch);
    await adapter.post({
      text: '答え合わせ',
      replyTo: { id: 'at://x/y/1', uri: 'at://x/y/1', cid: 'cid1' },
    });
    expect(calls).toHaveLength(2);
    const record = bodyOf(calls[1]).record;
    expect(record.reply).toEqual({
      root: { uri: 'at://x/y/1', cid: 'cid1' },
      parent: { uri: 'at://x/y/1', cid: 'cid1' },
    });
    expect(record.embed).toBeUndefined();
  });

  test('大きすぎる画像は添付せずテキストだけ投稿する', async () => {
    const { fetch, calls } = mockFetch([
      { body: session },
      { body: { uri: 'at://a/b/c', cid: 'cid' } },
    ]);
    const adapter = new BlueskyAdapter({ identifier: 'h', password: 'p' }, fetch);
    await adapter.post({
      text: 'x',
      image: { bytes: new Uint8Array(960_000), mimeType: 'image/png', alt: 'a' },
    });
    expect(calls.map((c) => c.url.split('/').pop())).toEqual([
      'com.atproto.server.createSession',
      'com.atproto.repo.createRecord',
    ]);
  });

  test('ログイン失敗は AdapterError', async () => {
    const { fetch } = mockFetch([{ status: 401, body: { error: 'AuthenticationRequired' } }]);
    const adapter = new BlueskyAdapter({ identifier: 'h', password: 'bad' }, fetch);
    await expect(adapter.post({ text: 'x' })).rejects.toBeInstanceOf(AdapterError);
  });
});

describe('Threads', () => {
  test('画像付き: コンテナ作成 → 処理完了待ち → 公開', async () => {
    const { fetch, calls } = mockFetch([
      { body: { id: 'container-1' } },
      { body: { status: 'IN_PROGRESS' } },
      { body: { status: 'FINISHED' } },
      { body: { id: 'post-1' } },
    ]);
    const sleeps: number[] = [];
    const adapter = new ThreadsAdapter(
      { userId: '123', accessToken: 'tok' },
      fetch,
      async (ms) => {
        sleeps.push(ms);
      },
      10,
    );
    const ref = await adapter.post({
      text: '今日の問題',
      image: { bytes: png, mimeType: 'image/png', alt: 'a', publicUrl: 'https://img.example/c.png' },
    });
    expect(ref).toEqual({ id: 'post-1' });
    expect(calls[0].url).toBe('https://graph.threads.net/v1.0/123/threads');
    const create = new URLSearchParams(calls[0].init!.body as string);
    expect(create.get('media_type')).toBe('IMAGE');
    expect(create.get('image_url')).toBe('https://img.example/c.png');
    expect(create.get('text')).toBe('今日の問題');
    expect(create.get('access_token')).toBe('tok');
    expect(create.get('reply_to_id')).toBeNull();
    expect(calls[1].url).toContain('/container-1?fields=status');
    expect(sleeps).toEqual([10]);
    expect(calls[3].url).toBe('https://graph.threads.net/v1.0/123/threads_publish');
    expect(new URLSearchParams(calls[3].init!.body as string).get('creation_id')).toBe('container-1');
  });

  test('画像なしの返信: TEXT で reply_to_id を付け、待たずに公開', async () => {
    const { fetch, calls } = mockFetch([{ body: { id: 'c2' } }, { body: { id: 'post-2' } }]);
    const adapter = new ThreadsAdapter({ userId: '123', accessToken: 'tok' }, fetch);
    const ref = await adapter.post({ text: '答え合わせ', replyTo: { id: 'post-1' } });
    expect(ref).toEqual({ id: 'post-2' });
    expect(calls).toHaveLength(2);
    const create = new URLSearchParams(calls[0].init!.body as string);
    expect(create.get('media_type')).toBe('TEXT');
    expect(create.get('reply_to_id')).toBe('post-1');
  });

  test('コンテナが ERROR なら失敗', async () => {
    const { fetch } = mockFetch([
      { body: { id: 'c' } },
      { body: { status: 'ERROR', error_message: 'bad image' } },
    ]);
    const adapter = new ThreadsAdapter({ userId: '1', accessToken: 't' }, fetch, async () => {}, 1);
    await expect(
      adapter.post({
        text: 'x',
        image: { bytes: png, mimeType: 'image/png', alt: '', publicUrl: 'https://i/x.png' },
      }),
    ).rejects.toThrow(/ERROR/);
  });

  test('トークン更新', async () => {
    const { fetch, calls } = mockFetch([{ body: { access_token: 'new', token_type: 'bearer', expires_in: 5184000 } }]);
    const r = await refreshThreadsToken('old', fetch);
    expect(r).toEqual({ accessToken: 'new', expiresInSec: 5184000 });
    expect(calls[0].url).toBe(
      'https://graph.threads.net/refresh_access_token?grant_type=th_refresh_token&access_token=old',
    );
  });
});

describe('Discord', () => {
  test('Webhook に本文と画像 URL の embed を送り、メンションを無効にする', async () => {
    const { fetch, calls } = mockFetch([{ body: { id: '999' } }]);
    const adapter = new DiscordAdapter({ webhookUrl: 'https://discord.com/api/webhooks/1/abc' }, fetch);
    const ref = await adapter.post({
      text: '@everyone 今日の問題',
      image: { bytes: png, mimeType: 'image/png', alt: '', publicUrl: 'https://img.example/c.png' },
    });
    expect(ref).toEqual({ id: '999' });
    expect(calls[0].url).toBe('https://discord.com/api/webhooks/1/abc?wait=true');
    const body = bodyOf(calls[0]);
    expect(body.content).toBe('@everyone 今日の問題');
    expect(body.allowed_mentions).toEqual({ parse: [] });
    expect(body.embeds).toEqual([{ image: { url: 'https://img.example/c.png' } }]);
  });

  test('画像なしなら embed を付けない。エラーは AdapterError', async () => {
    const ok = mockFetch([{ body: { id: '1' } }]);
    await new DiscordAdapter({ webhookUrl: 'https://d/x' }, ok.fetch).post({ text: 't' });
    expect(bodyOf(ok.calls[0]).embeds).toBeUndefined();
    const ng = mockFetch([{ status: 404, body: { message: 'Unknown Webhook' } }]);
    await expect(
      new DiscordAdapter({ webhookUrl: 'https://d/x' }, ng.fetch).post({ text: 't' }),
    ).rejects.toBeInstanceOf(AdapterError);
  });
});

describe('X: OAuth 1.0a 署名', () => {
  test('パーセントエンコードは RFC 3986', () => {
    expect(percentEncode("Hello Ladies + Gentlemen, a signed OAuth request!")).toBe(
      'Hello%20Ladies%20%2B%20Gentlemen%2C%20a%20signed%20OAuth%20request%21',
    );
    expect(percentEncode("a'b(c)*")).toBe('a%27b%28c%29%2A');
    expect(percentEncode('~-._')).toBe('~-._');
  });

  test('X のドキュメントにある署名の例と一致する', () => {
    // https://developer.x.com/en/docs/authentication/oauth-1-0a/creating-a-signature の例
    const params = {
      include_entities: 'true',
      oauth_consumer_key: 'xvz1evFS4wEEPTGEFPHBog',
      oauth_nonce: 'kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg',
      oauth_signature_method: 'HMAC-SHA1',
      oauth_timestamp: '1318622958',
      oauth_token: '370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb',
      oauth_version: '1.0',
      status: 'Hello Ladies + Gentlemen, a signed OAuth request!',
    };
    const sig = oauthSignature(
      'POST',
      'https://api.twitter.com/1.1/statuses/update.json',
      params,
      'kAcSOqF21Fu85e7zjz7ZN2U4ZRhfV3WpwPAoE3Z7kBw',
      'LswwdoUaIvS8ltyTt5jkRh4J50vUPVVHtR2YPi5kE',
    );
    expect(sig).toBe('hCtSmYh+iHYCEqBWrE7C7hYmtUk=');
  });

  test('Authorization ヘッダの形式', () => {
    const header = buildOauthHeader(
      'POST',
      'https://api.x.com/2/tweets',
      { apiKey: 'ck', apiSecret: 'cs', accessToken: 'at', accessSecret: 'as' },
      'nonce123',
      '1700000000',
    );
    expect(header.startsWith('OAuth ')).toBe(true);
    expect(header).toContain('oauth_consumer_key="ck"');
    expect(header).toContain('oauth_nonce="nonce123"');
    expect(header).toContain('oauth_signature_method="HMAC-SHA1"');
    expect(header).toContain('oauth_timestamp="1700000000"');
    expect(header).toContain('oauth_token="at"');
    expect(header).toMatch(/oauth_signature="[A-Za-z0-9%]+"/);
  });

  test('ツイート投稿（返信付き）', async () => {
    const { fetch, calls } = mockFetch([{ body: { data: { id: '1800', text: 't' } } }]);
    const adapter = new XAdapter(
      { apiKey: 'ck', apiSecret: 'cs', accessToken: 'at', accessSecret: 'as' },
      fetch,
    );
    const ref = await adapter.post({ text: 'こんにちは', replyTo: { id: '1700' } });
    expect(ref).toEqual({ id: '1800' });
    expect(calls[0].url).toBe('https://api.x.com/2/tweets');
    expect(bodyOf(calls[0])).toEqual({ text: 'こんにちは', reply: { in_reply_to_tweet_id: '1700' } });
    expect((calls[0].init!.headers as Record<string, string>).Authorization).toMatch(/^OAuth /);
  });
});

describe('buildAdapters（設定の揃った投稿先だけ作る）', () => {
  test('何も設定されていなければ空', () => {
    expect(buildAdapters({})).toEqual([]);
    expect(
      buildAdapters({ blueskyHandle: '-', blueskyAppPassword: '-', discordWebhookUrl: '-' }),
    ).toEqual([]);
  });

  test('3 つ設定すれば 3 つ（X は含まない）', () => {
    const adapters = buildAdapters({
      blueskyHandle: 'a.bsky.social',
      blueskyAppPassword: 'p',
      threadsUserId: '1',
      threadsAccessToken: 't',
      discordWebhookUrl: 'https://discord.com/api/webhooks/1/x',
      xEnabled: false,
      xCredentialsJson: '{"apiKey":"a","apiSecret":"b","accessToken":"c","accessSecret":"d"}',
    });
    expect(adapters.map((a) => a.platform)).toEqual(['bluesky', 'threads', 'discord']);
  });

  test('X は有効化され、認証情報が正しい JSON のときだけ', () => {
    const json = '{"apiKey":"a","apiSecret":"b","accessToken":"c","accessSecret":"d"}';
    expect(buildAdapters({ xEnabled: true, xCredentialsJson: json }).map((a) => a.platform)).toEqual(['x']);
    expect(buildAdapters({ xEnabled: true, xCredentialsJson: 'not json' })).toEqual([]);
    expect(buildAdapters({ xEnabled: true, xCredentialsJson: '-' })).toEqual([]);
    expect(buildAdapters({ xEnabled: true, xCredentialsJson: '{"apiKey":"a"}' })).toEqual([]);
  });

  test('isUnset / parseXCredentials', () => {
    expect(isUnset(undefined)).toBe(true);
    expect(isUnset(' - ')).toBe(true);
    expect(isUnset('x')).toBe(false);
    expect(parseXCredentials(undefined)).toBeNull();
  });
});
