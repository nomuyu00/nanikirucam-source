import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/notifications_strings.dart';
import 'package:nanikiru_cam/notifications/fcm_service.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/notifications/notification_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

class _ScheduledNotification {
  const _ScheduledNotification(this.id, this.at, this.title, this.body, this.payload);
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

class _FakeLocalBackend implements LocalNotificationBackend {
  NotificationPermission current = NotificationPermission.granted;
  NotificationPermission onRequest = NotificationPermission.granted;
  int requests = 0;
  String? launch;
  void Function(String? payload)? onTap;
  final Map<int, _ScheduledNotification> scheduled = {};
  final List<int> cancelled = [];

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {
    this.onTap = onTap;
  }

  @override
  Future<NotificationPermission> permission() async => current;

  @override
  Future<NotificationPermission> requestPermission() async {
    requests++;
    current = onRequest;
    return onRequest;
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
    scheduled[id] = _ScheduledNotification(id, at, title, body, payload);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<String?> launchPayload() async => launch;
}

class _FakeMessaging implements MessagingBackend {
  bool available = true;
  NotificationPermission current = NotificationPermission.granted;
  NotificationPermission onRequest = NotificationPermission.granted;
  int requests = 0;
  String? tokenValue = 'token-1';
  final List<String> subscribed = [];
  final List<String> unsubscribed = [];
  Object? subscribeError;
  final StreamController<Map<String, Object?>> openedController =
      StreamController.broadcast();
  final StreamController<String> refreshController = StreamController.broadcast();
  Map<String, Object?>? initial;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<NotificationPermission> permission() async => current;

  @override
  Future<NotificationPermission> requestPermission() async {
    requests++;
    current = onRequest;
    return onRequest;
  }

  @override
  Future<String?> token() async => tokenValue;

  @override
  Stream<String> get tokenRefreshes => refreshController.stream;

  @override
  Future<void> subscribe(String topic) async {
    final error = subscribeError;
    if (error != null) throw error;
    subscribed.add(topic);
  }

  @override
  Future<void> unsubscribe(String topic) async => unsubscribed.add(topic);

  @override
  Stream<Map<String, Object?>> get opened => openedController.stream;

  @override
  Future<Map<String, Object?>?> initialMessage() async => initial;
}

class _WrittenProfile {
  const _WrittenProfile(this.uid, this.token, this.notify);
  final String uid;
  final String? token;
  final Map<String, bool>? notify;
}

class _FakeProfileWriter implements DeviceProfileWriter {
  final List<_WrittenProfile> writes = [];
  Object? error;

