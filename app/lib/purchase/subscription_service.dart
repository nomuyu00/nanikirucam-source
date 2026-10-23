import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_backend.dart';

enum PurchaseOutcome {
  /// 購入が完了し、Pro になった。
  success,
  cancelled,

  /// 決済が保留中（承認待ち）。
  pending,
  failed,

  /// RevenueCat が未設定、または初期化できなかった。
  unavailable,

  /// 別の購入・復元の最中。
  busy,
}

enum RestoreOutcome { restored, nothingToRestore, failed, unavailable, busy }

enum SubscriptionBusy { none, purchasing, restoring }

enum PlansState { idle, loading, ready, failed }

/// 課金の窓口（設計書 9 章 `SubscriptionService`）。
///
/// - 未設定モード: API キーが空なら RevenueCat を使わず、Pro は常に false。Paywall は「準備中」。
/// - 起動時はまず端末のキャッシュ（最後に確認してから 3 日以内の Pro）を使い、RevenueCat から
///   取れたらそちらを正とする。オフラインでも猶予の間は Pro が続く。
class SubscriptionService extends ChangeNotifier {
  SubscriptionService({
    required this._backend,
    required this._apiKey,
    required this._cache,
    DateTime Function()? now,
    this._analytics,
    this._retryDelay = const Duration(seconds: 2),
    this._maxAttempts = 3,
  }) : _now = now ?? DateTime.now;

  final SubscriptionBackend _backend;
  final String _apiKey;
  final EntitlementCache _cache;
  final DateTime Function() _now;
  final AnalyticsSink? _analytics;
  final Duration _retryDelay;
  final int _maxAttempts;

  StreamSubscription<StoreEntitlement>? _updates;
  Future<void>? _starting;
  bool _startDone = false;
  bool _backendReady = false;
  bool _disposed = false;
  String? _uid;
  StoreEntitlement? _live;
  StoreEntitlement _entitlement = StoreEntitlement.none;
  List<StorePlan> _plans = const [];
  Future<void>? _plansLoad;
  PlansState _plansState = PlansState.idle;
  SubscriptionBusy _busy = SubscriptionBusy.none;

  /// RevenueCat のキーが入っているか（空なら未設定モード）。
  bool get configured => _apiKey.isNotEmpty;

  /// 購入・復元ができる状態か。
  bool get available => _backendReady;

  /// 起動の最中か（キーがあり、初期化がまだ終わっていない）。
  bool get initializing => configured && !_startDone;

  /// 現在のストアの権利。起動直後はキャッシュ、取得できたら RevenueCat の値。
  StoreEntitlement get entitlement => _entitlement;

  List<StorePlan> get plans => _plans;
  PlansState get plansState => _plansState;
  SubscriptionBusy get busy => _busy;

  /// 起動する。何度呼んでも最初の 1 回だけ初期化する。[uid] は Firebase の uid
  /// （RevenueCat の App User ID にする）。まだ分からなければ null で匿名のまま始め、
  /// 分かった時点で [attachUser] を呼ぶ。
  Future<void> start({String? uid}) => _starting ??= _start(uid);

  Future<void> _start(String? uid) async {
    if (!configured) {
      _startDone = true;
      return;
    }
    _uid = uid;
    // まずキャッシュで即座に答える（取得できたら上書きされる）。
    final cached = await _cache.read(_now());
    if (_live == null && !_disposed) _setEntitlement(cached);
    try {
      await _backend.configure(apiKey: _apiKey, appUserId: uid);
      _backendReady = true;
      _updates = _backend.updates.listen(_applyLive);
      _applyLive(await _backend.fetchEntitlement());
    } catch (error) {
      debugPrint('[SubscriptionService] start failed: $error');
    }
    _startDone = true;
    _notify();
    if (_backendReady) unawaited(loadPlans());
  }

  /// uid が決まったとき、または変わったとき。
  Future<void> attachUser(String? uid) async {
    if (uid == null || !configured) return;
    if (_starting == null) {
      await start(uid: uid);
      return;
    }
    await _starting;
    if (!_backendReady || _uid == uid) return;
    _uid = uid;
    try {
      _applyLive(await _backend.logIn(uid));
    } catch (error) {
      debugPrint('[SubscriptionService] logIn failed: $error');
    }
  }

  /// 最新の権利を取り直す（アプリに戻ったとき）。取れなければ今の値のまま。
  Future<void> refresh() async {
    if (!_backendReady) return;
    try {
      _applyLive(await _backend.fetchEntitlement());
    } catch (error) {
      debugPrint('[SubscriptionService] refresh failed: $error');
      if (_live == null) _setEntitlement(await _cache.read(_now()));
    }
  }

  /// Paywall に出すプランを読み込む。読み込み中なら、それが終わるのを待つ。
  Future<void> loadPlans({bool force = false}) async {
    // 起動に失敗していた（通信できなかったなど）なら、再試行のときに初期化からやり直す。
    if (force && configured && _startDone && !_backendReady && !_disposed) {
      _startDone = false;
      _starting = null;
      _notify();
      await start(uid: _uid);
    }
    if (!_backendReady) return;
    final loading = _plansLoad;
    if (loading != null) return loading;
    if (_plansState == PlansState.ready && !force) return;
    final load = _loadPlans();
    _plansLoad = load;
    try {
      await load;
    } finally {
      _plansLoad = null;
    }
  }

  Future<void> _loadPlans() async {
    _plansState = PlansState.loading;
    _notify();
    try {
      _plans = await _backend.fetchPlans();
      _plansState = _plans.isEmpty ? PlansState.failed : PlansState.ready;
    } catch (error) {
      debugPrint('[SubscriptionService] fetchPlans failed: $error');
      _plansState = PlansState.failed;
    }
    _notify();
  }

