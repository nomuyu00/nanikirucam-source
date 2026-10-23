import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:nanikiru_cam/share/sharing_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../problems/fakes.dart';

class _Source implements DeepLinkSource {
  final controller = StreamController<Uri>.broadcast();

  @override
  Stream<Uri> get links => controller.stream;
}

class _Referrer implements InstallReferrerSource {
  _Referrer(this.value);

  final String? value;
  int reads = 0;

  @override
  Future<String?> readReferrer() async {
    reads++;
    return value;
  }
}

const host = 'nanikiru-cam.web.app';

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final source = _Source();
  final repository = FakeProblemRepository();
  final account = FakeAccountService();
  final backend = FakeBackendClient();
  final store = MemoryQueueStore();
  final files = MemoryCardFiles();
  final pushed = <(String, Object?)>[];
  late final PublishService service = PublishService(
    backend: backend,
    uploader: FakeCardUploader(),
    store: store,
    files: files,
  );
  late ProviderContainer container;

  Future<void> pump({InstallReferrerSource? referrer}) async {
    pushed.clear();
    final key = UniqueKey();
    await tester.pumpWidget(
      ProviderScope(
        key: key,
        overrides: [
          deepLinkSourceProvider.overrideWithValue(source),
          installReferrerSourceProvider.overrideWithValue(
            referrer ?? _Referrer(null),
          ),
          problemRepositoryProvider.overrideWithValue(repository),
          accountServiceProvider.overrideWithValue(account),
          publishServiceProvider.overrideWithValue(service),
          appAnalyticsProvider.overrideWith((ref) => AppAnalytics()),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: testLocalizationsDelegates,
          navigatorKey: appNavigatorKey,
          builder: (context, child) =>
              SharingHost(child: child ?? const SizedBox.shrink()),
          onGenerateRoute: (settings) {
            if (settings.name != '/') {
              pushed.add((settings.name ?? '', settings.arguments));
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: Text('route:${settings.name}')),
            );
          },
        ),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> link(String url) async {
    source.controller.add(Uri.parse(url));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('/p/{id} は問題を読み込んで Quiz を開く（problemId つき）', (tester) async {
    final h = _Harness(tester);
    final problem = sampleProblem();
    h.repository.problems['AbC12345'] = problem;
    await h.pump();

    await h.link('https://$host/p/AbC12345');

    expect(h.repository.fetchedProblemIds, ['AbC12345']);
    final (name, args) = h.pushed.single;
    expect(name, Routes.quiz);
    final quiz = args! as QuizArgs;
    expect(quiz.problemId, 'AbC12345');
    expect(quiz.input, problem.input);
    expect(quiz.timed, isFalse);
    expect(find.text('route:${Routes.quiz}'), findsOneWidget);
  });

  testWidgets('ブロック中の出題者の問題はリンクから開かず、解除して開く導線を出す', (tester) async {
    SharedPreferences.setMockInitialValues({
      BlockedAuthorsNotifier.preferenceKey:
          '[{"uid":"bad-1","nickname":"迷惑さん","blockedAt":"2026-10-20T03:00:00.000Z"}]',
    });
    final h = _Harness(tester);
    h.repository.problems['AbC12345'] = sampleProblem(authorUid: 'bad-1');
    await h.pump();

    await h.link('https://$host/p/AbC12345');
    expect(h.pushed, isEmpty, reason: '開かない');
    expect(find.text('ブロック中の出題者の問題です'), findsOneWidget);
    expect(h.container.read(blockedAuthorsProvider).isBlocked('bad-1'), isTrue);

    await tester.tap(find.text('解除して開く'));
    await tester.pumpAndSettle();
    expect(
      h.container.read(blockedAuthorsProvider).isBlocked('bad-1'),
      isFalse,
    );
    final (name, args) = h.pushed.single;
    expect(name, Routes.quiz);
    expect((args! as QuizArgs).problemId, 'AbC12345');
  });

  testWidgets('別の出題者の問題は、ブロックがあっても開く', (tester) async {
    SharedPreferences.setMockInitialValues({
      BlockedAuthorsNotifier.preferenceKey:
          '[{"uid":"bad-1","nickname":"","blockedAt":"2026-10-20T03:00:00.000Z"}]',
    });
    final h = _Harness(tester);
    h.repository.problems['AbC12345'] = sampleProblem(authorUid: 'good-1');
    await h.pump();
    await h.link('https://$host/p/AbC12345');
    expect(h.pushed.single.$1, Routes.quiz);
  });

  testWidgets('見つからない・非表示の問題は遷移せずメッセージ', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    await h.link('https://$host/p/Missing1');
    expect(h.pushed, isEmpty);
    expect(find.textContaining('この問題は見つかりませんでした'), findsOneWidget);
  });

  testWidgets('読み込めないとき（オフライン）はそのメッセージ', (tester) async {
    final h = _Harness(tester);
    h.repository.error = const BackendException(code: 'unavailable');
    await h.pump();
    await h.link('https://$host/p/AbC12345');
    expect(h.pushed, isEmpty);
    expect(find.textContaining('問題を読み込めませんでした'), findsOneWidget);
  });

  testWidgets('/r/{code} は紹介コードを保留する（画面は開かない）', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    await h.link('https://$host/r/abcd-2345');
    expect(h.container.read(pendingReferralCodeProvider), 'ABCD2345');
    expect(h.pushed, isEmpty);
    expect(h.repository.fetchedProblemIds, isEmpty);
  });

  testWidgets('/p/{id}?ref= は問題を開き、紹介コードも保留する', (tester) async {
    final h = _Harness(tester);
    h.repository.problems['AbC12345'] = sampleProblem();
    await h.pump();
    await h.link('https://$host/p/AbC12345?ref=WXYZ2345');
    expect(h.container.read(pendingReferralCodeProvider), 'WXYZ2345');
    expect(h.pushed.single.$1, Routes.quiz);
  });

  testWidgets('アプリのリンクでなければ何もしない', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    await h.link('https://example.com/p/AbC12345');
    await h.link('https://$host/terms');
    expect(h.pushed, isEmpty);
    expect(h.repository.fetchedProblemIds, isEmpty);
  });

  group('Android の Install Referrer', () {
    testWidgets('初回起動で pid と ref を読んで、その問題を開き、紹介コードを保留する', (tester) async {
      final h = _Harness(tester);
      h.repository.problems['AbC12345'] = sampleProblem();
      final referrer = _Referrer(
        'utm_source=share&utm_campaign=problem&pid=AbC12345&ref=ABCD2345',
      );
      await h.pump(referrer: referrer);
      await tester.pumpAndSettle();
      expect(referrer.reads, 1);
      expect(h.pushed.single.$1, Routes.quiz);
      expect((h.pushed.single.$2! as QuizArgs).problemId, 'AbC12345');
      expect(h.container.read(pendingReferralCodeProvider), 'ABCD2345');

      // 2 回目の起動では読まない。
      await h.pump(referrer: referrer);
      await tester.pumpAndSettle();
      expect(referrer.reads, 1);
      expect(h.pushed, isEmpty);
    });

    testWidgets('referrer が無ければ何も開かない', (tester) async {
      final h = _Harness(tester);
      final referrer = _Referrer(null);
      await h.pump(referrer: referrer);
      await tester.pumpAndSettle();
      expect(referrer.reads, 1);
      expect(h.pushed, isEmpty);
    });
  });

  group('起動・復帰時の処理', () {
    Future<void> enqueue(_Harness h) async {
      final hand = sampleHand().normalized();
      await h.service.enqueue(
        PublishRequest(
          input: hand,
          answer: PublishedAnswer.fromReport(analyzeHand(hand), hand),
        ),
      );
    }

    testWidgets('起動時に公開待ちを再送する', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await enqueue(h);
      await h.pump();
      await tester.pumpAndSettle();
      expect(
        h.backend.calls.where((c) => c.$1 == 'publishProblem'),
        hasLength(1),
      );
      expect(h.store.jobs, isEmpty);
    });

    testWidgets('アプリ復帰時にも再送する（オフラインで残っていた分）', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async =>
          throw const BackendException(code: 'unavailable');
      await enqueue(h);
      await h.pump();
      await tester.pumpAndSettle();
      expect(h.store.jobs, hasLength(1));

      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.store.jobs, isEmpty);
    });

    testWidgets('サインインできていなければ復帰時にやり直す', (tester) async {
      final h = _Harness(tester);
      await h.pump();
      await tester.pumpAndSettle();
      final before = h.account.signInCalls;
      expect(before, greaterThan(0));

      h.account.uid = 'u1';
      h.account.profile = const UserProfile(
        uid: 'u1',
        referralCode: 'ABCD2345',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.account.signInCalls, greaterThan(before));
      expect(h.container.read(authUidProvider).valueOrNull, 'u1');
      expect(
        h.container.read(userProfileProvider).valueOrNull?.referralCode,
        'ABCD2345',
      );
    });

    testWidgets('起動直後にプロフィールの購読を始める（匿名サインイン → ensureUser）', (tester) async {
      final h = _Harness(tester);
      h.account.uid = 'u1';
      h.account.profile = const UserProfile(
        uid: 'u1',
        referralCode: 'ABCD2345',
      );
      await h.pump();
      await tester.pumpAndSettle();
      expect(h.account.ensureCalls, 1);
    });
  });
}
