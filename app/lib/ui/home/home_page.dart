import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart' show kDailyProblemCount;
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/home_strings.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_trial_extend_panel.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/tile_fan.dart';

/// Home（仕様 6.2）。
///
/// 上から: ブランドの見出し（アプリのアイコン・アプリ名・Pro・設定）→ 主動作「ライブナビ」
/// （大きなジェイドのカード。無料は体験の残り時間）→ 体験を使い切ったときだけ動画での延長 →
/// 主動作の 2 列「写真で解析」（無料は今日の残り回数）と「点数計算」（Pro。無料は Paywall
/// `winScore`）→ 毎日の「今日の問題」（進捗 n/3 とストリーク・今週の正解率）→ 補助の小さな
/// タイル（手入力・履歴・出題した問題）→ 直近のライブ。最下部にバナー（無料のみ）。
///
/// 下部ナビは使わない。行き先が少なく、ライブ・写真は全画面の作業フローなので、Home を
/// 起点にした push 遷移のままにする（タブにすると戻る操作と画面の状態の扱いが複雑になる）。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.homeStrings;
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final quota = ref.watch(quotaProvider);
    final now = ref.watch(clockProvider)();
    final streak = ref.watch(streakProvider);
    final history = ref.watch(historyProvider).valueOrNull ?? const [];
    final week = HistoryStats.lastWeek(history, now);
    final trial = ref.watch(liveTrialStateProvider).valueOrNull;
    final online = ref.watch(onlineFeaturesProvider);
    final sessions = ref.watch(liveSessionsProvider).valueOrNull;
    final lastSession = (sessions == null || sessions.isEmpty)
        ? null
        : sessions.first;

    // 今日の問題の進捗（端末内の 3 問のときだけ。公開問題の版は ID が日付から決まらない）。
    final repository = ref.watch(problemRepositoryProvider);
    int? solvedToday;
    if (repository is LocalDailyProblemRepository) {
      final today = ref.watch(todayDateProvider);
      final solved = ref.watch(dailySolvedProvider);
      solvedToday = [
        for (var n = 1; n <= kDailyProblemCount; n++)
          if (solved.contains(localDailyProblemId(today, n))) n,
      ].length;
    }

    void open(String route, {Object? arguments}) =>
        Navigator.of(context).pushNamed(route, arguments: arguments);

    Future<void> openLive() async {
      await Navigator.of(context).pushNamed(Routes.live);
      if (!context.mounted) return;
      // 体験の残り時間と対局サマリーを読み直す。
      ref
        ..invalidate(liveTrialStateProvider)
        ..invalidate(liveSessionsProvider);
    }

    final String? liveDetail;
    if (pro) {
      liveDetail = strings.livePro;
    } else if (trial == null) {
      liveDetail = null;
    } else if (trial.exhausted) {
      liveDetail = strings.liveTrialUsed;
    } else {
      final left = trial.remainingSeconds;
      liveDetail = strings.liveTrialLeft(left ~/ 60, left % 60);
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.xs,
            AppSpacing.gutter,
            AppSpacing.xl,
          ),
          children: [
            _BrandBar(
              pro: pro,
              onPro: () => open(
                Routes.paywall,
                arguments: const PaywallArgs(trigger: PaywallTrigger.home),
              ),
              onSettings: () => open(Routes.settings),
            ),
            const SizedBox(height: AppSpacing.sm),
            _LiveHeroCard(
              key: const ValueKey('home-live'),
              title: strings.live,
              subtitle: strings.liveSubtitle,
              detail: liveDetail,
              exhausted: !pro && (trial?.exhausted ?? false),
              unlimited: pro,
              onTap: openLive,
            ),
            // 体験を使い切っているときだけ、動画での延長を案内する（Pro・広告なしなら何も出ない）。
            const LiveTrialExtendPanel(analyticsTrigger: 'home'),
            const SizedBox(height: AppSpacing.md),
            // 主動作の 2 つ目と 3 つ目: 写真で解析と点数計算（Pro）を 2 列に。
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ActionTile(
                      key: const ValueKey('home-photo'),
                      icon: Icons.photo_camera_outlined,
                      title: strings.photo,
                      subtitle: strings.photoSubtitle,
                      detail: quota.unlimited
                          ? strings.photoUnlimited
                          : strings.photoRemaining(
                              quota.remaining,
                              quota.limit,
                            ),
                      detailKey: const ValueKey('home-photo-remaining'),
                      onTap: () => open(Routes.camera),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ActionTile(
                      key: const ValueKey('home-score'),
                      icon: Icons.calculate_outlined,
                      title: strings.score,
                      subtitle: strings.scoreSubtitle,
                      detail: pro
                          ? strings.scoreDetailPro
                          : strings.scoreDetailFree,
                      detailKey: const ValueKey('home-score-detail'),
                      pro: true,
                      locked: !pro,
                      onTap: () => pro
                          ? open(
                              Routes.camera,
                              arguments: const CameraArgs(
                                mode: HandEntryMode.score,
                              ),
                            )
                          : open(
                              Routes.paywall,
                              arguments: const PaywallArgs(
                                trigger: PaywallTrigger.winScore,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _DailyCard(
              solved: solvedToday,
              total: kDailyProblemCount,
              streakDays: streak.currentAsOf(now),
              bestDays: streak.best,
              week: week,
              onTap: () => open(Routes.today),
            ),
            SectionHeader(strings.more),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _MiniTile(
                    key: const ValueKey('home-manual'),
                    icon: Icons.grid_view_rounded,
                    label: strings.manual,
                    onTap: () => open(Routes.manualInput),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                Expanded(
                  child: _MiniTile(
                    key: const ValueKey('home-history'),
                    icon: Icons.history_rounded,
                    label: strings.history,
                    onTap: () => open(Routes.history),
                  ),
                ),
                // 出題した問題は公開（オンライン機能）が前提。サーバーなしの版では出さない。
                if (online) ...[
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: _MiniTile(
                      key: const ValueKey('home-my-problems'),
                      icon: Icons.quiz_outlined,
                      label: strings.myProblems,
                      onTap: () => open(Routes.myProblems),
                    ),
                  ),
                ],
              ],
            ),
            if (lastSession != null) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const ValueKey('home-last-live'),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                onTap: () => open(
                  Routes.liveSummary,
                  arguments: lastSession.toSummaryArgs(),
                ),
                child: Row(
                  children: [
                    const _IconBubble(icon: Icons.insights_outlined),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.lastLive(
                              (lastSession.durationSec / 60).ceil(),
                              lastSession.adviceCount,
                              lastSession.wins.length,
                            ),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (lastSession.wins.isNotEmpty)
                            Text(
                              strings.lastLiveBest(
                                formatPoints(
                                  lastSession.wins
                                      .map((w) => w.points)
                                      .reduce((a, b) => a > b ? a : b),
                                ),
                              ),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    const _Chevron(),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: pro
          ? null
          : const SafeArea(
              top: false,
              child: AdBannerSlot(placement: AdPlacement.homeBanner),
            ),
    );
  }
}

/// 見出し: 牌のマークとアプリ名、Pro（無料のみ）、設定。
class _BrandBar extends StatelessWidget {
  const _BrandBar({
    required this.pro,
    required this.onPro,
    required this.onSettings,
  });

  final bool pro;
  final VoidCallback onPro;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final strings = context.homeStrings;
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const _AppMark(),
          const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
          Expanded(
            child: Text(
              context.commonStrings.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.jadeDeep,
              ),
            ),
          ),
          if (pro)
            const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: ProBadge(),
            )
          else
            TextButton.icon(
              key: const ValueKey('home-pro'),
              onPressed: onPro,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.goldDeep,
                backgroundColor: AppColors.goldTint,
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text(strings.pro),
            ),
          IconButton(
            key: const ValueKey('home-settings'),
            tooltip: strings.settings,
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }
}

/// アプリのマーク（アプリのアイコン `assets/branding/app_mark.png` を角丸で）。
class _AppMark extends StatelessWidget {
  const _AppMark();

  static const double size = 36;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('home-app-mark'),
      width: size,
      height: size,
      decoration: const BoxDecoration(
        borderRadius: AppRadius.smAll,
        boxShadow: [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.smAll,
        child: Image.asset(
          'assets/branding/app_mark.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
          // 画像が読めなくても見出しの並びを崩さない。
          errorBuilder: (context, error, stack) =>
              const ColoredBox(color: AppColors.jade),
        ),
      ),
    );
  }
}

