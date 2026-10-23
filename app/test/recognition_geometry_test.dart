// 流用元: reference/agari_cam/test/recognition_geometry_test.dart（2026-10-21 時点）
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';

/// 400×300 の灰色画像の (300,50)-(340,90) に赤い四角を描く。
Future<ui.Image> markerImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 400, 300),
    Paint()..color = const Color(0xFF404040),
  );
  canvas.drawRect(
    const Rect.fromLTWH(300, 50, 40, 40),
    Paint()..color = const Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  return picture.toImage(400, 300);
}

/// 入力画像中の赤い画素の外接矩形（640入力座標）。
Rect redBounds(Uint8List rgba) {
  var l = 640.0, t = 640.0, r = 0.0, b = 0.0;
  for (var y = 0; y < 640; y++) {
    for (var x = 0; x < 640; x++) {
      final i = (y * 640 + x) * 4;
      if (rgba[i] > 200 && rgba[i + 1] < 60 && rgba[i + 2] < 60) {
        if (x < l) l = x.toDouble();
        if (y < t) t = y.toDouble();
        if (x + 1 > r) r = x + 1.0;
        if (y + 1 > b) b = y + 1.0;
      }
    }
  }
  return Rect.fromLTRB(l, t, r, b);
}

void main() {
  // 写真を時計回りに q 回回したとき、赤い四角が来る位置（0〜1）。
  const expected = <int, Rect>{
    0: Rect.fromLTRB(300 / 400, 50 / 300, 340 / 400, 90 / 300),
    1: Rect.fromLTRB(210 / 300, 300 / 400, 250 / 300, 340 / 400),
    2: Rect.fromLTRB(60 / 400, 210 / 300, 100 / 400, 250 / 300),
    3: Rect.fromLTRB(50 / 300, 60 / 400, 90 / 300, 100 / 400),
  };

  for (final entry in expected.entries) {
    testWidgets('rotation ${entry.key} maps boxes back to the photo', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await markerImage();
        final service = TfliteService();
        final full = await service.renderRegion(
          image,
          entry.key,
          const Rect.fromLTWH(0, 0, 1, 1),
        );
        final mapped = full.toImageRect(redBounds(full.rgba))!;
        expect(mapped.left, closeTo(entry.value.left, 0.01));
        expect(mapped.top, closeTo(entry.value.top, 0.01));
        expect(mapped.right, closeTo(entry.value.right, 0.01));
        expect(mapped.bottom, closeTo(entry.value.bottom, 0.01));

        // 牌の列のまわりだけを拡大して描いても、同じ位置に戻る。
        double clamp(double v) => v.clamp(0.0, 1.0);
        final half = Rect.fromLTRB(
          clamp(entry.value.left - 0.15),
          clamp(entry.value.top - 0.15),
          clamp(entry.value.right + 0.15),
          clamp(entry.value.bottom + 0.15),
        );
        final zoomed = await service.renderRegion(image, entry.key, half);
        final zoomedBox = redBounds(zoomed.rgba);
        expect(
          zoomedBox.width,
          greaterThan(redBounds(full.rgba).width),
          reason: 'the half region is drawn larger',
        );
        final back = zoomed.toImageRect(zoomedBox)!;
        expect(back.left, closeTo(entry.value.left, 0.01));
        expect(back.bottom, closeTo(entry.value.bottom, 0.01));
        image.dispose();
      });
    });
  }

  testWidgets('large photos are letterboxed into the 640 input', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1920, 1080),
        Paint()..color = const Color(0xFF808080),
      );
      final image = await recorder.endRecording().toImage(1920, 1080);
      final rendered = await TfliteService().renderRegion(
        image,
        0,
        const Rect.fromLTWH(0, 0, 1, 1),
      );
      expect(rendered.rgba.length, 640 * 640 * 4);
      expect(rendered.scale, closeTo(640 / 1920, 1e-9));
      // 上下の余白は Ultralytics と同じ114の灰色。
      expect(rendered.rgba[0], 114);
      image.dispose();
    });
  });
}