  @override
  Future<void> write({
    required String uid,
    String? fcmToken,
    Map<String, bool>? notify,
  }) async {
    final e = error;
    if (e != null) throw e;
    writes.add(_WrittenProfile(uid, fcmToken, notify));
  }
}

void main() {
  const ja = NotificationStrings(AppLang.ja);

  group('通知タップの行き先', () {
    test('サーバーの通知（FCM data.type）', () {
      expect(
        notificationTapFromRemote({'type': 'daily', 'date': '2026-10-21'}),
        const NotificationTap(topic: 'daily', route: Routes.today),
      );
      expect(
        notificationTapFromRemote({'type': 'weekly', 'problemId': 'AbC12345'}),
        const NotificationTap(topic: 'weekly', route: Routes.today),
      );
      expect(
        notificationTapFromRemote({'type': 'answer_milestone', 'count': '10'}),
        const NotificationTap(topic: 'answers', route: Routes.myProblems),
      );
      expect(notificationTapFromRemote({'type': 'other'}), isNull);
      expect(notificationTapFromRemote(const {}), isNull);
    });

    test('端末で予約した通知', () {
      expect(
        notificationTapFromLocal(LocalScheduler.streakPayload),
        const NotificationTap(topic: 'streak', route: Routes.today),
      );
      expect(
        notificationTapFromLocal(LocalScheduler.trialPayload),
        const NotificationTap(topic: 'trial', route: Routes.settings),
      );
      expect(
        notificationTapFromLocal(LocalScheduler.dailyPayload),
        const NotificationTap(topic: 'daily', route: Routes.today),
      );
      expect(notificationTapFromLocal('x'), isNull);
      expect(notificationTapFromLocal(null), isNull);
    });
  });

  group('ストリークのリマインド（21:00）', () {
    test('21:00 より前なら今日から 3 日分', () {
      final times = LocalScheduler.streakReminderTimes(
        DateTime(2026, 10, 21, 12),
        answeredToday: false,
      );
      expect(times, [
        DateTime(2026, 10, 21, 21),
        DateTime(2026, 10, 22, 21),
        DateTime(2026, 10, 23, 21),
      ]);
    });

    test('21:00 を過ぎていれば明日から', () {
      final times = LocalScheduler.streakReminderTimes(
        DateTime(2026, 10, 21, 21, 30),
        answeredToday: false,
      );
      expect(times.first, DateTime(2026, 10, 22, 21));
      expect(times, hasLength(3));
    });

    test('今日すでに回答していれば、今日の分は鳴らさない', () {
      final times = LocalScheduler.streakReminderTimes(
        DateTime(2026, 10, 21, 12),
        answeredToday: true,
      );
      expect(times.first, DateTime(2026, 10, 22, 21));
      expect(times, hasLength(3));
    });

    test('月末をまたぐ', () {
      final times = LocalScheduler.streakReminderTimes(
        DateTime(2026, 10, 31, 22),
        answeredToday: false,
      );
      expect(times.first, DateTime(2026, 11, 1, 21));
    });

    test('予約して、回答済みの日・オフのときは取り消す', () async {
      final backend = _FakeLocalBackend();
      final scheduler = LocalScheduler(backend);
      final now = DateTime(2026, 10, 21, 12);
      await scheduler.syncStreak(
        enabled: true,
        streak: const StreakState(current: 5, best: 5, lastAnsweredDate: '2026-10-20'),
        now: now,
        todayKey: '2026-10-21',
        strings: ja,
      );
      expect(backend.scheduled.keys, [
        LocalScheduler.streakBaseId,
        LocalScheduler.streakBaseId + 1,
        LocalScheduler.streakBaseId + 2,
      ]);
      final first = backend.scheduled[LocalScheduler.streakBaseId]!;
      expect(first.at, DateTime(2026, 10, 21, 21));
      expect(first.title, '5日連続中！');
      expect(first.payload, LocalScheduler.streakPayload);

      // 回答した → 今日の分がなくなる。
      await scheduler.syncStreak(
        enabled: true,
        streak: const StreakState(current: 6, best: 6, lastAnsweredDate: '2026-10-21'),
        now: now,
        todayKey: '2026-10-21',
        strings: ja,
      );
      expect(
        backend.scheduled.values.map((n) => n.at).reduce(
          (a, b) => a.isBefore(b) ? a : b,
        ),
        DateTime(2026, 10, 22, 21),
      );

      // オフ → 全部取り消す。
      await scheduler.syncStreak(
        enabled: false,
        streak: const StreakState(),
        now: now,
        todayKey: '2026-10-21',
        strings: ja,
      );
      expect(backend.scheduled, isEmpty);
    });

    test('連続日数がないときの文言', () {
      expect(ja.streakTitle(0), '今日の何切る、まだですか？');
      expect(ja.streakTitle(3), '3日連続中！');
      expect(const NotificationStrings(AppLang.en).streakTitle(3), '3-day streak!');
    });
  });

  group('毎朝の今日の問題（8:00、サーバーなしの版）', () {
    test('8:00 より前なら今日から 3 日分、過ぎていれば明日から', () {
      expect(LocalScheduler.dailyReminderTimes(DateTime(2026, 10, 21, 7)), [
        DateTime(2026, 10, 21, 8),
        DateTime(2026, 10, 22, 8),
        DateTime(2026, 10, 23, 8),
      ]);
      expect(LocalScheduler.dailyReminderTimes(DateTime(2026, 10, 31, 9)), [
        DateTime(2026, 11, 1, 8),
        DateTime(2026, 11, 2, 8),
        DateTime(2026, 11, 3, 8),
      ]);
    });

    test('予約して、オフなら取り消す', () async {
      final backend = _FakeLocalBackend();
      final scheduler = LocalScheduler(backend);
      final now = DateTime(2026, 10, 21, 12);
      await scheduler.syncDaily(enabled: true, now: now, strings: ja);
      expect(backend.scheduled.keys, [
        LocalScheduler.dailyBaseId,
        LocalScheduler.dailyBaseId + 1,
        LocalScheduler.dailyBaseId + 2,
      ]);
      final first = backend.scheduled[LocalScheduler.dailyBaseId]!;
      expect(first.at, DateTime(2026, 10, 22, 8));
      expect(first.title, '今日の何切る 3 問');
      expect(first.payload, LocalScheduler.dailyPayload);
      expect(
        const NotificationStrings(AppLang.en).dailyTitle,
        "Today's three problems",
      );

      await scheduler.syncDaily(enabled: false, now: now, strings: ja);
      expect(backend.scheduled, isEmpty);
    });
  });

  group('トライアル終了前日の通知', () {
    test('期限の 24 時間前。過ぎていれば予約しない', () {
      final until = DateTime(2026, 10, 28, 14);
      expect(
        LocalScheduler.trialReminderTime(until, DateTime(2026, 10, 21, 14)),
        DateTime(2026, 10, 27, 14),
      );
      expect(
        LocalScheduler.trialReminderTime(until, DateTime(2026, 10, 27, 15)),
        isNull,
      );
    });

    test('トライアル中だけ予約し、終わったら取り消す', () async {
      final backend = _FakeLocalBackend();
      final scheduler = LocalScheduler(backend);
      final now = DateTime(2026, 10, 21, 14);
      await scheduler.syncTrial(
        entitlement: EntitlementState(
          pro: true,
          source: EntitlementSource.store,
          trial: true,
          until: DateTime(2026, 10, 28, 14),
        ),
        now: now,
        strings: ja,
      );
      final scheduled = backend.scheduled[LocalScheduler.trialId]!;
      expect(scheduled.at, DateTime(2026, 10, 27, 14));
      expect(scheduled.title, '無料トライアルは明日までです');
      expect(scheduled.payload, LocalScheduler.trialPayload);

      // 有料に切り替わった → 取り消す。
      await scheduler.syncTrial(
        entitlement: EntitlementState(
          pro: true,
          source: EntitlementSource.store,
          until: DateTime(2026, 11, 28),
        ),
        now: now,
        strings: ja,
      );
      expect(backend.scheduled, isEmpty);
    });

    test('紹介特典の Pro（トライアルではない）では予約しない', () async {
      final backend = _FakeLocalBackend();
      await LocalScheduler(backend).syncTrial(
        entitlement: EntitlementState(
          pro: true,
          source: EntitlementSource.referral,
          until: DateTime(2026, 10, 28),
        ),
        now: DateTime(2026, 10, 21),
        strings: ja,
      );
      expect(backend.scheduled, isEmpty);
    });
  });

  group('FcmService（トピックとトークン）', () {
    late _FakeMessaging messaging;
    late _FakeProfileWriter writer;
    late SharedPreferences prefs;
    late FcmService fcm;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      messaging = _FakeMessaging();
      writer = _FakeProfileWriter();
      fcm = FcmService(
        backend: messaging,
        writer: writer,
        preferences: () async => prefs,
      );
    });

    test('設定どおりに daily / weekly を購読し、トークンと notify を保存する', () async {
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(messaging.subscribed.toSet(), {'daily', 'weekly'});
      expect(prefs.getStringList(FcmService.topicsKey), ['daily', 'weekly']);
      final write = writer.writes.single;
      expect(write.uid, 'u1');
      expect(write.token, 'token-1');
      expect(write.notify, {'daily': true, 'weekly': true, 'milestone': true});
    });

    test('オフにしたトピックは購読解除する。変わらなければ何もしない', () async {
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      messaging.subscribed.clear();
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(messaging.subscribed, isEmpty, reason: '購読済みは再購読しない');
      expect(writer.writes, hasLength(1), reason: '同じ内容は書き直さない');

      await fcm.sync(
        uid: 'u1',
        settings: const AppSettings(notifyDaily: false, notifyAnswers: false),
      );
      expect(messaging.unsubscribed, ['daily']);
      expect(prefs.getStringList(FcmService.topicsKey), ['weekly']);
      expect(writer.writes.last.notify, {
        'daily': false,
        'weekly': true,
        'milestone': false,
      });
    });

    test('購読に失敗したトピックは控えず、次の同期で再試行する', () async {
      messaging.subscribeError = StateError('apns-token-not-set');
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(prefs.getStringList(FcmService.topicsKey), isEmpty);
      messaging.subscribeError = null;
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(messaging.subscribed.toSet(), {'daily', 'weekly'});
    });

    test('通知が許可されていなければ何もしない', () async {
      messaging.current = NotificationPermission.denied;
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(messaging.subscribed, isEmpty);
      expect(writer.writes, isEmpty);
    });

    test('Firebase が無効なら何もしない', () async {
      messaging.available = false;
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(messaging.subscribed, isEmpty);
      expect(writer.writes, isEmpty);
      expect(await fcm.permission(), NotificationPermission.notDetermined);
      expect(await fcm.requestPermission(), NotificationPermission.notDetermined);
      expect(messaging.requests, 0);
    });

    test('未サインインならトピックだけ。サインイン後にトークンを保存する', () async {
      await fcm.sync(uid: null, settings: const AppSettings());
      expect(messaging.subscribed.toSet(), {'daily', 'weekly'});
      expect(writer.writes, isEmpty);
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(writer.writes, hasLength(1));
    });

    test('users/{uid} がまだ無くて保存に失敗したら、次の同期で書き直す', () async {
      writer.error = StateError('not-found');
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(writer.writes, isEmpty);
      writer.error = null;
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(writer.writes, hasLength(1));
    });

    test('トークンが取れない間は保存しない', () async {
      messaging.tokenValue = null;
      await fcm.sync(uid: 'u1', settings: const AppSettings());
      expect(writer.writes, isEmpty);
    });

    test('タップの data を行き先に変換して流す', () async {
      final taps = <NotificationTap>[];
      final sub = fcm.taps.listen(taps.add);
      messaging.openedController
        ..add({'type': 'daily'})
        ..add({'type': 'unknown'})
        ..add({'type': 'answer_milestone'});
      await pumpEventQueue();
      expect(taps.map((t) => t.topic), ['daily', 'answers']);
      await sub.cancel();
    });
  });

