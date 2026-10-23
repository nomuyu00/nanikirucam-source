// 3 軸の順位（設計書 4.6.4、仕様 7.3）。「速さと打点で解が割れる」代表 20 手で各軸の
// 1 位を固定する。上がりやすさは表（win_ease_table.g.dart）の差し替えに左右されない
// よう、単調な仮の関数 [_ease] に差し替える（バランス軸はこの関数のもとでの値）。
//
// 前提: 子・南家・東場（1z は場風、2z は自風）。ドラはドラそのもの。
import 'dart:math';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

/// 受け入れ u 枚を 12 回のツモで引く確率 × シャンテン 1 段ごとに 0.35。
double _ease({
  required int shanten,
  required int ukeireTotal,
  int? turn,
  ShantenType type = ShantenType.standard,
}) => shanten < 0
    ? 1
    : (1 - pow(1 - ukeireTotal / 70, 12)) * pow(0.35, shanten).toDouble();

class _Split {
  final String hand;
  final String melds;
  final String dora;
  final String speed;
  final String points;
  final String balance;
  const _Split(
    this.hand, {
    this.melds = '',
    required this.dora,
    required this.speed,
    required this.points,
    required this.balance,
  });
}

const _splits = <_Split>[
  // 1m（ドラ）を切ると 123m ができて受け入れ最大（14 枚）、ドラ対子 11m を残す 6s・6z 切りは
  // 13 枚でドラ 2 が確定。
  _Split(
    '112356m455667p6s6z',
    dora: '1m',
    speed: '1m',
    points: '6s,6z',
    balance: '6s,6z',
  ),
  // 1p 切りは受け入れ 31 枚、萬子の 45m を外すと筒子の清一色（中央値 16000）。
  _Split(
    '45m145667778889p',
    dora: '3s',
    speed: '1p',
    points: '4m,5m',
    balance: '4m,5m',
  ),
  // 1m 切りは受け入れ最大、3m 切りは 13m の嵌張（2m）を残し 123 の三色が濃厚。
  _Split(
    '133m1123p1237899s',
    dora: '7z',
    speed: '1m',
    points: '3m',
    balance: '3m',
  ),
  // 6s 切りは受け入れ 31 枚、8s 切りは 666s・888s の暗刻と 33z を残し三暗刻が濃厚。
  _Split(
    '9p35666778888s33z',
    dora: '7s',
    speed: '6s',
    points: '8s',
    balance: '8s',
  ),
  // 6z 切りは受け入れ 39 枚の一般形、8s 切りは対子 5 組で七対子が確定（受け入れ 9 枚）。
  _Split(
    '445p4556677888s6z',
    dora: '2m',
    speed: '6z',
    points: '8s',
    balance: '6z',
  ),
  // テンパイの取り方: 9s 切りは 3s・4s の 7 枚待ち、4s 切りは 9s 単騎（3 枚）だが
  // 777p・888p・222s の三暗刻が確定。
  _Split(
    '777788889p22249s',
    dora: '1m',
    speed: '9s',
    points: '4s',
    balance: '4s',
  ),
  // 字牌（1z・6z）を切ると 7777m の 4 枚目が生きて受け入れ 21 枚、7m 切りは場風・發の
  // 両方を残して役牌のシャンポンが狙える（受け入れ 8 枚）。
  _Split(
    '2347777m44789s16z',
    dora: '3m',
    speed: '1z,6z',
    points: '7m',
    balance: '7m',
  ),
  // 3s 切りは受け入れ 19 枚、7m 切りは 44566m が 5m で 445566m になる形だけが残り
  // 一盃口が確定。
  _Split(
    '445667m345p367s44z',
    dora: '2m',
    speed: '3s',
    points: '7m',
    balance: '7m',
  ),
  // テンパイの取り方: 7p 切りは 6m・9m の延べ単（6 枚）だが役なし、9m 切りは 4p・7p
  // 待ち（5 枚）で断么九・平和が確定し 4p ならドラも増える。
  _Split(
    '6789m3455677p456s',
    dora: '4p',
    speed: '7p',
    points: '9m',
    balance: '9m',
  ),
  // 1z 切りは受け入れ 38 枚、4m を外すと索子と字牌だけになり混一色が確定。
  _Split(
    '4m578888999s1222z',
    dora: '2m',
    speed: '1z',
    points: '4m',
    balance: '4m',
  ),
  // 7s 切りは受け入れ 28 枚、5m 切り・4p 切りは 444m・777p・333z の暗刻を生かして
  // 三暗刻（ドラ 3 の 777p 込みで跳満級）。
  _Split(
    '44457m45777p7s333z',
    dora: '7p',
    speed: '7s',
    points: '5m,4p',
    balance: '5m,4p',
  ),
  // テンパイの取り方: 8m 切りは 6s・8m など 11 枚待ちで三暗刻・中、6s 切りは 8m 単騎で
  // 四暗刻（役満 32000）。
  _Split(
    '2228m222p6777s777z',
    dora: '4p',
    speed: '8m',
    points: '6s',
    balance: '6s',
  ),
  // 副露: チー 567p。4p・6p 切りは受け入れ 11 枚だが 11m があって役なし、1m を切れば
  // 喰いタンが確定（受け入れ 10 枚）。
  _Split(
    '1133445m46p77s',
    melds: 'chi:5p',
    dora: '4s',
    speed: '4p,6p',
    points: '1m',
    balance: '1m',
  ),
  // 副露: ポン 777p。9p 切りは受け入れ最大、3s を外せば清一色が確定（ドラ 8p 2 枚込み）。
  _Split(
    '1333456889p3s',
    melds: 'pon:7p',
    dora: '8p',
    speed: '9p',
    points: '3s',
    balance: '3s',
  ),
  // 副露テンパイ: 4m 切りは 1p 単騎・3p 辺張の 7 枚待ちだが 3p では役なし、1p 切りは
  // 4m 単騎（3 枚）で対々和・三暗刻・断么九が確定（満貫）。
  _Split(
    '4777m1222p444s',
    melds: 'pon:6s',
    dora: '1s',
    speed: '4m',
    points: '1p',
    balance: '1p',
  ),
  // 副露: チー 678m、混一色。8m 切りは受け入れ最大、2m・4m 切りは白・發の対子と 777m を
  // 残して役牌が濃厚（満貫級）。
  _Split(
    '2477788m5566z',
    melds: 'chi:6m',
    dora: '7p',
    speed: '8m',
    points: '2m,4m',
    balance: '2m,4m',
  ),
  // 副露: ポン 555m。4m 切りは受け入れ 18 枚、4p 切りは 77m・33p・88p の対子が残り
  // 対々和・断么九が確定。
  _Split(
    '477m22233488p',
    melds: 'pon:5m',
    dora: '7p',
    speed: '4m',
    points: '4p',
    balance: '4p',
  ),
  // 副露: チー 678s。7s 切りは受け入れ 24 枚だが 45m が残り役なし、萬子の 4m・5m を
  // 外せば清一色が濃厚。
  _Split(
    '45m455557999s',
    melds: 'chi:6s',
    dora: '4s',
    speed: '7s',
    points: '4m,5m',
    balance: '4m,5m',
  ),
  // 副露: ポン 111p。7z 切りは受け入れ最大だが役なし、索子の 1s・2s を外せば筒子と
  // 7z の混一色が狙える。
  _Split(
    '34456678p12s7z',
    melds: 'pon:1p',
    dora: '8m',
    speed: '7z',
    points: '1s,2s',
    balance: '1s,2s',
  ),
  // 副露: ポン 777m。6s 切りは受け入れ 23 枚だが 9m・9p が残り役なし、9m を切れば
  // 喰いタンが狙える（9p も後で切る）。
  _Split(
    '3456789m679p6s',
    melds: 'pon:7m',
    dora: '3z',
    speed: '6s',
    points: '9m',
    balance: '9m',
  ),
];

