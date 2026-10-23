import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/app_restart.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/url_opener.dart';
import 'package:nanikiru_cam/notifications/fcm_service.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/ui/settings/data_deletion.dart';
import 'package:nanikiru_cam/ui/settings/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

class _FakeEraser implements AccountEraser {
  _FakeEraser({this.available = true});

  @override
  final bool available;
  Object? deleteError;
  int deletes = 0;
  int signOuts = 0;

  @override
  Future<void> deleteRemote() async {
    deletes++;
    final e = deleteError;
    if (e != null) throw e;
  }

  @override
  Future<void> signOut() async => signOuts++;
}

class _FakeLocal implements LocalNotificationBackend {
  NotificationPermission current = NotificationPermission.granted;
  NotificationPermission onRequest = NotificationPermission.granted;
  int requests = 0;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {}
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
  }) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<String?> launchPayload() async => null;
}

void main() {
  late FakeSubscriptionBackend backend;
  late _FakeEraser eraser;
  late _FakeLocal local;
  late List<Uri> opened;
  late FakeClock clock;

  setUp(() {
    backend = FakeSubscriptionBackend();
    eraser = _FakeEraser();
    local = _FakeLocal();
    opened = [];
    clock = FakeClock(DateTime(2026, 10, 21, 12));
  });

  Future<ProviderContainer> pumpSettings(
    WidgetTester tester, {
    String apiKey = 'test_key',
    Locale? locale,
    Map<String, Object> prefs = const {},
    EntitlementState? entitlement,
    ReviewAccessConfig? reviewConfig,
    bool withRestart = false,

    /// オンライン機能（サーバー）があるビルドか。既定は「ある」（false が本番のサーバーなし構成）。
    bool online = true,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final overrides = [
      subscriptionBackendProvider.overrideWithValue(backend),
      revenueCatApiKeyProvider.overrideWithValue(apiKey),
      sharedPreferencesProvider.overrideWith(
        (ref) => SharedPreferences.getInstance(),
      ),
      authUidProvider.overrideWith((ref) async => 'uid-1'),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(
          const UserProfile(uid: 'uid-1', referralCode: 'MYCADE22'),
        ),
      ),
      clockProvider.overrideWithValue(clock.call),
      analyticsSinkProvider.overrideWithValue(RecordingAnalytics().call),
      urlOpenerProvider.overrideWithValue((uri) async {
        opened.add(uri);
        return true;
      }),
      accountEraserProvider.overrideWithValue(eraser),
      localNotificationBackendProvider.overrideWithValue(local),
      messagingBackendProvider.overrideWithValue(_NoMessaging()),
      appVersionProvider.overrideWith((ref) async => '1.2.3 (45)'),
      onlineFeaturesProvider.overrideWithValue(online),
      if (reviewConfig != null)
        reviewAccessConfigProvider.overrideWithValue(reviewConfig),
      if (entitlement != null)
        entitlementsProvider.overrideWith((ref) => entitlement),
    ];
    Widget app() => ProviderScope(
      overrides: overrides,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: locale ?? ref.watch(appLocaleProvider) ?? const Locale('ja'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: {
            Routes.paywall: (_) => const Scaffold(body: Text('PAYWALL')),
          },
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpWidget(withRestart ? AppRestart(child: app()) : app());
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(SettingsPage)));
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  /// いま出ている画面（トップかサブページ）の一覧をスクロールして [finder] を見せる。
  Future<void> show(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String name) async {
    await show(tester, key(name));
    await tester.tap(key(name));
  }

  SwitchListTile switchOf(WidgetTester tester, String name) =>
      tester.widget<SwitchListTile>(key(name));

  /// トップの行からサブページ（live / notifications / rules）を開く。
  Future<void> openSection(WidgetTester tester, String name) async {
    await tapKey(tester, 'settings-open-$name');
    await tester.pumpAndSettle();
    expect(key('settings-$name-page'), findsOneWidget);
  }

  /// サブページを閉じてトップへ戻る。
  Future<void> back(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).last).pop();
    await tester.pumpAndSettle();
  }

  group('ルール・撮影・ライブ（settings_v1 に保存）', () {
    testWidgets('既定値を表示し、切り替えると保存される', (tester) async {
      final container = await pumpSettings(tester);
      // トップの行に今の設定の要約が出る。
      expect(find.text('赤ドラあり・喰いタンあり'), findsOneWidget);

      await openSection(tester, 'rules');
      expect(switchOf(tester, 'settings-red-fives').value, isTrue);
      expect(switchOf(tester, 'settings-open-tanyao').value, isTrue);
      expect(switchOf(tester, 'settings-quick-capture').value, isFalse);

      await tester.tap(key('settings-red-fives'));
      await tester.tap(key('settings-quick-capture'));
      await tester.pumpAndSettle();
      await back(tester);
      expect(find.text('赤ドラなし・喰いタンあり・撮るだけモード'), findsOneWidget);

      await openSection(tester, 'live');
      await tapKey(tester, 'settings-live-sound');
      await tester.pumpAndSettle();

      final settings = container.read(appSettingsProvider);
      expect(settings.redFives, isFalse);
      expect(settings.quickCapture, isTrue);
      expect(settings.liveSound, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppSettingsNotifier.preferenceKey),
        contains('"redFives":false'),
      );
    });

    testWidgets('保存された設定で開く', (tester) async {
      await pumpSettings(
        tester,
        prefs: {
          AppSettingsNotifier.preferenceKey:
              '{"openTanyao":false,"quickCapture":true}',
        },
      );
      await openSection(tester, 'rules');
      expect(switchOf(tester, 'settings-open-tanyao').value, isFalse);
      expect(switchOf(tester, 'settings-quick-capture').value, isTrue);
    });
  });

  group('ライブナビ（仕様 6.11）', () {
    testWidgets('既定の軸・振動・明るさ固定を保存し、置き方の案内を次回出す', (tester) async {
      final container = await pumpSettings(
        tester,
        prefs: {'live_guide_seen_v1': true},
      );
      final initial = container.read(appSettingsProvider);
      expect(initial.liveDefaultAxis, StrategyAxis.balance);
      expect(initial.liveHaptics, isTrue);
      expect(initial.liveLockBrightness, isFalse);
      expect(find.text('最初の軸: バランス・振動オン'), findsOneWidget);
      await openSection(tester, 'live');
      expect(switchOf(tester, 'settings-live-haptics').value, isTrue);

      await tester.tap(find.text('速さ'));
      await tester.tap(key('settings-live-haptics'));
      await tapKey(tester, 'settings-live-brightness');
      await tester.pumpAndSettle();
      final settings = container.read(appSettingsProvider);
      expect(settings.liveDefaultAxis, StrategyAxis.speed);
      expect(settings.liveHaptics, isFalse);
      expect(settings.liveLockBrightness, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppSettingsNotifier.preferenceKey),
        contains('"liveDefaultAxis":"speed"'),
      );

      await tapKey(tester, 'settings-live-guide');
      await tester.pumpAndSettle();
      expect(prefs.getBool('live_guide_seen_v1'), isNull);
      expect(find.text('次にライブを始めるときに案内を出します。'), findsOneWidget);

      await back(tester);
      expect(find.text('最初の軸: 速さ・振動オフ'), findsOneWidget);
    });
  });

  group('通知', () {
    testWidgets('オフにすると設定に反映される', (tester) async {
      final container = await pumpSettings(tester);
      expect(find.text('すべてオン'), findsOneWidget);
      await openSection(tester, 'notifications');
      await tester.tap(key('settings-notify-daily'));
      await tester.pumpAndSettle();
      expect(container.read(appSettingsProvider).notifyDaily, isFalse);
      expect(local.requests, 0, reason: 'オフにするときは許可を聞かない');
      await back(tester);
      expect(find.text('5 件中 4 件オン'), findsOneWidget);
    });

    testWidgets('「昨日の対局サマリー」は独立したスイッチで、保存される', (tester) async {
      final container = await pumpSettings(tester);
      await openSection(tester, 'notifications');
      expect(switchOf(tester, 'settings-notify-live-summary').value, isTrue);
      await tapKey(tester, 'settings-notify-live-summary');
      await tester.pumpAndSettle();
      final settings = container.read(appSettingsProvider);
      expect(settings.notifyLiveSummary, isFalse);
      expect(settings.notifyStreak, isTrue, reason: 'ストリークのスイッチとは別');
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppSettingsNotifier.preferenceKey),
        contains('"notifyLiveSummary":false'),
      );
    });

    testWidgets('オンにしたとき、許可がなければ OS の許可を求める。拒否されたら案内する', (tester) async {
      final container = await pumpSettings(
        tester,
        prefs: {AppSettingsNotifier.preferenceKey: '{"notifyWeekly":false}'},
      );
      local.current = NotificationPermission.notDetermined;
      local.onRequest = NotificationPermission.denied;
      await openSection(tester, 'notifications');
      await tester.tap(key('settings-notify-weekly'));
      await tester.pumpAndSettle();
      expect(container.read(appSettingsProvider).notifyWeekly, isTrue);
      expect(local.requests, 1);
      expect(find.textContaining('通知が許可されていません'), findsOneWidget);
    });
  });

  group('言語', () {
    testWidgets('日本語・English・端末に従うを切り替える', (tester) async {
      final container = await pumpSettings(tester);
      expect(container.read(appLocaleProvider), isNull);

      await show(tester, find.text('English'));
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(container.read(appLocaleProvider), const Locale('en'));
      expect(find.text('Settings'), findsOneWidget, reason: '画面も英語になる');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale_v1'), 'en');

      await tester.tap(find.text('Device'));
      await tester.pumpAndSettle();
      expect(container.read(appLocaleProvider), isNull);
    });
  });

  group('プラン・購入の復元・解約', () {
    testWidgets('無料: プランを見るで Paywall へ、復元と解約の導線がある', (tester) async {
      await pumpSettings(tester);
      expect(find.text('無料プラン'), findsOneWidget);
      await tester.tap(key('settings-plan'));
      await tester.pumpAndSettle();
      expect(find.text('PAYWALL'), findsOneWidget);
    });

    testWidgets('復元: 見つからない・見つかった', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'settings-restore');
      await tester.pumpAndSettle();
      expect(find.text('復元できる購入が見つかりませんでした。'), findsOneWidget);

      backend.restoreResult = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 12, 1),
      );
      await tester.pump(const Duration(seconds: 5));
      await tapKey(tester, 'settings-restore');
      await tester.pumpAndSettle();
      expect(find.text('購入を復元しました。'), findsOneWidget);
      expect(find.text('Pro プラン'), findsOneWidget, reason: '復元後は Pro の表示に変わる');
    });

    testWidgets('解約はストアの購読管理ページを開く', (tester) async {
      await pumpSettings(tester);
      await tapKey(tester, 'settings-manage-subscription');
      await tester.pump();
      expect(opened.single, subscriptionManagementUri());
    });

    testWidgets('Pro の表示（期限つき・トライアル中・紹介特典）', (tester) async {
      await pumpSettings(
        tester,
        entitlement: EntitlementState(
          pro: true,
          source: EntitlementSource.store,
          trial: true,
          until: DateTime.utc(2026, 10, 28),
        ),
      );
      expect(find.text('Pro（無料トライアル中）'), findsOneWidget);
      expect(find.text('2026-10-28 まで'), findsOneWidget);
    });

    testWidgets('キー未設定では復元・解約を出さない', (tester) async {
      await pumpSettings(tester, apiKey: '');
      expect(key('settings-restore'), findsNothing);
      expect(key('settings-manage-subscription'), findsNothing);
    });
  });

  group('オンライン機能が無い版（サーバーなし）', () {
    testWidgets('招待コード・ブロック一覧・週間/回答到達の通知を出さない', (tester) async {
      await pumpSettings(tester, online: false);
      expect(find.text('招待コード'), findsNothing);
      expect(key('referral-input'), findsNothing);
      expect(find.text('MYCADE22'), findsNothing);
      expect(key('settings-blocked-authors'), findsNothing);
      await openSection(tester, 'notifications');
      expect(key('settings-notify-weekly'), findsNothing);
      expect(key('settings-notify-answers'), findsNothing);
      // 端末内で使える通知は残す。
      expect(key('settings-notify-daily'), findsOneWidget);
      expect(key('settings-notify-streak'), findsOneWidget);
      expect(key('settings-notify-live-summary'), findsOneWidget);
      expect(find.text('今日の問題'), findsOneWidget);
    });

    testWidgets('データ削除の説明は端末内のデータの削除', (tester) async {
      await pumpSettings(tester, online: false);
      await show(tester, key('settings-delete-data'));
      expect(find.textContaining('サーバー上のデータ'), findsNothing);
      expect(find.textContaining('この端末に保存されている'), findsOneWidget);
    });

    testWidgets('サーバーがある版では、招待コード・ブロック一覧・週間/回答到達の通知を出す', (tester) async {
      await pumpSettings(tester);
      await openSection(tester, 'notifications');
      expect(key('settings-notify-weekly'), findsOneWidget);
      expect(key('settings-notify-answers'), findsOneWidget);
      await back(tester);
      await show(tester, key('referral-input'));
      expect(find.text('招待コード'), findsOneWidget);
      expect(key('referral-input'), findsOneWidget);
      await show(tester, key('settings-blocked-authors'));
      expect(key('settings-blocked-authors'), findsOneWidget);
      await show(tester, key('settings-delete-data'));
      expect(find.textContaining('サーバー上のデータ'), findsOneWidget);
    });
  });

  group('招待コード・規約・バージョン', () {
    testWidgets('自分のコードと入力欄が出る', (tester) async {
      await pumpSettings(tester);
      await show(tester, key('referral-input'));
      expect(find.text('MYCADE22'), findsOneWidget);
      expect(key('referral-input'), findsOneWidget);
    });

    testWidgets('規約・プライバシー・特商法のリンクを開く', (tester) async {
      await pumpSettings(tester);
      for (final name in ['terms', 'privacy', 'tokushoho']) {
        await tapKey(tester, 'settings-$name');
        await tester.pump();
      }
      expect(opened.map((u) => u.toString()), [
        'https://aile-net.jp/nanikirucam-terms/',
        'https://aile-net.jp/nanikirucam-privacy-policy/',
        'https://aile-net.jp/nanikirucam-test-purchases/',
      ]);
    });

    testWidgets('バージョンを表示する', (tester) async {
      await pumpSettings(tester);
      await show(tester, key('settings-version'));
      expect(find.text('1.2.3 (45)'), findsOneWidget);
    });

    testWidgets('分析の同意の切り替えを置いている', (tester) async {
      await pumpSettings(tester);
      await show(tester, find.text('利用状況の分析に協力'));
      expect(find.text('利用状況の分析に協力'), findsOneWidget);
    });
  });

  group('審査用アクセス', () {
    const code = 'widget-test-review-code-never-used-in-release';
    ReviewAccessConfig reviewConfig({bool android = true}) =>
        ReviewAccessConfig(
          codeSha256: sha256.convert(utf8.encode(code)).toString(),
          expiresAt: clock
              .call()
              .toUtc()
              .add(const Duration(days: 30))
              .toIso8601String(),
          android: android,
        );

    testWidgets('設定から入力・解除でき、実際の購入権利は変えない', (tester) async {
      final c = await pumpSettings(
        tester,
        online: false,
        reviewConfig: reviewConfig(),
      );
      await tapKey(tester, 'settings-review-access');
      await tester.pumpAndSettle();
      await tester.enterText(key('review-code'), 'wrong');
      await tester.tap(key('review-activate'));
      await tester.pumpAndSettle();
      expect(find.text('コードを確認してください。'), findsOneWidget);
      expect(c.read(entitlementsProvider).pro, isFalse);
      await tester.enterText(key('review-code'), code);
      await tester.tap(key('review-activate'));
      await tester.pumpAndSettle();
      expect(find.text('Pro（審査用アクセス）'), findsOneWidget);
      expect(c.read(entitlementsProvider).source, EntitlementSource.review);
      expect(c.read(subscriptionServiceProvider).entitlement.pro, isFalse);
      await tester.tap(key('review-deactivate'));
      await tester.pumpAndSettle();
      expect(c.read(entitlementsProvider).pro, isFalse);
      expect(key('review-code'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('review-code')).controller!.text,
        isEmpty,
      );
      // 購入や分析イベントは発生させない。
      expect(backend.purchased, isEmpty);
    });

    testWidgets('非Androidには入口を表示しない', (tester) async {
      await pumpSettings(
        tester,
        online: false,
        reviewConfig: reviewConfig(android: false),
      );
      await show(tester, key('settings-version'));
      expect(key('settings-review-access'), findsNothing);
    });

    testWidgets('データ削除時はメモリ上の審査用権利も解除', (tester) async {
      final c = await pumpSettings(
        tester,
        online: false,
        reviewConfig: reviewConfig(),
      );
      await c.read(reviewAccessProvider).activate(code);
      await tester.pumpAndSettle();
      expect(c.read(entitlementsProvider).pro, isTrue);
      final result = await c.read(dataDeletionProvider).run();
      await tester.pumpAndSettle();
      expect(result.ok, isTrue);
      expect(c.read(entitlementsProvider).pro, isFalse);
    });
  });

  group('データ削除', () {
    Future<void> seedAndOpenDialog(WidgetTester tester) async {
      await tapKey(tester, 'settings-delete-data');
      await tester.pumpAndSettle();
    }

    testWidgets('確認ダイアログでやめれば何も消さない', (tester) async {
      await pumpSettings(
        tester,
        prefs: {'history_v1': '[1]', AppSettingsNotifier.preferenceKey: '{}'},
      );
      await seedAndOpenDialog(tester);
      expect(find.text('データを削除しますか？'), findsOneWidget);
      await tester.tap(key('settings-delete-cancel'));
      await tester.pumpAndSettle();
      expect(eraser.deletes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('history_v1'), '[1]');
    });

    testWidgets('サーバーの削除に失敗したら端末のデータは消さない', (tester) async {
      eraser.deleteError = StateError('offline');
      await pumpSettings(tester, prefs: {'history_v1': '[1]'});
      await seedAndOpenDialog(tester);
      await tester.tap(key('settings-delete-confirm'));
      await tester.pumpAndSettle();
      expect(eraser.deletes, 1);
      expect(eraser.signOuts, 0);
      expect(find.textContaining('削除できませんでした'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('history_v1'), '[1]');
    });

    testWidgets('成功: サーバー → サインアウト → 端末のデータ削除 → アプリを作り直す', (tester) async {
      await pumpSettings(
        tester,
        withRestart: true,
        prefs: {
          'history_v1': '[1]',
          'streak_v1': '{"current":3}',
          'referral_v1': '{"appliedCode":"ABCD2345"}',
          'entitlement_cache_v1': '{"pro":true}',
          AppSettingsNotifier.preferenceKey: '{"quickCapture":true}',
          // 残すもの。
          QuotaNotifier.preferenceKey: '{"date":"2026-10-21","used":4}',
          'live_trial_v1': '{"usedSeconds":120}',
          'install_referrer_consumed_v1': true,
        },
      );
      await openSection(tester, 'rules');
      expect(switchOf(tester, 'settings-quick-capture').value, isTrue);
      await back(tester);

      await seedAndOpenDialog(tester);
      expect(find.textContaining('購読'), findsWidgets, reason: '課金は続くことを案内する');
      await tester.tap(key('settings-delete-confirm'));
      await tester.pumpAndSettle();

      expect(eraser.deletes, 1);
      expect(eraser.signOuts, 1);
      expect(find.text('データを削除しました。アプリを初期状態に戻します。'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('history_v1'), isNull);
      expect(prefs.getString('streak_v1'), isNull);
      expect(prefs.getString('referral_v1'), isNull);
      expect(prefs.getString('entitlement_cache_v1'), isNull);
      expect(prefs.getString(AppSettingsNotifier.preferenceKey), isNull);
      // 無料枠の記録と Install Referrer の印は残す。
      expect(prefs.getString(QuotaNotifier.preferenceKey), isNotNull);
      expect(prefs.getString('live_trial_v1'), isNotNull);
      expect(prefs.getBool('install_referrer_consumed_v1'), isTrue);

      await tester.tap(key('settings-delete-done'));
      await tester.pumpAndSettle();
      // 作り直されて、設定が既定値に戻っている。
      await openSection(tester, 'rules');
      expect(switchOf(tester, 'settings-quick-capture').value, isFalse);
    });

    testWidgets('Firebase 無効なら、サーバーを呼ばず端末のデータだけ消す', (tester) async {
      eraser = _FakeEraser(available: false);
      await pumpSettings(
        tester,
        online: false,
        withRestart: true,
        prefs: {'history_v1': '[1]'},
      );
      await seedAndOpenDialog(tester);
      // サーバーのデータや出題した問題には触れず、端末内の削除だとわかる文言。
      expect(find.textContaining('出題した問題'), findsNothing);
      expect(find.textContaining('招待コード'), findsNothing);
      expect(find.textContaining('サーバー'), findsNothing);
      // 設定画面の説明と、確認ダイアログの本文。
      expect(find.textContaining('この端末に保存されている'), findsNWidgets(2));
      await tester.tap(key('settings-delete-confirm'));
      await tester.pumpAndSettle();
      expect(eraser.deletes, 0);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('history_v1'), isNull);
      await tester.tap(key('settings-delete-done'));
      await tester.pumpAndSettle();
    });
  });
  group('ブロック中の出題者（App Store 審査ガイドライン 1.2）', () {
    String blockedJson() =>
        '[{"uid":"bad-1","nickname":"迷惑さん","blockedAt":"2026-10-20T03:00:00.000Z"},'
        '{"uid":"bad-2","nickname":"","blockedAt":"2026-10-19T03:00:00.000Z"}]';

    testWidgets('一覧に出して、解除すると消えて端末の保存も更新される', (tester) async {
      final container = await pumpSettings(
        tester,
        prefs: {BlockedAuthorsNotifier.preferenceKey: blockedJson()},
      );
      await show(tester, key('settings-unblock-bad-1'));
      expect(find.text('ブロック中の出題者'), findsOneWidget);
      expect(find.text('迷惑さん'), findsOneWidget);
      expect(find.text('匿名の出題者'), findsOneWidget);
      expect(key('settings-blocked-empty'), findsNothing);

      await tester.tap(key('settings-unblock-bad-1'));
      await tester.pumpAndSettle();
      expect(find.text('迷惑さん'), findsNothing);
      expect(find.text('ブロックを解除しました'), findsOneWidget);
      expect(container.read(blockedAuthorsProvider).authors.map((a) => a.uid), [
        'bad-2',
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(BlockedAuthorsNotifier.preferenceKey),
        isNot(contains('bad-1')),
      );
    });

    testWidgets('ブロックしていなければ、ブロックのしかたを案内する', (tester) async {
      await pumpSettings(tester);
      await show(tester, key('settings-blocked-empty'));
      expect(find.text('ブロック中の出題者'), findsOneWidget);
      expect(key('settings-blocked-empty'), findsOneWidget);
    });

    testWidgets('データ削除でブロック一覧も消える（保存もメモリも）', (tester) async {
      final container = await pumpSettings(
        tester,
        prefs: {BlockedAuthorsNotifier.preferenceKey: blockedJson()},
      );
      await show(tester, key('settings-unblock-bad-1'));
      expect(container.read(blockedAuthorsProvider).authors, hasLength(2));
      await tapKey(tester, 'settings-delete-data');
      await tester.pumpAndSettle();
      await tester.tap(key('settings-delete-confirm'));
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(BlockedAuthorsNotifier.preferenceKey), isNull);
      expect(container.read(blockedAuthorsProvider).authors, isEmpty);
      await tester.tap(key('settings-delete-done'));
      await tester.pumpAndSettle();
    });
  });
}

/// FCM を使わない（Firebase 無効のビルド）。
class _NoMessaging implements MessagingBackend {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<NotificationPermission> permission() async =>
      NotificationPermission.notDetermined;
  @override
  Future<NotificationPermission> requestPermission() async =>
      NotificationPermission.notDetermined;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Future<void> subscribe(String topic) async {}
  @override
  Future<void> unsubscribe(String topic) async {}
  @override
  Stream<Map<String, Object?>> get opened => const Stream.empty();
  @override
  Future<Map<String, Object?>?> initialMessage() async => null;
}
