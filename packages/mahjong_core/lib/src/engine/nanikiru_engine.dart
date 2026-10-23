import 'dart:collection';

import 'package:mahjong_core/src/engine/analysis_report.dart';
import 'package:mahjong_core/src/engine/blocks.dart';
import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/engine_version.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/route_enumerator.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/thirteen_report.dart';
import 'package:mahjong_core/src/engine/win_ease.dart';
import 'package:mahjong_core/src/engine/win_evaluator.dart';
import 'package:mahjong_core/src/scoring/hand_analyzer.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';

/// 何切る解析エンジンの窓口（設計書 4.2）。
abstract class NanikiruEngine {
  /// 総合のシャンテン数（一般形・七対子・国士の最小と種類）。
  ShantenResult shanten(HandState hand);

  /// 13 枚または 14 枚（副露込み）の手を解析する。[deep] は Pro の詳しい解析。
  AnalysisReport analyze(HandState hand, {required bool deep});
}

/// 既定の実装。同じ入力の結果を LRU（既定 50 件、設計書 4.8）で持つ。
///
/// 無料（deep=false）と Pro（deep=true）で 3 軸の順位・おすすめは同じ（どちらも経路を
/// すべて列挙する。順位に使う中央値・良形率を同じにするため）。無料は出力から
/// 次を省く（仕様 5 章）:
/// - 候補: 消える役・成立させる牌・良形率・2 段階先・リーチ判断・理由タグの
///   消える役（`ReasonTag.yakuLoss`）
/// - レポート: ブロック分解（[AnalysisReport.blocks] は空）
/// - 13 枚: リーチ判断（[ThirteenReport.riichi] は null。リーチ込みの点数は
///   [WaitInfo] にあるので「リーチした場合・しない場合の想定打点」は無料でも出せる）
///
/// UI からは Isolate で呼ぶ想定（設計書 4.8）。キャッシュは Isolate ごとなので、
/// 使い回すなら長生きの Isolate に置く。
class DefaultNanikiruEngine implements NanikiruEngine {
  final Ruleset ruleset;
  final int cacheSize;

  /// 上がりやすさの関数（既定は表の `winEase`。テストで差し替える）。
  final WinEaseFunction winEaseOf;
  final LinkedHashMap<String, AnalysisReport> _cache =
      LinkedHashMap<String, AnalysisReport>();

  DefaultNanikiruEngine({
    Ruleset? ruleset,
    this.cacheSize = 50,
    this.winEaseOf = winEase,
  }) : ruleset = ruleset ?? Rulesets.mLeague();

  /// いまキャッシュにある件数（テスト用）。
  int get cachedCount => _cache.length;

  @override
  ShantenResult shanten(HandState hand) =>
      shantenFromCounts(hand.counts, meldCount: hand.meldCount);

  @override
  AnalysisReport analyze(HandState hand, {required bool deep}) {
    final key = '${deep ? 'P' : 'F'}${analysisCacheKey(hand)}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final report = _analyze(hand, deep);
    _cache[key] = report;
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    return report;
  }

  AnalysisReport _analyze(HandState hand, bool deep) {
    final count = hand.tileCount;
    final sh = shanten(hand);
    if (count == 13) {
      return AnalysisReport(
        shanten: sh,
        thirteen: buildThirteenReport(
          hand,
          evaluator: WinEvaluator(hand, ruleset: ruleset),
          riichiAdvice: deep,
          winEaseOf: winEaseOf,
        ),
        blocks: deep ? decomposeBlocks(hand) : const [],
        engineVersion: kEngineVersion,
        deep: deep,
      );
    }
    if (count != 14) {
      throw ArgumentError.value(count, 'hand', '13 枚か 14 枚（副露込み）の手ではない');
    }
    final routes = RouteEnumerator(hand, ruleset: ruleset);
    // 理由タグに使うので無料でも分解する（レポートに載せるのは Pro だけ）。
    final blocks = decomposeBlocks(hand);
    final candidates = analyzeDiscards(
      hand,
      enumerator: routes,
      deep: deep,
      winEaseOf: winEaseOf,
      blocks: blocks,
    );
    HandScore? win;
    int? winPoints;
    if (sh.shanten == -1) {
      final best = _bestTsumo(hand, routes.evaluator);
      win = best?.$1;
      winPoints = best?.$2;
    }
    return AnalysisReport(
      shanten: sh,
      candidates: candidates,
      bestByAxis: bestByAxisOf(candidates),
      win: win,
      winPoints: winPoints,
      blocks: deep ? blocks : const [],
      engineVersion: kEngineVersion,
      deep: deep,
    );
  }

  /// 和了形の 14 枚を、手の中のどの牌をツモったとしても最も高い解釈で評価する。
  (HandScore, int)? _bestTsumo(HandState hand, WinEvaluator evaluator) {
    final red = <int>{
      for (final id in hand.redIds)
        if (hand.counts[id] > 0) id,
    };
    (HandScore, int)? best;
    for (var t = 0; t < kTileKinds; t++) {
      if (hand.counts[t] == 0) continue;
      final ev = evaluator.evaluate(hand.counts, t, redHeld: red);
      final score = ev?.tsumo;
      if (ev == null || score == null) continue;
      if (best == null ||
          ev.tsumoPoints > best.$2 ||
          (ev.tsumoPoints == best.$2 && score.han > best.$1.han)) {
        best = (score, ev.tsumoPoints);
      }
    }
    return best;
  }
}

/// LRU のキー（counts + visible + 副露 + ドラ・赤・風・親子・巡目）。
String analysisCacheKey(HandState hand) {
  final b = StringBuffer()
    ..writeAll(hand.counts)
    ..write('|')
    ..writeAll(hand.visible, ',')
    ..write('|');
  for (final m in hand.openMelds) {
    b
      ..write(m.type.index)
      ..write(m.open ? 'o' : 'c');
    for (final t in m.tiles) {
      b
        ..write(tileIdOf(t))
        ..write(t.red ? 'r' : '')
        ..write(',');
    }
    b.write(';');
  }
  b
    ..write('|')
    ..writeAll(List<int>.of(hand.doraIds)..sort(), ',')
    ..write('|')
    ..writeAll(hand.redIds.toList()..sort(), ',')
    ..write('|${hand.seatWind.index}${hand.roundWind.index}')
    ..write(hand.dealer ? 'd' : 'n')
    ..write('|${hand.turn ?? '-'}');
  return b.toString();
}
