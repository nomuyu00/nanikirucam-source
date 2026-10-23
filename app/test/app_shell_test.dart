import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/app.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

HandInput sampleInput() => HandInput(
  tiles: const [
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
  ],
);

/// 引数が必要なルートに渡す値。
Object? argumentsFor(String route) => switch (route) {
  Routes.quiz => QuizArgs(input: sampleInput()),
  Routes.result => ResultArgs(input: sampleInput()),
  Routes.candidateDetail ||
  Routes.explanation => CandidateDetailArgs(input: sampleInput(), discardId: 0),
  Routes.shareCard => ShareCardArgs(
    kind: ShareCardKind.problem,
    input: sampleInput(),
  ),
  Routes.publish => PublishArgs(input: sampleInput()),
  Routes.liveSummary => LiveSummaryArgs(
    startedAt: DateTime(2026, 10, 21),
    durationSec: 300,
    adviceCount: 12,
    wins: const [LiveWinSummary(han: 3, fu: 30, points: 3900)],
  ),
  Routes.paywall => const PaywallArgs(trigger: PaywallTrigger.liveTrialEnded),
  Routes.winScore => WinScoreArgs(input: sampleInput()),
  _ => null,
};

Future<void> pumpApp(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  Locale? platformLocale,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  if (platformLocale != null) {
    tester.platformDispatcher.localesTestValue = [platformLocale];
    tester.platformDispatcher.localeTestValue = platformLocale;
  }
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearLocalesTestValue();
    tester.platformDispatcher.clearLocaleTestValue();
  });
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        appAnalyticsProvider.overrideWith((ref) => AppAnalytics()),
        // 解析はその場で動かす（別 Isolate はテストの偽の時間では終わらない）。
        analysisServiceProvider.overrideWithValue(
          AnalysisService(
            runner: (hand, deep) async =>
                DefaultNanikiruEngine().analyze(hand, deep: deep),
          ),
        ),
        // 今日の問題（サーバーなしの版は端末内で作る）もその場で作る。
        problemRepositoryProvider.overrideWithValue(
          LocalDailyProblemRepository(
            generate: (date) async => DailyProblemGenerator().generate(date),
          ),
        ),
      ],
      child: const NanikiruCamApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('仕様 6.0 の全画面がルート表に登録されている', () {
    const expected = {
      Routes.home,
      Routes.onboarding,
      Routes.live,
      Routes.liveSummary,
      Routes.camera,
      Routes.recognitionLoading,
      Routes.recognition,
      Routes.manualInput,
      Routes.quiz,
      Routes.result,
      Routes.candidateDetail,
      Routes.explanation,
      Routes.shareCard,
      Routes.publish,
      Routes.today,
      Routes.myProblems,
      Routes.history,
      Routes.paywall,
      Routes.settings,
      Routes.winScore,
    };
    expect(appRoutes.keys.toSet(), expected);
    // 画面名（GA4）にも全ルートがある。
    expect(AppAnalytics.screenNames.keys.toSet(), expected);
  });

  testWidgets('初回起動は Onboarding、見終えると Home になり、次回から Home', (tester) async {
    await pumpApp(tester);
    expect(find.byKey(const ValueKey('onboarding-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-live')), findsNothing);

    // 3 枚の説明を飛ばして、最後のページ（マナーと同意）の「はじめる」。
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-live')), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OnboardingGate.preferenceKey), isTrue);

    // 次回起動（保存された状態から）。
    await pumpApp(tester, prefs: {OnboardingGate.preferenceKey: true});
    expect(find.byKey(const ValueKey('home-live')), findsOneWidget);
  });

  testWidgets('Home から各画面へ遷移できる', (tester) async {
    await pumpApp(tester, prefs: {OnboardingGate.preferenceKey: true});

    Future<void> openAndBack(String key, String route, {Key? pageKey}) async {
      final entry = find.byKey(ValueKey(key));
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      if (pageKey != null) {
        expect(find.byKey(pageKey), findsOneWidget, reason: route);
      } else {
        // 仮表示（ルート名の表示）から実装済みの画面に替わっても通るよう、
        // いちばん上の画面のルート名で確かめる。
        final top = ModalRoute.of(tester.element(find.byType(Scaffold).last));
        expect(top?.settings.name, route, reason: route);
      }
      Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-live')), findsOneWidget);
    }

    // Live は体験時間の秒読みやカメラの準備で止まらないことがあるので、pump で進める。
    final live = find.byKey(const ValueKey('home-live'));
    await tester.ensureVisible(live);
    await tester.tap(live);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('live-page')), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('live-page')))).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-live')), findsOneWidget);

    await openAndBack('home-today', Routes.today);
    // サーバーなしの構成（テストの既定）では「出題した問題」は出さない。
    expect(find.byKey(const ValueKey('home-my-problems')), findsNothing);
    await openAndBack(
      'home-history',
      Routes.history,
      pageKey: const ValueKey('history-page'),
    );
    await openAndBack('home-settings', Routes.settings);
  });

  testWidgets('Home の「手入力」は空の手入力画面、「写真で解析」は撮影画面のルート', (tester) async {
    await pumpApp(tester, prefs: {OnboardingGate.preferenceKey: true});
    await tester.ensureVisible(find.byKey(const ValueKey('home-manual')));
    await tester.tap(find.byKey(const ValueKey('home-manual')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('recognition-add-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('recognition-tile-0')), findsNothing);
  });

  for (final route in [
    Routes.onboarding,
    Routes.live,
    Routes.liveSummary,
    Routes.quiz,
    Routes.result,
    Routes.candidateDetail,
    Routes.explanation,
    Routes.shareCard,
    Routes.publish,
    Routes.today,
    Routes.myProblems,
    Routes.history,
    Routes.paywall,
    Routes.settings,
    Routes.manualInput,
    Routes.winScore,
  ]) {
    testWidgets('$route を引数つきで開ける', (tester) async {
      await pumpApp(tester, prefs: {OnboardingGate.preferenceKey: true});
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pushNamed(route, arguments: argumentsFor(route));
      if (route == Routes.live) {
        // Live は体験時間の秒読みやカメラの準備で止まらないことがあるので、pump で進め、
        // 閉じてタイマーを止める。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('live-page')), findsOneWidget);
        navigator.pop();
        await tester.pumpAndSettle();
        return;
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsWidgets);
    });
  }

  testWidgets('Quiz から Result へ HandInput が渡る', (tester) async {
    await pumpApp(tester, prefs: {OnboardingGate.preferenceKey: true});
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    // 14 枚: 1 枚選んで答えると Result（選んだ牌と軸つき）。
    final fourteen = HandInput(
      tiles: [...sampleInput().tiles, '9s'],
      tsumoIndex: 13,
    );
    navigator.pushNamed(Routes.quiz, arguments: QuizArgs(input: fourteen));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz-page')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quiz-tile-13')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-verdict')), findsOneWidget);

    // 13 枚はクイズにせず Result（待ちと点数）。
    navigator.pushNamed(Routes.quiz, arguments: QuizArgs(input: sampleInput()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quiz-page')), findsNothing);
    expect(find.byKey(const ValueKey('thirteen-waits')), findsOneWidget);
  });

  testWidgets('端末の言語が英語なら英語、それ以外は日本語で表示される', (tester) async {
    await pumpApp(
      tester,
      prefs: {OnboardingGate.preferenceKey: true},
      platformLocale: const Locale('en', 'US'),
    );
    expect(find.text('Live Navi'), findsOneWidget);

    await pumpApp(
      tester,
      prefs: {OnboardingGate.preferenceKey: true},
      platformLocale: const Locale('fr', 'FR'),
    );
    expect(find.text('ライブナビ'), findsOneWidget);

    await pumpApp(
      tester,
      prefs: {OnboardingGate.preferenceKey: true},
      platformLocale: const Locale('ja', 'JP'),
    );
    expect(find.text('ライブナビ'), findsOneWidget);
  });

  test('引数の型は HandInput を中心に渡せる', () {
    final input = sampleInput();
    expect(QuizArgs(input: input).input, input);
    expect(
      ResultArgs(
        input: input,
        chosenDiscardId: 3,
        chosenAxis: StrategyAxis.speed,
      ).chosenAxis,
      StrategyAxis.speed,
    );
  });
}
