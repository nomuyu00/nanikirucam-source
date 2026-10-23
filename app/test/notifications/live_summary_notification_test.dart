import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/notifications_strings.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/notifications/notification_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';
import '../support/notification_fakes.dart';

LiveSession session({
  required DateTime startedAt,
  int advice = 12,
  int wins = 1,
}) => LiveSession(
  startedAt: startedAt,
  durationSec: 1500,
  adviceCount: advice,
  followedCount: 5,
  followChecks: 8,
  wins: [
    for (var i = 0; i < wins; i++)
      const LiveWinRecord(han: 3, fu: 30, points: 3900, yaku: ['断么九']),
  ],
);

void main() {
  const ja = NotificationStrings(AppLang.ja);

  group('LocalScheduler.scheduleLiveSummary', () {
    test('24 時間後に、案内回数と和了数を入れた通知を予約する', () async {
      final backend = FakeLocalNotifications();
      final now = DateTime(2026, 10, 21, 22, 30);
      final started = DateTime(2026, 10, 21, 21, 5);
      final scheduled = await LocalScheduler(backend).scheduleLiveSummary(
        startedAt: started,
        adviceCount: 12,
        winCount: 1,
        now: now,
        strings: ja,
      );
      expect(scheduled, isTrue);
      final n = backend.scheduled[LocalScheduler.liveSummaryId]!;
      expect(n.at, DateTime(2026, 10, 22, 22, 30));
      expect(n.title, '昨日の対局サマリー');
      expect(n.body, contains('案内12回'));
      expect(n.body, contains('和了1回'));
      expect(n.payload, LocalScheduler.liveSummaryPayload(started));
    });

    test('案内が 0 回のセッションは予約しない（既存の予約も触らない）', () async {
      final backend = FakeLocalNotifications();
      final scheduler = LocalScheduler(backend);
      final now = DateTime(2026, 10, 21, 22);
      await scheduler.scheduleLiveSummary(
        startedAt: DateTime(2026, 10, 21, 21),
        adviceCount: 3,
        winCount: 0,
        now: now,
        strings: ja,
      );
      final scheduled = await scheduler.scheduleLiveSummary(
        startedAt: DateTime(2026, 10, 21, 21, 50),
        adviceCount: 0,
        winCount: 0,
        now: now,
        strings: ja,
      );
      expect(scheduled, isFalse);
      expect(backend.scheduleCalls, 1);
      expect(backend.scheduled, hasLength(1));
    });

    test('新しいセッションの予約は古い予約を置き換える（常に 1 件）', () async {
      final backend = FakeLocalNotifications();
      final scheduler = LocalScheduler(backend);
      await scheduler.scheduleLiveSummary(
        startedAt: DateTime(2026, 10, 21, 12),
        adviceCount: 3,
        winCount: 0,
        now: DateTime(2026, 10, 21, 13),
        strings: ja,
      );
      await scheduler.scheduleLiveSummary(
        startedAt: DateTime(2026, 10, 21, 20),
        adviceCount: 9,
        winCount: 2,
        now: DateTime(2026, 10, 21, 21),
        strings: ja,
      );
      expect(backend.scheduled, hasLength(1));
      final n = backend.scheduled[LocalScheduler.liveSummaryId]!;
      expect(n.at, DateTime(2026, 10, 22, 21));
      expect(n.body, contains('案内9回'));
      expect(n.body, contains('和了2回'));
    });

    test('ペイロードは開始時刻に戻せる。形式が違えば null', () {
      final started = DateTime(2026, 10, 21, 21, 5, 30);
      expect(
        LocalScheduler.liveSummaryStartedAt(
          LocalScheduler.liveSummaryPayload(started),
        ),
        started,
      );
      expect(LocalScheduler.liveSummaryStartedAt('streak'), isNull);
      expect(LocalScheduler.liveSummaryStartedAt('live:xyz'), isNull);
      expect(LocalScheduler.liveSummaryStartedAt(null), isNull);
    });

    test('通知のタップは live_summary の行き先になる', () {
      final started = DateTime(2026, 10, 21, 21, 5);
      final tap = notificationTapFromLocal(
        LocalScheduler.liveSummaryPayload(started),
      )!;
      expect(tap.topic, 'live_summary');
      expect(tap.route, Routes.liveSummary);
      expect(tap.liveSessionStartedAt, started);
    });

    test('英語の文言', () {
      const en = NotificationStrings(AppLang.en);
      expect(en.liveSummaryTitle, 'Yesterday\'s match summary');
      expect(en.liveSummaryBody(12, 1), contains('12 suggestions'));
    });
  });

  group('NotificationCoordinator とライブのセッション保存', () {
    late FakeLocalNotifications local;
    late FakeClock clock;
    late RecordingAnalytics analytics;
    late List<NotificationTap> navigated;

    setUp(() {
      local = FakeLocalNotifications();
      clock = FakeClock(DateTime(2026, 10, 21, 22, 30));
      analytics = RecordingAnalytics();
      navigated = [];
    });

    Future<ProviderContainer> start({
      List<LiveSession> existing = const [],
      Map<String, Object> prefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({
        if (existing.isNotEmpty)
          LiveSessionStore.preferenceKey: _encode(existing),
        ...prefs,
      });
      final c = ProviderContainer(
        overrides: [
          localNotificationBackendProvider.overrideWithValue(local),
          messagingBackendProvider.overrideWithValue(UnavailableMessaging()),
          sharedPreferencesProvider.overrideWith(
            (ref) => SharedPreferences.getInstance(),
          ),
          authUidProvider.overrideWith((ref) async => null),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
          clockProvider.overrideWithValue(clock.call),
          appLocaleProvider.overrideWith((ref) => _JapaneseLocale()),
          analyticsSinkProvider.overrideWithValue(analytics.call),
          notificationNavigatorProvider.overrideWithValue(navigated.add),
          entitlementsProvider.overrideWith((ref) => EntitlementState.free),
        ],
      );
      addTearDown(c.dispose);
      c.read(notificationCoordinatorProvider);
      await pumpEventQueue();
      return c;
    }

    /// ライブ画面と同じ手順: 保存してから `liveSessionsProvider` を invalidate する。
    Future<void> saveLikeLivePage(ProviderContainer c, LiveSession s) async {
      final store = await c.read(liveSessionStoreProvider.future);
      await store.add(s);
      c.invalidate(liveSessionsProvider);
      await pumpEventQueue();
    }

    test('保存されたセッションの 24 時間後に通知を予約する', () async {
      final c = await start();
      await saveLikeLivePage(
        c,
        session(startedAt: DateTime(2026, 10, 21, 21, 5), advice: 12, wins: 1),
      );
      final n = local.scheduled[LocalScheduler.liveSummaryId]!;
      expect(n.at, DateTime(2026, 10, 22, 22, 30));
      expect(n.body, '案内12回、和了1回。振り返りと共有はこちらから。');
    });

    test('起動時にすでに保存されているセッションでは予約しない（新しく増えたときだけ）', () async {
      final c = await start(
        existing: [session(startedAt: DateTime(2026, 10, 20, 21))],
      );
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isFalse);
      expect(c.read(liveSessionsProvider).valueOrNull, hasLength(1));
    });

    test('次のセッションが保存されたら、最新のもので置き換える', () async {
      final c = await start();
      await saveLikeLivePage(
        c,
        session(startedAt: DateTime(2026, 10, 21, 12), advice: 3, wins: 0),
      );
      clock.now = DateTime(2026, 10, 21, 23);
      await saveLikeLivePage(
        c,
        session(startedAt: DateTime(2026, 10, 21, 21, 50), advice: 20, wins: 2),
      );
      expect(
        local.scheduled.keys.where((id) => id == LocalScheduler.liveSummaryId),
        hasLength(1),
      );
      final n = local.scheduled[LocalScheduler.liveSummaryId]!;
      expect(n.at, DateTime(2026, 10, 22, 23));
      expect(n.body, contains('案内20回'));
      expect(
        n.payload,
        LocalScheduler.liveSummaryPayload(DateTime(2026, 10, 21, 21, 50)),
      );
    });

    test('案内 0 回のセッションでは予約しない', () async {
      final c = await start();
      await saveLikeLivePage(
        c,
        session(startedAt: DateTime(2026, 10, 21, 21), advice: 0, wins: 0),
      );
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isFalse);
    });

    test('設定の「昨日の対局サマリー」がオフなら予約しない', () async {
      final c = await start();
      c.read(appSettingsProvider.notifier).update(
        (s) => s.copyWith(notifyLiveSummary: false),
      );
      await pumpEventQueue();
      await saveLikeLivePage(c, session(startedAt: DateTime(2026, 10, 21, 21)));
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isFalse);
    });

    test('設定をオフにすると、予約済みの通知も取り消す。ほかの通知は残る', () async {
      final c = await start();
      await saveLikeLivePage(c, session(startedAt: DateTime(2026, 10, 21, 21)));
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isTrue);
      c.read(appSettingsProvider.notifier).update(
        (s) => s.copyWith(notifyLiveSummary: false),
      );
      await pumpEventQueue();
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isFalse);
      expect(local.scheduled.containsKey(LocalScheduler.streakBaseId), isTrue);
    });

    test('ストリークの設定をオフにしても対局サマリーは別（独立したスイッチ）', () async {
      final c = await start();
      c.read(appSettingsProvider.notifier).update(
        (s) => s.copyWith(notifyStreak: false),
      );
      await pumpEventQueue();
      await saveLikeLivePage(c, session(startedAt: DateTime(2026, 10, 21, 21)));
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isTrue);
    });

    test('通知が許可されていなければ予約しない', () async {
      local.current = NotificationPermission.denied;
      final c = await start();
      await saveLikeLivePage(c, session(startedAt: DateTime(2026, 10, 21, 21)));
      expect(local.scheduled, isEmpty);
    });

    test('通知のタップ: 保存済みのセッションのサマリー画面を、そのセッションの引数で開く', () async {
      final started = DateTime(2026, 10, 21, 21, 5);
      final c = await start();
      await saveLikeLivePage(c, session(startedAt: started, advice: 12, wins: 1));
      final payload = local.scheduled[LocalScheduler.liveSummaryId]!.payload;

      local.onTap!(payload);
      await pumpEventQueue();

      final tap = navigated.single;
      expect(tap.route, Routes.liveSummary);
      final args = tap.arguments! as LiveSummaryArgs;
      expect(args.startedAt, started);
      expect(args.adviceCount, 12);
      expect(args.followChecks, 8);
      expect(args.wins.single.points, 3900);
      final event = analytics.events.single;
      expect(event.event, AnalyticsEvent.notificationOpened);
      expect(event.parameters, {'topic': 'live_summary'});
    });

    test('セッションが消えていたら Live の入口へ', () async {
      final c = await start();
      local.onTap!(
        LocalScheduler.liveSummaryPayload(DateTime(2026, 10, 1, 21)),
      );
      await pumpEventQueue();
      expect(navigated.single.route, Routes.live);
      expect(navigated.single.arguments, isNull);
      expect(c.read(liveSessionsProvider).valueOrNull, isEmpty);
    });

    test('通知のタップで起動したときも同じ', () async {
      final started = DateTime(2026, 10, 21, 21, 5);
      local.launch = LocalScheduler.liveSummaryPayload(started);
      await start(existing: [session(startedAt: started)]);
      expect(navigated.single.route, Routes.liveSummary);
      expect((navigated.single.arguments! as LiveSummaryArgs).startedAt, started);
    });

    test('データ削除: 予約済みの対局サマリーも取り消す', () async {
      final c = await start();
      await saveLikeLivePage(c, session(startedAt: DateTime(2026, 10, 21, 21)));
      await c.read(notificationCoordinatorProvider).clearAll();
      expect(local.scheduled.containsKey(LocalScheduler.liveSummaryId), isFalse);
    });
  });

  group('設定の保存', () {
    test('notifyLiveSummary は既定で ON、保存して読み戻せる。通知のどれかが ON なら anyNotification', () {
      expect(const AppSettings().notifyLiveSummary, isTrue);
      final off = const AppSettings().copyWith(notifyLiveSummary: false);
      expect(AppSettings.fromJson(off.toJson()).notifyLiveSummary, isFalse);
      const onlyLive = AppSettings(
        notifyDaily: false,
        notifyWeekly: false,
        notifyAnswers: false,
        notifyStreak: false,
      );
      expect(onlyLive.anyNotification, isTrue);
      expect(onlyLive.copyWith(notifyLiveSummary: false).anyNotification, isFalse);
    });
  });
}

String _encode(List<LiveSession> sessions) =>
    jsonEncode([for (final s in sessions) s.toJson()]);

/// 端末の言語に関わらず日本語の文言で確かめる。
class _JapaneseLocale extends AppLocaleController {
  _JapaneseLocale() {
    state = const Locale('ja');
  }
}
