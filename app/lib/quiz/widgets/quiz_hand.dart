import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// クイズの手牌（仕様 6.7）。指で押しやすいよう、牌 1 枚の当たり判定を 44pt 以上にする。
///
/// 14 枚を 1 列に並べると 1 枚が 25pt 前後になって押し間違えるので、1 列に入らなければ
/// 2 段に折り返す。折り返す位置は真ん中に近い色（萬・筒・索・字）の切れ目にして、
/// 形が読みやすいようにする。ツモ牌は 2 段目の右端に少し離して置く。
///
/// 選んだ牌は持ち上げて朱の枠と「切る」の札を付ける（Result の結論カードの「切る」と同じ朱）。
/// 牌のキーは `<tileKeyPrefix>-<添字>`（添字は [HandInput.tiles] の添字）。
class QuizHand extends StatelessWidget {
  const QuizHand({
    super.key,
    required this.input,
    required this.selectedIndex,
    required this.onTapTile,
    this.tileKeyPrefix = 'quiz-tile',
  });

  /// 理牌済み（[HandInput.normalized]）の手。
  final HandInput input;
  final int? selectedIndex;

  /// null なら押せない（答えを送っている間）。
  final ValueChanged<int>? onTapTile;
  final String tileKeyPrefix;

  /// 1 枚の枠（当たり判定）の幅の上限と下限（論理ピクセル）。
  static const double maxSlot = 52;
  static const double minSlot = 30;

  /// 1 段に並べる枚数の上限（これを超えたら 2 段にする）。
  static const int maxPerRow = 8;

  /// ツモ牌の前の隙間（枠の何枚分か）。
  static const double tsumoGap = 0.35;

  @override
  Widget build(BuildContext context) {
    final tsumo = input.hasTsumo ? input.tsumoIndex : null;
    final order = [
      for (var i = 0; i < input.tiles.length; i++)
        if (i != tsumo) i,
    ];
    final rows = splitQuizRows([
      for (final i in order) input.tiles[i],
    ], hasTsumo: tsumo != null);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxSlot * maxPerRow;
        // いちばん長い段に合わせて枠の幅を決める。
        var widest = 0.0;
        for (var r = 0; r < rows.length; r++) {
          final last = r == rows.length - 1;
          final slots = rows[r] + (last && tsumo != null ? 1 + tsumoGap : 0.0);
          widest = math.max(widest, slots);
        }
        final slot = (available / math.max(widest, 1)).clamp(minSlot, maxSlot);

        final children = <Widget>[];
        var start = 0;
        for (var r = 0; r < rows.length; r++) {
          final last = r == rows.length - 1;
          final indices = order.sublist(start, start + rows[r]);
          start += rows[r];
          children.add(
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final i in indices) _tile(context, i, slot),
                if (last && tsumo != null) ...[
                  SizedBox(width: slot * tsumoGap),
                  _tile(context, tsumo, slot),
                ],
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...children,
            if (input.melds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final meld in input.melds)
                      MeldView(meld: meld, tileWidth: slot * 0.62),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, int index, double slot) {
    final common = context.commonStrings;
    final label = input.tiles[index];
    final selected = index == selectedIndex;
    return _QuizTile(
      key: ValueKey('$tileKeyPrefix-$index'),
      label: label,
      semanticLabel: common.tileName(label),
      slot: slot,
      selected: selected,
      onTap: onTapTile == null ? null : () => onTapTile!(index),
    );
  }
}

/// [tiles]（ツモ牌を除いた門前の牌、理牌済み）を何枚ずつの段に分けるか。
///
/// 1 段（ツモ牌を含めて [QuizHand.maxPerRow] 枚以下）に入ればそのまま。入らなければ 2 段で、
/// 1 段目の枚数は 2 段目（ツモ牌を含む）も上限に収まる範囲で、色の切れ目のうち真ん中に
/// 近いところ（無ければ真ん中）にする。
List<int> splitQuizRows(List<String> tiles, {required bool hasTsumo}) {
  final n = tiles.length;
  final extra = hasTsumo ? 1 : 0;
  if (n + extra <= QuizHand.maxPerRow) return [n];
  final low = math.max(1, n + extra - QuizHand.maxPerRow);
  final high = math.min(QuizHand.maxPerRow, n - 1);
  final middle = (n + extra) / 2;
  int? best;
  for (var k = low; k <= high; k++) {
    final boundary = _suit(tiles[k - 1]) != _suit(tiles[k]);
    if (!boundary) continue;
    if (best == null || (k - middle).abs() < (best - middle).abs()) best = k;
  }
  final first = best ?? middle.floor().clamp(low, high);
  return [first, n - first];
}

String _suit(String label) => label.length < 2 ? label : label[1];

class _QuizTile extends StatelessWidget {
  const _QuizTile({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.slot,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final double slot;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final theme = Theme.of(context);
    final tileWidth = slot - 4;
    final tileHeight = tileWidth * 4 / 3;
    // 持ち上げる高さと、その上に出す「切る」の札の分を空けておく。
    final lift = (tileHeight * 0.22).clamp(8.0, 14.0);
    const tagHeight = 18.0;
    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, selected ? -lift : 0, 0),
      decoration: BoxDecoration(
        color: AppColors.tileFace,
        borderRadius: BorderRadius.circular(tileWidth * 0.14),
        border: Border.all(
          color: selected ? AppColors.vermilion : Colors.transparent,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: selected
                ? AppColors.vermilion.withValues(alpha: 0.35)
                : AppColors.ink.withValues(alpha: 0.12),
            blurRadius: selected ? 10 : 3,
            offset: Offset(0, selected ? 5 : 1.5),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: TileImage(label, width: tileWidth - 7),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: slot,
          // 当たり判定は枠いっぱい（幅 slot × 高さ 牌 + 持ち上げ + 札）。
          height: tileHeight + lift + tagHeight + 4,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(bottom: 2, child: tile),
              if (selected)
                Positioned(
                  bottom: tileHeight + lift + 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: const BoxDecoration(
                      color: AppColors.vermilion,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Text(
                      s.discard,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontSize: 10.5,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
