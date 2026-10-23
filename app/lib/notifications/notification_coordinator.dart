import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/notifications_strings.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/notifications/fcm_service.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_routes.dart';

/// 通知のタップで開く画面へ遷移する。起動直後で Navigator がまだ無ければ、次のフレームで再試行する。
typedef NotificationNavigator = void Function(NotificationTap tap);

void navigateForNotification(NotificationTap tap, {int attempts = 20}) {
  final navigator = appNavigatorKey.currentState;
  if (navigator != null) {
    navigator.pushNamed(tap.route, arguments: tap.arguments);
    return;
  }
  if (attempts <= 0) return;
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback(
    (_) => navigateForNotification(tap, attempts: attempts - 1),
  );
  binding.scheduleFrame();
}

/// 通知まわりをまとめて動かす（設計書 12 章）。
///
/// - 設定・アカウント・ストリーク・課金状態が変わるたびに、FCM のトピック購読とトークンの保存、
///   ローカル通知（ストリーク 21:00、トライアル終了前日）の予約を揃える。
/// - 通知の許可は、設定で通知をオンにしたとき、または最初に問題を解いたあとで 1 回だけ聞く
///   （起動直後には聞かない）。
/// - 通知のタップは `notification_opened{topic}` を記録して該当画面へ遷移する。
class NotificationCoordinator {
  NotificationCoordinator(this._ref);

  final Ref _ref;

  /// 自動で許可を聞いたことがあるか（端末内）。
  static const permissionAskedKey = 'notification_permission_asked_v1';

  bool _disposed = false;

  // ライブのセッション（最初に読めた時点を基準にして、その後に増えたものだけを新しいとみなす）。
  bool _liveBaselineSet = false;
  DateTime? _seenLiveSessionStart;
  bool _syncing = false;
  bool _syncAgain = false;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  FcmService get _fcm => _ref.read(fcmServiceProvider);
  LocalNotificationBackend get _local =>
      _ref.read(localNotificationBackendProvider);

  /// 変更の購読を登録する（provider の本体から同期的に呼ぶ）。
  void listen() {
    _ref.listen(appSettingsProvider, (_, _) => unawaited(resync()));
    _ref.listen(authUidProvider, (_, _) => unawaited(resync()));
    _ref.listen(userProfileProvider, (previous, next) {
      // users/{uid} が用意できたら、保存できなかったトークンを書き直す。
      if (previous?.valueOrNull == null && next.valueOrNull != null) {
        _fcm.forgetPushedState();
        unawaited(resync());
      }
    });
    _ref.listen(entitlementsProvider, (_, _) => unawaited(resync()));
    _ref.listen(appLocaleProvider, (_, _) => unawaited(resync()));
    // ライブのセッションが保存されると（ライブ画面が保存後に invalidate する）、
    // 24 時間後の「昨日の対局サマリー」を予約する。
    _ref.listen<AsyncValue<List<LiveSession>>>(
      liveSessionsProvider,
      (_, next) => unawaited(_onLiveSessions(next)),
      fireImmediately: true,
    );
    _ref.listen(streakProvider, (previous, next) {
      unawaited(resync());
      // 最初に問題を解いたあとが、通知の許可を聞く自然なタイミング。
      final firstAnswer =
          previous?.lastAnsweredDate == null && next.lastAnsweredDate != null;
      if (firstAnswer) unawaited(requestPermissionIfFirstTime());
    });
  }

  /// 端末側の購読（タップ・トークン更新）と初期化。
  Future<void> initialize() async {
    await _local.initialize(onTap: _onLocalTap);
    if (_disposed) return;
    _subscriptions.add(_fcm.taps.listen(_open));
    _subscriptions.add(
      _fcm.tokenRefreshes.listen((_) {
        _fcm.forgetPushedState();
        unawaited(resync());
      }),
    );
    // 通知のタップで起動したとき。
    final launchTap = notificationTapFromLocal(await _local.launchPayload());
    if (launchTap != null && !_disposed) _open(launchTap);
    final remoteTap = await _fcm.initialTap();
    if (remoteTap != null && !_disposed) _open(remoteTap);
    await resync();
  }

