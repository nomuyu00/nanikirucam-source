// 流用元: reference/agari_cam/lib/ml/tile_selection.dart（2026-10-21 時点）
// 改修（設計書 3.2）: 窓を 14 枚から「13 または 14 枚」へ、和了形判定（HandParser）をやめて
// 「枚数が 13/14 で各牌 4 枚以内」を完成の条件にした。15 枚以上の窓（槓子対策）は作らない。
// 選んだ牌は左から右の並び（x 座標順）で返し、ツモ牌・副露の推定は tile_arrangement.dart。
import 'dart:math' as math;
import 'dart:ui';

import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_arrangement.dart';

class SelectedTiles {
  const SelectedTiles({
    required this.detections,
    required this.strategy,
    required this.quality,
  });

  /// 左から右（枠の中心の x 座標順）に並べた牌。
  final List<TileDetection> detections;
  final String strategy;
  final double quality;

  List<String> get labels =>
      detections.map((d) => d.label).toList(growable: false);
  List<double> get scores =>
      detections.map((d) => d.score).toList(growable: false);

  /// 枚数が 13 または 14 で、同じ牌が 4 枚を超えない。
  /// （副露の槓があると物理的には 14 枚で論理 13 枚になるが、15 枚以上は無効にする。）
  bool get isComplete => TileSelectionEngine.isCompleteSet(labels);

  /// 全牌の確度の最小値（牌がなければ 0）。
  double get minScore => detections.isEmpty
      ? 0.0
      : detections.map((d) => d.score).reduce(math.min);

  double get averageScore {
    if (detections.isEmpty) return 0.0;
    final total = detections.fold<double>(0.0, (sum, d) => sum + d.score);
    return total / detections.length;
  }

  /// 13 または 14 枚で、全牌の確度が [threshold] 以上（設計書 3.2 の打ち切り条件）。
  bool isConfident(double threshold) => isComplete && minScore >= threshold;

  /// ツモ牌・副露候補の推定（[detections] の添字で返す）。
  TileArrangement get arrangement =>
      TileArrangementDetector.analyze(detections);
}

class TileSelectionEngine {
  TileSelectionEngine();

  /// 14 枚（ツモ後）。
  static const int handTileCount = 14;

  /// 13 枚（打牌後・ツモ前）。
  static const int standingTileCount = 13;

  /// 枚数が 13 または 14 で、同じ牌が 4 枚を超えないラベル列か。
  static bool isCompleteSet(List<String> labels) {
    if (labels.length != standingTileCount && labels.length != handTileCount) {
      return false;
    }
    return _countTilesOverLimit(labels) == 0;
  }

  SelectedTiles selectBest(List<TileDetection> detections) {
    final valid = detections.where(_isSelectableTile).toList(growable: false);
    if (valid.isEmpty) {
      return const SelectedTiles(
        detections: [],
        strategy: 'empty',
        quality: double.negativeInfinity,
      );
    }

    final legacy = _buildLegacy(valid);
    final candidates = <SelectedTiles>[
      legacy,
      _buildTopScore(valid),
      _buildDominantRow(valid, variant: 'row-tight', rowFactor: 0.90),
      _buildDominantRow(valid, variant: 'row-relaxed', rowFactor: 1.20),
    ].where((candidate) => candidate.detections.isNotEmpty).toList();

    candidates.sort((a, b) => b.quality.compareTo(a.quality));
    final best = candidates.first;

    if (_shouldKeepLegacy(best, legacy)) {
      return legacy;
    }
    return best;
  }

  bool _shouldKeepLegacy(SelectedTiles best, SelectedTiles legacy) {
    if (best.strategy == legacy.strategy) return false;
    if (best.isComplete && !legacy.isComplete) return false;
    if (!best.isComplete && legacy.isComplete) return true;
    if (best.quality >= legacy.quality + 8.0) return false;
    if (best.averageScore >= legacy.averageScore + 0.08 &&
        best.isComplete &&
        legacy.isComplete) {
      return false;
    }
    return true;
  }

  SelectedTiles _buildLegacy(List<TileDetection> detections) {
    final sorted = List<TileDetection>.from(detections)
      ..sort(
        (a, b) => _distanceSqToCenter(
          a.box.center,
        ).compareTo(_distanceSqToCenter(b.box.center)),
      );
    return _candidateFrom(
      sorted.take(handTileCount).toList(growable: false),
      strategy: 'legacy',
    );
  }

  SelectedTiles _buildTopScore(List<TileDetection> detections) {
    final sorted = List<TileDetection>.from(detections)
      ..sort((a, b) => b.score.compareTo(a.score));
    return _candidateFrom(
      sorted.take(handTileCount).toList(growable: false),
      strategy: 'top-score',
    );
  }

