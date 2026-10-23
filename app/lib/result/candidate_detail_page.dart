import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/detail_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/result/result_providers.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/result/widgets/thirteen_view.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 候補の詳細（仕様 6.9）。打牌後の 13 枚、受け入れ、役の確度と成立させる牌、
/// 想定打点、上がりやすさ、（Pro）良形率・2 段階先・受け入れ牌ごとの変化・リーチ判断、理由。
///
/// 無料は役名・打点の目安・上がりやすさの高中低・理由 1 行まで。Pro の項目は鍵
/// （Paywall `candidateLocked`）。上位 3 件より下の候補は無料では開けない。
class CandidateDetailPage extends ConsumerWidget {
  const CandidateDetailPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.resultStrings;
    final args = context.routeArgs<CandidateDetailArgs>();
    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.candidateTitle)),
        body: Center(child: Text(s.noHand)),
      );
    }
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final async = ref.watch(
      analysisReportProvider(AnalysisRequest(args.input, deep: pro)),
    );
    return Scaffold(
      key: const ValueKey('candidate-detail-page'),
      appBar: AppBar(title: Text(s.candidateTitle)),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const LoadingState(),
        error: (_, _) => EmptyState.error(message: s.analysisFailed),
        data: (report) => _body(context, report, args, pro),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AnalysisReport report,
    CandidateDetailArgs args,
    bool pro,
  ) {
    final s = context.resultStrings;
    final c = candidateOf(report, args.discardId);
    if (c == null) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        message: s.candidateMissing,
      );
    }
    final free = visibleCandidates(report, args.axis, pro: false);
    if (!pro && !free.any((x) => x.discardId == c.discardId)) {
      return EmptyState(
        key: const ValueKey('candidate-locked'),
        icon: Icons.lock_outline,
        message: s.candidateLockedBody,
        action: ProLock(label: s.candidateTitle),
      );
    }
    return CandidateDetailBody(
      report: report,
      candidate: c,
      input: args.input,
      pro: pro,
      footer: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: FilledButton.icon(
          key: const ValueKey('detail-explanation'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          ),
          onPressed: () => Navigator.of(context).pushNamed(
            Routes.explanation,
            arguments: CandidateDetailArgs(
              input: args.input,
              discardId: c.discardId,
              axis: args.axis,
            ),
          ),
          icon: const Icon(Icons.menu_book_outlined),
          label: Text(s.openExplanation),
        ),
      ),
    );
  }
}

/// 候補の詳細の中身。結論（切る牌・軸の順位・理由 1 行）→ 数字で見る（受け入れ・
/// 上がりやすさ・打点・良形率）→ くわしく（切ったあとの手・受け入れ牌・役・打点の内訳・
/// Pro の項目・理由）の順に、要点を先に置く。
class CandidateDetailBody extends StatelessWidget {
  const CandidateDetailBody({
    super.key,
    required this.report,
    required this.candidate,
    required this.input,
    required this.pro,
    this.footer,
  });

  final AnalysisReport report;
  final DiscardCandidate candidate;
  final HandInput input;
  final bool pro;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final d = context.detailStrings;
    final common = context.commonStrings;
    final text = ReasonText(context.lang);
    final theme = Theme.of(context);
    final c = candidate;
    final reason = text.oneLine(c, report.candidates);

