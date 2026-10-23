import 'dart:math';

import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/ukeire.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';

Map<int, int> _tiles(String spec) {
  // '1m:4 4m:4'（牌:残り枚数）を Map<牌 id, 枚数> にする
  final result = <int, int>{};
  for (final part in spec.split(' ')) {
    if (part.isEmpty) continue;
    final kv = part.split(':');
    result[idsFromNotation(kv[0]).single] = int.parse(kv[1]);
  }
  return result;
}

void main() {
  group('テンパイの受け入れ（待ち）', () {
    final cases = <(String, String, String)>[
      ('両面', '23m456p789s11122z', '1m:4 4m:4'),
      ('嵌張', '13m456p789s11122z', '2m:4'),
      ('辺張', '12m456p789s11122z', '3m:4'),
      ('双碰', '11m456p789s11122z', '1m:2 2z:2'),
      ('単騎', '1m456p789s111222z', '1m:3'),
      ('延べ単', '1234m456p789s111z', '1m:3 4m:3'),
      ('三面張', '34567m456p789s11z', '2m:4 5m:3 8m:4'),
      ('七対子単騎', '1155m2288p3366s7z', '7z:3'),
      (
        '国士十三面',
        '19m19p19s1234567z',
        '1m:3 9m:3 1p:3 9p:3 1s:3 9s:3 1z:3 2z:3 3z:3 4z:3 5z:3 6z:3 7z:3',
      ),
    ];
    for (final (name, hand, expected) in cases) {
      test('$name $hand', () {
        final state = handFromNotation(hand);
        expect(shanten(state).shanten, 0);
        expect(ukeire(state).tiles, _tiles(expected));
      });
    }

    test('九蓮宝燈は 9 種 23 枚', () {
      final u = ukeire(handFromNotation('1112345678999m'));
      expect(u.kinds, 9);
      expect(u.total, 23);
      expect(u.tiles[0], 1);
      expect(u.tiles[8], 1);
    });
  });

  group('残り枚数', () {
    test('見えている牌（visible）の分だけ減る', () {
      final u = ukeire(
        handFromNotation('23m456p789s11122z', visible: '1m1m4m'),
      );
      expect(u.tiles, _tiles('1m:2 4m:3'));
      expect(u.total, 5);
      expect(u.kinds, 2);
    });

    test('残り 0 の牌は受け入れに入らない', () {
      final u = ukeire(
        handFromNotation('23m456p789s11122z', visible: '1m1m1m1m'),
      );
      expect(u.tiles, _tiles('4m:4'));
    });

    test('自分の副露（ポン・チー）の分だけ減る', () {
      final u = ukeire(handFromNotation('23m456p11z', melds: 'pon:1m,chi:3m'));
      expect(u.tiles, _tiles('1m:1 4m:3'));
    });

    test('自分の槓は 4 枚として数える', () {
      final u = ukeire(handFromNotation('23m456p11z', melds: 'kan:1m,chi:7s'));
      expect(u.tiles, _tiles('4m:4'));
    });

    test('副露で 4 枚使った単騎は待ちが無い（テンパイだが受け入れ 0）', () {
      final hand = handFromNotation('1m', melds: 'pon:1m,chi:7s,pon:1p,chi:2p');
      expect(shanten(hand).shanten, 0);
      expect(ukeire(hand).tiles, isEmpty);
      expect(ukeire(hand).total, 0);
    });

    test('手の中に 4 枚ある牌は受け入れに入らない', () {
      // 1111m + 3 面子は 1m 単騎にならないので一向聴。1m 以外の 33 種が受け入れ
      final hand = handFromNotation('1111m234p567p789p');
      expect(shanten(hand).shanten, 1);
      final u = ukeire(hand);
      expect(u.tiles.containsKey(0), isFalse);
      expect(u.kinds, 33);
      // 2p〜9p は手に 1 枚（7p だけ 2 枚）、それ以外の 25 種は 4 枚
      expect(u.total, 7 * 3 + 2 + 25 * 4);
    });
  });

  test('13 枚系でない手は ArgumentError', () {
    expect(
      () => ukeire(handFromNotation('123m456p789s11122z')),
      throwsArgumentError,
    );
  });

  group('性質（ランダムな手）', () {
    final random = Random(20261021);
    final hands = [
      for (var i = 0; i < 400; i++) _randomHand13(random, melds: i % 4),
    ];

    test('受け入れ牌を引けばシャンテンが必ず下がり、それ以外の牌では下がらない', () {
      for (final hand in hands) {
        final s0 = shanten(hand).shanten;
        final u = ukeire(hand);
        for (var id = 0; id < kTileKinds; id++) {
          final counts = List<int>.of(hand.counts);
          if (counts[id] >= 4) {
            expect(u.tiles.containsKey(id), isFalse);
            continue;
          }
          counts[id]++;
          final s = shantenFromCounts(
            counts,
            meldCount: hand.meldCount,
          ).shanten;
          final reason = '${notationOfCounts(hand.counts)} 引き ${labelOfId(id)}';
          if (u.tiles.containsKey(id)) {
            expect(s, s0 - 1, reason: reason);
          } else if (hand.remaining(id) > 0) {
            expect(s, greaterThanOrEqualTo(s0), reason: reason);
          }
        }
      }
    });

    test('残り 0 の牌は入らず、値は残り枚数で、合計と種類数が合う', () {
      var sawZeroRemaining = false;
      for (final hand in hands) {
        final u = ukeire(hand);
        var sum = 0;
        for (final MapEntry(key: id, value: n) in u.tiles.entries) {
          expect(n, hand.remaining(id));
          expect(n, greaterThan(0));
          sum += n;
        }
        for (var id = 0; id < kTileKinds; id++) {
          if (hand.remaining(id) == 0) {
            expect(u.tiles.containsKey(id), isFalse);
            sawZeroRemaining = true;
          }
        }
        expect(u.total, sum);
        expect(u.kinds, u.tiles.length);
        expect(u.tiles.keys.toList(), orderedEquals([...u.tiles.keys]..sort()));
      }
      expect(sawZeroRemaining, isTrue);
    });
  });
}

/// 山からランダムに 13 枚系の手を作る（副露はポンかチー、visible もランダムに少し）。
HandState _randomHand13(Random random, {int melds = 0}) {
  final avail = List<int>.filled(kTileKinds, 4);
  final meldSpecs = <String>[];
  while (meldSpecs.length < melds) {
    if (random.nextBool()) {
      final t = random.nextInt(kTileKinds);
      if (avail[t] < 3) continue;
      avail[t] -= 3;
      meldSpecs.add('pon:${labelOfId(t)}');
    } else {
      final t = random.nextInt(3) * 9 + random.nextInt(7);
      if (avail[t] < 1 || avail[t + 1] < 1 || avail[t + 2] < 1) continue;
      for (var i = 0; i < 3; i++) {
        avail[t + i]--;
      }
      meldSpecs.add('chi:${labelOfId(t)}');
    }
  }
  List<int> draw(int n) {
    final counts = List<int>.filled(kTileKinds, 0);
    for (var i = 0; i < n; i++) {
      while (true) {
        final t = random.nextInt(kTileKinds);
        if (avail[t] == 0) continue;
        avail[t]--;
        counts[t]++;
        break;
      }
    }
    return counts;
  }

  final counts = draw(13 - 3 * melds);
  final visible = draw(random.nextInt(20));
  return HandState(
    counts: counts,
    openMelds: meldsFromSpec(meldSpecs.join(',')),
    visible: visible,
  );
}