  SelectedTiles _buildDominantRow(
    List<TileDetection> detections, {
    required String variant,
    required double rowFactor,
  }) {
    final ranked = List<TileDetection>.from(detections)
      ..sort((a, b) => b.score.compareTo(a.score));
    final anchors = ranked.take(math.min(30, ranked.length)).toList();
    if (anchors.isEmpty) {
      return const SelectedTiles(
        detections: [],
        strategy: 'row-empty',
        quality: double.negativeInfinity,
      );
    }

    final boxHeights = anchors.map((d) => d.box.height).toList()..sort();
    final boxWidths = anchors.map((d) => d.box.width).toList()..sort();
    final medianHeight = boxHeights[boxHeights.length ~/ 2];
    final medianWidth = boxWidths[boxWidths.length ~/ 2];
    final rowTolerance = math.max(medianHeight * rowFactor, 0.035);
    final xTolerance = math.max(medianWidth * 0.55, 0.02);

    SelectedTiles? best;
    for (final anchor in anchors) {
      final band = ranked.where((candidate) {
        final dy = (candidate.box.center.dy - anchor.box.center.dy).abs();
        return dy <= rowTolerance;
      }).toList();
      if (band.length < standingTileCount) {
        continue;
      }

      final deduped = _dedupeSpatial(
        band,
        xTolerance: xTolerance,
        rowTolerance: rowTolerance,
      );
      if (deduped.length < standingTileCount) {
        continue;
      }

      final rowOrdered = List<TileDetection>.from(deduped)
        ..sort((a, b) => a.box.center.dx.compareTo(b.box.center.dx));

      // 13 枚（ツモ前）と 14 枚（ツモ後）の窓を試す。15 枚以上は作らない。
      for (final size in const [standingTileCount, handTileCount]) {
        if (rowOrdered.length < size) break;
        final window = _bestWindow(
          rowOrdered,
          windowSize: size,
          rowTolerance: rowTolerance,
          medianWidth: medianWidth,
        );
        final candidate = _candidateFrom(window, strategy: variant);
        if (best == null || candidate.quality > best.quality) {
          best = candidate;
        }
      }
    }

    return best ??
        const SelectedTiles(
          detections: [],
          strategy: 'row-none',
          quality: double.negativeInfinity,
        );
  }

  List<TileDetection> _dedupeSpatial(
    List<TileDetection> detections, {
    required double xTolerance,
    required double rowTolerance,
  }) {
    final ranked = List<TileDetection>.from(detections)
      ..sort((a, b) => b.score.compareTo(a.score));
    final kept = <TileDetection>[];
    for (final detection in ranked) {
      final duplicate = kept.any((existing) {
        final overlap = _iou(existing.box, detection.box);
        final xDistance = (existing.box.center.dx - detection.box.center.dx)
            .abs();
        final yDistance = (existing.box.center.dy - detection.box.center.dy)
            .abs();
        return overlap >= 0.35 ||
            (xDistance <= xTolerance && yDistance <= rowTolerance);
      });
      if (!duplicate) {
        kept.add(detection);
      }
    }
    return kept;
  }

  List<TileDetection> _bestWindow(
    List<TileDetection> detections, {
    required int windowSize,
    required double rowTolerance,
    required double medianWidth,
  }) {
    if (detections.length <= windowSize) {
      return detections;
    }

    List<TileDetection>? bestWindow;
    double bestScore = double.negativeInfinity;

    for (var start = 0; start <= detections.length - windowSize; start++) {
      final window = detections.sublist(start, start + windowSize);
      final score = _windowQuality(
        window,
        rowTolerance: rowTolerance,
        medianWidth: medianWidth,
      );
      if (score > bestScore) {
        bestScore = score;
        bestWindow = window;
      }
    }

    return bestWindow ?? detections.take(windowSize).toList(growable: false);
  }

  double _windowQuality(
    List<TileDetection> detections, {
    required double rowTolerance,
    required double medianWidth,
  }) {
    final centersX = detections.map((d) => d.box.center.dx).toList();
    final centersY = detections.map((d) => d.box.center.dy).toList();
    final gaps = <double>[];
    for (var i = 1; i < centersX.length; i++) {
      gaps.add(centersX[i] - centersX[i - 1]);
    }

    final avgScore =
        detections.fold<double>(0.0, (sum, d) => sum + d.score) /
        detections.length;
    final ySpan = centersY.reduce(math.max) - centersY.reduce(math.min);
    final xSpan = centersX.reduce(math.max) - centersX.reduce(math.min);
    final meanY = centersY.reduce((a, b) => a + b) / centersY.length;
    final centerYDistance = (meanY - 0.5).abs();
    final gapPenalty = gaps.isEmpty ? 0.0 : _coefficientOfVariation(gaps);
    final widthPenalty = medianWidth <= 0.0
        ? 0.0
        : gaps.where((gap) => gap < medianWidth * 0.25).length * 0.5;

    return (avgScore * 100.0) -
        (gapPenalty * 12.0) -
        (widthPenalty * 8.0) -
        ((ySpan / math.max(rowTolerance, 0.001)) * 18.0) -
        (centerYDistance * 90.0) +
        (math.min(xSpan, 0.85) * 10.0);
  }

