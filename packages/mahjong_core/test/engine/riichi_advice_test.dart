// リーチ判断（設計書 4.6.5、仕様 4.5）。子・南家・東場。
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

double _half({
  required int shanten,
  required int ukeireTotal,
  int? turn,
  ShantenType type = ShantenType.standard,
}) => 0.5;

RiichiAdvice? _advice(String hand, {String melds = '', String visible = ''}) =>
    buildThirteenReport(
      stateOf(hand, melds: melds, visible: visible),
      riichiAdvice: true,
      winEaseOf: _half,
    ).riichi;

void main() {
  group('adviseRiichi（待ちの点数から）', () {
    RiichiWait w(
      int remaining, {
      int ron = 0,
      int tsumo = 0,
      int ronR = 0,
      int tsumoR = 0,
      bool yaku = true,
    }) => (
      remaining: remaining,
      ronPoints: ron,
      tsumoPoints: tsumo,
      ronRiichiPoints: ronR,
      tsumoRiichiPoints: tsumoR,
      ronHasYaku: yaku,
    );

    test('役なし（どの待ちもダマのロンに役が無い）はリーチ一択', () {
      final a = adviseRiichi([
        w(4, tsumo: 1100, ronR: 1300, tsumoR: 2000, yaku: false),
      ], winEase: 0.4);
      expect(a.recommendRiichi, isTrue);
      expect(a.reason, RiichiReason.noYaku);
      expect(a.riichiPoints, 1650);
      expect(a.damaPoints, 550);
      expect(a.riichiValue, closeTo(1650 * 0.4, 1e-9));
      expect(a.damaValue, closeTo(550 * 0.4 * 1.1, 1e-9));
    });

    test('リーチで打点が上がらなければダマ（1.1 倍の補正）', () {
      final a = adviseRiichi([
        w(3, ron: 32000, tsumo: 32000, ronR: 32000, tsumoR: 32000),
      ], winEase: 0.3);
      expect(a.recommendRiichi, isFalse);
      expect(a.reason, RiichiReason.damaValue);
    });

    test('ちょうど 1.1 倍ならリーチ（以上で推奨）', () {
      final a = adviseRiichi([
        w(4, ron: 1000, tsumo: 1000, ronR: 1100, tsumoR: 1100),
      ], winEase: 0.5);
      expect(a.reason, RiichiReason.riichiValue);
      expect(a.recommendRiichi, isTrue);
    });

    test('待ちの残り枚数で重み付けする（残り 0 枚の待ちは数えない）', () {
      final a = adviseRiichi([
        w(1, ron: 8000, tsumo: 8000, ronR: 12000, tsumoR: 12000),
        w(3, ron: 1000, tsumo: 1000, ronR: 2000, tsumoR: 2000),
        w(0, ron: 99999, tsumo: 99999, ronR: 99999, tsumoR: 99999),
      ], winEase: 1);
      expect(a.damaPoints, (8000 + 3 * 1000) / 4);
      expect(a.riichiPoints, (12000 + 3 * 2000) / 4);
    });

    test('待ちが残っていない（空テン）はダマ', () {
      final a = adviseRiichi([w(0, ron: 1000)], winEase: 0);
      expect(a.recommendRiichi, isFalse);
      expect(a.reason, RiichiReason.noWaitsLeft);
      expect(a.riichiValue, 0);
      expect(a.damaValue, 0);
    });
  });

  group('13 枚の手（buildThirteenReport）', () {
    test('門前の役なしテンパイ: リーチ一択', () {
      // 12m 辺張の 3m 待ち。ダマはロン不可、ツモ 30 符 1 翻 1,100。
      // リーチ: ロン 40 符 1 翻 1,300、ツモ 30 符 2 翻 2,000。
      final a = _advice('12m 456p 789s 23455s')!;
      expect(a.reason, RiichiReason.noYaku);
      expect(a.recommendRiichi, isTrue);
      expect(a.riichiPoints, (1300 + 2000) / 2);
      expect(a.damaPoints, (0 + 1100) / 2);
      expect(a.winEase, 0.5);
    });

    test('愚形の安手: リーチ推奨', () {
      // 24m 嵌張の 3m 待ちでタンヤオのみ。ダマ: ロン 40 符 1 翻 1,300、ツモ 30 符 2 翻
      // 2,000。リーチ: ロン 40 符 2 翻 2,600、ツモ 30 符 3 翻 4,000。
      // 3,300 ≥ 1,650 × 1.1 なのでリーチ。
      final a = _advice('24m 456p 678s 234s 55p')!;
      expect(a.reason, RiichiReason.riichiValue);
      expect(a.recommendRiichi, isTrue);
      expect(a.riichiPoints, 3300);
      expect(a.damaPoints, 1650);
    });

    test('高打点のダマ（清一色の倍満）: リーチしても倍満のままなので様子見', () {
      // 22m 345m 456m 678m 34m: 清一色・断么九・平和でダマでも全部の待ちが倍満 16,000。
      // リーチで一部が三倍満になっても 1.1 倍に届かない。
      final a = _advice('22m 345m 456m 678m 34m')!;
      expect(a.damaPoints, 16000);
      expect(a.riichiPoints, greaterThan(16000));
      expect(a.riichiPoints, lessThan(16000 * 1.1));
      expect(a.reason, RiichiReason.damaValue);
      expect(a.recommendRiichi, isFalse);
    });

    test('役満のダマ（四暗刻単騎）: 様子見', () {
      final a = _advice('111m 333p 555s 999s 4z')!;
      expect(a.damaPoints, 32000);
      expect(a.riichiPoints, 32000);
      expect(a.reason, RiichiReason.damaValue);
    });

    test('待ちが全部見えている（空テン）: ダマ', () {
      final a = _advice('12m 456p 789s 23455s', visible: '3333m')!;
      expect(a.reason, RiichiReason.noWaitsLeft);
      expect(a.recommendRiichi, isFalse);
    });

    test('副露・テンパイでない手・riichiAdvice=false では null', () {
      expect(_advice('234m 456p 78s 11z', melds: 'pon:6s'), isNull);
      expect(_advice('12m 456p 789s 2345s 9p'), isNull);
      expect(
        buildThirteenReport(stateOf('12m 456p 789s 23455s')).riichi,
        isNull,
      );
    });

    test('待ちにリーチ込みの点数（門前）を付ける。副露は null', () {
      final r = buildThirteenReport(stateOf('24m 456p 678s 234s 55p'));
      expect(r.waits.single.ronRiichiPoints, 2600);
      expect(r.waits.single.tsumoRiichiPoints, 4000);
      final open = buildThirteenReport(
        stateOf('234m 456p 11z 66s', melds: 'chi:7s'),
      );
      for (final wait in open.waits) {
        expect(wait.ronRiichiPoints, isNull);
        expect(wait.tsumoRiichiPoints, isNull);
      }
    });
  });

  group('14 枚の候補', () {
    test('門前でテンパイに取る候補にだけ付ける（Pro）。無料は null', () {
      // 456p 678s 345s 99m 2m 3m 5m: 打 5m は平和の両面、打 2m は嵌張でリーチのみ。
      final hand = stateOf('456p 678s 345s 99m 2m 3m 5m');
      final pro = analyzeDiscards(hand, winEaseOf: _half);
      String label(DiscardCandidate c) => labelOfId(c.discardId);
      for (final c in pro) {
        if (c.shantenAfter == 0) {
          expect(c.riichi, isNotNull, reason: label(c));
        } else {
          expect(c.riichi, isNull, reason: label(c));
        }
      }
      final c2m = pro.firstWhere((c) => label(c) == '2m');
      expect(c2m.riichi!.reason, RiichiReason.noYaku);
      final c5m = pro.firstWhere((c) => label(c) == '5m');
      expect(c5m.riichi!.reason, RiichiReason.riichiValue);
      // 13 枚にしたときと同じ
      expect(
        c5m.riichi,
        buildThirteenReport(
          afterDiscard(hand, idsFromNotation('5m').single),
          riichiAdvice: true,
          winEaseOf: _half,
        ).riichi,
      );
      for (final c in analyzeDiscards(hand, deep: false, winEaseOf: _half)) {
        expect(c.riichi, isNull);
      }
    });

    test('副露した手の候補には付けない', () {
      // 打 6s で 78s の両面テンパイ（チーしているのでリーチできない）
      final hand = stateOf('234m 456p 11z 6s 78s', melds: 'chi:7s');
      final list = analyzeDiscards(hand);
      expect(list.any((c) => c.shantenAfter == 0), isTrue);
      for (final c in list) {
        expect(c.riichi, isNull);
      }
    });
  });
}