  Future<PurchaseOutcome> purchase(StorePlan plan) async {
    if (!_backendReady) {
      _log(AnalyticsEvent.purchaseFailed, {'error_code': 'store_unavailable'});
      return PurchaseOutcome.unavailable;
    }
    if (_busy != SubscriptionBusy.none) return PurchaseOutcome.busy;
    _busy = SubscriptionBusy.purchasing;
    _notify();
    _log(AnalyticsEvent.purchaseStarted, {'plan': plan.kind.name});
    try {
      final result = await _backend.purchase(plan);
      final wasPro = _entitlement.pro;
      _applyLive(result, announce: false);
      if (!result.pro) {
        _log(AnalyticsEvent.purchaseFailed, {'error_code': 'purchase_failed'});
        return PurchaseOutcome.failed;
      }
      _log(AnalyticsEvent.purchaseCompleted, {'plan': plan.kind.name});
      if (!wasPro) {
        _log(
          result.trial
              ? AnalyticsEvent.trialStarted
              : AnalyticsEvent.subscriptionActive,
          {'plan': plan.kind.name},
        );
      }
      return PurchaseOutcome.success;
    } on PurchaseCancelledException {
      _log(AnalyticsEvent.purchaseFailed, {'error_code': 'purchase_canceled'});
      return PurchaseOutcome.cancelled;
    } on PurchasePendingException {
      return PurchaseOutcome.pending;
    } catch (error) {
      debugPrint('[SubscriptionService] purchase failed: $error');
      _log(AnalyticsEvent.purchaseFailed, {'error_code': 'purchase_failed'});
      return PurchaseOutcome.failed;
    } finally {
      _busy = SubscriptionBusy.none;
      _notify();
    }
  }

  /// 購入の復元。通信の一時的な失敗は [_maxAttempts] 回まで再試行する。
  Future<RestoreOutcome> restore() async {
    if (!_backendReady) {
      _log(AnalyticsEvent.purchaseFailed, {'error_code': 'store_unavailable'});
      return RestoreOutcome.unavailable;
    }
    if (_busy != SubscriptionBusy.none) return RestoreOutcome.busy;
    _busy = SubscriptionBusy.restoring;
    _notify();
    try {
      StoreEntitlement? result;
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          result = await _backend.restore();
          break;
        } on StoreException catch (error) {
          debugPrint('[SubscriptionService] restore attempt $attempt: $error');
          if (!error.retryable || attempt == _maxAttempts) break;
          await Future<void>.delayed(_retryDelay);
          if (_disposed) break;
        }
      }
      if (result == null) {
        _log(AnalyticsEvent.purchaseFailed, {'error_code': 'purchase_failed'});
        return RestoreOutcome.failed;
      }
      _applyLive(result, announce: false);
      if (!result.pro) return RestoreOutcome.nothingToRestore;
      _log(AnalyticsEvent.purchaseRestored);
      return RestoreOutcome.restored;
    } catch (error) {
      debugPrint('[SubscriptionService] restore failed: $error');
      _log(AnalyticsEvent.purchaseFailed, {'error_code': 'purchase_failed'});
      return RestoreOutcome.failed;
    } finally {
      _busy = SubscriptionBusy.none;
      _notify();
    }
  }

  void _applyLive(StoreEntitlement next, {bool announce = true}) {
    if (_disposed) return;
    final previous = _entitlement;
    _live = next;
    unawaited(_cache.write(next, _now()));
    _setEntitlement(next);
    // トライアルが有料に切り替わった（アプリを開いている間に起きたとき）。
    if (announce && previous.pro && previous.trial && next.pro && !next.trial) {
      _log(AnalyticsEvent.subscriptionActive);
    }
  }

  void _setEntitlement(StoreEntitlement next) {
    if (next == _entitlement) return;
    _entitlement = next;
    _notify();
  }

  void _log(AnalyticsEvent event, [Map<String, Object> parameters = const {}]) {
    if (_disposed) return;
    _analytics?.call(event, parameters);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_updates?.cancel());
    unawaited(_backend.dispose());
    super.dispose();
  }
}

// --- providers --------------------------------------------------------------

/// RevenueCat のキー。テストでは差し替える（空なら未設定モード）。
final revenueCatApiKeyProvider = Provider<String>(
  (ref) => AppConfig.revenueCatApiKey,
);

final subscriptionBackendProvider = Provider<SubscriptionBackend>(
  (ref) => RevenueCatBackend(),
);

/// 購入・復元・プラン一覧。作られた時点で初期化を始める（uid が決まるまで最大 8 秒待つ）。
final subscriptionServiceProvider = ChangeNotifierProvider<SubscriptionService>(
  (ref) {
    final service = SubscriptionService(
      backend: ref.watch(subscriptionBackendProvider),
      apiKey: ref.watch(revenueCatApiKeyProvider),
      cache: EntitlementCache(() => ref.read(sharedPreferencesProvider.future)),
      now: ref.read(clockProvider),
      analytics: ref.read(analyticsSinkProvider),
    );
    if (service.configured) {
      unawaited(() async {
        String? uid;
        try {
          uid = await ref.read(authUidProvider.future).timeout(
            const Duration(seconds: 8),
          );
        } catch (_) {
          // サインインが遅い・失敗: 匿名のまま始め、決まったら紐づける。
        }
        await service.start(uid: uid);
      }());
      ref.listen<AsyncValue<String?>>(authUidProvider, (previous, next) {
        final uid = next.valueOrNull;
        if (uid != null) unawaited(service.attachUser(uid));
      });
    }
    // ChangeNotifierProvider が破棄時に dispose する。
    return service;
  },
);
