import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/live_inference_worker.dart';
import 'package:nanikiru_cam/ml/live_yolo_decoder.dart';

/// `[1, 4+C, N]`（チャンネルが先）の YOLO 出力を作る。写真用・ライブ用の tflite と同じ並び。
Float32List _channelsFirst({
  required int classes,
  required int anchors,
  required List<_Anchor> items,
}) {
  final channels = 4 + classes;
  final out = Float32List(channels * anchors);
  for (final item in items) {
    final a = item.anchor;
    out[0 * anchors + a] = item.cx;
    out[1 * anchors + a] = item.cy;
    out[2 * anchors + a] = item.w;
    out[3 * anchors + a] = item.h;
    out[(4 + item.classIndex) * anchors + a] = item.score;
  }
  return out;
}

class _Anchor {
  const _Anchor(
    this.anchor,
    this.cx,
    this.cy,
    this.w,
    this.h,
    this.classIndex,
    this.score,
  );
  final int anchor;
  final double cx;
  final double cy;
  final double w;
  final double h;
  final int classIndex;
  final double score;
}

void main() {
  group('decodeYoloOutput', () {
    // 0〜1 で出るモデル（ライブ用 tflite）。入力 640（8400 アンカー）と 480（4725 アンカー）。
    for (final (size, anchors) in [(640, 8400), (480, 4725)]) {
      test('入力 $size: 正規化座標を入力の画素に直し、重なる検出は高い方だけ残す', () {
        final out = _channelsFirst(
          classes: 38,
          anchors: anchors,
          items: const [
            _Anchor(10, 0.25, 0.5, 0.10, 0.20, 5, 0.90),
            // 同じ牌への重複（別クラスで低い確度）: クラスを区別しない NMS で消える。
            _Anchor(20, 0.25, 0.5, 0.10, 0.20, 6, 0.80),
            _Anchor(30, 0.75, 0.5, 0.10, 0.20, 7, 0.60),
            // しきい値未満。
            _Anchor(40, 0.50, 0.50, 0.10, 0.20, 8, 0.10),
          ],
        );
        final boxes = decodeYoloOutput(
          out,
          [1, 42, anchors],
          scoreThreshold: 0.25,
          inputSize: size,
        );
        expect(boxes, hasLength(2));
        expect(boxes[0].classIndex, 5);
        expect(boxes[0].score, closeTo(0.90, 1e-6));
        final s = size.toDouble();
        // Float32 の誤差があるので近似で比べる。
        expect(boxes[0].box.center.dx, closeTo(0.25 * s, 1e-3));
        expect(boxes[0].box.center.dy, closeTo(0.5 * s, 1e-3));
        expect(boxes[0].box.width, closeTo(0.10 * s, 1e-3));
        expect(boxes[0].box.height, closeTo(0.20 * s, 1e-3));
        expect(boxes[1].classIndex, 7);
        expect(boxes[1].box.center.dx, closeTo(0.75 * s, 1e-3));
      });
    }

    test('画素座標で出るモデルは倍率をかけない', () {
      final out = _channelsFirst(
        classes: 38,
        anchors: 8400,
        items: const [
          // アンカー 0 の幅が大きい = 画素座標のモデル。
          _Anchor(0, 100, 200, 60, 80, 1, 0.9),
        ],
      );
      final boxes = decodeYoloOutput(
        out,
        [1, 42, 8400],
        scoreThreshold: 0.25,
        inputSize: 640,
      );
      expect(boxes, hasLength(1));
      expect(
        boxes.single.box,
        Rect.fromCenter(center: const Offset(100, 200), width: 60, height: 80),
      );
    });

    test('形が不正なら空', () {
      expect(
        decodeYoloOutput(Float32List(10), [1, 42], scoreThreshold: 0.25),
        isEmpty,
      );
      expect(
        decodeYoloOutput(Float32List(10), [1, 42, 8400], scoreThreshold: 0.25),
        isEmpty,
      );
    });
  });

  group('liveModelInputSize', () {
    test('入力形状 [1, S, S, 3] から一辺を読む', () {
      expect(liveModelInputSize([1, 640, 640, 3]), 640);
      expect(liveModelInputSize([1, 480, 480, 3]), 480);
    });

    test('正方形でない・形が違うときは既定の 640', () {
      expect(liveModelInputSize([1, 480, 640, 3]), 640);
      expect(liveModelInputSize([1, 0, 0, 3]), 640);
      expect(liveModelInputSize([1, 3]), 640);
      expect(liveModelInputSize([1, 320, 320, 3], fallback: 480), 320);
      expect(liveModelInputSize(const [], fallback: 480), 480);
    });

    test('LiveInferenceConfig の入力サイズは既定でモデルから読む', () {
      expect(const LiveInferenceConfig().inputSize, isNull);
      expect(const LiveInferenceConfig(inputSize: 480).inputSize, 480);
    });
  });
}
