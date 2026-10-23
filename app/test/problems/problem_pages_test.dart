import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart'
    show DailyHand, DailyProblemGenerator;
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/my_problems_page.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/problems/report_sheet.dart';
import 'package:nanikiru_cam/problems/today_page.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const today = '2026-10-21';

/// 画面を開いたときに押された遷移を記録する。
class PageNav {
  final pushed = <(String, Object?)>[];

  Route<dynamic>? generate(RouteSettings settings) {
    pushed.add((settings.name ?? '', settings.arguments));
    return MaterialPageRoute<void>(
      settings: settings,
      builder: (_) => Scaffold(body: Text('route:${settings.name}')),
    );
  }
}

Future<PageNav> pumpPage(
  WidgetTester tester,
  Widget page, {
  required ProblemRepository repository,
  bool pro = false,
  String? uid = 'me',
  Locale locale = const Locale('ja'),
  List<Override> overrides = const [],
  Map<String, Object> preferences = const {},
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues(preferences);
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final nav = PageNav();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        problemRepositoryProvider.overrideWithValue(repository),
        todayDateProvider.overrideWithValue(today),
        authUidProvider.overrideWith((ref) async => uid),
        appAnalyticsProvider.overrideWith((ref) => AppAnalytics()),
        entitlementsProvider.overrideWith(
          (ref) => pro
              ? const EntitlementState(
                  pro: true,
                  source: EntitlementSource.store,
                )
              : EntitlementState.free,
        ),
        ...overrides,
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: testLocalizationsDelegates,
        home: page,
        onGenerateRoute: nav.generate,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return nav;
}

void main() {
  late FakeProblemRepository repository;

  setUp(() {
    repository = FakeProblemRepository();
  });

  group('TodayPage（今日の問題）', () {
    final official = sampleProblem(
      id: 'OFFICIAL',
      nickname: '運営',
      authorUid: 'official',
      stats: const ProblemStats(total: 120, correct: 54),
    );
    final pickA = sampleProblem(
      id: 'PICKAAAA',
      nickname: 'まじゃおう',
      stats: const ProblemStats(total: 4, correct: 1),
    );
    final pickB = sampleProblem(
      id: 'PICKBBBB',
      nickname: '',
      stats: const ProblemStats(),
    );

    setUp(() {
      repository.daily[today] = DailyProblems(
        date: today,
        official: official,
        picks: [pickA, pickB],
      );
    });

    testWidgets('公式 1 問とユーザー投稿 2 問を、出題者・回答数・正解率つきで見せる', (tester) async {
      await pumpPage(tester, const TodayPage(), repository: repository);
      expect(find.text('10月21日の問題'), findsOneWidget);
      expect(find.text('公式'), findsOneWidget);
      expect(find.text('みんなの問題'), findsNWidgets(2));
      expect(find.text('出題: 運営'), findsOneWidget);
      expect(find.text('出題: まじゃおう'), findsOneWidget);
      expect(find.text('出題: 匿名'), findsOneWidget);
      expect(find.text('120人が回答 ・ 正解率 45%'), findsOneWidget);
      expect(find.text('4人が回答 ・ 正解率 25%'), findsOneWidget);
      expect(find.text('まだ回答がありません'), findsOneWidget);
      // 答えは見えない。
      expect(find.textContaining('正解:'), findsNothing);
      expect(repository.fetchedDates, [today]);
    });

    testWidgets('問題をタップすると制限時間つきで Quiz へ（problemId つき）', (tester) async {
      final nav = await pumpPage(
        tester,
        const TodayPage(),
        repository: repository,
      );
      await tester.tap(find.byKey(const ValueKey('today-problem-PICKAAAA')));
      await tester.pumpAndSettle();
      final (name, args) = nav.pushed.last;
      expect(name, Routes.quiz);
      final quiz = args! as QuizArgs;
      expect(quiz.problemId, 'PICKAAAA');
      expect(quiz.timed, isTrue);
      expect(quiz.input, pickA.input);
      expect(quiz.input.isFourteen, isTrue);
    });

    testWidgets('今日の問題がまだなければ準備中の表示', (tester) async {
      repository.daily.clear();
      await pumpPage(tester, const TodayPage(), repository: repository);
      expect(find.textContaining('今日の問題はまだ準備中'), findsOneWidget);
    });

    testWidgets('読み込めなければ再読み込みできる', (tester) async {
      repository.error = const BackendException(code: 'unavailable');
      await pumpPage(tester, const TodayPage(), repository: repository);
      expect(find.textContaining('読み込めませんでした'), findsOneWidget);
      repository.error = null;
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.text('公式'), findsOneWidget);
    });

    testWidgets('Firebase が使えないときは準備中（何も読みに行かない）', (tester) async {
      repository.isAvailable = false;
      await pumpPage(tester, const TodayPage(), repository: repository);
      expect(find.text('オンライン機能は準備中です'), findsOneWidget);
      expect(repository.fetchedDates, isEmpty);
    });

    testWidgets('無料: 前の日へは Pro の案内（課金画面）。もっと解くはロック', (tester) async {
      final nav = await pumpPage(
        tester,
        const TodayPage(),
        repository: repository,
      );
      expect(
        find.byKey(const ValueKey('today-popular-locked')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('today-prev')));
      await tester.pumpAndSettle();
      final (name, args) = nav.pushed.last;
      expect(name, Routes.paywall);
      expect((args! as PaywallArgs).trigger, PaywallTrigger.todayLimit);
      expect(repository.fetchedDates, [today], reason: '過去の日は読まない');
    });

    testWidgets('Pro: 前の日の問題をさかのぼれる。今日より先へは進めない', (tester) async {
      repository.daily['2026-10-20'] = DailyProblems(
        date: '2026-10-20',
        official: sampleProblem(id: 'YESTERDY', nickname: '昨日の人'),
      );
      repository.popular = [sampleProblem(id: 'POPULAR1', nickname: '人気')];
      await pumpPage(
        tester,
        const TodayPage(),
        repository: repository,
        pro: true,
      );
      expect(find.byKey(const ValueKey('today-popular')), findsOneWidget);
      expect(find.text('出題: 人気'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('today-next')))
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('today-prev')));
      await tester.pumpAndSettle();
      expect(find.text('10月20日の問題'), findsOneWidget);
      expect(find.text('出題: 昨日の人'), findsOneWidget);

      // 2 日前は問題なし。
      await tester.tap(find.byKey(const ValueKey('today-prev')));
      await tester.pumpAndSettle();
      expect(find.text('この日の問題はありません'), findsOneWidget);

      // 戻る。
      await tester.tap(find.byKey(const ValueKey('today-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-next')));
      await tester.pumpAndSettle();
      expect(find.text('10月21日の問題'), findsOneWidget);
      expect(find.text('公式'), findsOneWidget);
    });

    testWidgets('他人の問題は通報できる。自分の問題には通報メニューが出ない', (tester) async {
      repository.daily[today] = DailyProblems(
        date: today,
        official: official,
        picks: [sampleProblem(id: 'MINEAAAA', authorUid: 'me')],
      );
      await pumpPage(tester, const TodayPage(), repository: repository);
      expect(find.byKey(const ValueKey('today-menu-MINEAAAA')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('today-menu-OFFICIAL')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('この問題を通報'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('report-reason-wrongAnswer')));
      await tester.pumpAndSettle();
      expect(repository.reports, [
        ('OFFICIAL', ProblemReportReason.wrongAnswer),
      ]);
      expect(find.text('通報しました。ご協力ありがとうございます'), findsOneWidget);
    });

    testWidgets('英語表示', (tester) async {
      await pumpPage(
        tester,
        const TodayPage(),
        repository: repository,
        locale: const Locale('en'),
      );
      expect(find.text('Problems for 10/21'), findsOneWidget);
      expect(find.text('Official'), findsOneWidget);
      expect(find.text('120 answered ・ Solved by 45%'), findsOneWidget);
    });
  });

  group('TodayPage（端末内の今日の問題・サーバーなし）', () {
    final memo = <String, List<DailyHand>>{};
    late List<String> generated;
    Object? failure;
    Completer<List<DailyHand>>? pending;

    List<DailyHand> handsOf(String date) =>
        memo.putIfAbsent(date, () => DailyProblemGenerator().generate(date));

    LocalDailyProblemRepository localRepository() =>
        LocalDailyProblemRepository(
          generate: (date) async {
            generated.add(date);
            final wait = pending;
            if (wait != null) return wait.future;
            final error = failure;
            if (error != null) {
              failure = null;
              throw error;
            }
            return handsOf(date);
          },
        );

    String id(int n, [String date = today]) => 'daily-$date-$n';

    setUp(() {
      generated = [];
      failure = null;
      pending = null;
    });

    testWidgets('3 問を基本・標準・応用で見せる。出題者・回答数・通報・人気の問題は出さない', (tester) async {
      await pumpPage(tester, const TodayPage(), repository: localRepository());
      expect(find.text('10月21日の問題'), findsOneWidget);
      expect(find.text('基本'), findsOneWidget);
      expect(find.text('標準'), findsOneWidget);
      expect(find.text('応用'), findsOneWidget);
      expect(find.text('速さ・打点・バランスで答えが割れる手'), findsOneWidget);
      for (var n = 1; n <= 3; n++) {
        expect(find.byKey(ValueKey('today-problem-${id(n)}')), findsOneWidget);
        expect(find.byKey(ValueKey('today-menu-${id(n)}')), findsNothing);
        expect(find.byKey(ValueKey('problem-stats-${id(n)}')), findsNothing);
        expect(find.byKey(ValueKey('today-solved-${id(n)}')), findsNothing);
      }
      expect(find.textContaining('出題'), findsNothing);
      expect(find.text('公式'), findsNothing);
      expect(find.text('オンライン機能は準備中です'), findsNothing);
      expect(find.byKey(const ValueKey('today-popular-locked')), findsNothing);
      expect(find.byKey(const ValueKey('today-popular')), findsNothing);
      expect(find.text('0 / 3 問 解答済み'), findsOneWidget);
      expect(generated, [today]);
    });

    testWidgets('タップすると制限時間つきで Quiz へ（端末内の ID、出どころは today）', (tester) async {
      final nav = await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
      );
      await tester.tap(find.byKey(ValueKey('today-problem-${id(3)}')));
      await tester.pumpAndSettle();
      final (name, args) = nav.pushed.last;
      expect(name, Routes.quiz);
      final quiz = args! as QuizArgs;
      expect(quiz.problemId, id(3));
      expect(quiz.timed, isTrue);
      expect(quiz.source, 'today');
      expect(quiz.input.tiles, handsOf(today)[2].tiles);
      expect(quiz.input.isFourteen, isTrue);
    });

    testWidgets('解いた問題にはチェック。3 問とも解いたら達成の表示', (tester) async {
      await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
        preferences: {
          DailySolvedNotifier.preferenceKey: jsonEncode([
            id(2),
            id(1, '2026-10-20'),
          ]),
        },
      );
      expect(find.byKey(ValueKey('today-solved-${id(2)}')), findsOneWidget);
      expect(find.byKey(ValueKey('today-solved-${id(1)}')), findsNothing);
      expect(find.text('解答済み'), findsOneWidget);
      expect(find.text('1 / 3 問 解答済み'), findsOneWidget);
      expect(find.byKey(const ValueKey('today-all-solved')), findsNothing);
    });

    testWidgets('3 問とも解いていれば「すべて解きました」', (tester) async {
      await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
        preferences: {
          DailySolvedNotifier.preferenceKey: jsonEncode([id(1), id(2), id(3)]),
        },
      );
      expect(find.byKey(const ValueKey('today-all-solved')), findsOneWidget);
      expect(find.text('今日の 3 問をすべて解きました！'), findsOneWidget);
      expect(find.text('解答済み'), findsNWidgets(3));
    });

    testWidgets('無料: 前の日へは課金画面（前の日の問題は作らない）', (tester) async {
      final nav = await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
      );
      await tester.tap(find.byKey(const ValueKey('today-prev')));
      await tester.pumpAndSettle();
      final (name, args) = nav.pushed.last;
      expect(name, Routes.paywall);
      expect((args! as PaywallArgs).trigger, PaywallTrigger.todayLimit);
      expect(generated, [today]);
    });

    testWidgets('Pro: 前の日の 3 問も端末内で作って解ける', (tester) async {
      final nav = await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
        pro: true,
      );
      expect(find.byKey(const ValueKey('today-popular')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('today-prev')));
      await tester.pumpAndSettle();
      expect(find.text('10月20日の問題'), findsOneWidget);
      final yesterday = id(1, '2026-10-20');
      expect(find.byKey(ValueKey('today-problem-$yesterday')), findsOneWidget);
      expect(generated, [today, '2026-10-20']);

      await tester.tap(find.byKey(ValueKey('today-problem-$yesterday')));
      await tester.pumpAndSettle();
      final quiz = nav.pushed.last.$2! as QuizArgs;
      expect(quiz.problemId, yesterday);
      expect(quiz.input.tiles, handsOf('2026-10-20')[0].tiles);
    });

    testWidgets('作っている間は読み込み表示。作れなかったら再試行できる', (tester) async {
      pending = Completer<List<DailyHand>>();
      await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
        settle: false,
      );
      expect(find.text('問題を用意しています'), findsOneWidget);
      pending!.completeError(StateError('boom'));
      pending = null;
      await tester.pumpAndSettle();
      expect(find.text('問題を用意できませんでした。もう一度お試しください'), findsOneWidget);
      expect(find.textContaining('通信'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('today-retry')));
      await tester.pumpAndSettle();
      expect(find.text('基本'), findsOneWidget);
      expect(generated, [today, today]);
    });

    testWidgets('英語表示', (tester) async {
      await pumpPage(
        tester,
        const TodayPage(),
        repository: localRepository(),
        locale: const Locale('en'),
      );
      expect(find.text('Basic'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('0 of 3 solved'), findsOneWidget);
    });
  });

  group('通報シート', () {
    testWidgets('通報済み・自分の問題・失敗のメッセージ', (tester) async {
      Future<void> open(WidgetTester tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ja'),
            supportedLocales: supportedAppLocales,
            localizationsDelegates: testLocalizationsDelegates,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showReportProblemSheet(
                    context,
                    repository: repository,
                    problemId: 'AbC12345',
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('report-reason-spam')));
        await tester.pumpAndSettle();
      }

      repository.error = const BackendException(
        code: 'permission-denied',
        reason: 'own_problem',
      );
      await open(tester);
      expect(find.text('自分の問題は通報できません'), findsOneWidget);

      repository.error = const BackendException(code: 'unavailable');
      await open(tester);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('通報できませんでした'), findsOneWidget);
    });
  });

  group('MyProblemsPage（出題した問題）', () {
    testWidgets('自分の問題を回答数・正解率つきで見せる。10/50/100 人の到達と非表示', (tester) async {
      repository.mine = [
        sampleProblem(
          id: 'HUNDRED1',
          stats: const ProblemStats(total: 130, correct: 65),
          createdAt: DateTime(2026, 10, 21, 9, 5),
        ),
        sampleProblem(
          id: 'TENTEN01',
          stats: const ProblemStats(total: 12, correct: 3),
        ),
        sampleProblem(id: 'ZERO0001', stats: const ProblemStats()),
        sampleProblem(
          id: 'HIDDEN01',
          hidden: true,
          stats: const ProblemStats(total: 3, correct: 3),
        ),
      ];
      await pumpPage(tester, const MyProblemsPage(), repository: repository);
      expect(
        find.byKey(const ValueKey('problem-stats-HUNDRED1')),
        findsOneWidget,
      );
      expect(find.text('130人が回答 ・ 正解率 50%'), findsOneWidget);
      expect(find.text('12人が回答 ・ 正解率 25%'), findsOneWidget);
      expect(find.text('まだ回答がありません'), findsOneWidget);
      // 回答到達の表示。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('my-problem-HUNDRED1')),
          matching: find.text('100人が回答！もう一度シェアしよう'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('my-problem-TENTEN01')),
          matching: find.text('10人が回答！もう一度シェアしよう'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('my-problem-milestone-ZERO0001')),
        findsNothing,
      );
      // 非表示（通報）の問題はバッジと説明、共有ボタンなし。
      expect(find.text('非表示'), findsOneWidget);
      expect(find.text('通報により、他の人には表示されていません'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('my-problem-share-HIDDEN01')),
        findsNothing,
      );
      expect(find.text('10/21 09:05'), findsOneWidget);
    });

    testWidgets('「もう一度シェア」で問題カード（problemId つき）へ', (tester) async {
      repository.mine = [sampleProblem(id: 'TENTEN01')];
      final nav = await pumpPage(
        tester,
        const MyProblemsPage(),
        repository: repository,
      );
      await tester.tap(find.byKey(const ValueKey('my-problem-share-TENTEN01')));
      await tester.pumpAndSettle();
      final (name, args) = nav.pushed.last;
      expect(name, Routes.shareCard);
      final card = args! as ShareCardArgs;
      expect(card.kind, ShareCardKind.problem);
      expect(card.problemId, 'TENTEN01');
      expect(card.input, repository.mine.single.input);
    });

    testWidgets('まだ出題していなければ案内', (tester) async {
      await pumpPage(tester, const MyProblemsPage(), repository: repository);
      expect(find.textContaining('まだ出題していません'), findsOneWidget);
    });

    testWidgets('未サインインなら空（オフラインでも落ちない）', (tester) async {
      repository.mine = [sampleProblem()];
      await pumpPage(
        tester,
        const MyProblemsPage(),
        repository: repository,
        uid: null,
      );
      expect(find.textContaining('まだ出題していません'), findsOneWidget);
    });

    testWidgets('読み込めなければ再読み込みできる', (tester) async {
      repository.error = const BackendException(code: 'unavailable');
      repository.mine = [sampleProblem(id: 'TENTEN01')];
      await pumpPage(tester, const MyProblemsPage(), repository: repository);
      expect(find.textContaining('読み込めませんでした'), findsOneWidget);
      repository.error = null;
      await tester.tap(find.text('再読み込み'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my-problem-TENTEN01')), findsOneWidget);
    });

    testWidgets('公開待ち（オフラインで公開できなかった分）を見せる', (tester) async {
      final backend = FakeBackendClient()..isAvailable = false;
      final store = MemoryQueueStore();
      final files = MemoryCardFiles();
      final service = PublishService(
        backend: backend,
        uploader: FakeCardUploader(),
        store: store,
        files: files,
      );
      final hand = sampleHand().normalized();
      await service.enqueue(
        PublishRequest(
          input: hand,
          answer: PublishedAnswer.fromReport(analyzeHand(hand), hand),
        ),
      );
      await pumpPage(
        tester,
        const MyProblemsPage(),
        repository: repository,
        overrides: [publishServiceProvider.overrideWithValue(service)],
      );
      expect(find.byKey(const ValueKey('my-problems-pending')), findsOneWidget);
      expect(find.textContaining('公開待ち 1件'), findsOneWidget);
    });

    testWidgets('開いたとき、公開待ちを再試行して公開できたら一覧に出る', (tester) async {
      final backend = FakeBackendClient()
        ..handlers['publishProblem'] = (_) async =>
            publishResponse(id: 'RETRIED1');
      final service = PublishService(
        backend: backend,
        uploader: FakeCardUploader(),
        store: MemoryQueueStore(),
        files: MemoryCardFiles(),
      );
      final hand = sampleHand().normalized();
      await service.enqueue(
        PublishRequest(
          input: hand,
          answer: PublishedAnswer.fromReport(analyzeHand(hand), hand),
        ),
      );
      repository.mine = [sampleProblem(id: 'RETRIED1')];
      await pumpPage(
        tester,
        const MyProblemsPage(),
        repository: repository,
        overrides: [publishServiceProvider.overrideWithValue(service)],
      );
      expect(
        backend.calls.where((c) => c.$1 == 'publishProblem'),
        hasLength(1),
      );
      expect(find.byKey(const ValueKey('my-problems-pending')), findsNothing);
      expect(find.byKey(const ValueKey('my-problem-RETRIED1')), findsOneWidget);
    });
  });
}
