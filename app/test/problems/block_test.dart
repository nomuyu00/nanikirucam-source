// 出題者のブロック（App Store 審査ガイドライン 1.2: ユーザー生成コンテンツ）のテスト。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/blocked_authors_section.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_menu.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/problems/report_sheet.dart';
import 'package:nanikiru_cam/problems/today_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const today = '2026-10-21';
const blockedKey = BlockedAuthorsNotifier.preferenceKey;

String blockedJson(List<String> uids) =>
    '[${[for (final uid in uids) '{"uid":"$uid","nickname":"迷惑さん","blockedAt":"2026-10-20T03:00:00.000Z"}'].join(',')}]';

Future<ProviderContainer> pump(
  WidgetTester tester,
  Widget home, {
  required FakeProblemRepository repository,
  Map<String, Object> prefs = const {},
  String? uid = 'me',
  bool pro = false,
  Locale locale = const Locale('ja'),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
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
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: testLocalizationsDelegates,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  late FakeProblemRepository repository;

  setUp(() {
    repository = FakeProblemRepository();
  });

  group('Today: ブロック中の出題者の問題は一覧に出ない', () {
    final official = sampleProblem(
      id: 'OFFICIAL',
      authorUid: 'official',
      nickname: '運営',
    );
    final bad = sampleProblem(
      id: 'BADBADBA',
      authorUid: 'bad-1',
      nickname: '迷惑さん',
    );
    final good = sampleProblem(
      id: 'GOODGOOD',
      authorUid: 'good-1',
      nickname: 'まじゃおう',
    );

    setUp(() {
      repository.daily[today] = DailyProblems(
        date: today,
        official: official,
        picks: [bad, good],
      );
    });

    testWidgets('ブロック済みの出題者の問題だけが消える', (tester) async {
      await pump(
        tester,
        const TodayPage(),
        repository: repository,
        prefs: {
          blockedKey: blockedJson(['bad-1']),
        },
      );
      expect(key('today-problem-OFFICIAL'), findsOneWidget);
      expect(key('today-problem-GOODGOOD'), findsOneWidget);
      expect(key('today-problem-BADBADBA'), findsNothing);
    });

    testWidgets('公式の問題の出題者でもブロックすれば消える。全部消えたら案内', (tester) async {
      await pump(
        tester,
        const TodayPage(),
        repository: repository,
        prefs: {
          blockedKey: blockedJson(['official', 'bad-1', 'good-1']),
        },
      );
      expect(key('today-problem-OFFICIAL'), findsNothing);
      expect(find.text('ブロック中の出題者の問題は表示されません'), findsOneWidget);
      expect(find.textContaining('今日の問題はまだ準備中'), findsNothing);
    });

    testWidgets('「⋮」→「この出題者をブロック」→ 確認 → ブロックして一覧から消え、端末に保存', (tester) async {
      final container = await pump(
        tester,
        const TodayPage(),
        repository: repository,
      );
      expect(key('today-problem-BADBADBA'), findsOneWidget);

      await tester.tap(key('today-menu-BADBADBA'));
      await tester.pumpAndSettle();
      expect(key('problem-menu-report'), findsOneWidget);
      await tester.tap(key('problem-menu-block'));
      await tester.pumpAndSettle();

      // 確認ダイアログ。出題者名が出る。
      expect(find.text('この出題者をブロックしますか？'), findsOneWidget);
      expect(find.textContaining('「迷惑さん」の問題は'), findsOneWidget);
      await tester.tap(key('block-confirm-ok'));
      await tester.pumpAndSettle();

      expect(key('today-problem-BADBADBA'), findsNothing);
      expect(key('today-problem-GOODGOOD'), findsOneWidget);
      expect(find.text('ブロックしました。設定から解除できます'), findsOneWidget);
      expect(container.read(blockedAuthorsProvider).authors.map((a) => a.uid), [
        'bad-1',
      ]);
      expect(
        container.read(blockedAuthorsProvider).authors.single.nickname,
        '迷惑さん',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(blockedKey), contains('bad-1'));
      // 問題は読み直していない（端末内の非表示だけ）。サーバーへの通報もしていない。
      expect(repository.reports, isEmpty);
      expect(repository.fetchedProblemIds, isEmpty);
    });

    testWidgets('確認でやめればブロックしない', (tester) async {
      final container = await pump(
        tester,
        const TodayPage(),
        repository: repository,
      );
      await tester.tap(key('today-menu-BADBADBA'));
      await tester.pumpAndSettle();
      await tester.tap(key('problem-menu-block'));
      await tester.pumpAndSettle();
      await tester.tap(key('block-cancel'));
      await tester.pumpAndSettle();
      expect(key('today-problem-BADBADBA'), findsOneWidget);
      expect(container.read(blockedAuthorsProvider).authors, isEmpty);
    });

    testWidgets('自分の問題には「⋮」が出ない', (tester) async {
      repository.daily[today] = DailyProblems(
        date: today,
        picks: [sampleProblem(id: 'MINEAAAA', authorUid: 'me')],
      );
      await pump(tester, const TodayPage(), repository: repository);
      expect(key('today-menu-MINEAAAA'), findsNothing);
    });

    testWidgets('人気問題（Pro）もブロック中の出題者の問題を除く', (tester) async {
      repository.popular = [
        sampleProblem(id: 'POPBAD01', authorUid: 'bad-1', nickname: '迷惑さん'),
        sampleProblem(id: 'POPGOOD1', authorUid: 'good-1', nickname: 'まじゃおう'),
      ];
      await pump(
        tester,
        const TodayPage(),
        repository: repository,
        pro: true,
        prefs: {
          blockedKey: blockedJson(['bad-1']),
        },
      );
      expect(key('today-problem-POPGOOD1'), findsOneWidget);
      expect(key('today-problem-POPBAD01'), findsNothing);
    });

    testWidgets('英語表示', (tester) async {
      await pump(
        tester,
        const TodayPage(),
        repository: repository,
        locale: const Locale('en'),
      );
      await tester.tap(key('today-menu-BADBADBA'));
      await tester.pumpAndSettle();
      expect(find.text('Block this author'), findsOneWidget);
      await tester.tap(key('problem-menu-block'));
      await tester.pumpAndSettle();
      expect(find.text('Block this author?'), findsOneWidget);
      expect(find.textContaining('"迷惑さん"'), findsOneWidget);
    });
  });

  group('通報シートの「この出題者をブロック」（Result・Quiz のように問題 ID しか持たない画面）', () {
    Future<ProviderContainer> openSheet(
      WidgetTester tester, {
      String? uid = 'me',
      Map<String, Object> prefs = const {},
    }) async {
      final container = await pump(
        tester,
        Scaffold(
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
        repository: repository,
        uid: uid,
        prefs: prefs,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('理由の下にブロックの項目が並ぶ', (tester) async {
      await openSheet(tester);
      expect(key('report-reason-spam'), findsOneWidget);
      expect(key('report-block-author'), findsOneWidget);
    });

    testWidgets('問題を読み込んで出題者を確認 → ブロック', (tester) async {
      repository.problems['AbC12345'] = sampleProblem(
        authorUid: 'bad-1',
        nickname: '迷惑さん',
      );
      final container = await openSheet(tester);
      await tester.tap(key('report-block-author'));
      await tester.pumpAndSettle();
      expect(repository.fetchedProblemIds, ['AbC12345']);
      await tester.tap(key('block-confirm-ok'));
      await tester.pumpAndSettle();
      expect(container.read(blockedAuthorsProvider).isBlocked('bad-1'), isTrue);
      expect(find.text('ブロックしました。設定から解除できます'), findsOneWidget);
    });

    testWidgets('自分の問題はブロックできない', (tester) async {
      repository.problems['AbC12345'] = sampleProblem(authorUid: 'me');
      final container = await openSheet(tester);
      await tester.tap(key('report-block-author'));
      await tester.pumpAndSettle();
      expect(find.text('自分の問題の出題者はブロックできません'), findsOneWidget);
      expect(key('block-confirm'), findsNothing);
      expect(container.read(blockedAuthorsProvider).authors, isEmpty);
    });

    testWidgets('読み込めない・見つからない・削除済みの出題者は「ブロックできませんでした」', (tester) async {
      // オフライン。
      repository.error = const BackendException(code: 'unavailable');
      await openSheet(tester);
      await tester.tap(key('report-block-author'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ブロックできませんでした'), findsOneWidget);
      expect(key('block-confirm'), findsNothing);

      // 見つからない（非表示・削除済みの問題）。
      repository.error = null;
      await openSheet(tester);
      await tester.tap(key('report-block-author'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ブロックできませんでした'), findsOneWidget);

      // 退会済みの出題者（authorUid = deleted）。
      repository.problems['AbC12345'] = sampleProblem(
        authorUid: 'deleted',
        nickname: '',
      );
      final last = await openSheet(tester);
      await tester.tap(key('report-block-author'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ブロックできませんでした'), findsOneWidget);
      expect(last.read(blockedAuthorsProvider).authors, isEmpty);
    });

    testWidgets('ProviderScope の外ではブロックの項目を出さない（通報だけ）', (tester) async {
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
      expect(key('report-reason-spam'), findsOneWidget);
      expect(key('report-block-author'), findsNothing);
    });
  });

  group('ProblemMenuButton', () {
    testWidgets('通報とブロックが並ぶ。「通報」は理由のシートを開く', (tester) async {
      await pump(
        tester,
        Scaffold(
          appBar: AppBar(
            actions: const [ProblemMenuButton(problemId: 'AbC12345')],
          ),
        ),
        repository: repository,
      );
      await tester.tap(find.byType(ProblemMenuButton));
      await tester.pumpAndSettle();
      expect(key('problem-menu-block'), findsOneWidget);
      await tester.tap(key('problem-menu-report'));
      await tester.pumpAndSettle();
      expect(key('report-reason-offensive'), findsOneWidget);
    });

    testWidgets('自分の問題（problem を渡したとき）には出ない', (tester) async {
      await pump(
        tester,
        Scaffold(
          appBar: AppBar(
            actions: [
              ProblemMenuButton(
                problemId: 'AbC12345',
                problem: sampleProblem(authorUid: 'me'),
              ),
            ],
          ),
        ),
        repository: repository,
      );
      expect(find.byType(PopupMenuButton<Object?>), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
    });
  });

  group('ブロック中の出題者の問題を開く（ディープリンク・通知）', () {
    final problem = sampleProblem(authorUid: 'bad-1', nickname: '迷惑さん');

    testWidgets('開かずに、ブロック中であることを知らせる', (tester) async {
      repository.problems['AbC12345'] = problem;
      final pushed = <(String, Object?)>[];
      OpenProblemResult? result;
      Problem? notified;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: testLocalizationsDelegates,
          onGenerateRoute: (settings) {
            if (settings.name != '/') {
              pushed.add((settings.name!, settings.arguments));
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: Text('route:${settings.name}')),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      result = await openProblemById(
        navigator: navigator,
        repository: repository,
        problemId: 'AbC12345',
        isBlocked: (uid) => uid == 'bad-1',
        onBlocked: (p) => notified = p,
      );
      await tester.pumpAndSettle();
      expect(result, OpenProblemResult.blocked);
      expect(notified?.id, 'AbC12345');
      expect(pushed, isEmpty);

      // ブロックしていない出題者なら開く。
      result = await openProblemById(
        navigator: navigator,
        repository: repository,
        problemId: 'AbC12345',
        isBlocked: (uid) => false,
      );
      await tester.pumpAndSettle();
      expect(result, OpenProblemResult.opened);
      expect(pushed, hasLength(1));
    });
  });

  group('設定の「ブロック中の出題者」', () {
    testWidgets('一覧に名前（なければ匿名）とブロックした日。解除すると消えて保存も更新', (tester) async {
      final container = await pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: BlockedAuthorsSection()),
        ),
        repository: repository,
        prefs: {
          blockedKey:
              '[{"uid":"bad-1","nickname":"迷惑さん","blockedAt":"2026-10-20T03:00:00.000Z"},'
              '{"uid":"bad-2","nickname":"","blockedAt":"2026-10-19T03:00:00.000Z"}]',
        },
      );
      expect(find.text('ブロック中の出題者'), findsOneWidget);
      expect(find.text('迷惑さん'), findsOneWidget);
      expect(find.text('匿名の出題者'), findsOneWidget);
      expect(find.textContaining('にブロック'), findsNWidgets(2));
      expect(key('settings-blocked-empty'), findsNothing);

      await tester.tap(key('settings-unblock-bad-1'));
      await tester.pumpAndSettle();
      expect(find.text('迷惑さん'), findsNothing);
      expect(find.text('ブロックを解除しました'), findsOneWidget);
      expect(container.read(blockedAuthorsProvider).authors.map((a) => a.uid), [
        'bad-2',
      ]);

      await tester.tap(key('settings-unblock-bad-2'));
      await tester.pumpAndSettle();
      expect(key('settings-blocked-empty'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(blockedKey), isNull);
    });

    testWidgets('ブロックしていなければブロックのしかたを案内', (tester) async {
      await pump(
        tester,
        const Scaffold(
          body: SingleChildScrollView(child: BlockedAuthorsSection()),
        ),
        repository: repository,
        locale: const Locale('en'),
      );
      expect(find.text('Blocked authors'), findsOneWidget);
      expect(
        find.textContaining('You have not blocked anyone'),
        findsOneWidget,
      );
    });
  });
}
