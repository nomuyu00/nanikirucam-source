// camera/overlay_painter.dart（写真の検出枠）を参考に、ライブ用に新規作成。
// 枠の色分け（面子＝緑、搭子＝青、孤立＝灰、おすすめ＝黄、確度低＝赤）、おすすめの牌の矢印と
// 「1萬を切る」のラベル、推論範囲（ROI）の枠を描く（仕様 6.3）。色だけに頼らず矢印と文字で示す。
import 'package:flutter/material.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';

/// オーバーレイに描く牌 1 枚。
class LiveOverlayTile {
  const LiveOverlayTile({
    required this.box,
    this.label,
    this.role,
    this.lowConfidence = false,
    this.tag,
  });

  /// 正立フレーム（＝プレビュー）に対する 0〜1 の枠。
  final Rect box;

  /// 枠の上に出す短い文字（確度の低い牌の「？」など）。
  final String? label;

  /// 役割（stable で解析済みのときだけ）。null は白の細枠。
  final LiveTileRole? role;
  final bool lowConfidence;

  /// 別解のバッジ（「高打点」など）。
  final String? tag;
}

class LiveOverlayPainter extends CustomPainter {
  LiveOverlayPainter({
    required this.tiles,
    this.highlight,
    this.highlightText,
    this.roi,
    this.showRoi = false,
    this.roiText,
    this.dimmed = false,
  });

  final List<LiveOverlayTile> tiles;

  /// おすすめの牌（[tiles] の添字）。
  final int? highlight;

  /// おすすめの牌の上に出す文字（「1萬を切る」）。
  final String? highlightText;

  /// 推論範囲（0〜1）。
  final Rect? roi;
  final bool showRoi;
  final String? roiText;

  /// 牌の枠と案内を薄く描く（手が揺れて案内を保っている間。`LiveController.adviceHeld`）。
  final bool dimmed;

  /// [dimmed] のときの不透明度。
  static const double dimmedOpacity = 0.55;

  static const Color meldColor = AppColors.liveOk;
  static const Color partialColor = AppColors.liveTaatsu;
  static const Color isolatedColor = AppColors.liveIdle;
  static const Color highlightColor = AppColors.liveRecommend;
  static const Color lowColor = AppColors.liveError;

  @override
  void paint(Canvas canvas, Size size) {
    Rect toCanvas(Rect r) => Rect.fromLTRB(
      r.left * size.width,
      r.top * size.height,
      r.right * size.width,
      r.bottom * size.height,
    );

    final roi = this.roi;
    if (showRoi && roi != null) {
      final rect = toCanvas(roi).deflate(2);
      _dashedRect(
        canvas,
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.liveTextMuted,
      );
      final text = roiText;
      if (text != null) {
        _label(
          canvas,
          text,
          Offset(rect.center.dx, rect.top + 8),
          background: AppColors.liveLabelScrim,
          below: true,
        );
      }
    }

    if (dimmed) {
      canvas.saveLayer(
        Offset.zero & size,
        Paint()..color = AppColors.camera.withValues(alpha: dimmedOpacity),
      );
    }
    for (var i = 0; i < tiles.length; i++) {
      if (i == highlight) continue;
      final t = tiles[i];
      final rect = toCanvas(t.box);
      final color = t.lowConfidence
          ? lowColor
          : switch (t.role) {
              LiveTileRole.meld => meldColor,
              LiveTileRole.partial => partialColor,
              LiveTileRole.isolated => isolatedColor,
              null => AppColors.liveTextMuted,
            };
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = t.role == null ? 1.5 : 2.5
        ..color = color;
      if (t.lowConfidence) {
        _dashedRect(canvas, rect, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          paint,
        );
      }
      final label = t.label;
      if (label != null) {
        _label(
          canvas,
          label,
          Offset(rect.center.dx, rect.bottom + 2),
          background: color.withValues(alpha: 0.85),
          below: true,
          small: true,
        );
      }
      final tag = t.tag;
      if (tag != null) {
        _label(
          canvas,
          tag,
          Offset(rect.center.dx, rect.top - 2),
          background: AppColors.liveInfoScrim,
          small: true,
        );
      }
    }

    final h = highlight;
    if (h != null && h >= 0 && h < tiles.length) {
      final t = tiles[h];
      final rect = toCanvas(t.box).inflate(3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(4)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = t.lowConfidence ? lowColor : highlightColor,
      );
      // 矢印（上から牌を指す）。
      final arrowHeight = (rect.height * 0.9).clamp(18.0, 48.0);
      final tip = Offset(rect.center.dx, rect.top - 4);
      final base = tip.dy - arrowHeight;
      final half = (rect.width * 0.45).clamp(8.0, 18.0);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - half, tip.dy - half)
        ..lineTo(tip.dx - half / 2.5, tip.dy - half)
        ..lineTo(tip.dx - half / 2.5, base)
        ..lineTo(tip.dx + half / 2.5, base)
        ..lineTo(tip.dx + half / 2.5, tip.dy - half)
        ..lineTo(tip.dx + half, tip.dy - half)
        ..close();
      canvas.drawPath(path, Paint()..color = highlightColor);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = AppColors.liveScrimStrong,
      );
      final text = highlightText;
      if (text != null) {
        _label(
          canvas,
          text,
          Offset(rect.center.dx, base - 4),
          background: highlightColor,
          foreground: AppColors.camera,
          bold: true,
          canvasWidth: size.width,
        );
      }
    }
    if (dimmed) canvas.restore();
  }

  void _label(
    Canvas canvas,
    String text,
    Offset anchor, {
    required Color background,
    Color foreground = AppColors.liveText,
    bool below = false,
    bool small = false,
    bool bold = false,
    double? canvasWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: foreground,
          fontSize: small ? 11 : 16,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const padX = 6.0;
    const padY = 3.0;
    var left = anchor.dx - tp.width / 2 - padX;
    final width = tp.width + padX * 2;
    if (canvasWidth != null) {
      left = left.clamp(
        2.0,
        (canvasWidth - width - 2).clamp(2.0, double.infinity),
      );
    }
    final top = below ? anchor.dy : anchor.dy - tp.height - padY * 2;
    final box = Rect.fromLTWH(left, top, width, tp.height + padY * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(6)),
      Paint()..color = background,
    );
    tp.paint(canvas, Offset(left + padX, top + padY));
  }

  void _dashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 6.0;
    const gap = 4.0;
    void line(Offset a, Offset b) {
      final total = (b - a).distance;
      if (total <= 0) return;
      final dir = (b - a) / total;
      for (var d = 0.0; d < total; d += dash + gap) {
        final end = d + dash > total ? total : d + dash;
        canvas.drawLine(a + dir * d, a + dir * end, paint);
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant LiveOverlayPainter old) =>
      old.tiles != tiles ||
      old.highlight != highlight ||
      old.highlightText != highlightText ||
      old.roi != roi ||
      old.showRoi != showRoi ||
      old.roiText != roiText ||
      old.dimmed != dimmed;
}
