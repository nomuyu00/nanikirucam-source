import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/notice_card.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';

/// 対局サマリー（仕様 6.4）: 利用時間・案内回数・採用率・和了と最高打点・役の一覧。
/// 和了があれば節目（初めての和了・初めての満貫・最高打点の更新）を出して共有へ。
class LiveSummaryPage extends ConsumerWidget {
  const LiveSummaryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.liveStrings;
    final args = context.routeArgs<LiveSummaryArgs>();
    final sessionsAsync = ref.watch(liveSessionsProvider);
    final sessionsLoaded = sessionsAsync.hasValue && !sessionsAsync.isLoading;
    final sessions = sessionsAsync.value ?? const <LiveSession>[];
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final today = localDateKey(ref.watch(clockProvider)());

    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.summaryTitle)),
        body: EmptyState(
          icon: Icons.sports_esports_outlined,
          message: strings.noWins,
        ),
      );
    }

    // 保存したセッション（和了した手・役）を引く。無ければ引数だけで出す。
    LiveSession? saved;
    for (final s in sessions) {
      if (s.startedAt == args.startedAt) {
        saved = s;
        break;
      }
    }
    final earlier = [
      for (final s in sessions)
        if (s.startedAt.isBefore(args.startedAt)) s,
    ];
    // 採用率 = 採用した回数 / 判定できた回数（判定できなければ「—」）。
    final rate = args.followChecks == 0
        ? null
        : args.followedCount / args.followChecks;
    final wins =
        saved?.wins ??
        [
          for (final w in args.wins)
            LiveWinRecord(han: w.han, fu: w.fu, points: w.points, yaku: w.yaku),
        ];
    final best = wins.isEmpty
        ? null
        : wins.reduce((a, b) => a.points >= b.points ? a : b);

    // 節目は、保存したセッションを読み終えてから判定する（読み込み中に「初めて」と出さない）。
    final milestones = <String>[];
    var firstWin = false;
    if (wins.isNotEmpty && sessionsLoaded) {
      final earlierWins = [for (final s in earlier) ...s.wins];
      firstWin = earlierWins.isEmpty;
      if (firstWin) milestones.add(strings.milestoneFirstWin);
      final mangan = wins.any((w) => w.rank != 'none');
      if (mangan && !earlierWins.any((w) => w.rank != 'none')) {
        milestones.add(strings.milestoneFirstMangan);
      }
      final previousBest = earlierWins.fold<int>(
        0,
        (m, w) => w.points > m ? w.points : m,
      );
      if (earlierWins.isNotEmpty &&
          best != null &&
          best.points > previousBest) {
        milestones.add(strings.milestoneBest);
      }
    }

    final todaySessions = [
      for (final s in sessions)
        if (localDateKey(s.startedAt) == today) s,
    ];
    final endedNote = strings.endedBy(args.endedBy);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(strings.summaryTitle)),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          if (endedNote.isNotEmpty) ...[
            NoticeCard(
              tone: NoticeTone.caution,
              icon: Icons.info_outline_rounded,
              message: endedNote,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          for (final m in milestones) ...[
            _MilestoneCard(
              key: const ValueKey('live-summary-milestone'),
              text: m,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          // 今回の数字（利用時間・案内した回数・採用率・和了と最高打点）。
          _StatsCard(
            stats: [
              (
                Icons.timer_outlined,
                strings.usedTime,
                strings.duration(args.durationSec),
              ),
              (
                Icons.tips_and_updates_outlined,
                strings.adviceCount,
                '${args.adviceCount}',
              ),
              (
                Icons.check_circle_outline_rounded,
                strings.followRate,
                rate == null
                    ? strings.noFollowData
                    : '${(rate * 100).round()}%',
              ),
              (
                Icons.emoji_events_outlined,
                strings.winsLabel,
                strings.winCount(wins.length),
              ),
            ],
            best: best == null ? null : strings.points(best.points),
          ),
          SectionHeader(strings.winsLabel),
          if (wins.isEmpty)
            AppCard(
              child: Row(
                children: [
                  Icon(
                    Icons.sports_esports_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      strings.noWins,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            GroupedSection(
              children: [
                for (final w in wins)
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.goldTint,
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(
                        w.winType == 'ron'
                            ? Icons.front_hand_outlined
                            : Icons.back_hand_outlined,
                        color: AppColors.goldDeep,
                      ),
                    ),
                    title: Text(
                      [
                        w.winType == 'ron'
                            ? strings.ronLabel
                            : strings.tsumoLabel,
                        strings.hanFu(w.han, w.fu),
                        if (strings.rankName(w.rank).isNotEmpty)
                          strings.rankName(w.rank),
                        strings.points(w.points),
                      ].join('  '),
                    ),
                    subtitle: Text(w.yaku.map(strings.yakuName).join('・')),
                  ),
              ],
            ),
          SectionHeader(strings.todayTotal),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.todaySummary(
                    todaySessions.length,
                    todaySessions.fold<int>(0, (n, s) => n + s.wins.length),
                  ),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                if (pro)
                  Text(
                    strings.allTimeSummary(
                      sessions.length,
                      sessions.fold<int>(0, (n, s) => n + s.wins.length),
                      sessions
                          .expand((s) => s.wins)
                          .fold<int>(0, (m, w) => w.points > m ? w.points : m),
                    ),
                    style: theme.textTheme.bodyMedium,
                  )
                else
                  Row(
                    children: [
                      const ProBadge(),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          strings.proHistoryNote,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
      // 共有の導線は画面の下に固定する（和了があれば節目カード、なければサマリーカード）。
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.md,
              AppSpacing.gutter,
              AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (best != null) ...[
                  FilledButton.icon(
                    key: const ValueKey('live-summary-share'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.lgAll,
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pushNamed(
                      Routes.shareCard,
                      arguments: ShareCardArgs(
                        kind: ShareCardKind.liveMilestone,
                        input: best.hand,
                        win: best.toSummary(),
                        firstWin: firstWin,
                      ),
                    ),
                    icon: const Icon(Icons.ios_share),
                    label: Text(strings.share),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const ValueKey('live-summary-share-summary'),
                        onPressed: () => Navigator.of(context).pushNamed(
                          Routes.shareCard,
                          arguments: ShareCardArgs(
                            kind: ShareCardKind.liveSummary,
                            live: args,
                          ),
                        ),
                        icon: const Icon(Icons.ios_share),
                        label: Text(
                          strings.shareSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(strings.close),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 節目（初めての和了・初めての満貫・最高打点の更新）。ゴールドで祝う。
class _MilestoneCard extends StatelessWidget {
  const _MilestoneCard({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgAll,
        gradient: const LinearGradient(
          colors: [AppColors.goldTint, AppColors.tileFace],
        ),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration_rounded, color: AppColors.goldDeep),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.goldDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 今回の数字（2 列）と最高打点。
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.stats, required this.best});

  final List<(IconData, String, String)> stats;
  final String? best;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget stat((IconData, String, String) s) {
      final (icon, label, value) = s;
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(value, style: theme.textTheme.headlineSmall),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      if (rows.isNotEmpty) rows.add(const Divider());
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: stat(stats[i])),
              const VerticalDivider(width: 1),
              Expanded(
                child: i + 1 < stats.length
                    ? stat(stats[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          if (best != null) ...[
            const Divider(),
            Container(
              color: AppColors.goldTint.withValues(alpha: 0.6),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.workspace_premium_rounded,
                    size: 20,
                    color: AppColors.goldDeep,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      strings.bestPoints,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    best!,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: AppColors.goldDeep,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
