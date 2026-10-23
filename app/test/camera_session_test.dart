// 流用元: reference/agari_cam/test/camera_session_test.dart（2026-10-21 時点）
import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/camera/camera_session.dart';

// Shared test support is outside lib/.
// ignore: always_use_package_imports
import 'support/fake_camera_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CameraPlatform previousPlatform;
  late FakeCameraPlatform platform;
  late CameraSession session;
  var sessionDisposed = false;

  setUp(() {
    previousPlatform = CameraPlatform.instance;
    platform = FakeCameraPlatform();
    CameraPlatform.instance = platform;
    session = CameraSession();
    sessionDisposed = false;
  });

  tearDown(() async {
    if (!sessionDisposed) session.dispose();
    await Future<void>.delayed(Duration.zero);
    CameraPlatform.instance = previousPlatform;
  });

  test(
    'prefers the rear wide lens, bounded resolution and platform image format',
    () async {
      platform.cameras = [
        const CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 90,
        ),
        const CameraDescription(
          name: 'back-ultra-wide',
          lensDirection: CameraLensDirection.back,
          sensorOrientation: 90,
          lensType: CameraLensType.ultraWide,
        ),
        wideBackCamera,
      ];

      await session.setActive(true);

      expect(platform.created.single, wideBackCamera);
      expect(
        platform.settings.single.resolutionPreset,
        ResolutionPreset.veryHigh,
      );
      expect(platform.settings.single.enableAudio, isFalse);
      expect(platform.imageFormats.single, ImageFormatGroup.unknown);
      expect(platform.orientationLocks.single, DeviceOrientation.portraitUp);
      expect(session.controller?.value.isInitialized, isTrue);
      expect(session.isInitializing, isFalse);
      expect(session.error, isNull);
    },
  );

  test('does not silently substitute the front camera', () async {
    platform.cameras = [
      const CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 90,
      ),
    ];
    await session.setActive(true);
    expect(session.error?.code, 'NoBackCamera');
    expect(platform.created, isEmpty);
  });

  test('reports an empty camera list and can retry', () async {
    platform.cameras = [];
    await session.setActive(true);
    expect(session.error?.code, 'NoCameraAvailable');
    expect(session.isInitializing, isFalse);

    platform.cameras = [wideBackCamera];
    await session.retry();
    expect(session.controller, isNotNull);
    expect(session.error, isNull);
  });

  test(
    'disposal during camera discovery never creates a native camera',
    () async {
      final available = Completer<List<CameraDescription>>();
      platform.availableResult = available;
      final starting = session.setActive(true);
      await Future<void>.delayed(Duration.zero);
      session.dispose();
      sessionDisposed = true;

      available.complete([wideBackCamera]);
      await starting;
      expect(platform.created, isEmpty);
    },
  );

  test('suspending during discovery discards the result', () async {
    final available = Completer<List<CameraDescription>>();
    platform.availableResult = available;
    final starting = session.setActive(true);
    await Future<void>.delayed(Duration.zero);
    final suspending = session.setActive(false);
    available.complete([wideBackCamera]);
    await Future.wait([starting, suspending]);

    expect(platform.created, isEmpty);
    expect(session.controller, isNull);
    expect(session.isInitializing, isFalse);
  });

  test(
    'disposal waits for native initialization before releasing its handle',
    () async {
      final initializing = Completer<void>();
      platform.initializeGate = initializing;
      final starting = session.setActive(true);
      await Future<void>.delayed(Duration.zero);
      expect(platform.events, contains('initialize:1'));

      session.dispose();
      sessionDisposed = true;
      expect(platform.disposedIds, isEmpty);
      initializing.complete();
      await starting;
      await Future<void>.delayed(Duration.zero);
      expect(platform.disposedIds, [1]);
    },
  );

  test('rapid suspend/resume serializes disposal before replacement', () async {
    final initializing = Completer<void>();
    final disposing = Completer<void>();
    platform.initializeGate = initializing;
    platform.disposeGate = disposing;
    final starting = session.setActive(true);
    await Future<void>.delayed(Duration.zero);

    final suspending = session.setActive(false);
    final resuming = session.setActive(true);
    final suspendingAgain = session.setActive(false);
    final resumingAgain = session.setActive(true);
    initializing.complete();
    await Future<void>.delayed(Duration.zero);
    expect(platform.events, contains('dispose-start:1'));
    expect(platform.created, hasLength(1));

    disposing.complete();
    await Future.wait([
      starting,
      suspending,
      resuming,
      suspendingAgain,
      resumingAgain,
    ]);
    expect(platform.created, hasLength(2));
    expect(platform.disposedIds, [1]);
    expect(
      platform.events.indexOf('disposed:1'),
      lessThan(platform.events.indexOf('create:2')),
    );
    expect(session.controller?.cameraId, 2);
  });

  test(
    'initialization failure releases the failed handle and retry recovers',
    () async {
      platform.initializeFailure = CameraException(
        'CameraAccessDenied',
        'Permission denied',
      );
      await session.setActive(true);
      expect(session.error?.code, 'CameraAccessDenied');
      expect(session.controller, isNull);
      expect(session.isInitializing, isFalse);
      expect(platform.disposedIds, [1]);

      await Future.wait([session.retry(), session.retry()]);
      expect(platform.created, hasLength(2));
      expect(session.controller, isNotNull);
      expect(session.error, isNull);
    },
  );

  test(
    'unsupported optional focus/exposure settings do not block preview',
    () async {
      platform.failOptionalSettings = true;
      await session.setActive(true);
      expect(session.controller?.value.isInitialized, isTrue);
      expect(session.error, isNull);
    },
  );

  test('native camera errors notify the UI and allow retry', () async {
    await session.setActive(true);
    var notifications = 0;
    session.addListener(() => notifications++);
    platform.errors.add(const CameraErrorEvent(1, 'Camera disconnected'));
    await Future<void>.delayed(Duration.zero);

    expect(session.error?.code, 'CameraError');
    expect(session.error?.description, 'Camera disconnected');
    expect(notifications, greaterThan(0));
    await session.retry();
    expect(session.controller?.cameraId, 2);
    expect(session.error, isNull);
    expect(platform.disposedIds, [1]);
  });

  test(
    'native errors during setup are visible before the preview is published',
    () async {
      platform.errorDuringOrientationLock =
          'Capture session interrupted during startup';
      await session.setActive(true);

      expect(session.error?.code, 'CameraError');
      expect(
        session.error?.description,
        'Capture session interrupted during startup',
      );
      expect(session.isInitializing, isFalse);

      await session.retry();
      expect(session.error, isNull);
      expect(session.controller?.cameraId, 2);
    },
  );
}
