import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';

int _id(String label) => idsFromNotation(label).single;

Map<String, DiscardCandidate> _byLabel(List<DiscardCandidate> list) => {
  for (final c in list) labelOfId(c.discardId): c,
};

void main() {
  test('同値は同順位（1,1,1,4…）', () {
    // 3 面子 + 雀頭 + 浮いた字牌 3 枚。3z/5z/7z のどれを切っても一向聴・受け入れ 8 枚
    final list = rankDiscards(handFromNotation('123m456p789s113z57z'));
    final top = list.take(3).toList();
    expect(top.map((c) => labelOfId(c.discardId)), ['3z', '5z', '7z']);
    for (final c in top) {
      expect(c.shantenAfter, 1);
      expect(c.ukeire.total, 8);
      expect(c.rankByAxis, {StrategyAxis.speed: 1});
    }
    expect(_byLabel(list)['3z']!.ukeire.tiles, {
      _id('1z'): 2,
      _id('5z'): 3,
      _id('7z'): 3,
    });
    expect(list[3].rankByAxis[StrategyAxis.speed], 4);
    expect(list[3].shantenAfter, greaterThan(1));
  });

  test('14 枚が和了形のとき: 切った後はテンパイで、受け入れの多い順に並ぶ', () {
    final hand = handFromNotation('123m456p789s11122z');
    expect(shanten(hand).shanten, -1);
    final list = rankDiscards(hand);
    final byLabel = _byLabel(list);
    expect(list, hasLength(11));
    expect(list.every((c) => c.shantenAfter == 0), isTrue);

    // 両面が残る 4 通りが 1 位（切った牌は河に出るので 1m 待ちは 3 枚）
    for (final l in ['1m', '4p', '6p', '9s']) {
      expect(byLabel[l]!.rankByAxis[StrategyAxis.speed], 1, reason: l);
      expect(byLabel[l]!.ukeire.total, 7, reason: l);
    }
    expect(byLabel['1m']!.ukeire.tiles, {_id('1m'): 3, _id('4m'): 4});
    // 嵌張・辺張・双碰が 5 位
    for (final l in ['2m', '3m', '5p', '7s', '8s', '1z']) {
      expect(byLabel[l]!.rankByAxis[StrategyAxis.speed], 5, reason: l);
      expect(byLabel[l]!.ukeire.total, 3, reason: l);
    }
    expect(byLabel['1z']!.ukeire.tiles, {_id('1z'): 1, _id('2z'): 2});
    // 2z 単騎が最下位
    expect(byLabel['2z']!.rankByAxis[StrategyAxis.speed], 11);
    expect(byLabel['2z']!.ukeire.tiles, {_id('2z'): 2});
  });

  test('副露ありの 11 枚（+ ポン）: 自分の副露の牌は残り枚数から除く', () {
    final hand = handFromNotation('234m456p78s115z', melds: 'pon:6s');
    expect(hand.tileCount, 14);
    final list = rankDiscards(hand);
    final best = list.first;
    expect(labelOfId(best.discardId), '5z');
    expect(best.shantenAfter, 0);
    expect(best.rankByAxis[StrategyAxis.speed], 1);
    // 6s はポンで 3 枚使っているので残り 1 枚
    expect(best.ukeire.tiles, {_id('6s'): 1, _id('9s'): 4});
    expect(list[1].rankByAxis[StrategyAxis.speed], 2);
  });

  test('副露 3 つの 5 枚（和了形）: 切り方で待ちが変わり、ポンした牌は残りが減る', () {
    final hand = handFromNotation('11m234p', melds: 'pon:5z,chi:7s,pon:1p');
    expect(hand.tileCount, 14);
    expect(shanten(hand).shanten, -1);
    final list = rankDiscards(hand);
    final byLabel = _byLabel(list);
    // 2p 切り: 1m 雀頭 + 34p 両面（2p は自分の河に 1 枚出たので残り 3）
    expect(byLabel['2p']!.ukeire.tiles, {_id('2p'): 3, _id('5p'): 4});
    // 4p 切り: 23p 両面だが 1p はポンで 3 枚使っていて残り 1
    expect(byLabel['4p']!.ukeire.tiles, {_id('1p'): 1, _id('4p'): 3});
    // 3p 切り: 嵌張、1m 切り: 1m 単騎（手に 1 枚・河に 1 枚で残り 2）
    expect(byLabel['3p']!.ukeire.tiles, {_id('3p'): 3});
    expect(byLabel['1m']!.ukeire.tiles, {_id('1m'): 2});
    expect(list.map((c) => labelOfId(c.discardId)), ['2p', '4p', '3p', '1m']);
    expect(list.map((c) => c.rankByAxis[StrategyAxis.speed]), [1, 2, 3, 4]);
  });

  test('返す順は速さ軸の順位、同順位は牌 id の昇順', () {
    final list = rankDiscards(handFromNotation('1245m3378p66789s1z'));
    for (var i = 1; i < list.length; i++) {
      final a = list[i - 1];
      final b = list[i];
      final ra = a.rankByAxis[StrategyAxis.speed]!;
      final rb = b.rankByAxis[StrategyAxis.speed]!;
      expect(ra, lessThanOrEqualTo(rb));
      if (ra == rb) {
        expect(a.discardId, lessThan(b.discardId));
        expect(a.shantenAfter, b.shantenAfter);
        expect(a.ukeire.total, b.ukeire.total);
      } else {
        expect(rb, i + 1);
      }
    }
    expect(list.first.rankByAxis.keys, [StrategyAxis.speed]);
  });

  test('14 枚でない手は ArgumentError', () {
    expect(
      () => rankDiscards(handFromNotation('123m456p789s1122z')),
      throwsArgumentError,
    );
  });
}
