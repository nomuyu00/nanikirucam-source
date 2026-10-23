import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

/// 和了の手の表示。門前の牌を理牌して並べ、和了牌を少し離して右端に朱の枠で示す。
/// 副露は次の行に（鳴いた牌は横向き、暗槓はそのまま）。
///
/// [onTapTile] を渡すと、門前の牌をタップして和了牌を選び直せる（添字は [WinHand.tiles]）。
class WinHandView extends StatelessWidget {
  const WinHandView({
    super.key,
    required this.hand,
    this.onTapTile,
    this.maxTileWidth = 40,
    this.tileKeyPrefix = 'win-tile',
  });

  final WinHand hand;
  final ValueChanged<int>? onTapTile;
  final double maxTileWidth;
  final String tileKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    final strings = context.winStrings;
    final order = hand.displayOrder;
    final win = hand.winningTile == null ? null : hand.winIndex;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final slots = hand.tiles.length + (win == null ? 0 : 0.4);
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxTileWidth * 15;
        final tileWidth = ((available - gap - 4) / (slots < 1 ? 1 : slots))
            .clamp(14.0, maxTileWidth);

        Widget tile(int index) {
          final label = hand.tiles[index];
          final isWin = index == win;
          Widget image = TileImage(
            label,
            width: tileWidth,
            semanticLabel: common.tileName(label),
          );
          if (isWin) {
            image = DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.vermilion, width: 2.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: image,
            );
          }
          final key = ValueKey('$tileKeyPrefix-$index');
          if (onTapTile == null) return KeyedSubtree(key: key, child: image);
          return Semantics(
            button: true,
            selected: isWin,
            label:
                '${common.tileName(label)}${isWin ? ' ${strings.winningTileLabel}' : ''}',
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: () => onTapTile!(index),
              child: ExcludeSemantics(child: image),
            ),
          );
        }

        final rest = order.where((i) => i != win).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              // 和了牌の下に札があるので、牌の上端でそろえる。
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final i in rest) tile(i),
                if (win != null) ...[
                  const SizedBox(width: gap),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      tile(win),
                      const SizedBox(height: AppSpacing.xxs),
                      _WinLabel(strings.winningTileLabel, width: tileWidth),
                    ],
                  ),
                ],
              ],
            ),
            if (hand.melds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final meld in hand.melds)
                      MeldView(meld: meld, tileWidth: tileWidth * 0.9),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 和了牌の下の小さな札。
class _WinLabel extends StatelessWidget {
  const _WinLabel(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    // 牌の幅を超えない（超えると手牌の行があふれる）。文字は縮めて収める。
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      decoration: const BoxDecoration(
        color: AppColors.vermilion,
        borderRadius: AppRadius.pillAll,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}
