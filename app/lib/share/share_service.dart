// 流用元: reference/agari_cam/lib/share/share_service.dart（2026-10-21 時点）
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:gal/gal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/share/share_target.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class ShareOutcome {
  const ShareOutcome({required this.completed, required this.target});

  final bool completed;
  // share_target の固定値（x / instagram / line / ...）。
  final String target;
}

/// 共有画像の書き出しと共有シート・写真保存をまとめる。
class ShareService {
  const ShareService();

  /// 次のフレームが終わるのを待ってから、[key] の RepaintBoundary を [pixelRatio] 倍で PNG にする。
  Future<Uint8List> capture(GlobalKey key, {required double pixelRatio}) async {
    await WidgetsBinding.instance.endOfFrame;
    return captureNow(key, pixelRatio: pixelRatio);
  }

  /// フレームを待たず、いま描かれている内容を PNG にする（描画済みと分かっているとき。テスト用）。
  Future<Uint8List> captureNow(
    GlobalKey key, {
    required double pixelRatio,
  }) async {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw StateError('Share image is not ready');
    }
    final image = await renderObject.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) throw StateError('Could not encode share image');
    return data.buffer.asUint8List();
  }

  /// [capture] したあと、PNG が [maxBytes] を超えたら解像度を段階的に下げて撮り直す
  /// （問題カードの Storage の上限は 900KB。`app/storage.rules`）。最後まで超えたら最小のものを返す。
  Future<Uint8List> captureWithinLimit(
    GlobalKey key, {
    required double pixelRatio,
    int maxBytes = 900 * 1024,
    List<double> scales = const [1.0, 0.85, 0.7, 0.55],
  }) async {
    Uint8List? smallest;
    for (final scale in scales) {
      final png = await capture(key, pixelRatio: pixelRatio * scale);
      if (png.lengthInBytes <= maxBytes) return png;
      if (smallest == null || png.lengthInBytes < smallest.lengthInBytes) {
        smallest = png;
      }
    }
    return smallest!;
  }

  Future<XFile> writeTemp(
    Uint8List png, {
    String prefix = 'nanikiru_cam',
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(png, flush: true);
    return XFile(file.path, mimeType: 'image/png');
  }

  Future<ShareOutcome> shareFiles(
    List<XFile> files, {
    required String text,
    required String subject,
    Rect? origin,
  }) async {
    final result = await Share.shareXFiles(
      files,
      text: text,
      subject: subject,
      sharePositionOrigin: origin,
    );
    return ShareOutcome(
      completed: result.status == ShareResultStatus.success,
      target: shareTargetBucket(result.raw),
    );
  }

  /// 写真アプリに保存する。権限がなければ要求し、拒否されたら false。
  Future<bool> saveToPhotos(Uint8List png, {required String album}) async {
    if (!await Gal.hasAccess(toAlbum: true)) {
      if (!await Gal.requestAccess(toAlbum: true)) return false;
    }
    await Gal.putImageBytes(
      png,
      album: album,
      name: 'nanikiru_cam_${DateTime.now().millisecondsSinceEpoch}',
    );
    return true;
  }

  static Rect originFrom(BuildContext anchor) {
    final renderObject = anchor.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final size = renderObject.size;
      if (size.width > 0 && size.height > 0) {
        return renderObject.localToGlobal(Offset.zero) & size;
      }
    }
    final screen = MediaQuery.sizeOf(anchor);
    return Rect.fromLTWH(screen.width / 2, screen.height / 2, 1, 1);
  }
}

final shareServiceProvider = Provider<ShareService>(
  (ref) => const ShareService(),
);
