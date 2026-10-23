import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

/// Remote Config のキー（設計書 3.4）。値が空・0 以下・未知の名前なら無視して既定値のまま。
abstract final class RemoteConfigKeys {
  static const photoModelVariant = 'photo_model_variant';
  static const liveModelVariant = 'live_model_variant';
  static const scoreThreshold = 'score_threshold';
  static const liveTargetFps = 'live_target_fps';
}

/// Remote Config から [ModelConfig] を組み立てる。範囲外の値は既定値にする。
ModelConfig modelConfigFromRemote(Map<String, Object?> values) {
  String? text(String key) {
    final value = values[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  double? number(String key, {required double min, required double max}) {
    final value = values[key];
    final parsed = switch (value) {
      num() => value.toDouble(),
      String() => double.tryParse(value),
      _ => null,
    };
    if (parsed == null || parsed.isNaN || parsed < min || parsed > max) {
      return null;
    }
    return parsed;
  }

  return ModelConfig.fromVariants(
    photoVariant: text(RemoteConfigKeys.photoModelVariant),
    liveVariant: text(RemoteConfigKeys.liveModelVariant),
    scoreThreshold: number(RemoteConfigKeys.scoreThreshold, min: 0.01, max: 0.9),
    liveTargetFps: number(RemoteConfigKeys.liveTargetFps, min: 1, max: 30),
  );
}

/// Remote Config の SDK 側。テストでは差し替える。
abstract class RemoteConfigBackend {
  /// Firebase が使えるか。無効なら何もしない。
  Future<bool> isAvailable();

  /// 前回までに取得した値を有効にして返す（初回は既定値）。
  Future<Map<String, Object?>> activate();

  /// 最新の値を取得して端末に控える。有効になるのは次の起動から。
  Future<void> fetchForNextLaunch();
}

class FirebaseRemoteConfigBackend implements RemoteConfigBackend {
  static const _defaults = <String, Object>{
    RemoteConfigKeys.photoModelVariant: '',
    RemoteConfigKeys.liveModelVariant: '',
    RemoteConfigKeys.scoreThreshold: 0.0,
    RemoteConfigKeys.liveTargetFps: 0.0,
  };

  bool _configured = false;

  FirebaseRemoteConfig get _config => FirebaseRemoteConfig.instance;

  @override
  Future<bool> isAvailable() => FirebaseBootstrap.ensureInitialized();

  Future<void> _configure() async {
    if (_configured) return;
    await _config.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 12),
      ),
    );
    await _config.setDefaults(_defaults);
    _configured = true;
  }

  @override
  Future<Map<String, Object?>> activate() async {
    await _configure();
    await _config.activate();
    return {
      RemoteConfigKeys.photoModelVariant: _config.getString(
        RemoteConfigKeys.photoModelVariant,
      ),
      RemoteConfigKeys.liveModelVariant: _config.getString(
        RemoteConfigKeys.liveModelVariant,
      ),
      RemoteConfigKeys.scoreThreshold: _config.getDouble(
        RemoteConfigKeys.scoreThreshold,
      ),
      RemoteConfigKeys.liveTargetFps: _config.getDouble(
        RemoteConfigKeys.liveTargetFps,
      ),
    };
  }

  @override
  Future<void> fetchForNextLaunch() async {
    await _configure();
    await _config.fetch();
  }
}

final remoteConfigBackendProvider = Provider<RemoteConfigBackend>(
  (ref) => FirebaseRemoteConfigBackend(),
);

/// 起動時に Remote Config を読み、[modelConfigProvider] に反映する。
///
/// 反映は起動時の 1 回だけ（前回取得した値）。推論サービスは設定が変わると作り直されるため、
/// 使用中に差し替えない。最新の値は裏で取得して次の起動から使う。
/// Firebase が無効・失敗のときは既定値のまま。
final remoteConfigStartupProvider = Provider<void>((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  unawaited(() async {
    try {
      final backend = ref.read(remoteConfigBackendProvider);
      if (!await backend.isAvailable()) return;
      final config = modelConfigFromRemote(await backend.activate());
      if (disposed) return;
      ref.read(modelConfigProvider.notifier).state = config;
      await backend.fetchForNextLaunch();
    } catch (error) {
      debugPrint('[RemoteConfig] startup failed: $error');
    }
  }());
});
