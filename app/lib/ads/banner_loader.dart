import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ads_initializer.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/di.dart';

/// 読み込み済みのバナー。広告 SDK の型を画面に出さないための包み。
class BannerHandle {
  const BannerHandle({
    required this.widget,
    required this.height,
    required this.dispose,
  });

  final Widget widget;
  final double height;
  final VoidCallback dispose;
}

/// [width]（論理ピクセル）のアンカー型アダプティブバナーを読み込む。失敗・同意なしは null。
typedef BannerLoader =
    Future<BannerHandle?> Function(AdPlacement placement, int width);

/// AdMob のバナーを読み込む。
Future<BannerHandle?> loadAdMobBanner(
  AdsInitializer ads,
  AdPlacement placement,
  int width, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!ads.canRequestAds || width <= 0) return null;
  AdSize size = AdSize.banner;
  try {
    size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width) ?? size;
  } catch (_) {
    // 取れなければ標準サイズ。
  }
  final completer = Completer<BannerHandle?>();
  final banner = ads.createBanner(
    placement: placement,
    size: size,
    listener: BannerAdListener(
      onAdLoaded: (ad) {
        if (completer.isCompleted) {
          unawaited(ad.dispose());
          return;
        }
        completer.complete(
          BannerHandle(
            widget: AdWidget(ad: ad as BannerAd),
            height: size.height.toDouble(),
            dispose: () => unawaited(ad.dispose()),
          ),
        );
      },
      onAdFailedToLoad: (ad, error) {
        unawaited(ad.dispose());
        if (!completer.isCompleted) completer.complete(null);
      },
    ),
  );
  if (banner == null) return null;
  return completer.future.timeout(
    timeout,
    onTimeout: () {
      unawaited(banner.dispose());
      return null;
    },
  );
}

/// バナーの読み込み。広告 SDK の初期化は [adsInitializerProvider] が（有効なときだけ）行う。
final bannerLoaderProvider = Provider<BannerLoader>((ref) {
  final ads = ref.watch(adsInitializerProvider);
  return (placement, width) => loadAdMobBanner(ads, placement, width);
});
