import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_page.dart';

const hand13 = [
  '1m',
  '2m',
  '3m',
  '4m',
  '5m',
  '6m',
  '7m',
  '8m',
  '9m',
  '1p',
  '2p',
  '3p',
  '4p', //
];

void main() {
  Object? nextArguments;
  String? nextRoute;

  /// [home] の画面から始めて、次の画面（quiz / result）への遷移を記録する。
  Future<void> pumpPage(
    WidgetTester tester, {
    required Widget page,
    RecognitionArgs? args,
    Locale locale = const Locale('ja'),
  }) async {
    nextArguments = null;
    nextRoute = null;
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    Widget next(String route) => Builder(
      builder: (context) {
        nextRoute = route;
        nextArguments = ModalRoute.of(context)?.settings.arguments;
        return Scaffold(body: Text('next:$route'));
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAnalyticsProvider.overrideWith((ref) => AppAnalytics())],
        child: MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          initialRoute: '/start',
          onGenerateRoute: (settings) {
            if (settings.name == '/start') {
              return MaterialPageRoute<void>(
                settings: RouteSettings(name: '/start', arguments: args),
                builder: (_) => page,
              );
            }
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => next(settings.name ?? ''),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RecognitionArgs argsOf(
    List<String> labels, {
    int? tsumoIndex,
    List<double?>? confidences,
    List<MeldCandidate> melds = const [],
    HandInput? base,
    String? notice,
  }) {
    return RecognitionArgs(
      draft: RecognitionDraft(
        labels: labels,
        tsumoIndex: tsumoIndex,
        confidences: confidences,
        melds: melds,
      ),
      base: base,
      notice: notice,
    );
  }

  String previewText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('recognition-preview')))
      .data!;

  bool nextEnabled(WidgetTester tester) =>
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('recognition-next')))
          .onPressed !=
      null;

  testWidgets('手入力は空の状態から始まり、牌が足りない間は進めない', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(manual: true),
      args: RecognitionArgs.manual,
    );

    expect(find.text('手入力'), findsOneWidget);
    expect(previewText(tester), contains('＋から牌を追加'));
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('手入力で 13 枚そろえると、シャンテン数と受け入れが出て Result へ進める', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(manual: true),
      args: RecognitionArgs.manual,
    );

    await tester.tap(find.byKey(const ValueKey('recognition-add-tile')));
    await tester.pumpAndSettle();
    for (final label in hand13.take(12)) {
      await tester.tap(find.byKey(ValueKey('tile-picker-$label')));
      await tester.pump();
    }
    expect(find.textContaining('(12枚)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tile-picker-4p')));
    await tester.pump();
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('recognition-tile-12')), findsOneWidget);
    expect(previewText(tester), startsWith('テンパイ・受け入れ'));
    expect(nextEnabled(tester), isTrue);
    expect(find.text('待ちを見る'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recognition-next')));
    await tester.pumpAndSettle();

    expect(nextRoute, Routes.result);
    final result = nextArguments as ResultArgs;
    expect(result.input.tiles, hand13);
    expect(result.input.tileCount, 13);
  });

  testWidgets('14 枚は Quiz へ。ツモ牌は末尾に移り、HandInput に入る', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf([...hand13, '9s'], tsumoIndex: 13),
    );

    // 14 枚: 最良の打牌（9s）つきのプレビュー。
    expect(previewText(tester), contains('テンパイ'));
    expect(previewText(tester), contains('9索切り'));
    expect(find.text('ツモ'), findsOneWidget);
    expect(find.text('この手を解く'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recognition-next')));
    await tester.pumpAndSettle();

    expect(nextRoute, Routes.quiz);
    final quiz = nextArguments as QuizArgs;
    expect(quiz.input.tileCount, 14);
    expect(quiz.input.tsumoTile, '9s');
    expect(quiz.input.tsumoIndex, 13);
  });

  testWidgets('牌が合わないときは理由を出して進めない', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf(hand13.take(11).toList()),
    );

    expect(previewText(tester), contains('牌が足りません（11枚）'));
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('確度の低い牌には ? が付き、注意書きが出る', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf(
        hand13,
        confidences: [for (var i = 0; i < 13; i++) i == 4 ? 0.3 : 0.9],
      ),
    );

    expect(find.text('?'), findsOneWidget);
    expect(find.textContaining('赤枠の牌は認識に自信がありません'), findsOneWidget);
  });

  testWidgets('牌をタップして直すと、プレビューと並びが更新され、元に戻せる', (tester) async {
    await pumpPage(tester, page: const RecognitionPage(), args: argsOf(hand13));
    final before = previewText(tester);

    await tester.tap(find.byKey(const ValueKey('recognition-tile-12'))); // 4p
    await tester.pumpAndSettle();
    expect(find.text('この牌を直す'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tile-picker-9s')));
    await tester.pumpAndSettle();

    expect(previewText(tester), isNot(before));
    expect(find.byKey(const ValueKey('recognition-undo')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recognition-undo')));
    await tester.pumpAndSettle();
    expect(previewText(tester), before);
    expect(find.byKey(const ValueKey('recognition-undo')), findsNothing);
  });

  testWidgets('4 枚そろっている牌は選べない', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf(['1m', '1m', '1m', '1m', ...hand13.skip(4)]),
    );

    await tester.tap(find.byKey(const ValueKey('recognition-tile-12')));
    await tester.pumpAndSettle();
    final picker = tester.widget<InkWell>(
      find.byKey(const ValueKey('tile-picker-1m')),
    );
    expect(picker.onTap, isNull);
  });

  testWidgets('牌をタップしてツモ牌にできる', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf([...hand13, '9s']),
    );
    expect(find.text('ツモ'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('recognition-tile-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ツモ牌にする'));
    await tester.pumpAndSettle();

    expect(find.text('ツモ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('recognition-next')));
    await tester.pumpAndSettle();
    final quiz = nextArguments as QuizArgs;
    expect(quiz.input.tsumoTile, '1m');
    expect(quiz.input.tsumoIndex, 13);
  });

  testWidgets('副露の候補を採用すると、牌が副露に移って枚数が合う', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf(
        [
          '1m',
          '2m',
          '3m',
          '6m',
          '7m',
          '8m',
          '2p',
          '3p',
          '4p',
          '5p',
          '5z',
          '5z',
          '5z', //
        ],
        melds: const [
          MeldCandidate(indices: [10, 11, 12], kind: MeldKind.pon),
        ],
      ),
    );
    expect(find.text('右端に副露の候補があります'), findsNothing);
    expect(find.textContaining('副露の候補'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('recognition-remove-meld-0')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('recognition-adopt-suggestion-0')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('recognition-remove-meld-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('recognition-adopt-suggestion-0')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('recognition-tile-10')), findsNothing);
    expect(nextEnabled(tester), isTrue);

    await tester.tap(find.byKey(const ValueKey('recognition-next')));
    await tester.pumpAndSettle();
    final result = nextArguments as ResultArgs;
    expect(result.input.melds.single.kind, MeldKind.pon);
    expect(result.input.tiles, hasLength(10));
    expect(result.input.tileCount, 13);
  });

  testWidgets('自風・場風・巡目を変えると HandInput に入る', (tester) async {
    await pumpPage(tester, page: const RecognitionPage(), args: argsOf(hand13));

    Future<void> tapKey(String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pump();
    }

    await tapKey('seat-west');
    await tapKey('round-south');
    await tapKey('recognition-turn-plus');
    await tapKey('recognition-turn-plus');
    expect(find.text('7巡目'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('recognition-next')));
    await tester.pumpAndSettle();
    final result = nextArguments as ResultArgs;
    expect(result.input.seatWind.name, 'west');
    expect(result.input.roundWind.name, 'south');
    expect(result.input.dealer, isFalse);
    expect(result.input.turn, 7);
  });

  testWidgets('ドラ表示牌を選んで HandInput に入れる', (tester) async {
    await pumpPage(tester, page: const RecognitionPage(), args: argsOf(hand13));

    await tester.ensureVisible(
      find.byKey(const ValueKey('recognition-pick-dora')),
    );
    await tester.tap(find.byKey(const ValueKey('recognition-pick-dora')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tile-picker-5p')));
    await tester.pump();
    await tester.tap(find.text('完了'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('recognition-next')));
    await tester.pumpAndSettle();
    final result = nextArguments as ResultArgs;
    expect(result.input.doraIndicators, ['5p']);
  });

  testWidgets('英語の端末では英語で表示される', (tester) async {
    await pumpPage(
      tester,
      page: const RecognitionPage(),
      args: argsOf(hand13),
      locale: const Locale('en'),
    );
    expect(find.text('Check the tiles'), findsOneWidget);
    expect(previewText(tester), startsWith('Tenpai'));
    expect(find.text('See the waits'), findsOneWidget);
  });
}
