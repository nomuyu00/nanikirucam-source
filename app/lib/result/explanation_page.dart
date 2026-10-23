import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/detail_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/candidate_detail_page.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/result/result_providers.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/result/widgets/thirteen_view.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 解説（仕様 6.9 の Pro の詳細）: ブロック分解、理由の全文、受け入れ牌ごとの変化と
/// 2 段階先、3 軸の答えとの比較、リーチ判断、役の確度と成立条件。
///
/// Pro でなければ鍵の画面。動画広告（[RewardKind.explanation]）を最後まで見ると、
/// この手だけ 1 回（アプリを閉じるまで）詳しい解析で見られる。または Paywall
/// （`explanationLocked`）。
class ExplanationPage extends ConsumerStatefulWidget {
  const ExplanationPage({super.key});

  @override
  ConsumerState<ExplanationPage> createState() => _ExplanationPageState();
}

class _ExplanationPageState extends ConsumerState<ExplanationPage> {
  bool _logged = false;
  bool _showingVideo = false;

  Future<void> _watchVideo(HandInput input) async {
    final gate = ref.read(rewardedGateProvider);
    setState(() => _showingVideo = true);
    final rewarded = await gate.show(RewardKind.explanation);
    if (!mounted) return;
    setState(() => _showingVideo = false);
    if (!rewarded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.resultStrings.videoUnavailable)),
      );
      return;
    }
    // rewarded_granted は RewardedGate が記録する。
    ref.read(explanationUnlocksProvider.notifier).unlock(input);
  }

  void _logOpened(bool pro) {
    if (_logged) return;
    _logged = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(appAnalyticsProvider)
            .logEvent(
              AnalyticsEvent.explanationOpened,
              parameters: {
                'gate': pro ? 'pro' : 'free',
                'screen': 'explanation',
                if (!pro) 'reward': 'explanation',
              },
            ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final args = context.routeArgs<CandidateDetailArgs>();
    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.explanationTitle)),
        body: Center(child: Text(s.noHand)),
      );
    }
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    ref.watch(explanationUnlocksProvider);
    final unlocked =
        args.input.isAnalyzable &&
        ref.read(explanationUnlocksProvider.notifier).isUnlocked(args.input);
    final Widget body;
    if (!pro && !unlocked) {
      body = _locked(context, args);
    } else {
      final async = ref.watch(
        analysisReportProvider(AnalysisRequest(args.input, deep: true)),
      );
      body = async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (_, _) => EmptyState.error(message: s.analysisFailed),
        data: (report) {
          _logOpened(pro);
          return _content(context, report, args);
        },
      );
    }
    return Scaffold(
      key: const ValueKey('explanation-page'),
      appBar: AppBar(title: Text(s.explanationTitle)),
      body: body,
    );
  }

  Widget _locked(BuildContext context, CandidateDetailArgs args) {
    final s = context.resultStrings;
    final theme = Theme.of(context);
    final gate = ref.watch(rewardedGateProvider);
    final ready = gate.isReady(RewardKind.explanation) && !_showingVideo;
    return Center(
      key: const ValueKey('explanation-locked'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.goldTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.menu_book_rounded,
                  size: 34,
                  color: AppColors.goldDeep,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              s.explanationLockedTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.explanationLockedBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(
              key: const ValueKey('explanation-paywall'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.lgAll,
                ),
              ),
              onPressed: () => Navigator.of(context).pushNamed(
                Routes.paywall,
                arguments: const PaywallArgs(
                  trigger: PaywallTrigger.explanationLocked,
                ),
              ),
              child: Text(s.seePro),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('explanation-watch-video'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: ready && args.input.isAnalyzable
                  ? () => _watchVideo(args.input)
                  : null,
              icon: const Icon(Icons.ondemand_video),
              label: Text(s.watchVideo),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AnalysisReport report,
    CandidateDetailArgs args,
  ) {
    final s = context.resultStrings;
    final d = context.detailStrings;
    final c = candidateOf(report, args.discardId);
    if (c == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        message: s.candidateMissing,
      );
    }
    return ListView(
      key: const ValueKey('explanation-list'),
      padding: AppSpacing.page,
      children: [
        // 結論 → 根拠（理由・ブロック・3 軸との比較）→ 詳細（リーチ判断・受け入れ牌ごと・役）。
        DetailConclusionCard(report: report, candidate: c),
        SectionHeader(d.reasoning),
        DetailSection(
          title: s.choiceReasons,
          icon: Icons.lightbulb_outline,
          child: ReasonList(candidate: c, all: report.candidates),
        ),
        if (report.blocks.isNotEmpty)
          DetailSection(
            title: s.blocksTitle,
            icon: Icons.grid_view_rounded,
            child: BlocksView(blocks: report.blocks, discardId: c.discardId),
          ),
        DetailSection(
          title: s.compareTitle,
          icon: Icons.compare_arrows_rounded,
          child: _CompareTable(report: report, candidate: c),
        ),
        SectionHeader(d.details),
        if (c.riichi != null)
          DetailSection(
            title: s.riichiAdviceTitle,
            icon: Icons.flag_outlined,
            child: RiichiAdviceView(advice: c.riichi!),
          ),
        if (c.twoStep != null)
          DetailSection(
            title: s.perDrawTitle,
            icon: Icons.download_rounded,
            child: TwoStepList(twoStep: c.twoStep!, showTitle: false),
          ),
        DetailSection(
          title: s.yakuTitle,
          icon: Icons.emoji_events_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: AppSpacing.xs + AppSpacing.xxs,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                children: [
                  if (c.yaku.isEmpty) Text(s.noYakuProspect),
                  for (final y in c.yaku) YakuChip(prospect: y, pro: true),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                s.legendTitle,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const ConfidenceLegend(),
            ],
          ),
        ),
      ],
    );
  }
}

