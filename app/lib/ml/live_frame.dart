import 'dart:typed_data';
import 'dart:ui';

/// ライブナビの 1 フレームの画素の並び（設計書 3.3）。
///
/// - [yuv420]: Android の `YUV_420_888`（Y・U・V の 3 面。U/V は行と画素の間隔つき）、
///   iOS の `420YpCbCr8BiPlanar`（Y と CbCr の 2 面）。
/// - [nv21]: Y の後に VU が交互に並ぶ 1 面（Android）。
/// - [bgra8888]: iOS の BGRA（1 面）。
enum LiveFrameFormat { yuv420, nv21, bgra8888 }

/// フレームの 1 面。
class LivePlane {
  const LivePlane({
    required this.bytes,
    required this.bytesPerRow,
    this.bytesPerPixel = 1,
  });

  final Uint8List bytes;
  final int bytesPerRow;

  /// U/V 面の画素の間隔（Android の `pixelStride`）。不明なら 1。
  final int bytesPerPixel;
}

/// カメラの 1 フレーム（センサーの向きのまま）。
///
/// メモリ上で推論に使うだけで、保存も送信もしない（仕様 12 章）。
class LiveFrame {
  const LiveFrame({
    required this.format,
    required this.width,
    required this.height,
    required this.planes,
  });

  final LiveFrameFormat format;
  final int width;
  final int height;
  final List<LivePlane> planes;
}

/// 推論で見つけた牌 1 枚。
class LiveTileBox {
  const LiveTileBox({
    required this.box,
    required this.label,
    required this.score,
  });

  /// 正立させたフレーム（端末の向きに回したもの）全体に対する 0〜1 の枠。
  final Rect box;

  /// 牌ラベル（`1m`〜`9s`、`1z`〜`7z`、赤5は `0m` `0p` `0s`、裏向きは `0b`）。
  final String label;
  final double score;

  @override
  String toString() => 'LiveTileBox($label ${score.toStringAsFixed(2)} $box)';
}

/// 1 フレームの推論結果。
class LiveDetections {
  const LiveDetections({
    required this.tiles,
    required this.luminance,
    this.sharpness = 0,
    this.uprightWidth = 0,
    this.uprightHeight = 0,
    this.preprocessMicros = 0,
    this.inferenceMicros = 0,
  });

  /// 見つけた牌（並びは不定。並べるのは `TileTracker`）。
  final List<LiveTileBox> tiles;

  /// 推論に使った範囲の平均輝度（0〜1）。暗さの判定に使う。
  final double luminance;

  /// 推論に使った範囲の鮮鋭度（`liveSharpness`。隣の画素との輝度差の平均、0〜1）。
  /// 手ぶれで下がる。0 は「測っていない」。
  final double sharpness;

  /// 正立させたフレームの大きさ（画素）。
  final int uprightWidth;
  final int uprightHeight;

  /// 前処理（YUV/BGRA → RGB・回転・縮小）にかかった時間。
  final int preprocessMicros;

  /// 推論（`Interpreter.invoke`）にかかった時間。
  final int inferenceMicros;
}
