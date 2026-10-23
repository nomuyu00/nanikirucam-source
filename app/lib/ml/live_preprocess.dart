import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:nanikiru_cam/ml/live_frame.dart';

/// ライブの前処理（設計書 3.3）: 端末の向きで回転を固定 → 推論範囲を切り出し → 640 に
/// レターボックス。回転 4 方向の探索はしない。
///
/// 推論範囲（ROI）は、正立させたフレームの中央の正方形（縦向きなら横幅いっぱい）を既定にする。
/// 720p の縦向き（720×1280）を丸ごと 640 に縮めると牌が約 18px まで小さくなるため、
/// 横幅いっぱいの正方形（720×720 → 640、牌は約 32px）に絞る。画面にはこの範囲を枠で示す。

/// 640 入力の余白の色（YOLO の学習時と同じ灰色）。
const int liveLetterboxGray = 114;

/// フレームの幅・高さと [sensorOrientation] から、正立させるのに時計回りに回す回数。
///
/// 縦向き固定で使う前提。フレームが横長（センサーの向きのまま）なら、センサーの向きの分だけ
/// 回す。すでに縦長なら回さない（端末がフレームを回してから渡す場合）。
int liveQuarterTurns({
  required int sensorOrientation,
  required int width,
  required int height,
}) {
  if (width <= height) return 0;
  final turns = (sensorOrientation ~/ 90) % 4;
  return turns.isOdd ? turns : 1;
}

/// 正立させたフレームの中央の正方形（0〜1 の座標）。
Rect centeredSquareRoi(int uprightWidth, int uprightHeight) {
  if (uprightWidth <= 0 || uprightHeight <= 0) {
    return const Rect.fromLTRB(0, 0, 1, 1);
  }
  if (uprightWidth <= uprightHeight) {
    final h = uprightWidth / uprightHeight;
    final top = (1 - h) / 2;
    return Rect.fromLTRB(0, top, 1, top + h);
  }
  final w = uprightHeight / uprightWidth;
  final left = (1 - w) / 2;
  return Rect.fromLTRB(left, 0, left + w, 1);
}

/// 生のフレーム → 正立 → ROI → 640 入力 の座標変換。
class LiveInputTransform {
  const LiveInputTransform({
    required this.rawWidth,
    required this.rawHeight,
    required this.quarterTurns,
    required this.roiLeft,
    required this.roiTop,
    required this.roiWidth,
    required this.roiHeight,
    required this.inputSize,
    required this.outLeft,
    required this.outTop,
    required this.outWidth,
    required this.outHeight,
  });

  /// [roi] は正立させたフレームに対する 0〜1 の範囲。null なら [centeredSquareRoi]。
  factory LiveInputTransform.compute({
    required int rawWidth,
    required int rawHeight,
    required int quarterTurns,
    Rect? roi,
    int inputSize = 640,
  }) {
    final turns = quarterTurns % 4;
    final uw = turns.isOdd ? rawHeight : rawWidth;
    final uh = turns.isOdd ? rawWidth : rawHeight;
    final r = roi ?? centeredSquareRoi(uw, uh);
    final left = (r.left.clamp(0.0, 1.0) * uw);
    final top = (r.top.clamp(0.0, 1.0) * uh);
    final right = (r.right.clamp(0.0, 1.0) * uw);
    final bottom = (r.bottom.clamp(0.0, 1.0) * uh);
    final roiW = math.max(1.0, right - left);
    final roiH = math.max(1.0, bottom - top);
    final scale = math.min(inputSize / roiW, inputSize / roiH);
    final outW = math.max(1, math.min(inputSize, (roiW * scale).round()));
    final outH = math.max(1, math.min(inputSize, (roiH * scale).round()));
    return LiveInputTransform(
      rawWidth: rawWidth,
      rawHeight: rawHeight,
      quarterTurns: turns,
      roiLeft: left,
      roiTop: top,
      roiWidth: roiW,
      roiHeight: roiH,
      inputSize: inputSize,
      outLeft: (inputSize - outW) ~/ 2,
      outTop: (inputSize - outH) ~/ 2,
      outWidth: outW,
      outHeight: outH,
    );
  }

  final int rawWidth;
  final int rawHeight;
  final int quarterTurns;

