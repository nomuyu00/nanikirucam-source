import { consumePublishQuota, contentKey, DAILY_PUBLISH_LIMIT } from '../src/lib/contentKey';
import { addDays, jstDate, jstWeekday } from '../src/lib/dates';
import { checkNickname, containsNgWord, normalizeForNgCheck } from '../src/lib/ngwords';
import {
  extractProblemIdFromPath,
  generateProblemId,
  isProblemId,
  PROBLEM_ID_LENGTH,
} from '../src/lib/problemId';
import { generateReferralCode, isReferralCode, normalizeReferralCode } from '../src/lib/referral';
import { sampleInput } from './fixtures';

describe('problemId (base62, 8 文字)', () => {
  test('8 文字の base62 になる', () => {
    for (let i = 0; i < 200; i++) {
      const id = generateProblemId();
      expect(id).toHaveLength(PROBLEM_ID_LENGTH);
      expect(id).toMatch(/^[0-9A-Za-z]{8}$/);
      expect(isProblemId(id)).toBe(true);
    }
  });

  test('乱数関数を差し替えると決定的（先頭から順に文字を引く）', () => {
    const seq = [0, 10, 36, 61, 1, 2, 3, 4];
    let i = 0;
    expect(generateProblemId(() => seq[i++])).toBe('0Aaz1234');
  });

  test('62 文字すべてが出うる（範囲 [0,62)）', () => {
    const seen = new Set<string>();
    for (let n = 0; n < 62; n++) seen.add(generateProblemId(() => n)[0]);
    expect(seen.size).toBe(62);
  });

  test('衝突しない（1 万個）', () => {
    const ids = new Set(Array.from({ length: 10000 }, () => generateProblemId()));
    expect(ids.size).toBe(10000);
  });

  test('isProblemId は不正な形式を拒否する', () => {
    for (const bad of ['', 'abc', 'AbC1234', 'AbC123456', 'AbC1234!', 'AbC 1234', null, 12345678]) {
      expect(isProblemId(bad)).toBe(false);
    }
  });

  test('パスから問題 ID を取り出す', () => {
    expect(extractProblemIdFromPath('/p/AbC12345')).toBe('AbC12345');
    expect(extractProblemIdFromPath('/p/AbC12345/')).toBe('AbC12345');
    expect(extractProblemIdFromPath('/nanikiru-cam/asia-northeast1/renderProblemPage/p/AbC12345')).toBe(
      'AbC12345',
    );
    expect(extractProblemIdFromPath('/p/')).toBeNull();
    expect(extractProblemIdFromPath('/p/short')).toBeNull();
    expect(extractProblemIdFromPath('/x/AbC12345')).toBeNull();
    expect(extractProblemIdFromPath('/p/AbC12345/extra')).toBeNull();
    expect(extractProblemIdFromPath('/')).toBeNull();
  });
});

describe('NG ワード', () => {
  test('正規化: 全角半角・大文字小文字・カタカナ・記号・空白', () => {
    expect(normalizeForNgCheck('ＦｕＣｋ')).toBe('fuck');
    expect(normalizeForNgCheck('ウンエイ')).toBe('うんえい');
    expect(normalizeForNgCheck('う.ん え-い')).toBe('うんえい');
  });

  test('NG ワードを検出する', () => {
    for (const bad of ['運営', '公式', '管理人', '事務局', '死ね', '殺す']) {
      expect(containsNgWord(bad)).toBe(true);
    }
    expect(containsNgWord('こうしき')).toBe(true);
    expect(containsNgWord('コウシキ')).toBe(true);
    expect(containsNgWord('fuck')).toBe(true);
    expect(containsNgWord('ｆｕｃｋ')).toBe(true);
    expect(containsNgWord('Official')).toBe(true);
    expect(containsNgWord('admin123')).toBe(true);
    expect(containsNgWord('ナニキルカム')).toBe(true);
  });

  test('リンク・メール・メンションに見える名前は拒否', () => {
    for (const bad of ['http://a.b', 'https://x', 'www.example.jp', 'foo@bar', '＠foo', 'example.com']) {
      expect(containsNgWord(bad)).toBe(true);
    }
  });

  test('ふつうの名前・麻雀用語は通す（チョンボ、シネマ、wwww）', () => {
    for (const ok of ['まじゃおう', 'チョンボ太郎', 'シネマ', 'ゆうきwww', 'Taro', '雀士123', 'tenpai']) {
      expect(containsNgWord(ok)).toBe(false);
    }
  });

  test('checkNickname: 長さ・制御文字・NG', () => {
    expect(checkNickname('  たろう ')).toEqual({ ok: true, value: 'たろう' });
    expect(checkNickname('あ'.repeat(21))).toEqual({ ok: false, reason: 'too_long' });
    expect(checkNickname('a\u0007b')).toEqual({ ok: false, reason: 'control_chars' });
    expect(checkNickname('こうしき')).toEqual({ ok: false, reason: 'ng_word' });
    expect(checkNickname('')).toEqual({ ok: true, value: '' });
  });
});

