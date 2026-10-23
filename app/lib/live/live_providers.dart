import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/live/live_camera.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/live_detector.dart';
import 'package:nanikiru_cam/live/live_device.dart';
import 'package:nanikiru_cam/live/live_model_tier.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// ライブのカメラを作る（テストでは偽のカメラ）。画面ごとに 1 つ作って画面が破棄する。
final liveCameraFactoryProvider = Provider<LiveCamera Function()>(
  (ref) => CameraLiveCamera.new,
);

/// 自動切り替えで落ちた段の保存先（`live_model_tier_v1`）。
final liveModelTierStoreProvider = FutureProvider<LiveModelTierStore>((
  ref,
) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return LiveModelTierStore(prefs);
});

/// 保存した段が今のアプリのものかを見分けるためのバージョン（`1.0.0+1`）。取れなければ空。
final liveAppVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (error) {
    debugPrint('[Live] app version unavailable: $error');
    return '';
  }
});

/// ライブの検出器を作る（テストでは偽の検出器）。画面ごとに 1 つ作って画面が破棄する。
///
/// 始めのモデルは、前回までに自動で落ちた段（アプリの更新や Remote Config の明示で捨てる）。
final liveDetectorFactoryProvider = Provider<LiveDetector Function()>((ref) {
  final config = ref.watch(modelConfigProvider);
  return () => TfliteLiveDetector(
    config: config,
    storedTier: () async {
      final store = await ref.read(liveModelTierStoreProvider.future);
      final version = await ref.read(liveAppVersionProvider.future);
      return store.resolveStart(
        explicit: config.liveModelExplicit,
        appVersion: version,
      );
    },
  );
});

/// ライブのモデルの自動切り替え。Remote Config の `live_model_variant` が明示されていれば null
/// （そのモデルに固定する）。切り替えたら、落ちた段を端末に保存する。
final liveModelTieringProvider = Provider<LiveModelTiering?>((ref) {
  final config = ref.watch(modelConfigProvider);
  if (config.liveModelExplicit) return null;
  return LiveModelTiering(
    onSwitched: (asset) => unawaited(() async {
      try {
        final store = await ref.read(liveModelTierStoreProvider.future);
        final version = await ref.read(liveAppVersionProvider.future);
        await store.save(asset, appVersion: version);
      } catch (error) {
        debugPrint('[Live] saving the model tier failed: $error');
      }
    }()),
  );
});

/// フレームの時刻（単調）。テストでは偽の時計。
final liveClockFactoryProvider = Provider<LiveClock Function()>(
  (ref) => StopwatchLiveClock.new,
);

/// 画面の点灯・温度・電池。
final liveDeviceProvider = Provider<LiveDevice>((ref) => PlatformLiveDevice());

/// 無料体験の残り時間（`live_trial_v1`）。
final liveTrialProvider = FutureProvider<LiveTrial>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return LiveTrial(prefs, now: ref.watch(clockProvider));
});

/// 今日の体験の残り（Home の「体験残り時間」用）。Live 画面を閉じたら `ref.invalidate` する。
final liveTrialStateProvider = FutureProvider<LiveTrialState>((ref) async {
  final trial = await ref.watch(liveTrialProvider.future);
  final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
  return trial.load(pro: pro);
});

/// ライブの対局サマリーの保存先（`live_sessions_v1`）。
final liveSessionStoreProvider = FutureProvider<LiveSessionStore>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return LiveSessionStore(prefs);
});

/// 保存したセッション（新しい順）。Home の「直近のライブ対局サマリー」用。
final liveSessionsProvider = FutureProvider<List<LiveSession>>((ref) async {
  final store = await ref.watch(liveSessionStoreProvider.future);
  return store.load();
});

/// 置き方の案内（初回のみ）を見たか。
const String liveGuideSeenKey = 'live_guide_seen_v1';

/// 次に Live を始めるときに置き方の案内をもう一度出す（設定の「置き方の案内をもう一度見る」）。
Future<void> resetLiveGuide(WidgetRef ref) async {
  final prefs = await ref.read(sharedPreferencesProvider.future);
  await prefs.remove(liveGuideSeenKey);
}
