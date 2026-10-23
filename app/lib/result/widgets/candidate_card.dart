import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 候補 1 つ（仕様 4.6 の 1 ブロック）。
///
/// いつも見せるのは「順位・切る牌・軸のバッジ・理由の 1 行・シャンテン数の変化と受け入れ枚数」。
/// 受け入れ牌・狙える役・想定打点・上がりやすさ・良形率は「詳しく」で開く（キー
/// `candidate-more-<id>`）。カード全体のタップは候補の詳細ページ（[onTap]）。
/// 無料／Pro の出し分けは仕様 5 章（役は名前だけ、打点は目安、上がりやすさは高中低、
/// 良形率・2 段階先は鍵）。
class CandidateCard extends StatefulWidget {
  const CandidateCard({
    super.key,
    required this.report,
    required this.candidate,
    required this.axis,
    required this.pro,
    required this.dealer,
    this.chosen = false,
    this.onTap,
    this.initiallyExpanded = false,
  });

  final AnalysisReport report;
  final DiscardCandidate candidate;
  final StrategyAxis axis;
  final bool pro;
  final bool dealer;

  /// クイズで選んだ牌。
  final bool chosen;
  final VoidCallback? onTap;

  /// 詳しい項目を最初から開いておく。
  final bool initiallyExpanded;

  @override
  State<CandidateCard> createState() => _CandidateCardState();
}

class _CandidateCardState extends State<CandidateCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final text = ReasonText(context.lang);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = widget.candidate;
    final report = widget.report;
    final label = tileLabelOfId(c.discardId);
    final rank = c.rankByAxis[widget.axis];
    final recommended = rank == 1;
    final badges = bestAxesOf(report, c.discardId);
    final change = shantenChangeOf(report, c);
    final reason = text.oneLine(c, report.candidates);

    return Card(
      key: ValueKey('candidate-${c.discardId}'),
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 1),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(
          color: recommended ? scheme.primary : scheme.outlineVariant,
          width: recommended ? 1.6 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md + AppSpacing.xxs,
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RankMark(rank: rank, notRanked: s.notRanked),
                  const SizedBox(width: AppSpacing.md),
                  TileImage(
                    label,
                    width: 32,
                    semanticLabel: common.tileName(label),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '${s.discard} ${common.tileName(label)}',
                              style: theme.textTheme.titleMedium,
                            ),
                            for (final a in badges)
                              AxisBadge(
                                key: ValueKey('badge-${c.discardId}-${a.name}'),
                                axis: a,
                              ),
                            if (widget.chosen) TagLabel(s.yourChoice),
                          ],
                        ),
                        if (reason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xxs),
                            child: Text(
                              reason,
                              key: ValueKey('reason-${c.discardId}'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xxs),
                          child: Text(
                            '${s.shantenChange(change, common.shanten(c.shantenAfter))}'
                            '  ·  ${s.ukeire(c.ukeire.kinds, c.ukeire.total)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onTap != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: scheme.outline,
                      ),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: ValueKey('candidate-more-${c.discardId}'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    textStyle: theme.textTheme.labelMedium,
                  ),
                  iconAlignment: IconAlignment.end,
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(_expanded ? s.closeDetail : s.openDetail),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Padding(
                        padding: const EdgeInsets.only(
                          right: AppSpacing.xs,
                          bottom: AppSpacing.md,
                        ),
                        child: _Details(
                          report: report,
                          candidate: c,
                          pro: widget.pro,
                          dealer: widget.dealer,
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 順位の丸。1 位は朱で塗る（「切る牌」の強調）。
class _RankMark extends StatelessWidget {
  const _RankMark({required this.rank, required this.notRanked});

  final int? rank;
  final String notRanked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final first = rank == 1;
    return Container(
      width: 28,
      height: 28,
      margin: const EdgeInsets.only(top: AppSpacing.xs + 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: first ? AppColors.vermilion : scheme.surfaceContainerHigh,
      ),
      child: Text(
        rank == null ? '–' : '$rank',
        semanticsLabel: rank == null
            ? notRanked
            : context.resultStrings.rankLabel(rank!),
        style: theme.textTheme.labelLarge?.copyWith(
          color: first ? Colors.white : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 開いたときの項目（受け入れ牌・役・打点・上がりやすさ・良形率）。
class _Details extends StatelessWidget {
  const _Details({
    required this.report,
    required this.candidate,
    required this.pro,
    required this.dealer,
  });

  final AnalysisReport report;
  final DiscardCandidate candidate;
  final bool pro;
  final bool dealer;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final c = candidate;
    final yaku = pickYaku(c);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.ukeire.tiles.isNotEmpty)
            InfoLine(
              label: s.drawsTitle,
              child: TileCountStrip(counts: c.ukeire.tiles, tileWidth: 18),
            ),
          InfoLine(
            label: s.yakuTitle,
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (yaku.isEmpty) Text(s.noYakuProspect),
                for (final y in yaku) YakuChip(prospect: y, pro: pro),
                if (!pro && yaku.isNotEmpty) ProLock(label: s.lockedYaku),
              ],
            ),
          ),
          InfoLine(
            label: s.pointsTitle,
            child: pro
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.riichiPoints == null ? '' : '${s.dama} '}'
                        '${formatRange(c.points, s)}',
                        key: ValueKey('points-${c.discardId}'),
                      ),
                      if (c.riichiPoints != null)
                        Text(
                          '${s.riichiIncluded} '
                          '${formatRange(c.riichiPoints!, s)}',
                        ),
                    ],
                  )
                : Wrap(
                    spacing: AppSpacing.sm - 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        formatPointsLevel(c, s, dealer: dealer),
                        key: ValueKey('points-${c.discardId}'),
                      ),
                      ProLock(label: s.lockedRange),
                    ],
                  ),
          ),
          InfoLine(
            label: s.winEaseTitle,
            child: Text(
              pro
                  ? formatPercent(c.winEase)
                  : s.winEaseLevel(winEaseLevel(c.winEase)),
              key: ValueKey('ease-${c.discardId}'),
            ),
          ),
          if (pro && c.goodShapeRate != null)
            InfoLine(
              label: s.goodShapeTitle,
              child: Text(formatPercent(c.goodShapeRate!)),
            ),
          if (!pro)
            InfoLine(
              label: s.goodShapeTitle,
              child: Align(
                alignment: Alignment.centerLeft,
                child: ProLock(label: '${s.goodShapeTitle}・${s.twoStepTitle}'),
              ),
            ),
        ],
      ),
    );
  }
}

/// [HandInput] を持たない画面からも使える、候補の打牌の名前。
String discardName(BuildContext context, int id) =>
    context.commonStrings.tileName(tileLabelOfId(id));
