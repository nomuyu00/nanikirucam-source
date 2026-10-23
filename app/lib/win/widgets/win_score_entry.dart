import 'package:flutter/material.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';

/// Result の和了形の下に置く「役と点数を詳しく見る」（Pro）。
///
/// Pro は和了の点数画面（[Routes.winScore]）へ、無料は Paywall（`winScore`）へ。
class WinScoreEntry extends StatelessWidget {
  const WinScoreEntry({
    super.key,
    required this.input,
    required this.pro,
    this.source = 'result',
  });

  final HandInput input;
  final bool pro;
  final String source;

  void _open(BuildContext context) {
    final navigator = Navigator.of(context);
    if (pro) {
      navigator.pushNamed(
        Routes.winScore,
        arguments: WinScoreArgs(input: input, source: source),
      );
    } else {
      navigator.pushNamed(
        Routes.paywall,
        arguments: const PaywallArgs(trigger: PaywallTrigger.winScore),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    return AppCard(
      key: const ValueKey('result-win-score'),
      onTap: () => _open(context),
      color: pro ? null : AppColors.goldTint.withValues(alpha: 0.5),
      borderColor: pro ? null : AppColors.gold.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: pro
                  ? theme.colorScheme.primaryContainer
                  : AppColors.goldTint,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(
              Icons.calculate_outlined,
              color: pro ? AppColors.jadeDeep : AppColors.goldDeep,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs + 2,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(s.entryTitle, style: theme.textTheme.titleSmall),
                    const ProBadge(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(s.entrySubtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            pro ? Icons.chevron_right_rounded : Icons.lock_outline,
            color: pro ? theme.colorScheme.outline : AppColors.goldDeep,
          ),
        ],
      ),
    );
  }
}