  /// 正立させたフレーム上の ROI（画素）。
  final double roiLeft;
  final double roiTop;
  final double roiWidth;
  final double roiHeight;

  final int inputSize;

  /// 640 入力の中で ROI を描く範囲（画素）。外側は灰色の余白。
  final int outLeft;
  final int outTop;
  final int outWidth;
  final int outHeight;

  int get uprightWidth => quarterTurns.isOdd ? rawHeight : rawWidth;
  int get uprightHeight => quarterTurns.isOdd ? rawWidth : rawHeight;

  double get scaleX => outWidth / roiWidth;
  double get scaleY => outHeight / roiHeight;

  /// ROI を正立させたフレームに対する 0〜1 の範囲で。
  Rect get roiNormalized => Rect.fromLTWH(
    roiLeft / uprightWidth,
    roiTop / uprightHeight,
    roiWidth / uprightWidth,
    roiHeight / uprightHeight,
  );

  /// 640 入力上の枠 → 正立させたフレーム全体に対する 0〜1 の枠（ROI の外は切る）。
  Rect? toUprightNormalized(Rect inputBox) {
    double u(double x) => ((x - outLeft) / scaleX + roiLeft) / uprightWidth;
    double v(double y) => ((y - outTop) / scaleY + roiTop) / uprightHeight;
    final roi = roiNormalized;
    final rect = Rect.fromLTRB(
      u(inputBox.left).clamp(roi.left, roi.right),
      v(inputBox.top).clamp(roi.top, roi.bottom),
      u(inputBox.right).clamp(roi.left, roi.right),
      v(inputBox.bottom).clamp(roi.top, roi.bottom),
    );
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }
}

/// 1 軸ぶんの標本位置（双線形補間の 2 点と重み 0〜256）。
class _Axis {
  _Axis(int n) : i0 = Int32List(n), i1 = Int32List(n), w = Int32List(n);

  final Int32List i0;
  final Int32List i1;
  final Int32List w;

  void set(int k, double pixel, int size) {
    // 画素の中心を 0.5 とした連続座標 → 画素の添字。
    var p = pixel - 0.5;
    if (p < 0) p = 0;
    final maxIndex = size - 1;
    if (p > maxIndex) p = maxIndex.toDouble();
    final f = p.floor();
    i0[k] = f;
    i1[k] = f < maxIndex ? f + 1 : maxIndex;
    w[k] = ((p - f) * 256).round();
  }
}

/// [frame] を [t] に従って 640×640 の RGB（[out]、長さ 640*640*3）に描く。
/// 余白は [liveLetterboxGray]。戻り値は ROI の平均輝度（0〜1）。
///
/// 縮小は双線形 1 回（学習時の縮小と合わせる。handoff 5 章）。YUV の色差は最近傍。
double preprocessLiveFrame(
  LiveFrame frame,
  LiveInputTransform t,
  Uint8List out,
) {
  final s = t.inputSize;
  if (out.length < s * s * 3) {
    throw ArgumentError.value(out.length, 'out', '640*640*3 以上の長さが必要');
  }
  out.fillRange(0, s * s * 3, liveLetterboxGray);

  final w = frame.width;
  final h = frame.height;
  final turns = t.quarterTurns;
  final odd = turns.isOdd;

  // 出力の列（i）と行（j）ごとに、生フレームの座標を前もって求める。
  // 回転は 90° 単位なので、生フレームの x・y はそれぞれ列か行のどちらか一方だけで決まる。
  final cols = _Axis(t.outWidth);
  final rows = _Axis(t.outHeight);
  for (var i = 0; i < t.outWidth; i++) {
    final u = t.roiLeft + (i + 0.5) / t.scaleX;
    switch (turns) {
      case 0:
        cols.set(i, u, w); // x = u
      case 1:
        cols.set(i, h - u, h); // y = H - u
      case 2:
        cols.set(i, w - u, w); // x = W - u
      default:
        cols.set(i, u, h); // y = u
    }
  }
  for (var j = 0; j < t.outHeight; j++) {
    final v = t.roiTop + (j + 0.5) / t.scaleY;
    switch (turns) {
      case 0:
        rows.set(j, v, h); // y = v
      case 1:
        rows.set(j, v, w); // x = v
      case 2:
        rows.set(j, h - v, h); // y = H - v
      default:
        rows.set(j, w - v, w); // x = W - v
    }
  }

  return switch (frame.format) {
    LiveFrameFormat.bgra8888 => _bgra(frame, t, out, cols, rows, odd),
    LiveFrameFormat.yuv420 ||
    LiveFrameFormat.nv21 => _yuv(frame, t, out, cols, rows, odd),
  };
}

