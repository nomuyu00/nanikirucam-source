import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/block.dart';
import 'package:mahjong_core/src/engine/blocks.dart';
import 'package:mahjong_core/src/engine/explain.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/points.dart';
import 'package:mahjong_core/src/engine/reason_tag.dart';
import 'package:mahjong_core/src/engine/riichi_advice.dart';
import 'package:mahjong_core/src/engine/route_enumerator.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/thirteen_report.dart';
import 'package:mahjong_core/src/engine/two_step.dart';
import 'package:mahjong_core/src/engine/ukeire.dart';
import 'package:mahjong_core/src/engine/win_ease.dart';
import 'package:mahjong_core/src/engine/yaku.dart';

/// 上がりやすさの関数（[winEase] と同じ形）。
typedef WinEaseFunction =
    double Function({
      required int shanten,
      required int ukeireTotal,
      int? turn,
      ShantenType type,
    });

/// 打牌候補を並べる軸（仕様 7.3、設計書 4.6.4）。
enum StrategyAxis { speed, points, balance }

/// 14 枚の手から 1 枚切ったときの候補（設計書 4.2）。
class DiscardCandidate extends Equatable {
  final int discardId;
  final int shantenAfter;
  final Ukeire ukeire;

  /// 役の見込み（確度 → 役の順）。消える役も含む。UI が最大 3 件を選ぶ。
  /// 無料（deep=false）では消える役と成立させる牌を省く。
  final List<YakuProspect> yaku;

  /// ダマの想定打点（[PointRange] の説明を参照）。
  final PointRange points;

  /// 門前のとき、リーチ込みの想定打点（仕様 4.4「リーチ込みと別表示」）。副露なら null。
  final PointRange? riichiPoints;

  /// 上がりやすさ 0..1（`winEase` の表）。
  final double winEase;

  /// Pro: テンパイ形のうち待ちが 5 枚以上の重み付き割合。二向聴以上と無料では null。
  final double? goodShapeRate;

  /// Pro: 2 段階先（受け入れを引いた後の受け入れと、改良の牌。`two_step.dart`）。
  /// 無料と [rankDiscards] では null。
  final TwoStep? twoStep;

  /// 理由タグ（`explain.dart`）。タグの宣言順。[rankDiscards] では空。
  final List<Reason> reasons;

  /// Pro: 門前で打牌後テンパイのときのリーチ判断（`riichi_advice.dart`）。
  /// それ以外と無料では null。
  final RiichiAdvice? riichi;

  /// 軸ごとの順位（1 が最良、同値は同順位で 1,1,3…）。打点軸で除外された候補
  /// （シャンテン数が最良より 2 以上悪い）には [StrategyAxis.points] が無い。
  final Map<StrategyAxis, int> rankByAxis;

  DiscardCandidate({
    required this.discardId,
    required this.shantenAfter,
    required this.ukeire,
    List<YakuProspect> yaku = const [],
    this.points = PointRange.zero,
    this.riichiPoints,
    this.winEase = 0,
    this.goodShapeRate,
    this.twoStep,
    List<Reason> reasons = const [],
    this.riichi,
    required Map<StrategyAxis, int> rankByAxis,
  }) : yaku = List.unmodifiable(yaku),
       reasons = List.unmodifiable(reasons),
       rankByAxis = Map.unmodifiable(rankByAxis);

  /// 順位付けに使う想定打点の中央値。門前はリーチ込み、副露はダマ。
  int get rankingMedian => (riichiPoints ?? points).median;

  /// Pro: 2 段階先の受け入れ平均（[TwoStep.average]）。テンパイの候補と無料では null。
  double? get twoStepAverage => twoStep?.average;

  /// 理由タグだけ（[reasons] のタグ）。
  List<ReasonTag> get reasonTags => [for (final r in reasons) r.tag];

  @override
  List<Object?> get props => [
    discardId,
    shantenAfter,
    ukeire,
    yaku,
    points,
    riichiPoints,
    winEase,
    goodShapeRate,
    twoStep,
    reasons,
    riichi,
    rankByAxis,
  ];

  @override
  String toString() =>
      'DiscardCandidate(打$discardId, $shantenAfter向聴, $ukeire, $rankByAxis)';
}

