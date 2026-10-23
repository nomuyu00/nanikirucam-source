/// 理由タグ（設計書 4.7、仕様 7.4）。
///
/// 14 枚のブロック分解（`decomposeBlocks`）で打牌がどの役割の牌かを見て、切った後の
/// 受け入れ・役・ドラを候補どうしで比べてタグを付ける。日本語の文は UI が作る。
///
/// タグごとの条件（「最良」は候補の中で最も小さい打牌後のシャンテン数）:
///
/// | タグ | 条件 |
/// | --- | --- |
/// | isolatedHonor | 打牌が浮き牌（手に 1 枚）の字牌で役牌でない。シャンテン数が最良 |
/// | isolatedTerminal | 打牌が浮き牌の 1・9。シャンテン数が最良 |
/// | penchanFix | 打牌が辺張の牌。シャンテン数が最良で、同じシャンテン数で辺張を崩さない候補の最大より受け入れが n 枚多い（n > 0） |
/// | kanchanVsRyanmen | 打牌が嵌張の牌で、分解に両面がある。シャンテン数が最良で、同じシャンテン数で両面を崩す候補の最大より受け入れが n 枚多い（n > 0） |
/// | keepDora | 打牌がドラ（表ドラ、または最後の 1 枚の赤5） |
/// | yakuLoss | 役を同じ方法で調べた他の候補で確定・濃厚の役が、この候補では成立しない（Pro だけ。役満が成立し得る候補には付けない） |
/// | sevenPairsRoute | 門前で、打牌後の対子が 4 組以上、七対子のシャンテン数が打牌後のシャンテン数 + 1 以内 |
/// | floatingMiddle | 打牌が浮き牌で、それより真ん中寄りの 2〜8 の浮き牌を残し、その浮き牌を切るより速い（シャンテン数が小さいか、受け入れが多い）。シャンテン数が最良 |
/// | yakuGain | 速さ 1 位でない候補が打点かバランスで 1 位で、速さ 1 位の候補のどれでも成立しない役を残す（シャンテン数は最良 + 1 まで、役を同じ方法で調べた候補どうし） |
/// | riichiOnlyYaku | 門前で打牌後テンパイ、待ちが残っていて、リーチ以外の役（ドラを除き、役満を含む）が無い |
///
/// 「役を同じ方法で」: テンパイ・一向聴の経路の列挙か、二向聴以上の規則による目安か
/// （`PointRange.isEstimate`）。目安の規則は平和・一盃口などを見ないので混ぜない。
///
/// 浮き牌は「手に 1 枚だけで、字牌か、同じ色の ±2 に他の牌が無い」数牌（孤立牌）。
/// 国士が最小の手（分解が国士）では形のタグ（孤立・辺張・嵌張・浮き牌・七対子）を
/// 付けない。yakuLoss・yakuGain の役にはリーチ・ドラ・役満を入れない。
library;

import 'package:mahjong_core/src/engine/block.dart';
import 'package:mahjong_core/src/engine/blocks.dart';
import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/reason_tag.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/win_evaluator.dart';
import 'package:mahjong_core/src/engine/yaku.dart';

/// 14 枚の手 [hand] の候補 [candidates]（`analyzeDiscards` の結果。理由はまだ空で
/// よい）に理由タグを付ける。牌 id → 理由（タグの宣言順）。
///
/// [blocks] は [hand] の `decomposeBlocks`（渡さなければここで作る）。[deep] が
/// false（無料）なら [ReasonTag.yakuLoss] を出さない（消える役は Pro、仕様 5 章）。
Map<int, List<Reason>> explainCandidates(
  HandState hand,
  List<DiscardCandidate> candidates, {
  List<Block>? blocks,
  bool deep = true,
}) {
  if (hand.tileCount != 14) {
    throw ArgumentError.value(hand.tileCount, 'hand', '14 枚（副露込み）の手ではない');
  }
  final result = <int, List<Reason>>{};
  if (candidates.isEmpty) return result;
  final ctx = _Context(hand, candidates, blocks ?? decomposeBlocks(hand));
  for (final c in candidates) {
    final reasons = <Reason>[
      ...ctx.shapeReasons(c),
      ?ctx.keepDora(c),
      if (deep) ?ctx.yakuLoss(c),
      ?ctx.sevenPairs(c),
      ?ctx.yakuGain(c),
      ?ctx.riichiOnly(c),
    ]..sort((a, b) => a.tag.index.compareTo(b.tag.index));
    result[c.discardId] = reasons;
  }
  return result;
}

