import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';

import '../problems/fakes.dart';

void main() {
  group('UserProfile', () {
    test('users/{uid} のドキュメントから作る（紹介特典の期限は pro.referral.until）', () {
      final profile = UserProfile.fromData('u1', {
        'nickname': 'まじゃおう',
        'referralCode': 'ABCD2345',
        'locale': 'ja',
        'pro': {
          'active': true,
          'source': 'referral',
          'until': DateTime.utc(2026, 10, 28),
          'referral': {'until': DateTime.utc(2026, 10, 28, 3)},
        },
      });
      expect(profile.uid, 'u1');
      expect(profile.nickname, 'まじゃおう');
      expect(profile.referralCode, 'ABCD2345');
      expect(profile.referralProUntil, DateTime.utc(2026, 10, 28, 3));
    });

    test('値が足りなくても作れる（空文字は null、期限は ISO 文字列も読む）', () {
      final profile = UserProfile.fromData('u1', {
        'nickname': '',
        'pro': {
          'referral': {'until': '2026-11-01T00:00:00.000Z'},
        },
      });
      expect(profile.nickname, isNull);
      expect(profile.referralCode, isNull);
      expect(profile.referralProUntil, DateTime.utc(2026, 11, 1));
      expect(UserProfile.fromData('u2', {}).referralProUntil, isNull);
    });

    test('ensureUser の返事: 紹介由来の期限だけを referralProUntil にする', () {
      final referral = UserProfile.fromEnsureUser('u1', {
        'referralCode': 'ABCD2345',
        'nickname': null,
        'pro': {
          'active': true,
          'source': 'referral',
          'until': '2026-10-28T00:00:00Z',
        },
        'created': true,
      });
      expect(referral.referralCode, 'ABCD2345');
      expect(referral.referralProUntil, DateTime.utc(2026, 10, 28));

      final store = UserProfile.fromEnsureUser('u1', {
        'referralCode': 'ABCD2345',
        'pro': {
          'active': true,
          'source': 'revenuecat',
          'until': '2027-01-01T00:00:00Z',
        },
      });
      expect(store.referralProUntil, isNull);
    });

    test('同じ値なら等しい', () {
      const a = UserProfile(uid: 'u', nickname: 'n');
      const b = UserProfile(uid: 'u', nickname: 'n');
      expect(a, b);
    });
  });

  group('normalizeFirestoreValue', () {
    test('入れ子の Map / List をそろえ、キーを文字列にする', () {
      final out = normalizeFirestoreValue({
        1: [
          {'a': 1},
          2,
        ],
        'b': {'c': 'd'},
      });
      expect(out, {
        '1': [
          {'a': 1},
          2,
        ],
        'b': {'c': 'd'},
      });
    });

    test('Map でないものは空の Map', () {
      expect(normalizeFirestoreMap(null), isEmpty);
      expect(normalizeFirestoreMap([1]), isEmpty);
    });

    test('parseDateTime は DateTime・文字列・ミリ秒を読む', () {
      final at = DateTime.utc(2026, 10, 21);
      expect(parseDateTime(at), at);
      expect(parseDateTime('2026-10-21T00:00:00Z'), at);
      expect(parseDateTime(at.millisecondsSinceEpoch), at.toLocal());
      expect(parseDateTime('not a date'), isNull);
      expect(parseDateTime(null), isNull);
    });
  });

  group('BackendException', () {
    test('通信の失敗は再試行してよく、入力の誤りや上限は再試行しない', () {
      for (final code in const [
        'unavailable',
        'deadline-exceeded',
        'unauthenticated',
        'internal',
      ]) {
        expect(BackendException(code: code).isRetryable, isTrue, reason: code);
      }
      for (final code in const [
        'invalid-argument',
        'resource-exhausted',
        'permission-denied',
        'not-found',
      ]) {
        expect(BackendException(code: code).isRetryable, isFalse, reason: code);
      }
    });
  });

  group('providers', () {
    test('Firebase が無効（テストの既定）なら uid もプロフィールも null', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(await container.read(authUidProvider.future), isNull);
      expect(await container.read(userProfileProvider.future), isNull);
      expect(container.read(backendClientProvider).available, isFalse);
      await expectLater(
        container.read(backendClientProvider).call('ensureUser'),
        throwsA(isA<BackendException>()),
      );
    });

    test('サインインできなければ null のまま（オフラインでも動く）', () async {
      final service = FakeAccountService(uid: null);
      final container = ProviderContainer(
        overrides: [accountServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      expect(await container.read(authUidProvider.future), isNull);
      expect(await container.read(userProfileProvider.future), isNull);
      expect(service.ensureCalls, 0);
    });

    test('サインイン → ensureUser の結果が最初の値、そのあと users/{uid} の購読', () async {
      const seeded = UserProfile(uid: 'u1', referralCode: 'ABCD2345');
      final service = FakeAccountService(uid: 'u1', profile: seeded);
      final container = ProviderContainer(
        overrides: [accountServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);

      final seen = <UserProfile?>[];
      container.listen<AsyncValue<UserProfile?>>(
        userProfileProvider,
        (_, next) => seen.add(next.valueOrNull),
        fireImmediately: false,
      );
      expect(await container.read(authUidProvider.future), 'u1');
      await container.read(userProfileProvider.future);
      expect(service.ensureCalls, 1);
      expect(container.read(userProfileProvider).value, seeded);
      // 購読が始まるのを待つ（broadcast は購読前のイベントを捨てる）。
      await Future<void>.delayed(const Duration(milliseconds: 10));

      service.controller.add(
        const UserProfile(
          uid: 'u1',
          nickname: 'まじゃおう',
          referralCode: 'ABCD2345',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(userProfileProvider).value?.nickname, 'まじゃおう');
      expect(seen.whereType<UserProfile>(), isNotEmpty);
    });

    test('users/{uid} の購読が失敗しても、それまでの値を残す', () async {
      const seeded = UserProfile(uid: 'u1', referralCode: 'ABCD2345');
      final service = FakeAccountService(uid: 'u1', profile: seeded);
      final container = ProviderContainer(
        overrides: [accountServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      await container.read(userProfileProvider.future);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.controller.addError(StateError('offline'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(userProfileProvider).hasError, isFalse);
      expect(container.read(userProfileProvider).value, seeded);
    });
  });
}
