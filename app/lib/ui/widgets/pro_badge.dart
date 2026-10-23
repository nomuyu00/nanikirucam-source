import 'package:flutter/material.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

/// 「PRO」の小さなバッジ（ゴールド）。Pro 限定の機能・Pro の状態に添える。
class ProBadge extends StatelessWidget {
  const ProBadge({super.key, this.label = 'PRO', this.filled = true});

  final String label;

  /// true はゴールドの面に白抜き、false は淡い面にゴールドの文字。
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: filled ? AppColors.gold : AppColors.goldTint,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: filled ? Colors.white : AppColors.goldDeep,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
