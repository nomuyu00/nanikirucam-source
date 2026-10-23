import 'dart:math';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

void main() {
  test('13 枚: ThirteenReport を返し、候補は空', () {
    final engine = DefaultNanikiruEngine();
    final r = engine.analyze(stateOf('23m456p789s23455s'), deep: false);
    expect(r.shanten.shanten, 0);
    expect(r.thirteen, isNotNull);
    expect(r.thirteen!.waits, hasLength(2));
    expect(r.candidates, isEmpty);
    expect(r.bestByAxis, isEmpty);
    expect(r.win, isNull);
    expect(r.blocks, isEmpty);
    expect(r.engineVersion, kEngineVersion);
    expect(r.deep, isFalse);
  });

  test('14 枚: 候補と 3 軸のおすすめ', () {
    // 上がりやすさは表の差し替えに左右されないよう単調な仮の関数にする
    final engine = DefaultNanikiruEngine(
      winEaseOf:
          ({
            required shanten,
            required ukeireTotal,
            turn,
            type = ShantenType.standard,
          }) => shanten < 0
          ? 1
          : (1 - pow(1 - ukeireTotal / 70, 12)) * pow(0.35, shanten).toDouble(),
    );
    final r = engine.analyze(stateOf('23m456p678s23455s9m'), deep: true);
    expect(r.shanten.shanten, 0);
    expect(r.thirteen, isNull);
    expect(r.win, isNull);
    expect(r.candidates, isNotEmpty);
    expect(r.bestByAxis.keys, StrategyAxis.values);
    // 9m を切れば T02 の形（平和確定、4m で断么九）。どの軸でも 1 位。
    for (final axis in StrategyAxis.values) {
      expect(r.bestByAxis[axis]!.map(labelOfId), ['9m'], reason: axis.name);
    }
    expect(r.deep, isTrue);
    expect(r.engineVersion, '1.1.0');
  });

  test('14 枚の和了形: ツモの評価（手の中のどの牌をツモっても最も高い解釈）', () {
    final engine = DefaultNanikiruEngine();
    // 平和 + 赤 + ツモ 3 翻 20 符 700/1300 = 2700
    final r = engine.analyze(stateOf('123m406p789s23455s'), deep: false);
    expect(r.shanten.shanten, -1);
    expect(r.win, isNotNull);
    expect(r.winPoints, 2700);
    expect(r.win!.yaku.map((y) => y.name), containsAll(['平和', '門前清自摸和']));
    // 副露で役なしの和了形は和了できない
    final open = engine.analyze(
      stateOf('234m456p789s11z', melds: 'pon:6s'),
      deep: false,
    );
    expect(open.shanten.shanten, -1);
    expect(open.win, isNull);
    expect(open.winPoints, isNull);
  });

  test('二向聴以上の候補は目安（isEstimate）', () {
    final r = DefaultNanikiruEngine().analyze(
      stateOf('1245m3378p66789s1z'),
      deep: true,
    );
    expect(r.shanten.shanten, 2);
    for (final c in r.candidates) {
      expect(c.points.isEstimate, isTrue);
      expect(c.riichiPoints!.isEstimate, isTrue);
      expect(c.goodShapeRate, isNull);
    }
  });

  test('13・14 枚でない手は ArgumentError', () {
    final engine = DefaultNanikiruEngine();
    expect(
      () => engine.analyze(stateOf('23m456p789s2345s'), deep: false),
      throwsArgumentError,
    );
  });

  group('無料と Pro の出し分け（仕様 5 章）', () {
    test('13 枚: ブロック分解・リーチ判断は Pro だけ。待ちのリーチ込み点数は両方', () {
      final engine = DefaultNanikiruEngine();
      final hand = stateOf('24m 456p 678s 234s 55p');
      final pro = engine.analyze(hand, deep: true);
      final free = engine.analyze(hand, deep: false);
      expect(pro.blocks, decomposeBlocks(hand));
      expect(pro.blocks, isNotEmpty);
      expect(free.blocks, isEmpty);
      expect(pro.thirteen!.riichi, isNotNull);
      expect(free.thirteen!.riichi, isNull);
      expect(free.thirteen!.waits, pro.thirteen!.waits);
      expect(free.thirteen!.waits.single.ronRiichiPoints, 2600);
    });

    test('14 枚: 2 段階先・リーチ判断・ブロック分解・消える役のタグは Pro だけ', () {
      final engine = DefaultNanikiruEngine();
      // 1234m 567p 345s 678s 5p: 打 1m・4m・5p はテンパイ。打 4m はタンヤオが消える
      final hand = stateOf('1234m 567p 345s 678s 5p');
      final pro = engine.analyze(hand, deep: true);
      final free = engine.analyze(hand, deep: false);
      expect(pro.blocks, decomposeBlocks(hand));
      expect(free.blocks, isEmpty);
      expect(free.bestByAxis, pro.bestByAxis);
      var yakuLossSeen = false;
      for (var i = 0; i < pro.candidates.length; i++) {
        final p = pro.candidates[i];
        final f = free.candidates[i];
        expect(f.discardId, p.discardId);
        expect(f.rankByAxis, p.rankByAxis);
        expect(p.twoStep, isNotNull);
        expect(f.twoStep, isNull);
        expect(f.riichi, isNull);
        expect(p.riichi != null, p.shantenAfter == 0);
        if (p.reasons.any((r) => r.tag == ReasonTag.yakuLoss)) {
          yakuLossSeen = true;
        }
        expect(
          f.reasons,
          p.reasons.where((r) => r.tag != ReasonTag.yakuLoss).toList(),
        );
      }
      expect(yakuLossSeen, isTrue);
    });
  });

  test('shanten は総合のシャンテン数', () {
    final engine = DefaultNanikiruEngine();
    expect(
      engine.shanten(stateOf('1199m2288p336s57z')),
      const ShantenResult(shanten: 1, type: ShantenType.sevenPairs),
    );
  });

  group('LRU', () {
    test('同じ入力は同じ結果を返し、無料と Pro は別に持つ', () {
      final engine = DefaultNanikiruEngine();
      final hand = stateOf('23m456p678s23455s9m');
      final a = engine.analyze(hand, deep: true);
      final b = engine.analyze(stateOf('23m456p678s23455s9m'), deep: true);
      expect(identical(a, b), isTrue);
      final free = engine.analyze(hand, deep: false);
      expect(identical(a, free), isFalse);
      expect(engine.cachedCount, 2);
    });

    test('件数の上限を超えたら最も古いものから捨てる', () {
      final engine = DefaultNanikiruEngine(cacheSize: 3);
      HandState h(int turn) => stateOf('23m456p789s23455s', turn: turn);
      final first = engine.analyze(h(1), deep: false);
      engine.analyze(h(2), deep: false);
      engine.analyze(h(3), deep: false);
      // 1 を使い直すと 2 が最も古くなる
      expect(identical(engine.analyze(h(1), deep: false), first), isTrue);
      engine.analyze(h(4), deep: false);
      expect(engine.cachedCount, 3);
      expect(identical(engine.analyze(h(1), deep: false), first), isTrue);
      final second = engine.analyze(h(2), deep: false);
      expect(engine.cachedCount, 3);
      expect(identical(engine.analyze(h(2), deep: false), second), isTrue);
    });

    test('既定は 50 件', () {
      final engine = DefaultNanikiruEngine();
      for (var t = 1; t <= 60; t++) {
        engine.analyze(stateOf('23m456p789s23455s', turn: t), deep: false);
      }
      expect(engine.cachedCount, 50);
    });

    test('キーは counts・visible・副露・ドラ・赤・風・親子・巡目で変わる', () {
      final base = analysisCacheKey(stateOf('23m406p789s23455s'));
      final variants = [
        stateOf('23m456p789s23455s'),
        stateOf('23m406p789s23455s', visible: '1m'),
        stateOf('23m406p789s23455s', dora: '2m'),
        stateOf('23m406p789s23455s', dealer: true),
        stateOf('23m406p789s23455s', round: Wind.south),
        stateOf('23m406p789s23455s', turn: 3),
        stateOf('23m406p7s23455s', melds: 'chi:7s'),
        stateOf('23m406p7s23455s', melds: 'pon:7s'),
      ];
      final keys = {base, for (final v in variants) analysisCacheKey(v)};
      expect(keys, hasLength(variants.length + 1));
      expect(analysisCacheKey(stateOf('23m406p789s23455s')), base);
    });
  });
}
