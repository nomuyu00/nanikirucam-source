import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/points.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/ukeire.dart';
import 'package:mahjong_core/src/engine/win_evaluator.dart';
import 'package:mahjong_core/src/engine/yaku.dart';
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';
import 'package:mahjong_core/src/scoring/scoring_engine.dart';

/// 良形（設計書 4.6.1）: テンパイ形の待ちの残り枚数がこれ以上。
const int kGoodShapeMinWaits = 5;

/// 濃厚の閾値（仕様 4.3）: 重み付きで 7 割以上。
const int _likelyNumerator = 7;
const int _likelyDenominator = 10;

/// 一向聴で同じ評価の打牌が k 通りあるとき重みを k 等分する。割り切れるよう
/// 1..16 の最小公倍数を掛けておく（重みはすべて整数で持ち、比較を厳密にする）。
const int _tieScale = 720720;

/// 打牌後の 13 枚 1 つについての経路の集計（設計書 4.6.1・4.6.2）。
class RouteSummary {
  final int shanten;
  final Ukeire ukeire;

  /// 確定・濃厚・狙える（消えるは候補をまたいで決めるので含まない）。
  /// 確度 → [YakuId] の順。
  final List<YakuProspect> yaku;

  /// 1 経路でも成立する役（[yaku] の全部。消える役の判定に使う）。
  final Set<YakuId> reachable;

  /// ダマの想定打点（[PointRange] の説明を参照）。
  final PointRange points;

  /// 門前のとき、リーチ込みの想定打点。副露していれば null。
  final PointRange? riichiPoints;

  /// テンパイ形のうち待ちが [kGoodShapeMinWaits] 枚以上の重み付き割合。
  /// 二向聴以上（目安）では null。
  final double? goodShapeRate;

  /// 二向聴以上で、規則による目安か。
  final bool isEstimate;

  /// 打牌後の手（副露・赤を含む）にあるドラの枚数。
  final int doraHeld;

  /// 和了形まで評価した経路の数（重み 0 を除く。目安では 0）。
  final int routeCount;

  RouteSummary({
    required this.shanten,
    required this.ukeire,
    required List<YakuProspect> yaku,
    required Set<YakuId> reachable,
    required this.points,
    required this.riichiPoints,
    required this.goodShapeRate,
    required this.isEstimate,
    required this.doraHeld,
    required this.routeCount,
  }) : yaku = List.unmodifiable(yaku),
       reachable = Set.unmodifiable(reachable);

  /// 順位付けに使う中央値。門前はリーチ込み、副露はダマ（[riichiPoints] の説明）。
  int get rankingMedian => (riichiPoints ?? points).median;
}

/// 経路の列挙（テンパイ・一向聴）と規則による目安（二向聴以上）。
///
/// [context] は解析する手（副露・ドラ・赤・風・親子を使う）。[summarize] には
/// その手から 1 枚切った後の 13 枚（[HandState.discard] で切った牌を見えている牌に
/// 移したもの）を渡す。和了形の評価は 1 回の解析の中でメモする。
///
/// 経路と重み:
/// - テンパイ: 待ち w ごとに 1 経路、重み = w の残り枚数。
/// - 一向聴: 受け入れ a を引き、テンパイに取る打牌 d、待ち w。重み = a の残り × w の残り
///   （d を切って河に出し、a を手に入れた後の残り枚数）。a を引いた後のテンパイの
///   取り方は「Σ(待ちの残り × 評価値) が最大の打牌」を選ぶ（評価値はロン + ツモの点数、
///   門前はリーチ込み）。同じなら待ちの多い方、それも同じなら等分する。
///   選ばなかった取り方も「狙える役」と「成立させる牌」には数える。
/// - 各経路はロンとツモを 1 回ずつ（重みは同じ）数える。
///
/// フリテン（自分が切った牌での和了）と、引いた牌が赤5である可能性は考えない。
class RouteEnumerator {
  final HandState context;
  final WinEvaluator evaluator;
  final ScoringEngine _scoring;

  RouteEnumerator(this.context, {Ruleset? ruleset})
    : evaluator = WinEvaluator(context, ruleset: ruleset),
      _scoring = ScoringEngine(ruleset ?? Rulesets.mLeague());

  Ruleset get ruleset => evaluator.ruleset;