  group('NotificationCoordinator（設定・アカウント・課金状態と連動）', () {
    late _FakeLocalBackend local;
    late _FakeMessaging messaging;
    late _FakeProfileWriter writer;
    late FakeClock clock;
    late RecordingAnalytics analytics;
    late List<NotificationTap> navigated;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      local = _FakeLocalBackend();
      messaging = _FakeMessaging();
      writer = _FakeProfileWriter();
      clock = FakeClock(DateTime(2026, 10, 21, 12));
      analytics = RecordingAnalytics();
      navigated = [];
    });

    ProviderContainer container({String? uid = 'uid-1'}) {
      final c = ProviderContainer(
        overrides: [
          localNotificationBackendProvider.overrideWithValue(local),
          messagingBackendProvider.overrideWithValue(messaging),
          deviceProfileWriterProvider.overrideWithValue(writer),
          sharedPreferencesProvider.overrideWith(
            (ref) => SharedPreferences.getInstance(),
          ),
          authUidProvider.overrideWith((ref) async => uid),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(uid == null ? null : UserProfile(uid: uid)),
          ),
          clockProvider.overrideWithValue(clock.call),
          analyticsSinkProvider.overrideWithValue(analytics.call),
          notificationNavigatorProvider.overrideWithValue(navigated.add),
          entitlementsProvider.overrideWith((ref) => EntitlementState.free),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('起動時: トピックを購読し、ストリークのリマインドを予約する', () async {
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(messaging.subscribed.toSet(), {'daily', 'weekly'});
      expect(writer.writes.single.uid, 'uid-1');
      expect(local.scheduled.keys, contains(LocalScheduler.streakBaseId));
    });

    test('設定の変更がトピックの購読・解除とローカル通知に反映される', () async {
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();

      c.read(appSettingsProvider.notifier).update(
        (s) => s.copyWith(notifyDaily: false, notifyStreak: false),
      );
      await pumpEventQueue();
      expect(messaging.unsubscribed, ['daily']);
      expect(local.scheduled, isEmpty, reason: 'ストリークをオフにしたので予約を取り消す');

      c.read(appSettingsProvider.notifier).update(
        (s) => s.copyWith(notifyDaily: true, notifyStreak: true),
      );
      await pumpEventQueue();
      expect(messaging.subscribed.where((t) => t == 'daily'), hasLength(2));
      expect(local.scheduled, isNotEmpty);
    });

    test('今日回答すると、今日の 21:00 の予約がなくなる', () async {
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(
        local.scheduled[LocalScheduler.streakBaseId]!.at,
        DateTime(2026, 10, 21, 21),
      );
      await c.read(streakProvider.notifier).recordAnswer(clock.now);
      await pumpEventQueue();
      // ストリークの予約だけを見る（毎朝の今日の問題の予約も並ぶため）。
      final times = [
        for (final n in local.scheduled.values)
          if (n.payload == LocalScheduler.streakPayload) n.at,
      ]..sort();
      expect(times.first, DateTime(2026, 10, 22, 21));
    });

    test('サーバーなしの版は毎朝 8:00 の今日の問題を端末で予約する（設定でオフにできる）', () async {
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      if (AppConfig.firebaseBackendEnabled) {
        // サーバーがある版は FCM が届けるので予約しない。
        expect(local.scheduled.keys, isNot(contains(LocalScheduler.dailyBaseId)));
        return;
      }
      final daily = local.scheduled[LocalScheduler.dailyBaseId]!;
      expect(daily.at, DateTime(2026, 10, 22, 8));
      expect(daily.payload, LocalScheduler.dailyPayload);
      // 文言は端末の言語（テスト環境では英語のことがある）。
      expect(daily.title, anyOf('今日の何切る 3 問', "Today's three problems"));

      c.read(appSettingsProvider.notifier).update(
        (s) => s.copyWith(notifyDaily: false),
      );
      await pumpEventQueue();
      expect(
        local.scheduled.values.where(
          (n) => n.payload == LocalScheduler.dailyPayload,
        ),
        isEmpty,
      );
      expect(local.scheduled.keys, contains(LocalScheduler.streakBaseId));
    });

    test('通知が許可されていなければ予約しない', () async {
      local.current = NotificationPermission.denied;
      messaging.current = NotificationPermission.denied;
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(local.scheduled, isEmpty);
      expect(messaging.subscribed, isEmpty);
    });

    test('Firebase が無効でもローカル通知は動く（FCM は何もしない）', () async {
      messaging.available = false;
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(messaging.subscribed, isEmpty);
      expect(writer.writes, isEmpty);
      expect(local.scheduled, isNotEmpty);
    });

    test('トライアル中なら終了前日の通知を予約する', () async {
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      c.read(entitlementsProvider.notifier).state = EntitlementState(
        pro: true,
        source: EntitlementSource.store,
        trial: true,
        until: DateTime(2026, 10, 28, 14),
      );
      await pumpEventQueue();
      expect(local.scheduled[LocalScheduler.trialId]!.at, DateTime(2026, 10, 27, 14));
    });

    test('通知のタップ: notification_opened{topic} を記録して該当画面へ', () async {
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();

      messaging.openedController.add({'type': 'daily'});
      await pumpEventQueue();
      local.onTap!(LocalScheduler.streakPayload);
      local.onTap!(LocalScheduler.trialPayload);
      messaging.openedController.add({'type': 'answer_milestone'});
      await pumpEventQueue();

      expect(navigated.map((t) => t.route), [
        Routes.today,
        Routes.today,
        Routes.settings,
        Routes.myProblems,
      ]);
      expect(
        analytics.events
            .where((e) => e.event == AnalyticsEvent.notificationOpened)
            .map((e) => e.parameters['topic']),
        ['daily', 'streak', 'trial', 'answers'],
      );
    });

    test('通知のタップで起動したとき（ローカル・FCM）も遷移する', () async {
      local.launch = LocalScheduler.streakPayload;
      messaging.initial = {'type': 'answer_milestone'};
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(navigated.map((t) => t.topic), ['streak', 'answers']);
    });

    test('許可は最初の回答のあとに 1 回だけ聞く（起動直後には聞かない）', () async {
      local.current = NotificationPermission.notDetermined;
      messaging.current = NotificationPermission.notDetermined;
      final c = container();
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(messaging.requests, 0);
      expect(local.requests, 0);

      await c.read(streakProvider.notifier).recordAnswer(clock.now);
      await pumpEventQueue();
      expect(messaging.requests, 1);

      // 許可されたので、トピックを購読し予約もする。
      expect(messaging.subscribed.toSet(), {'daily', 'weekly'});
      expect(local.scheduled, isNotEmpty);

      // もう聞かない。
      messaging.current = NotificationPermission.notDetermined;
      clock.now = DateTime(2026, 10, 22, 12);
      await c.read(streakProvider.notifier).recordAnswer(clock.now);
      await pumpEventQueue();
      expect(messaging.requests, 1);
    });

    test('通知がすべてオフなら許可を聞かない', () async {
      messaging.current = NotificationPermission.notDetermined;
      final c = container();
      c.read(appSettingsProvider.notifier).replace(
        const AppSettings(
          notifyDaily: false,
          notifyWeekly: false,
          notifyAnswers: false,
          notifyStreak: false,
          notifyLiveSummary: false,
        ),
      );
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      await c.read(streakProvider.notifier).recordAnswer(clock.now);
      await pumpEventQueue();
      expect(messaging.requests, 0);
    });

    test('Firebase が無効なら許可はローカル通知側で聞く', () async {
      messaging.available = false;
      local.current = NotificationPermission.notDetermined;
      final c = container();
      final coordinator = c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      final result = await coordinator.requestPermission();
      expect(result, NotificationPermission.granted);
      expect(local.requests, 1);
      expect(messaging.requests, 0);
    });

    test('許可を拒否されたら denied を返し、予約はしない', () async {
      messaging.current = NotificationPermission.notDetermined;
      local.current = NotificationPermission.notDetermined;
      messaging.onRequest = NotificationPermission.denied;
      final c = container();
      final coordinator = c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(await coordinator.requestPermission(), NotificationPermission.denied);
      expect(local.scheduled, isEmpty);
    });

    test('データ削除: 予約済みの通知と購読の控えを消す', () async {
      final c = container();
      final coordinator = c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      expect(local.scheduled, isNotEmpty);
      await coordinator.clearAll();
      expect(local.scheduled, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(FcmService.topicsKey), isFalse);
    });
  });
}
