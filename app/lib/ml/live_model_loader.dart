import 'package:flutter/foundation.dart';

/// 開けなかったモデルとその理由。
class LiveModelFailure {
  const LiveModelFailure(this.asset, this.error);

  final String asset;
  final Object error;

  @override
  String toString() => '$asset: $error';
}

/// [openFirstLiveModel] の結果。
class LiveModelOpening<T> {
  const LiveModelOpening({
    required this.value,
    required this.asset,
    required this.failures,
  });

  /// 開けたもの（ワーカーなど）。
  final T value;

  /// 開けたモデルのアセットのパス。
  final String asset;

  /// それより前に試して開けなかったモデル（空なら先頭のモデルで動いている）。
  final List<LiveModelFailure> failures;

  /// 先頭の候補ではなく、控えのモデルで動いているか。
  bool get usedFallback => failures.isNotEmpty;
}

/// [assets] を先頭から順に [open] で開き、最初に成功したものを返す。
///
/// アセットが無い・壊れている・Remote Config の名前が不正、などで先頭が開けなくても、
/// 次の候補（写真用の int8）で続けるため。全部だめなら、理由を並べた [StateError] を投げる。
/// 切り替えたときは `[Live]` のログに、どのモデルがなぜだめだったかを出す。
Future<LiveModelOpening<T>> openFirstLiveModel<T>(
  List<String> assets,
  Future<T> Function(String asset) open,
) async {
  final failures = <LiveModelFailure>[];
  for (final asset in assets) {
    try {
      final value = await open(asset);
      if (failures.isEmpty) {
        debugPrint('[Live] model: $asset');
      } else {
        debugPrint(
          '[Live] model: $asset (fallback; failed: ${failures.join(' / ')})',
        );
      }
      return LiveModelOpening(value: value, asset: asset, failures: failures);
    } catch (error) {
      debugPrint('[Live] model load failed: $asset: $error');
      failures.add(LiveModelFailure(asset, error));
    }
  }
  throw StateError('No live model could be loaded: ${failures.join(' / ')}');
}

/// アセットのパス → 表示用の短い名前（`mahjong_yolo_live_n_int8`）。
String liveModelLabel(String asset) {
  final name = asset.split('/').last;
  return name.endsWith('.tflite')
      ? name.substring(0, name.length - '.tflite'.length)
      : name;
}
