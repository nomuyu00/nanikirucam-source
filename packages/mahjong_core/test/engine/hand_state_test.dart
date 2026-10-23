import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/models.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';

void main() {
  test('tileIdOf は 34 種の並び（萬・筒・索・字）', () {
    expect(tileIdOf(const Tile(Suit.m, 1)), 0);
    expect(tileIdOf(const Tile(Suit.p, 5, red: true)), 13);
    expect(tileIdOf(const Tile(Suit.s, 9)), 26);
    expect(tileIdOf(const Tile(Suit.z, 7)), 33);
  });

  test('fromLabels: 赤5は 5 として数え、redIds に入る', () {
    final hand = HandState.fromLabels(
      ['1m', '0p', '5p', '5z', '5z'],
      visible: ['1m', '9s'],
    );
    expect(hand.counts[0], 1);
    expect(hand.counts[13], 2);
    expect(hand.counts[31], 2);
    expect(hand.redIds, {13});
    expect(hand.visible[0], 1);
    expect(hand.visible[26], 1);
    expect(() => HandState.fromLabels(['8z']), throwsArgumentError);
  });

  test('tileCount は副露を 3 枚（槓も 3 枚）として数える', () {
    expect(handFromNotation('123m456p789s11122z').tileCount, 14);
    expect(
      handFromNotation('23m456p11z', melds: 'kan:1m,chi:7s').tileCount,
      13,
    );
    expect(
      handFromNotation('11m', melds: 'pon:1z,ankan:2z,kan:3z,chi:1p').tileCount,
      14,
    );
  });

  test('remaining = 4 − 手牌 − 自分の副露 − 見えている牌（0 未満にしない）', () {
    final hand = handFromNotation(
      '23m456p11z',
      melds: 'pon:1m,kan:7z',
      visible: '1m4m4m4m4m4m',
    );
    expect(hand.remaining(0), 0); // 1m: ポン 3 + 見えている 1
    expect(hand.remaining(1), 3); // 2m: 手に 1
    expect(hand.remaining(3), 0); // 4m: 見えている 5（認識の誤りでも 0 で止める）
    expect(hand.remaining(33), 0); // 7z: 槓 4
    expect(hand.remaining(27), 2); // 1z: 手に 2
    expect(hand.meldTileCount(0), 3);
    expect(hand.meldTileCount(33), 4);
  });

  test('discard は手牌から 1 枚減らし、河（visible）に 1 枚足す', () {
    final hand = handFromNotation('123m456p789s11122z');
    final after = hand.discard(27);
    expect(after.counts[27], 2);
    expect(after.visible[27], 1);
    expect(after.tileCount, 13);
    expect(after.remaining(27), hand.remaining(27));
    expect(() => hand.discard(3), throwsArgumentError);
  });

  test('不正な入力は ArgumentError', () {
    expect(() => HandState(counts: List.filled(33, 0)), throwsArgumentError);
    expect(
      () => handFromNotation('111m', melds: 'pon:1m'),
      throwsArgumentError,
    );
  });

  test('値として等しい', () {
    expect(
      handFromNotation('123m456p789s11122z'),
      handFromNotation('11122z789s456p123m'),
    );
  });
}
