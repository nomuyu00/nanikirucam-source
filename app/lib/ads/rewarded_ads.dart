import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/ads/ads_initializer.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_config.dart';

/// 動画広告を表示した結果。
class RewardedShowResult {
  const RewardedShowResult({required this.earned, this.watched});

  /// 報酬が発生しなかった（途中で閉じた・表示できなかった）。
  static const RewardedShowResult notEarned = RewardedShowResult(earned: false);

  /// 最後まで見て報酬が発生した。
  final bool earned;

  /// 広告の表示（`onAdShowedFullScreenContent`）から報酬の発生（`onUserEarnedReward`）までの
  /// 経過時間（単調時計）。AdMob は広告の長さを返さないので、これで長さを見積もる。
  /// 表示時刻が取れなかったときは null。
  final Duration? watched;
}

/// 読み込み済みの動画広告 1 本。
abstract class RewardedHandle {
  /// 表示して、最後まで見て報酬が発生したら true。
  Future<bool> show();

  /// [show] に加えて、見た時間を返す。既定は時間なし（null）。
  Future<RewardedShowResult> showTimed() async =>
      RewardedShowResult(earned: await show());

  void dispose();
}

/// 動画広告の SDK 側。[RewardedAdsGate] のテスト用の境界。
abstract class RewardedAdsPort {
  /// [placement] の動画広告を読み込む。失敗・同意なしは null。
  Future<RewardedHandle?> load(AdPlacement placement);
}

/// AdMob の動画広告。
class AdMobRewardedAdsPort implements RewardedAdsPort {
  AdMobRewardedAdsPort(
    this._ads, {
    this.timeout = const Duration(seconds: 30),
  });

  final AdsInitializer _ads;
  final Duration timeout;

  @override
  Future<RewardedHandle?> load(AdPlacement placement) async {
    if (!_ads.canRequestAds) return null;
    final completer = Completer<RewardedHandle?>();
    try {
      await RewardedAd.load(
        adUnitId: AppConfig.adUnitId(placement),
        request: _ads.adRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (completer.isCompleted) {
              unawaited(ad.dispose());
              return;
            }
            completer.complete(_AdMobRewardedHandle(ad));
          },
          onAdFailedToLoad: (error) {
            debugPrint('[Rewarded] load failed: $error');
            if (!completer.isCompleted) completer.complete(null);
          },
        ),
      );
    } catch (error) {
      debugPrint('[Rewarded] load failed: $error');
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future.timeout(timeout, onTimeout: () => null);
  }
}

class _AdMobRewardedHandle extends RewardedHandle {
  _AdMobRewardedHandle(this._ad);

  final RewardedAd _ad;
  bool _disposed = false;

  @override
  Future<bool> show() async => (await showTimed()).earned;

  @override
  Future<RewardedShowResult> showTimed() async {
    if (_disposed) return RewardedShowResult.notEarned;
    var earned = false;
    Duration? watched;
    // 表示された時刻から報酬が発生するまでを、単調時計で測る。
    final stopwatch = Stopwatch();
    final finished = Completer<void>();
    _ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdShowedFullScreenContent: (_) => stopwatch.start(),
      onAdDismissedFullScreenContent: (_) {
        if (!finished.isCompleted) finished.complete();
      },
      onAdFailedToShowFullScreenContent: (_, error) {
        debugPrint('[Rewarded] show failed: $error');
        if (!finished.isCompleted) finished.complete();
      },
    );
    try {
      await _ad.show(
        onUserEarnedReward: (ad, reward) {
          earned = true;
          watched = stopwatch.isRunning ? stopwatch.elapsed : null;
        },
      );
      // show() は表示を始めた時点で返る。閉じられるまで待つ。
      await finished.future;
    } catch (error) {
      debugPrint('[Rewarded] show failed: $error');
    }
    return RewardedShowResult(earned: earned, watched: earned ? watched : null);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_ad.dispose());
  }
}

/// 動画広告の準備と表示（設計書 10 章 `RewardedGate`）。
///
/// 読み込み済みのときだけ [isReady] が true になる。ライブ体験時間の延長
/// （[RewardKind.liveTrial]）にも使うが、ライブ画面の外（Paywall・Home）で見せる。ライブ中は
/// 広告を出さない。付与（無料枠 +3、ライブ +1〜3 分など）は呼び出し側が行う。
/// 報酬が発生したときに `rewarded_granted{reward}` を記録する。
class RewardedAdsGate extends RewardedGate {
  RewardedAdsGate({
    required this._port,
    required this._enabled,
    this._analytics,
    this.retryDelay = const Duration(seconds: 60),
    this.maxRetries = 3,
  });

  final RewardedAdsPort _port;
  final bool Function() _enabled;
  final AnalyticsSink? _analytics;

  /// 読み込みに失敗してから再試行するまでの間隔。
  final Duration retryDelay;
  final int maxRetries;

  final Map<RewardKind, RewardedHandle> _ready = {};
  final Set<RewardKind> _loading = {};
  final Map<RewardKind, int> _failures = {};
  final Set<Timer> _timers = {};
  bool _disposed = false;

  /// 先に読み込んでおく。
  void preload(RewardKind kind) => unawaited(_load(kind));

  @override
  bool isReady(RewardKind kind) {
    if (_disposed || !_enabled()) return false;
    if (_ready.containsKey(kind)) return true;
    // 初めて聞かれたときに読み込みを始める（使われない種類は読み込まない）。
    scheduleMicrotask(() => unawaited(_load(kind)));
    return false;
  }

  @override
  Future<bool> show(RewardKind kind) async => (await showTimed(kind)).earned;

  @override
  Future<RewardedShowResult> showTimed(RewardKind kind) async {
    if (_disposed || !_enabled()) return RewardedShowResult.notEarned;
    final handle = _ready.remove(kind);
    if (handle == null) return RewardedShowResult.notEarned;
    notifyListeners();
    var result = RewardedShowResult.notEarned;
    try {
      result = await handle.showTimed();
    } finally {
      handle.dispose();
    }
    if (result.earned) {
      _analytics?.call(AnalyticsEvent.rewardedGranted, {
        'reward': kind.analyticsName,
      });
    }
    // 次の分を用意する。
    if (!_disposed) unawaited(_load(kind));
    return result;
  }

  static AdPlacement _placementOf(RewardKind kind) => switch (kind) {
    RewardKind.quota => AdPlacement.quotaReward,
    RewardKind.explanation => AdPlacement.explanationReward,
    RewardKind.liveTrial => AdPlacement.liveTrialReward,
  };

  Future<void> _load(RewardKind kind) async {
    if (_disposed || !_enabled()) return;
    if (_ready.containsKey(kind) || !_loading.add(kind)) return;
    RewardedHandle? handle;
    try {
      handle = await _port.load(_placementOf(kind));
    } catch (error) {
      debugPrint('[Rewarded] load failed: $error');
    }
    _loading.remove(kind);
    if (_disposed || !_enabled()) {
      handle?.dispose();
      return;
    }
    if (handle == null) {
      _scheduleRetry(kind);
      return;
    }
    _failures.remove(kind);
    _ready[kind] = handle;
    notifyListeners();
  }

  void _scheduleRetry(RewardKind kind) {
    final failures = (_failures[kind] ?? 0) + 1;
    _failures[kind] = failures;
    if (failures > maxRetries) return;
    late final Timer timer;
    timer = Timer(retryDelay, () {
      _timers.remove(timer);
      unawaited(_load(kind));
    });
    _timers.add(timer);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    for (final handle in _ready.values) {
      handle.dispose();
    }
    _ready.clear();
    super.dispose();
  }
}