  RouteSummary summarize(HandState after) {
    if (after.tileCount != 13) {
      throw ArgumentError.value(after.tileCount, 'after', '13 枚（副露込み）の手ではない');
    }
    final sh = shanten(after).shanten;
    final uk = ukeire(after);
    final doraHeld = _doraHeld(after);
    if (sh >= 2) return _estimate(after, sh, uk, doraHeld);

    final counts = List<int>.of(after.counts);
    final visible = List<int>.of(after.visible);
    final red = <int>{
      for (final id in after.redIds)
        if (kRedFiveIds.contains(id) && counts[id] > 0) id,
    };
    final acc = _Accumulator(closed: evaluator.isClosed);
    if (sh == 0) {
      final waits = _waits(counts, visible);
      var total = 0;
      for (final (w, rw) in waits) {
        if (rw == 0) continue;
        total += rw;
        final ev = _evaluate(counts, w, red);
        acc.addOutcome(ev, rw);
        acc.addReachable(ev, w);
      }
      acc.addForm(1, total >= kGoodShapeMinWaits);
    } else {
      _oneShanten(counts, visible, red, uk, acc);
    }
    return acc.build(shanten: sh, ukeire: uk, doraHeld: doraHeld);
  }

  void _oneShanten(
    List<int> counts,
    List<int> visible,
    Set<int> red,
    Ukeire uk,
    _Accumulator acc,
  ) {
    final meldCount = context.meldCount;
    for (final MapEntry(key: a, value: ra) in uk.tiles.entries) {
      counts[a]++;
      final options = <_Option>[];
      for (var d = 0; d < kTileKinds; d++) {
        if (counts[d] == 0) continue;
        counts[d]--;
        if (shantenFromCounts(counts, meldCount: meldCount).shanten == 0) {
          visible[d]++;
          final red2 = counts[d] == 0 && red.contains(d)
              ? ({...red}..remove(d))
              : red;
          final option = _Option();
          for (final (w, rw) in _waits(counts, visible)) {
            if (rw == 0) continue;
            final ev = _evaluate(counts, w, red2);
            option.add(w, rw, ev);
            acc.addReachable(ev, a);
          }
          options.add(option);
          visible[d]--;
        }
        counts[d]++;
      }
      counts[a]--;
      if (options.isEmpty) continue;

      // テンパイの取り方を選ぶ（評価値 → 待ちの枚数 → 等分）。
      var best = <_Option>[];
      for (final o in options) {
        if (best.isEmpty) {
          best = [o];
          continue;
        }
        final c = _compareOption(o, best.first);
        if (c > 0) {
          best = [o];
        } else if (c == 0) {
          best.add(o);
        }
      }
      final share = ra * (_tieScale ~/ best.length);
      for (final o in best) {
        acc.addForm(share, o.waitTotal >= kGoodShapeMinWaits);
        for (final (_, rw, ev) in o.waits) {
          acc.addOutcome(ev, share * rw);
        }
      }
    }
  }

  static int _compareOption(_Option a, _Option b) {
    final v = a.value.compareTo(b.value);
    if (v != 0) return v;
    return a.waitTotal.compareTo(b.waitTotal);
  }

  WinEvaluation _evaluate(List<int> counts, int w, Set<int> red) {
    counts[w]++;
    final ev = evaluator.evaluate(counts, w, redHeld: red);
    counts[w]--;
    if (ev == null) {
      throw StateError('和了形にならない待ち ${_labelOf(w)}');
    }
    return ev;
  }

  /// テンパイの 13 枚（副露を除く [counts]）の和了牌と残り枚数（0 も含む）。
  List<(int, int)> _waits(List<int> counts, List<int> visible) {
    final meldCount = context.meldCount;
    final result = <(int, int)>[];
    final kokushi = meldCount == 0 && kokushiShanten(counts) == 0;
    for (var w = 0; w < kTileKinds; w++) {
      if (counts[w] >= 4) continue;
      if (!kokushi && !_touches(counts, w)) continue;
      counts[w]++;
      final s = shantenFromCounts(counts, meldCount: meldCount).shanten;
      counts[w]--;
      if (s != -1) continue;
      final r = 4 - counts[w] - context.meldTileCount(w) - visible[w];
      result.add((w, r < 0 ? 0 : r));
    }
    return result;
  }

