// 流用元: reference/agari_cam/test/tflite_initialization_test.dart（2026-10-21 時点）
import 'dart:async';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
// Native handles are represented by inert pointers; no native library is loaded.
// ignore: implementation_imports
import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'concurrent initialization shares one future and one interpreter',
    () async {
      final labels = Completer<String>();
      final runtime = _FakeRuntime()..loadLabels = () => labels.future;
      final service = runtime.createService();
      addTearDown(service.dispose);

      final first = service.ensureInitialized();
      final second = service.ensureInitialized();
      expect(identical(first, second), isTrue);
      expect(service.isAvailable, isFalse);

      labels.complete('1m\n2m\n');
      await Future.wait([first, second]);
      await service.ensureInitialized();

      expect(runtime.labelLoads, 1);
      expect(runtime.interpreters, hasLength(1));
      expect(runtime.interpreters.single.allocations, 1);
      expect(runtime.options.single.deleted, isTrue);
      expect(service.isAvailable, isTrue);
      expect(service.labelsList, ['1m', '2m']);
    },
  );

  test('loads the models listed in ModelConfig, in order', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final runtime = _FakeRuntime()..failFp32Loading = true;
    final service = runtime.createService(
      config: const ModelConfig(
        photoModels: [
          'assets/models/custom_fp32.tflite',
          'assets/models/custom_int8.tflite',
        ],
      ),
    );
    addTearDown(service.dispose);

    await service.ensureInitialized();

    expect(service.isAvailable, isTrue);
    expect(runtime.assets.first, 'assets/models/custom_fp32.tflite');
    expect(runtime.assets.last, 'assets/models/custom_int8.tflite');
    expect(runtime.assets, everyElement(startsWith('assets/models/custom_')));
    expect(service.config.photoModels, hasLength(2));
  });

  test('Metal creation failure falls back to the FP32 CPU model', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final runtime = _FakeRuntime()..failMetalCreation = true;
    final service = runtime.createService();
    addTearDown(service.dispose);

    await service.ensureInitialized();

    expect(service.isAvailable, isTrue);
    expect(service.lastError, isNull);
    expect(runtime.assets, ['assets/models/mahjong_yolo_fp32.tflite']);
    expect(runtime.options, hasLength(2));
    expect(runtime.options.every((options) => options.deleted), isTrue);
    expect(runtime.options.last.threadCount, 4);
    expect(runtime.options.last.delegate, isNull);
  });

  test(
    'failed tensor allocation closes candidates and permits a later retry',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final runtime = _FakeRuntime()..failAllocation = true;
      final service = runtime.createService();
      addTearDown(service.dispose);

      await service.ensureInitialized();

      expect(service.isAvailable, isFalse);
      expect(service.lastError, contains('tensor allocation failed'));
      expect(runtime.interpreters, isNotEmpty);
      expect(
        runtime.interpreters.every((interpreter) => interpreter.closed),
        isTrue,
      );
      expect(runtime.options.every((options) => options.deleted), isTrue);

      runtime.failAllocation = false;
      await service.ensureInitialized();

      expect(service.isAvailable, isTrue);
      expect(service.lastError, isNull);
      expect(runtime.labelLoads, 2);
      expect(runtime.interpreters.last.closed, isFalse);
    },
  );

  test(
    'failed Metal interpreters close before their delegate and CPU fallback',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final runtime = _FakeRuntime()..failMetalAllocation = true;
      final service = runtime.createService();
      addTearDown(service.dispose);

      await service.ensureInitialized();

      expect(service.isAvailable, isTrue);
      expect(runtime.interpreters, hasLength(3));
      expect(
        runtime.interpreters.take(2).every((value) => value.closed),
        isTrue,
      );
      expect(runtime.interpreters.last.closed, isFalse);
      expect(runtime.delegates.single.deleted, isTrue);
      expect(
        runtime.events.indexOf('interpreter 1 closed'),
        lessThan(runtime.events.indexOf('delegate deleted')),
      );
      expect(
        runtime.events.indexOf('delegate deleted'),
        lessThan(runtime.events.indexOf('interpreter 2 opened')),
      );
      expect(runtime.assets.every((asset) => asset.contains('fp32')), isTrue);
    },
  );

  test(
    'successful Metal delegate stays alive until after interpreter disposal',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final runtime = _FakeRuntime();
      final service = runtime.createService();

      await service.ensureInitialized();

      expect(runtime.options.single.deleted, isTrue);
      expect(runtime.delegates.single.deleted, isFalse);
      expect(runtime.interpreters.single.closed, isFalse);

      service.dispose();

      expect(service.isAvailable, isFalse);
      expect(runtime.interpreters.single.closed, isTrue);
      expect(runtime.delegates.single.deleted, isTrue);
      expect(
        runtime.events.indexOf('interpreter 0 closed'),
        lessThan(runtime.events.indexOf('delegate deleted')),
      );
    },
  );

  test(
    'disposing during initialization releases the eventual native result',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final modelReady = Completer<void>();
      final runtime = _FakeRuntime()..modelReady = modelReady.future;
      final service = runtime.createService();
      var notifications = 0;
      service.addListener(() => notifications++);

      final initialization = service.ensureInitialized();
      await runtime.modelStarted.future;
      service.dispose();
      modelReady.complete();
      await initialization;
      await service.ensureInitialized();

      expect(service.isAvailable, isFalse);
      expect(notifications, 0);
      expect(runtime.interpreters.single.closed, isTrue);
      expect(runtime.options.single.deleted, isTrue);
      expect(runtime.delegates.single.deleted, isTrue);
      expect(runtime.labelLoads, 1);
    },
  );

  test(
    'FP32 loading failure tries both paths before falling back to INT8',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final runtime = _FakeRuntime()..failFp32Loading = true;
      final service = runtime.createService();
      addTearDown(service.dispose);

      await service.ensureInitialized();

      expect(service.isAvailable, isTrue);
      expect(runtime.assets, [
        'assets/models/mahjong_yolo_fp32.tflite',
        'assets/models/mahjong_yolo_fp32.tflite',
        'assets/models/mahjong_yolo_int8.tflite',
      ]);
      expect(runtime.fileAttempts, [true, false, true]);
      expect(runtime.options.every((options) => options.deleted), isTrue);
    },
  );
}

