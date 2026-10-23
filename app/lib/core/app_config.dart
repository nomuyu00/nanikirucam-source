import 'package:flutter/foundation.dart';

/// 広告の配置（設計書 10 章）。
enum AdPlacement {
  homeBanner,
  resultBanner,
  historyBanner,
  nextHandInterstitial,
  quotaReward,
  explanationReward,

  /// ライブ体験時間の延長（動画を見て +1〜3 分）。本番で専用ユニットが未定義なら
  /// [quotaReward] のユニットを使う（[AppConfig.adUnitId]）。
  liveTrialReward,
}

/// `--dart-define` で受けるビルド時設定。
///
/// 例:
/// ```
/// flutter run \
///   --dart-define=FIREBASE_ENABLED=true \
///   --dart-define=REVENUECAT_API_KEY_IOS=appl_xxx \
///   --dart-define=ADMOB_HOME_BANNER_ANDROID=ca-app-pub-xxx/yyy
/// ```
///
/// AdMob のユニット ID は Google の公開テスト ID が既定値なので、定義なしのビルドでは
/// 必ずテスト広告になる（本番 ID は CI の `--dart-define` で渡す）。
/// AdMob の **App ID** は Dart ではなくネイティブ側が読む:
/// - Android: `android/app/build.gradle.kts` が `--dart-define=ADMOB_APP_ID_ANDROID=...` を
///   読んで manifest に埋める（既定はテスト ID）。
/// - iOS: `ios/Flutter/*.xcconfig` の `ADMOB_APP_ID`（`ios/Flutter/Secrets.xcconfig` で上書き）。
/// ここの [admobAppIdAndroid] / [admobAppIdIos] は参照・診断用で、ネイティブ側と同じ既定値。
abstract final class AppConfig {
  /// TestFlight・Play のテスト配信では、登録済みの広告枠があってもテスト広告を使う。
  static const bool admobUseTestAds = bool.fromEnvironment('ADMOB_USE_TEST_ADS');

  // --- Firebase ---------------------------------------------------------
  /// false なら Firebase を初期化せず、Analytics・Auth・Firestore などは使わない。
  /// `firebase_options.dart` / `google-services.json` / `GoogleService-Info.plist` を
  /// 入れてから `--dart-define=FIREBASE_ENABLED=true` で有効にする。
  static const bool firebaseEnabled = bool.fromEnvironment('FIREBASE_ENABLED');

  /// Analytics と独立した、Functions・Firestore・Storage の利用許可。
  /// 固定費・サーバー代0円の配信では false。RevenueCat の購入判定は利用できる。
  static const bool firebaseBackendEnabled =
      firebaseEnabled && bool.fromEnvironment('FIREBASE_BACKEND_ENABLED');

  // --- RevenueCat（空なら未設定。課金 UI は「準備中」にする） ---------------
  static const String revenueCatApiKeyIos = String.fromEnvironment(
    'REVENUECAT_API_KEY_IOS',
  );
  static const String revenueCatApiKeyAndroid = String.fromEnvironment(
    'REVENUECAT_API_KEY_ANDROID',
  );

  /// 現在のプラットフォームの RevenueCat API キー。未設定・非対応 OS は空文字。
  static String get revenueCatApiKey => switch (defaultTargetPlatform) {
    TargetPlatform.iOS => revenueCatApiKeyIos,
    TargetPlatform.android => revenueCatApiKeyAndroid,
    _ => '',
  };

  static bool get revenueCatConfigured => revenueCatApiKey.isNotEmpty;

  /// Android 審査用。両方未設定なら入口も権利も作らない。平文コードは渡さない。
  static const String reviewAccessCodeSha256 = String.fromEnvironment(
    'REVIEW_ACCESS_CODE_SHA256',
  );
  static const String reviewAccessExpiresAt = String.fromEnvironment(
    'REVIEW_ACCESS_EXPIRES_AT',
  );

