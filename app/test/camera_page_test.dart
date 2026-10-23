// 流用元: reference/agari_cam/test/camera_page_test.dart（2026-10-21 時点）
import 'dart:async';
import 'dart:typed_data';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/camera/camera_page.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/route_observer.dart';
import 'package:nanikiru_cam/core/routes.dart';

// Shared test support is outside lib/.
// ignore: always_use_package_imports
import 'support/fake_camera_platform.dart';

void main() {
  late FakeCameraPlatform platform;
  late _RecordingAnalytics analytics;
  late GlobalKey<NavigatorState> navigatorKey;
  var recognitionVisits = 0;
  RecognitionLoadingArgs? recognitionArguments;
  RecognitionArgs? manualArguments;
  var manualVisits = 0;

  /// [args] を渡すと、その引数で撮影画面を開く（点数計算モードなど）。
  Future<void> pumpCamera(WidgetTester tester, {CameraArgs? args}) async {
    final previousPlatform = CameraPlatform.instance;
    CameraPlatform.instance = platform;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      CameraPlatform.instance = previousPlatform;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAnalyticsProvider.overrideWith((ref) => analytics),
          tfliteServiceProvider.overrideWith((ref) {
            throw StateError(
              'Camera preview must not initialize the ML service',
            );
          }),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [appRouteObserver],
          locale: const Locale('ja'),
          supportedLocales: const [Locale('ja')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: args == null ? const CameraPage() : null,
          initialRoute: args == null ? null : Routes.camera,
          onGenerateRoute: (settings) => settings.name == Routes.camera
              ? MaterialPageRoute<void>(
                  settings: RouteSettings(name: Routes.camera, arguments: args),
                  builder: (_) => const CameraPage(),
                )
              : null,
          routes: {
            Routes.manualInput: (context) {
              manualVisits++;
              manualArguments =
                  ModalRoute.of(context)!.settings.arguments
                      as RecognitionArgs?;
              return const Scaffold(body: Text('Test manual'));
            },
            Routes.settings: (context) => Scaffold(
              appBar: AppBar(title: const Text('Test settings')),
              body: const Text('Settings content'),
            ),
            Routes.recognitionLoading: (context) {
              recognitionVisits++;
              recognitionArguments =
                  ModalRoute.of(context)!.settings.arguments
                      as RecognitionLoadingArgs;
              return const Scaffold(body: Text('Test recognition'));
            },
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    platform = FakeCameraPlatform();
    analytics = _RecordingAnalytics();
    navigatorKey = GlobalKey<NavigatorState>();
    recognitionVisits = 0;
    recognitionArguments = null;
    manualArguments = null;
    manualVisits = 0;
  });

  testWidgets('点数計算モード: 見出しと案内が変わり、撮影・手入力にモードを引き継ぐ', (tester) async {
    await pumpCamera(tester, args: const CameraArgs(mode: HandEntryMode.score));
    expect(find.text('点数計算（写真）'), findsOneWidget);
    expect(find.textContaining('和了牌は少し離して右に'), findsOneWidget);

    await tester.tap(find.byType(RawMaterialButton));
    await tester.pumpAndSettle();
    expect(recognitionArguments?.mode, HandEntryMode.score);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    expect(manualArguments?.mode, HandEntryMode.score);
    expect(manualArguments?.draft.length, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('既定（何切る）の撮影はモードを付けない', (tester) async {
    await pumpCamera(tester);
    await tester.tap(find.byType(RawMaterialButton));
    await tester.pumpAndSettle();
    expect(recognitionArguments?.mode, HandEntryMode.solve);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.grid_view_rounded));
    await tester.pumpAndSettle();
    expect(manualVisits, 1);
    expect(manualArguments, isNull);
  });

  testWidgets('camera preview opens without creating the ML service', (
    tester,
  ) async {
    await pumpCamera(tester);
    expect(find.byKey(const ValueKey('camera-preview-1')), findsOneWidget);
    expect(analytics.events.map((event) => event.$1), [
      AnalyticsEvent.cameraOpened,
      AnalyticsEvent.cameraReady,
    ]);
    expect(
      tester
          .widget<RawMaterialButton>(find.byType(RawMaterialButton))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'permission denial provides settings guidance and retry recovers',
    (tester) async {
      platform.initializeFailure = CameraException(
        'CameraAccessDeniedWithoutPrompt',
        'Access denied',
      );
      await pumpCamera(tester);

      expect(find.textContaining('端末の「設定」で本アプリのカメラを許可'), findsOneWidget);
      expect(
        tester
            .widget<RawMaterialButton>(find.byType(RawMaterialButton))
            .onPressed,
        isNull,
      );

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-preview-2')), findsOneWidget);
      expect(find.text('再試行'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'opening settings releases the camera and returning recreates it',
    (tester) async {
      await pumpCamera(tester);
      await tester.tap(find.byIcon(Icons.settings));
      await tester.pumpAndSettle();
      expect(platform.disposedIds, [1]);
      expect(find.text('Settings content'), findsOneWidget);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(platform.created, hasLength(2));
      expect(find.byKey(const ValueKey('camera-preview-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'backgrounding releases the camera and foregrounding recreates it',
    (tester) async {
      await pumpCamera(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      // No rendered frame is guaranteed once the app is backgrounded.
      await tester.idle();
      expect(platform.disposedIds, [1]);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('camera-preview-2')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'rapid shutter taps produce one capture and one recognition route',
    (tester) async {
      final capture = Completer<XFile>();
      platform.captureResult = capture;
      await pumpCamera(tester);

      // Two events can arrive before the disabled button is rebuilt.
      await tester.tap(find.byType(RawMaterialButton));
      await tester.tap(find.byType(RawMaterialButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(platform.captureCalls, 1);
      expect(find.textContaining('撮影に失敗しました'), findsNothing);
      expect(
        tester
            .widget<RawMaterialButton>(find.byType(RawMaterialButton))
            .onPressed,
        isNull,
      );

      capture.complete(
        XFile.fromData(Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg'),
      );
      await tester.pumpAndSettle();
      expect(recognitionVisits, 1);
      expect(recognitionArguments?.imageBytes, orderedEquals([1, 2, 3]));
      expect(platform.disposedIds, [1]);
      expect(analytics.events.map((event) => event.$1), [
        AnalyticsEvent.cameraOpened,
        AnalyticsEvent.cameraReady,
        AnalyticsEvent.captureStarted,
        AnalyticsEvent.captureSucceeded,
      ]);
      expect(
        analytics.events.last.$2.keys,
        unorderedEquals(['source', 'duration_ms']),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native camera failure disables capture and offers recovery', (
    tester,
  ) async {
    await pumpCamera(tester);
    platform.errors.add(const CameraErrorEvent(1, 'Camera disconnected'));
    await tester.pumpAndSettle();

    expect(find.text('再試行'), findsOneWidget);
    expect(
      tester
          .widget<RawMaterialButton>(find.byType(RawMaterialButton))
          .onPressed,
      isNull,
    );
    expect(analytics.events.last.$1, AnalyticsEvent.cameraFailed);
    expect(analytics.events.last.$2, {
      'source': 'camera',
      'error_code': 'camera_start_failed',
    });
    await tester.tap(find.text('再試行'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('camera-preview-2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capture failure logs once without raw exception details', (
    tester,
  ) async {
    final capture = Completer<XFile>();
    platform.captureResult = capture;
    await pumpCamera(tester);
    await tester.tap(find.byType(RawMaterialButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    capture.completeError(StateError('private image path'));
    await tester.pumpAndSettle();

    expect(analytics.events.map((event) => event.$1), [
      AnalyticsEvent.cameraOpened,
      AnalyticsEvent.cameraReady,
      AnalyticsEvent.captureStarted,
      AnalyticsEvent.captureFailed,
    ]);
    expect(analytics.events.last.$2, {
      'source': 'camera',
      'duration_ms': isA<int>(),
      'error_code': 'capture_failed',
    });
    expect(recognitionVisits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late capture completion does not interrupt another route', (
    tester,
  ) async {
    final capture = Completer<XFile>();
    platform.captureResult = capture;
    await pumpCamera(tester);
    await tester.tap(find.byType(RawMaterialButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(platform.captureCalls, 1);

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();
    expect(platform.disposedIds, [1]);
    capture.complete(
      XFile.fromData(Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Settings content'), findsOneWidget);
    expect(recognitionVisits, 0);
    expect(find.textContaining('撮影に失敗しました'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _RecordingAnalytics extends ChangeNotifier implements AppAnalytics {
  final events = <(AnalyticsEvent, Map<String, Object>)>[];

  @override
  Future<void> logEvent(
    AnalyticsEvent event, {
    Map<String, Object> parameters = const {},
  }) async {
    events.add((event, Map<String, Object>.from(parameters)));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
