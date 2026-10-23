import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/quiz/quiz_page.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_harness.dart';

const s = ResultStrings(AppLang.ja);

/// 理牌後の並び: 2m 3m 4m 3p 4p 5p 7p 8p 5s 6s 6s 6s 7s | ツモ 1z。
const index2m = 0;
const index8p = 7;
const index1z = 13;

String headline(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('result-verdict-headline')))
    .data!;

void main() {
  final report = analyzeNow(splitHand);
  final id1z = tileIdFromLabel('1z');
  final id8p = tileIdFromLabel('8p');
  final now = DateTime(2026, 10, 21, 20);
  final clock = clockProvider.overrideWithValue(() => now);

  testWidgets('選んだ軸の解と一致すれば正解。quiz_answered とストリーク', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(
      tester,
      analytics: analytics,
      overrides: [clock],
    );
    await h.push(Routes.quiz, QuizArgs(input: splitHand, source: 'manual'));
    expect(find.byKey(const ValueKey('quiz-page')), findsOneWidget);
    // 解析は開いたときに始める。
    expect(analytics.named('analysis_started').single, {
      'source': 'manual',
      'hand_size': 14,
    });
    expect(analytics.named('analysis_completed'), hasLength(1));

    // 速さで判定、打東。
    await tester.tap(find.byKey(const ValueKey('quiz-axis-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index1z')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    expect(headline(tester), '${s.correct}（${s.axis(StrategyAxis.speed)}）');
    expect(analytics.named('quiz_answered').single, {
      'correct_axis': 'speed',
      'selected_axis': 'speed',
      'correct': 1,
    });
    final args = h.routes.lastArgs(Routes.result) as ResultArgs;
    expect(args.chosenDiscardId, id1z);
    expect(args.chosenAxis, StrategyAxis.speed);
    expect(args.fromQuiz, isTrue);

    // ストリーク（streak_v1 に保存）。
    expect(h.container.read(streakProvider).current, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(
      jsonDecode(prefs.getString(StreakNotifier.preferenceKey)!),
      {'current': 1, 'best': 1, 'lastAnsweredDate': '2026-10-21'},
    );
    // 履歴にも残る。
    final history = await h.container.read(historyProvider.future);
    expect(history.single.correct, isTrue);
    expect(history.single.userChoice, '1z');
  });

  testWidgets('別の軸の解なら「打点重視なら正解」（correct_axis は points）', (tester) async {
    final verdict = judgeChoice(report, id8p, StrategyAxis.speed);
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(tester, analytics: analytics, overrides: [clock]);
    await h.push(Routes.quiz, QuizArgs(input: splitHand));
    await tester.tap(find.byKey(const ValueKey('quiz-axis-speed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index8p')));
    await tester.pumpAndSettle();
    expect(find.text('打 8筒 で答える'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();
    expect(headline(tester), verdict.otherCorrectAxes.map(s.correctFor).join(' / '));
    expect(headline(tester), contains(s.correctFor(StrategyAxis.points)));
    expect(analytics.named('quiz_answered').single, {
      'correct_axis': 'points',
      'selected_axis': 'speed',
      'correct': 0,
    });
  });

  testWidgets('どの軸の解でもなければ不正解（correct_axis は none）', (tester) async {
    final verdict = judgeChoice(report, tileIdFromLabel('2m'), StrategyAxis.balance);
    expect(verdict.otherCorrectAxes, isEmpty);
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(tester, analytics: analytics, overrides: [clock]);
    await h.push(Routes.quiz, QuizArgs(input: splitHand));
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index2m')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();
    expect(
      headline(tester),
      '${s.incorrect}（${s.rankOn(StrategyAxis.balance, verdict.rank!)}）',
    );
    expect(analytics.named('quiz_answered').single['correct_axis'], 'none');
    expect(analytics.named('quiz_answered').single['correct'], 0);
  });

  testWidgets('牌を選ぶまで答えられない。「わからない」は答えずに Result へ', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(tester, analytics: analytics, overrides: [clock]);
    await h.push(Routes.quiz, QuizArgs(input: splitHand));
    final confirm = tester.widget<FilledButton>(
      find.byKey(const ValueKey('quiz-confirm')),
    );
    expect(confirm.onPressed, isNull);
    // 選んでもう一度タップすると外れる。
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index1z')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index1z')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('quiz-confirm')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('quiz-skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-verdict')), findsNothing);
    expect(analytics.named('quiz_answered'), isEmpty);
    expect(h.container.read(streakProvider).current, 0);
    final history = await h.container.read(historyProvider.future);
    expect(history.single.correct, isNull);
  });

  testWidgets('公開問題はサーバーへ回答を送り、みんなの正解率を Result に出す', (tester) async {
    final submitter = _FakeSubmitter(
      ProblemAnswerOutcome.fromJson({
        'yourTile': '1z',
        'correct': true,
        'judgement': {'speed': true, 'points': false, 'balance': true},
        'stats': {
          'total': 40,
          'correct': 9,
          'byTile': {'1z': 9, '8p': 20, '2m': 11},
        },
        'answer': <String, Object?>{},
      }),
    );
    final h = await pumpScreens(
      tester,
      overrides: [
        clock,
        problemAnswerSubmitterProvider.overrideWithValue(submitter),
      ],
    );
    await h.push(Routes.quiz, QuizArgs(input: splitHand, problemId: 'p42'));
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index1z')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();
    expect(submitter.sent, [('p42', id1z)]);
    final args = h.routes.lastArgs(Routes.result) as ResultArgs;
    expect(args.problemOutcome?.stats.total, 40);
    expect(args.source, 'problem');
    expect(find.byKey(const ValueKey('result-community')), findsOneWidget);
    expect(find.text(s.communityRate(23, 40)), findsOneWidget);
    expect(find.text(s.communityTitle(40)), findsOneWidget);
    // 公開問題は通報できる。
    expect(find.byKey(const ValueKey('result-menu')), findsOneWidget);
  });

  testWidgets('公開問題の Quiz には通報・出題者のブロックのメニューが出る。手入力の問題には出ない', (
    tester,
  ) async {
    final h = await pumpScreens(tester, overrides: [clock]);
    await h.push(Routes.quiz, QuizArgs(input: splitHand, problemId: 'p42'));
    await tester.tap(find.byKey(const ValueKey('quiz-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('problem-menu-report')), findsOneWidget);
    expect(find.byKey(const ValueKey('problem-menu-block')), findsOneWidget);

    await h.push(Routes.quiz, QuizArgs(input: splitHand));
    expect(find.byKey(const ValueKey('quiz-menu')), findsNothing);
  });

  testWidgets('端末内の今日の問題: 通報メニューを出さず、回答は送らずに解答済みとして記録する', (
    tester,
  ) async {
    final submitter = _FakeSubmitter(
      ProblemAnswerOutcome.fromJson({
        'yourTile': '1z',
        'correct': true,
        'stats': <String, Object?>{},
        'answer': <String, Object?>{},
      }),
    );
    final h = await pumpScreens(
      tester,
      overrides: [
        clock,
        problemAnswerSubmitterProvider.overrideWithValue(submitter),
      ],
    );
    const id = 'daily-2026-10-21-3';
    await h.push(
      Routes.quiz,
      QuizArgs(input: splitHand, problemId: id, timed: true, source: 'today'),
    );
    expect(find.byKey(const ValueKey('quiz-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('quiz-menu')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quiz-tile-$index1z')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();
    expect(submitter.sent, isEmpty, reason: 'サーバーへは送らない');
    expect(h.container.read(dailySolvedProvider), {id});
    final args = h.routes.lastArgs(Routes.result) as ResultArgs;
    expect(args.problemId, id);
    expect(args.problemOutcome, isNull);
    expect(args.source, 'today');
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-menu')), findsNothing);
    expect(find.byKey(const ValueKey('result-community')), findsNothing);
    final history = await h.container.read(historyProvider.future);
    expect(history.first.problemId, id);
  });

  testWidgets('端末内の今日の問題: 時間切れ（答えない）は解答済みにしない', (tester) async {
    final h = await pumpScreens(tester, overrides: [clock]);
    await h.push(
      Routes.quiz,
      QuizArgs(
        input: splitHand,
        problemId: 'daily-2026-10-21-1',
        timed: true,
        source: 'today',
      ),
    );
    await tester.pump(const Duration(seconds: kQuizTimeLimitSeconds + 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    expect(h.container.read(dailySolvedProvider), isEmpty);
  });

  testWidgets('13 枚の手はクイズにせず Result へ', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.quiz, QuizArgs(input: closedYakuHand, problemId: 'p1'));
    expect(find.byKey(const ValueKey('quiz-page')), findsNothing);
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    final args = h.routes.lastArgs(Routes.result) as ResultArgs;
    expect(args.problemId, 'p1');
    expect(args.source, 'problem');
  });

  testWidgets('和了形はクイズにせず Result（ツモ和了）へ', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.quiz, QuizArgs(input: winHand));
    expect(find.byKey(const ValueKey('result-win')), findsOneWidget);
  });

  testWidgets('制限時間つきは時間切れで答えずに Result へ', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.quiz, QuizArgs(input: splitHand, timed: true));
    expect(find.byKey(const ValueKey('quiz-timer')), findsOneWidget);
    await tester.pump(const Duration(seconds: kQuizTimeLimitSeconds + 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-verdict')), findsNothing);
    expect(h.routes.contains(Routes.result), isTrue);
  });

  group('ストリーク', () {
    test('連続した日は伸び、1 日空くと 1 からやり直す。同じ日は増えない', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(streakProvider.notifier);
      await notifier.recordAnswer(DateTime(2026, 10, 20, 9));
      await notifier.recordAnswer(DateTime(2026, 10, 20, 22));
      expect(container.read(streakProvider).current, 1);
      await notifier.recordAnswer(DateTime(2026, 10, 21, 7));
      expect(container.read(streakProvider).current, 2);
      await notifier.recordAnswer(DateTime(2026, 10, 23, 7));
      final state = container.read(streakProvider);
      expect(state.current, 1);
      expect(state.best, 2);
      expect(state.lastAnsweredDate, '2026-10-23');
      // 途切れていれば表示は 0。
      expect(state.currentAsOf(DateTime(2026, 10, 24)), 1);
      expect(state.currentAsOf(DateTime(2026, 10, 25)), 0);
    });

    test('保存した値を読み込む（再起動後も続く）', () async {
      SharedPreferences.setMockInitialValues({
        StreakNotifier.preferenceKey: jsonEncode({
          'current': 6,
          'best': 9,
          'lastAnsweredDate': '2026-10-20',
        }),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(sharedPreferencesProvider.future);
      expect(container.read(streakProvider).current, 6);
      await container
          .read(streakProvider.notifier)
          .recordAnswer(DateTime(2026, 10, 21));
      expect(container.read(streakProvider).current, 7);
      expect(container.read(streakProvider).best, 9);
    });
  });
}

class _FakeSubmitter extends ProblemAnswerSubmitter {
  _FakeSubmitter(this.outcome)
    : super(repository: UnavailableProblemRepository());

  final ProblemAnswerOutcome outcome;
  final List<(String, int)> sent = [];

  @override
  Future<ProblemAnswerOutcome?> submitChoice({
    required String problemId,
    required HandInput input,
    required int discardId,
    int? selfRank,
  }) async {
    sent.add((problemId, discardId));
    return outcome;
  }
}
