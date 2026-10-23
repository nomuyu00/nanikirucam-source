// 流用元: reference/agari_cam/lib/camera/camera_session.dart（2026-10-21 時点）
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serializes native camera creation and disposal across route/lifecycle changes.
class CameraSession extends ChangeNotifier {
  CameraController? _ownedController;
  CameraController? controller;
  CameraException? error;
  bool isInitializing = false;
  bool _active = false;
  bool _disposed = false;
  int _revision = 0;
  Future<void> _pending = Future<void>.value();

  Future<void> setActive(bool active) {
    if (_disposed || _active == active) return _pending;
    _active = active;
    return _schedule();
  }

  Future<void> retry() {
    if (_disposed || !_active || isInitializing) return _pending;
    return _schedule();
  }

  Future<void> _schedule() {
    final revision = ++_revision;
    controller = null;
    error = null;
    isInitializing = _active;
    _notify();
    _pending = _pending.then((_) async {
      await _closeController();
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
      final backCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.back,
      );
      final selected = backCameras.isNotEmpty
          ? backCameras.firstWhere(
              (camera) => camera.lensType == CameraLensType.wide,
              orElse: () => backCameras.first,
            )
          : cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.external,
              orElse: () => throw CameraException(
                'NoBackCamera',
                'No rear camera available',
              ),
            );

      // iPhone 17's max preset can select compressed pixels unsupported by
      // Flutter textures. 1080p also bounds preview/capture memory consumption.
      final next = CameraController(
        selected,
        ResolutionPreset.veryHigh,
        enableAudio: false,
        // Still-image recognition does not consume raw image stream buffers.
        // Let the platform select its supported preview pixel format.
      );
      _ownedController = next;
      await next.initialize();
      if (!_isCurrent(revision)) return;
      await configureCaptureQuality(next);
      if (!_isCurrent(revision)) return;
      // 牌の表面はフラッシュで白飛びしやすい。必要なときは画面のライトで点灯する。
      try {
        await next.setFlashMode(FlashMode.off);
      } catch (error) {
        debugPrint('[CameraSession] Flash setting unavailable: $error');
      }
      if (!_isCurrent(revision)) return;
      try {
        await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } on CameraException catch (error) {
        debugPrint('[CameraSession] Orientation lock unavailable: $error');
      }
      if (!_isCurrent(revision)) return;
      controller = next;
      next.addListener(_onCameraChanged);
      // Native errors can arrive while the optional settings are configured,
      // before our listener is registered.
      _onCameraChanged();
    } catch (failure) {
      debugPrint('[CameraSession] Initialization failed: $failure');
      if (_isCurrent(revision)) {
        error = failure is CameraException
            ? failure
            : CameraException('CameraInitializationFailed', failure.toString());
      }
    } finally {
      if (controller == null) await _closeController();
      if (_isCurrent(revision)) {
        isInitializing = false;
        _notify();
      }
    }
  }

  void _onCameraChanged() {
    final current = controller;
    if (current == null || !current.value.hasError) return;
    error = CameraException('CameraError', current.value.errorDescription);
    _notify();
  }

  Future<void> _closeController() async {
    final previous = _ownedController;
    _ownedController = null;
    if (previous == null) return;
    previous.removeListener(_onCameraChanged);
    try {
      await previous.dispose();
    } catch (error) {
      debugPrint('[CameraSession] Disposal failed: $error');
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
    controller = null;
    // Let an in-flight initialize complete before disposing its native handle.
    _pending = _pending.then((_) => _closeController());
    super.dispose();
  }
}

Future<void> configureCaptureQuality(CameraController controller) async {
  for (final configure in <Future<void> Function()>[
    () => controller.setFocusMode(FocusMode.auto),
    () => controller.setExposureMode(ExposureMode.auto),
    () => controller.setFocusPoint(const Offset(0.5, 0.5)),
    () => controller.setExposurePoint(const Offset(0.5, 0.5)),
  ]) {
    try {
      await configure();
    } on CameraException catch (error) {
      debugPrint(
        '[CameraSession] Optional capture setting unavailable: $error',
      );
    }
  }
}
