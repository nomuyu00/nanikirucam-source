import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/live/live_camera.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/live_detector.dart';
import 'package:nanikiru_cam/live/live_device.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';

/// 手牌の検出枠を横一列に作る（正立フレームに対する 0〜1）。
///
/// [angleDeg] は列の傾き（度、時計回りが正。画面の y は下向き）。牌の中心を列の中央を軸に回し、
/// 枠は回した牌の外接矩形（検出器の軸に沿った枠と同じ）にする。[dx]・[dy] は手全体の平行移動。
List<LiveTileBox> handBoxes(
  List<String> labels, {
  List<double>? scores,
  double left = 0.1,
  double right = 0.9,
  double y = 0.5,
  double jitter = 0,
  int seed = 0,
  double angleDeg = 0,
  double dx = 0,
  double dy = 0,
}) {
  final n = labels.length;
  if (n == 0) return const [];
  final pitch = (right - left) / n;
  final w = pitch * 0.9;
  final h = w * 1.33;
  var s = seed;
  double noise() {
    // 決まった並びの小さな揺れ（線形合同法）。
    s = (s * 1103515245 + 12345) & 0x7fffffff;
    return ((s / 0x7fffffff) - 0.5) * 2 * jitter;
  }

  final a = angleDeg * math.pi / 180;
  final cosA = math.cos(a);
  final sinA = math.sin(a);
  final midX = (left + right) / 2;
  final boxW = (w * cosA).abs() + (h * sinA).abs();
  final boxH = (w * sinA).abs() + (h * cosA).abs();
  return [
    for (var i = 0; i < n; i++)
      () {
        final along = left + pitch * (i + 0.5) - midX;
        final center = Offset(
          midX + along * cosA + dx + noise(),
          y + along * sinA + dy + noise(),
        );
        return LiveTileBox(
          box: Rect.fromCenter(center: center, width: boxW, height: boxH),
          label: labels[i],
          score: scores == null ? 0.92 : scores[i],
        );
      }(),
  ];
}

TrackerObservation obs(
  int ms,
  List<LiveTileBox> tiles, {
  double luminance = 0.5,
  double sharpness = 0,
}) => TrackerObservation(
  timestamp: Duration(milliseconds: ms),
  tiles: tiles,
  luminance: luminance,
  sharpness: sharpness,
);

/// 記録したフレーム列（1 行 1 フレーム: `時刻ms 輝度 牌[:確度] …`、`#` 以降は注釈）を読む。
List<TrackerObservation> parseRecording(String text) {
  final result = <TrackerObservation>[];
  for (final raw in text.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;
    final parts = line.split(RegExp(r'\s+'));
    final ms = int.parse(parts[0]);
    final lum = double.parse(parts[1]);
    final labels = <String>[];
    final scores = <double>[];
    for (final token in parts.skip(2)) {
      final kv = token.split(':');
      labels.add(kv[0]);
      scores.add(kv.length > 1 ? double.parse(kv[1]) : 0.92);
    }
    result.add(
      obs(
        ms,
        handBoxes(labels, scores: scores, seed: ms),
        luminance: lum,
      ),
    );
  }
  return result;
}

/// 時刻を手で進める時計。
class ManualLiveClock implements LiveClock {
  Duration now = Duration.zero;

  @override
  Duration get elapsed => now;
}

/// 決めた検出を返す検出器。
class ScriptedDetector implements LiveDetector {
  ScriptedDetector({this.next});

  /// 次のフレームの検出（null なら何も見つからない）。
  List<LiveTileBox> Function()? next;
  double luminance = 0.5;

  /// 次のフレームの鮮鋭度（0 は測っていない）。
  double sharpness = 0;
  bool loaded = false;
  bool failLoad = false;
  int calls = 0;

  /// 1 フレームの前処理・推論にかかったことにする時間（マイクロ秒）。
  int preprocessMicros = 0;
  int inferenceMicros = 0;

  /// 今動いているモデル（自動切り替えのテスト用）。
  @override
  String? activeModel;
  final List<String> switchRequests = [];
  bool failSwitch = false;

