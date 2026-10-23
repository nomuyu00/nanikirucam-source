import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/quiz/widgets/quiz_hand.dart';

import 'screens_harness.dart';

void main() {
  group('splitQuizRows（2 段に折り返す位置）', () {
    test('1 段に入れば折り返さない', () {
      expect(
        splitQuizRows([
          '1m',
          '2m',
          '3m',
          '4p',
          '5p',
          '6p',
          '7s',
        ], hasTsumo: true),
        [7],
      );
    });

    test('14 枚は色の切れ目のうち真ん中に近いところで折り返す', () {
      // 理牌後の splitHand（ツモの東を除く 13 枚）: 萬 3・筒 5・索 5。
      final tiles = '2m 3m 4m 3p 4p 5p 7p 8p 5s 6s 6s 6s 7s'.split(' ');
      expect(splitQuizRows(tiles, hasTsumo: true), [8, 5]);
    });

    test('色の切れ目が無ければ真ん中で折り返し、どの段も上限以下', () {
      final tiles = '1p 1p 1p 2p 3p 4p 5p 6p 7p 8p 9p 9p 9p'.split(' ');
      final rows = splitQuizRows(tiles, hasTsumo: true);
      expect(rows.reduce((a, b) => a + b), 13);
      expect(rows.first, lessThanOrEqualTo(QuizHand.maxPerRow));
      expect(rows.last + 1, lessThanOrEqualTo(QuizHand.maxPerRow));
    });
  });

  testWidgets('牌の当たり判定は 44pt 以上（幅 375pt の端末でも）', (tester) async {
    final h = await pumpScreens(tester);
    tester.view.physicalSize = const Size(375, 812);
    await h.push(Routes.quiz, QuizArgs(input: splitHand));
    for (var i = 0; i < 14; i++) {
      final size = tester.getSize(find.byKey(ValueKey('quiz-tile-$i')));
      expect(size.width, greaterThanOrEqualTo(44), reason: 'quiz-tile-$i');
      expect(size.height, greaterThanOrEqualTo(44), reason: 'quiz-tile-$i');
    }
    // 選んだ牌には「切る」の札が付く。
    expect(find.text('切る'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('quiz-tile-3')));
    await tester.pumpAndSettle();
    expect(find.text('切る'), findsOneWidget);
  });
}