  /// 一般形・七対子の和了牌は、手にある牌と同じか同じ色で 2 以内（字牌は同じ牌）。
  static bool _touches(List<int> counts, int w) {
    if (counts[w] > 0) return true;
    if (w >= 27) return false;
    final pos = w % 9;
    for (var d = -2; d <= 2; d++) {
      final p = pos + d;
      if (d == 0 || p < 0 || p > 8) continue;
      if (counts[w + d] > 0) return true;
    }
    return false;
  }

  int _doraHeld(HandState after) {
    var n = 0;
    for (final d in context.doraIds) {
      n += after.counts[d] + context.meldTileCount(d);
    }
    var red = 0;
    for (final id in after.redIds) {
      if (kRedFiveIds.contains(id) && after.counts[id] > 0) red++;
    }
    for (final meld in context.openMelds) {
      for (final t in meld.tiles) {
        if (t.red) red++;
      }
    }
    final cap = ruleset.redFives;
    return n + (red > cap ? cap : red);
  }

  // ---- 二向聴以上（設計書 4.6.2） -------------------------------------------

  RouteSummary _estimate(HandState after, int sh, Ukeire uk, int doraHeld) {
    final closed = evaluator.isClosed;
    final counts = after.counts;
    final melds = context.openMelds;
    final all = [
      for (var i = 0; i < kTileKinds; i++) counts[i] + context.meldTileCount(i),
    ];
    final draws = uk.tiles.keys.toList();
    final found = <YakuId, YakuProspect>{};
    void add(
      YakuId id,
      YakuConfidence confidence, [
      Iterable<int> enabling = const [],
    ]) {
      final previous = found[id];
      if (previous != null && previous.confidence.index <= confidence.index) {
        return;
      }
      found[id] = YakuProspect(
        yaku: id,
        confidence: confidence,
        enablingTiles: confidence == YakuConfidence.possible
            ? (enabling.toSet().toList()..sort())
            : const [],
        rate: confidence == YakuConfidence.certain ? 1 : 0,
        count: id == YakuId.dora ? doraHeld : null,
      );
    }

    bool meldHasYaochu(Meld m) => m.tiles.any((t) => t.isHonor || t.isTerminal);

    // 断么九: 么九牌を（向聴数 + 1）枚以内なら有効牌を引くたびに切り切れる。
    if (!melds.any(meldHasYaochu) && (closed || ruleset.kuitan)) {
      var yaochu = 0;
      for (var i = 0; i < kTileKinds; i++) {
        if (_isYaochu(i)) yaochu += counts[i];
      }
      if (yaochu <= sh + 1) {
        add(
          YakuId.tanyao,
          YakuConfidence.possible,
          draws.where((t) => !_isYaochu(t)),
        );
      }
    }

    // 役牌: 刻子（手の中・副露）は確定、対子は狙える（その牌）。
    for (final t in _yakuhaiTiles()) {
      final id = _yakuhaiId(t);
      final meldTriplet = melds.any(
        (m) =>
            (m.type == MeldType.koutsu || m.type == MeldType.kantsu) &&
            tileIdOf(m.tiles.first) == t,
      );
      if (meldTriplet || counts[t] >= 3) {
        add(id, YakuConfidence.certain);
      } else if (counts[t] == 2 && after.remaining(t) > 0) {
        add(id, YakuConfidence.possible, [t]);
      }
    }

    // 混一色・清一色: 同じ色が 9 枚以上（副露込み）で、他の色の副露が無い。
    var honors = 0;
    for (var i = 27; i < kTileKinds; i++) {
      honors += all[i];
    }
    for (var s = 0; s < 3; s++) {
      var suit = 0;
      for (var i = s * 9; i < s * 9 + 9; i++) {
        suit += all[i];
      }
      if (suit < 9) continue;
      final otherMeld = melds.any(
        (m) => m.tiles.any((t) => !t.isHonor && tileIdOf(t) ~/ 9 != s),
      );
      if (otherMeld) continue;
      add(
        YakuId.honitsu,
        YakuConfidence.possible,
        draws.where((t) => t >= 27 || t ~/ 9 == s),
      );
      final honorMeld = melds.any((m) => m.tiles.first.isHonor);
      if (suit >= 11 && !honorMeld) {
        add(
          YakuId.chinitsu,
          YakuConfidence.possible,
          draws.where((t) => t < 27 && t ~/ 9 == s),
        );
      }
    }

    // 七対子: 門前で対子 4 組以上。成立させる牌は対子になっていない牌。
    if (melds.isEmpty) {
      var pairs = 0;
      for (final c in counts) {
        if (c >= 2) pairs++;
      }
      if (pairs >= 4) {
        add(YakuId.chiitoitsu, YakuConfidence.possible, [
          for (var i = 0; i < kTileKinds; i++)
            if (counts[i] == 1 && after.remaining(i) > 0) i,
        ]);
      }
    }

    // 順子の材料（手牌 + チー）。
    final present = List<bool>.generate(kTileKinds, (i) => counts[i] > 0);
    for (final m in melds) {
      if (m.type != MeldType.shuntsu) continue;
      for (final t in m.tiles) {
        present[tileIdOf(t)] = true;
      }
    }

    // 三色同順: 同じ数の 3 枚組で、2 色以上が 2 枚以上そろい、3 色の合計が 6 枚以上。
    _bestRun(
      starts: [
        for (var n = 0; n <= 6; n++) [n, n + 9, n + 18],
      ],
      present: present,
      remaining: after.remaining,
      onFound: (missing) =>
          add(YakuId.sanshoku, YakuConfidence.possible, missing),
    );

    // 一気通貫: 同じ色の 123・456・789 で、2 段以上が 2 枚以上、合計 6 枚以上。
    _bestRun(
      starts: [
        for (var s = 0; s < 3; s++) [s * 9, s * 9 + 3, s * 9 + 6],
      ],
      present: present,
      remaining: after.remaining,
      onFound: (missing) => add(YakuId.ittsu, YakuConfidence.possible, missing),
    );

    // 対々和: チーが無く、対子以上（手牌）+ ポン・カンが 3 組以上。
    if (!melds.any((m) => m.type == MeldType.shuntsu)) {
      var sets = melds.length;
      for (final c in counts) {
        if (c >= 2) sets++;
      }
      if (sets >= 3) {
        add(YakuId.toitoi, YakuConfidence.possible, [
          for (var i = 0; i < kTileKinds; i++)
            if (counts[i] == 2 && after.remaining(i) > 0) i,
        ]);
      }
    }

    // 混全帯么九・純全帯么九: 副露が全部么九牌を含み、4〜6 の牌を（向聴数 + 1）枚以内で
    // 切り切れ、么九牌が 4 枚以上ある。字牌があれば混全帯、無ければ純全帯。
    if (melds.every(meldHasYaochu)) {
      var middle = 0;
      var yaochu = 0;
      for (var i = 0; i < kTileKinds; i++) {
        if (i < 27 && i % 9 >= 3 && i % 9 <= 5) middle += counts[i];
        if (_isYaochu(i)) yaochu += all[i];
      }
      if (middle <= sh + 1 && yaochu >= 4) {
        add(
          honors > 0 ? YakuId.chanta : YakuId.junchan,
          YakuConfidence.possible,
          draws.where((t) => t >= 27 || t % 9 <= 2 || t % 9 >= 6),
        );
      }
    }

    final yakuOnly = found.values.toList();
    if (closed) add(YakuId.riichi, YakuConfidence.certain);
    if (doraHeld > 0) add(YakuId.dora, YakuConfidence.certain);

    final points = _estimatePoints(yakuOnly, doraHeld, closed);
    final list = found.values.toList()..sort(compareProspects);
    return RouteSummary(
      shanten: sh,
      ukeire: uk,
      yaku: list,
      reachable: found.keys.toSet(),
      points: points.$1,
      riichiPoints: points.$2,
      goodShapeRate: null,
      isEstimate: true,
      doraHeld: doraHeld,
      routeCount: 0,
    );
  }

