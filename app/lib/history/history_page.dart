import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/history_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 履歴・弱点（仕様 6.11、設計書 5.1 `history_v1`）。
///
/// 解析・クイズの記録を新しい順に並べ、タップで Result を開き直す（履歴には足さない）。
/// 無料は直近 [kFreeHistoryCount] 件、Pro は全件と弱点分析（軸ごとの正解率・間違えた
/// 問題に多い理由タグ）。最下部にバナー（無料のみ）。
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.historyStrings;
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final async = ref.watch(historyProvider);
    final hasEntries = async.valueOrNull?.isNotEmpty ?? false;
    return Scaffold(
      key: const ValueKey('history-page'),
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          if (hasEntries)
            IconButton(
              key: const ValueKey('history-clear'),
              tooltip: s.clear,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () => _confirmClear(context, ref),
            ),
        ],
      ),
      body: async.when(
        loading: () => const LoadingState(),
        error: (_, _) => EmptyState.error(message: s.loadFailed),
        data: (entries) =>
            _list(context, entries, pro, ref.watch(clockProvider)()),
      ),
      bottomNavigationBar: pro
          ? null
          : const SafeArea(
              top: false,
              child: AdBannerSlot(placement: AdPlacement.historyBanner),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final s = context.historyStrings;
    final common = context.commonStrings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(s.clearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(common.cancel),
          ),
          TextButton(
            key: const ValueKey('history-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.clearAction),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(historyProvider.notifier).clear();
  }

  Widget _list(
    BuildContext context,
    List<HistoryEntry> entries,
    bool pro,
    DateTime now,
  ) {
    final s = context.historyStrings;
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.history_rounded,
        message: s.empty,
        messageKey: const ValueKey('history-empty'),
      );
    }
    final visible = pro ? entries : entries.take(kFreeHistoryCount).toList();
    // 日付ごとに見出しを付けてまとめる（新しい順のまま）。
    final children = <Widget>[_WeaknessCard(entries: entries, pro: pro)];
    String? day;
    for (final e in visible) {
      final key = _dayKey(e.createdAt);
      if (key != day) {
        day = key;
        children.add(SectionHeader(s.dayHeader(e.createdAt, now)));
      }
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _HistoryTile(entry: e),
        ),
      );
    }
    if (entries.length > visible.length) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Center(
            child: ProLock(
              key: const ValueKey('history-more-locked'),
              trigger: PaywallTrigger.historyLocked,
              label: s.moreLocked(
                entries.length - visible.length,
                kFreeHistoryCount,
              ),
            ),
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('history-list'),
      padding: AppSpacing.page,
      children: children,
    );
  }
}

