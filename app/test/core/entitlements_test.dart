import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 21, 12);

  group('composeEntitlements（RevenueCat の pro OR 紹介特典）', () {
    test('どちらもなければ無料', () {
      final state = composeEntitlements(
        store: StoreEntitlement.none,
        now: now,
      );
      expect(state, EntitlementState.free);
      expect(state.pro, isFalse);
      expect(state.source, EntitlementSource.none);
    });

    test('ストアの pro: 由来は store、期限とトライアルを引き継ぐ', () {
      final until = DateTime.utc(2026, 10, 28);
      final state = composeEntitlements(
        store: StoreEntitlement(pro: true, until: until, trial: true),
        now: now,
      );
      expect(state.pro, isTrue);
      expect(state.source, EntitlementSource.store);
      expect(state.until, until);
      expect(state.trial, isTrue);
    });

    test('紹介特典が期限内なら Pro（由来は referral、トライアルではない）', () {
      final until = now.add(const Duration(days: 3));
      final state = composeEntitlements(
        store: StoreEntitlement.none,
        referralUntil: until,
        now: now,
      );
      expect(state.pro, isTrue);
      expect(state.source, EntitlementSource.referral);
      expect(state.until, until);
      expect(state.trial, isFalse);
    });

    test('紹介特典が期限切れ（ちょうど今も含む）なら無料', () {
      expect(
        composeEntitlements(
          store: StoreEntitlement.none,
          referralUntil: now.subtract(const Duration(seconds: 1)),
          now: now,
        ).pro,
        isFalse,
      );
      expect(
        composeEntitlements(
          store: StoreEntitlement.none,
          referralUntil: now,
          now: now,
        ).pro,
        isFalse,
      );
    });

    test('両方あればストアを優先する', () {
      final state = composeEntitlements(
        store: const StoreEntitlement(pro: true),
        referralUntil: now.add(const Duration(days: 7)),
        now: now,
      );
      expect(state.source, EntitlementSource.store);
    });
  });

  group('entitlementsProvider', () {
    late FakeSubscriptionBackend backend;
    late FakeClock clock;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      backend = FakeSubscriptionBackend();
      clock = FakeClock(now);
    });

    ProviderContainer container({
      DateTime? referralUntil,
      String apiKey = 'test_key',
    }) {
      final c = ProviderContainer(
        overrides: [
          subscriptionBackendProvider.overrideWithValue(backend),
          revenueCatApiKeyProvider.overrideWithValue(apiKey),
          sharedPreferencesProvider.overrideWith(
            (ref) => SharedPreferences.getInstance(),
          ),
          authUidProvider.overrideWith((ref) async => 'uid-1'),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(
              UserProfile(uid: 'uid-1', referralProUntil: referralUntil),
            ),
          ),
          clockProvider.overrideWithValue(clock.call),
          analyticsSinkProvider.overrideWithValue(RecordingAnalytics().call),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('最初は無料。RevenueCat から Pro が届いたら Pro になる', () async {
      backend.entitlement = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 11, 20),
      );
      final c = container();
      expect(c.read(entitlementsProvider), EntitlementState.free);
      await pumpEventQueue();
      final state = c.read(entitlementsProvider);
      expect(state.pro, isTrue);
      expect(state.source, EntitlementSource.store);
      expect(backend.configuredUser, 'uid-1', reason: 'Firebase の uid が App User ID');
    });

    test('RevenueCat が無料でも、紹介特典が期限内なら Pro', () async {
      final c = container(referralUntil: now.add(const Duration(days: 5)));
      c.read(entitlementsProvider);
      await pumpEventQueue();
      final state = c.read(entitlementsProvider);
      expect(state.pro, isTrue);
      expect(state.source, EntitlementSource.referral);
    });

    test('紹介特典が期限切れなら無料', () async {
      final c = container(referralUntil: now.subtract(const Duration(days: 1)));
      c.read(entitlementsProvider);
      await pumpEventQueue();
      expect(c.read(entitlementsProvider).pro, isFalse);
    });

    test('キー未設定でも紹介特典の Pro は有効（RevenueCat は呼ばない）', () async {
      final c = container(
        referralUntil: now.add(const Duration(days: 2)),
        apiKey: '',
      );
      c.read(entitlementsProvider);
      await pumpEventQueue();
      expect(c.read(entitlementsProvider).source, EntitlementSource.referral);
      expect(backend.configureCalls, 0);
    });

    test('購入すると Pro に変わり、広告・無料枠が参照する pro が true になる', () async {
      final c = container();
      expect(c.read(entitlementsProvider).pro, isFalse);
      await pumpEventQueue();
      final outcome = await c
          .read(subscriptionServiceProvider)
          .purchase(FakeSubscriptionBackend.monthly);
      expect(outcome, PurchaseOutcome.success);
      expect(c.read(entitlementsProvider).pro, isTrue);
      expect(c.read(entitlementsProvider).trial, isTrue);
    });

    test('テストから .notifier で差し替えられる', () {
      final c = container();
      c.read(entitlementsProvider.notifier).state = const EntitlementState(
        pro: true,
        source: EntitlementSource.store,
      );
      expect(c.read(entitlementsProvider).pro, isTrue);
    });
  });
}