  void _onLocalTap(String? payload) {
    final tap = notificationTapFromLocal(payload);
    if (tap != null) _open(tap);
  }

  void _open(NotificationTap tap) {
    if (_disposed) return;
    _ref.read(analyticsSinkProvider)(AnalyticsEvent.notificationOpened, {
      'topic': tap.topic,
    });
    unawaited(_navigate(tap));
  }

  Future<void> _navigate(NotificationTap tap) async {
    var target = tap;
    final startedAt = tap.liveSessionStartedAt;
    if (startedAt != null) target = await _resolveLiveSummary(tap, startedAt);
    if (_disposed) return;
    _ref.read(notificationNavigatorProvider)(target);
  }

  /// 対局サマリーの通知: 保存済みのセッションからサマリーの引数を作る。
  /// 消えていた（データ削除、保存件数の上限）ときは Live の入口へ。
  Future<NotificationTap> _resolveLiveSummary(
    NotificationTap tap,
    DateTime startedAt,
  ) async {
    try {
      final store = await _ref.read(liveSessionStoreProvider.future);
      final session = store.find(startedAt);
      if (session != null) {
        return NotificationTap(
          topic: tap.topic,
          route: Routes.liveSummary,
          arguments: session.toSummaryArgs(),
        );
      }
    } catch (error) {
      debugPrint('[Notifications] live session lookup failed: $error');
    }
    return NotificationTap(topic: tap.topic, route: Routes.live);
  }

  Future<void> _onLiveSessions(AsyncValue<List<LiveSession>> value) async {
    try {
      if (_disposed || value.isLoading) return;
      final sessions = value.valueOrNull;
      if (sessions == null) return;
      final latest = sessions.isEmpty ? null : sessions.first;
      if (!_liveBaselineSet) {
        _liveBaselineSet = true;
        _seenLiveSessionStart = latest?.startedAt;
        return;
      }
      if (latest == null || latest.startedAt == _seenLiveSessionStart) return;
      _seenLiveSessionStart = latest.startedAt;
      await scheduleLiveSummary(latest);
    } catch (error) {
      debugPrint('[Notifications] live sessions failed: $error');
    }
  }

  /// [session] の 24 時間後に「昨日の対局サマリー」を予約する（設定がオンで通知が許可されて
  /// いるときだけ。案内 0 回のセッションは予約しない）。
  Future<void> scheduleLiveSummary(LiveSession session) async {
    if (!_ref.read(appSettingsProvider).notifyLiveSummary) return;
    if (await permission() != NotificationPermission.granted) return;
    await _ref.read(localSchedulerProvider).scheduleLiveSummary(
      startedAt: session.startedAt,
      adviceCount: session.adviceCount,
      winCount: session.wins.length,
      now: _ref.read(clockProvider)(),
      strings: _strings(),
    );
  }

  Future<NotificationPermission> permission() async {
    if (await _fcm.available) return _fcm.permission();
    return _local.permission();
  }

  /// OS の許可ダイアログを出す。許可されたら通知を予約し直す。
  Future<NotificationPermission> requestPermission() async {
    final prefs = await _ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(permissionAskedKey, true);
    final result = await (await _fcm.available
        ? _fcm.requestPermission()
        : _local.requestPermission());
    if (result == NotificationPermission.granted) await resync();
    return result;
  }

  /// まだ聞いていなければ、通知が必要な設定のときだけ許可を聞く。
  Future<void> requestPermissionIfFirstTime() async {
    try {
      final prefs = await _ref.read(sharedPreferencesProvider.future);
      if (prefs.getBool(permissionAskedKey) ?? false) return;
      if (!_ref.read(appSettingsProvider).anyNotification) return;
      if (await permission() == NotificationPermission.granted) return;
      await requestPermission();
    } catch (error) {
      debugPrint('[Notifications] requestPermissionIfFirstTime failed: $error');
    }
  }

