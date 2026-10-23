import {
  contentSecurityPolicy,
  escapeHtml,
  jsonForScript,
  renderNotFoundPage,
  renderProblemPage,
} from '../src/lib/html';
import type { PageContext } from '../src/lib/html';
import { fmt, pickLang, strings } from '../src/lib/i18n';
import { appStoreUrl, cardPathFor, cardPublicUrl, playStoreUrl, problemUrl } from '../src/lib/storeLinks';
import type { StoreConfig } from '../src/lib/storeLinks';

const stores: StoreConfig = {
  siteUrl: 'https://nanikiru-cam.web.app',
  iosAppStoreId: '1234567890',
  iosProviderToken: 'PT123',
  androidPackage: 'jp.aile.nanikiru_cam',
};

function ctx(patch: Partial<PageContext> = {}): PageContext {
  return {
    problemId: 'AbC12345',
    problem: {
      tiles: ['1m', '2m', '3m', '0m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '2z', '9p'],
      melds: [],
      dora: ['3z'],
      seatWind: 'south',
      roundWind: 'east',
      turn: 6,
      authorNickname: 'まじゃおう',
    },
    lang: 'ja',
    siteUrl: 'https://nanikiru-cam.web.app',
    ogImageUrl: 'https://firebasestorage.googleapis.com/v0/b/b/o/cards%2FAbC12345%2F1x1.png?alt=media',
    ogImageIsCard: true,
    ref: null,
    stores,
    ga4Id: '',
    appleAppId: '',
    ...patch,
  };
}

describe('エスケープ', () => {
  test('escapeHtml', () => {
    expect(escapeHtml(`<script>alert("x")&'y'</script>`)).toBe(
      '&lt;script&gt;alert(&quot;x&quot;)&amp;&#39;y&#39;&lt;/script&gt;',
    );
    expect(escapeHtml('ふつう')).toBe('ふつう');
  });

  test('jsonForScript は </script> で閉じられない形にする', () => {
    const json = jsonForScript({ a: '</script><script>alert(1)</script>', b: 'x&y', c: '  ' });
    expect(json).not.toContain('<');
    expect(json).not.toContain('>');
    expect(json).not.toContain('&');
    expect(json).not.toContain(' ');
    // 元に戻せる
    expect(JSON.parse(json)).toEqual({
      a: '</script><script>alert(1)</script>',
      b: 'x&y',
      c: '  ',
    });
  });
});

describe('問題ページ（SSR）', () => {
  const html = renderProblemPage(ctx());

  test('出題者名など DB 由来の文字列はエスケープされる', () => {
    const evil = renderProblemPage(
      ctx({
        problem: {
          ...ctx().problem,
          authorNickname: '<img src=x onerror=alert(1)>"\'&</script>',
        },
      }),
    );
    expect(evil).not.toContain('<img src=x');
    expect(evil).toContain('&lt;img src=x onerror=alert(1)&gt;');
    // スクリプトのデータブロックは閉じられていない
    const scripts = evil.match(/<script/g) ?? [];
    expect(scripts).toHaveLength(2); // JSON データと problem.js だけ
    expect(evil).not.toMatch(/<script>[^<]*alert/);
  });

  test('インラインのスクリプト・スタイルを含まない（CSP と整合）', () => {
    expect(html).not.toMatch(/<script(?![^>]*(src=|type="application\/json"))/);
    expect(html).not.toMatch(/<style/);
    expect(html).not.toMatch(/ on[a-z]+=/);
    expect(html).not.toMatch(/style="/);
    expect(contentSecurityPolicy()).toContain("script-src 'self'");
    expect(contentSecurityPolicy()).not.toContain('unsafe-inline');
  });

  test('OGP と Twitter カードのメタ', () => {
    expect(html).toContain('<meta property="og:title" content="この手、何切る？ | なにきるカム">');
    expect(html).toContain('<meta property="og:url" content="https://nanikiru-cam.web.app/p/AbC12345">');
    expect(html).toContain('<meta property="og:type" content="website">');
    expect(html).toContain('<meta property="og:locale" content="ja_JP">');
    expect(html).toContain(
      '<meta property="og:image" content="https://firebasestorage.googleapis.com/v0/b/b/o/cards%2FAbC12345%2F1x1.png?alt=media">',
    );
    expect(html).toContain('<meta property="og:image:width" content="1080">');
    expect(html).toContain('<meta property="og:image:height" content="1080">');
    expect(html).toContain('<meta name="twitter:card" content="summary_large_image">');
    expect(html).toContain('<meta name="twitter:image" content="https://firebasestorage.googleapis.com');
    expect(html).toContain('<link rel="canonical" href="https://nanikiru-cam.web.app/p/AbC12345">');
    expect(html).toContain('<meta name="robots" content="noindex,follow">');
  });

  test('カードが無いときは既定画像（1200x630）', () => {
    const fallback = renderProblemPage(
      ctx({ ogImageUrl: 'https://nanikiru-cam.web.app/assets/og-default.png', ogImageIsCard: false }),
    );
    expect(fallback).toContain('content="https://nanikiru-cam.web.app/assets/og-default.png"');
    expect(fallback).toContain('<meta property="og:image:width" content="1200">');
    expect(fallback).toContain('<meta property="og:image:height" content="630">');
  });

  test('og:description に答えや出題者名を入れない', () => {
    const m = /property="og:description" content="([^"]*)"/.exec(html);
    expect(m?.[1]).toContain('3つの解');
    expect(m?.[1]).not.toContain('まじゃおう');
  });

  test('牌は ASCII ラベルの画像で描画し、14 個のボタンになる。ツモ牌に印を付ける', () => {
    const buttons = html.match(/<button type="button" class="tile[^"]*" data-tile="[^"]+"/g) ?? [];
    expect(buttons).toHaveLength(14);
    expect(html).toContain('src="/tiles/0m.png"');
    expect(html).toContain('alt="赤5萬"');
    expect(html).toContain('class="tile tsumo" data-tile="9p"');
    expect(html).toContain('class="tsumo-label">ツモ<');
    expect(html).toContain('aria-label="9筒を切る"');
  });

  test('ドラ表示牌・風・巡目・出題者を表示する', () => {
    expect(html).toContain('東場 南家 6巡目');
    expect(html).toContain('出題: まじゃおう');
    expect(html).toContain('ドラ表示牌');
    expect(html).toContain('class="dora-img" src="/tiles/3z.png"');
  });

  test('副露を表示する（開いた副露は先頭の牌を横向き、暗槓は倒さない）', () => {
    const withMeld = renderProblemPage(
      ctx({
        problem: {
          ...ctx().problem,
          tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s'],
          melds: [{ kind: 'pon', tiles: ['5z', '5z', '5z'] }],
        },
      }),
    );
    expect(withMeld).toContain('class="melds"');
    expect(withMeld.match(/class="meld-img/g)).toHaveLength(3);
    expect(withMeld).toContain('class="meld-img sideways"');
    const ankan = renderProblemPage(
      ctx({
        problem: {
          ...ctx().problem,
          tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s'],
          melds: [{ kind: 'ankan', tiles: ['5z', '5z', '5z', '5z'] }],
        },
      }),
    );
    expect(ankan.match(/class="meld-img/g)).toHaveLength(4);
    expect(ankan).not.toContain('sideways');
  });

  test('DB の値が壊れていても、不正な牌ラベルは描画しない（属性への注入を防ぐ）', () => {
    const broken = renderProblemPage(
      ctx({
        problem: {
          ...ctx().problem,
          tiles: ['1m', '"><script>alert(1)</script>', '9p'],
          dora: ['x" onerror="alert(1)'],
          melds: [{ kind: 'pon', tiles: ['5z', '"bad', '5z'] }],
        },
      }),
    );
    expect(broken).not.toContain('<script>alert');
    expect(broken).not.toContain('onerror');
    expect(broken.match(/data-tile="/g)).toHaveLength(2);
  });

  test('答えと統計を HTML に含めない', () => {
    expect(html).not.toContain('"answer"');
    expect(html).not.toContain('byAxis');
    expect(html).not.toContain('"stats"');
  });

  test('クライアント用のデータブロック', () => {
    const m = /<script type="application\/json" id="nk-data">(.*?)<\/script>/s.exec(html);
    expect(m).not.toBeNull();
    const data = JSON.parse(m![1]);
    expect(data.problemId).toBe('AbC12345');
    expect(data.answerEndpoint).toBe('/api/answer');
    expect(data.lang).toBe('ja');
    expect(data.ga4Id).toBe('');
    expect(data.t.appName).toBe('なにきるカム');
    expect(data.tiles).toHaveLength(14);
  });

  test('ストアのリンクに pid と ref を付ける（Play の referrer）', () => {
    const withRef = renderProblemPage(ctx({ ref: 'ABCD2345' }));
    const referrer = encodeURIComponent('utm_source=share&utm_campaign=problem&pid=AbC12345&ref=ABCD2345');
    expect(withRef).toContain(
      `https://play.google.com/store/apps/details?id=jp.aile.nanikiru_cam&amp;referrer=${referrer}`,
    );
    expect(withRef).toContain('https://apps.apple.com/jp/app/id1234567890?pt=PT123&amp;ct=problem&amp;mt=8');
    expect(withRef).toContain('data-store="ios"');
    expect(withRef).toContain('data-store="android"');
    expect(withRef).toContain('解説をアプリで見る');
  });

  test('ref が無いときは referrer に ref を入れない', () => {
    const noRef = renderProblemPage(ctx());
    expect(noRef).toContain(encodeURIComponent('utm_source=share&utm_campaign=problem&pid=AbC12345'));
    expect(noRef).not.toContain('ref%3D');
  });

  test('App Store の ID が未設定なら iOS のボタンを出さない（Google Play は出す）', () => {
    const noIos = renderProblemPage(ctx({ stores: { ...stores, iosAppStoreId: '' } }));
    expect(noIos).not.toContain('data-store="ios"');
    expect(noIos).toContain('data-store="android"');
  });

  test('Smart App Banner は App Store ID があるときだけ', () => {
    expect(html).not.toContain('apple-itunes-app');
    expect(renderProblemPage(ctx({ appleAppId: '1234567890' }))).toContain(
      '<meta name="apple-itunes-app" content="app-id=1234567890, app-argument=https://nanikiru-cam.web.app/p/AbC12345">',
    );
  });

  test('英語ページ', () => {
    const en = renderProblemPage(ctx({ lang: 'en' }));
    expect(en).toContain('<html lang="en">');
    expect(en).toContain('What would you discard? | Nanikiru Cam');
    expect(en).toContain('property="og:locale" content="en_US"');
    expect(en).toContain('alt="Red 5 Man"');
    expect(en).toContain('East round South seat Turn 6');
    expect(en).toContain('Get it on Google Play');
  });

  test('出題者名が空なら出題者表示を出さない', () => {
    const anon = renderProblemPage(ctx({ problem: { ...ctx().problem, authorNickname: '' } }));
    expect(anon).not.toContain('class="author"');
  });
});

describe('404 ページ', () => {
  test('noindex で、日本語・英語', () => {
    const ja = renderNotFoundPage('ja');
    expect(ja).toContain('<meta name="robots" content="noindex">');
    expect(ja).toContain('この問題は見つかりません');
    expect(renderNotFoundPage('en')).toContain('Problem not found');
  });
});

describe('言語の決定', () => {
  test('クエリが優先', () => {
    expect(pickLang('ja', 'en')).toBe('en');
    expect(pickLang('en-US', 'ja')).toBe('ja');
  });

  test('Accept-Language: 英語が日本語より先のときだけ英語', () => {
    expect(pickLang('en-US,en;q=0.9,ja;q=0.8')).toBe('en');
    expect(pickLang('ja,en-US;q=0.9')).toBe('ja');
    expect(pickLang('ja-JP')).toBe('ja');
    expect(pickLang('fr-FR,de;q=0.8')).toBe('ja');
    expect(pickLang('en;q=0.5,ja;q=0.9')).toBe('ja');
    expect(pickLang(undefined)).toBe('ja');
    expect(pickLang('')).toBe('ja');
    expect(pickLang('en', 'xx')).toBe('en');
  });

  test('fmt はプレースホルダを置換し、未知のキーはそのまま', () => {
    expect(fmt('{n}人が回答', { n: 12 })).toBe('12人が回答');
    expect(fmt('{a}-{b}', { a: 1 })).toBe('1-{b}');
    expect(strings('en').appName).toBe('Nanikiru Cam');
    expect(strings('ja').appName).toBe('なにきるカム');
  });
});

describe('リンク', () => {
  test('Play: referrer は URL エンコードされ、不正な ref は無視する', () => {
    const url = playStoreUrl(stores, { pid: 'AbC12345', ref: '<bad>', campaign: 'problem' });
    expect(url).toContain('referrer=' + encodeURIComponent('utm_source=share&utm_campaign=problem&pid=AbC12345'));
    expect(url).not.toContain('bad');
  });

  test('App Store: ID 未設定ならトップページ、トークン未設定なら pt/ct なし', () => {
    expect(appStoreUrl({ ...stores, iosAppStoreId: '' }, { campaign: 'problem' })).toBe(
      'https://nanikiru-cam.web.app/',
    );
    expect(appStoreUrl({ ...stores, iosProviderToken: '' }, { campaign: 'problem' })).toBe(
      'https://apps.apple.com/jp/app/id1234567890',
    );
    expect(appStoreUrl(stores, { campaign: 'referral' })).toBe(
      'https://apps.apple.com/jp/app/id1234567890?pt=PT123&ct=referral&mt=8',
    );
  });

  test('問題 URL・カードのパスと公開 URL', () => {
    expect(problemUrl('https://x.example', 'AbC12345')).toBe('https://x.example/p/AbC12345');
    expect(problemUrl('https://x.example', 'AbC12345', 'ABCD2345')).toBe(
      'https://x.example/p/AbC12345?ref=ABCD2345',
    );
    expect(problemUrl('https://x.example', 'AbC12345', 'bad ref')).toBe('https://x.example/p/AbC12345');
    expect(cardPathFor('AbC12345')).toBe('cards/AbC12345/1x1.png');
    expect(cardPublicUrl('my-bucket.appspot.com', 'cards/AbC12345/1x1.png')).toBe(
      'https://firebasestorage.googleapis.com/v0/b/my-bucket.appspot.com/o/cards%2FAbC12345%2F1x1.png?alt=media',
    );
  });
});
