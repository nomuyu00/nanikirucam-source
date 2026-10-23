import 'package:flutter/material.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 手牌の見た目: 牌を並べ、ツモ牌を少し離して金枠で示し、副露は横向きの牌で右に並べる
/// （設計書 8 章）。共有カードと問題の一覧で使う。
///
/// 収まらないときは枠に合わせて縮める。ドラ表示牌は [HandPanel] には含めない（[DoraRow]）。
class HandPanel extends StatelessWidget {
  const HandPanel({
    super.key,
    required this.input,
    this.tileWidth = 24,
    this.background = true,
    this.highlightTsumo = true,
  });

  final HandInput input;

  /// 縮める前の牌の幅（14 枚が 1 行に並ぶように、枠の幅に合わせて縮む）。
  final double tileWidth;

  /// 暗い下地を敷くか。
  final bool background;

  final bool highlightTsumo;

  @override
  Widget build(BuildContext context) {
    final tsumo = input.tsumoTile;
    final concealed = tsumo == null ? input.tiles : input.tilesWithoutTsumo;
    final gap = tileWidth * 0.45;
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final tile in concealed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.6),
            child: TileImage(tile, width: tileWidth),
          ),
        if (tsumo != null) ...[
          SizedBox(width: gap),
          Container(
            key: const ValueKey('hand-panel-tsumo'),
            decoration: BoxDecoration(
              border: highlightTsumo
                  ? Border.all(color: kCardGold, width: 1.5)
                  : null,
              borderRadius: BorderRadius.circular(3),
            ),
            child: TileImage(tsumo, width: tileWidth),
          ),
        ],
        for (final meld in input.melds) ...[
          SizedBox(width: gap),
          for (var i = 0; i < meld.tiles.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0.6),
              child: TileImage(
                meld.tiles[i],
                width: tileWidth,
                sideways: i == 0,
              ),
            ),
        ],
      ],
    );
    final scaled = FittedBox(fit: BoxFit.scaleDown, child: row);
    if (!background) return scaled;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: scaled,
    );
  }
}

/// ドラ表示牌を小さく並べる行（なければ何も描かない）。
class DoraRow extends StatelessWidget {
  const DoraRow({
    super.key,
    required this.indicators,
    required this.label,
    this.tileWidth = 16,
  });

  final List<String> indicators;
  final String label;
  final double tileWidth;

  @override
  Widget build(BuildContext context) {
    if (indicators.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.white70),
        ),
        const SizedBox(width: 6),
        for (final tile in indicators)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.5),
            child: TileImage(tile, width: tileWidth),
          ),
      ],
    );
  }
}