/// 14 枚（副露込みで 3n+2 枚）の手について、重複を除いた各牌を 1 枚切った候補を返す。
///
/// 受け入れだけで並べる軽い版（役・打点は計算しない。[DiscardCandidate.points] は
/// [PointRange.zero]）。全部の軸は [analyzeDiscards]。
///
/// 速さ軸: シャンテン数の昇順 → 受け入れ枚数の降順。同値は同順位。
/// 切った牌は河に出るので、受け入れの残り枚数からも除く（[HandState.discard]）。
/// 返す順は速さ軸の順位、同順位は牌 id の昇順。
List<DiscardCandidate> rankDiscards(HandState hand) {
  _check14(hand);
  final raw = <({int id, int shanten, Ukeire ukeire})>[];
  final types = <int, ShantenType>{};
  for (var id = 0; id < kTileKinds; id++) {
    if (hand.counts[id] == 0) continue;
    final after = hand.discard(id);
    final sh = shanten(after);
    types[id] = sh.type;
    raw.add((id: id, shanten: sh.shanten, ukeire: ukeire(after)));
  }
  int compareSpeed(
    ({int id, int shanten, Ukeire ukeire}) a,
    ({int id, int shanten, Ukeire ukeire}) b,
  ) {
    final s = a.shanten.compareTo(b.shanten);
    if (s != 0) return s;
    return b.ukeire.total.compareTo(a.ukeire.total);
  }

  raw.sort((a, b) {
    final c = compareSpeed(a, b);
    return c != 0 ? c : a.id.compareTo(b.id);
  });

  final result = <DiscardCandidate>[];
  var rank = 0;
  for (var i = 0; i < raw.length; i++) {
    if (i == 0 || compareSpeed(raw[i - 1], raw[i]) != 0) rank = i + 1;
    final e = raw[i];
    result.add(
      DiscardCandidate(
        discardId: e.id,
        shantenAfter: e.shanten,
        ukeire: e.ukeire,
        winEase: winEase(
          shanten: e.shanten,
          ukeireTotal: e.ukeire.total,
          turn: hand.turn,
          type: types[e.id]!,
        ),
        rankByAxis: {StrategyAxis.speed: rank},
      ),
    );
  }
  return result;
}

/// 14 枚の手の全候補を、役の見込み・想定打点・上がりやすさ・良形率付きで返す
/// （設計書 4.6）。返す順は速さ軸の順位、同順位は牌 id の昇順。
///
/// 3 軸の順位（設計書 4.6.4、同値は同順位）:
/// - 速さ: シャンテン数 ↑ → 受け入れ枚数 ↓ → 良形率 ↓ → 想定打点の中央値 ↓
/// - 打点: シャンテン数が最良 + 1 までの候補で、中央値 ↓ → シャンテン数 ↑ →
///   受け入れ枚数 ↓
/// - バランス: 上がりやすさ × 中央値 ↓ → シャンテン数 ↑ → 受け入れ枚数 ↓
///
/// 打点・バランスで受け入れ枚数を比べる前にシャンテン数を見る（シャンテン数の違う
/// 手の受け入れ枚数は比べられないため。設計書 4.6.4 からの追加）。
///
/// 中央値は [DiscardCandidate.rankingMedian]（門前はリーチ込み）。順位は [deep] に
/// よらず同じ（2 段階先・理由タグは順位に使わない）。[winEaseOf] は上がりやすさの
/// 関数（既定は表の [winEase]。テストで差し替える）。
///
/// 理由タグ（[DiscardCandidate.reasons]）は無料・Pro の両方に付ける。[blocks] は
/// [hand] の `decomposeBlocks`（渡さなければここで作る）。
///
/// [deep] が false（無料）のときは出力から消える役・成立させる牌・良形率・2 段階先・
/// リーチ判断・理由タグの [ReasonTag.yakuLoss]（消える役）を省く（仕様 5 章）。
List<DiscardCandidate> analyzeDiscards(
  HandState hand, {
  RouteEnumerator? enumerator,
  bool deep = true,
  WinEaseFunction winEaseOf = winEase,
  List<Block>? blocks,
}) {
  _check14(hand);
  final routes = enumerator ?? RouteEnumerator(hand);
  final entries = <_Entry>[];
  for (var id = 0; id < kTileKinds; id++) {
    if (hand.counts[id] == 0) continue;
    final after = afterDiscard(hand, id);
    final summary = routes.summarize(after);
    entries.add(
      _Entry(
        id,
        summary,
        winEaseOf(
          shanten: summary.shanten,
          ukeireTotal: summary.ukeire.total,
          turn: hand.turn,
          // 七対子・国士の形は和了率が一般形と大きく違うので表を分ける。
          type: shanten(after).type,
        ),
      ),
    );
  }

  // 消える役: 同じ方法（経路／目安）で調べた候補のどれかで成立するのに、この候補では無い。
  final before = <bool, Set<YakuId>>{true: {}, false: {}};
  for (final e in entries) {
    before[e.summary.isEstimate]!.addAll(e.summary.reachable);
  }

  final speed = _rank(entries, (a, b) {
    var c = a.summary.shanten.compareTo(b.summary.shanten);
    if (c != 0) return c;
    c = b.summary.ukeire.total.compareTo(a.summary.ukeire.total);
    if (c != 0) return c;
    c = (b.summary.goodShapeRate ?? -1).compareTo(
      a.summary.goodShapeRate ?? -1,
    );
    if (c != 0) return c;
    return b.summary.rankingMedian.compareTo(a.summary.rankingMedian);
  });
  var bestShanten = 99;
  for (final e in entries) {
    if (e.summary.shanten < bestShanten) bestShanten = e.summary.shanten;
  }
  final points = _rank(
    [
      for (final e in entries)
        if (e.summary.shanten <= bestShanten + 1) e,
    ],
    (a, b) {
      var c = b.summary.rankingMedian.compareTo(a.summary.rankingMedian);
      if (c != 0) return c;
      c = a.summary.shanten.compareTo(b.summary.shanten);
      if (c != 0) return c;
      return b.summary.ukeire.total.compareTo(a.summary.ukeire.total);
    },
  );
  final balance = _rank(entries, (a, b) {
    var c = b.balanceValue.compareTo(a.balanceValue);
    if (c != 0) return c;
    c = a.summary.shanten.compareTo(b.summary.shanten);
    if (c != 0) return c;
    return b.summary.ukeire.total.compareTo(a.summary.ukeire.total);
  });

  final result = <DiscardCandidate>[];
  for (final e in entries) {
    final s = e.summary;
    final yaku = [
      for (final p in s.yaku)
        if (deep || p.enablingTiles.isEmpty)
          p
        else
          YakuProspect(
            yaku: p.yaku,
            confidence: p.confidence,
            rate: p.rate,
            count: p.count,
          ),
    ];
    if (deep) {
      for (final y in before[s.isEstimate]!.difference(s.reachable)) {
        if (y.isYakuman || y == YakuId.riichi) continue;
        yaku.add(
          YakuProspect(
            yaku: y,
            confidence: YakuConfidence.lost,
            count: y == YakuId.dora ? s.doraHeld : null,
          ),
        );
      }
    }
    yaku.sort(compareProspects);
    result.add(
      DiscardCandidate(
        discardId: e.id,
        shantenAfter: s.shanten,
        ukeire: s.ukeire,
        yaku: yaku,
        points: s.points,
        riichiPoints: s.riichiPoints,
        winEase: e.winEase,
        goodShapeRate: deep ? s.goodShapeRate : null,
        rankByAxis: {
          StrategyAxis.speed: speed[e.id]!,
          if (points.containsKey(e.id)) StrategyAxis.points: points[e.id]!,
          StrategyAxis.balance: balance[e.id]!,
        },
      ),
    );
  }
  result.sort((a, b) {
    final c = a.rankByAxis[StrategyAxis.speed]!.compareTo(
      b.rankByAxis[StrategyAxis.speed]!,
    );
    return c != 0 ? c : a.discardId.compareTo(b.discardId);
  });

  final reasons = explainCandidates(
    hand,
    result,
    blocks: blocks ?? decomposeBlocks(hand),
    deep: deep,
  );
  final twoStep = deep ? TwoStepCalculator(hand) : null;
  final closed = routes.evaluator.isClosed;
  return [
    for (final c in result)
      DiscardCandidate(
        discardId: c.discardId,
        shantenAfter: c.shantenAfter,
        ukeire: c.ukeire,
        yaku: c.yaku,
        points: c.points,
        riichiPoints: c.riichiPoints,
        winEase: c.winEase,
        goodShapeRate: c.goodShapeRate,
        twoStep: twoStep?.of(c.discardId),
        reasons: reasons[c.discardId] ?? const [],
        riichi: deep && closed && c.shantenAfter == 0
            ? buildThirteenReport(
                afterDiscard(hand, c.discardId),
                evaluator: routes.evaluator,
                riichiAdvice: true,
                winEaseOf: winEaseOf,
              ).riichi
            : null,
        rankByAxis: c.rankByAxis,
      ),
  ];
}

