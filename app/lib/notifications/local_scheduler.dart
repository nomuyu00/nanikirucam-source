import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/strings/notifications_strings.dart';
import 'package:timezone/timezone.dart' as tz;

/// 通知の許可の状態。
enum NotificationPermission {
  /// まだ聞いていない（または Android で判別できない）。
  notDetermined,
  granted,
  denied,
}

/// ローカル通知の SDK 側（`flutter_local_notifications`）。テストでは差し替える。
abstract class LocalNotificationBackend {
  /// 初期化する。[onTap] は通知をタップしたときのペイロード。
  Future<void> initialize({required void Function(String? payload) onTap});

  Future<NotificationPermission> permission();

  /// OS の許可ダイアログを出す。
  Future<NotificationPermission> requestPermission();

  /// [at]（端末のローカル時刻）に 1 回だけ鳴らす。
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelName,
    required String channelDescription,
  });

  Future<void> cancel(int id);

  /// 通知のタップで起動したときのペイロード（なければ null）。
  Future<String?> launchPayload();
}

/// 何もしない実装（通知プラグインのない環境: `flutter test` など）。
class NoopLocalNotificationBackend implements LocalNotificationBackend {
  const NoopLocalNotificationBackend();

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {}

  @override
  Future<NotificationPermission> permission() async =>
      NotificationPermission.notDetermined;

  @override
  Future<NotificationPermission> requestPermission() async =>
      NotificationPermission.notDetermined;

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<String?> launchPayload() async => null;
}

/// 本物。どの呼び出しも失敗してもアプリを止めない（プラグインが無いテスト環境も含む）。
class FlutterLocalNotificationsBackend implements LocalNotificationBackend {
  FlutterLocalNotificationsBackend([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // 通知の小アイコン（白一色の透過 PNG。android/app/src/main/res/drawable-*dpi/ic_stat_notify.png）。
          // AndroidManifest の FCM 既定アイコン（default_notification_icon）と同じ。
          android: AndroidInitializationSettings('ic_stat_notify'),
          // 許可はアプリが聞くタイミングで求める（起動直後には出さない）。
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => onTap(response.payload),
      );
      _initialized = true;
      // FCM の通知（AndroidManifest の default_notification_channel_id）も使うチャンネル。
      // 名前は予約のたびに端末の言語のものに更新される。
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                'reminders',
                'リマインド / Reminders',
              ),
            );
      }
    } catch (error) {
      debugPrint('[LocalNotifications] initialize failed: $error');
    }
  }

  @override
  Future<NotificationPermission> permission() async {
    if (!_initialized) return NotificationPermission.notDetermined;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final enabled = await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.areNotificationsEnabled();
          return enabled == true
              ? NotificationPermission.granted
              : NotificationPermission.notDetermined;
        case TargetPlatform.iOS:
          final options = await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.checkPermissions();
          return options?.isEnabled == true
              ? NotificationPermission.granted
              : NotificationPermission.notDetermined;
        default:
          return NotificationPermission.notDetermined;
      }
    } catch (error) {
      debugPrint('[LocalNotifications] permission failed: $error');
      return NotificationPermission.notDetermined;
    }
  }

  @override
  Future<NotificationPermission> requestPermission() async {
    if (!_initialized) return NotificationPermission.notDetermined;
    try {
      bool? granted;
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          granted = await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission();
        case TargetPlatform.iOS:
          granted = await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, sound: true);
        default:
          break;
      }
      return granted == true
          ? NotificationPermission.granted
          : NotificationPermission.denied;
    } catch (error) {
      debugPrint('[LocalNotifications] requestPermission failed: $error');
      return NotificationPermission.denied;
    }
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async {
    if (!_initialized) return;
    try {
      final utc = at.toUtc();
      await _plugin.zonedSchedule(
        id: id,
        // 1 回きりの予約なので、時刻は UTC の瞬間として渡せば足りる。
        scheduledDate: tz.TZDateTime.utc(
          utc.year,
          utc.month,
          utc.day,
          utc.hour,
          utc.minute,
          utc.second,
        ),
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            channelName,
            channelDescription: channelDescription,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        // 正確な時刻の許可（SCHEDULE_EXACT_ALARM）は要らない。数分のずれは許容する。
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (error) {
      debugPrint('[LocalNotifications] schedule failed: $error');
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: id);
    } catch (error) {
      debugPrint('[LocalNotifications] cancel failed: $error');
    }
  }

  @override
  Future<String?> launchPayload() async {
    if (!_initialized) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (error) {
      debugPrint('[LocalNotifications] launchPayload failed: $error');
      return null;
    }
  }
}

/// ローカル通知の予約（ストリーク 21:00、トライアル終了前日。設計書 12 章）。
///
/// どちらも 1 回きりの通知を数日先まで予約し、アプリを開くたびに予約し直す。開かない日が
/// 続けば通知も止まる（しつこくしない）。
class LocalScheduler {
  LocalScheduler(this._backend);

  final LocalNotificationBackend _backend;

  static const int streakBaseId = 2100;
  static const int streakDays = 3;
  static const int trialId = 2200;
  static const int liveSummaryId = 2300;
  static const int dailyBaseId = 2400;
  static const int dailyDays = 3;

  /// ペイロード。タップ時の遷移に使う（`notification_routes.dart`）。
  static const String streakPayload = 'streak';
  static const String trialPayload = 'trial';
  static const String dailyPayload = 'daily';

  /// 毎朝の今日の問題の時刻（ローカル 8:00）。
  static const int dailyHour = 8;

  /// 次の [days] 回分の 8:00（[now] を過ぎた時刻は除く）。
  static List<DateTime> dailyReminderTimes(
    DateTime now, {
    int days = dailyDays,
  }) {
    final times = <DateTime>[];
    for (var offset = 0; times.length < days && offset <= days; offset++) {
      final at = DateTime(now.year, now.month, now.day + offset, dailyHour);
      if (at.isAfter(now)) times.add(at);
    }
    return times;
  }

