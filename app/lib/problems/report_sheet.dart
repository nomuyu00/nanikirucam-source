import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';

/// 通報シートで「この出題者をブロック」が選ばれたことを表す。
const Object _blockChoice = Object();

/// 問題の通報シート（`reportProblem`。API.md 1.3）。理由の下に「この出題者をブロック」も並ぶ
/// （App Store 審査ガイドライン 1.2）。Today の問題の「⋮」メニューと、Result 画面（公開問題を
/// 解いたあと）から使う:
///
/// ```dart
/// showReportProblemSheet(context, repository: ref.read(problemRepositoryProvider), problemId: id);
/// ```
///
/// ブロックの対象は [problem] の出題者。渡さなければ [problemId] で問題を読み込んで決める
/// （Result・Quiz のように問題 ID しか持たない画面用）。`ProviderScope` の外
/// （[ProviderScope.containerOf] できない）ではブロックの項目を出さない。
Future<void> showReportProblemSheet(
  BuildContext context, {
  required ProblemRepository repository,
  required String problemId,
  Problem? problem,
}) async {
  final strings = context.problemsStrings;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = _containerOf(context);
  final choice = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              strings.reportTitle,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final reason in ProblemReportReason.values)
            ListTile(
              key: ValueKey('report-reason-${reason.name}'),
              title: Text(strings.reasonLabel(reason)),
              onTap: () => Navigator.of(sheetContext).pop(reason),
            ),
          if (container != null) ...[
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('report-block-author'),
              leading: const Icon(Icons.block),
              title: Text(strings.blockAuthor),
              onTap: () => Navigator.of(sheetContext).pop(_blockChoice),
            ),
          ],
        ],
      ),
    ),
  );
  if (choice == null) return;
  if (identical(choice, _blockChoice)) {
    if (!context.mounted || container == null) return;
    // 自分の uid は、まだ読み込み中かもしれない（自分の問題を除くために待つ）。
    String? myUid;
    try {
      myUid = await container.read(authUidProvider.future);
    } catch (_) {}
    if (!context.mounted) return;
    await blockAuthorOfProblem(
      context,
      repository: repository,
      blocks: container.read(blockedAuthorsProvider.notifier),
      problemId: problemId,
      problem: problem,
      myUid: myUid,
    );
    return;
  }
  final reason = choice as ProblemReportReason;
  String message;
  try {
    final result = await repository.report(problemId, reason);
    message = result.alreadyReported
        ? strings.reportAlready
        : strings.reportDone;
  } on BackendException catch (error) {
    message = error.reason == 'own_problem'
        ? strings.reportOwn
        : strings.reportFailed;
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

ProviderContainer? _containerOf(BuildContext context) {
  try {
    return ProviderScope.containerOf(context, listen: false);
  } catch (_) {
    return null;
  }
}

/// 問題の出題者を、確認ダイアログのあとでブロックする。
///
/// [problem] が無ければ [problemId] で読み込む（読み込めなければ「ブロックできませんでした」）。
/// 自分の問題・削除済みの出題者はブロックできない。ブロックしたら true。
Future<bool> blockAuthorOfProblem(
  BuildContext context, {
  required ProblemRepository repository,
  required BlockedAuthorsNotifier blocks,
  required String problemId,
  Problem? problem,
  String? myUid,
}) async {
  final strings = context.problemsStrings;
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String message) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Problem? target = problem;
  if (target == null) {
    try {
      target = await repository.fetchProblem(problemId);
    } on BackendException {
      say(strings.blockFailed);
      return false;
    }
  }
  if (target == null || !isBlockableAuthor(target.authorUid)) {
    say(strings.blockFailed);
    return false;
  }
  if (target.isAuthoredBy(myUid)) {
    say(strings.blockSelf);
    return false;
  }
  final author = target;
  if (!context.mounted) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const ValueKey('block-confirm'),
      title: Text(strings.blockConfirmTitle),
      content: Text(strings.blockConfirmBody(author.authorNickname)),
      actions: [
        TextButton(
          key: const ValueKey('block-cancel'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            MaterialLocalizations.of(dialogContext).cancelButtonLabel,
          ),
        ),
        FilledButton(
          key: const ValueKey('block-confirm-ok'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(strings.blockAction),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  final ok = await blocks.block(
    author.authorUid,
    nickname: author.authorNickname,
  );
  say(ok ? strings.blockDone : strings.blockFailed);
  return ok;
}
