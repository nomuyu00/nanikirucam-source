import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';

// flutter test tool/test_ads_smoke_test.dart --dart-define=FIREBASE_ENABLED=true
//   --dart-define=ADMOB_USE_TEST_ADS=true
//   --dart-define=ADMOB_HOME_BANNER_ANDROID=ca-app-pub-9864062667468133/6879789955
void main() {
  test('無料のAnalyticsを有効にしても独自サーバーを利用しない', () async {
    expect(AppConfig.firebaseEnabled, isTrue);
    expect(AppConfig.firebaseBackendEnabled, isFalse);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(accountServiceProvider).available, isFalse);
    expect(container.read(backendClientProvider).available, isFalse);
    expect(container.read(problemRepositoryProvider).available, isFalse);
    expect(await container.read(authUidProvider.future), isNull);
  });

  test('テスト配信では登録済み広告枠よりテスト広告を優先する', () {
    expect(AppConfig.admobUseTestAds, isTrue);
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      for (final placement in AdPlacement.values) {
        expect(
          AppConfig.adUnitId(placement, platform: platform),
          startsWith('ca-app-pub-3940256099942544/'),
          reason: '$platform $placement',
        );
      }
    }
  });
}