  /// 目安の打点（30 符のロン）。
  /// - 最小・中央値: 確定役の翻 + ドラ（ダマで確定役が無ければ 0＝役なしで和了できない
  ///   ことがある）。狙える役は中央値に入れない（二向聴以上の「狙える」は当てにしない。
  ///   入れると、戻す打牌が経路を列挙した候補より打点軸で上に来やすくなる）。
  /// - 最大: 確定役 + 狙える役（同時に付かない組は大きい方）+ ドラ。
  /// - リーチ込み（門前）: それぞれ 1 翻足す。
  (PointRange, PointRange?) _estimatePoints(
    List<YakuProspect> yaku,
    int dora,
    bool closed,
  ) {
    var certain = 0;
    final possible = <YakuId, int>{};
    for (final p in yaku) {
      final han = _estimateHan(p.yaku, closed);
      if (han == 0) continue;
      if (p.confidence == YakuConfidence.certain) {
        certain += han;
      } else {
        possible[p.yaku] = han;
      }
    }
    int groupMax(List<YakuId> ids) {
      var best = 0;
      for (final id in ids) {
        final h = possible.remove(id) ?? 0;
        if (h > best) best = h;
      }
      return best;
    }

    var sum = groupMax([YakuId.honitsu, YakuId.chinitsu]);
    sum += groupMax([YakuId.chanta, YakuId.junchan]);
    sum += groupMax([YakuId.chiitoitsu, YakuId.toitoi]);
    for (final h in possible.values) {
      sum += h;
    }

    int pts(int han) => han <= 0
        ? 0
        : ronPayment(
            _scoring.basePointsFor(han: han, fu: 30),
            dealer: context.dealer,
          );

    final low = certain > 0 ? pts(certain + dora) : 0;
    final dama = PointRange(
      min: low,
      median: low,
      max: certain + sum > 0 ? pts(certain + sum + dora) : 0,
      isEstimate: true,
    );
    final riichi = closed
        ? PointRange(
            min: pts(1 + certain + dora),
            median: pts(1 + certain + dora),
            max: pts(1 + certain + sum + dora),
            isEstimate: true,
          )
        : null;
    return (dama, riichi);
  }