double _yuv(
  LiveFrame frame,
  LiveInputTransform t,
  Uint8List out,
  _Axis cols,
  _Axis rows,
  bool odd,
) {
  final s = t.inputSize;
  final yPlane = frame.planes[0];
  final yBytes = yPlane.bytes;
  final yStride = yPlane.bytesPerRow;

  // 色差の取り出し方: U と V の面（間隔つき）、または交互に並ぶ 1 面。
  late final Uint8List uBytes;
  late final Uint8List vBytes;
  late final int uvStride;
  late final int uvPixel;
  late final int uOffset;
  late final int vOffset;
  if (frame.format == LiveFrameFormat.nv21) {
    if (frame.planes.length >= 2) {
      uBytes = frame.planes[1].bytes;
      uvStride = frame.planes[1].bytesPerRow;
      uOffset = 1;
      vOffset = 0;
    } else {
      uBytes = yBytes;
      uvStride = yStride;
      // Y の後に VU が並ぶ。
      vOffset = yStride * frame.height;
      uOffset = vOffset + 1;
    }
    vBytes = uBytes;
    uvPixel = 2;
  } else if (frame.planes.length >= 3) {
    uBytes = frame.planes[1].bytes;
    vBytes = frame.planes[2].bytes;
    uvStride = frame.planes[1].bytesPerRow;
    uvPixel = math.max(1, frame.planes[1].bytesPerPixel);
    uOffset = 0;
    vOffset = 0;
  } else {
    // iOS の 2 面（CbCr が交互）。
    uBytes = frame.planes[1].bytes;
    vBytes = uBytes;
    uvStride = frame.planes[1].bytesPerRow;
    uvPixel = 2;
    uOffset = 0;
    vOffset = 1;
  }
  final uLast = uBytes.length - 1;
  final vLast = vBytes.length - 1;

  var lumaSum = 0;
  for (var j = 0; j < t.outHeight; j++) {
    final rj0 = rows.i0[j];
    final rj1 = rows.i1[j];
    final rjw = rows.w[j];
    var o = ((t.outTop + j) * s + t.outLeft) * 3;
    for (var i = 0; i < t.outWidth; i++) {
      int x0, x1, wx, y0, y1, wy;
      if (odd) {
        x0 = rj0;
        x1 = rj1;
        wx = rjw;
        y0 = cols.i0[i];
        y1 = cols.i1[i];
        wy = cols.w[i];
      } else {
        x0 = cols.i0[i];
        x1 = cols.i1[i];
        wx = cols.w[i];
        y0 = rj0;
        y1 = rj1;
        wy = rjw;
      }
      final r0 = y0 * yStride;
      final r1 = y1 * yStride;
      final p00 = yBytes[r0 + x0];
      final p01 = yBytes[r0 + x1];
      final p10 = yBytes[r1 + x0];
      final p11 = yBytes[r1 + x1];
      final top = (p00 << 8) + (p01 - p00) * wx;
      final bottom = (p10 << 8) + (p11 - p10) * wx;
      final yv = ((top << 8) + (bottom - top) * wy + 32768) >> 16;
      lumaSum += yv;

      final cx = (wx >= 128 ? x1 : x0) >> 1;
      final cy = (wy >= 128 ? y1 : y0) >> 1;
      final c = cy * uvStride + cx * uvPixel;
      var ui = c + uOffset;
      var vi = c + vOffset;
      if (ui > uLast) ui = uLast;
      if (vi > vLast) vi = vLast;
      final u = uBytes[ui] - 128;
      final v = vBytes[vi] - 128;
      // BT.601 フルレンジ（Android のカメラの YUV_420_888）。
      var r = yv + ((359 * v) >> 8);
      var g = yv - ((88 * u + 183 * v) >> 8);
      var b = yv + ((454 * u) >> 8);
      if (r < 0) {
        r = 0;
      } else if (r > 255) {
        r = 255;
      }
      if (g < 0) {
        g = 0;
      } else if (g > 255) {
        g = 255;
      }
      if (b < 0) {
        b = 0;
      } else if (b > 255) {
        b = 255;
      }
      out[o] = r;
      out[o + 1] = g;
      out[o + 2] = b;
      o += 3;
    }
  }
  final n = t.outWidth * t.outHeight;
  return n == 0 ? 0 : lumaSum / (n * 255);
}