  /// 毎朝の今日の問題の通知。サーバーの通知（FCM の `notifyDaily`）が届かない版
  /// （バックエンドなし）で、端末内で作る 3 問を知らせる。ストリークと同じく数日先まで
  /// 予約し、アプリを開くたびに予約し直す。
  Future<void> syncDaily({
    required bool enabled,
    required DateTime now,
    required NotificationStrings strings,
  }) async {
    for (var i = 0; i < dailyDays; i++) {
      await _backend.cancel(dailyBaseId + i);
    }
    if (!enabled) return;
    final times = dailyReminderTimes(now);
    for (var i = 0; i < times.length; i++) {
      await _backend.schedule(
        id: dailyBaseId + i,
        at: times[i],
        title: strings.dailyTitle,
        body: strings.dailyBody,
        payload: dailyPayload,
        channelName: strings.channelName,
        channelDescription: strings.channelDescription,
      );
    }
  }

  /// ライブの対局サマリー。`live:` のあとにセッションの開始時刻（ISO 8601）が続く。
  static const String liveSummaryPayloadPrefix = 'live:';

  static String liveSummaryPayload(DateTime startedAt) =>
      '$liveSummaryPayloadPrefix${startedAt.toIso8601String()}';

  /// [liveSummaryPayload] の逆。形式が違えば null。
  static DateTime? liveSummaryStartedAt(String? payload) {
    if (payload == null || !payload.startsWith(liveSummaryPayloadPrefix)) {
      return null;
    }
    return DateTime.tryParse(
      payload.substring(liveSummaryPayloadPrefix.length),
    );
  }

  /// ライブのセッションが終わってから、対局サマリーを知らせるまでの時間（仕様 11 章）。
  static const Duration liveSummaryDelay = Duration(hours: 24);

  /// 対局サマリーの通知を鳴らす時刻。セッション終了の 24 時間後だが、深夜（0 時〜8 時）に
  /// 当たるときはその日の 9 時にずらす（夜中に鳴らさない）。
  static DateTime liveSummaryTime(DateTime now) {
    final at = now.add(liveSummaryDelay);
    if (at.hour < 8) return DateTime(at.year, at.month, at.day, 9);
    return at;
  }

  /// ストリークのリマインドの時刻（ローカル 21:00）。
  static const int reminderHour = 21;

  /// 次の [days] 回分の 21:00。[now] を過ぎた時刻と、回答済みの今日は除く。
  static List<DateTime> streakReminderTimes(
    DateTime now, {
    required bool answeredToday,
    int days = streakDays,
  }) {
    final times = <DateTime>[];
    for (var offset = 0; times.length < days && offset < days + 2; offset++) {
      if (offset == 0 && answeredToday) continue;
      final at = DateTime(now.year, now.month, now.day + offset, reminderHour);
      if (at.isAfter(now)) times.add(at);
    }
    return times;
  }

  /// トライアル終了の前日（期限の 24 時間前）。すでに過ぎていれば null。
  static DateTime? trialReminderTime(DateTime until, DateTime now) {
    final at = until.subtract(const Duration(days: 1));
    return at.isAfter(now) ? at : null;
  }

  Future<void> syncStreak({
    required bool enabled,
    required StreakState streak,
    required DateTime now,
    required String todayKey,
    required NotificationStrings strings,
  }) async {
    for (var i = 0; i < streakDays; i++) {
      await _backend.cancel(streakBaseId + i);
    }
    if (!enabled) return;
    final times = streakReminderTimes(
      now,
      answeredToday: streak.answeredOn(todayKey),
    );
    for (var i = 0; i < times.length; i++) {
      // 鳴らす時点で続いている日数（先の日ほど、回答しなければ途切れる）。
      final current = streak.currentAsOf(times[i]);
      await _backend.schedule(
        id: streakBaseId + i,
        at: times[i],
        title: strings.streakTitle(current),
        body: strings.streakBody(current),
        payload: streakPayload,
        channelName: strings.channelName,
        channelDescription: strings.channelDescription,
      );
    }
  }

  /// ライブのセッション（[startedAt] に始まり、[now] に終わった）の 24 時間後に、
  /// 「昨日の対局サマリー」を知らせる。案内が 0 回のセッションは予約せず false を返す。
  /// すでに予約があれば最新のもので置き換える（予約は常に 1 件）。
  Future<bool> scheduleLiveSummary({
    required DateTime startedAt,
    required int adviceCount,
    required int winCount,
    required DateTime now,
    required NotificationStrings strings,
  }) async {
    if (adviceCount <= 0) return false;
    await _backend.schedule(
      id: liveSummaryId,
      at: liveSummaryTime(now),
      title: strings.liveSummaryTitle,
      body: strings.liveSummaryBody(adviceCount, winCount),
      payload: liveSummaryPayload(startedAt),
      channelName: strings.channelName,
      channelDescription: strings.channelDescription,
    );
    return true;
  }

  Future<void> cancelLiveSummary() => _backend.cancel(liveSummaryId);

  Future<void> syncTrial({
    required EntitlementState entitlement,
    required DateTime now,
    required NotificationStrings strings,
  }) async {
    await _backend.cancel(trialId);
    final until = entitlement.until;
    if (!entitlement.trial || until == null) return;
    final at = trialReminderTime(until, now);
    if (at == null) return;
    await _backend.schedule(
      id: trialId,
      at: at,
      title: strings.trialTitle,
      body: strings.trialBody,
      payload: trialPayload,
      channelName: strings.channelName,
      channelDescription: strings.channelDescription,
    );
  }
}