String _dayKey(DateTime t) => '${t.year}-${t.month}-${t.day}';

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry});

  final HistoryEntry entry;

  void _open(BuildContext context) {
    if (entry.pending) {
      // 未解析（撮るだけモード）: 修正画面で確かめてから Quiz / Result へ。写真は無い。
      // 無料枠は認識したときに使っているので、ここでは使わない。
      Navigator.of(context).pushNamed(
        Routes.recognition,
        arguments: RecognitionArgs(
          draft: RecognitionDraft(
            labels: entry.input.tiles,
            tsumoIndex: entry.input.tsumoIndex,
          ),
          base: entry.input,
          historyId: entry.id,
        ),
      );
      return;
    }
    final choice = entry.userChoice;
    Navigator.of(context).pushNamed(
      Routes.result,
      arguments: ResultArgs(
        input: entry.input,
        chosenDiscardId: choice == null ? null : tileIdFromLabel(choice),
        chosenAxis: entry.axis,
        problemId: entry.problemId,
        saveToHistory: false,
        source: 'history',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.historyStrings;
    final rs = context.resultStrings;
    final common = context.commonStrings;
    final text = ReasonText(context.lang);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (IconData icon, Color color, String status) = entry.pending
        ? (Icons.photo_camera_outlined, AppColors.info, s.pending)
        : switch (entry.correct) {
            true => (Icons.check_circle_rounded, AppColors.success, s.correct),
            false => (Icons.cancel_rounded, AppColors.danger, s.incorrect),
            null => (
              Icons.remove_circle_outline,
              AppColors.outline,
              s.notAnswered,
            ),
          };
    final axis = entry.axis ?? kDefaultAxis;
    final best = entry.best[axis] ?? const <String>[];
    final t = entry.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}';
    final tags = [
      for (final code in entry.reasonTags.take(2)) text.tagLabelOfCode(code),
    ];

    // 結果の行: あなたの選択と、判定した軸の答え（牌の絵つき）。
    final Widget result;
    if (entry.pending) {
      result = Row(
        children: [
          const Icon(Icons.touch_app_outlined, size: 18, color: AppColors.info),
          const SizedBox(width: AppSpacing.xs + AppSpacing.xxs),
          Expanded(
            child: Text(s.pendingSummary, style: theme.textTheme.bodyMedium),
          ),
        ],
      );
    } else if (!entry.input.isFourteen) {
      result = Text(
        s.thirteenTiles(common.shanten(entry.shanten ?? 0)),
        style: theme.textTheme.bodyMedium,
      );
    } else {
      final choice = entry.userChoice;
      result = Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs + AppSpacing.xxs,
        children: [
          if (choice != null)
            _TilePill(
              text: s.yourChoice(common.tileName(choice)),
              labels: [choice],
              color: entry.correct == null ? scheme.outline : color,
            ),
          if (best.isNotEmpty)
            _TilePill(
              text: s.answer(
                rs.axis(axis),
                best.map(common.tileName).join('・'),
              ),
              labels: best,
              color: scheme.outlineVariant,
            ),
        ],
      );
    }

    return Material(
      key: ValueKey('history-${entry.id}'),
      color: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(
          color: entry.pending ? color : scheme.outlineVariant,
          width: entry.pending ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm + AppSpacing.xxs,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs + AppSpacing.xxs,
                      AppSpacing.xxs,
                      AppSpacing.sm,
                      AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          status,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    time,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const Spacer(),
                  if (entry.answered) AxisBadge(axis: axis),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              HandView(
                input: entry.input.normalized(),
                maxTileWidth: 24,
                showDora: false,
                highlightIds: {
                  if (entry.userChoice != null)
                    tileIdFromLabel(entry.userChoice!),
                },
              ),
              const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
              result,
              if (tags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
                Text(tags.join(' / '), style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 「あなた: 8筒」「バランスの答え: 8筒」の小さな札（牌の絵つき）。
class _TilePill extends StatelessWidget {
  const _TilePill({
    required this.text,
    required this.labels,
    required this.color,
  });

  final String text;
  final List<String> labels;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xxs,
        AppSpacing.sm + AppSpacing.xxs,
        AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: color),
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final label in labels.take(2))
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xxs),
              child: TileImage(label, width: 16),
            ),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 弱点分析（Pro）: 軸ごとの正解率と、間違えた問題に多い理由タグ。
class _WeaknessCard extends StatelessWidget {
  const _WeaknessCard({required this.entries, required this.pro});

  final List<HistoryEntry> entries;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final s = context.historyStrings;
    final rs = context.resultStrings;
    final text = ReasonText(context.lang);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = Row(
      children: [
        Icon(Icons.insights_rounded, size: 20, color: scheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(s.weaknessTitle, style: theme.textTheme.titleSmall),
        ),
        if (!pro) const ProBadge(),
      ],
    );
    if (!pro) {
      return AppCard(
        key: const ValueKey('history-weakness-locked'),
        color: AppColors.goldTint.withValues(alpha: 0.45),
        borderColor: AppColors.gold.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            title,
            const SizedBox(height: AppSpacing.sm),
            ProLock(
              trigger: PaywallTrigger.historyLocked,
              label: s.weaknessLocked,
            ),
          ],
        ),
      );
    }
    final stats = HistoryStats.of(entries);
    return AppCard(
      key: const ValueKey('history-weakness'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: AppSpacing.md),
          if (stats.answered == 0)
            Text(s.weaknessEmpty, style: theme.textTheme.bodyMedium)
          else ...[
            for (final axis in kAxisOrder)
              if (stats.byAxis[axis] case final a?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.axisAccuracy(
                          rs.axis(axis),
                          a.correct,
                          a.answered,
                          (a.correct * 100 / a.answered).round(),
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ClipRRect(
                        borderRadius: AppRadius.pillAll,
                        child: LinearProgressIndicator(
                          minHeight: 6,
                          value: a.answered == 0 ? 0 : a.correct / a.answered,
                          color: axisColor(axis),
                          backgroundColor: axisColor(
                            axis,
                          ).withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
            if (stats.missedTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(s.missedTagsTitle, style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs + AppSpacing.xxs),
              Wrap(
                spacing: AppSpacing.xs + AppSpacing.xxs,
                runSpacing: AppSpacing.xs + AppSpacing.xxs,
                children: [
                  for (final t in stats.missedTags.take(3))
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm + AppSpacing.xxs,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.07),
                        border: Border.all(
                          color: AppColors.danger.withValues(alpha: 0.35),
                        ),
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(
                        s.tagCount(text.tagLabelOfCode(t.code), t.count),
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}
