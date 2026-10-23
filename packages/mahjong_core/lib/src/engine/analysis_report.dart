import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/block.dart';
import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/thirteen_report.dart';
import 'package:mahjong_core/src/scoring/hand_analyzer.dart';

/// `NanikiruEngine.analyze` の結果（設計書 4.2）。
class AnalysisReport extends Equatable {
  /// 入力の手のシャンテン数（14 枚なら -1 が和了形）。
  final ShantenResult shanten;

  /// 14 枚のとき、各打牌の候補（速さ軸の順位 → 牌 id の順）。13 枚なら空。
  final List<DiscardCandidate> candidates;

  /// 軸ごとの 1 位の打牌（同順位はすべて、牌 id の昇順）。13 枚なら空。
  final Map<StrategyAxis, List<int>> bestByAxis;

  /// 13 枚のときのレポート。14 枚なら null。
  final ThirteenReport? thirteen;

  /// 14 枚が和了形のとき、ツモ和了の評価（和了牌は分からないので、手の中の牌の
  /// どれをツモったとしても最も高い解釈）。役が無ければ null。
  final HandScore? win;

  /// [win] で受け取る合計点数（現在の親子、本場なし）。
  final int? winPoints;

  /// Pro: ブロック分解（`decomposeBlocks`。14 枚なら打牌前の 14 枚、13 枚ならその
  /// 13 枚。副露は最後）。無料では空（仕様 5 章）。
  final List<Block> blocks;

  /// 解析エンジンの版（`kEngineVersion`）。
  final String engineVersion;

  /// Pro の詳しい解析か（deep=true）。
  final bool deep;

  AnalysisReport({
    required this.shanten,
    List<DiscardCandidate> candidates = const [],
    Map<StrategyAxis, List<int>> bestByAxis = const {},
    this.thirteen,
    this.win,
    this.winPoints,
    List<Block> blocks = const [],
    required this.engineVersion,
    required this.deep,
  }) : candidates = List.unmodifiable(candidates),
       bestByAxis = Map.unmodifiable({
         for (final e in bestByAxis.entries)
           e.key: List<int>.unmodifiable(e.value),
       }),
       blocks = List.unmodifiable(blocks);

  @override
  List<Object?> get props => [
    shanten,
    candidates,
    bestByAxis,
    thirteen,
    win?.han,
    win?.fu,
    winPoints,
    blocks,
    engineVersion,
    deep,
  ];
}
