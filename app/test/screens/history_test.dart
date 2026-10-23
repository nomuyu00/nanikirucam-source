import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_harness.dart';

HistoryEntry entryAt(
  DateTime at, {
  String? choice,
  StrategyAxis axis = StrategyAxis.balance,
}) {
  final report = analyzeNow(oneChoiceHand);
  return historyEntryFor(
    input: oneChoiceHand,
    report: report,
    chosenId: choice == null ? null : tileIdFromLabel(choice),
    axis: axis,
    source: 'manual',
    now: at,
  );
}

Map<String, Object> savedPrefs(List<HistoryEntry> entries) => {
  LocalHistory.preferenceKey: jsonEncode([
    for (final e in entries) e.toJson(),
  ]),
};

void main() {
  final base = DateTime(2026, 10, 21, 12);

  group('history_v1', () {
    test('JSON の往復（手・選択・各軸の正解・理由タグ・版）', () {
      final e = entryAt(base, choice: '2m');
      final back = HistoryEntry.fromJson(
        jsonDecode(jsonEncode(e.toJson())) as Map<String, Object?>,
      );
      expect(back, e);
      expect(back.input.tiles, oneChoiceHand.tiles);
      expect(back.input.tsumoIndex, 13);
      expect(back.best[StrategyAxis.points], ['9s']);
      expect(back.correct, isFalse);
      expect(back.reasonTags, contains('isolated_terminal'));
      expect(back.engineVersion, kEngineVersion);
    });

    test('壊れた記録は読み飛ばし、新しい順に読む', () async {
      SharedPreferences.setMockInitialValues({
        LocalHistory.preferenceKey: jsonEncode([
          entryAt(base).toJson(),
          {'id': 'broken'},
          'not a map',
          entryAt(base.add(const Duration(hours: 1))).toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      final entries = LocalHistory(prefs).load();
      expect(entries, hasLength(2));
      expect(entries.first.createdAt, base.add(const Duration(hours: 1)));
    });

    test('集計: 軸ごとの正解率と、間違えた問題に多い理由タグ', () {
      final entries = [
        entryAt(base, choice: '9s'),
        entryAt(base, choice: '2m'),
        entryAt(base, choice: '9s', axis: StrategyAxis.speed),
        entryAt(base),
      ];
      final stats = HistoryStats.of(entries);
      expect(stats.answered, 3);
      expect(stats.correct, 2);
      expect(stats.byAxis[StrategyAxis.balance], (answered: 2, correct: 1));
      expect(stats.byAxis[StrategyAxis.speed], (answered: 1, correct: 1));
      expect(stats.missedTags.first.code, 'isolated_terminal');
      expect(stats.missedTags.first.count, 1);

      final week = HistoryStats.lastWeek([
        entryAt(base.subtract(const Duration(days: 8)), choice: '2m'),
        entryAt(base, choice: '9s'),
      ], base);
      expect(week.answered, 1);
      expect(week.rate, 1.0);
    });
  });

  group('未解析（撮るだけモード）', () {
    final captured = HistoryEntry.captured(
      input: splitHand.normalized(),
      now: base,
    );

    test('JSON は "pending": true。解析の項目は持たない', () {
      final json = captured.toJson();
      expect(json['pending'], isTrue);
      expect(json.containsKey('best'), isFalse);
      expect(json.containsKey('correct'), isFalse);
      expect(json['hand'], splitHand.normalized().toJson());
      final back = HistoryEntry.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(back, captured);
      expect(back.pending, isTrue);
      // 解析済みの記録には pending を書かない。
      expect(entryAt(base).toJson().containsKey('pending'), isFalse);
      // 集計に入れない。
      expect(HistoryStats.of([captured]).answered, 0);
    });

    testWidgets('一覧で区別し、開くと修正画面 → Quiz → Result で解析済みに置き換わる', (
      tester,
    ) async {
      final h = await pumpScreens(
        tester,
        prefs: savedPrefs([captured, entryAt(base.subtract(const Duration(days: 1)))]),
        pages: realRecognitionPage,
      );
      await h.push(Routes.history, null);
      final card = find.byKey(ValueKey('history-${captured.id}'));
      expect(
        find.descendant(of: card, matching: find.text('未解析')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.text('撮るだけモードで保存した手。タップして確認・解析'),
        ),
        findsOneWidget,
      );

      await tester.tap(card);
      await tester.pumpAndSettle();
      final args = h.routes.lastArgs(Routes.recognition) as RecognitionArgs;
      expect(args.historyId, captured.id);
      expect(args.imageBytes, isNull);
      expect(find.byKey(const ValueKey('recognition-tile-13')), findsOneWidget);

      final next = find.byKey(const ValueKey('recognition-next'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect((h.routes.lastArgs(Routes.quiz) as QuizArgs).historyId, captured.id);
      await tester.tap(find.byKey(const ValueKey('quiz-tile-13')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('result-verdict')), findsOneWidget);

      // 二重に数えない: 件数は 2 のまま、同じ ID が解析済みになる。
      final history = await h.container.read(historyProvider.future);
      expect(history, hasLength(2));
      final updated = history.firstWhere((e) => e.id == captured.id);
      expect(updated.pending, isFalse);
      expect(updated.userChoice, '1z');
      expect(updated.correct, isNotNull);
      expect(updated.best[StrategyAxis.speed], ['1z']);
      expect(updated.source, 'photo');
      expect(updated.engineVersion, kEngineVersion);
      // 開いても無料枠は使わない。
      expect(h.container.read(quotaProvider).used, 0);
    });
  });

  testWidgets('空の履歴', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.history, null);
    expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
  });

  testWidgets('無料は直近 20 件と鍵、弱点分析は鍵、バナーあり', (tester) async {
    final entries = [
      for (var i = 0; i < 25; i++)
        entryAt(base.subtract(Duration(minutes: i)), choice: '9s'),
    ];
    final h = await pumpScreens(tester, prefs: savedPrefs(entries));
    await h.push(Routes.history, null);
    expect(find.byKey(const ValueKey('history-weakness-locked')), findsOneWidget);
    expect(find.byType(AdBannerSlot), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('history-more-locked')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(ValueKey('history-${entries[19].id}')), findsOneWidget);
    expect(find.byKey(ValueKey('history-${entries[20].id}')), findsNothing);
  });

  testWidgets('Pro は全件と弱点分析、バナーなし', (tester) async {
    final entries = [
      for (var i = 0; i < 25; i++)
        entryAt(
          base.subtract(Duration(minutes: i)),
          choice: i.isEven ? '9s' : '2m',
        ),
    ];
    final h = await pumpScreens(tester, pro: true, prefs: savedPrefs(entries));
    await h.push(Routes.history, null);
    expect(find.byKey(const ValueKey('history-weakness')), findsOneWidget);
    expect(find.textContaining('13 / 25 問'), findsOneWidget);
    expect(find.byType(AdBannerSlot), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('history-${entries[24].id}')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('history-more-locked')), findsNothing);
  });

  testWidgets('タップで Result を開き直す（履歴は増えない）', (tester) async {
    final entry = entryAt(base, choice: '2m');
    final h = await pumpScreens(tester, prefs: savedPrefs([entry]));
    await h.push(Routes.history, null);
    await tester.tap(find.byKey(ValueKey('history-${entry.id}')));
    await tester.pumpAndSettle();
    final args = h.routes.lastArgs(Routes.result) as ResultArgs;
    expect(args.saveToHistory, isFalse);
    expect(args.chosenDiscardId, tileIdFromLabel('2m'));
    expect(args.chosenAxis, StrategyAxis.balance);
    expect(find.byKey(const ValueKey('result-verdict')), findsOneWidget);
    expect(await h.container.read(historyProvider.future), hasLength(1));
  });

  testWidgets('履歴を消す', (tester) async {
    final h = await pumpScreens(tester, prefs: savedPrefs([entryAt(base)]));
    await h.push(Routes.history, null);
    await tester.tap(find.byKey(const ValueKey('history-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('history-clear-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('history-empty')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalHistory.preferenceKey), isNull);
  });
}
