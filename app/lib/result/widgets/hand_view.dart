import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/quiz_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 手牌の表示（Quiz・Result・候補の詳細・履歴で共通。仕様 6.7）。
///
/// - 門前の牌を左から並べ、ツモ牌（[HandInput.tsumoIndex]）は少し離して右端に置く。
/// - 副露は次の行に、鳴いた牌（先頭）を横に倒して並べる。
/// - [showDora] ならドラ表示牌と、それが示すドラを添える。
///
/// [input] は理牌済み（[HandInput.normalized]）を渡すと見やすい。[onTapTile] を渡すと
/// 門前の牌（添字は [HandInput.tiles] の添字）をタップできる。
class HandView extends StatelessWidget {
  const HandView({
    super.key,
    required this.input,
    this.onTapTile,
    this.selectedIndex,
    this.highlightIds = const {},
    this.maxTileWidth = 40,
    this.showDora = true,
    this.tileKeyPrefix,
  });

  final HandInput input;
  final ValueChanged<int>? onTapTile;

  /// 選んだ牌（[HandInput.tiles] の添字）。少し持ち上げて枠を付ける。
  final int? selectedIndex;

  /// 強調する牌（牌 id）。打牌の候補や待ちなど。
  final Set<int> highlightIds;
  final double maxTileWidth;
  final bool showDora;

  /// テスト用のキーの接頭辞（`<prefix>-<添字>`）。
  final String? tileKeyPrefix;

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    final tsumo = input.hasTsumo ? input.tsumoIndex : null;
    final order = [
      for (var i = 0; i < input.tiles.length; i++)
        if (i != tsumo) i,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 10.0;
        final slots = input.tiles.length + (tsumo == null ? 0 : 0.4);
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxTileWidth * 15;
        final width = (available - gap) / (slots < 1 ? 1 : slots);
        final tileWidth = width.clamp(14.0, maxTileWidth);

        Widget tile(int index) {
          final label = input.tiles[index];
          final selected = index == selectedIndex;
          final highlighted = highlightIds.contains(tileIdFromLabel(label));
          Widget image = TileImage(
            label,
            width: tileWidth,
            semanticLabel: common.tileName(label),
          );
          if (selected || highlighted) {
            image = DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(
                  color: selected ? AppColors.vermilion : AppColors.gold,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: image,
            );
          }
          image = AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            transform: Matrix4.translationValues(0, selected ? -8 : 0, 0),
            child: image,
          );
          final key = tileKeyPrefix == null
              ? null
              : ValueKey('$tileKeyPrefix-$index');
          if (onTapTile == null) return KeyedSubtree(key: key, child: image);
          return Semantics(
            button: true,
            selected: selected,
            label: common.tileName(label),
            child: GestureDetector(
              key: key,
              behavior: HitTestBehavior.opaque,
              onTap: () => onTapTile!(index),
              child: image,
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final i in order) tile(i),
                  if (tsumo != null) ...[
                    const SizedBox(width: gap),
                    tile(tsumo),
                  ],
                ],
              ),
            ),
            if (input.melds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final meld in input.melds)
                      MeldView(meld: meld, tileWidth: tileWidth),
                  ],
                ),
              ),
            if (showDora && input.doraIndicators.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: DoraView(indicators: input.doraIndicators),
              ),
          ],
        );
      },
    );
  }
}

/// 副露 1 組。鳴いた牌（先頭）を横に倒す。暗槓はそのまま並べる。
class MeldView extends StatelessWidget {
  const MeldView({super.key, required this.meld, this.tileWidth = 28});

  final MeldInput meld;
  final double tileWidth;

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < meld.tiles.length; i++)
          TileImage(
            meld.tiles[i],
            width: tileWidth,
            sideways: meld.isOpen && i == 0,
            semanticLabel: common.tileName(meld.tiles[i]),
          ),
      ],
    );
  }
}

/// ドラ表示牌と、それが示すドラ（「ドラ表示 3萬 → ドラ 4萬」）。
class DoraView extends StatelessWidget {
  const DoraView({super.key, required this.indicators, this.tileWidth = 22});

  final List<String> indicators;
  final double tileWidth;

  @override
  Widget build(BuildContext context) {
    final strings = context.quizStrings;
    final common = context.commonStrings;
    final style = Theme.of(context).textTheme.bodySmall;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(strings.doraIndicator, style: style),
        for (final label in indicators)
          TileImage(
            label,
            width: tileWidth,
            semanticLabel: common.tileName(label),
          ),
        const Icon(Icons.arrow_right_alt, size: 18),
        Text(strings.dora, style: style),
        for (final label in indicators)
          TileImage(
            doraFromIndicator(label),
            width: tileWidth,
            semanticLabel: common.tileName(doraFromIndicator(label)),
          ),
      ],
    );
  }
}

/// 牌 id の並びを、残り枚数つきで小さく並べる（受け入れ・待ちの一覧）。
class TileCountStrip extends StatelessWidget {
  const TileCountStrip({super.key, required this.counts, this.tileWidth = 22});

  /// 牌 id → 枚数（id の順に並べる）。
  final Map<int, int> counts;
  final double tileWidth;

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    final ids = counts.keys.toList()..sort();
    final style = Theme.of(context).textTheme.labelSmall;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final id in ids)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TileImage(
                tileLabelOfId(id),
                width: tileWidth,
                semanticLabel:
                    '${common.tileName(tileLabelOfId(id))} ${common.tileCount(counts[id]!)}',
              ),
              Text('${counts[id]}', style: style),
            ],
          ),
      ],
    );
  }
}

/// 牌 id の並びを小さく並べる（成立させる牌など）。
class TileIdRow extends StatelessWidget {
  const TileIdRow({super.key, required this.ids, this.tileWidth = 20});

  final List<int> ids;
  final double tileWidth;

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: [
        for (final id in ids)
          TileImage(
            tileLabelOfId(id),
            width: tileWidth,
            semanticLabel: common.tileName(tileLabelOfId(id)),
          ),
      ],
    );
  }
}

/// [input] から [discardId] を 1 枚切った 13 枚（候補の詳細の「切ったあとの手」）。
///
/// 同じ牌が複数あれば赤5でない方を切る（エンジンの `afterDiscard` と同じ）。ツモ牌は
/// 手に入れて理牌し直す。
HandInput handAfterDiscard(HandInput input, int discardId) {
  final tiles = [...input.tiles];
  var index = -1;
  for (var i = 0; i < tiles.length; i++) {
    if (tileIdFromLabel(tiles[i]) != discardId) continue;
    if (index < 0 || tiles[index].startsWith('0')) index = i;
  }
  if (index >= 0) tiles.removeAt(index);
  return input.copyWith(tiles: tiles, tsumoIndex: null).normalized();
}
