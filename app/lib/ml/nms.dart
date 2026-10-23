// 流用元: reference/agari_cam/lib/ml/nms.dart（2026-10-21 時点）
import 'dart:math' as math;
import 'dart:ui';

/// Non-maximum suppression: returns indices kept after NMS.
List<int> nonMaxSuppression(
  List<Rect> boxes,
  List<double> scores, {
  double iouThreshold = 0.45,
  int maxPerClass = 100,
}) {
  final idxs = List<int>.generate(boxes.length, (i) => i)
    ..sort((a, b) => scores[b].compareTo(scores[a]));
  final keep = <int>[];
  for (final i in idxs) {
    var shouldKeep = true;
    for (final j in keep) {
      if (_iou(boxes[i], boxes[j]) > iouThreshold) {
        shouldKeep = false;
        break;
      }
    }
    if (shouldKeep) {
      keep.add(i);
      if (keep.length >= maxPerClass) break;
    }
  }
  return keep;
}

double _iou(Rect a, Rect b) {
  final interLeft = math.max(a.left, b.left);
  final interTop = math.max(a.top, b.top);
  final interRight = math.min(a.right, b.right);
  final interBottom = math.min(a.bottom, b.bottom);
  final interW = math.max(0.0, interRight - interLeft);
  final interH = math.max(0.0, interBottom - interTop);
  final interArea = interW * interH;
  final union = a.width * a.height + b.width * b.height - interArea;
  if (union <= 0) return 0;
  return interArea / union;
}
