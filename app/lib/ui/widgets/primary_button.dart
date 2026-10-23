import 'package:flutter/material.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

/// 画面の主ボタン（大）。横幅いっぱい・高さ 56 以上。1 画面に 1 つを目安にする。
///
/// [busy] のときは押せず、文字の代わりに読み込み中の輪を出す。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  /// 淡い色の主ボタン（同じ画面に、より強い主ボタンがあるとき）。
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(56),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      textStyle: Theme.of(context).textTheme.titleMedium,
    );
    final Widget child = busy
        ? const SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 22),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    final onTap = busy ? null : onPressed;
    return tonal
        ? FilledButton.tonal(style: style, onPressed: onTap, child: child)
        : FilledButton(style: style, onPressed: onTap, child: child);
  }
}
