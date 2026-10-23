import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/live_milestone_card.dart';
import 'package:nanikiru_cam/share/cards/live_summary_card.dart';
import 'package:nanikiru_cam/share/cards/problem_card.dart';
import 'package:nanikiru_cam/share/cards/result_card.dart';
import 'package:nanikiru_cam/share/cards/streak_card.dart';
import 'package:nanikiru_cam/share/cards/weekly_card.dart';
import 'package:nanikiru_cam/share/cards/win_score_card.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/share/share_links.dart';

/// 共有カードに描く内容（種類ごと）。[ShareCardArgs] から [resolveShareCardModel] で作る。
sealed class ShareCardModel {
  const ShareCardModel();

  /// `share_variant`（分析用。許可リストは `AppAnalytics`）。
  String get analyticsVariant;
}

class ProblemCardModel extends ShareCardModel {
  const ProblemCardModel({
    required this.input,
    required this.authorName,
    this.problemId,
    this.answerCount = 0,
  });

  /// 理牌済みの 14 枚（ツモ牌が末尾）。
  final HandInput input;
  final String authorName;

  /// 公開済みなら ID（QR は問題ページへ）。公開前は null。
  final String? problemId;
  final int answerCount;

  @override
  String get analyticsVariant => 'quiz';
}

class ResultCardModel extends ShareCardModel {
  const ResultCardModel({required this.data, this.problemId});

  final ResultCardData data;
  final String? problemId;

  @override
  String get analyticsVariant => 'result';
}

class LiveMilestoneCardModel extends ShareCardModel {
  const LiveMilestoneCardModel({required this.win, this.firstWin = false});

  final LiveWinSummary win;
  final bool firstWin;

  @override
  String get analyticsVariant => 'app';
}

class LiveSummaryCardModel extends ShareCardModel {
  const LiveSummaryCardModel(this.summary);

  final LiveSummaryArgs summary;

  @override
  String get analyticsVariant => 'app';
}

class StreakCardModel extends ShareCardModel {
  const StreakCardModel(this.streak);

  final StreakState streak;

  @override
  String get analyticsVariant => 'app';
}

class WeeklyCardModel extends ShareCardModel {
  const WeeklyCardModel(this.summary);

  final WeeklySummary summary;

  @override
  String get analyticsVariant => 'app';
}

/// 和了の役と点数のカード。[quiz] なら点数・役を隠した点数クイズ。
class WinShareModel extends ShareCardModel {
  const WinShareModel(this.data, {this.quiz = false});

  final WinShareData data;
  final bool quiz;

  @override
  String get analyticsVariant => quiz ? 'win_quiz' : 'win';
}

/// カードに必要な外部の値（読み込み関数は画面が Riverpod 越しに渡す。テストでは偽物）。
class ShareCardSources {
  const ShareCardSources({
    required this.analyze,
    required this.fetchStats,
    required this.streak,
    required this.nickname,
  });

  /// 無料の解析（Pro の詳細は要らない）。
  final Future<AnalysisReport> Function(HandInput input) analyze;

  /// 公開問題の回答の集計。読めなければ null（失敗は例外にしない）。
  final Future<ProblemStats?> Function(String problemId) fetchStats;
  final StreakState streak;

  /// 出題者名（`users/{uid}.nickname`）。
  final String nickname;
}

