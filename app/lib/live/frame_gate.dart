import 'package:nanikiru_cam/live/tile_tracker.dart';

/// カメラのフレームを推論に回すかを決める門（設計書 3.3）。
///
/// - 推論中（[busy]）に来たフレームは捨てる（キューに溜めない）。
/// - 前に通したフレームから `1 / targetFps` 秒経っていなければ捨てる（間引き）。
///
/// 時刻は呼び出し側が渡す（テストでは偽の時計）。
class FrameGate {
  FrameGate({double targetFps = 5}) : _targetFps = _sanitize(targetFps);

  double _targetFps;
  bool _busy = false;
  Duration? _lastAccepted;

  /// 通したフレーム数。
  int accepted = 0;

  /// 推論中で捨てたフレーム数。
  int droppedBusy = 0;

  /// 間引きで捨てたフレーム数。
  int droppedRate = 0;

  double get targetFps => _targetFps;
  set targetFps(double value) => _targetFps = _sanitize(value);

  bool get busy => _busy;

  /// 通す間隔。カメラのフレーム間隔の揺れで 1 枚余計に待たないよう、少し（1 割、最大 20ms）
  /// 短く見る。
  Duration get interval {
    final micros = 1e6 / _targetFps;
    final slack = (micros * 0.1).clamp(0, 20000);
    return Duration(microseconds: (micros - slack).round());
  }

  /// [now] のフレームを推論に回すなら true（[release] を呼ぶまで [busy]）。
  bool tryAcquire(Duration now) {
    if (_busy) {
      droppedBusy++;
      return false;
    }
    final last = _lastAccepted;
    if (last != null && now - last < interval) {
      droppedRate++;
      return false;
    }
    _busy = true;
    _lastAccepted = now;
    accepted++;
    return true;
  }

  /// 推論が終わった（成功・失敗を問わない）。
  void release() => _busy = false;

  /// 間引きの基準を消す（一時停止の後など、次のフレームをすぐ通す）。
  void reset() {
    _busy = false;
    _lastAccepted = null;
  }

  static double _sanitize(double fps) =>
      fps.isFinite && fps > 0 ? fps.clamp(0.2, 60.0) : 5;
}

/// 目標 fps の決め方（設計書 3.3・15 章）。
///
/// - 手が動いている・探している間は [movingFps]（5〜8 fps）。
/// - stable が [slowdownAfter]（3 秒）続き、最新のフレームも一致していれば [stableFps]（2 fps）。
/// - 端末の温度警告が出ていれば [thermalFps]（1 fps）。
class LiveFrameRatePolicy {
  const LiveFrameRatePolicy({
    this.movingFps = 6,
    this.stableFps = 2,
    this.thermalFps = 1,
    this.slowdownAfter = const Duration(seconds: 3),
  });

  /// Remote Config の `live_target_fps`（`ModelConfig.liveTargetFps`）から作る。5〜8 に収める。
  factory LiveFrameRatePolicy.fromTarget(double liveTargetFps) =>
      LiveFrameRatePolicy(
        movingFps: liveTargetFps.isFinite ? liveTargetFps.clamp(5.0, 8.0) : 6,
      );

  final double movingFps;
  final double stableFps;
  final double thermalFps;
  final Duration slowdownAfter;

  double targetFps({
    required TrackerSnapshot snapshot,
    required bool thermalWarning,
  }) {
    if (thermalWarning) return thermalFps;
    if (snapshot.isStable &&
        snapshot.rawAgrees &&
        snapshot.stableFor >= slowdownAfter) {
      return stableFps;
    }
    return movingFps;
  }
}
