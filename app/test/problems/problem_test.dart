import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/problems/problem.dart';

import 'fakes.dart';

void main() {
  group('Problem.fromData（API.md 3.2 の形）', () {
    final doc = <String, Object?>{
      'tiles': [
        '1m', '2m', '3m', '5m', '6m', '4p', '5p', '6p', '7s', '8s', '9s', //
        '2z', '2z', '9p',
      ],
      'tsumo': '9p',
      'tsumoIndex': 13,
      'melds': <Object?>[],
      'dora': ['3z'],
      'seatWind': 'south',
      'roundWind': 'east',
      'turn': 6,
      'authorUid': 'author-1',
      'authorNickname': 'まじゃおう',
      'createdAt': DateTime.utc(2026, 10, 21, 3),
      'locale': 'ja',
      'stats': {
        'total': 12,
        'correct': 7,
        'byTile': {'9p': 7, '5m': 5},
      },
      'featured': {'daily': '2026-10-21', 'posted': false},
      'reports': 0,
      'hidden': false,
      'cardPath': 'cards/AbC12345/1x1.png',
      'contentKey': 'ignored',
    };

    test('手牌をそのまま HandInput にできる（ツモ牌が末尾）', () {
      final problem = Problem.fromData('AbC12345', doc);
      expect(problem.id, 'AbC12345');
      expect(problem.input.tiles, hasLength(14));
      expect(problem.input.tsumoTile, '9p');
      expect(problem.input.doraIndicators, ['3z']);
      expect(problem.input.seatWind, Wind.south);
      expect(problem.input.roundWind, Wind.east);
      expect(problem.input.turn, 6);
      expect(problem.input.dealer, isFalse);
      expect(problem.input.isAnalyzable, isTrue);
      expect(problem.authorNickname, 'まじゃおう');
      expect(problem.featuredDaily, '2026-10-21');
      expect(problem.cardPath, 'cards/AbC12345/1x1.png');
      expect(problem.hidden, isFalse);
      expect(problem.isAuthoredBy('author-1'), isTrue);
      expect(problem.isAuthoredBy('other'), isFalse);
      expect(problem.isAuthoredBy(null), isFalse);
    });

    test('正解率は stats から求める。回答がなければ null', () {
      final stats = Problem.fromData('AbC12345', doc).stats;
      expect(stats.total, 12);
      expect(stats.correct, 7);
      expect(stats.byTile, {'9p': 7, '5m': 5});
      expect(stats.correctPercent, 58);
      expect(const ProblemStats().correctRate, isNull);
      expect(const ProblemStats().correctPercent, isNull);
    });

    test('副露・turn なし・親の問題も読める', () {
      final problem = Problem.fromData('AbC12345', {
        'tiles': [
          '1m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', '2z', '9p', //
        ],
        'tsumoIndex': 10,
        'melds': [
          {
            'kind': 'pon',
            'tiles': ['5z', '5z', '5z'],
          },
        ],
        'seatWind': 'east',
        'roundWind': 'south',
        'turn': null,
        'hidden': true,
      });
      expect(problem.input.melds, hasLength(1));
      expect(problem.input.melds.single.kind, MeldKind.pon);
      expect(problem.input.dealer, isTrue);
      expect(problem.input.turn, isNull);
      expect(problem.hidden, isTrue);
      expect(problem.input.isFourteen, isTrue);
    });

    test('手牌が読めないドキュメントは FormatException', () {
      expect(
        () => Problem.fromData('x', {'authorUid': 'u'}),
        throwsFormatException,
      );
    });
  });

  group('PublishedAnswer', () {
    test('エンジンの結果から 3 軸の解を手牌のラベルで作る', () {
      final input = sampleHand();
      final report = analyzeHand(input);
      final answer = PublishedAnswer.fromReport(report, input);

      expect(answer.byAxis.keys, StrategyAxis.values);
      for (final labels in answer.byAxis.values) {
        expect(labels, isNotEmpty);
        expect(labels.length, lessThanOrEqualTo(14));
        expect(labels.toSet(), hasLength(labels.length), reason: '重複なし');
        for (final label in labels) {
          expect(input.tiles, contains(label), reason: '解は手牌にある牌');
        }
      }
      // 9p を切るとテンパイ（速さ軸）だが、バランス・打点軸は 5m（一向聴で受け入れ 31 枚）。
      expect(answer.byAxis[StrategyAxis.speed], ['9p']);
      expect(answer.byAxis[StrategyAxis.points], ['5m']);
      expect(answer.correctTiles, ['5m']);
      expect(answer.shanten, 1);
      expect(answer.ukeireKinds, 9);
      expect(answer.ukeireTotal, 31);
      expect(
        answer.engineVersion,
        matches(RegExp(r'^[A-Za-z0-9._+/:@-]{1,40}$')),
      );
    });

    test('toJson は API.md 1.2 の answer と同じキー', () {
      final input = sampleHand();
      final json = PublishedAnswer.fromReport(
        analyzeHand(input),
        input,
      ).toJson();
      expect(
        json.keys,
        containsAll(['byAxis', 'ukeire', 'shanten', 'engineVersion']),
      );
      expect((json['byAxis']! as Map).keys, ['speed', 'points', 'balance']);
      expect((json['ukeire']! as Map).keys, ['kinds', 'total']);
      // JSON を経由しても同じ。
      expect(
        PublishedAnswer.fromJson(json),
        PublishedAnswer.fromReport(analyzeHand(input), input),
      );
    });

    test('赤5 は手牌にある表記（0p）のラベルで返す', () {
      final input = HandInput(
        tiles: const [
          '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m', '1p', '2p', //
          '3p', '0p', '9s',
        ],
        tsumoIndex: 13,
      );
      expect(tileLabelInHand(input, tileIdFromLabel('5p')), '0p');
      expect(tileLabelInHand(input, tileIdFromLabel('9s')), '9s');
      expect(tileLabelInHand(input, tileIdFromLabel('1z')), isNull);
      // 通常の 5 もあるなら通常の 5。
      final both = input.copyWith(tiles: [...input.tiles.take(13), '5p']);
      expect(tileLabelInHand(both, tileIdFromLabel('5p')), '5p');
    });

    test('13 枚の手（候補なし）は作れない', () {
      final input = HandInput(
        tiles: const [
          '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m', '1p', '2p', //
          '3p', '4p',
        ],
      );
      expect(
        () => PublishedAnswer.fromReport(analyzeHand(input), input),
        throwsStateError,
      );
    });
  });

  group('ProblemAnswerOutcome（POST /api/answer の返事）', () {
    test('API.md 2.1 の例を読める', () {
      final outcome = ProblemAnswerOutcome.fromJson(answerResponseJson());
      expect(outcome.yourTile, '9p');
      expect(outcome.correct, isTrue);
      expect(outcome.alreadyAnswered, isFalse);
      expect(outcome.judgement, {
        StrategyAxis.speed: true,
        StrategyAxis.points: false,
        StrategyAxis.balance: true,
      });
      expect(outcome.matchedAxis, StrategyAxis.balance);
      expect(outcome.stats.total, 12);
      expect(outcome.stats.byTile['5m'], 5);
      expect(outcome.answer.byAxis[StrategyAxis.points], ['9p', '5m']);
      expect(outcome.answer.ukeireTotal, 24);
      expect(outcome.answer.correctTiles, ['9p']);
    });

    test('不正解でも別の軸の解と一致していれば matchedAxis に出る', () {
      final json = answerResponseJson(correct: false);
      final outcome = ProblemAnswerOutcome.fromJson(json);
      expect(outcome.correct, isFalse);
      expect(outcome.matchedAxis, StrategyAxis.speed);
    });
  });

  group('日付', () {
    test('JST の日付は UTC+9 で求める', () {
      expect(jstDateString(DateTime.utc(2026, 10, 20, 14, 59)), '2026-10-20');
      expect(jstDateString(DateTime.utc(2026, 10, 20, 15, 0)), '2026-10-21');
      expect(jstDateString(DateTime.utc(2026, 12, 31, 15, 30)), '2027-01-01');
    });

    test('前日・翌日（月またぎ・年またぎ）', () {
      expect(previousDateString('2026-10-21'), '2026-10-20');
      expect(previousDateString('2026-03-01'), '2026-02-28');
      expect(previousDateString('2026-01-01'), '2025-12-31');
      expect(nextDateString('2026-10-31'), '2026-11-01');
      expect(nextDateString('2026-12-31'), '2027-01-01');
      expect(previousDateString('bad'), isNull);
      expect(nextDateString('bad'), isNull);
    });
  });

  test('通報の理由はサーバーの値で送る', () {
    expect(ProblemReportReason.spam.wireValue, 'spam');
    expect(ProblemReportReason.offensive.wireValue, 'offensive');
    expect(ProblemReportReason.wrongAnswer.wireValue, 'wrong_answer');
    expect(ProblemReportReason.other.wireValue, 'other');
  });
}
