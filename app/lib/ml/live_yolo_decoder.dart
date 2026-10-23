import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:nanikiru_cam/ml/nms.dart';

/// YOLO の検出 1 件（640 入力の画素座標）。
class YoloBox {
  const YoloBox({
    required this.box,
    required this.classIndex,
    required this.score,
  });

  final Rect box;
  final int classIndex;
  final double score;
}

/// YOLO11 の 1 出力（`[1, 4+C, N]` または `[1, N, 4+C]`、float）を検出に変換する。
///
/// `TfliteService._decodeFloat`（写真用）と同じ考え方: 各アンカーで最も確度の高いクラスを採り、
/// [scoreThreshold] 未満は捨て、上位 [maxCandidates] 件にクラスを区別しない NMS をかける。
/// 座標が 0〜1 で出るモデルは [inputSize] 倍する。
List<YoloBox> decodeYoloOutput(
  Float32List out,
  List<int> shape, {
  required double scoreThreshold,
  int inputSize = 640,
  double iouThreshold = 0.5,
  int maxCandidates = 300,
  int maxDetections = 60,
}) {
  if (shape.length != 3) return const [];
  final channelsFirst = shape[1] < shape[2];
  final channels = channelsFirst ? shape[1] : shape[2];
  final anchors = channelsFirst ? shape[2] : shape[1];
  final classes = channels - 4;
  if (classes <= 0 || out.length < channels * anchors) return const [];

  double at(int channel, int anchor) => channelsFirst
      ? out[channel * anchors + anchor]
      : out[anchor * channels + channel];

  var maxCoord = 0.0;
  for (var a = 0; a < anchors; a += 97) {
    maxCoord = math.max(maxCoord, at(2, a));
  }
  final coordScale = maxCoord <= 1.5 ? inputSize.toDouble() : 1.0;

  final boxes = <Rect>[];
  final scores = <double>[];
  final labels = <int>[];
  if (channelsFirst) {
    // クラスごとに連続した並び。アンカーの順に最良のクラスを求める。
    final best = Float32List(anchors);
    final bestClass = Int32List(anchors);
    for (var c = 0; c < classes; c++) {
      final base = (4 + c) * anchors;
      for (var a = 0; a < anchors; a++) {
        final v = out[base + a];
        if (v > best[a]) {
          best[a] = v;
          bestClass[a] = c;
        }
      }
    }
    for (var a = 0; a < anchors; a++) {
      final score = best[a];
      if (score < scoreThreshold) continue;
      final cx = out[a] * coordScale;
      final cy = out[anchors + a] * coordScale;
      final w = out[2 * anchors + a] * coordScale;
      final h = out[3 * anchors + a] * coordScale;
      boxes.add(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));
      scores.add(score);
      labels.add(bestClass[a]);
    }
  } else {
    for (var a = 0; a < anchors; a++) {
      var bestScore = 0.0;
      var bestClass = -1;
      for (var c = 0; c < classes; c++) {
        final v = at(4 + c, a);
        if (v > bestScore) {
          bestScore = v;
          bestClass = c;
        }
      }
      if (bestClass < 0 || bestScore < scoreThreshold) continue;
      final cx = at(0, a) * coordScale;
      final cy = at(1, a) * coordScale;
      final w = at(2, a) * coordScale;
      final h = at(3, a) * coordScale;
      boxes.add(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));
      scores.add(bestScore);
      labels.add(bestClass);
    }
  }

  final order = List<int>.generate(scores.length, (i) => i)
    ..sort((x, y) => scores[y].compareTo(scores[x]));
  final top = order.take(maxCandidates).toList(growable: false);
  final keep = nonMaxSuppression(
    [for (final i in top) boxes[i]],
    [for (final i in top) scores[i]],
    iouThreshold: iouThreshold,
    maxPerClass: maxDetections,
  );
  return [
    for (final k in keep)
      YoloBox(
        box: boxes[top[k]],
        classIndex: labels[top[k]],
        score: scores[top[k]],
      ),
  ];
}

/// 量子化された出力（uint8 / int8）を float に戻す。
Float32List dequantize(
  Uint8List raw, {
  required bool signed,
  required double scale,
  required int zeroPoint,
}) {
  final out = Float32List(raw.length);
  if (signed) {
    final ints = Int8List.view(raw.buffer, raw.offsetInBytes, raw.length);
    for (var i = 0; i < ints.length; i++) {
      out[i] = (ints[i] - zeroPoint) * scale;
    }
  } else {
    for (var i = 0; i < raw.length; i++) {
      out[i] = (raw[i] - zeroPoint) * scale;
    }
  }
  return out;
}
