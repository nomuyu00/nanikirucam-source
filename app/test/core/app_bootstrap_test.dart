import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_bootstrap.dart';
import 'package:nanikiru_cam/core/app_restart.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/remote_config.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:nanikiru_cam/notifications/fcm_service.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/referral/referral_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

class _CountingLocal extends NoopLocalNotificationBackend {
  _CountingLocal();
  int initialized = 0;

  @override
  Future<void> initialize({required void Function(String? payload) onTap}) async {
    initialized++;
  }
}

class _FakeReferral implements ReferralBackend {
  final List<String> codes = [];
  @override
  Future<ReferralGrant> apply(String code) async {
    codes.add(code);
    return ReferralGrant(proUntil: DateTime.utc(2026, 10, 28, 12));
  }
}

class _FakeRemoteConfig implements RemoteConfigBackend {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<Map<String, Object?>> activate() async => {
    RemoteConfigKeys.liveTargetFps: 9,
  };
  @override
  Future<void> fetchForNextLaunch() async {}
}

void main() {
  testWidgets('AppRestart: 子のツリー（ProviderScope）を作り直して状態を初期化する', (tester) async {
    final counter = StateProvider<int>((ref) => 0);
    await tester.pumpWidget(
      AppRestart(
        child: ProviderScope(
          child: Consumer(
            builder: (context, ref, _) => Directionality(
              textDirection: TextDirection.ltr,
              child: GestureDetector(
                key: const ValueKey('count'),
                onTap: () => ref.read(counter.notifier).state++,
                onLongPress: () => AppRestart.restart(context),
                child: Text('${ref.watch(counter)}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('count')));
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.longPress(find.byKey(const ValueKey('count')));
    await tester.pump();
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('AppRestart で包まれていなければ restart は false', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    );
    expect(AppRestart.isAvailable(captured), isFalse);
    expect(AppRestart.restart(captured), isFalse);
  });

  group('appBootstrapProvider', () {
    late FakeSubscriptionBackend billing;
    late _CountingLocal local;
    late _FakeReferral referral;
    late FakeClock clock;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      billing = FakeSubscriptionBackend(
        entitlement: StoreEntitlement(pro: true, until: DateTime.utc(2026, 12, 1)),
      );
      local = _CountingLocal();
      referral = _FakeReferral();
      clock = FakeClock(DateTime(2026, 10, 21, 12));
    });

    List<Override> overrides({String apiKey = 'test_key'}) => [
      subscriptionBackendProvider.overrideWithValue(billing),
      revenueCatApiKeyProvider.overrideWithValue(apiKey),
      sharedPreferencesProvider.overrideWith(
        (ref) => SharedPreferences.getInstance(),
      ),
      authUidProvider.overrideWith((ref) async => 'uid-1'),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(const UserProfile(uid: 'uid-1')),
      ),
      clockProvider.overrideWithValue(clock.call),
      analyticsSinkProvider.overrideWithValue(RecordingAnalytics().call),
      localNotificationBackendProvider.overrideWithValue(local),
      messagingBackendProvider.overrideWithValue(_UnavailableMessaging()),
      remoteConfigBackendProvider.overrideWithValue(_FakeRemoteConfig()),
      referralBackendProvider.overrideWithValue(referral),
    ];

    test('起動すると、課金・通知・Remote Config が動き出す', () async {
      final container = ProviderContainer(overrides: overrides());
      addTearDown(container.dispose);
      container.read(appBootstrapProvider);
      await pumpEventQueue();
      expect(billing.configureCalls, 1);
      expect(billing.configuredUser, 'uid-1');
      expect(container.read(entitlementsProvider).pro, isTrue);
      expect(local.initialized, 1);
      expect(container.read(modelConfigProvider).liveTargetFps, 9);
    });

    test('RevenueCat のキーが無ければ課金は動かない（アプリは無料のまま起動）', () async {
      final container = ProviderContainer(overrides: overrides(apiKey: ''));
      addTearDown(container.dispose);
      container.read(appBootstrapProvider);
      await pumpEventQueue();
      expect(billing.configureCalls, 0);
      expect(container.read(entitlementsProvider).pro, isFalse);
    });

    testWidgets('リンクで届いた招待コードを自動で使い、結果を画面に出す', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: Consumer(
            builder: (context, ref, _) {
              ref.watch(appBootstrapProvider);
              return MaterialApp(
                navigatorKey: appNavigatorKey,
                locale: const Locale('ja'),
                supportedLocales: const [Locale('ja'), Locale('en')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const Scaffold(body: Text('home')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.text('home')),
      );
      container.read(pendingReferralCodeProvider.notifier).set('ABCD2345');
      await tester.pumpAndSettle();
      expect(referral.codes, ['ABCD2345']);
      expect(
        find.text('招待コードを使いました。Pro が 2026-10-28 まで有効です。'),
        findsOneWidget,
      );
      expect(container.read(pendingReferralCodeProvider), isNull);
    });
  });
}

class _UnavailableMessaging implements MessagingBackend {
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