/// 軸ごとの 1 位（同順位はすべて、牌 id の昇順）。
Map<StrategyAxis, List<int>> bestByAxisOf(List<DiscardCandidate> candidates) {
  return {
    for (final axis in StrategyAxis.values)
      axis: [
        for (final c in candidates)
          if (c.rankByAxis[axis] == 1) c.discardId,
      ]..sort(),
  };
}

/// [id] を 1 枚切った後の 13 枚。切った牌は見えている牌に移し、最後の 1 枚の
/// 赤5を切ったなら [HandState.redIds] からも外す（同じ牌が 2 枚以上あれば赤でない方を
/// 切ったとみなす）。
HandState afterDiscard(HandState hand, int id) {
  final after = hand.discard(id);
  if (after.counts[id] == 0 && after.redIds.contains(id)) {
    return after.copyWith(redIds: {...after.redIds}..remove(id));
  }
  return after;
}

void _check14(HandState hand) {
  if (hand.tileCount != 14) {
    throw ArgumentError.value(hand.tileCount, 'hand', '14 枚（副露込み）の手ではない');
  }
}

class _Entry {
  final int id;
  final RouteSummary summary;
  final double winEase;
  _Entry(this.id, this.summary, this.winEase);

  double get balanceValue => winEase * summary.rankingMedian;
}

/// [compare] が負なら a が上。同値は同順位（1,1,3…）。牌 id → 順位。
Map<int, int> _rank(
  List<_Entry> entries,
  int Function(_Entry a, _Entry b) compare,
) {
  final sorted = List<_Entry>.of(entries)
    ..sort((a, b) {
      final c = compare(a, b);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final result = <int, int>{};
  var rank = 0;
  for (var i = 0; i < sorted.length; i++) {
    if (i == 0 || compare(sorted[i - 1], sorted[i]) != 0) rank = i + 1;
    result[sorted[i].id] = rank;
  }
  return result;
}
