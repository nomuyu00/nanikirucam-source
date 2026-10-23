// 流用元: reference/agari_cam/test/support/fake_camera_platform.dart（2026-10-21 時点）
import 'dart:async';
import 'dart:math';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const wideBackCamera = CameraDescription(
  name: 'back-wide',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
  lensType: CameraLensType.wide,
);

class FakeCameraPlatform extends CameraPlatform {
  List<CameraDescription> cameras = [wideBackCamera];
  Completer<List<CameraDescription>>? availableResult;
  Completer<void>? initializeGate;
  Completer<void>? disposeGate;
  Completer<XFile>? captureResult;
  CameraException? initializeFailure;
  String? errorDuringOrientationLock;
  bool failOptionalSettings = false;
  int availableCalls = 0;
  int captureCalls = 0;
  int _nextId = 0;
  final created = <CameraDescription>[];
  final settings = <MediaSettings>[];
  final imageFormats = <ImageFormatGroup>[];
  final disposedIds = <int>[];
  final events = <String>[];
  final orientationLocks = <DeviceOrientation>[];
  final _initialized = StreamController<CameraInitializedEvent>.broadcast();
  final errors = StreamController<CameraErrorEvent>.broadcast();

  @override
  Future<List<CameraDescription>> availableCameras() async {
    availableCalls++;
    return availableResult == null ? cameras : availableResult!.future;
  }

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async {
    created.add(cameraDescription);
    settings.add(mediaSettings);
    final id = ++_nextId;
    events.add('create:$id');
    return id;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    imageFormats.add(imageFormatGroup);
    events.add('initialize:$cameraId');
    await initializeGate?.future;
    final failure = initializeFailure;
    initializeFailure = null;
    if (failure != null) throw failure;
    _initialized.add(
      CameraInitializedEvent(
        cameraId,
        1920,
        1080,
        ExposureMode.auto,
        true,
        FocusMode.auto,
        true,
      ),
    );
    events.add('initialized:$cameraId');
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      _initialized.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      errors.stream.where((event) => event.cameraId == cameraId);

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Future<void> setFocusMode(int cameraId, FocusMode mode) async {
    if (failOptionalSettings) {
      throw CameraException('NotSupported', 'Focus mode');
    }
  }

  @override
  Future<void> setExposureMode(int cameraId, ExposureMode mode) async {
    if (failOptionalSettings) {
      throw CameraException('NotSupported', 'Exposure mode');
    }
  }

  @override
  Future<void> setFocusPoint(int cameraId, Point<double>? point) async {
    if (failOptionalSettings) {
      throw CameraException('NotSupported', 'Focus point');
    }
  }

  @override
  Future<void> setExposurePoint(int cameraId, Point<double>? point) async {
    if (failOptionalSettings) {
      throw CameraException('NotSupported', 'Exposure point');
    }
  }

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {
    orientationLocks.add(orientation);
    final error = errorDuringOrientationLock;
    errorDuringOrientationLock = null;
    if (error != null) {
      errors.add(CameraErrorEvent(cameraId, error));
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<void> dispose(int cameraId) async {
    events.add('dispose-start:$cameraId');
    await disposeGate?.future;
    disposedIds.add(cameraId);
    events.add('disposed:$cameraId');
  }

  @override
  Widget buildPreview(int cameraId) =>
      SizedBox(key: ValueKey('camera-preview-$cameraId'));

  @override
  Future<XFile> takePicture(int cameraId) async {
    captureCalls++;
    return captureResult == null
        ? XFile.fromData(Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg')
        : captureResult!.future;
  }
}
