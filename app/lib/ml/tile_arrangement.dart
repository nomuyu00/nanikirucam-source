import 'dart:math' as math;

import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';

/// 右端の副露の候補（[TileArrangement.melds]）。
class MeldGroup {
  const MeldGroup({required this.indices, required this.kind});

  /// 検出列（左から右の並び）の中での添字。連続している。
  final List<int> indices;

  /// 牌の並びから推定した種類（槓は明槓。暗槓かどうかはユーザーが選ぶ）。
  final MeldKind kind;
}

/// 並んだ牌の配置から読み取れる、ツモ牌と副露の候補。
class TileArrangement {
  const TileArrangement({this.tsumoIndex, this.melds = const []});

  /// ツモ牌と推定した牌の添字（なければ null）。
  final int? tsumoIndex;

  /// 右端から順に見つけた副露候補（右にあるものが先）。
  final List<MeldGroup> melds;

  static const TileArrangement none = TileArrangement();
}

/// ツモ牌の推定と副露候補の検出（設計書 3.1）。
///
/// 入力は左から右に並べた牌（x 座標順）。牌の枠は 0〜1 の正規化座標でよい
/// （横向きの判定は他の牌との縦横比の比で行うので、画像の縦横比に依存しない）。
///
/// 並びの想定: `[門前の牌…] [少し離してツモ牌] [副露…]`。副露は右端にあり、
/// 鳴いた牌が 1 枚だけ横向き（縦横比が逆）になる。
abstract final class TileArrangementDetector {
  /// 右端の牌が、他の牌の平均の間隔（中心間距離）のこの倍以上離れていればツモ牌。
  static const double tsumoGapRatio = 1.6;

  /// 縦横比（幅/高さ）が、他の牌の中央値のこの倍以上なら横向きの牌。
  /// 標準の牌は幅:高さ ≒ 3:4 なので、横向きは約 1.8 倍になる。
  static const double sidewaysAspectRatio = 1.4;

  /// ツモ牌を推定するのに必要な最小の牌数（ツモ牌を除く）。
  static const int minTilesForTsumo = 5;

  static TileArrangement analyze(List<TileDetection> ordered) {
    if (ordered.length < minTilesForTsumo) return TileArrangement.none;
    if (!_isSingleRow(ordered)) return TileArrangement.none;

    final melds = detectMelds(ordered);
    final inMeld = {for (final m in melds) ...m.indices};
    final standing = [
      for (var i = 0; i < ordered.length; i++)
        if (!inMeld.contains(i)) i,
    ];
    // 論理枚数（槓も 3 枚）が 14 のときだけ、14 枚目＝ツモ牌がありうる。
    final logicalCount = standing.length + 3 * melds.length;
    int? tsumo;
    if (logicalCount == HandInput.maxTileCount) {
      tsumo = detectTsumoIndex(ordered, standing);
    }
    return TileArrangement(tsumoIndex: tsumo, melds: melds);
  }

  /// [indices]（[ordered] の添字を左から並べたもの）の右端がツモ牌なら、その添字を返す。
  static int? detectTsumoIndex(List<TileDetection> ordered, List<int> indices) {
    if (indices.length < minTilesForTsumo + 1) return null;
    double cx(int i) => ordered[indices[i]].box.center.dx;
    final last = indices.length - 1;
    // 右端を除く牌の平均の間隔（中心間距離）。
    final pitch = (cx(last - 1) - cx(0)) / (last - 1);
    if (pitch <= 0) return null;
    final lastGap = cx(last) - cx(last - 1);
    if (lastGap >= pitch * tsumoGapRatio) return indices[last];
    return null;
  }

  /// 右端にある副露の候補を、右から順に最大 4 つ返す。
  ///
  /// 右端の 3 枚（4 枚が同じ牌なら 4 枚）に横向きの牌が含まれ、牌の並びがチー・ポン・槓の
  /// どれかとして成り立つものだけを候補にする。成り立たない並びは誤検出として捨てる。
  static List<MeldGroup> detectMelds(List<TileDetection> ordered) {
    if (ordered.length < 6) return const [];
    final aspects = [
      for (final d in ordered) d.box.width / math.max(d.box.height, 1e-9),
    ]..sort();
    final median = aspects[aspects.length ~/ 2];
    if (median <= 0) return const [];
    bool sideways(int i) {
      final d = ordered[i];
      return d.box.width / math.max(d.box.height, 1e-9) >=
          median * sidewaysAspectRatio;
    }

    final result = <MeldGroup>[];
    var end = ordered.length; // まだ見ていない右端（含まない）
    while (result.length < 4 && end >= 3) {
      List<int>? group;
      if (end >= 4) {
        final four = [for (var i = end - 4; i < end; i++) i];
        if (four.any(sideways) &&
            MeldInput.guessKind([for (final i in four) ordered[i].label]) ==
                MeldKind.minkan) {
          group = four;
        }
      }
      if (group == null) {
        final three = [for (var i = end - 3; i < end; i++) i];
        if (three.any(sideways)) {
          final kind = MeldInput.guessKind([
            for (final i in three) ordered[i].label,
          ]);
          if (kind == MeldKind.chi || kind == MeldKind.pon) group = three;
        }
      }
      if (group == null) break;
      result.add(
        MeldGroup(
          indices: group,
          kind: MeldInput.guessKind([for (final i in group) ordered[i].label])!,
        ),
      );
      end -= group.length;
    }
    return result;
  }

  /// 牌の中心が 1 本の直線の上にほぼ収まっているか（複数段にまたがる選択を除く）。
  ///
  /// 中心に最小二乗の直線を当てはめ、直線からの縦のずれがどれも枠の高さの中央値の 0.6 倍以内、
  /// かつ隣どうしの（直線の傾きを除いた）縦のずれも 0.6 倍以内なら 1 段。カメラが傾いて
  /// 列が斜めに写っていても 1 段として扱う（水平の帯で判定すると ±6° ほどで外れる）。
  static bool _isSingleRow(List<TileDetection> ordered) {
    final heights = [for (final d in ordered) d.box.height]..sort();
    final medianHeight = heights[heights.length ~/ 2];
    final tolerance = medianHeight * 0.6;
    final xs = [for (final d in ordered) d.box.center.dx];
    final ys = [for (final d in ordered) d.box.center.dy];
    final n = ordered.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var sxx = 0.0;
    var sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sxx += (xs[i] - mx) * (xs[i] - mx);
      sxy += (xs[i] - mx) * (ys[i] - my);
    }
    if (sxx <= 1e-12) return false;
    final slope = sxy / sxx;
    // 45° を超える傾きは列ではない。
    if (slope.abs() > 1) return false;
    for (var i = 0; i < n; i++) {
      final residual = ys[i] - (my + slope * (xs[i] - mx));
      if (residual.abs() > tolerance) return false;
      if (i > 0) {
        final step = (ys[i] - ys[i - 1]) - slope * (xs[i] - xs[i - 1]);
        if (step.abs() > tolerance) return false;
      }
    }
    return true;
  }
}