class _FakeRuntime {
  final options = <_FakeOptions>[];
  final delegates = <_FakeDelegate>[];
  final interpreters = <_FakeInterpreter>[];
  final assets = <String>[];
  final fileAttempts = <bool>[];
  final events = <String>[];
  final modelStarted = Completer<void>();
  Future<void>? modelReady;
  Future<String> Function() loadLabels = () async => '1m\n2m\n';
  int labelLoads = 0;
  bool failMetalCreation = false;
  bool failAllocation = false;
  bool failMetalAllocation = false;
  bool failFp32Loading = false;

  TfliteService createService({ModelConfig config = ModelConfig.defaults}) {
    return TfliteService.withRuntime(
      config: config,
      loadLabels: () {
        labelLoads++;
        return loadLabels();
      },
      createOptions: () {
        final value = _FakeOptions();
        options.add(value);
        return value;
      },
      createMetalDelegate: () {
        if (failMetalCreation) throw StateError('Metal unavailable');
        final value = _FakeDelegate(events);
        delegates.add(value);
        return value;
      },
      openModel: (asset, options, fromFile) async {
        assets.add(asset);
        fileAttempts.add(fromFile);
        if (failFp32Loading && asset.contains('fp32')) {
          throw StateError('FP32 model unavailable');
        }
        final value = _FakeInterpreter(
          id: interpreters.length,
          events: events,
          failAllocation:
              failAllocation ||
              (failMetalAllocation &&
                  (options as _FakeOptions).delegate != null),
        );
        interpreters.add(value);
        events.add('interpreter ${value.id} opened');
        if (!modelStarted.isCompleted) modelStarted.complete();
        if (modelReady != null) await modelReady;
        return value;
      },
    );
  }
}

class _FakeOptions implements tfl.InterpreterOptions {
  int? threadCount;
  tfl.Delegate? delegate;
  bool deleted = false;

  @override
  set threads(int value) => threadCount = value;

  @override
  void addDelegate(tfl.Delegate value) => delegate = value;

  @override
  void delete() {
    expect(deleted, isFalse);
    deleted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDelegate implements tfl.Delegate {
  _FakeDelegate(this.events);

  final List<String> events;
  bool deleted = false;

  @override
  Pointer<TfLiteDelegate> get base => Pointer.fromAddress(1);

  @override
  void delete() {
    expect(deleted, isFalse);
    events.add('delegate deleted');
    deleted = true;
  }
}

class _FakeInterpreter implements tfl.Interpreter {
  _FakeInterpreter({
    required this.id,
    required this.events,
    required this.failAllocation,
  });

  final int id;
  final List<String> events;
  final bool failAllocation;
  int allocations = 0;
  bool closed = false;

  @override
  tfl.Tensor getInputTensor(int index) => _FakeTensor();

  @override
  void allocateTensors() {
    allocations++;
    if (failAllocation) throw StateError('tensor allocation failed');
  }

  @override
  void close() {
    expect(closed, isFalse);
    events.add('interpreter $id closed');
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTensor implements tfl.Tensor {
  @override
  List<int> get shape => [1, 640, 640, 3];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
