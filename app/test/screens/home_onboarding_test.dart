import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/ui/home/home_page.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_harness.dart';

void main() {
  final now = DateTime(2026, 10, 21, 20);
  final clock = clockProvider.overrideWithValue(() => now);

  Future<ScreenHarness> pumpHome(
    WidgetTester tester, {
    bool pro = false,
    bool online = false,
    Map<String, Object> prefs = const {},
  }) => pumpScreens(
    tester,
    pro: pro,
    prefs: prefs,
    overrides: [clock, onlineFeaturesProvider.overrideWithValue(online)],
    home: const HomePage(),
  );

  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('無料: 残りの写真解析・体験時間・Pro の入口・バナー', (tester) async {
    final h = await pumpHome(tester);
    expect(textOf(tester, 'home-photo-remaining'), '今日あと 5 / 5 回');
    expect(find.text('今日の体験 残り 5 分 00 秒'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-pro')), findsOneWidget);
    expect(find.byType(AdBannerSlot), findsOneWidget);
    expect(textOf(tester, 'home-streak'), '今日の 1 問で連続記録を始めよう');

    await h.container.read(quotaProvider.notifier).tryConsume();
    await h.container.read(quotaProvider.notifier).tryConsume();
    await tester.pumpAndSettle();
    expect(textOf(tester, 'home-photo-remaining'), '今日あと 3 / 5 回');

    await tester.tap(find.byKey(const ValueKey('home-pro')));
    await tester.pumpAndSettle();
    expect(
      (h.routes.lastArgs(Routes.paywall) as PaywallArgs).trigger,
      PaywallTrigger.home,
    );
  });

  testWidgets('Pro: 無制限の表示、Pro の入口とバナーなし', (tester) async {
    await pumpHome(tester, pro: true);
    expect(textOf(tester, 'home-photo-remaining'), 'Pro: 無制限');
    expect(find.byKey(const ValueKey('home-pro')), findsNothing);
    expect(find.byType(AdBannerSlot), findsNothing);
  });

  testWidgets('ストリークと今週の正解率', (tester) async {
    final report = analyzeNow(oneChoiceHand);
    HistoryEntry entry(String choice, int daysAgo) => historyEntryFor(
      input: oneChoiceHand,
      report: report,
      chosenId: tileIdFromLabel(choice),
      axis: StrategyAxis.balance,
      now: now.subtract(Duration(days: daysAgo, minutes: choice.length)),
    );
    await pumpHome(
      tester,
      prefs: {
        StreakNotifier.preferenceKey: jsonEncode({
          'current': 3,
          'best': 5,
          'lastAnsweredDate': '2026-10-20',
        }),
        LocalHistory.preferenceKey: jsonEncode([
          entry('9s', 0).toJson(),
          entry('2m', 1).toJson(),
          entry('9s', 2).toJson(),
          entry('9s', 10).toJson(),
        ]),
      },
    );
    expect(textOf(tester, 'home-streak'), '3 日連続');
    expect(find.text('最高 5 日'), findsOneWidget);
    expect(textOf(tester, 'home-week'), '今週の正解率 67%（2 / 3 問）');
  });

  Future<void> pumpWithSolved(WidgetTester tester, List<String> solved) =>
      pumpScreens(
        tester,
        prefs: {DailySolvedNotifier.preferenceKey: jsonEncode(solved)},
        overrides: [
          clock,
          onlineFeaturesProvider.overrideWithValue(false),
          todayDateProvider.overrideWithValue('2026-10-21'),
          problemRepositoryProvider.overrideWithValue(
            LocalDailyProblemRepository(generate: (date) async => const []),
          ),
        ],
        home: const HomePage(),
      );

  testWidgets('今日の問題の進捗（端末内の 3 問）を出す', (tester) async {
    await pumpWithSolved(tester, [
      localDailyProblemId('2026-10-21', 2),
      // 前の日の問題は数えない。
      localDailyProblemId('2026-10-20', 1),
    ]);
    expect(textOf(tester, 'home-today-progress'), '1 / 3 問クリア');
  });

  testWidgets('今日の問題を 3 問とも解いたら達成を出す', (tester) async {
    await pumpWithSolved(tester, [
      for (var n = 1; n <= 3; n++) localDailyProblemId('2026-10-21', n),
    ]);
    expect(textOf(tester, 'home-today-progress'), '今日の 3 問クリア！');
  });

  testWidgets('入口: 写真は撮影へ、履歴は履歴画面へ', (tester) async {
    final h = await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('home-photo')));
    await tester.pumpAndSettle();
    expect(h.routes.contains(Routes.camera), isTrue);
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('home-history')));
    await tester.tap(find.byKey(const ValueKey('home-history')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-page')), findsOneWidget);
  });

  testWidgets('出題した問題: オンライン機能が無いと出さない（今日の問題は出す）', (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const ValueKey('home-today')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-my-problems')), findsNothing);
    expect(find.text('出題した問題'), findsNothing);
  });

  testWidgets('出題した問題: オンライン機能があれば出す', (tester) async {
    await pumpHome(tester, online: true);
    await tester.ensureVisible(find.byKey(const ValueKey('home-my-problems')));
    expect(find.byKey(const ValueKey('home-my-problems')), findsOneWidget);
    expect(find.text('出題した問題'), findsOneWidget);
  });

  testWidgets('Onboarding: 3 枚 → マナーと同意 → はじめる', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(tester, analytics: analytics);
    await h.push(Routes.onboarding, null);
    expect(find.text('かざす'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-start')), findsNothing);
    // オンライン機能が無い版: 3 枚目は端末内で完結する説明（Web での回答に触れない）。
    for (final title in ['自分で切る', '毎日3問']) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-manners')), findsOneWidget);
    expect(find.textContaining('友人戦・練習用'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('onboarding-start')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-page')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(OnboardingGate.preferenceKey), isTrue);
    expect(analytics.named('onboarding_completed'), hasLength(1));
  });

  testWidgets('Onboarding: オンライン機能が無いと、3 枚目に「誰でもアプリなしで回答」と出さない', (
    tester,
  ) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.onboarding, null);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('毎日3問'), findsOneWidget);
    expect(find.textContaining('今日の問題を3問'), findsOneWidget);
    expect(find.textContaining('問題カードの画像'), findsOneWidget);
    expect(find.textContaining('アプリなしで回答'), findsNothing);
    expect(find.text('友達に出す'), findsNothing);
  });

  testWidgets('Onboarding: オンライン機能があれば、3 枚目は友達に出す説明', (tester) async {
    final h = await pumpScreens(
      tester,
      overrides: [onlineFeaturesProvider.overrideWithValue(true)],
    );
    await h.push(Routes.onboarding, null);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('onboarding-next')));
      await tester.pumpAndSettle();
    }
    expect(find.text('友達に出す'), findsOneWidget);
    expect(find.textContaining('アプリなしで回答できます'), findsOneWidget);
  });

  testWidgets('Onboarding: スキップで最後のページへ', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.onboarding, null);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-skip')), findsNothing);
  });
}
