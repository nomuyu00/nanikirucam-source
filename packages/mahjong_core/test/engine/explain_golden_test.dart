// 理由タグのゴールデン（設計書 4.9「代表的な何切る 30 問（自作）」）。
//
// 各問: 14 枚の手、速さ軸の正解（同点はすべて）、正解の打牌に付くタグ、必要なら他の打牌に
// 付くタグ。タグの書き方は「code(数)[牌]{役}」。子・南家・東場（1z 東は場風、2z 南は自風、
// 5z〜7z は三元牌で、どれも役牌。3z 西・4z 北はオタ風）。
//
// 上がりやすさは表の作り直しに左右されないよう単調な仮の関数にする（速さ軸・打点軸・タグは
// 上がりやすさを使わない。バランス軸だけが使う）。
import 'dart:math';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

double _fakeWinEase({
  required int shanten,
  required int ukeireTotal,
  int? turn,
  ShantenType type = ShantenType.standard,
}) => shanten < 0
    ? 1
    : (1 - pow(1 - ukeireTotal / 70, 12)) * pow(0.35, shanten).toDouble();

String reasonString(Reason r) {
  final b = StringBuffer(r.tag.code);
  if (r.count != null) b.write('(${r.count})');
  if (r.tileIds.isNotEmpty) b.write('[${r.tileIds.map(labelOfId).join(',')}]');
  if (r.yaku.isNotEmpty) b.write('{${r.yaku.map((y) => y.name).join(',')}}');
  return b.toString();
}

class _Problem {
  final String id;
  final String hand;
  final String melds;
  final String dora;
  final String visible;

  /// 速さ軸の 1 位（同点はすべて、牌 id の順）。
  final List<String> answer;

  /// 打牌 → その候補の理由（全部、タグの宣言順）。正解の打牌は必ず書く。
  final Map<String, List<String>> reasons;

  /// なぜそのタグか（1 行）。
  final String why;

  const _Problem(
    this.id,
    this.hand, {
    this.melds = '',
    this.dora = '',
    this.visible = '',
    required this.answer,
    required this.reasons,
    required this.why,
  });
}