  /// 切り替えをここで止めておけるようにする（null なら即座に終わる）。
  Completer<void>? switchGate;

  @override
  String? get modelLabel => activeModel;

  @override
  Future<bool> switchModel(String asset) async {
    switchRequests.add(asset);
    await switchGate?.future;
    if (failSwitch) return false;
    activeModel = asset;
    return true;
  }

  @override
  bool get isReady => loaded;

  @override
  Future<void> load() async {
    if (failLoad) throw StateError('model missing');
    loaded = true;
  }

  @override
  Future<LiveDetections> detect(LiveFrame frame, {required int quarterTurns}) {
    calls++;
    return Future.value(
      LiveDetections(
        tiles: next?.call() ?? const [],
        luminance: luminance,
        sharpness: sharpness,
        preprocessMicros: preprocessMicros,
        inferenceMicros: inferenceMicros,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

/// 偽のカメラ（[emit] でフレームを送る）。
class FakeLiveCamera extends ChangeNotifier implements LiveCamera {
  bool active = false;
  LiveCameraError? failure;
  int activations = 0;
  void Function(LiveFrame frame)? listener;
  bool torchOn = false;

  static final LiveFrame frame = LiveFrame(
    format: LiveFrameFormat.bgra8888,
    width: 4,
    height: 8,
    planes: [LivePlane(bytes: Uint8List(4 * 8 * 4), bytesPerRow: 16)],
  );

  @override
  bool get isReady => active && failure == null;

  @override
  bool get isInitializing => false;

  @override
  LiveCameraError? get error => active ? failure : null;

  @override
  double get previewAspectRatio => 9 / 16;

  @override
  int get sensorOrientation => 90;

  @override
  set onFrame(void Function(LiveFrame frame)? value) => listener = value;

  @override
  Future<void> setActive(bool value) async {
    if (value == active) return;
    active = value;
    if (value) activations++;
    notifyListeners();
  }

  @override
  Future<void> retry() async {
    failure = null;
    notifyListeners();
  }

  /// 1 フレーム送る（カメラが動いていなければ何もしない）。
  void emit() {
    if (!isReady) return;
    listener?.call(frame);
  }

  @override
  Widget buildPreview() => const SizedBox.expand(key: ValueKey('fake-preview'));

  @override
  Future<bool> setTorch(bool on) async {
    torchOn = on;
    return true;
  }
}

class FakeLiveDevice implements LiveDevice {
  ThermalStatus thermalStatus = ThermalStatus.normal;
  BatteryStatus batteryStatus = const BatteryStatus(level: 80);
  final screenOn = <bool>[];
  final brightnessLocks = <bool>[];

  @override
  Future<void> keepScreenOn(bool on) async => screenOn.add(on);

  @override
  Future<void> lockBrightness(bool lock) async => brightnessLocks.add(lock);

  @override
  Future<ThermalStatus> thermal() async => thermalStatus;

  @override
  Future<BatteryStatus> battery() async => batteryStatus;
}

/// 別 Isolate を使わずに解析する（テストの偽の時間でも完了する）。
AnalysisService inProcessAnalysis() => AnalysisService(
  runner: (hand, deep) async =>
      DefaultNanikiruEngine().analyze(hand, deep: deep),
);

/// 記録した解析イベント。
class RecordedEvent {
  const RecordedEvent(this.name, this.parameters);
  final String name;
  final Map<String, Object> parameters;

  @override
  String toString() => '$name$parameters';
}

@immutable
class HandFixtures {
  const HandFixtures._();

  /// 一向聴の 14 枚（萬子の 2 面子、筒子の搭子と面子、索子の搭子、孤立の東）。
  static const fourteen = [
    '1m', '2m', '3m', '4m', '5m', '6m', '3p', '4p', //
    '7p', '8p', '9p', '2s', '3s', '1z',
  ];

  /// 和了形の 14 枚（123m 456m 789p 234s 白白）。
  static const win = [
    '1m', '2m', '3m', '4m', '5m', '6m', '7p', '8p', //
    '9p', '2s', '3s', '4s', '5z', '5z',
  ];
}
