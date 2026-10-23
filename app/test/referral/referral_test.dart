import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/settings_strings.dart';
import 'package:nanikiru_cam/referral/referral_section.dart';
import 'package:nanikiru_cam/referral/referral_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

class _FakeReferralBackend implements ReferralBackend {
  final List<String> codes = [];
  Object? error;
  DateTime proUntil = DateTime.utc(2026, 10, 28, 12);

  @override
  Future<ReferralGrant> apply(String code) async {
    codes.add(code);
    final e = error;
    if (e != null) throw e;
    return ReferralGrant(proUntil: proUntil, referrerRewarded: true);
  }
}

class _FakeBackendClient implements BackendClient {
  _FakeBackendClient({this.available = true});

  @override
  final bool available;
  Object? error;
  Map<String, Object?> response = const {};
  final List<(String, Map<String, Object?>)> calls = [];

  @override
  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    calls.add((name, data));
    final e = error;
    if (e != null) throw e;
    return response;
  }
}

void main() {
  late _FakeReferralBackend backend;
  late RecordingAnalytics analytics;
  late FakeClock clock;
  String? shared;
  final shares = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _FakeReferralBackend();
    analytics = RecordingAnalytics();
    clock = FakeClock(DateTime.utc(2026, 10, 21, 12));
    shared = null;
    shares.clear();
  });

  ProviderContainer container({
    String? myCode,
    DateTime? serverReferralUntil,
    bool signedIn = true,
    Map<String, Object> prefs = const {},
  }) {
    SharedPreferences.setMockInitialValues(prefs);
    final c = ProviderContainer(
      overrides: [
        referralBackendProvider.overrideWithValue(backend),
        analyticsSinkProvider.overrideWithValue(analytics.call),
        clockProvider.overrideWithValue(clock.call),
        sharedPreferencesProvider.overrideWith(
          (ref) => SharedPreferences.getInstance(),
        ),
        authUidProvider.overrideWith((ref) async => signedIn ? 'uid-1' : null),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(
            signedIn
                ? UserProfile(
                    uid: 'uid-1',
                    referralCode: myCode,
                    referralProUntil: serverReferralUntil,
                  )
                : null,
          ),
        ),
        referralShareProvider.overrideWithValue((text) async {
          shared = text;
          shares.add(text);
        }),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('コードの整え方', () {
    test('大文字小文字・空白・ハイフンのゆれを直す', () {
      expect(normalizeReferralCode('abcd 2345'), 'ABCD2345');
      expect(normalizeReferralCode('abcd-2345'), 'ABCD2345');
      expect(normalizeReferralCode(' ABCD2345 '), 'ABCD2345');
    });

    test('形式が違うものは null（I O 0 1 は使えない、8 文字）', () {
      expect(normalizeReferralCode(null), isNull);
      expect(normalizeReferralCode(''), isNull);
      expect(normalizeReferralCode('ABCD234'), isNull);
      expect(normalizeReferralCode('ABCD23456'), isNull);
      expect(normalizeReferralCode('ABCD2I45'), isNull);
      expect(normalizeReferralCode('ABCD2045'), isNull);
    });
  });

  group('callable applyReferral のエラー', () {
    test('API.md 1.4 の表のとおりに分類する', () {
      ReferralFailure f(String code, [String? reason]) => referralFailureOf(
        BackendException(code: code, reason: reason),
      );
      expect(f('invalid-argument', 'invalid_code'), ReferralFailure.invalidCode);
      expect(f('not-found', 'invalid_code'), ReferralFailure.invalidCode);
      expect(f('already-exists', 'already_applied'), ReferralFailure.alreadyApplied);
      expect(f('failed-precondition', 'self_referral'), ReferralFailure.selfReferral);
      expect(f('failed-precondition', 'no_user'), ReferralFailure.noUser);
      expect(f('unauthenticated', 'sign_in_failed'), ReferralFailure.noUser);
      expect(f('unavailable'), ReferralFailure.network);
      expect(f('deadline-exceeded'), ReferralFailure.network);
      expect(f('unavailable', 'firebase_disabled'), ReferralFailure.unavailable);
      expect(f('internal'), ReferralFailure.unknown);
    });

    test('CallableReferralBackend: code を渡して proUntil を読む', () async {
      final client = _FakeBackendClient()
        ..response = {
          'applied': true,
          'proUntil': '2026-10-28T12:00:00.000Z',
          'referrerRewarded': true,
        };
      final grant = await CallableReferralBackend(client).apply('ABCD2345');
      expect(client.calls.single.$1, 'applyReferral');
      expect(client.calls.single.$2, {'code': 'ABCD2345'});
      expect(grant.proUntil, DateTime.utc(2026, 10, 28, 12));
      expect(grant.referrerRewarded, isTrue);
    });

    test('CallableReferralBackend: サーバーのエラーを ReferralException にする', () async {
      final client = _FakeBackendClient()
        ..error = const BackendException(
          code: 'already-exists',
          reason: 'already_applied',
        );
      await expectLater(
        CallableReferralBackend(client).apply('ABCD2345'),
        throwsA(
          isA<ReferralException>().having(
            (e) => e.failure,
            'failure',
            ReferralFailure.alreadyApplied,
          ),
        ),
      );
    });

    test('CallableReferralBackend: Firebase 無効なら呼ばずに unavailable', () async {
      final client = _FakeBackendClient(available: false);
      await expectLater(
        CallableReferralBackend(client).apply('ABCD2345'),
        throwsA(
          isA<ReferralException>().having(
            (e) => e.failure,
            'failure',
            ReferralFailure.unavailable,
          ),
        ),
      );
      expect(client.calls, isEmpty);
    });
  });

  group('招待コードの適用', () {
    test('成功したら referral_applied を記録し、特典の期限と使ったコードを保存する', () async {
      final c = container(myCode: 'MYCADE22');
      final result = await c.read(referralProvider.notifier).apply('abcd-2345');
      expect(result.ok, isTrue);
      expect(result.grant!.proUntil, DateTime.utc(2026, 10, 28, 12));
      expect(backend.codes, ['ABCD2345']);
      expect(analytics.names, [AnalyticsEvent.referralApplied]);

      final state = c.read(referralProvider);
      expect(state.appliedCode, 'ABCD2345');
      expect(state.proUntil, DateTime.utc(2026, 10, 28, 12));

      await pumpEventQueue();
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString(ReferralNotifier.preferenceKey)!) as Map;
      expect(saved['appliedCode'], 'ABCD2345');
    });

    test('使った直後からサーバーの値が届くまで、控えの期限で Pro にできる', () async {
      final c = container();
      expect(c.read(referralProUntilProvider), isNull);
      await c.read(referralProvider.notifier).apply('ABCD2345');
      expect(c.read(referralProUntilProvider), DateTime.utc(2026, 10, 28, 12));
    });

    test('サーバーの期限が遅ければそちらを使う', () async {
      final c = container(serverReferralUntil: DateTime.utc(2026, 11, 5));
      c.read(userProfileProvider);
      await pumpEventQueue();
      await c.read(referralProvider.notifier).apply('ABCD2345');
      expect(c.read(referralProUntilProvider), DateTime.utc(2026, 11, 5));
    });

    test('形式が違えば通信せずに invalidCode', () async {
      final c = container();
      final result = await c.read(referralProvider.notifier).apply('12');
      expect(result.failure, ReferralFailure.invalidCode);
      expect(backend.codes, isEmpty);
    });

    test('自分のコードは通信せずに selfReferral', () async {
      final c = container(myCode: 'MYCADE22');
      c.read(userProfileProvider);
      await pumpEventQueue();
      final result = await c.read(referralProvider.notifier).apply('mycade22');
      expect(result.failure, ReferralFailure.selfReferral);
      expect(backend.codes, isEmpty);
    });

    test('1 人 1 回: 使用済みなら通信せずに alreadyApplied', () async {
      final c = container();
      await c.read(referralProvider.notifier).apply('ABCD2345');
      final second = await c.read(referralProvider.notifier).apply('EFGH6789');
      expect(second.failure, ReferralFailure.alreadyApplied);
      expect(backend.codes, ['ABCD2345']);
    });

    test('サーバーのエラーは理由つきで返し、記録も保存もしない', () async {
      final c = container();
      backend.error = const ReferralException(ReferralFailure.invalidCode);
      final result = await c.read(referralProvider.notifier).apply('ABCD2345');
      expect(result.failure, ReferralFailure.invalidCode);
      expect(c.read(referralProvider).appliedCode, isNull);
      expect(analytics.events, isEmpty);
    });

    test('自分のコードは users/{uid} から控え、オフラインでも見せられる', () async {
      final c = container(myCode: 'MYCADE22');
      c.read(myReferralCodeProvider);
      await pumpEventQueue();
      expect(c.read(myReferralCodeProvider), 'MYCADE22');
      expect(c.read(referralProvider).myCode, 'MYCADE22');

      final prefs = await SharedPreferences.getInstance();
      final offline = container(
        signedIn: false,
        prefs: {
          ReferralNotifier.preferenceKey: prefs.getString(
            ReferralNotifier.preferenceKey,
          )!,
        },
      );
      offline.read(referralProvider);
      await pumpEventQueue();
      expect(offline.read(myReferralCodeProvider), 'MYCADE22');
    });
  });

  group('リンクで届いたコードの自動適用', () {
    test('サインイン済みなら自動で使い、保留を消して結果を通知する', () async {
      final c = container();
      c.read(authUidProvider);
      await pumpEventQueue();
      c.read(referralAutoApplyProvider);
      c.read(pendingReferralCodeProvider.notifier).set('ABCD2345');
      await pumpEventQueue();
      expect(backend.codes, ['ABCD2345']);
      expect(c.read(pendingReferralCodeProvider), isNull);
      expect(c.read(referralAutoApplyResultProvider)!.ok, isTrue);
    });

    test('通信できないときは保留を残して、あとで再試行できる', () async {
      final c = container();
      c.read(authUidProvider);
      await pumpEventQueue();
      backend.error = const ReferralException(ReferralFailure.network);
      final applier = c.read(referralAutoApplyProvider);
      c.read(pendingReferralCodeProvider.notifier).set('ABCD2345');
      await pumpEventQueue();
      expect(c.read(pendingReferralCodeProvider), 'ABCD2345');
      expect(c.read(referralAutoApplyResultProvider), isNull);

      backend.error = null;
      await applier.run();
      expect(c.read(pendingReferralCodeProvider), isNull);
      expect(c.read(referralAutoApplyResultProvider)!.ok, isTrue);
    });

    test('存在しないコード・自分のコードは保留を捨てる', () async {
      final c = container();
      c.read(authUidProvider);
      await pumpEventQueue();
      backend.error = const ReferralException(ReferralFailure.invalidCode);
      c.read(referralAutoApplyProvider);
      c.read(pendingReferralCodeProvider.notifier).set('ABCD2345');
      await pumpEventQueue();
      expect(c.read(pendingReferralCodeProvider), isNull);
      expect(
        c.read(referralAutoApplyResultProvider)!.failure,
        ReferralFailure.invalidCode,
      );
    });

    test('サインインできていない間は何もしない', () async {
      final c = container(signedIn: false);
      c.read(authUidProvider);
      await pumpEventQueue();
      c.read(referralAutoApplyProvider);
      c.read(pendingReferralCodeProvider.notifier).set('ABCD2345');
      await pumpEventQueue();
      expect(backend.codes, isEmpty);
      expect(c.read(pendingReferralCodeProvider), 'ABCD2345');
    });
  });

  group('設定の「招待コード」', () {
    Future<ProviderContainer> pumpSection(
      WidgetTester tester, {
      String? myCode = 'MYCADE22',
      String? pending,
      Map<String, Object> prefs = const {},
    }) async {
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = container(
        myCode: myCode,
        prefs: {
          PendingReferralCode.preferenceKey: ?pending,
          ...prefs,
        },
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: const MaterialApp(
            locale: Locale('ja'),
            supportedLocales: [Locale('ja'), Locale('en')],
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: SingleChildScrollView(child: ReferralSection())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('自分のコードを表示し、コピーと共有ができる', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpSection(tester);
      expect(find.text('MYCADE22'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('referral-copy')));
      await tester.pump();
      expect(copied, 'MYCADE22');
      expect(find.text('コピーしました'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('referral-share')));
      await tester.pump();
      expect(shared, contains('MYCADE22'));
      expect(shared, contains(AppConfig.referralUrl('MYCADE22')));
      expect(shares, hasLength(1));
    });

    testWidgets('コードがまだ無いときは準備中の案内', (tester) async {
      await pumpSection(tester, myCode: null);
      expect(find.byKey(const ValueKey('referral-code')), findsNothing);
      expect(find.byKey(const ValueKey('referral-code-unavailable')), findsOneWidget);
    });

    testWidgets('友だちのコードを入力して使うと、期限つきのメッセージが出る', (tester) async {
      await pumpSection(tester);
      await tester.enterText(
        find.byKey(const ValueKey('referral-input')),
        'abcd-2345',
      );
      await tester.tap(find.byKey(const ValueKey('referral-apply')));
      await tester.pumpAndSettle();
      expect(backend.codes, ['ABCD2345']);
      expect(
        find.text('招待コードを使いました。Pro が 2026-10-28 まで有効です。'),
        findsOneWidget,
      );
      // 使用済みになると入力欄は出さない。
      expect(find.byKey(const ValueKey('referral-input')), findsNothing);
      expect(find.byKey(const ValueKey('referral-already-applied')), findsOneWidget);
    });

    testWidgets('エラーは日本語の理由で出す', (tester) async {
      await pumpSection(tester);
      backend.error = const ReferralException(ReferralFailure.alreadyApplied);
      await tester.enterText(
        find.byKey(const ValueKey('referral-input')),
        'ABCD2345',
      );
      await tester.tap(find.byKey(const ValueKey('referral-apply')));
      await tester.pumpAndSettle();
      expect(
        find.text('招待コードは 1 人 1 回までです。すでに使用済みです。'),
        findsOneWidget,
      );
    });

    testWidgets('形式が違うコードは通信せずに案内する', (tester) async {
      await pumpSection(tester);
      await tester.enterText(find.byKey(const ValueKey('referral-input')), 'xx');
      await tester.tap(find.byKey(const ValueKey('referral-apply')));
      await tester.pumpAndSettle();
      expect(backend.codes, isEmpty);
      expect(find.textContaining('コードが正しくありません'), findsOneWidget);
    });

    testWidgets('リンクから届いて保留中のコードを入力欄に入れておく', (tester) async {
      await pumpSection(tester, pending: 'EFGH6789');
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('referral-input')),
      );
      expect(field.controller!.text, 'EFGH6789');
    });
  });

  test('全てのエラー理由に日本語・英語の文言がある', () {
    for (final failure in ReferralFailure.values) {
      expect(const SettingsStrings(AppLang.ja).referralFailure(failure), isNotEmpty);
      expect(const SettingsStrings(AppLang.en).referralFailure(failure), isNotEmpty);
    }
  });
}
