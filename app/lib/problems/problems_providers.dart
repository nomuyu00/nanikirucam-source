import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';

/// 今日(JST)の日付。テストでは差し替える。
final todayDateProvider = Provider<String>(
  (ref) => jstDateString(DateTime.now()),
);

/// `daily/{date}` と載っている問題。
final dailyProblemsProvider = FutureProvider.autoDispose
    .family<DailyProblems, String>(
      (ref, date) => ref.watch(problemRepositoryProvider).fetchDaily(date),
    );

/// 自分の問題（新しい順）。未サインインなら空。
final myProblemsProvider = FutureProvider.autoDispose<List<Problem>>((
  ref,
) async {
  final uid = await ref.watch(authUidProvider.future);
  if (uid == null) return const [];
  return ref.watch(problemRepositoryProvider).fetchMyProblems(uid);
});

/// 回答の多い順の問題（Pro の「もっと解く」）。
final popularProblemsProvider = FutureProvider.autoDispose<List<Problem>>(
  (ref) => ref.watch(problemRepositoryProvider).fetchPopular(),
);

/// アプリから公開問題の回答をサーバーへ送る窓口（`POST /api/answer`）。
///
/// Quiz 画面が公開問題（`QuizArgs.problemId` あり）で牌を選んだら呼ぶ:
///
/// ```dart
/// final outcome = await ref.read(problemAnswerSubmitterProvider).submitChoice(
///   problemId: id, input: input, discardId: tileId, selfRank: rank,
/// );
/// // outcome が null（オフライン・未公開など）でも、手元のエンジンの結果で Result へ進める。
/// Navigator.pushNamed(context, Routes.result,
///   arguments: ResultArgs(input: input, chosenDiscardId: tileId, problemId: id, problemOutcome: outcome));
/// ```
class ProblemAnswerSubmitter {
  ProblemAnswerSubmitter({required this.repository, this.analytics});

  final ProblemRepository repository;
  final AppAnalytics? analytics;

  /// 選んだ牌の id（34 種）で送る。手牌にない牌なら null（送らない）。
  Future<ProblemAnswerOutcome?> submitChoice({
    required String problemId,
    required HandInput input,
    required int discardId,
    int? selfRank,
  }) {
    final tile = tileLabelInHand(input, discardId);
    if (tile == null) return Future.value();
    return submit(problemId: problemId, tile: tile, selfRank: selfRank);
  }

  /// 牌ラベルで送る。送れなかった（オフライン・Firebase 無効・削除済みなど）ときは null。
  Future<ProblemAnswerOutcome?> submit({
    required String problemId,
    required String tile,
    int? selfRank,
  }) async {
    if (!repository.available) return null;
    try {
      final outcome = await repository.answer(
        problemId: problemId,
        tile: tile,
        selfRank: selfRank,
      );
      if (!outcome.alreadyAnswered) {
        unawaited(
          analytics?.logEvent(
            AnalyticsEvent.problemAnswered,
            parameters: {'correct': outcome.correct ? 1 : 0},
          ),
        );
      }
      return outcome;
    } on BackendException {
      return null;
    }
  }
}

final problemAnswerSubmitterProvider = Provider<ProblemAnswerSubmitter>(
  (ref) => ProblemAnswerSubmitter(
    repository: ref.watch(problemRepositoryProvider),
    analytics: ref.read(appAnalyticsProvider),
  ),
);

/// [openProblemById] の結果。[blocked] はブロック中の出題者の問題（開かない）。
enum OpenProblemResult { opened, notFound, unavailable, blocked }

/// 公開問題を Quiz で開く。[problem] を渡した画面（Today など）はそのまま遷移する。
/// [source] は計測・履歴の出どころ（[QuizArgs.source]。省略時は `problem`）。
Future<Object?> pushProblemQuiz(
  NavigatorState navigator,
  Problem problem, {
  bool timed = false,
  String? source,
}) {
  return navigator.pushNamed(
    Routes.quiz,
    arguments: QuizArgs(
      input: problem.input,
      problemId: problem.id,
      timed: timed,
      source: source,
    ),
  );
}

/// 問題 ID から公開問題を読み込んで Quiz を開く（ディープリンク・通知から）。
/// 見つからない（削除・非表示）・読み込めないときは遷移せず結果を返す。
///
/// [isBlocked] が出題者の uid に true を返したら（ブロック中の出題者。App Store 審査ガイドライン
/// 1.2）開かずに [OpenProblemResult.blocked] を返し、[onBlocked] に問題を渡す
/// （[showBlockedProblemNotice] で解除の導線を出す）。
Future<OpenProblemResult> openProblemById({
  required NavigatorState navigator,
  required ProblemRepository repository,
  required String problemId,
  AppAnalytics? analytics,
  String source = 'deeplink',
  bool timed = false,
  bool Function(String authorUid)? isBlocked,
  void Function(Problem problem)? onBlocked,
}) async {
  try {
    final problem = await repository.fetchProblem(problemId);
    if (problem == null) return OpenProblemResult.notFound;
    if (isBlocked != null && isBlocked(problem.authorUid)) {
      onBlocked?.call(problem);
      return OpenProblemResult.blocked;
    }
    if (!navigator.mounted) return OpenProblemResult.unavailable;
    unawaited(
      analytics?.logEvent(
        AnalyticsEvent.problemOpened,
        parameters: {'source': source},
      ),
    );
    unawaited(pushProblemQuiz(navigator, problem, timed: timed));
    return OpenProblemResult.opened;
  } on BackendException {
    return OpenProblemResult.unavailable;
  }
}

/// [openProblemById] の結果が失敗なら、画面下にメッセージを出す。
void showOpenProblemFailure(BuildContext context, OpenProblemResult result) {
  final strings = context.problemsStrings;
  final message = switch (result) {
    OpenProblemResult.opened || OpenProblemResult.blocked => null,
    OpenProblemResult.notFound => strings.problemNotFound,
    OpenProblemResult.unavailable => strings.problemOffline,
  };
  if (message == null) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// ブロック中の出題者の問題を開こうとしたときのお知らせ。「ブロック中の出題者の問題です」と
/// 出して開かず、「解除して開く」でブロックを解除してから開ける。
void showBlockedProblemNotice(
  BuildContext context, {
  required Problem problem,
  required BlockedAuthorsNotifier blocks,
  required NavigatorState navigator,
}) {
  final strings = context.problemsStrings;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        key: const ValueKey('blocked-problem-notice'),
        content: Text(strings.blockedProblemNotice),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: strings.unblockAndOpen,
          onPressed: () async {
            await blocks.unblock(problem.authorUid);
            if (navigator.mounted) {
              unawaited(pushProblemQuiz(navigator, problem));
            }
          },
        ),
      ),
    );
}