/// 主動作「ライブナビ」の大きなカード（ジェイドのグラデーションと牌の扇）。
class _LiveHeroCard extends StatelessWidget {
  const _LiveHeroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.detail,
    required this.exhausted,
    required this.onTap,
    this.unlimited = false,
  });

  final String title;
  final String subtitle;
  final String? detail;
  final bool exhausted;

  /// Pro（無制限）。
  final bool unlimited;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const fan = TileFan(
      labels: ['2m', '3m', '5p', '7z', '9s'],
      tileWidth: 30,
      highlight: 3,
    );
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.xlAll,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.jadeBright, AppColors.jade, AppColors.jadeDeep],
            stops: [0, 0.45, 1],
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              // 卓の縁のような淡い円（飾り）。
              Positioned(
                right: -60,
                top: -70,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                      width: 26,
                    ),
                  ),
                ),
              ),
              Positioned(right: AppSpacing.sm, top: AppSpacing.md, child: fan),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl - AppSpacing.xs,
                  AppSpacing.xl - AppSpacing.xs,
                  AppSpacing.xl - AppSpacing.xs,
                  AppSpacing.lg + AppSpacing.xxs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.videocam_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                    Padding(
                      // 牌の扇に文字が重ならないよう、見出しの右側を空ける。
                      padding: EdgeInsets.only(right: fan.size.width * 0.35),
                      child: Text(
                        title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md + AppSpacing.xxs),
                    Row(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: detail == null
                                ? const SizedBox.shrink()
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal:
                                          AppSpacing.md - AppSpacing.xxs,
                                      vertical: AppSpacing.xs + 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: AppRadius.pillAll,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          unlimited
                                              ? Icons.all_inclusive_rounded
                                              : exhausted
                                              ? Icons.hourglass_empty_rounded
                                              : Icons.timer_outlined,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(
                                          width: AppSpacing.xs + 2,
                                        ),
                                        Flexible(
                                          child: Text(
                                            detail!,
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.jade,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 主動作（写真で解析・点数計算）の 2 列のタイル。アイコン・見出し・説明・補足。
/// [pro] なら右上に Pro のバッジ、[locked]（無料）なら補足を鍵つきの金色にする。
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.detail,
    this.detailKey,
    this.pro = false,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? detail;
  final Key? detailKey;
  final VoidCallback onTap;
  final bool pro;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detailColor = locked ? AppColors.goldDeep : theme.colorScheme.primary;
    return AppCard(
      onTap: onTap,
      radius: AppRadius.xl - AppSpacing.xs,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _IconBubble(
                icon: icon,
                size: 44,
                color: pro ? AppColors.goldDeep : null,
                background: pro ? AppColors.goldTint : null,
              ),
              const Spacer(),
              if (pro) const ProBadge(),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(subtitle, style: theme.textTheme.bodySmall),
          const Spacer(),
          if (detail != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (locked) ...[
                  Icon(Icons.lock_outline, size: 14, color: detailColor),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Expanded(
                  child: Text(
                    detail!,
                    key: detailKey,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: detailColor,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 毎日の「今日の問題」: 進捗（n/3）とストリーク・今週の正解率。
class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.solved,
    required this.total,
    required this.streakDays,
    required this.bestDays,
    required this.week,
    required this.onTap,
  });

  /// 今日解いた数（端末内の今日の問題のときだけ。null は進捗を出さない）。
  final int? solved;
  final int total;
  final int streakDays;
  final int bestDays;
  final HistoryStats week;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.homeStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rate = week.rate;
    final done = solved != null && solved! >= total;
    return AppCard(
      key: const ValueKey('home-today'),
      onTap: onTap,
      radius: AppRadius.xl - AppSpacing.xs,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg + AppSpacing.xxs,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                _IconBubble(
                  icon: done ? Icons.emoji_events_outlined : Icons.event_note,
                  size: 52,
                  color: done ? AppColors.goldDeep : AppColors.vermilion,
                  background: done
                      ? AppColors.goldTint
                      : AppColors.vermilionTint,
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(strings.today, style: theme.textTheme.titleLarge),
                      Text(
                        solved == null
                            ? strings.todaySubtitle
                            : done
                            ? strings.todayDone
                            : strings.todayProgress(solved!, total),
                        key: const ValueKey('home-today-progress'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (solved != null)
                  _ProgressDots(done: solved!, total: total)
                else
                  const _Chevron(),
              ],
            ),
          ),
          Container(
            key: const ValueKey('home-status'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg + AppSpacing.xxs,
              AppSpacing.sm + AppSpacing.xxs,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            color: scheme.surfaceContainerLow,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.local_fire_department_rounded,
                    size: 20,
                    color: streakDays > 0 ? AppColors.streak : scheme.outline,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            streakDays > 0
                                ? strings.streak(streakDays)
                                : strings.noStreak,
                            key: const ValueKey('home-streak'),
                            style: theme.textTheme.titleSmall,
                          ),
                          if (bestDays > 0)
                            Text(
                              strings.bestStreak(bestDays),
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                      Text(
                        rate == null
                            ? strings.weekNone
                            : strings.weekAccuracy(
                                (rate * 100).round(),
                                week.correct,
                                week.answered,
                              ),
                        key: const ValueKey('home-week'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 3 問のうち解いた数の丸。
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$done / $total',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < total; i++)
              Container(
                margin: const EdgeInsets.only(left: AppSpacing.xs + 1),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < done ? scheme.primary : Colors.transparent,
                  border: Border.all(
                    color: i < done ? scheme.primary : scheme.outlineVariant,
                    width: 2,
                  ),
                ),
                child: i < done
                    ? Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: scheme.onPrimary,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// 補助の小さなタイル（手入力・履歴など）。
class _MiniTile extends StatelessWidget {
  const _MiniTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.md + AppSpacing.xxs,
      ),
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 26),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({
    required this.icon,
    this.size = 40,
    this.color,
    this.background,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.5, color: color ?? AppColors.jadeDeep),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: Theme.of(context).colorScheme.outline,
  );
}
