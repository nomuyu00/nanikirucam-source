// 13 枚のレポート（設計書 4.6.5、仕様 4.5）。子・南家・東場（1z は場風）。
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

int _id(String label) => idsFromNotation(label).single;

Map<String, WaitInfo> _waits(ThirteenReport r) => {
  for (final w in r.waits) labelOfId(w.tileId): w,
};

void main() {
  test('門前の役なしテンパイ: ロン不可・ツモ可、リーチできる', () {
    // 12m 辺張 3m 待ち。ツモは門前清自摸和 30 符 1 翻 300/500 = 1100。
    final r = buildThirteenReport(stateOf('12m456p789s23455s'));
    expect(r.shanten.shanten, 0);
    expect(r.hasYaku, isFalse);
    expect(r.riichiPossible, isTrue);
    expect(r.riichi, isNull);
    final w = _waits(r);
    expect(w.keys, ['3m']);
    expect(w['3m']!.remaining, 4);
    expect(w['3m']!.ronScore, isNull);
    expect(w['3m']!.ronPoints, isNull);
    expect(w['3m']!.tsumoScore!.yaku.map((y) => y.name), ['門前清自摸和']);
    expect(w['3m']!.tsumoPoints, 1100);
    expect(r.draws.tiles, {_id('3m'): 4});
  });

  test('副露の役なしテンパイ: ロンもツモもできない、リーチできない', () {
    final r = buildThirteenReport(stateOf('234m456p78s11z', melds: 'pon:6s'));
    expect(r.hasYaku, isFalse);
    expect(r.riichiPossible, isFalse);
    final w = _waits(r);
    expect(w.keys, ['6s', '9s']);
    expect(w['6s']!.remaining, 1, reason: 'ポンで 3 枚使っている');
    expect(w['9s']!.remaining, 4);
    for (final info in r.waits) {
      expect(info.ronScore, isNull);
      expect(info.tsumoScore, isNull);
      expect(info.ronPoints, isNull);
      expect(info.tsumoPoints, isNull);
    }
  });

  test('門前の役ありテンパイ: 待ちごとの点数', () {
    // 1m なら平和のみ（1000 / ツモ 400/700 = 1500）、4m なら断么九も付く
    // （2 翻 30 符 2000 / ツモ 3 翻 20 符 700/1300 = 2700）。
    final r = buildThirteenReport(stateOf('23m456p678s23455s'));
    expect(r.hasYaku, isTrue);
    expect(r.riichiPossible, isTrue);
    final w = _waits(r);
    expect(w['1m']!.ronPoints, 1000);
    expect(w['1m']!.tsumoPoints, 1500);
    expect(w['4m']!.ronPoints, 2000);
    expect(w['4m']!.tsumoPoints, 2700);
    expect(
      w['4m']!.ronScore!.yaku.map((y) => y.name),
      containsAll(['平和', '断么九']),
    );
  });

  test('副露の片あがり: 役のある待ちがあれば hasYaku', () {
    // チー 789s、1z・6s のシャンポン。1z なら場風 1000 / ツモ 1100、6s は役なし。
    final r = buildThirteenReport(stateOf('234m456p11z66s', melds: 'chi:7s'));
    expect(r.hasYaku, isTrue);
    expect(r.riichiPossible, isFalse);
    final w = _waits(r);
    expect(w['1z']!.ronPoints, 1000);
    expect(w['1z']!.tsumoPoints, 1100);
    expect(w['6s']!.ronScore, isNull);
    expect(w['6s']!.tsumoScore, isNull);
  });

  test('暗槓だけなら門前（リーチできる）', () {
    final r = buildThirteenReport(stateOf('234m456p78s11z', melds: 'ankan:9p'));
    expect(r.riichiPossible, isTrue);
    expect(r.hasYaku, isFalse);
    expect(_waits(r)['6s']!.tsumoPoints, 2000);
  });

  test('親の点数・赤ドラ', () {
    final dealer = buildThirteenReport(
      stateOf('34m456p678s23455s', dealer: true),
    );
    // 断么九・平和の親ロン 2 翻 30 符 2900、親ツモ 3 翻 20 符 1300 オール
    expect(_waits(dealer)['2m']!.ronPoints, 2900);
    expect(_waits(dealer)['2m']!.tsumoPoints, 3900);
    final red = buildThirteenReport(stateOf('34m406p789s23455s', dora: '3s'));
    // 平和 + ドラ 1 + 赤 1 = 3 翻 30 符 3900
    expect(_waits(red)['5m']!.ronPoints, 3900);
  });

  test('空テン: 待ちの牌が全部見えていても待ちとして返す（残り 0）', () {
    final r = buildThirteenReport(
      stateOf('12m456p789s23455s', visible: '3333m'),
    );
    expect(r.shanten.shanten, 0);
    expect(r.draws.tiles, isEmpty);
    final w = _waits(r);
    expect(w['3m']!.remaining, 0);
    expect(w['3m']!.tsumoPoints, 1100);
    expect(r.riichiPossible, isTrue);
  });

  test('国士 13 面待ち', () {
    final r = buildThirteenReport(stateOf('19m19p19s1234567z'));
    expect(r.waits, hasLength(13));
    expect(r.waits.every((w) => w.remaining == 3), isTrue);
    expect(r.waits.every((w) => w.ronPoints == 32000), isTrue);
    expect(r.hasYaku, isTrue);
  });

  test('テンパイでなければ待ちは空、受け入れだけ', () {
    final r = buildThirteenReport(stateOf('23m456p789s2344s7z'));
    expect(r.shanten.shanten, 1);
    expect(r.waits, isEmpty);
    expect(r.hasYaku, isFalse);
    expect(r.riichiPossible, isFalse);
    expect(r.draws.total, 17);
  });

  test('13 枚でない手は ArgumentError', () {
    expect(
      () => buildThirteenReport(stateOf('23m456p789s23455s9m')),
      throwsArgumentError,
    );
  });
}
