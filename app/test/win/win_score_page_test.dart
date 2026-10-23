// 和了の役と点数（Pro）の画面。点数は手で検算した値（Mリーグ相当のルール）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/win/win_score_page.dart';

import '../screens/screens_harness.dart';

/// 子の門前・平和・断么九の手（234m 567m 345p 678s 66s、和了牌 3p）。ドラ表示 1m → ドラ 2m。
final _pinfu = HandInput(
  tiles: const [
    '2m', '3m', '4m', '5m', '6m', '7m', //
    '4p', '5p', '6s', '7s', '8s', '6s', '6s', '3p',
  ],
  tsumoIndex: 13,
  doraIndicators: const ['1m'],
);

final Map<String, WidgetBuilder> _winPage = {
  Routes.winScore: (_) => const WinScorePage(),
};

Future<ScreenHarness> _open(
  WidgetTester tester,
  HandInput input, {
  bool pro = true,
  Locale locale = const Locale('ja'),
  RecordingAnalyticsBackend? analytics,
  String source = 'manual',
}) async {
  final h = await pumpScreens(
    tester,
    pro: pro,
    locale: locale,
    analytics: analytics,
    pages: _winPage,
  );
  await h.push(Routes.winScore, WinScoreArgs(input: input, source: source));
  return h;
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

Future<void> _tap(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('win-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _chipEnabled(WidgetTester tester, String key) =>
    tester.widget<FilterChip>(find.byKey(ValueKey(key))).onSelected != null;

bool _chipSelected(WidgetTester tester, String key) =>
    tester.widget<FilterChip>(find.byKey(ValueKey(key))).selected;

void main() {
  testWidgets('初期表示: ツモ牌が和了牌、子の門前ツモ・平和・断么九・ドラ1 = 4翻20符 1,300・2,600', (
    tester,
  ) async {
    final analytics = RecordingAnalyticsBackend();
    await _open(tester, _pinfu, analytics: analytics, source: 'photo');
    // 和了牌（3p, 添字 13）が朱の枠で右端（札「和了牌」つき）。
    expect(find.byKey(const ValueKey('win-tile-13')), findsOneWidget);
    expect(find.text('和了牌'), findsOneWidget);
    expect(_text(tester, 'win-who'), '子のツモ');
    expect(_text(tester, 'win-rank'), '4翻20符');
    expect(_text(tester, 'win-total'), '5,200点');
    expect(_text(tester, 'win-payment'), '1,300・2,600');
    expect(find.byKey(const ValueKey('win-yaku-menzenTsumo')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-yaku-pinfu')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-yaku-tanyao')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-dora')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-breakdown')), findsNothing);
    expect(analytics.named('win_score_viewed'), [
      {'source': 'photo'},
    ]);
  });

  testWidgets('ツモ/ロンの切り替えで点数が変わる（平和ロンは 30 符 3 翻 3,900）', (tester) async {
    await _open(tester, _pinfu);
    await _tap(tester, 'win-type-ron');
    expect(_text(tester, 'win-who'), '子のロン');
    expect(_text(tester, 'win-rank'), '3翻30符');
    expect(_text(tester, 'win-total'), '3,900点');
    expect(_text(tester, 'win-payment'), '3,900');
    expect(find.byKey(const ValueKey('win-yaku-menzenTsumo')), findsNothing);
  });

  testWidgets('リーチで満貫ツモ 2,000・4,000、一発・裏ドラが選べるようになる', (tester) async {
    await _open(tester, _pinfu);
    expect(_chipEnabled(tester, 'win-ippatsu'), isFalse);
    expect(find.byKey(const ValueKey('win-ura-row')), findsNothing);

    await _tap(tester, 'win-riichi-riichi');
    expect(_text(tester, 'win-rank'), '満貫');
    expect(_text(tester, 'win-total'), '8,000点');
    expect(_text(tester, 'win-payment'), '2,000・4,000');
    expect(find.byKey(const ValueKey('win-yaku-riichi')), findsOneWidget);
    expect(_chipEnabled(tester, 'win-ippatsu'), isTrue);
    expect(find.byKey(const ValueKey('win-ura-row')), findsOneWidget);

    // 一発を付けてからリーチをやめると、一発も外れる。
    await _tap(tester, 'win-ippatsu');
    expect(find.byKey(const ValueKey('win-yaku-ippatsu')), findsOneWidget);
    await _tap(tester, 'win-riichi-none');
    expect(_chipSelected(tester, 'win-ippatsu'), isFalse);
    expect(_text(tester, 'win-rank'), '4翻20符');
  });

  testWidgets('本場・供託を足すと内訳が出る（リーチ・ロン 7,700 ＋ 300 ＋ 1,000）', (tester) async {
    await _open(tester, _pinfu);
    await _tap(tester, 'win-type-ron');
    await _tap(tester, 'win-riichi-riichi');
    expect(_text(tester, 'win-total'), '7,700点');
    await _tap(tester, 'win-more');
    await _tap(tester, 'win-honba-plus');
    await _tap(tester, 'win-kyotaku-plus');
    expect(_text(tester, 'win-honba-value'), '1本場');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('win-total')),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(_text(tester, 'win-total'), '9,000点');
    expect(_text(tester, 'win-payment'), '8,000');
    expect(
      _text(tester, 'win-breakdown'),
      '素点 7,700 ＋ 本場 300 ＋ 供託 1,000 ＝ 9,000点',
    );
  });

  testWidgets('和了牌を選び直す: 6m（嵌張）なら平和が消えて 3翻30符 1,000・2,000', (tester) async {
    await _open(tester, _pinfu);
    await tester.tap(find.byKey(const ValueKey('win-tile-4')));
    await tester.pumpAndSettle();
    expect(_text(tester, 'win-rank'), '3翻30符');
    expect(_text(tester, 'win-payment'), '1,000・2,000');
    expect(find.byKey(const ValueKey('win-yaku-pinfu')), findsNothing);
    expect(find.text('嵌張待ち'), findsOneWidget);
  });

  testWidgets('待ちの取り方で点数が変わる手は一言出す（3455s の 5s）', (tester) async {
    final input = HandInput(
      tiles: const [
        '2m', '3m', '4m', '5m', '6m', '7m', //
        '6p', '7p', '8p', '3s', '4s', '5s', '5s', '5s',
      ],
      tsumoIndex: 13,
    );
    await _open(tester, input);
    expect(find.byKey(const ValueKey('win-alternative')), findsOneWidget);
    expect(find.textContaining('両面待ちで計算'), findsOneWidget);
  });

  testWidgets('偶然役: 海底はツモだけ、ロンにすると外れて河底が選べる。嶺上は槓がないと選べない', (tester) async {
    await _open(tester, _pinfu);
    await _tap(tester, 'win-more');
    expect(_chipEnabled(tester, 'win-sit-haitei'), isTrue);
    expect(_chipEnabled(tester, 'win-sit-houtei'), isFalse);
    expect(_chipEnabled(tester, 'win-sit-rinshan'), isFalse);
    expect(_chipEnabled(tester, 'win-sit-tenhou'), isFalse); // 子
    expect(_chipEnabled(tester, 'win-sit-chiihou'), isTrue);
    await _tap(tester, 'win-sit-haitei');
    expect(_chipSelected(tester, 'win-sit-haitei'), isTrue);
    await _tap(tester, 'win-type-ron');
    expect(_chipSelected(tester, 'win-sit-haitei'), isFalse);
    expect(_chipEnabled(tester, 'win-sit-houtei'), isTrue);
  });

  testWidgets('役なし: 副露してドラだけの手は「役がありません」', (tester) async {
    final input = HandInput(
      tiles: const [
        '4p', '5p', '6p', '7p', '8p', '9p', '2s', '3s', '4s', '5s', '5s', //
      ],
      tsumoIndex: 10,
      melds: [
        MeldInput(kind: MeldKind.chi, tiles: const ['1m', '2m', '3m']),
      ],
      doraIndicators: const ['4s'],
    );
    await _open(tester, input);
    expect(find.text('役がありません'), findsOneWidget);
    expect(find.byKey(const ValueKey('win-error-noYaku')), findsOneWidget);
    // 手牌の誤りではないので「手牌を直す」の操作は出さない。共有はできない。
    expect(find.byKey(const ValueKey('win-error-edit')), findsNothing);
    final share = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('win-share')),
    );
    expect(share.onPressed, isNull);
    // 副露しているのでリーチはかけられない。
    expect(find.byKey(const ValueKey('win-riichi-open')), findsOneWidget);
  });

  testWidgets('和了形でない: 「和了形ではありません」と、手入力（点数計算モード）へ戻る導線', (tester) async {
    final input = HandInput(
      tiles: const [
        '2m', '3m', '4m', '5m', '6m', '7m', //
        '6p', '7p', '8p', '3s', '4s', '5s', '2p', '9p',
      ],
      tsumoIndex: 13,
    );
    final h = await _open(tester, input);
    expect(find.text('和了形ではありません'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('win-error-edit')));
    await tester.pumpAndSettle();
    final args = h.routes.lastArgs(Routes.manualInput)! as RecognitionArgs;
    expect(args.mode, HandEntryMode.score);
    expect(args.draft.labels, input.tiles);
    expect(args.draft.tsumoIndex, 13);
  });

  testWidgets('13 枚で開いても「和了形ではありません」', (tester) async {
    await _open(tester, HandInput(tiles: _pinfu.tiles.take(13)));
    expect(find.text('和了形ではありません'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('win-error-wrongTileCount')),
      findsOneWidget,
    );
  });

  testWidgets('役満: 四暗刻ツモ 8,000・16,000、吸収された役は薄く', (tester) async {
    final input = HandInput(
      tiles: const [
        '2m', '2m', '2m', '4p', '4p', '4p', '6s', '6s', //
        '8s', '8s', '8s', '1p', '1p', '6s',
      ],
      tsumoIndex: 13,
    );
    await _open(tester, input);
    expect(_text(tester, 'win-rank'), '役満');
    expect(_text(tester, 'win-total'), '32,000点');
    expect(_text(tester, 'win-payment'), '8,000・16,000');
    expect(find.byKey(const ValueKey('win-yaku-suuankou')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-suppressed')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-fu')), findsNothing);
  });

  testWidgets('親のツモは「N オール」', (tester) async {
    await _open(tester, _pinfu.withSeatWind(Wind.east));
    expect(_text(tester, 'win-who'), '親のツモ');
    // 4翻20符の親ツモ 2,600 オール
    expect(_text(tester, 'win-payment'), '2,600オール');
    expect(_text(tester, 'win-total'), '7,800点');
  });

  testWidgets('共有: 計算結果を共有カードに渡し、win_score_shared{kind} を記録', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final h = await _open(tester, _pinfu, analytics: analytics);
    await tester.tap(find.byKey(const ValueKey('win-share')));
    await tester.pumpAndSettle();
    final args = h.routes.lastArgs(Routes.shareCard)! as ShareCardArgs;
    expect(args.kind, ShareCardKind.win);
    final data = args.winShare!;
    expect(data.result.payment.total, 5200);
    expect(data.hand.tsumoTile, '3p');
    expect(analytics.named('win_score_shared').last, {
      'kind': 'win',
      'rank': 'none',
    });

    Navigator.of(tester.element(find.text('route:/share'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('win-share-quiz')));
    await tester.pumpAndSettle();
    final quiz = h.routes.lastArgs(Routes.shareCard)! as ShareCardArgs;
    expect(quiz.kind, ShareCardKind.winQuiz);
    expect(analytics.named('win_score_shared').last['kind'], 'win_quiz');
    expect(data, isA<WinShareData>());
  });

  testWidgets('無料: Pro の案内だけを出し、Paywall（winScore）へ', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final h = await _open(tester, _pinfu, pro: false, analytics: analytics);
    expect(find.byKey(const ValueKey('win-locked')), findsOneWidget);
    expect(find.byKey(const ValueKey('win-hero')), findsNothing);
    expect(analytics.named('win_score_viewed'), isEmpty);
    await tester.tap(find.byKey(const ValueKey('win-go-pro')));
    await tester.pumpAndSettle();
    expect(
      (h.routes.lastArgs(Routes.paywall)! as PaywallArgs).trigger,
      PaywallTrigger.winScore,
    );
  });

  testWidgets('英語', (tester) async {
    await _open(tester, _pinfu, locale: const Locale('en'));
    expect(find.text('Yaku & points'), findsOneWidget);
    expect(_text(tester, 'win-who'), 'Non-dealer tsumo');
    expect(_text(tester, 'win-rank'), '4 han 20 fu');
    expect(_text(tester, 'win-total'), '5,200 pts');
    await _tap(tester, 'win-riichi-riichi');
    expect(_text(tester, 'win-rank'), 'Mangan');
    expect(find.text('Riichi'), findsWidgets);
  });
}