const _problems = <_Problem>[
  // ---- 孤立字牌 ---------------------------------------------------------------
  _Problem(
    'A1',
    '234m 567p 678s 33z 9m 1p 4z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]'],
      '9m': ['isolated_terminal[9m]'],
    },
    why: 'くっつき一向聴。北は重なり 3 枚だけ、9m・1p はくっつき 11 枚ずつ。オタ風の北から切る',
  ),
  _Problem(
    'A2',
    '234m 567p 678s 33z 9m 3s 4z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]', 'floating_middle[3s]'],
      '3s': [],
    },
    why: '浮き牌の比較は 字牌 → 端 → 中張牌。3s を残すとくっつきが 5 種で受け入れ最大',
  ),
  _Problem(
    'A3',
    '23m 456m 34p 78p 99s 57s 4z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]'],
    },
    why: '二向聴の 6 ブロック。孤立した北を切れば 4 つの搭子を全部残せる',
  ),
  _Problem(
    'A4',
    '23m 45p 78p 57s 99s 4z',
    melds: 'pon:7z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]'],
    },
    why: '中ポンで役あり。搭子は 4 つとも残し、孤立したオタ風を切る',
  ),
  // ---- 端牌 -------------------------------------------------------------------
  _Problem(
    'B1',
    '456p 22z 23m 67m 34s 78s 9p',
    answer: ['9p'],
    reasons: {
      '9p': ['isolated_terminal[9p]'],
    },
    why: '両面 4 つの二向聴。孤立した 9p を切れば受け入れ 32 枚で最大',
  ),
  _Problem(
    'B2',
    '234m 567p 678s 33z 9m 3s 1p',
    visible: '23p',
    answer: ['1p'],
    reasons: {
      '1p': ['isolated_terminal[1p]', 'floating_middle[3s]'],
      '9m': ['isolated_terminal[9m]', 'floating_middle[3s]'],
    },
    why: '端の浮き牌が 2 つ。2p・3p が見えていて 1p のくっつきが少ないので 1p から切る',
  ),
  _Problem(
    'B3',
    '23m 67m 34s 78s 22z 9p',
    melds: 'chi:3p',
    answer: ['9p'],
    reasons: {
      '9p': ['isolated_terminal[9p]'],
    },
    why: 'チーした手でも同じ。両面 4 つを残し孤立の 9p を切る',
  ),
  _Problem(
    'B4',
    '123m 789p 123s 33z 6m 4p 9s',
    answer: ['9s'],
    reasons: {
      '9s': ['isolated_terminal[9s]', 'floating_middle[6m,4p]'],
      '6m': ['yaku_gain{chanta}'],
      '4p': ['yaku_gain{chanta}'],
    },
    why: '速さは端の 9s を切って中張牌を残す。打点なら 6m・4p を切ってチャンタを残す',
  ),
  // ---- 辺張外し ---------------------------------------------------------------
  _Problem(
    'C1',
    '12m 456m 678p 23s 67s 99m',
    answer: ['1m', '2m'],
    reasons: {
      '1m': ['penchan_fix(4)[1m,2m]'],
      '2m': ['penchan_fix(4)[1m,2m]'],
      '2s': [],
    },
    why: '5 ブロックの一向聴。辺張を外すと両面 2 つで 16 枚、両面を崩すより 4 枚多い',
  ),
  _Problem(
    'C2',
    '234m 67m 23p 89p 567s 55s',
    answer: ['8p', '9p'],
    reasons: {
      '8p': ['penchan_fix(4)[8p,9p]'],
      '9p': ['penchan_fix(4)[8p,9p]'],
    },
    why: '89p の辺張を外して両面 2 つを残す',
  ),
  _Problem(
    'C3',
    '12p 45m 789m 56s 234s 77p',
    answer: ['1p', '2p'],
    reasons: {
      '1p': ['penchan_fix(4)[1p,2p]'],
      '2p': ['penchan_fix(4)[1p,2p]'],
    },
    why: '辺張 12p を外す。両面を崩すと受け入れが 4 枚以上減る',
  ),
  _Problem(
    'C4',
    '12m 45p 67s 234s 99m',
    melds: 'pon:6z',
    answer: ['1m', '2m'],
    reasons: {
      '1m': ['penchan_fix(4)[1m,2m]'],
      '2m': ['penchan_fix(4)[1m,2m]'],
    },
    why: '發ポンの手。辺張を外し両面 2 つで受ける',
  ),
  // ---- 嵌張 vs 両面 ------------------------------------------------------------
  _Problem(
    'D1',
    '234m 67m 13p 45s 678s 33z',
    answer: ['1p', '3p'],
    reasons: {
      '1p': ['kanchan_vs_ryanmen(4)[1p,3p]'],
      '3p': ['kanchan_vs_ryanmen(4)[1p,3p]'],
      '6m': [],
    },
    why: '両面 2 つと嵌張 13p。嵌張を外すと両面を崩すより 4 枚多い',
  ),
  _Problem(
    'D2',
    '345m 78m 46p 23s 789s 44z',
    answer: ['4p', '6p'],
    reasons: {
      '4p': ['kanchan_vs_ryanmen(4)[4p,6p]'],
      '6p': ['kanchan_vs_ryanmen(4)[4p,6p]'],
    },
    why: '嵌張 46p を外し、両面 78m・23s を残す',
  ),
  _Problem(
    'D3',
    '234m 78m 24p 67s 99p',
    melds: 'pon:5z',
    answer: ['2p', '4p'],
    reasons: {
      '2p': ['kanchan_vs_ryanmen(4)[2p,4p]'],
      '4p': ['kanchan_vs_ryanmen(4)[2p,4p]'],
    },
    why: '白ポンの手。嵌張 24p を外して両面 2 つ',
  ),
  _Problem(
    'D4',
    '234m 56m 34p 567p 79s 44z',
    answer: ['7s', '9s'],
    reasons: {
      '7s': ['kanchan_vs_ryanmen(7)[7s,9s]'],
      '9s': ['kanchan_vs_ryanmen(7)[7s,9s]'],
    },
    why: '34567p は 345 + 67 の両面。端の嵌張 79s を外すと 7 枚多い',
  ),
  // ---- ドラ残し ----------------------------------------------------------------
  _Problem(
    'E1',
    '234m 567p 678s 11m 3z 4z 1p',
    dora: '3z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]'],
      '3z': ['isolated_honor[3z]', 'keep_dora(1)[3z]'],
    },
    why: '西（ドラ）と北の受け入れは同じ。打点で上回るので北を切りドラを残す',
  ),
  _Problem(
    'E2',
    '23456m 99m 46p 13s 777z',
    dora: '4p',
    answer: ['1s', '3s'],
    reasons: {
      '1s': ['kanchan_vs_ryanmen(7)[1s,3s]'],
      '3s': ['kanchan_vs_ryanmen(7)[1s,3s]'],
      '4p': ['kanchan_vs_ryanmen(7)[4p,6p]', 'keep_dora(1)[4p]'],
      '6p': ['kanchan_vs_ryanmen(7)[4p,6p]'],
    },
    why: '嵌張 2 つの受け入れは同じ。ドラ 4p を含む 46p を残し 13s を外す',
  ),
  _Problem(
    'E3',
    '234p 678p 345s 333z 0m 9s',
    answer: ['9s'],
    reasons: {
      '9s': ['isolated_terminal[9s]', 'riichi_only_yaku'],
      '5m': ['keep_dora(1)[5m]', 'riichi_only_yaku'],
    },
    why: '単騎の選択。待ちの枚数は同じなので赤 5m を残して 9s を切る（役はリーチのみ）',
  ),
  // ---- 役が消える --------------------------------------------------------------
  _Problem(
    'F1',
    '1234m 567p 345s 678s 5p',
    answer: ['1m'],
    reasons: {
      '1m': [],
      '4m': ['yaku_loss{tanyao}'],
      '5p': ['yaku_loss{tanyao,pinfu}', 'riichi_only_yaku'],
    },
    why: '1m を切ればタンヤオ確定。4m を切ると 123m が残りタンヤオが消える',
  ),
  _Problem(
    'F2',
    '456p 678s 345s 99m 2m 3m 5m',
    answer: ['5m'],
    reasons: {
      '5m': [],
      '2m': ['yaku_loss{pinfu}', 'riichi_only_yaku'],
    },
    why: '5m を切れば 23m の両面で平和。2m を切ると 35m の嵌張で平和が消える',
  ),
  _Problem(
    'F3',
    '555z 234m 67m 34p 789s 9p',
    visible: '5z',
    answer: ['9p'],
    reasons: {
      '9p': ['isolated_terminal[9p]'],
      '5z': ['yaku_loss{yakuhaiHaku}'],
    },
    why: '白の刻子を崩すと残りの白が無く、役牌が二度と付かない',
  ),
  // ---- 七対子 ------------------------------------------------------------------
  _Problem(
    'G1',
    '11m 44p 77s 99s 33z 2m 6p 8s 5z',
    visible: '22m',
    answer: ['2m'],
    reasons: {
      '2m': ['seven_pairs_route(5)[1m,4p,7s,9s,3z]'],
    },
    why: '対子 5 組で七対子の一向聴。2m は残り 1 枚なので切る',
  ),
  _Problem(
    'G2',
    '22m 55m 88p 33s 77s 456p 4z',
    visible: '44z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]', 'seven_pairs_route(5)[2m,5m,8p,3s,7s]'],
    },
    why: '対子 5 組。北は残り 1 枚で重なりにくい。七対子の一向聴に取る',
  ),
  _Problem(
    'G3',
    '11m 44p 77s 99s 33z 22p 5m 8s',
    visible: '8s',
    answer: ['8s'],
    reasons: {
      '8s': ['seven_pairs_route(6)[1m,2p,4p,7s,9s,3z]'],
    },
    why: '七対子のテンパイ。8s 単騎は残り 2 枚、5m 単騎は 3 枚なので 8s を切る',
  ),
  // ---- くっつき ----------------------------------------------------------------
  _Problem(
    'H1',
    '789m 111p 777z 99s 2m 5p 5s',
    answer: ['2m'],
    reasons: {
      '2m': ['floating_middle[5p,5s]'],
    },
    why: 'くっつき一向聴。2m より 5p・5s の方がくっつく牌が多い',
  ),
  _Problem(
    'H2',
    '789m 111p 333z 99s 2m 5p 7z',
    answer: ['7z'],
    reasons: {
      '7z': ['floating_middle[2m,5p]'],
      '5p': ['yaku_gain{yakuhaiChun}'],
    },
    why: '中は重なり 3 枚だけ。役牌でも速さは中張牌の浮き牌を残す（打点なら中を残す）',
  ),
  _Problem(
    'H3',
    '123m 56m 789p 99s 3p 4s 9m 1s',
    answer: ['1s'],
    reasons: {
      '1s': ['isolated_terminal[1s]', 'floating_middle[3p,4s]'],
      '9m': ['isolated_terminal[9m]', 'floating_middle[3p,4s]'],
    },
    why: '二向聴のくっつき。1s のくっつき 2s・3s は 4s と重なるので、9m を残す方が 4 枚多い',
  ),
  // ---- その他（役がつく・リーチのみ） -----------------------------------------
  _Problem(
    'I1',
    '123m 456p 789s 99m 12s 4z',
    answer: ['4z'],
    reasons: {
      '4z': ['isolated_honor[4z]', 'riichi_only_yaku'],
      '1s': ['yaku_gain{pinfu}'],
    },
    why: '北を切れば辺張テンパイだがリーチのみ。打点なら 1s を切り平和を見る',
  ),
  _Problem(
    'I2',
    '123m 56m 123p 67p 13s 99s',
    answer: ['1s', '3s'],
    reasons: {
      '1s': ['kanchan_vs_ryanmen(4)[1s,3s]', 'yaku_loss{sanshoku}'],
      '3s': ['kanchan_vs_ryanmen(4)[1s,3s]', 'yaku_loss{sanshoku}'],
      '5m': ['yaku_gain{sanshoku}'],
      '7p': ['yaku_gain{sanshoku}'],
    },
    why: '速さは嵌張 13s を外す（三色が消える）。打点は両面を外して 2s で三色を残す',
  ),
];

