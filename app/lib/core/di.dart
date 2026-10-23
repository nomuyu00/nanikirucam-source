// 流用元: reference/agari_cam/lib/core/di.dart（2026-10-21 時点）
// 改修: 共通のものだけにした。機能ごとの provider は各機能のファイル
// （例: lib/ui/recognition/recognition_providers.dart）に置く。
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ads_initializer.dart';
import 'package:nanikiru_cam/consent/consent_manager.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = FutureProvider<SharedPreferences>((
  ref,
) async {
  return SharedPreferences.getInstance();
});

/// 写真用の推論サービス。モデルは認識を要求されたときに読み込む（カメラ起動後）。
/// [modelConfigProvider] が変わると作り直す。
final tfliteServiceProvider = ChangeNotifierProvider<TfliteService>((ref) {
  return TfliteService(config: ref.watch(modelConfigProvider));
});

// The singleton is owned by the app; provider containers only subscribe to it.
final consentManagerProvider = Provider<ConsentManager>(
  (ref) => ConsentManager.instance,
);

final consentStateProvider = Provider<ConsentState>((ref) {
  final manager = ref.watch(consentManagerProvider);
  void onChanged() => ref.invalidateSelf();
  manager.addListener(onChanged);
  ref.onDispose(() => manager.removeListener(onChanged));
  return manager.state;
});

/// 広告は UMP の同意があり、Pro でないときだけ出す。
final adsEnabledProvider = Provider<bool>((ref) {
  final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
  final consent = ref.watch(consentStateProvider);
  final reviewLoading = ref.watch(reviewAccessProvider).loading;
  return !pro && !reviewLoading && consent.canRequestAds;
});

final adsInitializerProvider = Provider<AdsInitializer>((ref) {
  final enabled = ref.watch(adsEnabledProvider);
  final consent = ref.watch(consentManagerProvider);
  ref.watch(
    consentStateProvider.select((state) => state.canRequestPersonalizedAds),
  );
  final ads = AdsInitializer(
    canRequestAds: () => ref.read(adsEnabledProvider) && consent.canRequestAds,
  );
  if (enabled) ads.initialize();
  ref.onDispose(ads.dispose);
  return ads;
});
