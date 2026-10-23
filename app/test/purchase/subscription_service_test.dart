import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_backend.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

void main() {
  late FakeSubscriptionBackend backend;
  late RecordingAnalytics analytics;
  late FakeClock clock;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    backend = FakeSubscriptionBackend();
    analytics = RecordingAnalytics();
    clock = FakeClock(DateTime.utc(2026, 10, 21, 12));
  });

  SubscriptionService build({String apiKey = 'test_key'}) {
    final service = SubscriptionService(
      backend: backend,
      apiKey: apiKey,
      cache: EntitlementCache(() async => prefs),
      now: clock.call,
      analytics: analytics.call,
      retryDelay: Duration.zero,
    );
    addTearDown(service.dispose);
    return service;
  }

  Future<void> writeCache({
    required bool pro,
    required DateTime fetchedAt,
    DateTime? expiresAt,
    bool trial = false,
  }) async {
    await prefs.setString(
      EntitlementCache.preferenceKey,
      jsonEncode({
        'pro': pro,
        'expiresAt': expiresAt?.toIso8601String(),
        'fetchedAt': fetchedAt.toIso8601String(),
        'trial': trial,
      }),
    );
  }

  group('未設定モード', () {
    test('キーが空なら RevenueCat を呼ばず、Pro は常に false', () async {
      final service = build(apiKey: '');
      await service.start(uid: 'u1');
      expect(service.configured, isFalse);
      expect(service.available, isFalse);
      expect(service.entitlement.pro, isFalse);
      expect(backend.configureCalls, 0);
      expect(await service.purchase(FakeSubscriptionBackend.monthly),
          PurchaseOutcome.unavailable);
      expect(await service.restore(), RestoreOutcome.unavailable);
      expect(backend.purchased, isEmpty);
    });
  });

  group('起動と権利', () {
    test('uid を App User ID にして configure し、取得した権利を使う', () async {
      backend.entitlement = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 11, 20),
      );
      final service = build();
      await service.start(uid: 'uid-123');
      expect(backend.configureCalls, 1);
      expect(backend.configuredApiKey, 'test_key');
      expect(backend.configuredUser, 'uid-123');
      expect(service.entitlement.pro, isTrue);
      expect(service.entitlement.until, DateTime.utc(2026, 11, 20));
      // 次回のオフラインに備えてキャッシュに残す。
      await Future<void>.delayed(Duration.zero);
      expect(prefs.getString(EntitlementCache.preferenceKey), contains('"pro":true'));
    });

    test('start は何度呼んでも初期化は 1 回', () async {
      final service = build();
      await Future.wait([service.start(uid: 'a'), service.start(uid: 'b')]);
      expect(backend.configureCalls, 1);
      expect(backend.configuredUser, 'a');
    });

    test('匿名で始めたあと uid が決まったら logIn で紐づける', () async {
      final service = build();
      await service.start();
      expect(backend.configuredUser, isNull);
      await service.attachUser('uid-9');
      expect(backend.loggedIn, ['uid-9']);
      await service.attachUser('uid-9');
      expect(backend.loggedIn, ['uid-9'], reason: '同じ uid では呼ばない');
    });

    test('RevenueCat の更新で権利が変わる（期限切れで無料に戻る）', () async {
      backend.entitlement = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 10, 22),
      );
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isTrue);
      backend.controller.add(StoreEntitlement.none);
      await Future<void>.delayed(Duration.zero);
      expect(service.entitlement.pro, isFalse);
    });

    test('トライアルが有料に変わったら subscription_active を記録する', () async {
      backend.entitlement = StoreEntitlement(
        pro: true,
        trial: true,
        until: DateTime.utc(2026, 10, 25),
      );
      final service = build();
      await service.start();
      expect(analytics.count(AnalyticsEvent.subscriptionActive), 0);
      backend.controller.add(
        StoreEntitlement(pro: true, until: DateTime.utc(2026, 11, 25)),
      );
      await Future<void>.delayed(Duration.zero);
      expect(analytics.count(AnalyticsEvent.subscriptionActive), 1);
    });
  });

  group('オフライン（entitlement_cache_v1、3 日）', () {
    test('取得できなくても、最後に確認してから 3 日以内なら Pro を維持する', () async {
      await writeCache(
        pro: true,
        fetchedAt: clock.now.subtract(const Duration(days: 2, hours: 23)),
      );
      backend.fetchError = const StoreException('offline', retryable: true);
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isTrue);
    });

    test('3 日を過ぎたキャッシュでは Pro にしない', () async {
      await writeCache(
        pro: true,
        fetchedAt: clock.now.subtract(const Duration(days: 3, minutes: 1)),
      );
      backend.fetchError = const StoreException('offline', retryable: true);
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isFalse);
    });

    test('未来の fetchedAt（時計の巻き戻し）は無効', () async {
      await writeCache(
        pro: true,
        fetchedAt: clock.now.add(const Duration(days: 1)),
      );
      backend.fetchError = const StoreException('offline');
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isFalse);
    });

    test('RevenueCat から取れたらキャッシュより優先する（解約済みなら無料）', () async {
      await writeCache(pro: true, fetchedAt: clock.now);
      backend.entitlement = StoreEntitlement.none;
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isFalse);
    });

    test('猶予が切れた後の refresh で無料に戻る', () async {
      await writeCache(
        pro: true,
        fetchedAt: clock.now.subtract(const Duration(days: 2)),
      );
      backend.fetchError = const StoreException('offline');
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isTrue);

      clock.now = clock.now.add(const Duration(days: 2));
      backend.fetchError = const StoreException('offline');
      await service.refresh();
      expect(service.entitlement.pro, isFalse);
    });

    test('キャッシュが壊れていても無料で続行する', () async {
      await prefs.setString(EntitlementCache.preferenceKey, '{broken');
      backend.fetchError = const StoreException('offline');
      final service = build();
      await service.start();
      expect(service.entitlement.pro, isFalse);
    });
  });

  group('プラン', () {
    test('起動後にプランを読み込む。失敗したら failed、force で再読み込み', () async {
      backend.plansError = const StoreException('boom');
      final service = build();
      await service.start();
      await Future<void>.delayed(Duration.zero);
      expect(service.plansState, PlansState.failed);
      await service.loadPlans(force: true);
      expect(service.plansState, PlansState.ready);
      expect(service.plans.map((p) => p.kind), [PlanKind.yearly, PlanKind.monthly]);
    });
  });

  group('初期化の失敗', () {
    test('RevenueCat を初期化できなければ購入はできず、再試行で初期化からやり直す', () async {
      backend.configureError = const StoreException('boom');
      final service = build();
      expect(service.initializing, isTrue);
      await service.start(uid: 'u1');
      expect(service.initializing, isFalse);
      expect(service.available, isFalse);
      expect(await service.purchase(FakeSubscriptionBackend.monthly),
          PurchaseOutcome.unavailable);
      expect(analytics.last(AnalyticsEvent.purchaseFailed)!.parameters, {
        'error_code': 'store_unavailable',
      });

      await service.loadPlans(force: true);
      expect(backend.configureCalls, 2);
      expect(backend.configuredUser, 'u1');
      expect(service.available, isTrue);
      expect(service.plansState, PlansState.ready);
    });

    test('未設定モードは初期化中にならない', () async {
      final service = build(apiKey: '');
      expect(service.initializing, isFalse);
    });
  });

  group('購入', () {
    test('月額（トライアル）: trial_started を記録して Pro になる', () async {
      final service = build();
      await service.start();
      final outcome = await service.purchase(FakeSubscriptionBackend.monthly);
      expect(outcome, PurchaseOutcome.success);
      expect(service.entitlement.pro, isTrue);
      expect(service.entitlement.trial, isTrue);
      expect(analytics.names, [
        AnalyticsEvent.purchaseStarted,
        AnalyticsEvent.purchaseCompleted,
        AnalyticsEvent.trialStarted,
      ]);
      expect(analytics.last(AnalyticsEvent.trialStarted)!.parameters, {
        'plan': 'monthly',
      });
    });

    test('年額（トライアルなし）: subscription_active を記録する', () async {
      final service = build();
      await service.start();
      await service.purchase(FakeSubscriptionBackend.yearly);
      expect(analytics.names, contains(AnalyticsEvent.subscriptionActive));
      expect(analytics.names, isNot(contains(AnalyticsEvent.trialStarted)));
      expect(service.entitlement.trial, isFalse);
    });

    test('キャンセルは cancelled。権利は変わらず purchase_failed(purchase_canceled)', () async {
      final service = build();
      await service.start();
      backend.purchaseError = const PurchaseCancelledException();
      expect(await service.purchase(FakeSubscriptionBackend.monthly),
          PurchaseOutcome.cancelled);
      expect(service.entitlement.pro, isFalse);
      expect(analytics.last(AnalyticsEvent.purchaseFailed)!.parameters, {
        'error_code': 'purchase_canceled',
      });
    });

    test('決済保留は pending', () async {
      final service = build();
      await service.start();
      backend.purchaseError = const PurchasePendingException();
      expect(await service.purchase(FakeSubscriptionBackend.monthly),
          PurchaseOutcome.pending);
      expect(service.entitlement.pro, isFalse);
    });

    test('ストアのエラーは failed（purchase_failed）', () async {
      final service = build();
      await service.start();
      backend.purchaseError = const StoreException('store down');
      expect(await service.purchase(FakeSubscriptionBackend.monthly),
          PurchaseOutcome.failed);
      expect(analytics.last(AnalyticsEvent.purchaseFailed)!.parameters, {
        'error_code': 'purchase_failed',
      });
    });

    test('購入中は busy になり、二重の購入は busy を返す', () async {
      final service = build();
      await service.start();
      backend.purchaseGate = Completer<void>();
      final first = service.purchase(FakeSubscriptionBackend.monthly);
      await Future<void>.delayed(Duration.zero);
      expect(service.busy, SubscriptionBusy.purchasing);
      expect(await service.purchase(FakeSubscriptionBackend.yearly),
          PurchaseOutcome.busy);
      backend.purchaseGate!.complete();
      expect(await first, PurchaseOutcome.success);
      expect(service.busy, SubscriptionBusy.none);
      expect(backend.purchased, hasLength(1));
    });
  });

  group('復元', () {
    test('通信の一時的な失敗は再試行して成功する（purchase_restored）', () async {
      final service = build();
      await service.start();
      backend.restoreErrors.addAll([
        const StoreException('network', retryable: true),
        const StoreException('network', retryable: true),
      ]);
      backend.restoreResult = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 12, 1),
      );
      expect(await service.restore(), RestoreOutcome.restored);
      expect(backend.restoreCalls, 3);
      expect(service.entitlement.pro, isTrue);
      expect(analytics.names, contains(AnalyticsEvent.purchaseRestored));
    });

    test('再試行しても失敗したら failed（3 回まで）', () async {
      final service = build();
      await service.start();
      backend.restoreErrors.addAll([
        for (var i = 0; i < 5; i++)
          const StoreException('network', retryable: true),
      ]);
      expect(await service.restore(), RestoreOutcome.failed);
      expect(backend.restoreCalls, 3);
    });

    test('再試行できないエラーは 1 回で諦める', () async {
      final service = build();
      await service.start();
      backend.restoreErrors.add(const StoreException('invalid receipt'));
      expect(await service.restore(), RestoreOutcome.failed);
      expect(backend.restoreCalls, 1);
    });

    test('復元できる購入がなければ nothingToRestore', () async {
      final service = build();
      await service.start();
      expect(await service.restore(), RestoreOutcome.nothingToRestore);
      expect(analytics.names, isNot(contains(AnalyticsEvent.purchaseRestored)));
    });
  });

  group('CustomerInfo の読み取り', () {
    EntitlementInfo info({
      required bool isActive,
      PeriodType periodType = PeriodType.normal,
      String? expiration = '2026-11-20T00:00:00Z',
      bool willRenew = true,
    }) => EntitlementInfo(
      proEntitlementId,
      isActive,
      willRenew,
      '2026-10-20T00:00:00Z',
      '2026-10-20T00:00:00Z',
      monthlyProductId,
      false,
      periodType: periodType,
      expirationDate: expiration,
    );

    CustomerInfo customer(Map<String, EntitlementInfo> active) => CustomerInfo(
      EntitlementInfos(active, active),
      const {},
      const [],
      const [],
      const [],
      '2026-10-20T00:00:00Z',
      'uid',
      const {},
      '2026-10-21T00:00:00Z',
    );

    test('権利 pro が有効なら Pro、トライアル・期限・自動更新も読む', () {
      final e = entitlementFromCustomerInfo(
        customer({
          proEntitlementId: info(
            isActive: true,
            periodType: PeriodType.trial,
            willRenew: false,
          ),
        }),
      );
      expect(e.pro, isTrue);
      expect(e.trial, isTrue);
      expect(e.willRenew, isFalse);
      expect(e.until, DateTime.utc(2026, 11, 20));
    });

    test('権利が無い・別の ID・期限なし', () {
      expect(entitlementFromCustomerInfo(customer({})).pro, isFalse);
      expect(
        entitlementFromCustomerInfo(
          customer({'other': info(isActive: true)}),
        ).pro,
        isFalse,
      );
      final lifetime = entitlementFromCustomerInfo(
        customer({proEntitlementId: info(isActive: true, expiration: null)}),
      );
      expect(lifetime.pro, isTrue);
      expect(lifetime.until, isNull);
    });
  });
}