  SelectedTiles _candidateFrom(
    List<TileDetection> detections, {
    required String strategy,
  }) {
    final ordered = _sortLeftToRight(detections);
    final labels = ordered.map((d) => d.label).toList(growable: false);
    final quality = _candidateQuality(detections, labels: labels);

    return SelectedTiles(
      detections: ordered,
      strategy: strategy,
      quality: quality,
    );
  }

  double _candidateQuality(
    List<TileDetection> detections, {
    required List<String> labels,
  }) {
    if (detections.isEmpty) return double.negativeInfinity;

    final avgScore =
        detections.fold<double>(0.0, (sum, d) => sum + d.score) /
        detections.length;
    final yCenters = detections.map((d) => d.box.center.dy).toList();
    final xCenters = detections.map((d) => d.box.center.dx).toList();
    final widths = detections.map((d) => d.box.width).toList();
    final heights = detections.map((d) => d.box.height).toList();

    final ySpan = (yCenters.reduce(math.max) - yCenters.reduce(math.min));
    final xSpan = (xCenters.reduce(math.max) - xCenters.reduce(math.min));
    final meanY = yCenters.reduce((a, b) => a + b) / yCenters.length;
    final centerYDistance = (meanY - 0.5).abs();
    final widthCv = _coefficientOfVariation(widths);
    final heightCv = _coefficientOfVariation(heights);
    final overLimitCount = _countTilesOverLimit(labels);
    final complete = isCompleteSet(labels);
    // 13・14 のどちらにも届かない枚数は、近い方との差だけ減点する。
    final countPenalty = complete
        ? 0.0
        : math
                  .min(
                    (labels.length - standingTileCount).abs(),
                    (labels.length - handTileCount).abs(),
                  )
                  .toDouble() *
              12.0;

    var quality = avgScore * 100.0;
    quality -= ySpan * 140.0;
    quality -= centerYDistance * 95.0;
    quality -= widthCv * 10.0;
    quality -= heightCv * 10.0;
    quality -= overLimitCount * 25.0;
    quality -= countPenalty;
    quality += math.min(xSpan, 0.85) * 8.0;

    if (complete) {
      // 13 と 14 のどちらも「完成」。列に 14 枚そろっているときに端の 1 枚を
      // 落として 13 枚にしないよう、14 枚をわずかに優先する。
      quality += 20.0 + (labels.length == handTileCount ? 6.0 : 0.0);
    }

    return quality;
  }

  static int _countTilesOverLimit(List<String> labels) {
    final counts = <String, int>{};
    for (final label in labels) {
      // 赤5も同じ種類の牌として4枚までに数える。
      final key = label.startsWith('0') ? '5${label[1]}' : label;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts.values.fold<int>(
      0,
      (sum, count) => sum + math.max(0, count - 4),
    );
  }

  List<TileDetection> _sortLeftToRight(List<TileDetection> detections) {
    final ordered = List<TileDetection>.from(detections);
    ordered.sort((a, b) {
      final x = a.box.center.dx.compareTo(b.box.center.dx);
      return x != 0 ? x : a.box.center.dy.compareTo(b.box.center.dy);
    });
    return ordered;
  }

  bool _isSelectableTile(TileDetection detection) {
    final label = detection.label;
    if (label.length != 2) return false;
    final suit = label[1];
    return suit == 'm' || suit == 'p' || suit == 's' || suit == 'z';
  }

  double _distanceSqToCenter(Offset center) {
    final dx = center.dx - 0.5;
    final dy = center.dy - 0.5;
    return (dx * dx) + (dy * dy);
  }

  double _coefficientOfVariation(List<double> values) {
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    if (mean == 0.0) return 0.0;
    final variance =
        values
            .map((value) => math.pow(value - mean, 2).toDouble())
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance) / mean;
  }

  double _iou(Rect a, Rect b) {
    final left = math.max(a.left, b.left);
    final top = math.max(a.top, b.top);
    final right = math.min(a.right, b.right);
    final bottom = math.min(a.bottom, b.bottom);
    final width = math.max(0.0, right - left);
    final height = math.max(0.0, bottom - top);
    final intersection = width * height;
    final union = (a.width * a.height) + (b.width * b.height) - intersection;
    if (union <= 0.0) return 0.0;
    return intersection / union;
  }
}
