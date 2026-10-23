import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';
import 'package:nanikiru_cam/ml/live_inference_worker.dart';
import 'package:nanikiru_cam/ml/live_model_loader.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

/// ライブの 1 フレーム推論（設計書 3.3 `LiveDetector`）。テストでは偽物に差し替える。
abstract class LiveDetector {
  /// モデルを読み込む。失敗したら投げる。
  Future<void> load();

  bool get isReady;

  /// 今動いているモデルのアセットのパス（読み込み前や、分からないときは null）。
  String? get activeModel;

  /// debug 表示用のモデル名（控えのモデルなら "(fallback)" 付き）。
  String? get modelLabel;

  /// 動いているモデルを [asset] に差し替える（自動切り替え）。開けなければ今のモデルのまま false。
  Future<bool> switchModel(String asset);

  /// [frame] を [quarterTurns] 回（時計回り 90°）回して推論する。
  Future<LiveDetections> detect(LiveFrame frame, {required int quarterTurns});

  Future<void> dispose();
}

/// ワーカーを開く（テストでは差し替える）。[asset] を端末内のファイルにして別 Isolate で読み込む。
typedef LiveWorkerOpener =
    Future<LiveInferenceWorker> Function(
      String asset,
      List<String> labels,
      LiveInferenceConfig inference,
    );

Future<LiveInferenceWorker> _openAssetWorker(
  String asset,
  List<String> labels,
  LiveInferenceConfig inference,
) async {
  final path = await ensureLiveModelFile(asset);
  return LiveInferenceWorker.spawn(
    modelPath: path,
    labels: labels,
    config: inference,
  );
}

/// 端末に保存した、前回までの自動切り替えで落ちた段（なければ null）。
typedef LiveStoredTier = Future<String?> Function();

/// 軽量モデル（`ModelConfig.liveModel`、既定は YOLO11s の int8）を別 Isolate で動かす。
///
/// 先頭のモデルは [storedTier]（前回までに自動で落ちた段。Remote Config で variant が明示されて
/// いれば使わない）、なければ `config.liveModel`。読み込めなければ、写真用の int8 に切り替えて続ける
/// （[ModelConfig.liveCandidates]）。どれで動いているかは [activeModel]。
/// 実行中の差し替えは [switchModel]。
class TfliteLiveDetector implements LiveDetector {
  TfliteLiveDetector({
    required this.config,
    this.inference = const LiveInferenceConfig(),
    this.storedTier,
    @visibleForTesting LiveWorkerOpener? openWorker,
  }) : _openWorker = openWorker ?? _openAssetWorker;

  final ModelConfig config;
  final LiveInferenceConfig inference;
  final LiveStoredTier? storedTier;
  final LiveWorkerOpener _openWorker;
  LiveInferenceWorker? _worker;
  List<String> _labels = const [];
  Future<void>? _loading;
  bool _disposed = false;
  String? _activeModel;
  String? _fallbackFrom;

  /// 実際に読み込めたモデルのアセットのパス（読み込み前は null）。
  @override
  String? get activeModel => _activeModel;

  /// 先頭の候補が読み込めず、控えに切り替えたときの、読み込めなかった先頭のモデル。
  String? get fallbackFrom => _fallbackFrom;

  /// 画面の debug 表示用: `mahjong_yolo_live_s_int8`、控えなら `mahjong_yolo_int8 (fallback)`。
  @override
  String? get modelLabel {
    final active = _activeModel;
    if (active == null) return null;
    return _fallbackFrom == null
        ? liveModelLabel(active)
        : '${liveModelLabel(active)} (fallback)';
  }

  @override
  bool get isReady => _worker?.isAlive ?? false;

  @override
  Future<void> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    if (isReady || _disposed) return;
    final raw = await rootBundle.loadString(config.labelsAsset);
    final labels = raw
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    String? stored;
    try {
      stored = await storedTier?.call();
    } catch (error) {
      debugPrint('[Live] stored model tier unavailable: $error');
    }
    final opened = await openFirstLiveModel<LiveInferenceWorker>(
      config.liveCandidates(storedTier: stored),
      (asset) => _openWorker(asset, labels, inference),
    );
    final worker = opened.value;
    if (_disposed) {
      await worker.close();
      return;
    }
    _worker = worker;
    _labels = labels;
    _activeModel = opened.asset;
    _fallbackFrom = opened.usedFallback ? opened.failures.first.asset : null;
  }

  @override
  Future<bool> switchModel(String asset) async {
    if (_disposed || asset == _activeModel || _worker == null) return false;
    final LiveInferenceWorker next;
    try {
      next = await _openWorker(asset, _labels, inference);
    } catch (error) {
      debugPrint('[Live] model switch to $asset failed: $error');
      return false;
    }
    if (_disposed) {
      await next.close();
      return false;
    }
    final previous = _worker;
    final previousAsset = _activeModel;
    _worker = next;
    _activeModel = asset;
    _fallbackFrom = null;
    debugPrint('[Live] model switched: $previousAsset -> $asset');
    // 古いワーカーの推論待ちは「閉じた」エラーで終わる（呼び出し側は切り替え前の結果として捨てる）。
    await previous?.close();
    return true;
  }

  @override
  Future<LiveDetections> detect(LiveFrame frame, {required int quarterTurns}) {
    final worker = _worker;
    if (worker == null || !worker.isAlive) {
      return Future.error(StateError('Live model is not loaded'));
    }
    return worker.detect(frame, quarterTurns: quarterTurns);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final worker = _worker;
    _worker = null;
    await worker?.close();
  }
}