/// 打牌の役割の「切りやすさ」（小さいほど先に切る）。同じ牌が複数のブロックに
/// あるときは最も切りやすい役割をその牌の役割とする。
const List<BlockRole> _cutOrder = [
  BlockRole.isolated,
  BlockRole.penchan,
  BlockRole.kanchan,
  BlockRole.pair,
  BlockRole.ryanmen,
  BlockRole.head,
  BlockRole.meld,
];

class _Context {
  final HandState hand;
  final List<DiscardCandidate> candidates;
  final List<Block> blocks;
  final Map<int, DiscardCandidate> byId;
  final Map<int, Block> blockOf = {};
  final int bestShanten;
  final bool kokushi;
  final bool closed;
  final List<DiscardCandidate> speedBest;
  final Set<int> pointsOrBalanceBest;

  _Context(this.hand, this.candidates, this.blocks)
    : byId = {for (final c in candidates) c.discardId: c},
      bestShanten = candidates
          .map((c) => c.shantenAfter)
          .reduce((a, b) => a < b ? a : b),
      kokushi =
          shantenFromCounts(hand.counts, meldCount: hand.meldCount).type ==
          ShantenType.kokushi,
      closed = !hand.openMelds.any((m) => m.open),
      speedBest = [
        for (final c in candidates)
          if (c.rankByAxis[StrategyAxis.speed] == 1) c,
      ],
      pointsOrBalanceBest = {
        for (final c in candidates)
          if (c.rankByAxis[StrategyAxis.points] == 1 ||
              c.rankByAxis[StrategyAxis.balance] == 1)
            c.discardId,
      } {
    for (final b in blocks) {
      if (b.declared) continue;
      for (final id in b.tileIds) {
        final prev = blockOf[id];
        if (prev == null ||
            _cutOrder.indexOf(b.role) < _cutOrder.indexOf(prev.role)) {
          blockOf[id] = b;
        }
      }
    }
  }

  BlockRole? roleOf(int id) => blockOf[id]?.role;

  /// 手に 1 枚だけで、字牌か、同じ色の ±2 に他の牌が無い数牌。
  bool isFloating(int id) {
    final counts = hand.counts;
    if (counts[id] != 1) return false;
    if (id >= 27) return true;
    final pos = id % 9;
    for (var k = -2; k <= 2; k++) {
      final p = pos + k;
      if (k == 0 || p < 0 || p > 8) continue;
      if (counts[id + k] > 0) return false;
    }
    return true;
  }

  bool isYakuhai(int id) =>
      id >= 31 ||
      id == 27 + hand.seatWind.index ||
      id == 27 + hand.roundWind.index;

  // ---- 形（孤立・辺張・嵌張・浮き牌） -----------------------------------------

  List<Reason> shapeReasons(DiscardCandidate c) {
    if (kokushi || c.shantenAfter != bestShanten) return const [];
    final d = c.discardId;
    final result = <Reason>[];
    if (isFloating(d)) {
      if (d >= 27 && !isYakuhai(d)) {
        result.add(Reason(ReasonTag.isolatedHonor, tileIds: [d]));
      }
      if (d < 27 && (d % 9 == 0 || d % 9 == 8)) {
        result.add(Reason(ReasonTag.isolatedTerminal, tileIds: [d]));
      }
      final kept = <int>[];
      for (var f = 0; f < 27; f++) {
        if (f == d || !isFloating(f)) continue;
        // 2〜8 で、切る牌より真ん中寄りの浮き牌だけ
        final cf0 = tileCentrality(f);
        if (cf0 < 2 || cf0 <= tileCentrality(d)) continue;
        final cf = byId[f];
        if (cf == null) continue;
        // くっつきが今の受け入れに効いている（その浮き牌を切ると速さが落ちる）ときだけ。
        final better =
            c.shantenAfter < cf.shantenAfter ||
            (c.shantenAfter == cf.shantenAfter &&
                c.ukeire.total > cf.ukeire.total);
        if (better) kept.add(f);
      }
      if (kept.isNotEmpty) {
        result.add(Reason(ReasonTag.floatingMiddle, tileIds: kept));
      }
    }
    final block = blockOf[d];
    if (block != null && block.role == BlockRole.penchan) {
      final n = _advantageOver(
        c,
        (o) => roleOf(o.discardId) != BlockRole.penchan,
      );
      if (n != null && n > 0) {
        result.add(
          Reason(ReasonTag.penchanFix, count: n, tileIds: block.tileIds),
        );
      }
    }
    if (block != null && block.role == BlockRole.kanchan) {
      final n = _advantageOver(
        c,
        (o) => roleOf(o.discardId) == BlockRole.ryanmen,
      );
      if (n != null && n > 0) {
        result.add(
          Reason(ReasonTag.kanchanVsRyanmen, count: n, tileIds: block.tileIds),
        );
      }
    }
    return result;
  }

