import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/share/share_data.dart';

/// 画面のルート名（仕様 6.0）。名前付きルートで遷移し、引数は下の `*Args` クラスで渡す。
///
/// 画面から画面へ渡す手は必ず [HandInput]（`lib/analysis/hand_input.dart`）。
/// 新しい画面を足すときは、ここに名前と引数の型を足し、`app.dart` の `routes` に登録する。
abstract final class Routes {
  /// 起動直後の画面。初回は Onboarding、以降は Home（`HomeGate`）。
  static const home = '/';
  static const onboarding = '/onboarding';

  /// ライブナビ（引数なし）。
  static const live = '/live';

  /// ライブの対局サマリー（[LiveSummaryArgs]）。
  static const liveSummary = '/live/summary';

  /// 写真の撮影（引数は省略可。[CameraArgs] で点数計算モードにできる）。
  /// 撮影後は [recognitionLoading] → [recognition]。
  static const camera = '/camera';

  /// 認識中（[RecognitionLoadingArgs]）。
  static const recognitionLoading = '/recognition/loading';

  /// 認識結果の修正（[RecognitionArgs]）。
  static const recognition = '/recognition';

  /// 手入力（引数は省略可で、[RecognitionArgs] を渡すと途中から始める）。
  static const manualInput = '/manual';

  /// クイズ「あなたなら何を切る？」（[QuizArgs]）。
  static const quiz = '/quiz';

  /// 結果（[ResultArgs]）。
  static const result = '/result';

  /// 候補の詳細（[CandidateDetailArgs]）。
  static const candidateDetail = '/result/candidate';

  /// 解説（Pro の詳細。[CandidateDetailArgs]）。
  static const explanation = '/result/explanation';

  /// 共有カード（[ShareCardArgs]）。
  static const shareCard = '/share';

  /// 問題の公開（[PublishArgs]）。
  static const publish = '/share/publish';

  /// 今日の問題（引数なし）。
  static const today = '/today';

  /// 出題した問題（引数なし）。
  static const myProblems = '/problems/mine';

  /// 履歴・弱点（引数なし）。
  static const history = '/history';

  /// 課金画面（[PaywallArgs]、省略可）。
  static const paywall = '/paywall';

  /// 設定（引数なし）。
  static const settings = '/settings';

  /// 和了の役と点数（Pro。[WinScoreArgs]）。
  static const winScore = '/win';
}

extension RouteArgsContext on BuildContext {
  /// 現在のルートの引数を [T] で受け取る。渡されていない・型が違うときは null。
  T? routeArgs<T extends Object>() {
    final args = ModalRoute.of(this)?.settings.arguments;
    return args is T ? args : null;
  }
}

// --- 引数 -----------------------------------------------------------------

/// 写真・手入力で手を入れたあとの行き先。
enum HandEntryMode {
  /// 何切る（既定）。確定すると Quiz（14 枚）か Result（13 枚）へ。
  solve,

  /// 和了の点数計算（Pro）。確定すると [Routes.winScore] へ。
  score,
}

/// [Routes.camera]（省略可）。
class CameraArgs {
  const CameraArgs({this.mode = HandEntryMode.solve});

  final HandEntryMode mode;
}

/// [Routes.recognitionLoading]: 撮影した写真（JPEG など）。
class RecognitionLoadingArgs {
  const RecognitionLoadingArgs({
    required this.imageBytes,
    this.mode = HandEntryMode.solve,
  });

  final Uint8List imageBytes;

  /// 認識のあとの修正画面に引き継ぐ。
  final HandEntryMode mode;
}

/// [Routes.recognition] / [Routes.manualInput]: 認識結果の修正画面。
class RecognitionArgs {
  const RecognitionArgs({
    required this.draft,
    this.imageBytes,
    this.imageQuarterTurns = 0,
    this.base,
    this.notice,
    this.historyId,
    this.mode = HandEntryMode.solve,
  });

  /// 手入力の開始（牌なし）。
  static final RecognitionArgs manual = RecognitionArgs(
    draft: RecognitionDraft.empty,
  );

  final RecognitionDraft draft;