    return ListView(
      key: const ValueKey('candidate-detail-list'),
      padding: AppSpacing.page,
      children: [
        DetailConclusionCard(
          report: report,
          candidate: c,
          reason: reason.isEmpty ? null : reason,
        ),
        SectionHeader(d.evidence),
        _StatGrid(
          tiles: [
            _Stat(
              label: s.drawsTitle,
              value: d.ukeireValue(c.ukeire.kinds, c.ukeire.total),
              sub: s.shantenChange(
                shantenChangeOf(report, c),
                common.shanten(c.shantenAfter),
              ),
            ),
            _Stat(
              label: s.winEaseTitle,
              value: pro
                  ? formatPercent(c.winEase)
                  : s.winEaseLevel(winEaseLevel(c.winEase)),
            ),
            _Stat(
              label: s.pointsTitle,
              value: pro
                  ? (c.rankingMedian <= 0
                        ? s.noPoints
                        : formatPoints(c.rankingMedian))
                  : formatPointsLevel(c, s, dealer: input.dealer),
            ),
            _Stat(
              label: s.goodShapeTitle,
              value: pro && c.goodShapeRate != null
                  ? formatPercent(c.goodShapeRate!)
                  : null,
              locked: !pro,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
            0,
          ),
          child: Text(s.winEaseNote, style: theme.textTheme.bodySmall),
        ),
        SectionHeader(d.details),
        DetailSection(
          title: s.handAfter,
          icon: Icons.back_hand_outlined,
          child: HandView(
            input: handAfterDiscard(input, c.discardId),
            showDora: true,
            maxTileWidth: 34,
          ),
        ),
        DetailSection(
          title: s.ukeireTiles,
          icon: Icons.download_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TileCountStrip(counts: c.ukeire.tiles, tileWidth: 24),
              const SizedBox(height: AppSpacing.md),
              if (pro && c.twoStep != null)
                TwoStepList(twoStep: c.twoStep!)
              else if (!pro)
                ProLock(label: s.perDrawTitle),
            ],
          ),
        ),
        DetailSection(
          title: s.yakuTitle,
          icon: Icons.emoji_events_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.yaku.isEmpty) Text(s.noYakuProspect),
              Wrap(
                spacing: AppSpacing.xs + AppSpacing.xxs,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                children: [
                  for (final y in c.yaku) YakuChip(prospect: y, pro: pro),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              if (pro)
                const ConfidenceLegend()
              else if (c.yaku.isNotEmpty)
                ProLock(label: s.lockedYaku),
            ],
          ),
        ),
        DetailSection(
          title: s.pointsTitle,
          icon: Icons.paid_outlined,
          child: pro
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PointsBar(
                      label: c.riichiPoints == null ? null : s.dama,
                      range: c.points,
                    ),
                    if (c.riichiPoints != null)
                      PointsBar(
                        label: s.riichiIncluded,
                        range: c.riichiPoints!,
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(s.pointsNote, style: theme.textTheme.bodySmall),
                  ],
                )
              : Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(formatPointsLevel(c, s, dealer: input.dealer)),
                    ProLock(label: s.lockedRange),
                  ],
                ),
        ),
        if (pro) ...[
          if (c.goodShapeRate != null)
            DetailSection(
              title: s.goodShapeTitle,
              icon: Icons.auto_awesome_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatPercent(c.goodShapeRate!),
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(s.goodShapeHelp, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          if (c.twoStepAverage != null)
            DetailSection(
              title: s.twoStepTitle,
              icon: Icons.stairs_outlined,
              child: Text(
                s.twoStepAverage(c.twoStepAverage!.toStringAsFixed(1)),
              ),
            ),
          if (c.riichi != null)
            DetailSection(
              title: s.riichiAdviceTitle,
              icon: Icons.flag_outlined,
              child: RiichiAdviceView(advice: c.riichi!),
            ),
        ] else
          DetailSection(
            title: '${s.goodShapeTitle}・${s.twoStepTitle}',
            icon: Icons.auto_awesome_outlined,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ProLock(
                label:
                    '${s.goodShapeTitle}・${s.twoStepTitle}・${s.riichiAdviceTitle}',
              ),
            ),
          ),
        if (pro)
          DetailSection(
            title: s.reasonTitle,
            icon: Icons.lightbulb_outline,
            child: ReasonList(candidate: c, all: report.candidates),
          ),
        ?footer,
      ],
    );
  }
}

/// 結論のカード（Result の結論カードと同じ見せ方: 牌の面に朱の枠、「切る」は朱）。
/// 切る牌・軸の 1 位のバッジ・3 軸の順位・理由 1 行。候補の詳細と解説で使う。
class DetailConclusionCard extends StatelessWidget {
  const DetailConclusionCard({
    super.key,
    required this.report,
    required this.candidate,
    this.reason,
  });

  final AnalysisReport report;
  final DiscardCandidate candidate;

  /// 理由 1 行（無ければ出さない）。
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final d = context.detailStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = candidate;
    final label = tileLabelOfId(c.discardId);
    final badges = bestAxesOf(report, c.discardId);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg + AppSpacing.xxs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.jadeDeep.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.conclusion,
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.tileFace,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: AppColors.vermilion, width: 2),
                ),
                child: TileImage(
                  label,
                  width: 44,
                  semanticLabel: common.tileName(label),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  s.detailTitle(common.tileName(label)),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs + AppSpacing.xxs,
            runSpacing: AppSpacing.xs + AppSpacing.xxs,
            children: [
              for (final a in badges) AxisBadge(axis: a),
              for (final a in kAxisOrder)
                TagLabel(
                  '${s.axis(a)} '
                  '${c.rankByAxis[a] == null ? s.notRanked : s.rankLabel(c.rankByAxis[a]!)}',
                  color: scheme.outline,
                ),
            ],
          ),
          if (reason != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(reason!, style: theme.textTheme.bodyLarge),
          ],
        ],
      ),
    );
  }
}

class _Stat {
  const _Stat({
    required this.label,
    required this.value,
    this.sub,
    this.locked = false,
  });

