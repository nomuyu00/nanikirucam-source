import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';

/// カメラの失敗（コードは `CameraException.code`。画面の文言は camera_strings を使う）。
class LiveCameraError {
  const LiveCameraError(this.code, [this.message]);

  final String code;
  final String? message;

  bool get isPermission =>
      code == 'CameraAccessDenied' ||
      code == 'CameraAccessDeniedWithoutPrompt' ||
      code == 'CameraAccessRestricted';

  /// `camera_failed{error_code}` の値。
  String get analyticsCode => switch (code) {
    'CameraAccessDenied' ||
    'CameraAccessDeniedWithoutPrompt' ||
    'CameraAccessRestricted' => 'permission_denied',
    'NoCameraAvailable' || 'NoBackCamera' => 'camera_unavailable',
    _ => 'camera_start_failed',
  };
}

/// ライブ用のカメラ（プレビューと画像ストリーム）。テストでは偽物に差し替える。
abstract class LiveCamera implements Listenable {
  bool get isReady;
  bool get isInitializing;
  LiveCameraError? get error;

  /// 縦向きのプレビューの縦横比（幅 / 高さ）。
  double get previewAspectRatio;

  /// センサーの向き（度）。フレームを正立させる回転に使う。
  int get sensorOrientation;

  /// 画面に出ている間 true。false でカメラを解放する（背景・別画面・一時停止）。
  Future<void> setActive(bool active);

  Future<void> retry();

  /// 画像ストリームのフレームを受け取る（null で外す）。
  set onFrame(void Function(LiveFrame frame)? listener);

  Widget buildPreview();

  /// ライト（トーチ）。できなければ false。
  Future<bool> setTorch(bool on);

  void dispose();
}

/// `camera` プラグインの実装（`camera/camera_session.dart` と同じく生成・破棄を直列にする）。
///
/// 720p（`ResolutionPreset.high`）、Android は YUV420、iOS は BGRA でストリームを受ける。
/// プラットフォームチャネルの負荷と電池のため、カメラ自体の fps は [cameraFps] に抑える。
///
/// 手持ち撮影向けに、ピントと露出の基準点を中央（推論範囲の中心）にし、対応する iOS 端末では
/// 低遅延の手ぶれ補正（[VideoStabilizationMode.level1]）を試す。どれも非対応なら無視する。
class CameraLiveCamera extends ChangeNotifier implements LiveCamera {
  CameraLiveCamera({this.cameraFps = 15});

  final int cameraFps;

  CameraController? _owned;
  CameraController? _controller;
  CameraDescription? _description;
  LiveCameraError? _error;
  bool _initializing = false;
  bool _active = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _pending = Future<void>.value();
  void Function(LiveFrame frame)? _onFrame;

  @override
  bool get isReady => _controller != null && _error == null;

  @override
  bool get isInitializing => _initializing;

  @override
  LiveCameraError? get error => _error;

  @override
  double get previewAspectRatio {
    final size = _controller?.value.previewSize;
    if (size == null || size.width <= 0 || size.height <= 0) return 9 / 16;
    return size.shortestSide / size.longestSide;
  }

  @override
  int get sensorOrientation => _description?.sensorOrientation ?? 90;

  @override
  set onFrame(void Function(LiveFrame frame)? listener) => _onFrame = listener;

  @override
  Future<void> setActive(bool active) {
    if (_disposed || _active == active) return _pending;
    _active = active;
    return _schedule();
  }

  @override
  Future<void> retry() {
    if (_disposed || !_active || _initializing) return _pending;
    return _schedule();
  }

  Future<void> _schedule() {
    final revision = ++_revision;
    _controller = null;
    _error = null;
    _initializing = _active;
    _notify();
    _pending = _pending.then((_) async {
      await _close();
      if (!_isCurrent(revision)) return;
      await _initialize(revision);
    });
    return _pending;
  }

  bool _isCurrent(int revision) =>
      !_disposed && _active && revision == _revision;