double _bgra(
  LiveFrame frame,
  LiveInputTransform t,
  Uint8List out,
  _Axis cols,
  _Axis rows,
  bool odd,
) {
  final s = t.inputSize;
  final plane = frame.planes[0];
  final bytes = plane.bytes;
  final stride = plane.bytesPerRow;

  var lumaSum = 0;
  for (var j = 0; j < t.outHeight; j++) {
    final rj0 = rows.i0[j];
    final rj1 = rows.i1[j];
    final rjw = rows.w[j];
    var o = ((t.outTop + j) * s + t.outLeft) * 3;
    for (var i = 0; i < t.outWidth; i++) {
      int x0, x1, wx, y0, y1, wy;
      if (odd) {
        x0 = rj0;
        x1 = rj1;
        wx = rjw;
        y0 = cols.i0[i];
        y1 = cols.i1[i];
        wy = cols.w[i];
      } else {
        x0 = cols.i0[i];
        x1 = cols.i1[i];
        wx = cols.w[i];
        y0 = rj0;
        y1 = rj1;
        wy = rjw;
      }
      final a = y0 * stride + x0 * 4;
      final b = y0 * stride + x1 * 4;
      final c = y1 * stride + x0 * 4;
      final d = y1 * stride + x1 * 4;
      int lerp(int k) {
        final p00 = bytes[a + k];
        final p01 = bytes[b + k];
        final p10 = bytes[c + k];
        final p11 = bytes[d + k];
        final top = (p00 << 8) + (p01 - p00) * wx;
        final bottom = (p10 << 8) + (p11 - p10) * wx;
        return ((top << 8) + (bottom - top) * wy + 32768) >> 16;
      }

      final bl = lerp(0);
      final gr = lerp(1);
      final rd = lerp(2);
      lumaSum += (77 * rd + 150 * gr + 29 * bl) >> 8;
      out[o] = rd;
      out[o + 1] = gr;
      out[o + 2] = bl;
      o += 3;
    }
  }
  final n = t.outWidth * t.outHeight;
  return n == 0 ? 0 : lumaSum / (n * 255);
}

/// 640 入力（[rgb]、[preprocessLiveFrame] の出力）の推論範囲の鮮鋭度（0〜1）。
///
/// 緑（輝度の代わり）の、右と下の隣の画素との差の 2 乗の平均（勾配のエネルギー）。
/// [step] 画素おきに数える（既定 2: 約 10 万点）。差の絶対値の平均は、ぼけても縁の段差の
/// 合計が変わらず下がりにくいので 2 乗を使う（k 画素にぼけた縁はおよそ 1/k になる）。
/// 値そのものは被写体と明るさで大きく変わるので、使う側は直近の値との比で判断する
/// （`TileTracker`）。
double liveSharpness(Uint8List rgb, LiveInputTransform t, {int step = 2}) {
  final s = t.inputSize;
  final stride = s * 3;
  if (rgb.length < s * stride || t.outWidth < 2 || t.outHeight < 2) return 0;
  final x0 = t.outLeft;
  final y0 = t.outTop;
  final x1 = x0 + t.outWidth - 1;
  final y1 = y0 + t.outHeight - 1;
  var sum = 0;
  var n = 0;
  for (var y = y0; y < y1; y += step) {
    final rowStart = y * stride + 1; // 緑
    for (var x = x0; x < x1; x += step) {
      final i = rowStart + x * 3;
      final g = rgb[i];
      final dx = rgb[i + 3] - g;
      final dy = rgb[i + stride] - g;
      sum += dx * dx + dy * dy;
      n++;
    }
  }
  return n == 0 ? 0 : sum / (n * 2 * 255 * 255);
}