  // --- Web（問題ページ・共有リンク） ----------------------------------------
  /// 末尾のスラッシュなし。独自ドメインを取ったら差し替える。
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'https://nanikiru-cam.web.app',
  );

  /// 問題ページの URL（`/p/{problemId}?ref={code}`）。
  static String problemUrl(String problemId, {String? referralCode}) {
    final base = '$webBaseUrl/p/$problemId';
    if (referralCode == null || referralCode.isEmpty) return base;
    return '$base?ref=${Uri.encodeQueryComponent(referralCode)}';
  }

  /// 紹介リンク（`/r/{code}`）。
  static String referralUrl(String code) =>
      '$webBaseUrl/r/${Uri.encodeComponent(code)}';

  // --- AdMob App ID（ネイティブ側と同じ既定値。上の説明を参照） --------------
  static const String admobAppIdAndroid = String.fromEnvironment(
    'ADMOB_APP_ID_ANDROID',
    defaultValue: 'ca-app-pub-3940256099942544~3347511713',
  );
  static const String admobAppIdIos = String.fromEnvironment(
    'ADMOB_APP_ID_IOS',
    defaultValue: 'ca-app-pub-3940256099942544~1458002511',
  );

  // --- AdMob ユニット ID（既定は Google の公開テスト ID） --------------------
  static const String _testBannerAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const String _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
  static const String _testInterstitialIos =
      'ca-app-pub-3940256099942544/4411468910';
  static const String _testRewardedAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _testRewardedIos =
      'ca-app-pub-3940256099942544/1712485313';

  static const String _homeBannerAndroid = String.fromEnvironment(
    'ADMOB_HOME_BANNER_ANDROID',
    defaultValue: _testBannerAndroid,
  );
  static const String _homeBannerIos = String.fromEnvironment(
    'ADMOB_HOME_BANNER_IOS',
    defaultValue: _testBannerIos,
  );
  static const String _resultBannerAndroid = String.fromEnvironment(
    'ADMOB_RESULT_BANNER_ANDROID',
    defaultValue: _testBannerAndroid,
  );
  static const String _resultBannerIos = String.fromEnvironment(
    'ADMOB_RESULT_BANNER_IOS',
    defaultValue: _testBannerIos,
  );
  static const String _historyBannerAndroid = String.fromEnvironment(
    'ADMOB_HISTORY_BANNER_ANDROID',
    defaultValue: _testBannerAndroid,
  );
  static const String _historyBannerIos = String.fromEnvironment(
    'ADMOB_HISTORY_BANNER_IOS',
    defaultValue: _testBannerIos,
  );
  static const String _nextHandInterstitialAndroid = String.fromEnvironment(
    'ADMOB_NEXT_HAND_INTERSTITIAL_ANDROID',
    defaultValue: _testInterstitialAndroid,
  );
  static const String _nextHandInterstitialIos = String.fromEnvironment(
    'ADMOB_NEXT_HAND_INTERSTITIAL_IOS',
    defaultValue: _testInterstitialIos,
  );
  static const String _quotaRewardAndroid = String.fromEnvironment(
    'ADMOB_QUOTA_REWARD_ANDROID',
    defaultValue: _testRewardedAndroid,
  );
  static const String _quotaRewardIos = String.fromEnvironment(
    'ADMOB_QUOTA_REWARD_IOS',
    defaultValue: _testRewardedIos,
  );
  static const String _explanationRewardAndroid = String.fromEnvironment(
    'ADMOB_EXPLANATION_REWARD_ANDROID',
    defaultValue: _testRewardedAndroid,
  );
  static const String _explanationRewardIos = String.fromEnvironment(
    'ADMOB_EXPLANATION_REWARD_IOS',
    defaultValue: _testRewardedIos,
  );

  // ライブ延長の動画。専用ユニットは任意（既定は空）。空なら quota_reward のユニットで出す。
  // AdMob で専用ユニットを作って `ADMOB_LIVE_TRIAL_REWARD_*` を渡すと、ライブ延長の収益を
  // 写真解析の動画と分けて見られる。
  static const String _liveTrialRewardAndroid = String.fromEnvironment(
    'ADMOB_LIVE_TRIAL_REWARD_ANDROID',
  );
  static const String _liveTrialRewardIos = String.fromEnvironment(
    'ADMOB_LIVE_TRIAL_REWARD_IOS',
  );

  /// ライブ延長の動画のユニット ID。[own] が空なら [quota]（quota_reward のユニット）。
  @visibleForTesting
  static String liveTrialRewardUnitId({
    required String own,
    required String quota,
  }) => own.isEmpty ? quota : own;

  /// [placement] の広告ユニット ID。Android・iOS 以外はテスト ID（Android 側）を返す。
  static String adUnitId(AdPlacement placement, {TargetPlatform? platform}) {
    final ios = (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
    if (admobUseTestAds) {
      return switch (placement) {
        AdPlacement.homeBanner ||
        AdPlacement.resultBanner ||
        AdPlacement.historyBanner => ios ? _testBannerIos : _testBannerAndroid,
        AdPlacement.nextHandInterstitial =>
          ios ? _testInterstitialIos : _testInterstitialAndroid,
        AdPlacement.quotaReward ||
        AdPlacement.explanationReward ||
        AdPlacement.liveTrialReward =>
          ios ? _testRewardedIos : _testRewardedAndroid,
      };
    }
    return switch (placement) {
      AdPlacement.homeBanner => ios ? _homeBannerIos : _homeBannerAndroid,
      AdPlacement.resultBanner => ios ? _resultBannerIos : _resultBannerAndroid,
      AdPlacement.historyBanner =>
        ios ? _historyBannerIos : _historyBannerAndroid,
      AdPlacement.nextHandInterstitial =>
        ios ? _nextHandInterstitialIos : _nextHandInterstitialAndroid,
      AdPlacement.quotaReward => ios ? _quotaRewardIos : _quotaRewardAndroid,
      AdPlacement.explanationReward =>
        ios ? _explanationRewardIos : _explanationRewardAndroid,
      AdPlacement.liveTrialReward => liveTrialRewardUnitId(
        own: ios ? _liveTrialRewardIos : _liveTrialRewardAndroid,
        quota: ios ? _quotaRewardIos : _quotaRewardAndroid,
      ),
    };
  }
}
