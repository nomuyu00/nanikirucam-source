import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

void main() {
  late FakeClock clock;

  setUp(() {
    clock = FakeClock(DateTime(2026, 10, 21, 12));
  });

  Future<ProviderContainer> container({
    Map<String, Object> prefs = const {},
    bool pro = false,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith(
          (ref) => SharedPreferences.getInstance(),
        ),
        clockProvider.overrideWithValue(clock.call),
        entitlementsProvider.overrideWith(
          (ref) => pro
              ? const EntitlementState(pro: true, source: EntitlementSource.store)
              : EntitlementState.free,
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<Map<String, Object?>> stored() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString(QuotaNotifier.preferenceKey)!)
        as Map<String, Object?>;
  }

  test('無料は 1 日 5 回。5 回目までは使え、6 回目は使えない', () async {
    final c = await container();
    final quota = c.read(quotaProvider.notifier);
    for (var i = 0; i < 5; i++) {
      expect(await quota.tryConsume(), isTrue, reason: '${i + 1} 回目');
    }
    expect(c.read(quotaProvider).remaining, 0);
    expect(c.read(quotaProvider).exhausted, isTrue);
    expect(await quota.tryConsume(), isFalse);
    expect(c.read(quotaProvider).used, 5);
  });

  test('使った回数は quota_v1 に保存され、再起動しても残る', () async {
    final c = await container();
    final quota = c.read(quotaProvider.notifier);
    await quota.tryConsume();
    await quota.tryConsume();
    await pumpEventQueue();
    expect(await stored(), {
      'date': '2026-10-21',
      'used': 2,
      'rewardedUsed': 0,
    });

    // 同じ保存内容で起動し直す。
    final prefs = await SharedPreferences.getInstance();
    final saved = <String, Object>{
      QuotaNotifier.preferenceKey: prefs.getString(QuotaNotifier.preferenceKey)!,
    };
    final again = await container(prefs: saved);
    expect(await again.read(quotaProvider.notifier).tryConsume(), isTrue);
    expect(again.read(quotaProvider).used, 3);
  });

  test('日付が変わると 0 から数え直す（保存された前日分は捨てる）', () async {
    final c = await container(
      prefs: {
        QuotaNotifier.preferenceKey: jsonEncode({
          'date': '2026-10-20',
          'used': 5,
          'rewardedUsed': 3,
        }),
      },
    );
    final quota = c.read(quotaProvider.notifier);
    expect(await quota.tryConsume(), isTrue);
    expect(c.read(quotaProvider).used, 1);
    expect(c.read(quotaProvider).rewardedGranted, 0);
  });

  test('起動中に 0 時をまたいだら、次に使うときに日付が切り替わる', () async {
    final c = await container();
    final quota = c.read(quotaProvider.notifier);
    for (var i = 0; i < 5; i++) {
      await quota.tryConsume();
    }
    expect(await quota.tryConsume(), isFalse);
    clock.now = DateTime(2026, 10, 22, 0, 0, 1);
    expect(await quota.tryConsume(), isTrue);
    expect(c.read(quotaProvider).date, '2026-10-22');
    expect(c.read(quotaProvider).used, 1);
  });

  group('動画広告（+3 回、1 日 2 回まで）', () {
    test('見終えると 3 回増える。上限（2 回）を超えては増えない', () async {
      final c = await container();
      final quota = c.read(quotaProvider.notifier);
      for (var i = 0; i < 5; i++) {
        await quota.tryConsume();
      }
      expect(c.read(quotaProvider).canGrantRewarded, isTrue);
      await quota.grantRewarded();
      expect(c.read(quotaProvider).limit, 8);
      expect(c.read(quotaProvider).remaining, 3);
      expect(await quota.tryConsume(), isTrue);

      await quota.grantRewarded();
      expect(c.read(quotaProvider).limit, 11);
      expect(c.read(quotaProvider).canGrantRewarded, isFalse);

      await quota.grantRewarded();
      expect(c.read(quotaProvider).limit, 11, reason: '3 回目は増えない');
    });

    test('追加分も保存され、日付が変わると消える', () async {
      final c = await container();
      final quota = c.read(quotaProvider.notifier);
      await quota.grantRewarded();
      await pumpEventQueue();
      expect((await stored())['rewardedUsed'], 3);
      clock.now = DateTime(2026, 10, 22, 9);
      await quota.tryConsume();
      expect(c.read(quotaProvider).rewardedGranted, 0);
    });
  });

  group('Pro は無制限', () {
    test('数えず、上限もなく、動画広告で増えない', () async {
      final c = await container(pro: true);
      final quota = c.read(quotaProvider.notifier);
      for (var i = 0; i < 20; i++) {
        expect(await quota.tryConsume(), isTrue);
      }
      expect(c.read(quotaProvider).unlimited, isTrue);
      expect(c.read(quotaProvider).exhausted, isFalse);
      expect(c.read(quotaProvider).used, 0);
      expect(c.read(quotaProvider).canGrantRewarded, isFalse);
      await quota.grantRewarded();
      expect(c.read(quotaProvider).rewardedGranted, 0);
    });

    test('Pro が切れて無料に戻っても、その日に数えた回数は失われない', () async {
      final c = await container();
      final quota = c.read(quotaProvider.notifier);
      await quota.tryConsume();
      await quota.tryConsume();
      c.read(entitlementsProvider.notifier).state = const EntitlementState(
        pro: true,
        source: EntitlementSource.store,
      );
      expect(c.read(quotaProvider).unlimited, isTrue);
      expect(await quota.tryConsume(), isTrue);
      c.read(entitlementsProvider.notifier).state = EntitlementState.free;
      expect(c.read(quotaProvider).unlimited, isFalse);
      expect(c.read(quotaProvider).used, 2);
      expect(c.read(quotaProvider).remaining, 3);
    });
  });

  test('読めない保存データでも無料枠は動く', () async {
    final c = await container(prefs: {QuotaNotifier.preferenceKey: '{x'});
    expect(await c.read(quotaProvider.notifier).tryConsume(), isTrue);
    expect(c.read(quotaProvider).used, 1);
  });
}
