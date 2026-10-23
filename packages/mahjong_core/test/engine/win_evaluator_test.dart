import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

int _id(String label) => idsFromNotation(label).single;

/// [closed13] に和了牌 [win] を足して評価する。
WinEvaluation? _eval(
  String closed13,
  String win, {
  String melds = '',
  String dora = '',
  bool dealer = false,
}) {
  final hand = stateOf(closed13, melds: melds, dora: dora, dealer: dealer);
  final counts = List<int>.of(hand.counts);
  counts[_id(win)]++;
  final red = {
    for (final id in hand.redIds)
      if (counts[id] > 0) id,
  };
  return WinEvaluator(hand).evaluate(counts, _id(win), redHeld: red);
}

void main() {
  test('ポンした刻子は明刻: 三暗刻にならず、役なしなら和了できない', () {
    // 111m 777s は暗刻、555p はポン。ポンを暗刻と数えると三暗刻（2 翻）になるが、
    // 正しくは 2 暗刻で役なし（1m・9p で断么九なし）。
    final ev = _eval('111m777s23m99p', '4m', melds: 'pon:5p')!;
    expect(ev.ron, isNull);
    expect(ev.tsumo, isNull);
    expect(ev.ronPoints, 0);
    expect(ev.ronYaku, isEmpty);
    expect(ev.ronRiichiPoints, isNull, reason: '副露しているのでリーチ不可');
  });

  test('チーした順子を含まない分け方は使わない', () {
    // チー 123m + 手牌 112233m 456p 99s。111m 222m 333m と分けると門前の三暗刻・
    // ツモになってしまうが、チーした 123m を含む分け方（123m×3）だけが正しく、役なし。
    final ev = _eval('11223m456p99s', '3m', melds: 'chi:1m')!;
    expect(ev.tsumo, isNull);
    expect(ev.ron, isNull);
    expect(ev.tsumoYaku, isNot(contains(YakuId.sanankou)));
  });

  test('暗槓は門前のまま: ツモは門前清自摸和、ダマのロンは役なし', () {
    // 234m 456p 78s 11z + 暗槓 9p、6s 待ち。ツモ: 20+2+32（暗槓么九）+2（場風の雀頭）
    // = 56 → 60 符 1 翻 = 500/1000。リーチのロン: 20+10+32+2 = 64 → 70 符 1 翻 = 2300。
    final ev = _eval('234m456p78s11z', '6s', melds: 'ankan:9p')!;
    expect(ev.ron, isNull);
    expect(ev.tsumo!.closed, isTrue);
    expect(ev.tsumo!.fu, 60);
    expect(ev.tsumoPoints, 2000);
    expect(ev.ronRiichiPoints, 2300);
    expect(ev.tsumoRiichiPoints, 4000);
  });

  test('ドラ・赤の枚数と点数', () {
    // 34m 4(赤5)6p 789s 234s 55s に 2m で和了。ドラ 3s（1 枚）+ 赤 1 = 2。
    // ロン: 平和 + ドラ 2 = 3 翻 30 符 = 3900。ツモ: 4 翻 20 符 = 1300/2600 = 5200。
    final ev = _eval('34m406p789s23455s', '2m', dora: '3s')!;
    expect(ev.doraCount, 2);
    expect(ev.ronPoints, 3900);
    expect(ev.tsumoPoints, 5200);
    expect(ev.ronYaku, {YakuId.pinfu, YakuId.dora});
    // 赤を持っていない扱い（切った後など）なら 1 枚少ない
    final hand = stateOf('34m456p789s23455s', dora: '3s');
    final counts = List<int>.of(hand.counts);
    counts[_id('2m')]++;
    final plain = WinEvaluator(hand).evaluate(counts, _id('2m'))!;
    expect(plain.doraCount, 1);
    expect(plain.ronPoints, 2000);
  });

  test('親の点数', () {
    // 平和・断么九 2 翻 30 符の親ロン 2900、親ツモ（3 翻 20 符）1300 オール = 3900
    final ev = _eval('34m456p678s23455s', '2m', dealer: true)!;
    expect(ev.ronPoints, 2900);
    expect(ev.tsumoPoints, 3900);
  });

  test('役満の結果は役満だけが並ぶ（HandAnalyzer の正規化）', () {
    final ev = _eval('111m222p333s44s55z', '4s')!;
    expect(ev.tsumoYaku, {YakuId.suuankou});
    expect(ev.tsumoPoints, 32000);
    expect(ev.ronYaku, {YakuId.toitoi, YakuId.sanankou});
    expect(ev.ronPoints, 8000);
  });

  test('和了形でなければ null、同じ和了形はメモする', () {
    final hand = stateOf('23m456p789s23455s');
    final evaluator = WinEvaluator(hand);
    final counts = List<int>.of(hand.counts);
    counts[_id('9m')]++;
    expect(evaluator.evaluate(counts, _id('9m')), isNull);
    counts[_id('9m')]--;
    counts[_id('1m')]++;
    final a = evaluator.evaluate(counts, _id('1m'));
    final b = evaluator.evaluate(counts, _id('1m'));
    expect(identical(a, b), isTrue);
    expect(evaluator.cacheSize, 2);
  });

  test('scoreHasYaku: ドラだけでは役にならない', () {
    final analyzer = HandAnalyzer();
    final ev = analyzer.evaluateBest(
      '1m 2m 3m 4p 5p 6p 7s 8s 9s 5s 5s 5s 1z 1z'.split(' '),
      initialQuickContext.copyWith(doraIndicators: 2),
      Rulesets.mLeague(),
      winningLabel: '5s',
    )!;
    expect(ev.score.han, 2);
    expect(scoreHasYaku(ev.score), isFalse);
    expect(prospectYakuOf(ev.score), {YakuId.dora});
  });
}