/// ブロック分解（面子・搭子・対子・孤立）。切る牌を含むブロックを朱の枠で強調する
/// （Result の「切る」と同じ朱）。役割は文字と色で示す。
class BlocksView extends StatelessWidget {
  const BlocksView({super.key, required this.blocks, this.discardId});

  final List<Block> blocks;
  final int? discardId;

  static Color _roleColor(BlockRole role, ColorScheme scheme) => switch (role) {
    BlockRole.meld => AppColors.success,
    BlockRole.ryanmen => AppColors.info,
    BlockRole.kanchan || BlockRole.penchan => AppColors.caution,
    BlockRole.pair || BlockRole.head => AppColors.axisBalance,
    BlockRole.isolated => scheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      key: const ValueKey('blocks-view'),
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final b in blocks)
          Builder(
            builder: (context) {
              final hasDiscard = b.tileIds.contains(discardId);
              final color = _roleColor(b.role, scheme);
              return Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xs + AppSpacing.xxs,
                  AppSpacing.xs + AppSpacing.xxs,
                  AppSpacing.xs + AppSpacing.xxs,
                  AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: hasDiscard
                      ? AppColors.vermilionTint
                      : scheme.surfaceContainerLow,
                  border: Border.all(
                    color: hasDiscard
                        ? AppColors.vermilion
                        : scheme.outlineVariant,
                    width: hasDiscard ? 2 : 1,
                  ),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final id in b.tileIds)
                          TileImage(tileLabelOfId(id), width: 24),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          s.blockRole(b.role),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hasDiscard
                                ? AppColors.vermilion
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// この候補と 3 軸の 1 位の比較（受け入れ・想定打点の中央値・上がりやすさ）。
/// この候補の行を朱の淡い面で強調し、数字は右に揃える。
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.report, required this.candidate});

  final AnalysisReport report;
  final DiscardCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final d = context.detailStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <(String, DiscardCandidate, bool)>[
      (d.thisCandidate, candidate, true),
      for (final axis in kAxisOrder)
        for (final id in bestOf(report, axis).take(1))
          if (candidateOf(report, id) case final best?)
            (s.badge(axis), best, false),
    ];
    final headerStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final numberStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget cell(Widget child, {Alignment alignment = Alignment.centerRight}) =>
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Align(alignment: alignment, child: child),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          key: const ValueKey('compare-table'),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: const {
            0: FlexColumnWidth(1.35),
            1: FlexColumnWidth(0.7),
            2: FlexColumnWidth(),
            3: FlexColumnWidth(1.1),
            4: FlexColumnWidth(),
          },
          border: TableBorder(
            horizontalInside: BorderSide(color: scheme.outlineVariant),
          ),
          children: [
            TableRow(
              children: [
                cell(const SizedBox.shrink(), alignment: Alignment.centerLeft),
                cell(
                  Text(s.discard, style: headerStyle),
                  alignment: Alignment.center,
                ),
                cell(Text(s.drawsTitle, style: headerStyle)),
                cell(Text(s.pointsTitle, style: headerStyle)),
                cell(Text(s.winEaseTitle, style: headerStyle)),
              ],
            ),
            for (final (title, c, mine) in rows)
              TableRow(
                decoration: mine
                    ? const BoxDecoration(color: AppColors.vermilionTint)
                    : null,
                children: [
                  cell(
                    Text(
                      title,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: mine ? AppColors.vermilion : scheme.onSurface,
                      ),
                    ),
                    alignment: Alignment.centerLeft,
                  ),
                  cell(
                    TileImage(
                      tileLabelOfId(c.discardId),
                      width: 20,
                      semanticLabel: common.tileName(
                        tileLabelOfId(c.discardId),
                      ),
                    ),
                    alignment: Alignment.center,
                  ),
                  cell(Text('${c.ukeire.total}', style: numberStyle)),
                  cell(
                    Text(
                      c.rankingMedian <= 0
                          ? s.noPoints
                          : formatPoints(c.rankingMedian),
                      style: numberStyle,
                    ),
                  ),
                  cell(Text(formatPercent(c.winEase), style: numberStyle)),
                ],
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(d.compareNote, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