/// [args] からカードの内容を作る。必要な項目が足りなければ null。
///
/// 通信の失敗でカード自体は作れなくならない（回答数・正解率が載らないだけ）。
Future<ShareCardModel?> resolveShareCardModel(
  ShareCardArgs args,
  ShareCardSources sources,
) async {
  switch (args.kind) {
    case ShareCardKind.problem:
      final input = args.input;
      if (input == null) return null;
      var count = 0;
      final id = args.problemId;
      if (id != null) {
        final stats = await sources.fetchStats(id);
        count = stats?.total ?? 0;
      }
      return ProblemCardModel(
        input: input.normalized(),
        authorName: sources.nickname,
        problemId: id,
        answerCount: count,
      );
    case ShareCardKind.result:
      final input = args.input;
      if (input == null) return null;
      final report = await sources.analyze(input);
      var percent = args.outcome?.stats.total == 0
          ? null
          : args.outcome?.stats.correctPercent;
      final id = args.problemId;
      if (percent == null && id != null) {
        final stats = await sources.fetchStats(id);
        percent = stats?.total == 0 ? null : stats?.correctPercent;
      }
      return ResultCardModel(
        data: ResultCardData.fromReport(
          input: input,
          report: report,
          chosenDiscardId: args.chosenDiscardId,
          communityPercent: percent,
          streak: sources.streak.current,
        ),
        problemId: id,
      );
    case ShareCardKind.liveMilestone:
      final win = args.win;
      if (win == null) return null;
      return LiveMilestoneCardModel(win: win, firstWin: args.firstWin);
    case ShareCardKind.liveSummary:
      final live = args.live;
      if (live == null) return null;
      return LiveSummaryCardModel(live);
    case ShareCardKind.streak:
      return StreakCardModel(sources.streak);
    case ShareCardKind.weekly:
      final weekly = args.weekly;
      if (weekly == null) return null;
      return WeeklyCardModel(weekly);
    case ShareCardKind.win:
    case ShareCardKind.winQuiz:
      final win = args.winShare;
      if (win == null) return null;
      return WinShareModel(win, quiz: args.kind == ShareCardKind.winQuiz);
  }
}

/// カードの QR が指す URL。問題（結果カードも、問題から来たなら）は問題ページ
/// （`/p/{id}?ref=`）、それ以外とオフライン時はストア。
String qrUrlFor(ShareCardModel model, {String? referralCode}) {
  final problemId = switch (model) {
    ProblemCardModel() => model.problemId,
    ResultCardModel() => model.problemId,
    _ => null,
  };
  if (problemId != null) {
    return AppConfig.problemUrl(problemId, referralCode: referralCode);
  }
  return ShareLinks.storeUrl(
    campaign: switch (model) {
      ProblemCardModel() || ResultCardModel() => 'problem',
      WinShareModel() => 'win',
      _ => 'referral',
    },
    referralCode: referralCode,
  );
}

/// 共有シートに添える文章。
String shareTextFor(
  ShareCardModel model,
  ShareStrings strings, {
  required String url,
}) {
  switch (model) {
    case ProblemCardModel():
      return strings.problemShareText(url);
    case ResultCardModel():
      return strings.resultShareText(
        correct: model.data.isCorrect == true,
        percent: model.data.communityPercent,
        url: url,
      );
    case LiveMilestoneCardModel():
    case LiveSummaryCardModel():
      return strings.liveShareText(url);
    case StreakCardModel():
      return strings.streakShareText(model.streak.current, url);
    case WeeklyCardModel():
      return strings.weeklyShareText(url);
    case WinShareModel():
      final win = WinStrings(strings.lang);
      return model.quiz
          ? win.quizShareText(model.data.request, url: url)
          : win.shareText(model.data.result, url: url);
  }
}

/// [model] のカードを描く。無料のときは [watermark] で透かしを重ねる。
Widget buildShareCard(
  ShareCardModel model, {
  required ShareCardFormat format,
  required ShareStrings strings,
  required String qrUrl,
  bool watermark = false,
}) {
  switch (model) {
    case ProblemCardModel():
      return ProblemCard(
        input: model.input,
        authorName: model.authorName,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
        answerCount: model.answerCount,
      );
    case ResultCardModel():
      return ResultCard(
        data: model.data,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
      );
    case LiveMilestoneCardModel():
      return LiveMilestoneCard(
        win: model.win,
        firstWin: model.firstWin,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
      );
    case LiveSummaryCardModel():
      return LiveSummaryCard(
        summary: model.summary,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
      );
    case StreakCardModel():
      return StreakCard(
        streak: model.streak,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
      );
    case WeeklyCardModel():
      return WeeklyCard(
        summary: model.summary,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
      );
    case WinShareModel():
      return WinScoreCard(
        data: model.data,
        quiz: model.quiz,
        qrUrl: qrUrl,
        format: format,
        strings: strings,
        watermark: watermark,
      );
  }
}
