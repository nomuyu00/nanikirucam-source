import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// ブランドのモチーフ: 扇形に少し広げた牌（Home のヒーロー・Onboarding の挿絵）。
///
/// 牌は白い縁と影を付けて、実物の牌のように見せる。[highlight] の位置の牌は
/// 少し持ち上げて朱の縁を付ける（「切る牌」の暗示）。
class TileFan extends StatelessWidget {
  const TileFan({
    super.key,
    this.labels = const ['3m', '4p', '7z', '5s', '1z'],
    this.tileWidth = 34,
    this.spread = 8,
    this.highlight,
  });

  final List<String> labels;
  final double tileWidth;

  /// 隣どうしの角度（度）。
  final double spread;

  /// 持ち上げて朱の縁を付ける牌の位置。
  final int? highlight;

  double get _tileHeight => tileWidth * 1.34;
  double get _step => tileWidth * 0.8;

  /// 扇全体の大きさ。
  Size get size =>
      Size(_step * (labels.length - 1) + tileWidth * 1.6, _tileHeight * 1.45);

  @override
  Widget build(BuildContext context) {
    final n = labels.length;
    final box = size;
    final half = (n - 1) / 2;
    return ExcludeSemantics(
      child: SizedBox(
        width: box.width,
        height: box.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < n; i++)
              Positioned(
                left: tileWidth * 0.3 + _step * i,
                top:
                    (box.height - _tileHeight) / 2 +
                    (half == 0 ? 0 : math.pow((i - half) / half, 2)) *
                        tileWidth *
                        0.3 -
                    (i == highlight ? _tileHeight * 0.2 : 0),
                child: Transform.rotate(
                  angle: (i - half) * spread * math.pi / 180,
                  child: _FanTile(
                    label: labels[i],
                    width: tileWidth,
                    height: _tileHeight,
                    highlighted: i == highlight,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FanTile extends StatelessWidget {
  const _FanTile({
    required this.label,
    required this.width,
    required this.height,
    required this.highlighted,
  });

  final String label;
  final double width;
  final double height;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.tileFace,
        borderRadius: BorderRadius.circular(width * 0.16),
        border: Border.all(
          color: highlighted ? AppColors.vermilion : AppColors.ivoryDeep,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: TileImage(label, width: width * 0.8),
    );
  }
}
