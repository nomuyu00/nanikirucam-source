import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/hand_panel.dart';
import 'package:nanikiru_cam/share/cards/live_milestone_card.dart';
import 'package:nanikiru_cam/share/cards/live_summary_card.dart';
import 'package:nanikiru_cam/share/cards/problem_card.dart';
import 'package:nanikiru_cam/share/cards/result_card.dart';
import 'package:nanikiru_cam/share/cards/streak_card.dart';
import 'package:nanikiru_cam/share/cards/weekly_card.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/share/share_links.dart';
import 'package:nanikiru_cam/share/share_service.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

import '../problems/fakes.dart';

const ja = ShareStrings(AppLang.ja);
const en = ShareStrings(AppLang.en);
const problemUrl = 'https://nanikiru-cam.web.app/p/AbC12345?ref=ABCD2345';

Future<void> pumpCard(WidgetTester tester, Widget card) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: card)),
    ),
  );
  await tester.pump();
}

Finder byKey(String key) => find.byKey(ValueKey(key));

CardQr qr(WidgetTester tester) => tester.widget<CardQr>(find.byType(CardQr));

void main() {
  final hand = sampleHand().normalized();

  group('問題カード（答えを隠した出題画像）', () {
    Widget card({
      ShareCardFormat format = ShareCardFormat.square,
      bool watermark = false,
      int answerCount = 0,
      HandInput? input,
      String author = 'まじゃおう',
      ShareStrings strings = ja,
      String qrUrl = problemUrl,
    }) => ProblemCard(
      input: input ?? hand,
      authorName: author,
      qrUrl: qrUrl,
      format: format,
      strings: strings,
      watermark: watermark,
      answerCount: answerCount,
    );

    for (final format in ShareCardFormat.values) {
      testWidgets('${format.name}: 設計書 8 章の要素がそろっている', (tester) async {
        await pumpCard(tester, card(format: format));
        expect(tester.takeException(), isNull, reason: 'はみ出しなし');

        expect(find.text('この手、何切る？'), findsOneWidget);
        // 牌パネル 14 枚 + ドラ表示牌 1 枚。
        expect(find.byType(TileImage), findsNWidgets(15));
        // ツモ牌を金枠で離す。
        expect(byKey('hand-panel-tsumo'), findsOneWidget);
        // ドラ・風・巡目。
        expect(find.text('東場 南家 6巡目'), findsOneWidget);
        expect(find.text('ドラ表示'), findsOneWidget);
        // 出題者名。
        expect(find.text('出題: まじゃおう'), findsOneWidget);
        // アプリ名とストア誘導。
        expect(find.text('なにきるカム'), findsOneWidget);
        expect(byKey('share-card-store-lead'), findsOneWidget);
        expect(find.text('解説はアプリで'), findsOneWidget);
        expect(byKey('share-card-store-guide'), findsOneWidget);
        // 左上のロゴはアプリのアイコン（画像）。
        expect(
          find.descendant(
            of: byKey('share-card-logo'),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );
        // QR は問題ページ（/p/{id}?ref=）。
        expect(qr(tester).url, problemUrl);
        expect(find.text('スキャンして答える'), findsOneWidget);
        // 論理サイズは 1080px 幅に書き出せる比率。
        final size = tester.getSize(find.byType(ShareCardFrame));
        expect(size, format.logicalSize);
        expect(size.width * format.pixelRatio, 1080);
      });
    }

    testWidgets('QR がストアの URL（問題 URL でない）ときは「スキャンしてアプリへ」', (tester) async {
      final storeUrl = ShareLinks.storeUrl(
        campaign: 'problem',
        platform: TargetPlatform.android,
      );
      expect(ShareLinks.isProblemUrl(storeUrl), isFalse);
      expect(ShareLinks.isProblemUrl(problemUrl), isTrue);
      await pumpCard(tester, card(qrUrl: storeUrl));
      expect(qr(tester).url, storeUrl);
      expect(find.text('スキャンしてアプリへ'), findsOneWidget);
      expect(find.text('スキャンして答える'), findsNothing);

      await pumpCard(tester, card(qrUrl: storeUrl, strings: en));
      expect(find.text('Scan to get the app'), findsOneWidget);
      expect(find.text('Scan to answer'), findsNothing);
    });

    testWidgets('答え（正解・受け入れ）は載せない', (tester) async {
      await pumpCard(tester, card());
      expect(find.textContaining('正解'), findsNothing);
      expect(find.textContaining('受け入れ'), findsNothing);
      expect(find.textContaining('答えは'), findsNothing);
    });

    testWidgets('透かしは無料のときだけ', (tester) async {
      await pumpCard(tester, card(watermark: true));
      expect(byKey('share-card-watermark'), findsOneWidget);
      await pumpCard(tester, card(watermark: false));
      expect(byKey('share-card-watermark'), findsNothing);
    });

    testWidgets('副露は横向きの牌で並ぶ。ドラ表示牌は複数', (tester) async {
      await pumpCard(tester, card(input: meldHand().normalized()));
      final tiles = tester
          .widgetList<TileImage>(find.byType(TileImage))
          .toList();
      // 手牌 11 + 副露 3 + ドラ表示 2。
      expect(tiles, hasLength(16));
      expect(tiles.where((t) => t.sideways), hasLength(1));
      expect(find.text('ドラ表示'), findsOneWidget);
    });

    testWidgets('ドラ表示牌が無ければドラの行は出ない。出題者名が空なら匿名', (tester) async {
      await pumpCard(
        tester,
        card(
          input: sampleHand().copyWith(doraIndicators: const []).normalized(),
          author: ' ',
        ),
      );
      expect(find.text('ドラ表示'), findsNothing);
      expect(find.text('出題: 匿名'), findsOneWidget);
    });

    testWidgets('回答数は 1 以上のときだけ載せる（再共有）', (tester) async {
      await pumpCard(tester, card(answerCount: 0));
      expect(find.textContaining('人が回答'), findsNothing);
      await pumpCard(tester, card(answerCount: 52));
      expect(find.text('52人が回答'), findsOneWidget);
    });

    testWidgets('英語でも同じ要素が出る', (tester) async {
      await pumpCard(tester, card(strings: en));
      expect(find.text('What would you discard?'), findsOneWidget);
      expect(find.text('By まじゃおう'), findsOneWidget);
      expect(find.text('East round · South seat · turn 6'), findsOneWidget);
      expect(find.text('Scan to answer'), findsOneWidget);
    });

    testWidgets('親・巡目なしの条件', (tester) async {
      final dealer = sampleHand(turn: null).withSeatWind(Wind.east);
      expect(ja.conditions(dealer), '東場 東家（親）');
      expect(ja.conditions(sampleHand()), '東場 南家 6巡目');
    });
  });

  group('結果カード', () {
    final report = analyzeHand(hand);

    test('ResultCardData: 正解はバランス軸の 1 位（5m）。選んだ牌と受け入れを比べる', () {
      final correct = ResultCardData.fromReport(
        input: hand,
        report: report,
        chosenDiscardId: tileIdFromLabel('5m'),
        communityPercent: 23,
        streak: 5,
      );
      expect(correct.chosen, '5m');
      expect(correct.correctTiles, ['5m']);
      expect(correct.isCorrect, isTrue);
      expect(correct.matchedAxis, isNull);
      expect(correct.chosenUkeire, 31);
      expect(correct.correctUkeire, 31);
      expect(correct.communityPercent, 23);
      expect(correct.streak, 5);

      // 9p は速さ軸の 1 位（テンパイ）。バランスでは不正解だが「速さ重視なら正解」。
      final speed = ResultCardData.fromReport(
        input: hand,
        report: report,
        chosenDiscardId: tileIdFromLabel('9p'),
      );
      expect(speed.chosen, '9p');
      expect(speed.isCorrect, isFalse);
      expect(speed.matchedAxis, StrategyAxis.speed);
      expect(speed.chosenUkeire, 8);
      expect(speed.correctUkeire, 31);

      final wrong = ResultCardData.fromReport(
        input: hand,
        report: report,
        chosenDiscardId: tileIdFromLabel('1m'),
      );
      expect(wrong.chosen, '1m');
      expect(wrong.isCorrect, isFalse);
      expect(wrong.matchedAxis, isNull);
      expect(wrong.chosenUkeire, lessThan(wrong.correctUkeire!));

      final skipped = ResultCardData.fromReport(input: hand, report: report);
      expect(skipped.chosen, isNull);
      expect(skipped.isCorrect, isNull);
      expect(skipped.chosenUkeire, isNull);
      expect(skipped.correctTiles, ['5m']);
    });

    Widget card(
      ResultCardData data, {
      ShareCardFormat format = ShareCardFormat.square,
    }) =>
        ResultCard(data: data, qrUrl: problemUrl, format: format, strings: ja);

    for (final format in ShareCardFormat.values) {
      testWidgets('${format.name}: あなた／正解／受け入れ／正解率／ストリーク', (tester) async {
        final data = ResultCardData.fromReport(
          input: hand,
          report: report,
          chosenDiscardId: tileIdFromLabel('1m'),
          communityPercent: 23,
          streak: 5,
        );
        await pumpCard(tester, card(data, format: format));
        expect(tester.takeException(), isNull);
        expect(find.text('惜しい！'), findsOneWidget);
        expect(byKey('result-card-you'), findsOneWidget);
        expect(byKey('result-card-answer'), findsOneWidget);
        expect(
          find.text(ja.ukeireVs(data.chosenUkeire!, data.correctUkeire!)),
          findsOneWidget,
        );
        expect(find.text('みんなの正解率 23%'), findsOneWidget);
        expect(find.text('連続 5日'), findsOneWidget);
        expect(qr(tester).url, problemUrl);
      });
    }

    testWidgets('正解のとき', (tester) async {
      final data = ResultCardData.fromReport(
        input: hand,
        report: report,
        chosenDiscardId: tileIdFromLabel('5m'),
      );
      await pumpCard(tester, card(data));
      expect(find.text('正解！'), findsOneWidget);
      expect(byKey('result-card-community'), findsNothing);
      expect(byKey('result-card-streak'), findsNothing);
    });

    testWidgets('選んでいないとき: 正解だけを載せる', (tester) async {
      final data = ResultCardData.fromReport(input: hand, report: report);
      await pumpCard(tester, card(data));
      expect(find.text('この手の正解は'), findsOneWidget);
      expect(byKey('result-card-you'), findsNothing);
      expect(byKey('result-card-answer'), findsOneWidget);
      expect(find.text('受け入れ 31枚'), findsOneWidget);
    });

    testWidgets('別の軸の解なら「打点重視なら正解」', (tester) async {
      final data = ResultCardData(
        input: hand,
        chosen: '5m',
        correctTiles: const ['9p'],
        chosenUkeire: 16,
        correctUkeire: 24,
        matchedAxis: StrategyAxis.points,
      );
      await pumpCard(tester, card(data));
      expect(find.text('打点重視なら正解'), findsOneWidget);
      expect(find.text('受け入れ 16枚 vs 24枚'), findsOneWidget);
    });

    testWidgets('透かしは無料のときだけ', (tester) async {
      final data = ResultCardData.fromReport(input: hand, report: report);
      await pumpCard(
        tester,
        ResultCard(
          data: data,
          qrUrl: problemUrl,
          format: ShareCardFormat.square,
          strings: ja,
          watermark: true,
        ),
      );
      expect(byKey('share-card-watermark'), findsOneWidget);
    });
  });

  group('ライブ・ストリーク・週間のカード', () {
    for (final format in ShareCardFormat.values) {
      testWidgets('${format.name}: ライブ節目（初和了）', (tester) async {
        await pumpCard(
          tester,
          LiveMilestoneCard(
            win: const LiveWinSummary(
              han: 4,
              fu: 40,
              points: 8000,
              yaku: ['リーチ', '平和', 'ドラ3'],
            ),
            firstWin: true,
            qrUrl: 'https://store',
            format: format,
            strings: ja,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('ナビ付きで初和了！'), findsOneWidget);
        expect(find.text('満貫'), findsOneWidget);
        expect(find.text('4翻40符'), findsOneWidget);
        expect(find.text('8000点'), findsOneWidget);
        expect(find.text('リーチ'), findsOneWidget);
        expect(find.text('ナビで打った'), findsOneWidget);
        // ライブは友人戦・練習用と明記する（仕様 8.4）。
        expect(find.text('友人戦・練習用'), findsOneWidget);
        expect(qr(tester).url, 'https://store');
      });

      testWidgets('${format.name}: ライブのサマリー', (tester) async {
        await pumpCard(
          tester,
          LiveSummaryCard(
            summary: LiveSummaryArgs(
              startedAt: DateTime(2026, 10, 21),
              durationSec: 1500,
              adviceCount: 20,
              followedCount: 15,
              wins: const [
                LiveWinSummary(han: 1, fu: 30, points: 1000),
                LiveWinSummary(han: 3, fu: 30, points: 3900, yaku: ['タンヤオ']),
              ],
            ),
            qrUrl: 'https://store',
            format: format,
            strings: ja,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('今日の成果'), findsOneWidget);
        expect(find.text('25分'), findsOneWidget);
        expect(find.text('ナビの案内 20回'), findsOneWidget);
        expect(find.text('採用 15回（75%）'), findsOneWidget);
        expect(find.text('和了 2回'), findsOneWidget);
        expect(find.text('最高 3900点'), findsOneWidget);
        expect(find.text('友人戦・練習用'), findsOneWidget);
      });

      testWidgets('${format.name}: ストリーク', (tester) async {
        await pumpCard(
          tester,
          StreakCard(
            streak: const StreakState(current: 30, best: 45),
            qrUrl: 'https://store',
            format: format,
            strings: ja,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('30日'), findsOneWidget);
        expect(find.text('自己ベスト 45日'), findsOneWidget);
      });

      testWidgets('${format.name}: 週間（今週の難問の結果）', (tester) async {
        await pumpCard(
          tester,
          WeeklyCard(
            summary: WeeklySummary(
              weekStart: DateTime(2026, 10, 19),
              answered: 20,
              correct: 14,
              hardProblems: const [
                WeeklyProblemResult(correct: true, communityRate: 0.18),
                WeeklyProblemResult(correct: false, communityRate: 0.31),
              ],
            ),
            qrUrl: 'https://store',
            format: format,
            strings: ja,
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.text('今週の成績'), findsOneWidget);
        expect(find.text('正解率 70%'), findsOneWidget);
        expect(find.text('20問に挑戦'), findsOneWidget);
        expect(find.text('正解 14問'), findsOneWidget);
        expect(find.text('10/19 - 10/25'), findsOneWidget);
        expect(find.text('みんなの正解率 18%'), findsOneWidget);
        expect(find.text('不正解'), findsOneWidget);
      });
    }

    testWidgets('回答がまだない週は件数だけ', (tester) async {
      await pumpCard(
        tester,
        WeeklyCard(
          summary: WeeklySummary(weekStart: DateTime(2026, 10, 19)),
          qrUrl: 'https://store',
          format: ShareCardFormat.square,
          strings: ja,
        ),
      );
      expect(byKey('weekly-card-accuracy'), findsOneWidget);
      expect(find.text('0問に挑戦'), findsWidgets);
      expect(find.text('今週の難問'), findsNothing);
    });

    test('和了のランク表示', () {
      expect(ja.winRank(1, 30), '');
      expect(ja.winRank(3, 30), '');
      expect(ja.winRank(3, 70), '満貫');
      expect(ja.winRank(4, 40), '満貫');
      expect(ja.winRank(5, 30), '満貫');
      expect(ja.winRank(6, 30), '跳満');
      expect(ja.winRank(8, 30), '倍満');
      expect(ja.winRank(11, 30), '三倍満');
      expect(ja.winRank(13, 30), '役満');
    });
  });

  group('HandPanel', () {
    testWidgets('ツモ牌がなければ金枠は出ない', (tester) async {
      await pumpCard(
        tester,
        HandPanel(input: sampleHand().copyWith(tsumoIndex: null)),
      );
      expect(byKey('hand-panel-tsumo'), findsNothing);
      expect(find.byType(TileImage), findsNWidgets(14));
    });
  });

  group('書き出し（幅 1080px の PNG）', () {
    final bundle = <String>{...hand.tiles, ...hand.doraIndicators};

    Future<Uint8List> render(
      WidgetTester tester,
      ShareCardFormat format,
    ) async {
      final key = GlobalKey();
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: ProblemCard(
                  input: hand,
                  authorName: 'まじゃおう',
                  qrUrl: problemUrl,
                  format: format,
                  strings: ja,
                  watermark: true,
                  answerCount: 12,
                ),
              ),
            ),
          ),
        ),
      );
      // 牌の画像を読み込んでから描く。
      await tester.runAsync(() async {
        final context = tester.element(find.byType(ProblemCard));
        for (final label in bundle) {
          final path = tileAssetPath(label);
          if (path != null) await precacheImage(AssetImage(path), context);
        }
      });
      await tester.pumpAndSettle();
      final png = await tester.runAsync(
        () =>
            const ShareService().captureNow(key, pixelRatio: format.pixelRatio),
      );
      return png!;
    }

    Future<(int, int)> dimensions(WidgetTester tester, Uint8List png) async {
      final size = await tester.runAsync(() async {
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        final result = (frame.image.width, frame.image.height);
        frame.image.dispose();
        return result;
      });
      return size!;
    }

    testWidgets('1:1 は 1080×1080、Storage の上限 900KB に収まる', (tester) async {
      final png = await render(tester, ShareCardFormat.square);
      expect(await dimensions(tester, png), (1080, 1080));
      expect(png.lengthInBytes, lessThan(900 * 1024));
      debugPrint('問題カード 1:1 の PNG: ${png.lengthInBytes} bytes');
    });

    testWidgets('9:16 は 1080×1920', (tester) async {
      final png = await render(tester, ShareCardFormat.story);
      expect(await dimensions(tester, png), (1080, 1920));
      debugPrint('問題カード 9:16 の PNG: ${png.lengthInBytes} bytes');
    });

    testWidgets('画面の外に置いたカードも書き出せる（公開画面の Storage 用 1:1）', (tester) async {
      // Offstage は描画されないので RepaintBoundary を書き出せない。公開画面は、
      // 画面の外（left: -4000）に描いたカードを書き出す。その構造を再現する。
      final key = GlobalKey();
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const SizedBox(height: 100),
                    Positioned(
                      left: -4000,
                      top: 0,
                      width: 360,
                      height: 360,
                      child: RepaintBoundary(
                        key: key,
                        child: ProblemCard(
                          input: hand,
                          authorName: 'まじゃおう',
                          qrUrl: problemUrl,
                          format: ShareCardFormat.square,
                          strings: ja,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final context = tester.element(find.byType(ProblemCard));
        for (final label in bundle) {
          final path = tileAssetPath(label);
          if (path != null) await precacheImage(AssetImage(path), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final png = await tester.runAsync(
        () => const ShareService().captureNow(key, pixelRatio: 3),
      );
      expect(await dimensions(tester, png!), (1080, 1080));
      // 白一色ではなく、牌や QR が描かれている。
      expect(png.lengthInBytes, greaterThan(50 * 1024));
    });
  });

  group('captureWithinLimit', () {
    test('上限を超えたら解像度を下げて撮り直す', () async {
      final service = _SizedShare();
      final png = await service.captureWithinLimit(
        GlobalKey(),
        pixelRatio: 3,
        maxBytes: 500,
      );
      // 3.0 → 2.55 → 2.1: 画素数に比例して 900 → 650 → 441 bytes。
      expect(service.ratios.first, 3);
      expect(png.lengthInBytes, lessThanOrEqualTo(500));
      expect(service.ratios, hasLength(3));
    });

    test('上限以下ならそのまま。最後まで超えるなら最小のものを返す', () async {
      final ok = _SizedShare();
      await ok.captureWithinLimit(GlobalKey(), pixelRatio: 3, maxBytes: 10000);
      expect(ok.ratios, [3]);

      final tooBig = _SizedShare();
      final png = await tooBig.captureWithinLimit(
        GlobalKey(),
        pixelRatio: 3,
        maxBytes: 10,
      );
      expect(tooBig.ratios, hasLength(4));
      expect(png.lengthInBytes, tooBig.smallest);
    });
  });
}

/// 画素数（pixelRatio の 2 乗）に比例した大きさの PNG を返す偽の ShareService。
class _SizedShare extends ShareService {
  final ratios = <double>[];
  int smallest = 1 << 30;

  @override
  Future<Uint8List> capture(GlobalKey key, {required double pixelRatio}) async {
    ratios.add(pixelRatio);
    final size = (pixelRatio * pixelRatio * 100).round();
    if (size < smallest) smallest = size;
    return Uint8List(size);
  }
}
