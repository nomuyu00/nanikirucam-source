import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problem_tile.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/notice_card.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';

/// 出題した問題（仕様 6.11）。自分の問題と回答数・正解率、回答が 10 / 50 / 100 人に
/// 届いたときの表示、もう一度シェアする導線、公開待ち（オフラインで公開できなかった分）。
class MyProblemsPage extends ConsumerStatefulWidget {
  const MyProblemsPage({super.key});

  @override
  ConsumerState<MyProblemsPage> createState() => _MyProblemsPageState();
}

class _MyProblemsPageState extends ConsumerState<MyProblemsPage> {
  @override
  void initState() {
    super.initState();
    // 公開待ちがあれば、開いたときに再試行する。
    unawaited(_retryQueue());
  }

  Future<void> _retryQueue() async {
    final service = ref.read(publishServiceProvider);
    if (!service.available) return;
    if (await service.pendingCount() == 0) return;
    await service.flush();
    if (!mounted) return;
    ref.invalidate(pendingPublishCountProvider);
    ref.invalidate(myProblemsProvider);
  }

  void _share(Problem problem) {
    Navigator.of(context).pushNamed(
      Routes.shareCard,
      arguments: ShareCardArgs(
        kind: ShareCardKind.problem,
        input: problem.input,
        problemId: problem.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.problemsStrings;
    final repository = ref.watch(problemRepositoryProvider);
    final mine = ref.watch(myProblemsProvider);
    final pending = ref.watch(pendingPublishCountProvider).valueOrNull ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(strings.myProblemsTitle)),
      body: !repository.available && pending == 0
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              message: strings.onlineUnavailable,
            )
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myProblemsProvider);
                ref.invalidate(pendingPublishCountProvider);
                await ref
                    .read(myProblemsProvider.future)
                    .catchError((Object _) => const <Problem>[]);
              },
              child: ListView(
                key: const ValueKey('my-problems-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.page,
                children: [
                  if (pending > 0) ...[
                    NoticeCard(
                      key: const ValueKey('my-problems-pending'),
                      tone: NoticeTone.info,
                      icon: Icons.cloud_upload_outlined,
                      message: strings.pendingPublish(pending),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  ...mine.when(
                    loading: () => const [LoadingState()],
                    error: (error, _) => [
                      EmptyState.error(
                        message: strings.offline,
                        action: FilledButton(
                          onPressed: () => ref.invalidate(myProblemsProvider),
                          child: Text(strings.retry),
                        ),
                      ),
                    ],
                    data: (problems) => problems.isEmpty
                        ? [
                            EmptyState(
                              icon: Icons.quiz_outlined,
                              message: strings.myProblemsEmpty,
                            ),
                          ]
                        : [
                            for (final p in problems)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: _tile(context, p),
                              ),
                          ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(BuildContext context, Problem problem) {
    final strings = context.problemsStrings;
    final theme = Theme.of(context);
    final milestone = strings.milestone(problem.stats.total);
    final created = problem.createdAt;
    return ProblemListTile(
      key: ValueKey('my-problem-${problem.id}'),
      problem: problem,
      showAuthor: false,
      badges: [if (problem.hidden) strings.hiddenBadge],
      onTap: problem.hidden ? null : () => _share(problem),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (problem.hidden)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: NoticeCard(
                tone: NoticeTone.danger,
                icon: Icons.visibility_off_outlined,
                message: strings.hiddenHelp,
              ),
            ),
          if (milestone != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.celebration_rounded,
                    size: 18,
                    color: AppColors.goldDeep,
                  ),
                  const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      milestone,
                      key: ValueKey('my-problem-milestone-${problem.id}'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: AppColors.goldDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              if (created != null)
                Text(
                  strings.createdLabel(created.toLocal()),
                  style: theme.textTheme.bodySmall,
                ),
              const Spacer(),
              if (!problem.hidden)
                TextButton.icon(
                  key: ValueKey('my-problem-share-${problem.id}'),
                  onPressed: () => _share(problem),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: Text(strings.shareAgain),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