describe('contentKey（同一牌列の重複判定）', () => {
  test('同じ内容なら同じキー（32 文字の 16 進）', () => {
    const a = contentKey(sampleInput());
    expect(a).toMatch(/^[0-9a-f]{32}$/);
    expect(contentKey(sampleInput())).toBe(a);
  });

  test('手牌の並び順は無視する', () => {
    const base = sampleInput();
    const shuffled = [...base.tiles.slice(0, 13)].reverse().concat(base.tiles[13]);
    expect(contentKey(sampleInput({ tiles: shuffled }))).toBe(contentKey(base));
  });

  test('ツモ牌が違えば別の問題', () => {
    const base = sampleInput();
    const tiles = [...base.tiles];
    // 13 枚目と 14 枚目を入れ替える（牌の集合は同じだがツモ牌が変わる）
    [tiles[12], tiles[13]] = [tiles[13], tiles[12]];
    expect(contentKey(sampleInput({ tiles }))).not.toBe(contentKey(base));
  });

  test('ドラ表示牌・風・副露が違えば別の問題。巡目・名前・言語・解答は無視', () => {
    const base = contentKey(sampleInput());
    expect(contentKey(sampleInput({ dora: ['4z'] }))).not.toBe(base);
    expect(contentKey(sampleInput({ seatWind: 'east' }))).not.toBe(base);
    expect(contentKey(sampleInput({ roundWind: 'south' }))).not.toBe(base);
    expect(contentKey(sampleInput({ turn: 12 }))).toBe(base);
    expect(contentKey(sampleInput({ nickname: 'べつのひと' }))).toBe(base);
    expect(contentKey(sampleInput({ locale: 'en' }))).toBe(base);
  });

  test('赤5 と通常の 5 は別の問題', () => {
    const base = sampleInput();
    const tiles = base.tiles.map((t) => (t === '5m' ? '0m' : t));
    expect(contentKey(sampleInput({ tiles }))).not.toBe(contentKey(base));
  });

  test('副露の違い', () => {
    const base = sampleInput({
      tiles: ['1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s'],
      melds: [{ kind: 'pon', tiles: ['5z', '5z', '5z'] }],
      dora: [],
    });
    const other = sampleInput({
      tiles: base.tiles,
      melds: [{ kind: 'pon', tiles: ['6z', '6z', '6z'] }],
      dora: [],
    });
    expect(contentKey(base)).not.toBe(contentKey(other));
  });
});

describe('1 日 20 問の制限', () => {
  test('上限は 20', () => {
    expect(DAILY_PUBLISH_LIMIT).toBe(20);
  });

  test('初回は 1 になる', () => {
    expect(consumePublishQuota(undefined, '2026-10-21', 20)).toEqual({
      ok: true,
      next: { date: '2026-10-21', count: 1 },
    });
  });

  test('20 問目までは通り、21 問目は拒否される', () => {
    let q: { date: string; count: number } | undefined;
    for (let i = 1; i <= 20; i++) {
      const r = consumePublishQuota(q, '2026-10-21', 20);
      expect(r.ok).toBe(true);
      if (r.ok) q = r.next;
    }
    expect(q).toEqual({ date: '2026-10-21', count: 20 });
    expect(consumePublishQuota(q, '2026-10-21', 20)).toEqual({ ok: false, used: 20 });
  });

  test('日付が変わればリセット', () => {
    const r = consumePublishQuota({ date: '2026-10-20', count: 20 }, '2026-10-21', 20);
    expect(r).toEqual({ ok: true, next: { date: '2026-10-21', count: 1 } });
  });
});

describe('日付（JST）', () => {
  test('UTC 15:00 は JST の翌日 0:00', () => {
    expect(jstDate(new Date('2026-10-20T14:59:59Z'))).toBe('2026-10-20');
    expect(jstDate(new Date('2026-10-20T15:00:00Z'))).toBe('2026-10-21');
  });

  test('addDays は月・年をまたぐ', () => {
    expect(addDays('2026-10-31', 1)).toBe('2026-11-01');
    expect(addDays('2026-01-01', -1)).toBe('2025-12-31');
    expect(addDays('2024-02-28', 1)).toBe('2024-02-29');
    expect(addDays('2026-10-21', -6)).toBe('2026-10-15');
  });

  test('曜日は JST 基準（2026-10-25 は日曜）', () => {
    expect(jstWeekday(new Date('2026-10-25T11:00:00Z'))).toBe(0);
    expect(jstWeekday(new Date('2026-10-24T15:00:00Z'))).toBe(0);
    expect(jstWeekday(new Date('2026-10-24T14:59:00Z'))).toBe(6);
  });
});

describe('紹介コード', () => {
  test('8 文字で紛らわしい文字（I O 0 1）を含まない', () => {
    for (let i = 0; i < 300; i++) {
      const code = generateReferralCode();
      expect(code).toMatch(/^[A-HJ-NP-Z2-9]{8}$/);
      expect(isReferralCode(code)).toBe(true);
    }
  });

  test('入力のゆれを正規化する', () => {
    expect(normalizeReferralCode(' abcd-2345 ')).toBe('ABCD2345');
    expect(normalizeReferralCode('ａｂｃｄ２３４５')).toBe('ABCD2345');
    expect(normalizeReferralCode('ABCD234')).toBeNull();
    expect(normalizeReferralCode('ABCD234O')).toBeNull(); // O は使わない
    expect(normalizeReferralCode(12345678)).toBeNull();
    expect(normalizeReferralCode(undefined)).toBeNull();
  });
});
