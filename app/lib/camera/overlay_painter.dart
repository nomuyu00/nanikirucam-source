// 流用元: reference/agari_cam/lib/camera/overlay_painter.dart（2026-10-21 時点）
import 'package:flutter/material.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';

class DetectionOverlayPainter extends CustomPainter {
  final List<TileDetection> detections;
  final List<Rect> indicator; // dora indicator boxes (normalized)
  final Size imageSize; // camera preview size in logical px
  final double minConfidence;
  DetectionOverlayPainter({
    required this.detections,
    required this.imageSize,
    this.indicator = const [],
    this.minConfidence = 0.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.liveOk;
    final dashed = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.liveWarn;
    const textStyle = TextStyle(
      color: Colors.white,
      backgroundColor: AppColors.liveScrim,
      fontSize: 12,
    );
    for (final d in detections) {
      final rect = Rect.fromLTRB(
        d.box.left * size.width,
        d.box.top * size.height,
        d.box.right * size.width,
        d.box.bottom * size.height,
      );
      final color = _colorForLabel(d.label);
      final paint = (d.score >= minConfidence ? basePaint : dashed)
        ..color = color;
      final p = d.score >= minConfidence ? paint : dashed;
      if (p == dashed) {
        _drawDashedRect(canvas, rect, dashed);
      } else {
        canvas.drawRect(rect, paint);
      }
      final label = '${d.label} ${(d.score * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.left, rect.top - tp.height - 2));
      if (d.isRed) {
        final badge = Rect.fromLTWH(rect.right - 16, rect.top - 16, 16, 16);
        canvas.drawRect(badge, Paint()..color = AppColors.liveError);
      }
    }

    // Draw dora indicator regions in amber
    final indPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = AppColors.liveRecommend;
    for (final r in indicator) {
      final rect = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      canvas.drawRect(rect, indPaint);
    }
  }

  Color _colorForLabel(String label) {
    final l = label.toLowerCase();
    // suit color mapping: m=black, p=red, s=green, honors=white
    if (l.contains('m')) return Colors.black;
    if (l.contains('p')) return AppColors.liveError;
    if (l.contains('s')) return AppColors.liveOk;
    // honors
    return Colors.white;
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashWidth = 6.0;
    const gap = 4.0;
    // top
    for (double x = rect.left; x < rect.right; x += dashWidth + gap) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(
          x + dashWidth > rect.right ? rect.right : x + dashWidth,
          rect.top,
        ),
        paint,
      );
    }
    // bottom
    for (double x = rect.left; x < rect.right; x += dashWidth + gap) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(
          x + dashWidth > rect.right ? rect.right : x + dashWidth,
          rect.bottom,
        ),
        paint,
      );
    }
    // left
    for (double y = rect.top; y < rect.bottom; y += dashWidth + gap) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(
          rect.left,
          y + dashWidth > rect.bottom ? rect.bottom : y + dashWidth,
        ),
        paint,
      );
    }
    // right
    for (double y = rect.top; y < rect.bottom; y += dashWidth + gap) {
      canvas.drawLine(
        Offset(rect.right, y),
        Offset(
          rect.right,
          y + dashWidth > rect.bottom ? rect.bottom : y + dashWidth,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.indicator != indicator ||
        oldDelegate.imageSize != imageSize;
  }
}