  static int _estimateHan(YakuId id, bool closed) {
    switch (id) {
      case YakuId.tanyao:
      case YakuId.yakuhaiHaku:
      case YakuId.yakuhaiHatsu:
      case YakuId.yakuhaiChun:
      case YakuId.yakuhaiSeatWind:
      case YakuId.yakuhaiRoundWind:
        return 1;
      case YakuId.doubleWind:
      case YakuId.toitoi:
        return 2;
      case YakuId.chiitoitsu:
        return closed ? 2 : 0;
      case YakuId.sanshoku:
      case YakuId.ittsu:
      case YakuId.chanta:
        return closed ? 2 : 1;
      case YakuId.honitsu:
      case YakuId.junchan:
        return closed ? 3 : 2;
      case YakuId.chinitsu:
        return closed ? 6 : 5;
      default:
        return 0;
    }
  }

  /// 3 枚組 3 つ（[starts] の各要素が組の先頭 id の 3 つ）のうち、そろい具合が最もよいもの。
  void _bestRun({
    required List<List<int>> starts,
    required List<bool> present,
    required int Function(int) remaining,
    required void Function(List<int> missing) onFound,
  }) {
    List<int>? bestMissing;
    var bestHave = -1;
    for (final group in starts) {
      var have = 0;
      var withTwo = 0;
      var allTouched = true;
      final missing = <int>[];
      for (final start in group) {
        var n = 0;
        for (var k = 0; k < 3; k++) {
          if (present[start + k]) {
            n++;
          } else {
            missing.add(start + k);
          }
        }
        have += n;
        if (n >= 2) withTwo++;
        if (n == 0) allTouched = false;
      }
      if (have < 6 || withTwo < 2 || !allTouched) continue;
      if (missing.any((t) => remaining(t) == 0)) continue;
      if (have > bestHave) {
        bestHave = have;
        bestMissing = missing;
      }
    }
    if (bestMissing != null) onFound(bestMissing);
  }

  List<int> _yakuhaiTiles() {
    final seat = 27 + context.seatWind.index;
    final round = 27 + context.roundWind.index;
    return {31, 32, 33, seat, round}.toList()..sort();
  }

  YakuId _yakuhaiId(int t) {
    if (t == 31) return YakuId.yakuhaiHaku;
    if (t == 32) return YakuId.yakuhaiHatsu;
    if (t == 33) return YakuId.yakuhaiChun;
    final seat = 27 + context.seatWind.index;
    final round = 27 + context.roundWind.index;
    if (t == seat && t == round) return YakuId.doubleWind;
    return t == seat ? YakuId.yakuhaiSeatWind : YakuId.yakuhaiRoundWind;
  }
}

/// 確度 → [YakuId] の順（表示順）。
int compareProspects(YakuProspect a, YakuProspect b) {
  final c = a.confidence.index.compareTo(b.confidence.index);
  if (c != 0) return c;
  return a.yaku.index.compareTo(b.yaku.index);
}

