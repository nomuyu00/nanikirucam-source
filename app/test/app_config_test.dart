import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:nanikiru_cam/share/share_links.dart';

void main() {
  group('AppConfig の既定値（--dart-define なし）', () {
    test('Firebase は無効、RevenueCat は未設定', () {
      expect(AppConfig.firebaseEnabled, isFalse);
      expect(AppConfig.revenueCatApiKeyIos, isEmpty);
      expect(AppConfig.revenueCatApiKeyAndroid, isEmpty);
      expect(AppConfig.revenueCatConfigured, isFalse);
    });

    test('Web のベース URL と問題・紹介リンク', () {
      expect(AppConfig.webBaseUrl, 'https://nanikiru-cam.web.app');
      expect(
        AppConfig.problemUrl('aB3dE5gH'),
        'https://nanikiru-cam.web.app/p/aB3dE5gH',
      );
      expect(
        AppConfig.problemUrl('aB3dE5gH', referralCode: 'ABC 123'),
        'https://nanikiru-cam.web.app/p/aB3dE5gH?ref=ABC+123',
      );
      expect(
        AppConfig.problemUrl('x', referralCode: ''),
        'https://nanikiru-cam.web.app/p/x',
      );
      expect(
        AppConfig.referralUrl('ABC'),
        'https://nanikiru-cam.web.app/r/ABC',
      );
    });

    test('AdMob の ID は Google の公開テスト ID', () {
      expect(
        AppConfig.admobAppIdAndroid,
        'ca-app-pub-3940256099942544~3347511713',
      );
      expect(AppConfig.admobAppIdIos, 'ca-app-pub-3940256099942544~1458002511');
      for (final placement in AdPlacement.values) {
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          expect(
            AppConfig.adUnitId(placement, platform: platform),
            startsWith('ca-app-pub-3940256099942544/'),
            reason: '$placement $platform',
          );
        }
      }
      expect(
        AppConfig.adUnitId(
          AdPlacement.homeBanner,
          platform: TargetPlatform.android,
        ),
        'ca-app-pub-3940256099942544/6300978111',
      );
      expect(
        AppConfig.adUnitId(
          AdPlacement.nextHandInterstitial,
          platform: TargetPlatform.iOS,
        ),
        'ca-app-pub-3940256099942544/4411468910',
      );
      expect(
        AppConfig.adUnitId(
          AdPlacement.quotaReward,
          platform: TargetPlatform.android,
        ),
        'ca-app-pub-3940256099942544/5224354917',
      );
    });
  });

  group('ライブ延長の動画広告のユニット ID', () {
    test('専用ユニットが未定義（空）なら quota_reward のユニットを使う', () {
      expect(
        AppConfig.liveTrialRewardUnitId(own: '', quota: 'ca-app-pub-1/quota'),
        'ca-app-pub-1/quota',
      );
    });

    test('専用ユニットがあればそれを使う（収益を分けて見られる）', () {
      expect(
        AppConfig.liveTrialRewardUnitId(
          own: 'ca-app-pub-1/live',
          quota: 'ca-app-pub-1/quota',
        ),
        'ca-app-pub-1/live',
      );
    });

    test('--dart-define なしでは quota_reward と同じ（テスト広告の ID）', () {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        expect(
          AppConfig.adUnitId(AdPlacement.liveTrialReward, platform: platform),
          AppConfig.adUnitId(AdPlacement.quotaReward, platform: platform),
        );
      }
      expect(
        AppConfig.adUnitId(
          AdPlacement.liveTrialReward,
          platform: TargetPlatform.android,
        ),
        'ca-app-pub-3940256099942544/5224354917',
      );
      expect(
        AppConfig.adUnitId(
          AdPlacement.liveTrialReward,
          platform: TargetPlatform.iOS,
        ),
        'ca-app-pub-3940256099942544/1712485313',
      );
    });
  });

  test('Firebase が無効なら Analytics も使わない', () {
    expect(FirebaseAnalyticsBackend().supported, isFalse);
  });

  test('Firebase が無効なら初期化せず、失敗を外に出さない', () async {
    FirebaseBootstrap.resetForTest();
    expect(await FirebaseBootstrap.ensureInitialized(), isFalse);
    expect(FirebaseBootstrap.isReady, isFalse);
    // 何度呼んでも同じ。
    expect(await FirebaseBootstrap.ensureInitialized(), isFalse);
  });

  group('ShareLinks', () {
    test('Android は Install Referrer に campaign・pid・ref を入れる', () {
      final url = ShareLinks.storeUrl(
        campaign: 'problem',
        problemId: 'aB3dE5gH',
        referralCode: 'CODE1',
        platform: TargetPlatform.android,
      );
      expect(
        url,
        '${ShareLinks.playStoreUrl}&referrer='
        '${Uri.encodeComponent('utm_source=share&utm_campaign=problem&pid=aB3dE5gH&ref=CODE1')}',
      );
      expect(
        url,
        contains('referrer=utm_source%3Dshare%26utm_campaign%3Dproblem'),
      );
      expect(url, contains('%26pid%3DaB3dE5gH%26ref%3DCODE1'));
    });

    test('pid・ref は省略できる', () {
      final url = ShareLinks.storeUrl(
        campaign: 'result',
        platform: TargetPlatform.android,
      );
      expect(
        url,
        endsWith(Uri.encodeComponent('utm_source=share&utm_campaign=result')),
      );
    });

    test('iOS は App Store の URL に誘導する（Web の問題ページは使わない）', () {
      expect(ShareLinks.iosAppStoreId, '6825623654');
      expect(
        ShareLinks.storeUrl(
          campaign: 'problem',
          problemId: 'abc',
          referralCode: 'R',
          platform: TargetPlatform.iOS,
        ),
        'https://apps.apple.com/jp/app/id6825623654',
      );
      expect(
        ShareLinks.storeUrl(campaign: 'result', platform: TargetPlatform.iOS),
        ShareLinks.appStoreUrl,
      );
    });

    test('問題カードの URL', () {
      expect(
        ShareLinks.problemUrl('abc', referralCode: 'R'),
        'https://nanikiru-cam.web.app/p/abc?ref=R',
      );
    });
  });

  group('ModelConfig', () {
    test('既定は写真が fp32 → int8、ライブは YOLO11s の int8', () {
      const config = ModelConfig.defaults;
      expect(config.photoModels, [
        'assets/models/mahjong_yolo_fp32.tflite',
        'assets/models/mahjong_yolo_int8.tflite',
      ]);
      expect(config.liveModel, 'assets/models/mahjong_yolo_live_s_int8.tflite');
      expect(config.labelsAsset, 'assets/labels/tiles_labels.txt');
      expect(config.scoreThreshold, 0.10);
      expect(config.liveTargetFps, 5);
    });

    test('Remote Config のバリアント名から組み立てる', () {
      final config = ModelConfig.fromVariants(
        photoVariant: 'int8',
        liveVariant: 'live_n_int8',
        scoreThreshold: 0.2,
        liveTargetFps: 6,
      );
      expect(config.photoModels, [
        'assets/models/mahjong_yolo_int8.tflite',
        'assets/models/mahjong_yolo_fp32.tflite',
      ]);
      expect(config.liveModel, 'assets/models/mahjong_yolo_live_n_int8.tflite');
      expect(config.liveModelExplicit, isTrue);
      expect(config.scoreThreshold, 0.2);
      expect(config.liveTargetFps, 6);
    });

    test('未知のバリアントや不正な値は既定値のまま', () {
      final config = ModelConfig.fromVariants(
        photoVariant: 'huge',
        liveVariant: null,
        scoreThreshold: -1,
        liveTargetFps: 0,
      );
      expect(config, ModelConfig.defaults);
    });
  });
}
