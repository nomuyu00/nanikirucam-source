import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const code = 'test-only-high-entropy-code-not-a-release-secret';
  final digest = sha256.convert(utf8.encode(code)).toString();
  final start = DateTime.utc(2026, 10, 23, 12);
  final expiry = start.add(const Duration(days: 30));
  late DateTime now;
  late SharedPreferences prefs;

  ReviewAccessConfig config({
    bool android = true,
    String? hash,
    String? expires,
  }) => ReviewAccessConfig(
    codeSha256: hash ?? digest,
    expiresAt: expires ?? expiry.toIso8601String(),
    android: android,
  );

  ReviewAccessService service({
    ReviewAccessConfig? settings,
    Future<SharedPreferences> Function()? load,
  }) {
    final result = ReviewAccessService(
      config: settings ?? config(),
      now: () => now,
      preferences: load ?? () async => prefs,
    );
    addTearDown(result.dispose);
    return result;
  }

  setUp(() async {
    now = start;
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  test('未設定・不正値・非Android・期限切れは保存を読まず無効', () async {
    for (final settings in [
      config(hash: ''),
      config(hash: 'not-a-sha256'),
      config(android: false),
      config(expires: ''),
      config(expires: '2026-12-01T00:00:00'), // UTC指定なし
      config(expires: '2027-02-30T00:00:00Z'),
      config(expires: '2026-10-23 14:00:00Z'),
      config(expires: '2026-01-01T00:00:00Z'),
    ]) {
      final s = service(
        settings: settings,
        load: () => throw StateError('must not read'),
      );
      await s.ready;
      expect(s.available, isFalse);
      expect(s.loading, isFalse);
      expect(await s.activate(code), ReviewAccessResult.unavailable);
      expect(s.active, isFalse);
    }
  });

  test('入力した正しいコードだけで有効化。平文を保存しない', () async {
    final s = service();
    await s.ready;
    for (final wrong in ['', 'wrong', code.toUpperCase(), 'x' * 257]) {
      expect(await s.activate(wrong), ReviewAccessResult.invalid);
      expect(s.active, isFalse);
    }
    expect(await s.activate('  $code\n'), ReviewAccessResult.activated);
    expect(s.active, isTrue);
    expect(s.until, expiry);
    expect(prefs.getKeys(), {ReviewAccessService.preferenceKey});
    expect(
      prefs.getString(ReviewAccessService.preferenceKey),
      isNot(contains(code)),
    );
  });

  test('再起動で復元。解除後は次の起動でも無効', () async {
    final first = service();
    await first.ready;
    await first.activate(code);
    final restored = service();
    await restored.ready;
    expect(restored.active, isTrue);
    expect(await restored.disable(), isTrue);
    expect(restored.active, isFalse);
    final next = service();
    await next.ready;
    expect(next.active, isFalse);
  });

  test('コード・期限の変更で以前の保存権利を使い回せない', () async {
    final first = service();
    await first.ready;
    await first.activate(code);
    final rotated = service(
      settings: config(
        expires: expiry.add(const Duration(days: 1)).toIso8601String(),
      ),
    );
    await rotated.ready;
    expect(rotated.active, isFalse);
    expect(prefs.containsKey(ReviewAccessService.preferenceKey), isFalse);
  });

  test('期限ちょうどで失効。復帰通知でも失効し保存を消す', () async {
    final s = service();
    await s.ready;
    await s.activate(code);
    now = expiry;
    expect(s.active, isFalse);
    s.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(prefs.containsKey(ReviewAccessService.preferenceKey), isFalse);
    now = start;
    expect(s.active, isFalse, reason: '失効後に時計を戻しても同じ権利は復活しない');
  });

  test('有効化前に時計を戻すと失効', () async {
    final s = service();
    await s.ready;
    await s.activate(code);
    now = start.subtract(const Duration(seconds: 1));
    s.refresh();
    expect(s.active, isFalse);
  });

  test('保存取得エラーは権利を付与しない', () async {
    final s = service(load: () async => throw StateError('storage failure'));
    await s.ready;
    expect(await s.activate(code), ReviewAccessResult.failed);
    expect(s.active, isFalse);
  });

  test('破損した保存データを信頼しない', () async {
    await prefs.setString(ReviewAccessService.preferenceKey, '{bad json');
    final s = service();
    await s.ready;
    expect(s.active, isFalse);
  });

  test('ストア・紹介特典を優先し、審査用を購入や試用と偽らない', () {
    final review = composeEntitlements(
      store: StoreEntitlement.none,
      reviewUntil: expiry,
      now: now,
    );
    expect(review.pro, isTrue);
    expect(review.source, EntitlementSource.review);
    expect(review.trial, isFalse);
    final paid = composeEntitlements(
      store: const StoreEntitlement(pro: true, trial: true),
      reviewUntil: expiry,
      now: now,
    );
    expect(paid.source, EntitlementSource.store);
    expect(paid.trial, isTrue);
    expect(
      composeEntitlements(
        store: StoreEntitlement.none,
        reviewUntil: now,
        now: now,
      ),
      EntitlementState.free,
    );
    expect(
      composeEntitlements(
        store: StoreEntitlement.none,
        reviewUntil: expiry,
        referralUntil: expiry,
        now: now,
      ).source,
      EntitlementSource.referral,
    );
  });

  testWidgets('操作せず画面を開いたままでも期限で通知して失効', (tester) async {
    final s = service(
      settings: config(
        expires: start.add(const Duration(seconds: 2)).toIso8601String(),
      ),
    );
    await s.ready;
    await s.activate(code);
    var notifications = 0;
    s.addListener(() => notifications++);
    now = start.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(s.active, isFalse);
    expect(notifications, greaterThan(0));
  });
}
