import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  BACK_LABEL,
  TILE_KINDS,
  TILE_LABELS,
  compareTiles,
  countKinds,
  isRedFive,
  isTileLabel,
  tileImagePath,
  tileKind,
  tileName,
  tileNameEn,
  tileNameJa,
} from '../src/lib/tiles';

describe('tiles', () => {
  test('受け付けるラベルは 37 種で、裏 0b は含まない', () => {
    expect(TILE_LABELS).toHaveLength(37);
    expect(new Set(TILE_LABELS).size).toBe(37);
    expect(TILE_LABELS).not.toContain(BACK_LABEL);
    expect(isTileLabel('0b')).toBe(false);
  });

  test('assets/labels/tiles_labels.txt の 38 クラスと一致する（裏を除く）', () => {
    const file = path.resolve(__dirname, '../../../assets/labels/tiles_labels.txt');
    if (!fs.existsSync(file)) return; // リポジトリ外で実行したときは省略
    const classes = fs.readFileSync(file, 'utf-8').split(/\s+/).filter(Boolean);
    expect(classes).toHaveLength(38);
    expect([...TILE_LABELS].sort()).toEqual(classes.filter((c) => c !== BACK_LABEL).sort());
  });

  test('isTileLabel は不正な値を拒否する', () => {
    for (const bad of ['', '0', '10m', '8z', '9z', '5x', 5, null, undefined, '5m ', '５m']) {
      expect(isTileLabel(bad)).toBe(false);
    }
    expect(isTileLabel('0m')).toBe(true);
    expect(isTileLabel('7z')).toBe(true);
  });

  test('赤5 は通常の 5 と同じ種類', () => {
    expect(tileKind('0m')).toBe('5m');
    expect(tileKind('0s')).toBe('5s');
    expect(tileKind('5p')).toBe('5p');
    expect(isRedFive('0p')).toBe(true);
    expect(isRedFive('5p')).toBe(false);
    expect(TILE_KINDS).toHaveLength(34);
  });

  test('countKinds は赤5 と通常の 5 を合算する', () => {
    const counts = countKinds(['0m', '5m', '5m', '1z']);
    expect(counts.get('5m')).toBe(3);
    expect(counts.get('1z')).toBe(1);
  });

  test('並び順: 萬 → 筒 → 索 → 字、赤5 は通常の 5 の前', () => {
    const sorted = ['1z', '5s', '5m', '0m', '1p', '9m'].sort(compareTiles);
    expect(sorted).toEqual(['0m', '5m', '9m', '1p', '5s', '1z'].sort(compareTiles));
    expect(sorted).toEqual(['0m', '5m', '9m', '1p', '5s', '1z']);
  });

  test('牌の名前', () => {
    expect(tileNameJa('5m')).toBe('5萬');
    expect(tileNameJa('0p')).toBe('赤5筒');
    expect(tileNameJa('1z')).toBe('東');
    expect(tileNameJa('6z')).toBe('發');
    expect(tileNameJa('7z')).toBe('中');
    expect(tileNameEn('0s')).toBe('Red 5 Sou');
    expect(tileNameEn('6z')).toBe('Green');
    expect(tileName('3s', 'en')).toBe('3 Sou');
    expect(tileName('3s', 'ja')).toBe('3索');
  });

  test('画像パスは ASCII のラベル名', () => {
    expect(tileImagePath('0m')).toBe('/tiles/0m.png');
  });
});
