// 和了の役と点数（Pro）の入口: Result・Home・修正画面の点数計算モード。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ui/home/home_page.dart';

import '../screens/screens_harness.dart';

void main() {
  group('Result', () {
    testWidgets('Pro: 和了形なら WinCard の直下に「役と点数を詳しく見る」→ 和了の点数画面', (tester) async {
      final h = await pumpScreens(tester, pro: true);
      await h.push(Routes.result, ResultArgs(input: winHand));
      final entry = find.byKey(const ValueKey('result-win-score'));
      expect(entry, findsOneWidget);
      final card = tester.getRect(find.byKey(const ValueKey('result-win')));
      expect(tester.getRect(entry).top, greaterThan(card.bottom));
      await tester.tap(entry);
      await tester.pumpAndSettle();
      final args = h.routes.lastArgs(Routes.winScore)! as WinScoreArgs;
      expect(args.source, 'result');
      expect(args.input, winHand);
    });

    testWidgets('無料: 鍵つきで Paywall（winScore）へ', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: winHand));
      expect(find.byIcon(Icons.lock_outline), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('result-win-score')));
      await tester.pumpAndSettle();
      expect(h.routes.contains(Routes.winScore), isFalse);
      expect(
        (h.routes.lastArgs(Routes.paywall)! as PaywallArgs).trigger,
        PaywallTrigger.winScore,
      );
    });

    testWidgets('和了形でない 14 枚には出さない', (tester) async {
      final h = await pumpScreens(tester, pro: true);
      await h.push(Routes.result, ResultArgs(input: splitHand));
      expect(find.byKey(const ValueKey('result-win-score')), findsNothing);
    });
  });

  group('Home', () {
    Future<ScreenHarness> pumpHome(WidgetTester tester, {bool pro = false}) =>
        pumpScreens(
          tester,
          pro: pro,
          overrides: [
            clockProvider.overrideWithValue(() => DateTime(2026, 10, 21, 20)),
            onlineFeaturesProvider.overrideWithValue(false),
          ],
          home: const HomePage(),
        );

    testWidgets('写真で解析の横に点数計算（2 列）。Pro はカメラを点数計算モードで開く', (tester) async {
      final h = await pumpHome(tester, pro: true);
      final photo = tester.getRect(find.byKey(const ValueKey('home-photo')));
      final score = tester.getRect(find.byKey(const ValueKey('home-score')));
      expect(score.top, photo.top);
      expect(score.left, greaterThan(photo.right));
      expect(find.byKey(const ValueKey('home-app-mark')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-score')));
      await tester.pumpAndSettle();
      final args = h.routes.lastArgs(Routes.camera)! as CameraArgs;
      expect(args.mode, HandEntryMode.score);
    });

    testWidgets('無料は Paywall（winScore）', (tester) async {
      final h = await pumpHome(tester);
      expect(find.text('Pro の機能'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-score')));
      await tester.pumpAndSettle();
      expect(h.routes.contains(Routes.camera), isFalse);
      expect(
        (h.routes.lastArgs(Routes.paywall)! as PaywallArgs).trigger,
        PaywallTrigger.winScore,
      );
    });
  });

  group('修正画面の点数計算モード', () {
    RecognitionArgs args(List<String> labels, {int? tsumo}) => RecognitionArgs(
      draft: RecognitionDraft(labels: labels, tsumoIndex: tsumo),
      mode: HandEntryMode.score,
    );

    testWidgets('「点数を計算」で和了の点数画面へ（巡目は出さない）', (tester) async {
      final h = await pumpScreens(
        tester,
        pro: true,
        pages: realRecognitionPage,
      );
      await h.push(Routes.recognition, args(winHand.tiles, tsumo: 13));
      expect(find.text('点数を計算'), findsOneWidget);
      expect(find.byKey(const ValueKey('recognition-turn-plus')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recognition-preview')))
            .data,
        '和了形です（和了牌: 5索）',
      );
      await tester.tap(find.byKey(const ValueKey('recognition-next')));
      await tester.pumpAndSettle();
      final win = h.routes.lastArgs(Routes.winScore)! as WinScoreArgs;
      expect(win.fromEditor, isTrue);
      expect(win.input.tsumoTile, '5s');
      expect(win.input.tileCount, 14);
      expect(h.routes.contains(Routes.quiz), isFalse);
    });

    testWidgets('和了牌が未指定なら指定を促す', (tester) async {
      final h = await pumpScreens(
        tester,
        pro: true,
        pages: realRecognitionPage,
      );
      await h.push(Routes.recognition, args(winHand.tiles));
      expect(
        find.byKey(const ValueKey('recognition-tsumo-hint')),
        findsOneWidget,
      );
      expect(find.textContaining('和了牌（ツモった牌・ロンした牌）'), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('recognition-preview')))
            .data,
        '和了形です。和了牌を指定してください（未指定なら最後の牌）',
      );
    });

    testWidgets('13 枚・和了形でない 14 枚では進めない', (tester) async {
      final h = await pumpScreens(
        tester,
        pro: true,
        pages: realRecognitionPage,
      );
      await h.push(Routes.recognition, args(winHand.tiles.take(13).toList()));
      String preview() => tester
          .widget<Text>(find.byKey(const ValueKey('recognition-preview')))
          .data!;
      bool enabled() => tester
          .widget<ButtonStyleButton>(
            find.byKey(const ValueKey('recognition-next')),
          )
          .enabled;
      expect(preview(), '和了牌を足して14枚にしてください');
      expect(enabled(), isFalse);

      await h.push(Routes.recognition, args(splitHand.tiles, tsumo: 13));
      expect(preview(), startsWith('和了形ではありません'));
      expect(enabled(), isFalse);
    });

    testWidgets('既定のモード（何切る）は今までどおり「この手を解く」', (tester) async {
      final h = await pumpScreens(
        tester,
        pro: true,
        pages: realRecognitionPage,
      );
      await h.push(
        Routes.recognition,
        RecognitionArgs(
          draft: RecognitionDraft(labels: winHand.tiles, tsumoIndex: 13),
        ),
      );
      expect(find.text('この手を解く'), findsOneWidget);
      expect(find.text('点数を計算'), findsNothing);
      expect(
        find.byKey(const ValueKey('recognition-turn-plus')),
        findsOneWidget,
      );
    });
  });

  test('HandInput の和了の手（テストの前提）', () {
    expect(winHand.isFourteen, isTrue);
    expect(winHand.tsumoTile, '5s');
    expect(HandEntryMode.values, hasLength(2));
  });
}
