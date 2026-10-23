import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/riichi_advice.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/ukeire.dart';
import 'package:mahjong_core/src/engine/win_ease.dart';
import 'package:mahjong_core/src/engine/win_evaluator.dart';
import 'package:mahjong_core/src/scoring/hand_analyzer.dart';

/// 13 枚テンパイの待ち 1 つ（設計書 4.2）。
class WaitInfo extends Equatable {
  final int tileId;

  /// 残り枚数（見えている牌・自分の手と副露を除く）。0 なら空テン。
  final int remaining;

  /// ダマのロン。役が無ければ null（門前の役なし・副露の役なし）。
  final HandScore? ronScore;

  /// ツモ。役が無ければ null（副露の役なし。門前ならツモが役になる）。
  final HandScore? tsumoScore;

  /// [ronScore] で受け取る点数（現在の親子、本場なし）。役なしは null。
  final int? ronPoints;

  /// [tsumoScore] で受け取る合計点数。役なしは null。
  final int? tsumoPoints;

  /// 門前のとき、リーチ込み（一発・裏ドラなし）のロンで受け取る点数（役なしの待ちも
  /// リーチで和了できる）。副露していれば null。仕様 4.5「リーチした場合の想定打点」。
  final int? ronRiichiPoints;

  /// 門前のとき、リーチ込みのツモで受け取る合計点数。副露していれば null。
  final int? tsumoRiichiPoints;

  const WaitInfo({
    required this.tileId,
    required this.remaining,
    required this.ronScore,
    required this.tsumoScore,
    this.ronPoints,
    this.tsumoPoints,
    this.ronRiichiPoints,
    this.tsumoRiichiPoints,
  });

  // HandScore は Equatable でないので翻・符で比べる。
  @override
  List<Object?> get props => [
    tileId,
    remaining,
    ronPoints,
    tsumoPoints,
    ronRiichiPoints,
    tsumoRiichiPoints,
    ronScore?.han,
    ronScore?.fu,
    tsumoScore?.han,
    tsumoScore?.fu,
  ];

  @override
  String toString() =>
      'WaitInfo($tileId 残り$remaining ロン$ronPoints ツモ$tsumoPoints)';
}

/// 13 枚のときのレポート（設計書 4.6.5）。
class ThirteenReport extends Equatable {
  final ShantenResult shanten;

  /// 受け入れ（設計書 4.4）。
  final Ukeire draws;

  /// テンパイのときの待ち（牌 id の昇順。残り 0 枚の待ちも含む）。テンパイでなければ空。
  final List<WaitInfo> waits;

  /// テンパイで、ダマのロンで和了できる待ちが 1 つでもあるか（役なしテンパイの判定）。
  /// テンパイでなければ false。
  final bool hasYaku;

  /// 門前（暗槓は可）でテンパイ。
  final bool riichiPossible;

  /// Pro のリーチ判断（[riichiPossible] のときだけ。無料では null）。
  final RiichiAdvice? riichi;

  ThirteenReport({
    required this.shanten,
    required this.draws,
    required List<WaitInfo> waits,
    required this.hasYaku,
    required this.riichiPossible,
    this.riichi,
  }) : waits = List.unmodifiable(waits);

  @override
  List<Object?> get props => [
    shanten,
    draws,
    waits,
    hasYaku,
    riichiPossible,
    riichi,
  ];
}

/// 13 枚（副露込み）の手のレポート。[evaluator] は同じ手の文脈で作ったもの（メモを共有
/// するために渡せる）。
///
/// [riichiAdvice] が true（Pro）で門前テンパイなら [ThirteenReport.riichi] を付ける。
/// 上がりやすさは [winEaseOf]（既定は表の `winEase`）に、待ちの残り枚数の合計と
/// [HandState.turn] を渡して求める。
ThirteenReport buildThirteenReport(
  HandState hand, {
  WinEvaluator? evaluator,
  bool riichiAdvice = false,
  WinEaseFunction winEaseOf = winEase,
}) {
  if (hand.tileCount != 13) {
    throw ArgumentError.value(hand.tileCount, 'hand', '13 枚（副露込み）の手ではない');
  }
  final eval = evaluator ?? WinEvaluator(hand);
  final sh = shanten(hand);
  final draws = ukeire(hand);
  final waits = <WaitInfo>[];
  if (sh.shanten == 0) {
    final counts = List<int>.of(hand.counts);
    final red = <int>{
      for (final id in hand.redIds)
        if (counts[id] > 0) id,
    };
    for (var w = 0; w < kTileKinds; w++) {
      if (counts[w] >= 4) continue;
      counts[w]++;
      final complete =
          shantenFromCounts(counts, meldCount: hand.meldCount).shanten == -1;
      final ev = complete ? eval.evaluate(counts, w, redHeld: red) : null;
      counts[w]--;
      if (ev == null) continue;
      waits.add(
        WaitInfo(
          tileId: w,
          remaining: hand.remaining(w),
          ronScore: ev.ron,
          tsumoScore: ev.tsumo,
          ronPoints: ev.ron == null ? null : ev.ronPoints,
          tsumoPoints: ev.tsumo == null ? null : ev.tsumoPoints,
          ronRiichiPoints: ev.ronRiichiPoints,
          tsumoRiichiPoints: ev.tsumoRiichiPoints,
        ),
      );
    }
  }
  final tenpai = sh.shanten == 0;
  final riichiPossible = tenpai && eval.isClosed;
  RiichiAdvice? riichi;
  if (riichiAdvice && riichiPossible) {
    var live = 0;
    for (final w in waits) {
      live += w.remaining;
    }
    riichi = adviseRiichi(
      [
        for (final w in waits)
          (
            remaining: w.remaining,
            ronPoints: w.ronPoints ?? 0,
            tsumoPoints: w.tsumoPoints ?? 0,
            ronRiichiPoints: w.ronRiichiPoints ?? 0,
            tsumoRiichiPoints: w.tsumoRiichiPoints ?? 0,
            ronHasYaku: w.ronScore != null,
          ),
      ],
      winEase: winEaseOf(
        shanten: 0,
        ukeireTotal: live,
        turn: hand.turn,
        type: sh.type,
      ),
    );
  }
  return ThirteenReport(
    shanten: sh,
    draws: draws,
    waits: waits,
    hasYaku: tenpai && waits.any((w) => w.ronScore != null),
    riichiPossible: riichiPossible,
    riichi: riichi,
  );
}