  Future<void> _initialize(int revision) async {
    try {
      final cameras = await availableCameras();
      if (!_isCurrent(revision)) return;
      if (cameras.isEmpty) {
        throw CameraException('NoCameraAvailable', 'No camera available');
      }
      final back = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (back.isEmpty) {
        throw CameraException('NoBackCamera', 'No rear camera available');
      }
      final selected = back.firstWhere(
        (c) => c.lensType == CameraLensType.wide,
        orElse: () => back.first,
      );
      CameraController create({required bool limitFps}) => CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        fps: limitFps ? cameraFps : null,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      var next = create(limitFps: true);
      _owned = next;
      try {
        await next.initialize();
      } on CameraException catch (e) {
        // fps の指定に対応しない端末では、指定なしでやり直す。権限の拒否はそのまま失敗。
        if (LiveCameraError(e.code).isPermission) rethrow;
        debugPrint('[LiveCamera] fps-limited init failed: $e');
        await _close();
        if (!_isCurrent(revision)) return;
        next = create(limitFps: false);
        _owned = next;
        await next.initialize();
      }
      if (!_isCurrent(revision)) return;
      for (final configure in <Future<void> Function()>[
        () => next.setFlashMode(FlashMode.off),
        () => next.setFocusMode(FocusMode.auto),
        () => next.setExposureMode(ExposureMode.auto),
        () => next.setFocusPoint(const Offset(0.5, 0.5)),
        () => next.setExposurePoint(const Offset(0.5, 0.5)),
        () => next.lockCaptureOrientation(DeviceOrientation.portraitUp),
        () => _enableLowLatencyStabilization(next),
      ]) {
        try {
          await configure();
        } catch (e) {
          debugPrint('[LiveCamera] optional setting unavailable: $e');
        }
        if (!_isCurrent(revision)) return;
      }
      await next.startImageStream(_handleImage);
      if (!_isCurrent(revision)) return;
      _description = selected;
      _controller = next;
      next.addListener(_onCameraChanged);
      _onCameraChanged();
    } catch (failure) {
      debugPrint('[LiveCamera] initialization failed: $failure');
      if (_isCurrent(revision)) {
        _error = failure is CameraException
            ? LiveCameraError(failure.code, failure.description)
            : LiveCameraError('CameraInitializationFailed', '$failure');
      }
    } finally {
      if (_controller == null) await _close();
      if (_isCurrent(revision)) {
        _initializing = false;
        _notify();
      }
    }
  }

  void _handleImage(CameraImage image) {
    final listener = _onFrame;
    if (listener == null || _controller == null) return;
    final frame = liveFrameFromCameraImage(image);
    if (frame != null) listener(frame);
  }

  void _onCameraChanged() {
    final current = _controller;
    if (current == null || !current.value.hasError) return;
    _error = LiveCameraError('CameraError', current.value.errorDescription);
    _notify();
  }

  Future<void> _close() async {
    final previous = _owned;
    _owned = null;
    if (previous == null) return;
    previous.removeListener(_onCameraChanged);
    try {
      if (previous.value.isStreamingImages) await previous.stopImageStream();
    } catch (e) {
      debugPrint('[LiveCamera] stop stream failed: $e');
    }
    try {
      await previous.dispose();
    } catch (e) {
      debugPrint('[LiveCamera] disposal failed: $e');
    }
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null) return const ColoredBox(color: Colors.black);
    return CameraPreview(controller);
  }

  @override
  Future<bool> setTorch(bool on) async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      await controller.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      return true;
    } catch (e) {
      debugPrint('[LiveCamera] torch unavailable: $e');
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _active = false;
    ++_revision;
    _controller = null;
    _onFrame = null;
    _pending = _pending.then((_) => _close());
    super.dispose();
  }
}

/// 対応する端末なら、いちばん遅延の少ない手ぶれ補正（level1 = iOS の standard）にする。
/// 対応しなければ何もしない。
///
/// iOS だけ。iOS はプレビューも画像ストリームも同じ映像出力から来るので、補正で切り出しが
/// 変わっても枠の位置はずれない。Android（CameraX）の `CONTROL_VIDEO_STABILIZATION_MODE_ON`
/// は端末によって録画系の出力だけを補正し、プレビューと解析用の画像で切り出しがずれて案内の
/// 位置が合わなくなるおそれがあるため、実機で確かめるまで使わない。
Future<void> _enableLowLatencyStabilization(CameraController controller) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;
  final modes = await controller.getSupportedVideoStabilizationModes();
  if (!modes.contains(VideoStabilizationMode.level1)) return;
  await controller.setVideoStabilizationMode(
    VideoStabilizationMode.level1,
    allowFallback: true,
  );
}

/// `CameraImage` → [LiveFrame]（対応しない形式は null）。
LiveFrame? liveFrameFromCameraImage(CameraImage image) {
  final format = switch (image.format.group) {
    ImageFormatGroup.yuv420 => LiveFrameFormat.yuv420,
    ImageFormatGroup.nv21 => LiveFrameFormat.nv21,
    ImageFormatGroup.bgra8888 => LiveFrameFormat.bgra8888,
    _ => null,
  };
  if (format == null || image.planes.isEmpty) return null;
  if (format == LiveFrameFormat.yuv420 && image.planes.length < 2) return null;
  return LiveFrame(
    format: format,
    width: image.width,
    height: image.height,
    planes: [
      for (final p in image.planes)
        LivePlane(
          bytes: p.bytes,
          bytesPerRow: p.bytesPerRow,
          bytesPerPixel: p.bytesPerPixel ?? 1,
        ),
    ],
  );
}
