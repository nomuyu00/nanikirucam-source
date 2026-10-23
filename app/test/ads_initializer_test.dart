// 流用元: reference/agari_cam/test/ads_initializer_test.dart（2026-10-21 時点）
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:nanikiru_cam/ads/ads_initializer.dart';

void main() {
  late _InterstitialLoader loader;
  late AdsInitializer ads;
  late DateTime now;
  late bool consentAllowed;

  setUp(() {
    loader = _InterstitialLoader();
    now = DateTime.utc(2026, 9, 11);
    consentAllowed = true;
    ads = AdsInitializer(
      interstitialLoader: loader.load,
      now: () => now,
      canRequestAds: () => consentAllowed,
    );
  });

  tearDown(() => ads.dispose());

  test(
    'consent gates SDK initialization, banners and interstitial requests',
    () async {
      consentAllowed = false;
      await ads.initialize();
      expect(ads.createBanner(), isNull);
      await ads.loadInterstitial();
      expect(loader.callbacks, isEmpty);

      consentAllowed = true;
      await ads.loadInterstitial();
      expect(loader.callbacks, hasLength(1));
    },
  );

  test('a loaded ad cannot be shown after consent is withdrawn', () async {
    await ads.loadInterstitial();
    final ad = _InterstitialAd();
    loader.callbacks.single.onAdLoaded(ad);

    consentAllowed = false;
    await ads.maybeShowInterstitial();
    expect(ad.showCalls, 0);
    expect(ad.disposeCalls, 1);
  });

  test('an ad arriving after consent changes is discarded', () async {
    await ads.loadInterstitial();
    consentAllowed = false;
    final ad = _InterstitialAd();
    loader.callbacks.single.onAdLoaded(ad);
    await ads.maybeShowInterstitial();

    expect(ad.showCalls, 0);
    expect(ad.disposeCalls, 1);
  });

  test('repeated rebuild requests reuse the pending and loaded ad', () async {
    await Future.wait(List.generate(5, (_) => ads.loadInterstitial()));
    expect(loader.callbacks, hasLength(1));

    final ad = _InterstitialAd();
    loader.callbacks.single.onAdLoaded(ad);
    await ads.loadInterstitial();
    expect(loader.callbacks, hasLength(1));

    ads.dispose();
    ads.dispose();
    expect(ad.disposeCalls, 1);
  });

  test(
    'an ad arriving after disposal is released and cannot be shown',
    () async {
      await ads.loadInterstitial();
      ads.dispose();

      final ad = _InterstitialAd();
      loader.callbacks.single.onAdLoaded(ad);
      await ads.maybeShowInterstitial();
      await ads.loadInterstitial();

      expect(ad.disposeCalls, 1);
      expect(ad.showCalls, 0);
      expect(loader.callbacks, hasLength(1));
    },
  );

  test('load failures allow the next request to retry', () async {
    await ads.loadInterstitial();
    loader.callbacks.single.onAdFailedToLoad(
      LoadAdError(1, 'test', 'No ad available', null),
    );
    await ads.loadInterstitial();
    expect(loader.callbacks, hasLength(2));
  });

  test('platform load exceptions are contained and allow retry', () async {
    loader.failNextLoad = true;
    await ads.loadInterstitial();
    await ads.loadInterstitial();
    expect(loader.callbacks, hasLength(2));
  });

  test(
    'navigation waits for dismissal and concurrent calls show one ad',
    () async {
      final ad = _InterstitialAd();
      await ads.loadInterstitial();
      loader.callbacks.single.onAdLoaded(ad);

      var firstCompleted = false;
      var secondCompleted = false;
      final first = ads.maybeShowInterstitial().then(
        (_) => firstCompleted = true,
      );
      final second = ads.maybeShowInterstitial().then(
        (_) => secondCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      await ads.loadInterstitial();

      expect(ad.showCalls, 1);
      expect(firstCompleted, isFalse);
      expect(secondCompleted, isFalse);
      expect(loader.callbacks, hasLength(1));

      ad.fullScreenContentCallback!.onAdDismissedFullScreenContent!(ad);
      await Future.wait([first, second]);
      expect(ad.disposeCalls, 1);
      expect(firstCompleted, isTrue);
      expect(secondCompleted, isTrue);

      now = now.add(const Duration(seconds: 119));
      await ads.loadInterstitial();
      expect(loader.callbacks, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      await ads.loadInterstitial();
      expect(loader.callbacks, hasLength(2));
    },
  );

  test(
    'presentation failure releases the ad and unblocks navigation',
    () async {
      final ad = _InterstitialAd();
      await ads.loadInterstitial();
      loader.callbacks.single.onAdLoaded(ad);

      final showing = ads.maybeShowInterstitial();
      ad.fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
        ad,
        AdError(1, 'test', 'Presentation failed'),
      );
      await showing;
      await ads.loadInterstitial();

      expect(ad.disposeCalls, 1);
      expect(loader.callbacks, hasLength(2));
    },
  );

  test(
    'platform presentation exceptions release the ad and allow retry',
    () async {
      final ad = _InterstitialAd()..failShow = true;
      await ads.loadInterstitial();
      loader.callbacks.single.onAdLoaded(ad);

      await ads.maybeShowInterstitial();
      await ads.loadInterstitial();

      expect(ad.disposeCalls, 1);
      expect(loader.callbacks, hasLength(2));
    },
  );

  test(
    'disposing during presentation completes waiting callers once',
    () async {
      final ad = _InterstitialAd();
      await ads.loadInterstitial();
      loader.callbacks.single.onAdLoaded(ad);

      final showing = ads.maybeShowInterstitial();
      ads.dispose();
      await showing;
      ad.fullScreenContentCallback!.onAdDismissedFullScreenContent!(ad);
      expect(ad.disposeCalls, 1);
    },
  );
}

class _InterstitialLoader {
  final callbacks = <InterstitialAdLoadCallback>[];
  bool failNextLoad = false;

  Future<void> load({
    required String adUnitId,
    required AdRequest request,
    required InterstitialAdLoadCallback adLoadCallback,
  }) async {
    callbacks.add(adLoadCallback);
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('Platform load failed');
    }
  }
}

class _InterstitialAd extends Fake implements InterstitialAd {
  @override
  FullScreenContentCallback<InterstitialAd>? fullScreenContentCallback;

  int showCalls = 0;
  int disposeCalls = 0;
  bool failShow = false;

  @override
  Future<void> show() async {
    showCalls++;
    if (failShow) throw StateError('Platform presentation failed');
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}
