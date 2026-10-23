import 'package:flutter/material.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

/// [NoticeCard] の調子。
enum NoticeTone { neutral, info, success, caution, danger, pro }

/// 調子ごとの（面, アイコン・見出しの色）。
({Color background, Color foreground}) noticeColors(
  BuildContext context,
  NoticeTone tone,
) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    NoticeTone.neutral => (
      background: scheme.surfaceContainerLow,
      foreground: scheme.onSurfaceVariant,
    ),
    NoticeTone.info => (
      background: scheme.primaryContainer.withValues(alpha: 0.55),
      foreground: AppColors.jadeDeep,
    ),
    NoticeTone.success => (
      background: AppColors.success.withValues(alpha: 0.09),
      foreground: AppColors.success,
    ),
    NoticeTone.caution => (
      background: AppColors.caution.withValues(alpha: 0.09),
      foreground: AppColors.caution,
    ),
    NoticeTone.danger => (
      background: scheme.errorContainer.withValues(alpha: 0.6),
      foreground: scheme.error,
    ),
    NoticeTone.pro => (
      background: AppColors.goldTint,
      foreground: AppColors.goldDeep,
    ),
  };
}

/// 短いお知らせ・注意のカード（アイコン＋見出し＋本文＋任意の操作）。
class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.message,
    this.title,
    this.icon,
    this.tone = NoticeTone.neutral,
    this.action,
    this.messageKey,
  });

  final String message;
  final String? title;
  final IconData? icon;
  final NoticeTone tone;
  final Widget? action;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = noticeColors(context, tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: colors.foreground),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.foreground,
                    ),
                  ),
                Text(
                  message,
                  key: messageKey,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tone == NoticeTone.neutral
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  action!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