HandState _handOf(_Problem p) =>
    stateOf(p.hand, melds: p.melds, dora: p.dora, visible: p.visible);

void main() {
  test('30 問', () => expect(_problems, hasLength(30)));

  group('Pro', () {
    for (final p in _problems) {
      test('${p.id} ${p.hand}: ${p.why}', () {
        final engine = DefaultNanikiruEngine(winEaseOf: _fakeWinEase);
        final r = engine.analyze(_handOf(p), deep: true);
        expect(
          r.bestByAxis[StrategyAxis.speed]!.map(labelOfId),
          p.answer,
          reason: '速さ軸の正解',
        );
        final byLabel = {
          for (final c in r.candidates) labelOfId(c.discardId): c,
        };
        for (final a in p.answer) {
          expect(p.reasons.containsKey(a), isTrue, reason: '正解 $a のタグを書く');
        }
        for (final e in p.reasons.entries) {
          expect(
            byLabel[e.key]!.reasons.map(reasonString),
            e.value,
            reason: '打${e.key}',
          );
        }
      });
    }
  });

  test('無料: 消える役（yaku_loss）だけ省き、他のタグは Pro と同じ', () {
    for (final p in _problems) {
      final hand = _handOf(p);
      final pro = DefaultNanikiruEngine(
        winEaseOf: _fakeWinEase,
      ).analyze(hand, deep: true);
      final free = DefaultNanikiruEngine(
        winEaseOf: _fakeWinEase,
      ).analyze(hand, deep: false);
      for (var i = 0; i < pro.candidates.length; i++) {
        expect(free.candidates[i].discardId, pro.candidates[i].discardId);
        expect(
          free.candidates[i].reasons,
          pro.candidates[i].reasons
              .where((x) => x.tag != ReasonTag.yakuLoss)
              .toList(),
          reason: '${p.id} 打${labelOfId(pro.candidates[i].discardId)}',
        );
      }
    }
  });

  test('タグの保存名（仕様 7.4 の snake_case）は往復でき、重複しない', () {
    final codes = ReasonTag.values.map((t) => t.code).toSet();
    expect(codes, hasLength(ReasonTag.values.length));
    for (final t in ReasonTag.values) {
      expect(reasonTagFromCode(t.code), t);
    }
    expect(reasonTagFromCode('safety'), isNull);
    expect(ReasonTag.keepDora.isCaution, isTrue);
    expect(ReasonTag.penchanFix.isCaution, isFalse);
  });

  group('個別の条件', () {
    Map<String, List<String>> reasonsOf(String hand, {String melds = ''}) {
      final r = DefaultNanikiruEngine(
        winEaseOf: _fakeWinEase,
      ).analyze(stateOf(hand, melds: melds), deep: true);
      return {
        for (final c in r.candidates)
          labelOfId(c.discardId): c.reasons.map(reasonString).toList(),
      };
    }

    test('役満のテンパイ（四暗刻単騎）は「リーチのみ」「役が消える」にしない', () {
      // 打 7z も打 4z も四暗刻の単騎。ダマで和了できる。役満の和了は役の一覧が役満
      // だけになる（対々和・三暗刻は載らない）が、それを「消える」とは言わない。
      final r = reasonsOf('111m 333p 555s 999s 4z 7z');
      expect(r['7z'], <String>[]);
      expect(r['4z'], ['isolated_honor[4z]']); // 北は役牌でない孤立字牌
    });

    test('国士が最小の手には形のタグを付けない', () {
      // 19m 19p 19s 123456z + 5m: 打 5m で国士テンパイ。字牌・端牌の孤立タグは出さない
      final r = reasonsOf('19m 19p 19s 123456z 5m');
      for (final reasons in r.values) {
        expect(reasons.where((x) => x.startsWith('isolated_')), isEmpty);
        expect(reasons.where((x) => x.startsWith('floating_')), isEmpty);
      }
    });

    test('役牌の浮き牌は isolated_honor にしない（自風・場風・三元牌）', () {
      // 3 面子 + 雀頭 + 浮き牌（東・南・白・9m）。どれも役牌で、9m は端の孤立
      final r = reasonsOf('234m 567p 678s 33z 1z 2z 5z');
      for (final z in ['1z', '2z', '5z']) {
        expect(r[z], isNot(contains('isolated_honor[$z]')), reason: z);
      }
    });
  });
}
