// 流用元: reference/agari_cam/lib/ui/widgets/tile_image.dart（2026-10-21 時点）
// 改修: 牌画像のパスを assets/tiles/ に変更。
import 'package:flutter/material.dart';

const _kanjiNumbers = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
const _honors = ['東', '南', '西', '北', '白', '發', '中'];

/// 牌ラベル（'5m' / '0p' = 赤5 / '7z' = 中）を同梱画像のパスに変換する。
String? tileAssetPath(String label) {
  if (label.length < 2) return null;
  final num = label[0];
  final suit = label[1];
  if (suit == 'z') {
    final value = int.tryParse(num);
    if (value == null || value < 1 || value > 7) return null;
    return 'assets/tiles/${_honors[value - 1]}.png';
  }
  final suitName = switch (suit) {
    'm' => '萬',
    'p' => '筒',
    's' => '索',
    _ => null,
  };
  if (suitName == null) return null;
  if (num == '0') return 'assets/tiles/赤五$suitName.png';
  final value = int.tryParse(num);
  if (value == null || value < 1 || value > 9) return null;
  return 'assets/tiles/${_kanjiNumbers[value - 1]}$suitName.png';
}

/// 牌選択などで使う読みやすい名前（例: 赤5萬 / 中）。
String tileDisplayName(String label, {bool english = false}) {
  if (label.length < 2) return label;
  final num = label[0];
  final suit = label[1];
  if (suit == 'z') {
    final value = int.tryParse(num) ?? 0;
    if (value < 1 || value > 7) return label;
    if (english) {
      return const [
        'East',
        'South',
        'West',
        'North',
        'White',
        'Green',
        'Red',
      ][value - 1];
    }
    return _honors[value - 1];
  }
  final suitName = english
      ? switch (suit) {
          'm' => 'Man',
          'p' => 'Pin',
          's' => 'Sou',
          _ => suit,
        }
      : switch (suit) {
          'm' => '萬',
          'p' => '筒',
          's' => '索',
          _ => suit,
        };
  if (num == '0') return english ? 'Red 5 $suitName' : '赤5$suitName';
  return english ? '$num $suitName' : '$num$suitName';
}

/// 全38種（赤5を含む）を萬・筒・索・字の順で返す。
List<String> allTileLabels() => [
  for (final suit in const ['m', 'p', 's']) ...[
    for (var n = 1; n <= 9; n++) '$n$suit',
    '0$suit',
  ],
  for (var n = 1; n <= 7; n++) '${n}z',
];

class TileImage extends StatelessWidget {
  const TileImage(
    this.label, {
    super.key,
    this.width = 36,
    this.sideways = false,
    this.semanticLabel,
  });

  final String label;
  final double width;
  // 鳴いた牌のように横向きに倒して描く。
  final bool sideways;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final height = width * 4 / 3;
    final path = tileAssetPath(label);
    final Widget image = path == null
        ? Container(
            width: width,
            height: height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(label, style: TextStyle(fontSize: width * 0.35)),
          )
        : Image.asset(
            path,
            width: width,
            height: height,
            fit: BoxFit.contain,
            semanticLabel: semanticLabel ?? tileDisplayName(label),
          );
    if (!sideways) return image;
    return RotatedBox(quarterTurns: 1, child: image);
  }
}