  /// 撮影した写真（サムネイルと検出枠の表示用）。端末の外には出さない。
  final Uint8List? imageBytes;

  /// [imageBytes] を正立させるのに時計回りに回す回数。
  final int imageQuarterTurns;

  /// 局の条件（風・ドラ表示牌・巡目など）の初期値。省略時は東場・南家。
  final HandInput? base;

  /// 画面上部に出す注意書き（認識が不完全だったときなど）。
  final String? notice;

  /// 撮るだけモードで保存した「未解析」の履歴（`HistoryEntry.id`）を開いたとき。
  /// 確定すると Quiz / Result を経て、その記録を解析済みに置き換える（二重に数えない）。
  final String? historyId;

  /// [HandEntryMode.score] なら確定ボタンが「点数を計算」になり、和了の点数画面へ進む。
  final HandEntryMode mode;
}

/// [Routes.quiz]: 14 枚から 1 枚選ぶ。13 枚の手は Result に直接進む。
class QuizArgs {
  const QuizArgs({
    required this.input,
    this.problemId,
    this.timed = false,
    this.source,
    this.historyId,
  });

  final HandInput input;

  /// 公開問題から来たときの問題 ID。
  final String? problemId;

  /// 今日の問題などで制限時間をつける。
  final bool timed;

  /// どこから来た手か（計測 `analysis_started{source}` と履歴に使う）。
  /// `photo` / `manual` / `today` / `problem` / `live` など（`AppAnalytics` の許可リスト）。
  /// 省略時は [problemId] があれば `problem`、なければ `manual`。
  final String? source;

  /// 未解析の履歴から来たとき、その記録の ID（[RecognitionArgs.historyId]）。
  final String? historyId;
}

/// [Routes.result]
class ResultArgs {
  const ResultArgs({
    required this.input,
    this.chosenDiscardId,
    this.chosenAxis,
    this.problemId,
    this.problemOutcome,
    this.fromQuiz = false,
    this.saveToHistory = true,
    this.source,
    this.historyId,
  });

  final HandInput input;

  /// クイズで選んだ牌（34 種の id）。スキップや 13 枚の手は null。
  final int? chosenDiscardId;

  /// クイズで正誤を判定した戦略軸。
  final StrategyAxis? chosenAxis;

  final String? problemId;

  /// Quiz から来た（解析の開始・完了は Quiz が計測済み）。
  final bool fromQuiz;

  /// 履歴（`history_v1`）に記録する。履歴から開き直したときは false。
  final bool saveToHistory;

  /// どこから来た手か（[QuizArgs.source] と同じ値）。
  final String? source;

  /// 未解析の履歴から来たとき、その記録の ID。履歴に足さず、その記録を解析済みに
  /// 置き換える（[RecognitionArgs.historyId]）。
  final String? historyId;

  /// 公開問題をアプリで解いたときの、サーバーの返事（分布・正解・各軸の正誤）。
  /// Quiz が `problemAnswerSubmitterProvider` で受け取って渡す。公開問題でない・
  /// オフラインで送れなかったときは null（手元のエンジンの結果だけで表示する）。
  final ProblemAnswerOutcome? problemOutcome;
}

/// [Routes.candidateDetail] / [Routes.explanation]
class CandidateDetailArgs {
  const CandidateDetailArgs({
    required this.input,
    required this.discardId,
    this.axis = StrategyAxis.balance,
  });

  final HandInput input;

  /// 見たい候補の打牌（34 種の id）。
  final int discardId;
  final StrategyAxis axis;
}

/// 共有カードの種類（仕様 6.10）。
enum ShareCardKind {
  problem,
  result,
  liveMilestone,
  streak,
  weekly,

  /// ライブの対局サマリー（今日の成果）。
  liveSummary,

  /// 和了の役と点数（[ShareCardArgs.winShare]）。
  win,

  /// 点数クイズ（[win] の点数・役を隠して「何点？」）。
  winQuiz,
}

