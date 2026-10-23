import 'package:equatable/equatable.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';

/// 共有カードに載せるデータのうち、他の画面から渡されるもの（`ShareCardArgs` の項目）。

/// 週間カードの「今週の難問」1 問の結果。
class WeeklyProblemResult extends Equatable {
  const WeeklyProblemResult({
    required this.correct,
    this.communityRate,
    this.problemId,
  });

  /// 自分が正解したか。
  final bool correct;

  /// みんなの正解率（0〜1）。分からなければ null。
  final double? communityRate;
  final String? problemId;

  @override
  List<Object?> get props => [correct, communityRate, problemId];
}

/// 週間カード（今週の成績と難問の結果。仕様 6.10）。
class WeeklySummary extends Equatable {
  const WeeklySummary({
    required this.weekStart,
    this.answered = 0,
    this.correct = 0,
    this.hardProblems = const [],
  });

  /// 週の最初の日。
  final DateTime weekStart;

  /// 今週解いた問題の数・正解数。
  final int answered;
  final int correct;

  /// 今週の難問（正解率の低い問題）の結果。カードには先頭から最大 3 件を載せる。
  final List<WeeklyProblemResult> hardProblems;

  /// 今週の正解率（0〜1）。解いていなければ null。
  double? get accuracy => answered <= 0 ? null : correct / answered;

  @override
  List<Object?> get props => [weekStart, answered, correct, hardProblems];
}

/// 和了の役と点数のカード（`ShareCardKind.win` / `winQuiz`）に載せるもの。
///
/// [hand] は和了牌をツモ牌（[HandInput.tsumoIndex]）にした手（副露・ドラ表示牌つき）。
/// [request] は採点した条件、[result] はその結果（高点法で選んだ解釈）。
class WinShareData extends Equatable {
  const WinShareData({
    required this.hand,
    required this.request,
    required this.result,
  });

  final HandInput hand;
  final WinRequest request;
  final WinResult result;

  @override
  List<Object?> get props => [hand, request, result];
}
