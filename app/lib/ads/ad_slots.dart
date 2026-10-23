import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ads_initializer.dart';
import 'package:nanikiru_cam/ads/banner_loader.dart';
import 'package:nanikiru_cam/ads/interstitial_controller.dart';
import 'package:nanikiru_cam/ads/interstitial_pacing.dart';
import 'package:nanikiru_cam/ads/rewarded_ads.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';

// 画面が [RewardedGate.showTimed] の結果を型名で扱えるように。
export 'package:nanikiru_cam/ads/rewarded_ads.dart' show RewardedShowResult;

/// 画面から広告を使うための窓口（設計書 10 章）。
///
/// 契約: 画面は次の 3 つだけを使う。中身（AdMob の読み込み・表示、同意、Pro なら出さない、
/// 間隔制御）はこのディレクトリの実装が行う。名前とシグネチャは変えない。
/// Live 画面ではどれも使わない（ライブ体験時間の延長用の動画も、ライブ画面の外で見せる）。

/// アンカー型のアダプティブバナー。Pro・同意なし・読み込み失敗なら何も描かない
/// （高さも 0）。画面の最下部に置く。
class AdBannerSlot extends ConsumerStatefulWidget {
  const AdBannerSlot({super.key, required this.placement});

  /// [AdPlacement.homeBanner] / [AdPlacement.resultBanner] / [AdPlacement.historyBanner]。
  final AdPlacement placement;

  @override
  ConsumerState<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends ConsumerState<AdBannerSlot> {
  BannerHandle? _banner;
  bool _loading = false;

  // 同じ条件で失敗したら、条件（幅・配置）が変わるまで再試行しない。
  int? _attemptedWidth;
  AdPlacement? _attemptedPlacement;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _banner?.dispose();
    _banner = null;
    super.dispose();
  }

  void _release() {
    _generation++;
    _banner?.dispose();
    _banner = null;
    _loading = false;
    _attemptedWidth = null;
    _attemptedPlacement = null;
  }

  void _load(int width) {
    _attemptedWidth = width;
    _attemptedPlacement = widget.placement;
    _loading = true;
    final generation = ++_generation;
    final loader = ref.read(bannerLoaderProvider);
    unawaited(() async {
      BannerHandle? handle;
      try {
        handle = await loader(widget.placement, width);
      } catch (_) {
        handle = null;
      }
      if (!mounted || generation != _generation) {
        handle?.dispose();
        return;
      }
      setState(() {
        _loading = false;
        _banner?.dispose();
        _banner = handle;
      });
    }());
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(adsEnabledProvider);
    if (!enabled) {
      if (_banner != null || _loading) _release();
      return const SizedBox.shrink();
    }
    // 有効なときだけ SDK を初期化する（adsInitializerProvider が行う）。
    ref.watch(adsInitializerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth.floor()
            : MediaQuery.sizeOf(context).width.floor();
        final changed =
            _attemptedWidth != width ||
            _attemptedPlacement != widget.placement;
        if (changed && !_loading && width > 0) {
          // 幅や配置が変わったら読み込み直す（向きの変更など）。
          if (_banner != null) {
            _generation++;
            _banner?.dispose();
            _banner = null;
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_loading) _load(width);
          });
        }
        final banner = _banner;
        if (banner == null) return const SizedBox.shrink();
        return SafeArea(
          top: false,
          child: SizedBox(
            width: width.toDouble(),
            height: banner.height,
            child: banner.widget,
          ),
        );
      },
    );
  }
}

/// 全画面広告（`next_hand_interstitial`）。
abstract class InterstitialController {
  /// Result を表示したことを数える（間隔制御の入力）。
  void onResultViewed();

  /// 共有を終えた直後（直後は出さない）。
  void onShared();

  /// 「次の手を撮る」の直前に呼ぶ。間隔制御に合えば表示し、閉じられるまで待つ。
  Future<void> maybeShowBeforeNextHand();
}

class _InterstitialAdapter implements InterstitialController {
  _InterstitialAdapter(this._inner);

  final PacedInterstitialController _inner;

  @override
  void onResultViewed() => unawaited(_inner.onResultViewed());

  @override
  void onShared() => _inner.onShared();

  @override
  Future<void> maybeShowBeforeNextHand() => _inner.maybeShowBeforeNextHand();
}

class _AdsInitializerInterstitialPort implements InterstitialPort {
  _AdsInitializerInterstitialPort(this._ads, this._enabled);

  final AdsInitializer _ads;
  final bool Function() _enabled;

  @override
  bool get enabled => _enabled() && _ads.canRequestAds;

  @override
  Future<void> load() => _ads.loadInterstitial();

  @override
  Future<bool> show() => _ads.maybeShowInterstitial();
}

final interstitialControllerProvider = Provider<InterstitialController>((ref) {
  final ads = ref.watch(adsInitializerProvider);
  return _InterstitialAdapter(
    PacedInterstitialController(
      pacing: () async => InterstitialPacing(
        await ref.read(sharedPreferencesProvider.future),
        now: ref.read(clockProvider),
      ),
      port: _AdsInitializerInterstitialPort(
        ads,
        () => ref.read(adsEnabledProvider),
      ),
      now: ref.read(clockProvider),
    ),
  );
});

/// 動画広告の用途。
enum RewardKind {
  /// 写真解析 +3 回（[AdPlacement.quotaReward]）。
  quota,

  /// 解説 1 問分の閲覧（[AdPlacement.explanationReward]）。
  explanation,

  /// ライブ体験時間の延長 +1〜3 分（[AdPlacement.liveTrialReward]）。Paywall（体験終了）と
  /// Home（使い切り表示）で見せる。ライブ画面の中では出さない。
  liveTrial;

  /// 計測の `reward` の値（`AppAnalytics` の許可リスト。snake_case）。
  String get analyticsName => switch (this) {
    RewardKind.quota => 'quota',
    RewardKind.explanation => 'explanation',
    RewardKind.liveTrial => 'live_trial',
  };
}

/// 動画広告（設計書 10 章 `RewardedGate`）。読み込み済みのときだけボタンを有効にする。
abstract class RewardedGate extends ChangeNotifier {
  bool isReady(RewardKind kind);

  /// 表示して、最後まで見られたら true。報酬の付与（無料枠 +3 など）は呼び出し側が行う。
  /// 見終えたとき `rewarded_granted{reward}` はここで記録する（呼び出し側は記録しない）。
  Future<bool> show(RewardKind kind);

  /// [show] に加えて、広告を見た時間（表示から報酬の発生まで）を返す。ライブ延長の長さの
  /// 段階づけに使う。既定は [show] を呼んで時間なし（null）を返す（偽物はこのままでよい）。
  Future<RewardedShowResult> showTimed(RewardKind kind) async =>
      RewardedShowResult(earned: await show(kind));
}

final rewardedGateProvider = ChangeNotifierProvider<RewardedGate>((ref) {
  // Pro・同意なしになったら作り直され、読み込み済みの広告は破棄される。
  final enabled = ref.watch(adsEnabledProvider);
  final gate = RewardedAdsGate(
    port: AdMobRewardedAdsPort(ref.watch(adsInitializerProvider)),
    enabled: () => ref.read(adsEnabledProvider),
    analytics: ref.read(analyticsSinkProvider),
  );
  // 写真解析の動画広告は上限に近づく前に用意しておく。ライブ延長の動画は、延長の案内を出す
  // 画面（Paywall・Home）が isReady を聞いたときに読み込む（起動時には読まない）。
  if (enabled) gate.preload(RewardKind.quota);
  return gate;
});