  final String label;
  final String? value;
  final String? sub;
  final bool locked;
}

/// 数字の要約（2 列の小さなカード）。
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.tiles});

  final List<_Stat> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: AppSpacing.sm));
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _StatTile(stat: tiles[i])),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: i + 1 < tiles.length
                    ? _StatTile(stat: tiles[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final _Stat stat;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xxs,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (stat.locked)
            Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: AppColors.goldDeep,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  s.proOnly,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.goldDeep,
                  ),
                ),
              ],
            )
          else
            Text(stat.value ?? s.noPoints, style: theme.textTheme.titleMedium),
          if (stat.sub != null)
            Text(stat.sub!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 見出しつきの段落（カード）。
class DetailSection extends StatelessWidget {
  const DetailSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
            child,
          ],
        ),
      ),
    );
  }
}

/// 想定打点のレンジを最小〜中央〜最大の帯で見せる（Pro）。
class PointsBar extends StatelessWidget {
  const PointsBar({super.key, required this.range, this.label});

  final PointRange range;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = Text.rich(
      TextSpan(
        children: [
          if (label != null)
            TextSpan(
              text: '$label  ',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          TextSpan(
            text: formatRange(range, s),
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
    if (range.max <= 0 || range.max == range.min) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: value,
      );
    }
    final position = (range.median - range.min) / (range.max - range.min);
    const marker = 14.0;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          value,
          const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: marker,
                width: width,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (marker - 6) / 2,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              scheme.primaryContainer,
                              scheme.primary.withValues(alpha: 0.55),
                            ],
                          ),
                          borderRadius: AppRadius.pillAll,
                        ),
                      ),
                    ),
                    Positioned(
                      left: (width - marker) * position.clamp(0.0, 1.0),
                      top: 0,
                      child: Container(
                        width: marker,
                        height: marker,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: scheme.surfaceContainerLowest,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 2 段階先の受け入れ牌ごとの変化（Pro）。進む牌を先に、改良の牌を後に。
class TwoStepList extends StatelessWidget {
  const TwoStepList({super.key, required this.twoStep, this.showTitle = true});

  final TwoStep twoStep;

  /// 見出し（受け入れ牌ごとの変化）を出す。見出しつきの段落の中では出さない。
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final text = ReasonText(context.lang);
    final theme = Theme.of(context);
    final draws = [
      ...twoStep.draws.where((d) => d.progress),
      ...twoStep.draws.where((d) => !d.progress),
    ];
    if (draws.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('two-step-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle) Text(s.perDrawTitle, style: theme.textTheme.titleSmall),
        if (twoStep.average != null)
          Text(
            s.twoStepAverage(twoStep.average!.toStringAsFixed(1)),
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: AppSpacing.xs),
        for (final d in draws)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs + AppSpacing.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TileImage(tileLabelOfId(d.tileId), width: 22),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    d.progress
                        ? s.drawThen(
                            text.tile(d.tileId),
                            text.tiles(d.discards),
                            common.shanten(d.shantenAfter),
                            d.ukeireAfter,
                          )
                        : s.improveThen(
                            text.tile(d.tileId),
                            text.tiles(d.discards),
                            d.ukeireAfter,
                          ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: d.progress
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 理由を「選ぶ理由」と「注意点」に分けて文で並べる（Pro）。
class ReasonList extends StatelessWidget {
  const ReasonList({super.key, required this.candidate, required this.all});

  final DiscardCandidate candidate;
  final List<DiscardCandidate> all;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final text = ReasonText(context.lang);
    final theme = Theme.of(context);
    final choose = candidate.reasons.where((r) => !r.tag.isCaution).toList();
    final caution = candidate.reasons.where((r) => r.tag.isCaution).toList();
    final comparison = text.comparison(candidate, all, standalone: true);
    return Column(
      key: const ValueKey('reason-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (choose.isEmpty && caution.isEmpty && comparison == null)
          Text(s.reasonsEmpty),
        for (final r in choose)
          _ReasonLine(
            icon: Icons.check_circle_rounded,
            text: text.sentence(r),
            color: AppColors.success,
          ),
        if (comparison != null)
          _ReasonLine(
            icon: Icons.compare_arrows_rounded,
            text: comparison,
            color: theme.colorScheme.primary,
          ),
        if (caution.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            s.cautionTitle,
            style: theme.textTheme.titleSmall?.copyWith(
              color: AppColors.caution,
            ),
          ),
          for (final r in caution)
            _ReasonLine(
              icon: Icons.warning_amber_rounded,
              text: text.sentence(r),
              color: AppColors.caution,
            ),
        ],
      ],
    );
  }
}

class _ReasonLine extends StatelessWidget {
  const _ReasonLine({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs + AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
