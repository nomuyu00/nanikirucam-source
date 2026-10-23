import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_menu.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problem_tile.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';

/// 今日の問題（仕様 3.5・6.11）。公式 1 問とユーザー投稿 2 問（無料）。Pro は過去の日の
/// 問題と、回答の多い人気問題も解ける。問題をタップすると Quiz（制限時間つき）へ進む。
///
/// バックエンドなしの版（[LocalDailyProblemRepository]）では、端末内で作る 3 問を
/// 「基本・標準・応用」として出す（出題者・回答数・通報・人気の問題は出さない）。
/// 回答した問題にはチェックを付け、3 問とも解いたら達成を表示する。
class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  /// 表示中の日付。null は今日。
  String? _date;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(appAnalyticsProvider).logEvent(AnalyticsEvent.dailyOpened),
    );
  }

  void _step(String today, String current, {required bool back}) {
    final pro = ref.read(entitlementsProvider).pro;
    if (back && !pro) {
      Navigator.of(context).pushNamed(
        Routes.paywall,
        arguments: const PaywallArgs(trigger: PaywallTrigger.todayLimit),
      );
      return;
    }
    final next = back ? previousDateString(current) : nextDateString(current);
    if (next == null) return;
    setState(() => _date = next == today ? null : next);
  }

  void _openProblem(Problem problem) {
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.problemOpened,
            parameters: {'source': 'today'},
          ),
    );
    unawaited(
      pushProblemQuiz(
        Navigator.of(context),
        problem,
        timed: true,
        // 端末内の問題は公開問題ではないので、計測・履歴の出どころは「今日の問題」。
        source: isLocalDailyProblemId(problem.id) ? 'today' : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.problemsStrings;
    final repository = ref.watch(problemRepositoryProvider);
    final today = ref.watch(todayDateProvider);
    final date = _date ?? today;
    final isToday = date == today;
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final myUid = ref.watch(authUidProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.todayTitle)),
      body: !repository.supportsDaily
          ? _Message(text: strings.onlineUnavailable)
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(dailyProblemsProvider(date));
                await ref
                    .read(dailyProblemsProvider(date).future)
                    .catchError((Object _) => DailyProblems.empty(date));
              },
              child: ListView(
                key: const ValueKey('today-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.sm,
                  AppSpacing.gutter,
                  AppSpacing.xl,
                ),
                children: [
                  _DateBar(
                    label: strings.dateLabel(date),
                    canGoForward: !isToday,
                    onBack: () => _step(today, date, back: true),
                    onForward: () => _step(today, date, back: false),
                  ),
                  ..._daily(
                    context,
                    date,
                    isToday,
                    myUid,
                    online: repository.available,
                  ),
                  // 人気の問題はバックエンドがあるときだけ（無いときはロックも出さない）。
                  if (repository.available) ...[
                    const SizedBox(height: 16),
                    _popular(context, pro),
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _daily(
    BuildContext context,
    String date,
    bool isToday,
    String? myUid, {
    required bool online,
  }) {
    final strings = context.problemsStrings;
    final daily = ref.watch(dailyProblemsProvider(date));
    final blocked = ref.watch(blockedAuthorsProvider);
    if (!online) {
      // 端末内の問題（出題者がいないのでブロックの読み込みを待たない）。
      return daily.when(
        loading: () => [_Loading(text: strings.generating)],
        error: (error, _) => [
          _Message(
            text: strings.generateFailed,
            action: FilledButton(
              key: const ValueKey('today-retry'),
              onPressed: () => ref.invalidate(dailyProblemsProvider(date)),
              child: Text(strings.tryAgain),
            ),
          ),
        ],
        data: (data) => data.isEmpty
            ? [_Message(text: isToday ? strings.todayEmpty : strings.dayEmpty)]
            : _localDaily(context, data.all, isToday),
      );
    }
    if (!blocked.loaded) return const [_Loading()];
    return daily.when(
      loading: () => const [_Loading()],
      error: (error, _) => [
        _Message(
          text: strings.offline,
          action: FilledButton(
            onPressed: () => ref.invalidate(dailyProblemsProvider(date)),
            child: Text(strings.retry),
          ),
        ),
      ],
      data: (data) {
        if (data.isEmpty) {
          return [
            _Message(text: isToday ? strings.todayEmpty : strings.dayEmpty),
          ];
        }
        // ブロック中の出題者の問題は出さない（App Store 審査ガイドライン 1.2）。
        final official = data.official;
        final showOfficial =
            official != null && !blocked.isBlocked(official.authorUid);
        final picks = withoutBlockedAuthors(data.picks, blocked);
        if (!showOfficial && picks.isEmpty) {
          return [_Message(text: strings.todayAllBlocked)];
        }
        return [
          if (showOfficial)
            _problemTile(official, strings.officialBadge, myUid),
          for (final problem in picks)
            _problemTile(problem, strings.communityBadge, myUid),
        ];
      },
    );
  }

  Widget _problemTile(Problem problem, String badge, String? myUid) {
    return ProblemListTile(
      key: ValueKey('today-problem-${problem.id}'),
      problem: problem,
      badges: [badge],
      onTap: () => _openProblem(problem),
      trailing: problem.isAuthoredBy(myUid)
          ? null
          : ProblemMenuButton(
              key: ValueKey('today-menu-${problem.id}'),
              problemId: problem.id,
              problem: problem,
            ),
    );
  }

  /// 端末内で作った 3 問（基本・標準・応用）と、解いた数・3 問クリアの表示。
  List<Widget> _localDaily(
    BuildContext context,
    List<Problem> problems,
    bool isToday,
  ) {
    final strings = context.problemsStrings;
    final theme = Theme.of(context);
    final solved = ref.watch(dailySolvedProvider);
    final solvedCount = problems.where((p) => solved.contains(p.id)).length;
    final allSolved = solvedCount == problems.length;
    return [
      // 進捗（n/3）。3 問とも解いたらゴールドの達成表示。
      AppCard(
        key: const ValueKey('today-progress'),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        color: allSolved ? AppColors.goldTint : null,
        borderColor: allSolved ? AppColors.gold.withValues(alpha: 0.5) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  allSolved
                      ? Icons.emoji_events_rounded
                      : Icons.event_note_rounded,
                  color: allSolved ? AppColors.goldDeep : AppColors.vermilion,
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    allSolved
                        ? strings.allSolved(isToday: isToday)
                        : strings.dailyProgress(solvedCount, problems.length),
                    key: ValueKey(
                      allSolved ? 'today-all-solved' : 'today-solved-count',
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Row(
              children: [
                for (var i = 0; i < problems.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: AppRadius.pillAll,
                        color: i < solvedCount
                            ? (allSolved
                                  ? AppColors.gold
                                  : theme.colorScheme.primary)
                            : theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Text(strings.localDailyNote, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
      for (final problem in problems)
        ProblemListTile(
          key: ValueKey('today-problem-${problem.id}'),
          problem: problem,
          badges: [
            if (localDailyLevelOf(problem.id) case final level?)
              strings.levelBadge(level),
          ],
          showAuthor: false,
          showStats: false,
          onTap: () => _openProblem(problem),
          trailing: solved.contains(problem.id)
              ? Row(
                  key: ValueKey('today-solved-${problem.id}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: 4),
                    Text(strings.solvedBadge, style: theme.textTheme.bodySmall),
                    const SizedBox(width: 4),
                  ],
                )
              : null,
          footer: switch (localDailyLevelOf(problem.id)) {
            final level? => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                strings.levelHint(level),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            null => null,
          },
        ),
    ];
  }

  Widget _popular(BuildContext context, bool pro) {
    final strings = context.problemsStrings;
    final theme = Theme.of(context);
    if (!pro) {
      return Card(
        key: const ValueKey('today-popular-locked'),
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(strings.popularTitle),
          subtitle: Text(strings.popularLockedBody),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).pushNamed(
              Routes.paywall,
              arguments: const PaywallArgs(trigger: PaywallTrigger.todayLimit),
            ),
            child: Text(strings.seePro),
          ),
        ),
      );
    }
    final popular = ref.watch(popularProblemsProvider);
    final blocked = ref.watch(blockedAuthorsProvider);
    final myUid = ref.watch(authUidProvider).valueOrNull;
    return Column(
      key: const ValueKey('today-popular'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(strings.popularTitle, style: theme.textTheme.titleMedium),
        ),
        popular.when(
          loading: () => const _Loading(),
          error: (_, _) => _Message(text: strings.offline),
          data: (problems) => !blocked.loaded
              ? const _Loading()
              : Column(
                  children: [
                    for (final problem in withoutBlockedAuthors(
                      problems,
                      blocked,
                    ))
                      _problemTile(problem, strings.communityBadge, myUid),
                  ],
                ),
        ),
      ],
    );
  }
}

class _DateBar extends StatelessWidget {
  const _DateBar({
    required this.label,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
  });

  final String label;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final strings = context.problemsStrings;
    return Row(
      children: [
        IconButton(
          key: const ValueKey('today-prev'),
          tooltip: strings.todayPast,
          onPressed: onBack,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            label,
            key: const ValueKey('today-date'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: const ValueKey('today-next'),
          tooltip: strings.todayNext,
          onPressed: canGoForward ? onForward : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.event_busy_outlined,
    message: text,
    action: action,
  );
}

class _Loading extends StatelessWidget {
  const _Loading({this.text});

  final String? text;

  @override
  Widget build(BuildContext context) => LoadingState(
    message: text,
    messageKey: const ValueKey('today-generating'),
  );
}
