import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

/// 速さ・打点・バランスの切り替え（仕様 4.1）。キーは `<prefix>-<軸>`。
class AxisSelector extends StatelessWidget {
  const AxisSelector({
    super.key,
    required this.axis,
    required this.onChanged,
    this.keyPrefix = 'axis',
  });

  final StrategyAxis axis;
  final ValueChanged<StrategyAxis> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<StrategyAxis>(
        showSelectedIcon: false,
        segments: [
          for (final a in kAxisOrder)
            ButtonSegment(
              value: a,
              label: Text(s.axis(a), key: ValueKey('$keyPrefix-${a.name}')),
              tooltip: s.axisHint(a),
            ),
        ],
        selected: {axis},
        onSelectionChanged: (value) {
          if (value.isNotEmpty && value.first != axis) onChanged(value.first);
        },
      ),
    );
  }
}

/// 軸の色（バッジと答えの一覧）。色だけに頼らず文字も必ず添える。
Color axisColor(StrategyAxis axis) => switch (axis) {
  StrategyAxis.speed => AppColors.axisSpeed,
  StrategyAxis.points => AppColors.axisPoints,
  StrategyAxis.balance => AppColors.axisBalance,
};

/// 「最速」「高打点」「バランス」のバッジ。
class AxisBadge extends StatelessWidget {
  const AxisBadge({super.key, required this.axis});

  final StrategyAxis axis;

  @override
  Widget build(BuildContext context) {
    final color = axisColor(axis);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        context.resultStrings.badge(axis),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// 小さな文字のラベル（「あなたの選択」「目安」など）。
class TagLabel extends StatelessWidget {
  const TagLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: c),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c),
      ),
    );
  }
}

/// 役の確度の色（確定＝緑、濃厚＝青、狙える＝橙、消える＝赤。仕様 4.3）。
Color confidenceColor(YakuConfidence c) => switch (c) {
  YakuConfidence.certain => AppColors.confidenceCertain,
  YakuConfidence.likely => AppColors.confidenceLikely,
  YakuConfidence.possible => AppColors.confidencePossible,
  YakuConfidence.lost => AppColors.confidenceLost,
};

/// 役 1 つのチップ。
///
/// Pro は「タンヤオ（濃厚）」「平和（狙える: 4索・7索を引けば）」「三色同順（消える）」を
/// 確度の色で出す。無料は役名だけ（仕様 5 章）。
class YakuChip extends StatelessWidget {
  const YakuChip({super.key, required this.prospect, required this.pro});

  final YakuProspect prospect;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final text = ReasonText(context.lang);
    final y = prospect;
    var name = text.yaku(y.yaku);
    if (y.yaku == YakuId.dora && (y.count ?? 0) > 0) {
      name = s.doraCount(y.count!);
    }
    final String label;
    final Color color;
    if (!pro) {
      label = name;
      color = Theme.of(context).colorScheme.outline;
    } else {
      final conf = s.confidence(y.confidence);
      final tiles = y.enablingTiles.isEmpty
          ? ''
          : ': ${s.enabling(text.tiles(y.enablingTiles))}';
      label = text.isEnglish ? '$name ($conf$tiles)' : '$name（$conf$tiles）';
      color = confidenceColor(y.confidence);
    }
    final lost = pro && y.confidence == YakuConfidence.lost;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: pro
            ? color.withValues(alpha: 0.08)
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        border: Border.all(
          color: pro
              ? color.withValues(alpha: 0.7)
              : color.withValues(alpha: 0.5),
        ),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: pro ? color : Theme.of(context).colorScheme.onSurface,
          fontWeight: pro ? FontWeight.w700 : FontWeight.w500,
          decoration: lost ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }
}

/// Pro 限定の項目の鍵（タップで Paywall。仕様 5 章）。
class ProLock extends StatelessWidget {
  const ProLock({
    super.key,
    required this.label,
    this.trigger = PaywallTrigger.candidateLocked,
    this.onTap,
  });

  final String label;
  final PaywallTrigger trigger;

  /// 既定は Paywall を開く。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.smAll,
      onTap:
          onTap ??
          () => Navigator.of(
            context,
          ).pushNamed(Routes.paywall, arguments: PaywallArgs(trigger: trigger)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 14, color: AppColors.goldDeep),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                '$label（${context.resultStrings.proOnly}）',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AppColors.goldDeep),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「見出し: 値」の 1 行。
class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 84, child: Text(label, style: style)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 確度ラベルの定義（仕様 15 章「確度ラベルの定義を画面で説明」）。
class ConfidenceLegend extends StatelessWidget {
  const ConfidenceLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in YakuConfidence.values)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    s.confidence(c),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: confidenceColor(c),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    s.confidenceHelp(c),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
