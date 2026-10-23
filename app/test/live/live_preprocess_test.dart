import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';
import 'package:nanikiru_cam/ml/live_preprocess.dart';
import 'package:nanikiru_cam/ml/live_yolo_decoder.dart';

/// 画素ごとに違う色の BGRA（R = x*40+10, G = y*40+10, B = 200）。
LiveFrame bgraFrame(int w, int h, {int padding = 0}) {
  final stride = w * 4 + padding;
  final bytes = Uint8List(stride * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * stride + x * 4;
      bytes[i] = 200; // B
      bytes[i + 1] = y * 40 + 10; // G
      bytes[i + 2] = x * 40 + 10; // R
      bytes[i + 3] = 255;
    }
  }
  return LiveFrame(
    format: LiveFrameFormat.bgra8888,
    width: w,
    height: h,
    planes: [LivePlane(bytes: bytes, bytesPerRow: stride)],
  );
}

/// YUV420（3 面、U/V は画素間隔 [uvPixel]）。Y・U・V はそれぞれ一定。
LiveFrame yuvFrame(
  int w,
  int h, {
  required int y,
  required int u,
  required int v,
  int uvPixel = 1,
  int yPadding = 0,
}) {
  final yStride = w + yPadding;
  final cw = w ~/ 2;
  final ch = h ~/ 2;
  final uvStride = cw * uvPixel;
  return LiveFrame(
    format: LiveFrameFormat.yuv420,
    width: w,
    height: h,
    planes: [
      LivePlane(
        bytes: Uint8List(yStride * h)..fillRange(0, yStride * h, y),
        bytesPerRow: yStride,
      ),
      LivePlane(
        bytes: Uint8List(uvStride * ch)..fillRange(0, uvStride * ch, u),
        bytesPerRow: uvStride,
        bytesPerPixel: uvPixel,
      ),
      LivePlane(
        bytes: Uint8List(uvStride * ch)..fillRange(0, uvStride * ch, v),
        bytesPerRow: uvStride,
        bytesPerPixel: uvPixel,
      ),
    ],
  );
}

List<int> px(Uint8List out, int size, int x, int y) {
  final i = (y * size + x) * 3;
  return [out[i], out[i + 1], out[i + 2]];
}

