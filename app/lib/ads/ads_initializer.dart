// 流用元: reference/agari_cam/lib/ads/ads_initializer.dart（2026-10-21 時点）
// 改修: 広告ユニット ID は AppConfig（--dart-define、既定は Google のテスト ID）から引く。
// バナーは配置（AdPlacement）ごとに作る。ライブ画面では広告を読み込まない（設計書 10 章）。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:nanikiru_cam/consent/consent_manager.dart';
import 'package:nanikiru_cam/core/app_config.dart';

typedef InterstitialLoader =
    Future<void> Function({
      required String adUnitId,
      required AdRequest request,
      required InterstitialAdLoadCallback adLoadCallback,
    });

class AdsInitializer {
  AdsInitializer({
    InterstitialLoader? interstitialLoader,
    DateTime Function()? now,
    bool Function()? canRequestAds,
  }) : _interstitialLoader = interstitialLoader ?? InterstitialAd.load,
       _now = now ?? DateTime.now,
       _canRequestAds =
           canRequestAds ?? (() => ConsentManager.instance.canRequestAds);

  InterstitialAd? _interstitial;
  final InterstitialLoader _interstitialLoader;
  final DateTime Function() _now;
  final bool Function() _canRequestAds;
  bool _loadingInterstitial = false;
  bool _disposed = false;
  Completer<void>? _showCompletion;
  DateTime _lastInterstitial = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> initialize() async {
    if (_disposed || !_canRequestAds()) return;
    try {
      await MobileAds.instance.initialize();
    } catch (error) {
      debugPrint('[AdsInitializer] Initialization failed: $error');
    }
  }

  /// 同意が得られていて、広告を要求してよいか。
  bool get canRequestAds => !_disposed && _canRequestAds();

  /// ATT/UMP の結果に合わせた広告リクエスト（パーソナライズなしの切り替え込み）。
  AdRequest adRequest() {
    final nonPersonalized = !ConsentManager.instance.canRequestPersonalizedAds;
    return AdRequest(nonPersonalizedAds: nonPersonalized);
  }

  /// [placement]（`homeBanner` / `resultBanner` / `historyBanner`）のバナーを作って読み込む。
  /// [size] はアダプティブバナーのサイズを渡す（省略時は標準の 320x50）。
  BannerAd? createBanner({
    AdPlacement placement = AdPlacement.homeBanner,
    AdSize size = AdSize.banner,
    BannerAdListener listener = const BannerAdListener(),
  }) {
    if (_disposed || !_canRequestAds()) return null;
    final unitId = AppConfig.adUnitId(placement);
    return BannerAd(
      size: size,
      adUnitId: unitId,
      listener: listener,
      request: adRequest(),
    )..load();
  }

  Future<void> loadInterstitial() async {
    // A result page can rebuild while a native ad request is still pending.
    if (_disposed ||
        !_canRequestAds() ||
        _loadingInterstitial ||
        _interstitial != null ||
        _showCompletion != null) {
      return;
    }
    // Frequency cap: 1 per 2 minutes
    if (_now().difference(_lastInterstitial) < const Duration(minutes: 2)) {
      return;
    }
    _loadingInterstitial = true;
    try {
      await _interstitialLoader(
        adUnitId: AppConfig.adUnitId(AdPlacement.nextHandInterstitial),
        request: adRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (ad) {
            _loadingInterstitial = false;
            if (_disposed || !_canRequestAds()) {
              unawaited(_disposeAd(ad));
              return;
            }
            _interstitial = ad;
          },
          onAdFailedToLoad: (error) {
            _loadingInterstitial = false;
            debugPrint('[AdsInitializer] Interstitial load failed: $error');
          },
        ),
      );
    } catch (error) {
      _loadingInterstitial = false;
      debugPrint('[AdsInitializer] Interstitial load failed: $error');
    }
  }

  /// 広告を表示して閉じられたら true。
  Future<bool> maybeShowInterstitial() async {
    if (_disposed) return false;
    final showing = _showCompletion;
    if (showing != null) {
      await showing.future;
      return false;
    }
    final ad = _interstitial;
    if (ad == null) return false;
    if (!_canRequestAds() ||
        _now().difference(_lastInterstitial) < const Duration(minutes: 2)) {
      _interstitial = null;
      await _disposeAd(ad);
      return false;
    }

    var shown = false;
    final completion = Completer<void>();
    _showCompletion = completion;
    void finish({bool dismissed = false}) {
      if (completion.isCompleted) return;
      shown = dismissed;
      if (dismissed) _lastInterstitial = _now();
      _interstitial = null;
      _showCompletion = null;
      unawaited(_disposeAd(ad));
      completion.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) => finish(dismissed: true),
      onAdFailedToShowFullScreenContent: (_, error) => finish(),
    );
    try {
      await ad.show();
      // The platform method completes when presentation starts, not on dismissal.
      await completion.future;
    } catch (error) {
      debugPrint('[AdsInitializer] Interstitial presentation failed: $error');
      finish();
    }
    return shown;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final ad = _interstitial;
    _interstitial = null;
    if (ad != null) unawaited(_disposeAd(ad));
    _showCompletion?.complete();
    _showCompletion = null;
  }

  Future<void> _disposeAd(InterstitialAd ad) async {
    try {
      await ad.dispose();
    } catch (error) {
      debugPrint('[AdsInitializer] Interstitial disposal failed: $error');
    }
  }
}