/// [Routes.shareCard]
///
/// 種類ごとに使う項目:
/// - problem: [input]（14 枚）。[problemId] があれば公開済みの問題（QR はその問題へ）、
///   なければ公開画面（[Routes.publish]）へ進む。
/// - result: [input]、[chosenDiscardId]、あれば [problemId] / [outcome]。
/// - liveMilestone: [win]（[firstWin] なら「初和了」）。
/// - liveSummary: [live]。
/// - streak: なし（`streakProvider` を読む）。
/// - weekly: [weekly]。
/// - win / winQuiz: [winShare]（和了の点数画面の計算結果）。
class ShareCardArgs {
  const ShareCardArgs({
    required this.kind,
    this.input,
    this.chosenDiscardId,
    this.problemId,
    this.outcome,
    this.win,
    this.firstWin = false,
    this.live,
    this.weekly,
    this.winShare,
  });

  final ShareCardKind kind;

  /// 問題・結果カードの手。
  final HandInput? input;
  final int? chosenDiscardId;
  final String? problemId;

  /// 公開問題を解いたときのサーバーの返事（結果カードの正解率に使う）。
  final ProblemAnswerOutcome? outcome;

  /// ライブ節目カード（初めての和了・満貫）の和了。
  final LiveWinSummary? win;
  final bool firstWin;

  /// ライブのサマリーカード。
  final LiveSummaryArgs? live;

  /// 週間カード。
  final WeeklySummary? weekly;

  /// 和了の役と点数のカード・点数クイズ。
  final WinShareData? winShare;
}

/// [Routes.winScore]: 和了の役と点数（Pro）。
class WinScoreArgs {
  const WinScoreArgs({
    required this.input,
    this.source = 'manual',
    this.fromEditor = false,
  });

  /// 和了形の 14 枚（副露込み）。和了牌の初期値は [HandInput.tsumoIndex]（無ければ末尾）。
  final HandInput input;

  /// どこから来たか（計測 `win_score_viewed{source}`。`photo` / `manual` / `result`）。
  final String source;

  /// 修正画面から来た（「手牌を直す」で戻るだけでよい）。
  final bool fromEditor;
}

/// [Routes.publish]
class PublishArgs {
  const PublishArgs({required this.input});

  final HandInput input;
}

/// ライブで和了した 1 回。
class LiveWinSummary {
  const LiveWinSummary({
    required this.han,
    required this.fu,
    required this.points,
    this.yaku = const [],
  });

  final int han;
  final int fu;
  final int points;
  final List<String> yaku;
}

/// [Routes.liveSummary]
class LiveSummaryArgs {
  const LiveSummaryArgs({
    required this.startedAt,
    required this.durationSec,
    this.adviceCount = 0,
    this.followedCount = 0,
    this.followChecks = 0,
    this.wins = const [],
    this.endedBy = 'user',
  });

  final DateTime startedAt;
  final int durationSec;

  /// 案内を出した回数（13 枚・14 枚の両方。同じ手は 1 回）。
  final int adviceCount;

  /// 14 枚の案内のあと、次の 13 枚で案内した牌が切られていた回数。
  final int followedCount;

  /// 採用したかを判定できた回数（採用率 = [followedCount] / [followChecks]。0 なら採用率なし）。
  final int followChecks;
  final List<LiveWinSummary> wins;

  /// `user` / `trial_limit` / `battery` / `thermal`（仕様 13 章の `live_ended`）。
  final String endedBy;
}

/// 課金画面を開いた理由（`paywall_viewed{trigger}`）。
enum PaywallTrigger {
  home,
  settings,
  liveTrialEnded,
  quotaExhausted,
  candidateLocked,
  explanationLocked,
  todayLimit,

  /// 履歴の全件・弱点分析（無料は直近 20 件）。
  historyLocked,

  /// 和了の役と点数（Result・Home の入口）。
  winScore,
}

/// [Routes.paywall]
class PaywallArgs {
  const PaywallArgs({
    this.trigger = PaywallTrigger.settings,
    this.liveAdviceCount,
    this.liveWinCount,
  });

  final PaywallTrigger trigger;

  /// 直前のライブで出した案内の回数・和了の回数（体験終了時の訴求に使う）。
  final int? liveAdviceCount;
  final int? liveWinCount;
}
