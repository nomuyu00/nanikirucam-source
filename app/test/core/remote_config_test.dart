import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/remote_config.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

class _FakeRemoteConfig implements RemoteConfigBackend {
  _FakeRemoteConfig({this.available = true, this.values = const {}});

  final bool available;
  Map<String, Object?> values;
  int activateCalls = 0;
  int fetchCalls = 0;
  Object? activateError;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Map<String, Object?>> activate() async {
    activateCalls++;
    final error = activateError;
    if (error != null) throw error;
    return values;
  }

  @override
  Future<void> fetchForNextLaunch() async => fetchCalls++;
}

void main() {
  group('modelConfigFromRemote', () {
    test('空の値は既定値のまま', () {
      expect(
        modelConfigFromRemote({
          RemoteConfigKeys.photoModelVariant: '',
          RemoteConfigKeys.liveModelVariant: '',
          RemoteConfigKeys.scoreThreshold: 0.0,
          RemoteConfigKeys.liveTargetFps: 0.0,
        }),
        ModelConfig.defaults,
      );
      expect(modelConfigFromRemote(const {}), ModelConfig.defaults);
    });

    test('4 つのキーを ModelConfig に反映する', () {
      final config = modelConfigFromRemote({
        RemoteConfigKeys.photoModelVariant: 'int8',
        RemoteConfigKeys.liveModelVariant: 'live_s_int8',
        RemoteConfigKeys.scoreThreshold: 0.25,
        RemoteConfigKeys.liveTargetFps: 8,
      });
      expect(config.photoModels.first, ModelConfig.int8Model);
      expect(config.photoModels, contains(ModelConfig.fp32Model));
      expect(config.liveModel, ModelConfig.liveSInt8Model);
      // 明示された variant は固定の意図なので、ライブの自動切り替えをしない。
      expect(config.liveModelExplicit, isTrue);
      expect(config.scoreThreshold, 0.25);
      expect(config.liveTargetFps, 8);
    });

    test('未知のバリアントと範囲外・不正な数値は無視する', () {
      final config = modelConfigFromRemote({
        RemoteConfigKeys.photoModelVariant: 'mystery',
        RemoteConfigKeys.liveModelVariant: ' ',
        RemoteConfigKeys.scoreThreshold: 5.0,
        RemoteConfigKeys.liveTargetFps: 'abc',
      });
      expect(config, ModelConfig.defaults);
      expect(config.liveModelExplicit, isFalse);
    });

    test('文字列で届いた数値も読む', () {
      final config = modelConfigFromRemote({
        RemoteConfigKeys.scoreThreshold: '0.3',
        RemoteConfigKeys.liveTargetFps: '10',
      });
      expect(config.scoreThreshold, 0.3);
      expect(config.liveTargetFps, 10);
    });
  });

  group('remoteConfigStartupProvider', () {
    ProviderContainer container(_FakeRemoteConfig backend) {
      final c = ProviderContainer(
        overrides: [remoteConfigBackendProvider.overrideWithValue(backend)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('前回取得した値を modelConfigProvider に反映し、最新の値は次回のために取得する', () async {
      final backend = _FakeRemoteConfig(
        values: {RemoteConfigKeys.liveTargetFps: 7},
      );
      final c = container(backend);
      c.read(remoteConfigStartupProvider);
      await pumpEventQueue();
      expect(c.read(modelConfigProvider).liveTargetFps, 7);
      expect(backend.activateCalls, 1);
      expect(backend.fetchCalls, 1);
    });

    test('Firebase が使えなければ何もしない（既定値のまま）', () async {
      final backend = _FakeRemoteConfig(
        available: false,
        values: {RemoteConfigKeys.liveTargetFps: 7},
      );
      final c = container(backend);
      c.read(remoteConfigStartupProvider);
      await pumpEventQueue();
      expect(c.read(modelConfigProvider), ModelConfig.defaults);
      expect(backend.activateCalls, 0);
    });

    test('取得に失敗しても落ちず、既定値のまま', () async {
      final backend = _FakeRemoteConfig()..activateError = StateError('boom');
      final c = container(backend);
      c.read(remoteConfigStartupProvider);
      await pumpEventQueue();
      expect(c.read(modelConfigProvider), ModelConfig.defaults);
    });
  });
}
