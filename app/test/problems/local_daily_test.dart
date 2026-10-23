// 端末内の今日の問題（LocalDailyProblemRepository・ID・解答済みの記録）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// メイン Isolate で同期的に作る生成器（呼ばれた日付を記録する）。
class RecordingGenerator {
  final List<String> dates = [];
  Object? error;

  Future<List<DailyHand>> call(String date) async {
    dates.add(date);
    final e = error;
    if (e != null) throw e;
    return DailyProblemGenerator().generate(date);
  }
}

void main() {
  group('問題 ID', () {
    test('日付と番号から作り、読み戻せる', () {
      expect(localDailyProblemId('2026-10-22', 1), 'daily-2026-10-22-1');
      final parsed = parseLocalDailyProblemId('daily-2026-10-22-3');
      expect(parsed?.date, '2026-10-22');
      expect(parsed?.number, 3);
      expect(localDailyLevelOf('daily-2026-10-22-1'), DailyLevel.basic);
      expect(localDailyLevelOf('daily-2026-10-22-2'), DailyLevel.standard);
      expect(localDailyLevelOf('daily-2026-10-22-3'), DailyLevel.advanced);
    });

    test('公開問題の ID・範囲外の番号・形の違うものは端末内の問題ではない', () {
      for (final id in [
        'AbC12345',
        'daily-2026-10-22-0',
        'daily-2026-10-22-4',
        'daily-2026-10-22',
        'daily-26-10-22-1',
        'xdaily-2026-10-22-1',
      ]) {
        expect(isLocalDailyProblemId(id), isFalse, reason: id);
        expect(localDailyLevelOf(id), isNull, reason: id);
      }
      expect(isLocalDailyProblemId(null), isFalse);
    });
  });

  group('LocalDailyProblemRepository', () {
    late RecordingGenerator generator;
    late LocalDailyProblemRepository repository;

    setUp(() {
      generator = RecordingGenerator();
      repository = LocalDailyProblemRepository(generate: generator.call);
    });

    test('オンライン機能は使えないが、今日の問題は出せる', () {
      expect(repository.available, isFalse);
      expect(repository.supportsDaily, isTrue);
      expect(const UnavailableProblemRepository().supportsDaily, isFalse);
    });

    test('fetchDaily は 3 問（ID は日付と番号、14 枚でツモ牌つき、出題者・集計なし）', () async {
      final daily = await repository.fetchDaily('2026-10-22');
      expect(daily.date, '2026-10-22');
      expect(
        [for (final p in daily.all) p.id],
        ['daily-2026-10-22-1', 'daily-2026-10-22-2', 'daily-2026-10-22-3'],
      );
      final hands = DailyProblemGenerator().generate('2026-10-22');
      for (var i = 0; i < 3; i++) {
        final problem = daily.all[i];
        expect(problem.input.isFourteen, isTrue);
        expect(problem.input.isAnalyzable, isTrue);
        expect(problem.input.tsumoIndex, 13);
        expect(problem.input.tiles, hands[i].tiles);
        expect(problem.input.doraIndicators, [hands[i].doraIndicator]);
        expect(problem.input.seatWind, hands[i].seatWind);
        expect(problem.input.roundWind, hands[i].roundWind);
        expect(problem.input.dealer, hands[i].seatWind == Wind.east);
        expect(problem.input.turn, hands[i].turn);
        expect(problem.authorUid, isEmpty);
        expect(problem.stats.total, 0);
        // アプリのエンジン（既定ルール）でも、生成器の選別どおりに割れる・割れない。
        final report = analyzeHand(problem.input);
        expect(
          agreementOf(report) == AnswerAgreement.split,
          hands[i].split,
          reason: problem.input.toString(),
        );
      }
    });

    test('同じ日は作り直さない。違う日は別の問題', () async {
      final a = await repository.fetchDaily('2026-10-22');
      final b = await repository.fetchDaily('2026-10-22');
      expect(b, a);
      expect(generator.dates, ['2026-10-22']);
      final c = await repository.fetchDaily('2026-10-21');
      expect(c.all.first.input, isNot(a.all.first.input));
      expect(generator.dates, ['2026-10-22', '2026-10-21']);
    });

    test('失敗は覚えず、次の呼び出しで作り直す', () async {
      generator.error = StateError('boom');
      await expectLater(repository.fetchDaily('2026-10-22'), throwsStateError);
      generator.error = null;
      final daily = await repository.fetchDaily('2026-10-22');
      expect(daily.all, hasLength(3));
      expect(generator.dates, ['2026-10-22', '2026-10-22']);
    });

    test('fetchProblem は ID から同じ問題を作り直す。公開問題の ID は読めない', () async {
      final daily = await repository.fetchDaily('2026-10-20');
      final fresh = LocalDailyProblemRepository(generate: generator.call);
      expect(await fresh.fetchProblem('daily-2026-10-20-2'), daily.all[1]);
      await expectLater(
        repository.fetchProblem('AbC12345'),
        throwsA(
          isA<BackendException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
    });

    test('出題した問題・人気の問題は空。回答・通報は使えない', () async {
      expect(await repository.fetchMyProblems('me'), isEmpty);
      expect(await repository.fetchPopular(), isEmpty);
      await expectLater(
        repository.answer(problemId: 'daily-2026-10-22-1', tile: '1m'),
        throwsA(isA<BackendException>()),
      );
      await expectLater(
        repository.report('daily-2026-10-22-1', ProblemReportReason.other),
        throwsA(isA<BackendException>()),
      );
    });

    test('既定では別 Isolate で作る（結果はメインで作ったものと同じ）', () async {
      final daily = await LocalDailyProblemRepository().fetchDaily(
        '2026-10-22',
      );
      final hands = DailyProblemGenerator().generate('2026-10-22');
      expect(
        [for (final p in daily.all) p.input.tiles],
        [for (final h in hands) h.tiles],
      );
    });

    test('バックエンド無効の版では problemRepositoryProvider が端末内の実装になる', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repository = container.read(problemRepositoryProvider);
      if (AppConfig.firebaseBackendEnabled) {
        expect(repository, isA<FirebaseProblemRepository>());
      } else {
        expect(repository, isA<LocalDailyProblemRepository>());
        expect(repository.supportsDaily, isTrue);
        expect(repository.available, isFalse);
      }
    });
  });

  group('解答済みの記録（daily_solved_v1）', () {
    test('記録して保存し、読み直せる。新しい順に上限まで', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final prefs = await SharedPreferences.getInstance();
      expect(container.read(dailySolvedProvider), isEmpty);
      final notifier = container.read(dailySolvedProvider.notifier);
      await notifier.markSolved('daily-2026-10-22-1');
      await notifier.markSolved('daily-2026-10-22-3');
      await notifier.markSolved('daily-2026-10-22-1');
      expect(container.read(dailySolvedProvider), {
        'daily-2026-10-22-1',
        'daily-2026-10-22-3',
      });
      expect(jsonDecode(prefs.getString(DailySolvedNotifier.preferenceKey)!), [
        'daily-2026-10-22-1',
        'daily-2026-10-22-3',
      ]);

      final again = ProviderContainer();
      addTearDown(again.dispose);
      again.read(dailySolvedProvider);
      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();
      expect(again.read(dailySolvedProvider), {
        'daily-2026-10-22-1',
        'daily-2026-10-22-3',
      });
    });

    test('上限を超えたら古いものから消える。壊れた値は空として読む', () async {
      SharedPreferences.setMockInitialValues({
        DailySolvedNotifier.preferenceKey: jsonEncode([
          for (var i = 0; i < DailySolvedNotifier.maxEntries; i++) 'old-$i',
        ]),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(dailySolvedProvider.notifier)
          .markSolved('daily-2026-10-22-2');
      final solved = container.read(dailySolvedProvider);
      expect(solved, hasLength(DailySolvedNotifier.maxEntries));
      expect(solved, contains('daily-2026-10-22-2'));
      expect(
        solved,
        isNot(contains('old-${DailySolvedNotifier.maxEntries - 1}')),
      );

      SharedPreferences.setMockInitialValues({
        DailySolvedNotifier.preferenceKey: '{broken',
      });
      final broken = ProviderContainer();
      addTearDown(broken.dispose);
      broken.read(dailySolvedProvider);
      await pumpEventQueue();
      expect(broken.read(dailySolvedProvider), isEmpty);
    });
  });
}