  /// 設定・アカウント・課金状態に合わせて通知を揃える。重なった呼び出しはまとめる。
  Future<void> resync() async {
    if (_disposed) return;
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _syncAgain = false;
        await _syncOnce();
      } while (_syncAgain && !_disposed);
    } catch (error) {
      debugPrint('[Notifications] resync failed: $error');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    final settings = _ref.read(appSettingsProvider);
    final uid = _ref.read(authUidProvider).valueOrNull;
    await _fcm.sync(uid: uid, settings: settings);
    final granted = await permission() == NotificationPermission.granted;
    final now = _ref.read(clockProvider)();
    final strings = _strings();
    final scheduler = _ref.read(localSchedulerProvider);
    await scheduler.syncStreak(
      enabled: settings.notifyStreak && granted,
      streak: _ref.read(streakProvider),
      now: now,
      todayKey: localDateKey(now),
      strings: strings,
    );
    // 毎朝の今日の問題: サーバーがある版は FCM（notifyDaily）が届けるので、端末内で
    // 予約するのはサーバーなしの版（端末内で 3 問を作る）だけ。
    await scheduler.syncDaily(
      enabled:
          settings.notifyDaily && granted && !AppConfig.firebaseBackendEnabled,
      now: now,
      strings: strings,
    );
    await scheduler.syncTrial(
      entitlement: granted
          ? _ref.read(entitlementsProvider)
          : EntitlementState.free,
      now: now,
      strings: strings,
    );
    // 設定をオフにした・通知の許可を外した場合は、予約済みの対局サマリーも取り消す。
    if (!settings.notifyLiveSummary || !granted) {
      await scheduler.cancelLiveSummary();
    }
  }

  NotificationStrings _strings() {
    final locale =
        _ref.read(appLocaleProvider) ?? ui.PlatformDispatcher.instance.locale;
    return NotificationStrings(
      locale.languageCode == 'en' ? AppLang.en : AppLang.ja,
    );
  }

  /// データ削除のあと、予約済みの通知と購読の控えを消す。
  Future<void> clearAll() async {
    final scheduler = _ref.read(localSchedulerProvider);
    await scheduler.syncStreak(
      enabled: false,
      streak: const StreakState(),
      now: _ref.read(clockProvider)(),
      todayKey: '',
      strings: _strings(),
    );
    await scheduler.syncDaily(
      enabled: false,
      now: _ref.read(clockProvider)(),
      strings: _strings(),
    );
    await scheduler.syncTrial(
      entitlement: EntitlementState.free,
      now: _ref.read(clockProvider)(),
      strings: _strings(),
    );
    await scheduler.cancelLiveSummary();
    await _fcm.clearLocal();
  }

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}

// --- providers --------------------------------------------------------------

final messagingBackendProvider = Provider<MessagingBackend>(
  (ref) => FirebaseMessagingBackend(),
);

final deviceProfileWriterProvider = Provider<DeviceProfileWriter>(
  (ref) => FirestoreDeviceProfileWriter(),
);

final fcmServiceProvider = Provider<FcmService>(
  (ref) => FcmService(
    backend: ref.watch(messagingBackendProvider),
    writer: ref.watch(deviceProfileWriterProvider),
    preferences: () => ref.read(sharedPreferencesProvider.future),
  ),
);

final localNotificationBackendProvider = Provider<LocalNotificationBackend>((
  ref,
) {
  // flutter test にはプラグインがないので何もしない（通知を試すテストは差し替える）。
  if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
    return const NoopLocalNotificationBackend();
  }
  return FlutterLocalNotificationsBackend();
});

final localSchedulerProvider = Provider<LocalScheduler>(
  (ref) => LocalScheduler(ref.watch(localNotificationBackendProvider)),
);

/// 通知のタップで画面を開く処理。テストでは差し替える。
final notificationNavigatorProvider = Provider<NotificationNavigator>(
  (ref) => navigateForNotification,
);

final notificationCoordinatorProvider = Provider<NotificationCoordinator>((
  ref,
) {
  final coordinator = NotificationCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  coordinator.listen();
  unawaited(coordinator.initialize());
  return coordinator;
});