void main() {
  group('回転', () {
    test('センサーの向きで回す回数（縦向き固定）', () {
      expect(
        liveQuarterTurns(sensorOrientation: 90, width: 1280, height: 720),
        1,
      );
      expect(
        liveQuarterTurns(sensorOrientation: 270, width: 1280, height: 720),
        3,
      );
      expect(
        liveQuarterTurns(sensorOrientation: 90, width: 720, height: 1280),
        0,
        reason: 'すでに縦長なら回さない',
      );
      expect(
        liveQuarterTurns(sensorOrientation: 0, width: 1280, height: 720),
        1,
      );
    });

    // 正立フレームの (u, v) が、生フレームのどの画素か。
    (int, int) source(int turns, int u, int v, int w, int h) => switch (turns) {
      0 => (u, v),
      1 => (v, h - 1 - u),
      2 => (w - 1 - u, h - 1 - v),
      _ => (w - 1 - v, u),
    };

    for (final turns in [0, 1, 2, 3]) {
      test('$turns 回（時計回り 90°）回した画素が正しい', () {
        const w = 4;
        const h = 2;
        final frame = bgraFrame(w, h, padding: 8);
        // 入力 4×4、ROI はフレーム全体、等倍で描く。
        final t = LiveInputTransform.compute(
          rawWidth: w,
          rawHeight: h,
          quarterTurns: turns,
          roi: const Rect.fromLTRB(0, 0, 1, 1),
          inputSize: 4,
        );
        final out = Uint8List(4 * 4 * 3);
        preprocessLiveFrame(frame, t, out);
        expect(t.scaleX, 1);
        expect(t.scaleY, 1);
        for (var v = 0; v < t.uprightHeight; v++) {
          for (var u = 0; u < t.uprightWidth; u++) {
            final (x, y) = source(turns, u, v, w, h);
            expect(
              px(out, 4, t.outLeft + u, t.outTop + v),
              [x * 40 + 10, y * 40 + 10, 200],
              reason: 'upright ($u,$v) ← raw ($x,$y)',
            );
          }
        }
        // 余白は灰色。
        if (t.outLeft > 0) {
          expect(px(out, 4, 0, 0), [114, 114, 114]);
        }
      });
    }
  });

  group('推論範囲とレターボックス', () {
    test('縦向き 720p は横幅いっぱいの正方形を 640 に縮める', () {
      final t = LiveInputTransform.compute(
        rawWidth: 1280,
        rawHeight: 720,
        quarterTurns: 1,
      );
      expect(t.uprightWidth, 720);
      expect(t.uprightHeight, 1280);
      expect(t.roiTop, 280);
      expect(t.roiWidth, 720);
      expect(t.outWidth, 640);
      expect(t.outHeight, 640);
      expect(t.roiNormalized.top, closeTo(0.21875, 1e-9));
      final full = t.toUprightNormalized(const Rect.fromLTRB(0, 0, 640, 640))!;
      expect(full.left, closeTo(0, 1e-9));
      expect(full.top, closeTo(0.21875, 1e-9));
      expect(full.right, closeTo(1, 1e-9));
      expect(full.bottom, closeTo(0.78125, 1e-9));
      // 中央の牌 1 枚（64px）は正立フレームの幅の 1 割。
      final tile = t.toUprightNormalized(
        const Rect.fromLTWH(288, 288, 64, 80),
      )!;
      expect(tile.width, closeTo(0.1, 1e-9));
      expect(tile.center.dx, closeTo(0.5, 1e-9));
    });

    test('横長の ROI は上下に灰色の余白', () {
      final t = LiveInputTransform.compute(
        rawWidth: 1280,
        rawHeight: 720,
        quarterTurns: 1,
        roi: const Rect.fromLTRB(0, 0.4, 1, 0.6),
      );
      expect(t.outWidth, 640);
      expect(t.outHeight, (720 * 0.2 / 720 * 1280 * 640 / 720).round());
      expect(t.outTop, greaterThan(0));
      final box = t.toUprightNormalized(Rect.fromLTWH(0, 0, 640, t.outTop - 1));
      expect(box, isNull, reason: '余白だけの枠は捨てる');
    });

    test('解像度が変わっても縮小後の画素はフレームの範囲内', () {
      final frame = bgraFrame(64, 36);
      final t = LiveInputTransform.compute(
        rawWidth: 64,
        rawHeight: 36,
        quarterTurns: 1,
        inputSize: 32,
      );
      final out = Uint8List(32 * 32 * 3);
      expect(() => preprocessLiveFrame(frame, t, out), returnsNormally);
    });
  });

  group('YUV → RGB', () {
    test('灰色（U=V=128）はそのまま、輝度は Y/255', () {
      final frame = yuvFrame(8, 4, y: 128, u: 128, v: 128, yPadding: 8);
      final t = LiveInputTransform.compute(
        rawWidth: 8,
        rawHeight: 4,
        quarterTurns: 1,
        roi: const Rect.fromLTRB(0, 0, 1, 1),
        inputSize: 8,
      );
      final out = Uint8List(8 * 8 * 3);
      final lum = preprocessLiveFrame(frame, t, out);
      expect(lum, closeTo(128 / 255, 1e-9));
      expect(px(out, 8, t.outLeft + 1, 3), [128, 128, 128]);
    });

    test('赤（V が大きい）・半平面（画素間隔 2）', () {
      final frame = yuvFrame(8, 4, y: 81, u: 90, v: 240, uvPixel: 2);
      final t = LiveInputTransform.compute(
        rawWidth: 8,
        rawHeight: 4,
        quarterTurns: 0,
        roi: const Rect.fromLTRB(0, 0, 1, 1),
        inputSize: 8,
      );
      final out = Uint8List(8 * 8 * 3);
      preprocessLiveFrame(frame, t, out);
      final rgb = px(out, 8, 3, t.outTop + 1);
      expect(rgb[0], greaterThan(200));
      expect(rgb[1], lessThan(40));
      expect(rgb[2], lessThan(40));
    });

    test('NV21（1 面: Y の後に VU）', () {
      const w = 4;
      const h = 2;
      final bytes = Uint8List(w * h + w * h ~/ 2)
        ..fillRange(0, w * h, 81)
        ..fillRange(w * h, w * h + w * h ~/ 2, 0);
      // VU の順。
      for (var i = w * h; i < bytes.length; i += 2) {
        bytes[i] = 240; // V
        bytes[i + 1] = 90; // U
      }
      final frame = LiveFrame(
        format: LiveFrameFormat.nv21,
        width: w,
        height: h,
        planes: [LivePlane(bytes: bytes, bytesPerRow: w)],
      );
      final t = LiveInputTransform.compute(
        rawWidth: w,
        rawHeight: h,
        quarterTurns: 0,
        roi: const Rect.fromLTRB(0, 0, 1, 1),
        inputSize: 4,
      );
      final out = Uint8List(4 * 4 * 3);
      preprocessLiveFrame(frame, t, out);
      final rgb = px(out, 4, 1, t.outTop);
      expect(rgb[0], greaterThan(200));
      expect(rgb[2], lessThan(40));
    });

    test('暗いフレームは輝度が低い', () {
      final frame = yuvFrame(8, 4, y: 10, u: 128, v: 128);
      final t = LiveInputTransform.compute(
        rawWidth: 8,
        rawHeight: 4,
        quarterTurns: 1,
        inputSize: 8,
      );
      expect(
        preprocessLiveFrame(frame, t, Uint8List(8 * 8 * 3)),
        lessThan(0.05),
      );
    });
  });

  group('鮮鋭度（手ぶれの検出）', () {
    /// 720p 横長（センサーの向き）の YUV420。Y は 6 画素角の市松模様と細い線（牌の模様の代わり）。
    /// [blur] > 0 なら、横方向に [blur] 画素の移動平均をかける（横に振った手ぶれ）。
    LiveFrame textured({int blur = 0}) {
      const w = 1280;
      const h = 720;
      var y = Uint8List(w * h);
      for (var r = 0; r < h; r++) {
        for (var c = 0; c < w; c++) {
          final checker = ((r ~/ 6) + (c ~/ 6)).isEven;
          final line = c % 17 == 0 || r % 23 == 0;
          y[r * w + c] = line ? 20 : (checker ? 200 : 70);
        }
      }
      if (blur > 0) {
        final blurred = Uint8List(w * h);
        for (var r = 0; r < h; r++) {
          for (var c = 0; c < w; c++) {
            var sum = 0;
            var n = 0;
            for (var k = -blur ~/ 2; k <= blur ~/ 2; k++) {
              final cc = c + k;
              if (cc < 0 || cc >= w) continue;
              sum += y[r * w + cc];
              n++;
            }
            blurred[r * w + c] = sum ~/ n;
          }
        }
        y = blurred;
      }
      final uv = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
      return LiveFrame(
        format: LiveFrameFormat.yuv420,
        width: w,
        height: h,
        planes: [
          LivePlane(bytes: y, bytesPerRow: w),
          LivePlane(bytes: uv, bytesPerRow: w ~/ 2),
          LivePlane(bytes: Uint8List.fromList(uv), bytesPerRow: w ~/ 2),
        ],
      );
    }

    final transform = LiveInputTransform.compute(
      rawWidth: 1280,
      rawHeight: 720,
      quarterTurns: 1,
    );

    double sharpnessOf(LiveFrame frame) {
      final out = Uint8List(640 * 640 * 3);
      preprocessLiveFrame(frame, transform, out);
      return liveSharpness(out, transform);
    }

    test('ぶれたフレームは、同じ被写体のはっきりしたフレームより大きく下がる', () {
      final sharp = sharpnessOf(textured());
      final blurred = sharpnessOf(textured(blur: 9));
      expect(sharp, greaterThan(0.01));
      expect(blurred, lessThan(sharp * 0.5));
      // 弱いぶれ（3 画素）でも下がる。
      expect(sharpnessOf(textured(blur: 3)), lessThan(sharp * 0.8));
    });

    test('平らな画像は 0、余白（レターボックス）は数えない', () {
      final flat = yuvFrame(1280, 720, y: 120, u: 128, v: 128);
      expect(sharpnessOf(flat), closeTo(0, 1e-9));
      // 横長の ROI（上下に灰色の余白）でも、余白との境目を数えない。
      final wide = LiveInputTransform.compute(
        rawWidth: 64,
        rawHeight: 32,
        quarterTurns: 0,
        roi: const Rect.fromLTRB(0, 0, 1, 1),
        inputSize: 64,
      );
      final out = Uint8List(64 * 64 * 3);
      preprocessLiveFrame(
        yuvFrame(64, 32, y: 10, u: 128, v: 128),
        wide,
        out,
      );
      expect(liveSharpness(out, wide), closeTo(0, 1e-9));
    });

    test('処理時間: 鮮鋭度は前処理（変換・縮小）よりずっと軽い', () {
      final frame = textured();
      final out = Uint8List(640 * 640 * 3);
      // 暖機（JIT）。
      for (var i = 0; i < 3; i++) {
        preprocessLiveFrame(frame, transform, out);
        liveSharpness(out, transform);
      }
      const runs = 10;
      final pre = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        preprocessLiveFrame(frame, transform, out);
      }
      pre.stop();
      final sharp = Stopwatch()..start();
      for (var i = 0; i < runs; i++) {
        liveSharpness(out, transform);
      }
      sharp.stop();
      final preMs = pre.elapsedMicroseconds / runs / 1000;
      final sharpMs = sharp.elapsedMicroseconds / runs / 1000;
      // ignore: avoid_print
      print(
        'preprocessLiveFrame: ${preMs.toStringAsFixed(2)} ms, '
        'liveSharpness: ${sharpMs.toStringAsFixed(2)} ms (JIT)',
      );
      expect(sharpMs, lessThan(preMs * 0.5));
    });
  });

  group('YOLO の出力', () {
    // [1, 4+3, 10] のチャネル先頭の出力を作る（足りないアンカーは 0）。
    const anchorCount = 10;
    Float32List output(List<List<double>> anchors) {
      const channels = 7;
      const n = anchorCount;
      final out = Float32List(channels * n);
      for (var a = 0; a < anchors.length; a++) {
        for (var c = 0; c < channels; c++) {
          out[c * n + a] = anchors[a][c];
        }
      }
      return out;
    }

    test('しきい値・最良のクラス・重なりの除去（NMS）', () {
      final out = output([
        [100, 100, 40, 50, 0.9, 0.1, 0.0], // クラス 0
        [102, 101, 40, 50, 0.1, 0.7, 0.0], // 上と重なる（確度が低い方は消える）
        [300, 100, 40, 50, 0.0, 0.2, 0.8], // クラス 2
        [500, 100, 40, 50, 0.1, 0.1, 0.1], // しきい値未満
        [10, 10, 4, 4, 0.0, 0.0, 0.0],
        [20, 20, 4, 4, 0.0, 0.0, 0.0],
      ]);
      final boxes = decodeYoloOutput(out, const [
        1,
        7,
        anchorCount,
      ], scoreThreshold: 0.25);
      expect(boxes.length, 2);
      final byClass = {for (final b in boxes) b.classIndex: b};
      expect(byClass[0]!.score, closeTo(0.9, 1e-6));
      expect(byClass[0]!.box.center, const Offset(100, 100));
      expect(byClass[2]!.box.width, 40);
    });

    test('0〜1 の座標と、アンカーが先の並び（[1, N, 4+C]）', () {
      const n = 8;
      const channels = 6; // 4 + 2 クラス（アンカーの方が多い）
      final out = Float32List(n * channels);
      void set(int a, List<double> values) {
        for (var c = 0; c < channels; c++) {
          out[a * channels + c] = values[c];
        }
      }

      set(0, [0.5, 0.5, 0.1, 0.1, 0.1, 0.95]);
      set(1, [0.2, 0.2, 0.1, 0.1, 0.0, 0.0]);
      set(2, [0.8, 0.8, 0.1, 0.1, 0.6, 0.0]);
      final boxes = decodeYoloOutput(
        out,
        const [1, n, channels],
        scoreThreshold: 0.5,
        inputSize: 640,
      );
      expect(boxes.length, 2);
      expect(boxes.first.classIndex, 1);
      expect(boxes.first.box.center, const Offset(320, 320));
    });

    test('量子化された出力を戻す', () {
      final raw = Uint8List.fromList([0, 128, 255]);
      expect(dequantize(raw, signed: false, scale: 0.5, zeroPoint: 128), [
        -64,
        0,
        63.5,
      ]);
      final signed = Uint8List.fromList([0xFF, 0x00, 0x7F]); // -1, 0, 127
      expect(dequantize(signed, signed: true, scale: 1, zeroPoint: 0), [
        -1,
        0,
        127,
      ]);
    });
  });
}