bool _isYaochu(int id) => id >= 27 || id % 9 == 0 || id % 9 == 8;

String _labelOf(int id) => '${id % 9 + 1}${'mpsz'[id ~/ 9]}';

/// 一向聴で受け入れを引いた後のテンパイの取り方 1 つ。
class _Option {
  final waits = <(int, int, WinEvaluation)>[];
  int waitTotal = 0;
  int value = 0;

  void add(int w, int rw, WinEvaluation ev) {
    waits.add((w, rw, ev));
    waitTotal += rw;
    value += rw * ev.rankingValue;
  }
}

class _Accumulator {
  final bool closed;
  final List<(int, int)> dama = [];
  final List<(int, int)> riichi = [];
  final Map<YakuId, int> yakuWeight = {};
  int total = 0;

  /// 役満になった結果（ロン・ツモそれぞれ）の重みの合計。
  int yakumanWeight = 0;
  int formTotal = 0;
  int formGood = 0;
  int routes = 0;
  final Map<YakuId, Set<int>> enabling = {};

  _Accumulator({required this.closed});

  /// 経路 1 つ（重み [w]）。ロンとツモを同じ重みで 1 回ずつ数える。
  void addOutcome(WinEvaluation ev, int w) {
    if (w <= 0) return;
    routes++;
    dama
      ..add((ev.ronPoints, w))
      ..add((ev.tsumoPoints, w));
    if (closed) {
      riichi
        ..add((ev.ronRiichiPoints!, w))
        ..add((ev.tsumoRiichiPoints!, w));
    }
    total += 2 * w;
    for (final set in [ev.ronYaku, ev.tsumoYaku]) {
      if (set.any((y) => y.isYakuman)) yakumanWeight += w;
      for (final y in set) {
        yakuWeight[y] = (yakuWeight[y] ?? 0) + w;
      }
    }
  }

  /// 経路の有無だけを見る（選ばなかったテンパイの取り方も含む）。
  void addReachable(WinEvaluation ev, int enablingTile) {
    for (final y in ev.ronYaku.followedBy(ev.tsumoYaku)) {
      (enabling[y] ??= <int>{}).add(enablingTile);
    }
  }

  void addForm(int weight, bool good) {
    formTotal += weight;
    if (good) formGood += weight;
  }

  RouteSummary build({
    required int shanten,
    required Ukeire ukeire,
    required int doraHeld,
  }) {
    final list = <YakuProspect>[];
    for (final y in enabling.keys) {
      final w = yakuWeight[y] ?? 0;
      // 役満の結果は役の一覧が役満だけになる（HandAnalyzer が他の役を落とす）ので、
      // 役満でない役の割合は役満の結果を除いて数える。
      final denominator = y.isYakuman ? total : total - yakumanWeight;
      var confidence = YakuConfidence.possible;
      if (denominator > 0 && w == denominator) {
        confidence = YakuConfidence.certain;
      } else if (denominator > 0 &&
          w * _likelyDenominator >= denominator * _likelyNumerator) {
        confidence = YakuConfidence.likely;
      }
      // 役満は「狙える」のみ（仕様 4.3）。
      if (y.isYakuman) confidence = YakuConfidence.possible;
      list.add(
        YakuProspect(
          yaku: y,
          confidence: confidence,
          enablingTiles: confidence == YakuConfidence.possible
              ? (enabling[y]!.toList()..sort())
              : const [],
          rate: denominator <= 0 ? 0 : w / denominator,
          count: y == YakuId.dora ? doraHeld : null,
        ),
      );
    }
    final reachable = enabling.keys.toSet();
    if (closed && total > 0) {
      list.add(
        YakuProspect(
          yaku: YakuId.riichi,
          confidence: YakuConfidence.certain,
          rate: 1,
        ),
      );
      reachable.add(YakuId.riichi);
    }
    list.sort(compareProspects);
    return RouteSummary(
      shanten: shanten,
      ukeire: ukeire,
      yaku: list,
      reachable: reachable,
      points: PointRange.fromWeighted(dama),
      riichiPoints: closed ? PointRange.fromWeighted(riichi) : null,
      goodShapeRate: formTotal == 0 ? 0 : formGood / formTotal,
      isEstimate: false,
      doraHeld: doraHeld,
      routeCount: routes,
    );
  }
}