String _labels(List<int> ids) => ids.map(labelOfId).join(',');

/// 同値は同順位（1,1,3…）の付け方になっているか。
void _expectCompetitionRanks(List<int> ranks) {
  final sorted = List<int>.of(ranks)..sort();
  for (var i = 0; i < sorted.length; i++) {
    if (i == 0) {
      expect(sorted[i], 1);
    } else if (sorted[i] != sorted[i - 1]) {
      expect(sorted[i], i + 1);
    }
  }
}

void main() {
  final engine = DefaultNanikiruEngine(winEaseOf: _ease);

  group('速さと打点で割れる 20 手', () {
    test('20 手', () => expect(_splits, hasLength(20)));
    for (final s in _splits) {
      test('${s.hand}${s.melds.isEmpty ? '' : ' +${s.melds}'} ドラ${s.dora}', () {
        final hand = stateOf(s.hand, melds: s.melds, dora: s.dora);
        final report = engine.analyze(hand, deep: true);
        final best = report.bestByAxis;
        expect(_labels(best[StrategyAxis.speed]!), s.speed);
        expect(_labels(best[StrategyAxis.points]!), s.points);
        expect(_labels(best[StrategyAxis.balance]!), s.balance);
        // 割れている（速さの 1 位と打点の 1 位が重ならない）
        expect(
          best[StrategyAxis.speed]!.toSet().intersection(
            best[StrategyAxis.points]!.toSet(),
          ),
          isEmpty,
        );
      });
    }
  });

  group('順位の付け方', () {
    for (final s in _splits.take(8)) {
      test('同値は同順位・打点軸の除外・無料と Pro で同じ順位: ${s.hand}', () {
        final hand = stateOf(s.hand, melds: s.melds, dora: s.dora);
        final pro = analyzeDiscards(hand, winEaseOf: _ease);
        final free = analyzeDiscards(hand, winEaseOf: _ease, deep: false);
        expect(
          free.map((c) => [c.discardId, c.rankByAxis]).toList(),
          pro.map((c) => [c.discardId, c.rankByAxis]).toList(),
        );
        for (final axis in StrategyAxis.values) {
          _expectCompetitionRanks([
            for (final c in pro)
              if (c.rankByAxis.containsKey(axis)) c.rankByAxis[axis]!,
          ]);
        }
        final bestShanten = pro.map((c) => c.shantenAfter).reduce(min);
        for (final c in pro) {
          expect(
            c.rankByAxis.containsKey(StrategyAxis.points),
            c.shantenAfter <= bestShanten + 1,
          );
        }
        // 返す順は速さの順位 → 牌 id
        for (var i = 1; i < pro.length; i++) {
          final a = pro[i - 1].rankByAxis[StrategyAxis.speed]!;
          final b = pro[i].rankByAxis[StrategyAxis.speed]!;
          expect(a <= b, isTrue);
          if (a == b) {
            expect(pro[i - 1].discardId, lessThan(pro[i].discardId));
          }
        }
      });
    }

    test('速さ軸: シャンテン → 受け入れ → 良形率 → 中央値', () {
      // 打 9s と打 4s はどちらもテンパイ。受け入れ 7 枚の 9s が上。
      final list = analyzeDiscards(
        stateOf('777788889p22249s', dora: '1m'),
        winEaseOf: _ease,
      );
      final byLabel = {for (final c in list) labelOfId(c.discardId): c};
      expect(byLabel['9s']!.rankByAxis[StrategyAxis.speed], 1);
      expect(byLabel['4s']!.rankByAxis[StrategyAxis.speed], 2);
      // 受け入れ・良形率が同じ 1m・4m 切り（どちらも平和の 7 枚待ち）は中央値も同じで同順位
      final same = analyzeDiscards(stateOf('123m406p789s23455s'));
      final b = {for (final c in same) labelOfId(c.discardId): c};
      expect(b['1m']!.rankByAxis[StrategyAxis.speed], 1);
      expect(b['4s']!.rankByAxis[StrategyAxis.speed], 1);
      // 2s 切り（34s + 55s の 2s・5s 待ち。2s は河に 1 枚、5s は手に 2 枚で計 5 枚）は下
      expect(b['2s']!.ukeire.total, 5);
      expect(b['2s']!.rankByAxis[StrategyAxis.speed], 6);
    });

    test('打点・バランスで中央値が同じなら、受け入れより先にシャンテン数を見る', () {
      // 二向聴以上の目安は中央値がそろいやすい。戻す打牌（三向聴）は受け入れが多くても下。
      final list = analyzeDiscards(
        stateOf('1245m3378p66789s1z'),
        winEaseOf:
            ({
              required shanten,
              required ukeireTotal,
              turn,
              type = ShantenType.standard,
            }) => 0,
      );
      final best = bestByAxisOf(list);
      for (final id in [
        ...best[StrategyAxis.points]!,
        ...best[StrategyAxis.balance]!,
      ]) {
        expect(list.firstWhere((c) => c.discardId == id).shantenAfter, 2);
      }
    });
  });

  group('消える役と無料版の省略', () {
    // 123m 4(赤5)6p 789s 23455s の和了形。打 5p は赤（唯一の 5p）を切るのでドラが消え、
    // 46p 嵌張待ちで平和も消える。
    final hand = stateOf('123m406p789s23455s');

    test('Pro: 消える役を候補に付ける', () {
      final list = analyzeDiscards(hand);
      final c5p = list.firstWhere((c) => labelOfId(c.discardId) == '5p');
      expect(yakuString(c5p.yaku), 'riichi:certain pinfu:lost dora:lost x0');
      final c1m = list.firstWhere((c) => labelOfId(c.discardId) == '1m');
      expect(
        yakuString(c1m.yaku),
        'pinfu:certain riichi:certain dora:certain x1',
      );
      // 1m 切りは 23m の 1m・4m 待ち、平和 + 赤 = ロン 2000、ツモ 2700
      expect(rangeString(c1m.points), '2000/2000/2700');
      expect(rangeString(c1m.riichiPoints), '3900/3900/5200');
      expect(c1m.goodShapeRate, 1.0);
      expect(c1m.twoStepAverage, isNull);
      expect(c1m.reasons, isEmpty);
    });

    test('無料: 消える役・成立させる牌・良形率を省く（順位・打点は同じ）', () {
      final pro = analyzeDiscards(stateOf('23m456p678s23455s9m'));
      final free = analyzeDiscards(stateOf('23m456p678s23455s9m'), deep: false);
      for (var i = 0; i < pro.length; i++) {
        expect(free[i].discardId, pro[i].discardId);
        expect(free[i].points, pro[i].points);
        expect(free[i].riichiPoints, pro[i].riichiPoints);
        expect(free[i].winEase, pro[i].winEase);
        expect(free[i].goodShapeRate, isNull);
        expect(
          free[i].yaku.any((p) => p.confidence == YakuConfidence.lost),
          isFalse,
        );
        expect(free[i].yaku.every((p) => p.enablingTiles.isEmpty), isTrue);
        expect(
          free[i].yaku.map((p) => p.yaku).toList(),
          pro[i].yaku
              .where((p) => p.confidence != YakuConfidence.lost)
              .map((p) => p.yaku)
              .toList(),
        );
      }
      // Pro の 9m 切りには「狙える: 4m で断么九」がある
      final c9m = pro.firstWhere((c) => labelOfId(c.discardId) == '9m');
      expect(yakuString(c9m.yaku), contains('tanyao:possible[4m]'));
    });
  });
}
