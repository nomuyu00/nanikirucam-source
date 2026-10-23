import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/report_sheet.dart';

enum _ProblemAction { report, block }

/// 公開問題の「⋮」メニュー: 「この問題を通報」と「この出題者をブロック」
/// （App Store 審査ガイドライン 1.2）。Today の一覧と Quiz の AppBar で使う。
///
/// 自分の問題には出さない。[problem] を渡すと出題者の読み込みを省ける。
class ProblemMenuButton extends ConsumerWidget {
  const ProblemMenuButton({super.key, required this.problemId, this.problem});

  final String problemId;
  final Problem? problem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.problemsStrings;
    final myUid = ref.watch(authUidProvider).valueOrNull;
    if (problem?.isAuthoredBy(myUid) ?? false) return const SizedBox.shrink();
    return PopupMenuButton<_ProblemAction>(
      tooltip: strings.problemMenuTooltip,
      onSelected: (action) {
        final repository = ref.read(problemRepositoryProvider);
        switch (action) {
          case _ProblemAction.report:
            showReportProblemSheet(
              context,
              repository: repository,
              problemId: problemId,
              problem: problem,
            );
          case _ProblemAction.block:
            blockAuthorOfProblem(
              context,
              repository: repository,
              blocks: ref.read(blockedAuthorsProvider.notifier),
              problemId: problemId,
              problem: problem,
              myUid: myUid,
            );
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const ValueKey('problem-menu-report'),
          value: _ProblemAction.report,
          child: Text(strings.report),
        ),
        PopupMenuItem(
          key: const ValueKey('problem-menu-block'),
          value: _ProblemAction.block,
          child: Text(strings.blockAuthor),
        ),
      ],
    );
  }
}