  /// 同じシャンテン数で [include] に当てはまる他の候補の受け入れの最大と比べて、
  /// [c] の受け入れが何枚多いか。比べる候補が無ければ null。
  int? _advantageOver(
    DiscardCandidate c,
    bool Function(DiscardCandidate other) include,
  ) {
    int? best;
    for (final o in candidates) {
      if (o.discardId == c.discardId || o.shantenAfter != c.shantenAfter) {
        continue;
      }
      if (!include(o)) continue;
      if (best == null || o.ukeire.total > best) best = o.ukeire.total;
    }
    return best == null ? null : c.ukeire.total - best;
  }

  // ---- ドラ -----------------------------------------------------------------

  Reason? keepDora(DiscardCandidate c) {
    final d = c.discardId;
    var lost = 0;
    for (final dora in hand.doraIds) {
      if (dora == d) lost++;
    }
    if (hand.counts[d] == 1 &&
        hand.redIds.contains(d) &&
        kRedFiveIds.contains(d)) {
      lost++;
    }
    if (lost == 0) return null;
    return Reason(ReasonTag.keepDora, count: lost, tileIds: [d]);
  }

  // ---- 役 -------------------------------------------------------------------

  static bool _countsAsYaku(YakuId y) =>
      !y.isYakuman && !y.isDora && y != YakuId.riichi;

  static Set<YakuId> _reachable(DiscardCandidate c) => {
    for (final p in c.yaku)
      if (p.confidence != YakuConfidence.lost && _countsAsYaku(p.yaku)) p.yaku,
  };

  /// 役を同じ方法（経路の列挙／二向聴以上の規則による目安）で調べた候補か。目安の
  /// 規則は平和・一盃口などを見ないので、方法の違う候補どうしの役は比べない。
  static bool _sameMethod(DiscardCandidate a, DiscardCandidate b) =>
      a.points.isEstimate == b.points.isEstimate;

  /// 役満が成立し得る候補か（役満の結果は役の一覧が役満だけになり、対々和・三暗刻など
  /// 含まれる役が載らないので、消える役の判定から外す）。
  static bool _hasYakuman(DiscardCandidate c) => c.yaku.any(
    (p) => p.confidence != YakuConfidence.lost && p.yaku.isYakuman,
  );

  Reason? yakuLoss(DiscardCandidate c) {
    if (_hasYakuman(c)) return null;
    final here = _reachable(c);
    final lost = <YakuId>{};
    for (final o in candidates) {
      if (o.discardId == c.discardId || !_sameMethod(o, c)) continue;
      for (final p in o.yaku) {
        if (!_countsAsYaku(p.yaku) || here.contains(p.yaku)) continue;
        if (p.confidence == YakuConfidence.certain ||
            p.confidence == YakuConfidence.likely) {
          lost.add(p.yaku);
        }
      }
    }
    if (lost.isEmpty) return null;
    return Reason(ReasonTag.yakuLoss, yaku: _sorted(lost));
  }

  Reason? yakuGain(DiscardCandidate c) {
    if (c.rankByAxis[StrategyAxis.speed] == 1) return null;
    if (!pointsOrBalanceBest.contains(c.discardId)) return null;
    if (c.shantenAfter > bestShanten + 1) return null;
    if (!speedBest.every((b) => _sameMethod(b, c))) return null;
    final gained = _reachable(c);
    for (final b in speedBest) {
      gained.removeAll(_reachable(b));
    }
    if (gained.isEmpty) return null;
    return Reason(ReasonTag.yakuGain, yaku: _sorted(gained));
  }

  Reason? riichiOnly(DiscardCandidate c) {
    if (!closed || c.shantenAfter != 0 || c.ukeire.total == 0) return null;
    // 役満も役（四暗刻単騎などはダマで和了できる）。
    if (_reachable(c).isNotEmpty || _hasYakuman(c)) return null;
    return Reason(ReasonTag.riichiOnlyYaku);
  }

  static List<YakuId> _sorted(Set<YakuId> ids) =>
      ids.toList()..sort((a, b) => a.index.compareTo(b.index));

  // ---- 七対子 ---------------------------------------------------------------

  Reason? sevenPairs(DiscardCandidate c) {
    if (hand.meldCount > 0 || kokushi) return null;
    final after = List<int>.of(hand.counts);
    after[c.discardId]--;
    final pairs = <int>[
      for (var i = 0; i < kTileKinds; i++)
        if (after[i] >= 2) i,
    ];
    if (pairs.length < 4) return null;
    if (sevenPairsShanten(after) > c.shantenAfter + 1) return null;
    return Reason(
      ReasonTag.sevenPairsRoute,
      count: pairs.length,
      tileIds: pairs,
    );
  }
}
