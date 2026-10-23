// 和了の役と点数の共有カード（通常・点数クイズ）と共有の本文。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/share_card_model.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

const _url = 'https://example.com/app';

/// 子の立直・門前ツモ・平和・断么九・ドラ1（234m 567m 345p 678s 66s、3p ツモ）= 満貫。
WinShareData _data({
  RiichiKind riichi = RiichiKind.riichi,
  int honba = 0,
  bool ippatsu = false,
}) {
  final input = HandInput(
    tiles: const [
      '2m', '3m', '4m', '5m', '6m', '7m', //
      '4p', '5p', '6s', '7s', '8s', '6s', '6s', '3p',
    ],
    tsumoIndex: 13,
    doraIndicators: const ['1m'],
  );
  final hand = WinHand.fromInput(input);
  final c = WinConditions.fromInput(
    input,
  ).copyWith(riichi: riichi, honba: honba, ippatsu: ippatsu);
  final outcome = scoreWin(WinScorer(Rulesets.mLeague()), hand, c);
  return WinShareData(
    hand: hand.toHandInput(c),
    request: buildWinRequest(hand, c),
    result: (outcome as WinScored).best,
  );
}

Future<ShareCardModel?> _resolve(ShareCardArgs args) => resolveShareCardModel(
  args,
  ShareCardSources(
    analyze: (_) => throw UnimplementedError(),
    fetchStats: (_) async => null,
    streak: const StreakState(),
    nickname: '',
  ),
);

Future<void> _pump(WidgetTester tester, Widget card) async {
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

void main() {
  const ja = ShareStrings(AppLang.ja);
  const en = ShareStrings(AppLang.en);

  test('満貫の検算: 立直・門前ツモ・平和・断么九・ドラ1 = 5翻 子 2,000・4,000', () {
    final r = _data().result;
    expect(r.han, 5);
    expect(r.rank, HandRank.mangan);
    expect(r.payment.tsumoFromChild, 2000);
    expect(r.payment.tsumoFromDealer, 4000);
    expect(r.payment.total, 8000);
  });

  test('ShareCardArgs から WinShareModel（通常・クイズ）を作る', () async {
    final data = _data();
    final win = await _resolve(
      ShareCardArgs(kind: ShareCardKind.win, winShare: data),
    );
    expect(win, isA<WinShareModel>());
    expect((win! as WinShareModel).quiz, isFalse);
    expect(win.analyticsVariant, 'win');
    final quiz = await _resolve(
      ShareCardArgs(kind: ShareCardKind.winQuiz, winShare: data),
    );
    expect((quiz! as WinShareModel).quiz, isTrue);
    expect(quiz.analyticsVariant, 'win_quiz');
    expect(
      await _resolve(const ShareCardArgs(kind: ShareCardKind.win)),
      isNull,
    );
  });

  test('共有の本文: 通常は段階名・点数・役。クイズは答えを書かない', () {
    final data = _data();
    expect(
      shareTextFor(WinShareModel(data), ja, url: _url),
      '【満貫 8,000点】立直・門前ツモ・断么九・平和・ドラ1 #なにきるカム\n$_url',
    );
    final quiz = shareTextFor(WinShareModel(data, quiz: true), ja, url: _url);
    expect(quiz, contains('この手、何点？'));
    expect(quiz, contains('子・ツモ・東場南家・立直'));
    expect(quiz, isNot(contains('8,000')));
    expect(quiz, isNot(contains('満貫')));
    expect(quiz, isNot(contains('平和')));
    expect(quiz, endsWith(_url));
    expect(
      shareTextFor(WinShareModel(data), en, url: _url),
      startsWith(
        '[Mangan 8,000 pts] Riichi, Self-draw, All simples, Pinfu, Dora 1',
      ),
    );
  });

  test('条件の 1 行: 一発・本場', () {
    final w = WinStrings(AppLang.ja);
    final r = _data(ippatsu: true, honba: 2).request;
    expect(w.conditionLine(r), '子・ツモ・東場南家・立直・一発・2本場');
  });

  testWidgets('通常のカード: 段階名と点数、支払い、役のチップ', (tester) async {
    await _pump(
      tester,
      buildShareCard(
        WinShareModel(_data()),
        format: ShareCardFormat.square,
        strings: ja,
        qrUrl: _url,
      ),
    );
    expect(find.text('満貫'), findsOneWidget);
    expect(find.text('8,000点'), findsOneWidget);
    expect(find.textContaining('2,000・4,000'), findsOneWidget);
    expect(find.text('立直 1翻'), findsOneWidget);
    expect(find.byKey(const ValueKey('win-card-winning')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-card-quiz')), findsNothing);
    // フッタは内容に合わせた誘導文、左上はアプリのアイコン。
    expect(find.text('点数計算はアプリで'), findsOneWidget);
    expect(find.text('解説はアプリで'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('share-card-logo')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点数クイズのカード: 点数・役を出さず「この手、何点？」', (tester) async {
    for (final format in ShareCardFormat.values) {
      await _pump(
        tester,
        buildShareCard(
          WinShareModel(_data(), quiz: true),
          format: format,
          strings: ja,
          qrUrl: _url,
          watermark: true,
        ),
      );
      expect(find.byKey(const ValueKey('win-card-quiz')), findsOneWidget);
      expect(find.text('この手、何点？'), findsOneWidget);
      expect(find.text('答えはアプリで'), findsOneWidget);
      expect(find.byKey(const ValueKey('win-card-rank')), findsNothing);
      expect(find.textContaining('8,000'), findsNothing);
      expect(find.text('立直 1翻'), findsNothing);
      // 条件（リーチ）は出す。
      expect(find.text('子・ツモ・東場南家・立直'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('share-card-watermark')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('英語・ストーリーでもあふれない', (tester) async {
    await _pump(
      tester,
      buildShareCard(
        WinShareModel(_data(honba: 3)),
        format: ShareCardFormat.story,
        strings: en,
        qrUrl: _url,
      ),
    );
    expect(find.text('Mangan'), findsOneWidget);
    expect(find.text('8,900 pts'), findsOneWidget);
    expect(find.text('Score your hands in the app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
