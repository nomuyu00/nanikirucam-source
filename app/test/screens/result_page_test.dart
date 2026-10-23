import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/result/result_logic.dart';

import 'screens_harness.dart';

const s = ResultStrings(AppLang.ja);
const text = ReasonText(AppLang.ja);

Finder inList(Finder f) =>
    find.descendant(of: find.byKey(const ValueKey('result-list')), matching: f);

/// 一覧を先頭に戻してから、[finder] が見えるまで下へスクロールする。
Future<void> scrollResultTo(WidgetTester tester, Finder finder) async {
  await tester.drag(
    find.byKey(const ValueKey('result-list')),
    const Offset(0, 6000),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const ValueKey('result-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

/// 候補カードの「詳しく」を開く（受け入れ牌・役・打点・上がりやすさは開いたときだけ出る）。
Future<void> openDetails(WidgetTester tester, int discardId) async {
  final more = find.byKey(ValueKey('candidate-more-$discardId'));
  await tester.ensureVisible(more);
  await tester.pumpAndSettle();
  await tester.tap(more);
  await tester.pumpAndSettle();
}

void main() {
  final id1z = tileIdFromLabel('1z');
  final id8p = tileIdFromLabel('8p');

  group('速さと打点で解が割れる手', () {
    late AnalysisReport free;
    late AnalysisReport deep;

    setUpAll(() {
      free = analyzeNow(splitHand);
      deep = analyzeNow(splitHand, deep: true);
      // 前提: エンジンで速さは打東、打点は打8筒（東を残す）。
      expect(free.bestByAxis[StrategyAxis.speed], [id1z]);
      expect(free.bestByAxis[StrategyAxis.points], [id8p]);
      expect(agreementOf(free), AnswerAgreement.split);
    });

    testWidgets('既定はバランス。軸を切り替えると 1 位とバッジ・並びが変わる', (tester) async {
      final analytics = RecordingAnalyticsBackend();
      final h = await pumpScreens(tester, analytics: analytics);
      await h.push(Routes.result, ResultArgs(input: splitHand));

      // 割れているので「一択」ではなく、軸ごとの答え。
      expect(find.byKey(const ValueKey('result-split')), findsOneWidget);
      expect(find.byKey(const ValueKey('result-one-choice')), findsNothing);
      // オンライン機能が無い版は「出題すると盛り上がります」と誘わない。
      expect(
        find.text(s.splitBody(speedVsPoints: true, online: false)),
        findsOneWidget,
      );
      expect(find.textContaining('出題すると'), findsNothing);

      // バランスの順位で並ぶ（最初のカードがバランス 1 位）。
      final balanceFirst = orderedCandidates(free, StrategyAxis.balance).first;
      Finder cards() => find.byWidgetPredicate(
        (w) =>
            w is Card &&
            w.key is ValueKey<String> &&
            (w.key! as ValueKey<String>).value.startsWith('candidate-'),
      );
      expect(
        tester.widget<Card>(cards().first).key,
        ValueKey('candidate-${balanceFirst.discardId}'),
      );
      // 結論（バランスの 1 位）を最上部のカードで大きく出す。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('result-conclusion')),
          matching: find.text(
            const CommonStrings(
              AppLang.ja,
            ).tileName(tileLabelOfId(balanceFirst.discardId)),
          ),
        ),
        findsOneWidget,
      );

      // バッジ: 東は最速、8筒は高打点。
      await scrollResultTo(tester, find.byKey(ValueKey('candidate-$id1z')));
      expect(find.byKey(ValueKey('badge-$id1z-speed')), findsOneWidget);
      expect(find.byKey(ValueKey('badge-$id1z-points')), findsNothing);
      await scrollResultTo(tester, find.byKey(ValueKey('candidate-$id8p')));
      expect(find.byKey(ValueKey('badge-$id8p-points')), findsOneWidget);
      expect(find.byKey(ValueKey('badge-$id8p-speed')), findsNothing);

      // 打点に切り替える。
      await tester.drag(
        find.byKey(const ValueKey('result-list')),
        const Offset(0, 6000),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('result-axis-points')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Card>(cards().first).key,
        ValueKey('candidate-$id8p'),
      );
      final changed = analytics.named('axis_changed');
      expect(changed.single, {
        'axis_from': 'balance',
        'axis_to': 'points',
        'screen': 'result',
      });

      // 速さに切り替えると東が先頭。
      await tester.tap(find.byKey(const ValueKey('result-axis-speed')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Card>(cards().first).key,
        ValueKey('candidate-$id1z'),
      );
    });

    testWidgets('無料: 上位 3 件、役は名前だけ、打点は目安、上がりやすさは高中低、鍵', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: splitHand));

      final ordered = orderedCandidates(free, StrategyAxis.balance);
      for (final c in ordered.take(3)) {
        await scrollResultTo(
          tester,
          find.byKey(ValueKey('candidate-${c.discardId}')),
        );
      }
      await scrollResultTo(
        tester,
        find.byKey(const ValueKey('result-more-locked')),
      );
      // 4 件目からは出さない。
      for (final c in ordered.skip(3)) {
        expect(find.byKey(ValueKey('candidate-${c.discardId}')), findsNothing);
      }
      expect(
        find.textContaining(s.moreLocked(free.candidates.length - 3)),
        findsOneWidget,
      );

      // 東の候補: 役は名前だけ（確度のラベルなし）。
      await scrollResultTo(tester, find.byKey(ValueKey('candidate-$id1z')));
      // 閉じているときは役・打点を出さない。
      expect(find.byKey(ValueKey('points-$id1z')), findsNothing);
      await openDetails(tester, id1z);
      final card1z = find.byKey(ValueKey('candidate-$id1z'));
      expect(
        find.descendant(of: card1z, matching: find.text('平和')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card1z, matching: find.textContaining('確定')),
        findsNothing,
      );
      final c1z = candidateOf(free, id1z)!;
      expect(
        tester.widget<Text>(find.byKey(ValueKey('points-$id1z'))).data,
        formatPointsLevel(c1z, s, dealer: false),
      );
      expect(
        tester.widget<Text>(find.byKey(ValueKey('ease-$id1z'))).data,
        s.winEaseLevel(winEaseLevel(c1z.winEase)),
      );
      // Pro の項目には鍵。
      expect(
        find.descendant(of: card1z, matching: find.byIcon(Icons.lock_outline)),
        findsWidgets,
      );
      // 下部のバナー（無料のみ）。
      expect(find.byType(AdBannerSlot), findsOneWidget);
    });

    testWidgets('鍵をタップすると Paywall（candidateLocked）', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: splitHand));
      await scrollResultTo(
        tester,
        find.byKey(const ValueKey('result-more-locked')),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('result-more-locked')),
          matching: find.byIcon(Icons.lock_outline),
        ),
      );
      await tester.pumpAndSettle();
      final args = h.routes.lastArgs(Routes.paywall) as PaywallArgs;
      expect(args.trigger, PaywallTrigger.candidateLocked);
    });

    testWidgets('Pro: 全候補、役の確度と成立条件・消える役、打点のレンジ、％', (tester) async {
      final h = await pumpScreens(tester, pro: true);
      await h.push(Routes.result, ResultArgs(input: splitHand));

      expect(find.byKey(const ValueKey('result-more-locked')), findsNothing);
      expect(find.byType(AdBannerSlot), findsNothing);

      // 打8筒: タンヤオ濃厚・場風（東を引けば）・平和（6筒・8筒を引けば）。
      await scrollResultTo(tester, find.byKey(ValueKey('candidate-$id8p')));
      await openDetails(tester, id8p);
      final card8p = find.byKey(ValueKey('candidate-$id8p'));
      expect(
        find.descendant(of: card8p, matching: find.text('タンヤオ（濃厚）')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card8p, matching: find.text('役牌（場風）（狙える: 東を引けば）')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card8p, matching: find.text('平和（狙える: 6筒・8筒を引けば）')),
        findsOneWidget,
      );

      // 打東: 場風が消える（赤の「消える」）。
      await scrollResultTo(tester, find.byKey(ValueKey('candidate-$id1z')));
      await openDetails(tester, id1z);
      final card1z = find.byKey(ValueKey('candidate-$id1z'));
      expect(
        find.descendant(of: card1z, matching: find.text('役牌（場風）（消える）')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card1z, matching: find.text('平和（確定）')),
        findsOneWidget,
      );
      final c1z = candidateOf(deep, id1z)!;
      expect(
        tester.widget<Text>(find.byKey(ValueKey('points-$id1z'))).data,
        '${s.dama} ${formatRange(c1z.points, s)}',
      );
      expect(
        find.descendant(
          of: card1z,
          matching: find.text(
            '${s.riichiIncluded} ${formatRange(c1z.riichiPoints!, s)}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(find.byKey(ValueKey('ease-$id1z'))).data,
        formatPercent(c1z.winEase),
      );

      // 全候補が並ぶ。
      final last = orderedCandidates(deep, StrategyAxis.balance).last;
      await scrollResultTo(
        tester,
        find.byKey(ValueKey('candidate-${last.discardId}')),
      );
      expect(
        find.byKey(ValueKey('candidate-${last.discardId}')),
        findsOneWidget,
      );
    });

    testWidgets('クイズの選択と各軸の正解の比較（別の軸なら「打点重視なら正解」）', (tester) async {
      final h = await pumpScreens(tester);
      // 速さで判定すると不正解だが、打点の解とは一致する。
      final verdict = judgeChoice(free, id8p, StrategyAxis.speed);
      expect(verdict.correct, isFalse);
      expect(verdict.otherCorrectAxes, contains(StrategyAxis.points));
      await h.push(
        Routes.result,
        ResultArgs(
          input: splitHand,
          chosenDiscardId: id8p,
          chosenAxis: StrategyAxis.speed,
          fromQuiz: true,
        ),
      );
      expect(find.byKey(const ValueKey('result-verdict')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('result-verdict-headline')))
            .data,
        verdict.otherCorrectAxes.map(s.correctFor).join(' / '),
      );
      expect(
        find.textContaining(s.correctFor(StrategyAxis.points)),
        findsOneWidget,
      );
      // 軸ごとの答え（打点の行に一致の印）。
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('answer-points')),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('answer-speed')),
          matching: find.byIcon(Icons.remove_circle_outline),
        ),
        findsOneWidget,
      );
    });

    testWidgets('表示で result_viewed・間隔制御・履歴の記録。開き直しは記録しない', (tester) async {
      final analytics = RecordingAnalyticsBackend();
      final interstitial = FakeInterstitial();
      final h = await pumpScreens(
        tester,
        analytics: analytics,
        interstitial: interstitial,
      );
      await h.push(
        Routes.result,
        ResultArgs(
          input: splitHand,
          chosenDiscardId: id1z,
          chosenAxis: StrategyAxis.speed,
          fromQuiz: true,
          source: 'photo',
        ),
      );
      expect(interstitial.resultViews, 1);
      expect(analytics.named('result_viewed').single, {
        'source': 'photo',
        'hand_size': 14,
        'shanten': 0,
        'gate': 'free',
      });
      // Quiz から来たときは解析の開始・完了を Result では送らない。
      expect(analytics.named('analysis_started'), isEmpty);

      final history = await h.container.read(historyProvider.future);
      expect(history, hasLength(1));
      final entry = history.single;
      expect(entry.userChoice, '1z');
      expect(entry.axis, StrategyAxis.speed);
      expect(entry.correct, isTrue);
      expect(entry.best[StrategyAxis.points], ['8p']);
      expect(entry.engineVersion, kEngineVersion);
      expect(entry.source, 'photo');

      // 履歴から開き直す（saveToHistory: false）。
      await h.push(
        Routes.result,
        ResultArgs(input: splitHand, saveToHistory: false, source: 'history'),
      );
      expect(await h.container.read(historyProvider.future), hasLength(1));
      expect(analytics.named('analysis_started').single['source'], 'history');
    });

    testWidgets('候補をタップすると詳細へ（candidate_opened）', (tester) async {
      final analytics = RecordingAnalyticsBackend();
      final h = await pumpScreens(tester, analytics: analytics);
      await h.push(Routes.result, ResultArgs(input: splitHand));
      await scrollResultTo(tester, find.byKey(ValueKey('candidate-$id8p')));
      await tester.tap(find.byKey(ValueKey('candidate-$id8p')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('candidate-detail-page')),
        findsOneWidget,
      );
      expect(analytics.named('candidate_opened').single, {
        'candidate_rank': candidateOf(
          free,
          id8p,
        )!.rankByAxis[StrategyAxis.balance]!,
        'axis': 'balance',
        'gate': 'free',
      });
      // 無料: 確度は鍵、打牌後の 13 枚は出る。
      expect(find.text(s.handAfter), findsOneWidget);
    });

    testWidgets('次の手・共有・出題のボタン', (tester) async {
      final interstitial = FakeInterstitial();
      final h = await pumpScreens(tester, interstitial: interstitial);
      await h.push(
        Routes.result,
        ResultArgs(input: splitHand, chosenDiscardId: id1z),
      );

      await tester.tap(find.byKey(const ValueKey('result-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-problem')));
      await tester.pumpAndSettle();
      final problem = h.routes.lastArgs(Routes.shareCard) as ShareCardArgs;
      expect(problem.kind, ShareCardKind.problem);
      expect(problem.input, splitHand);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('result-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-result')));
      await tester.pumpAndSettle();
      final result = h.routes.lastArgs(Routes.shareCard) as ShareCardArgs;
      expect(result.kind, ShareCardKind.result);
      expect(result.chosenDiscardId, id1z);
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('result-publish')));
      await tester.pumpAndSettle();
      expect(
        (h.routes.lastArgs(Routes.publish) as PublishArgs).input,
        splitHand,
      );
      h.navigator.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('result-next-hand')));
      await tester.pumpAndSettle();
      expect(interstitial.nextHands, 1);
      expect(h.routes.contains(Routes.camera), isTrue);
    });
  });

  group('オンライン機能の有無による文言', () {
    testWidgets('なし: 「友達に出題」ではなく「問題カードを共有」。誘い文句も出さない', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: splitHand));
      expect(find.text('友達に出題'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('result-publish')),
          matching: find.text('問題カードを共有'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('出題すると盛り上がります'), findsNothing);
      // 共有シートの問題カードも、Web で回答してもらう前提の説明にしない。
      await tester.tap(find.byKey(const ValueKey('result-share')));
      await tester.pumpAndSettle();
      expect(find.text(s.shareProblemCardBodyOffline), findsOneWidget);
      expect(find.text(s.shareProblemCardBody), findsNothing);
    });

    testWidgets('あり: 「友達に出題」と「出題すると盛り上がります」を出す', (tester) async {
      final h = await pumpScreens(
        tester,
        overrides: [onlineFeaturesProvider.overrideWithValue(true)],
      );
      await h.push(Routes.result, ResultArgs(input: splitHand));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('result-publish')),
          matching: find.text('友達に出題'),
        ),
        findsOneWidget,
      );
      expect(find.text('問題カードを共有'), findsNothing);
      expect(find.text(s.splitBody(speedVsPoints: true)), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('result-share')));
      await tester.pumpAndSettle();
      expect(find.text(s.shareProblemCardBody), findsOneWidget);
    });
  });

  testWidgets('3 軸が同じ牌なら「一択」', (tester) async {
    final report = analyzeNow(oneChoiceHand);
    expect(agreementOf(report), AnswerAgreement.single);
    final h = await pumpScreens(tester);
    await h.push(Routes.result, ResultArgs(input: oneChoiceHand));
    expect(find.byKey(const ValueKey('result-one-choice')), findsOneWidget);
    expect(find.text(s.oneChoice), findsOneWidget);
    expect(find.byKey(const ValueKey('result-split')), findsNothing);
    final id9s = tileIdFromLabel('9s');
    for (final axis in StrategyAxis.values) {
      expect(find.byKey(ValueKey('badge-$id9s-${axis.name}')), findsOneWidget);
    }
    // 理由: 端の孤立牌（理由タグの文）。
    expect(
      tester.widget<Text>(find.byKey(ValueKey('reason-$id9s'))).data,
      startsWith(text.sentence(Reason(ReasonTag.isolatedTerminal))),
    );
  });

  group('13 枚', () {
    testWidgets('門前・役なしテンパイ: リーチの案内、待ちと点数（無料はリーチ判断に鍵）', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: closedNoYakuHand));
      expect(find.byKey(const ValueKey('thirteen-shanten')), findsOneWidget);
      expect(find.text('テンパイ'), findsOneWidget);
      expect(find.text(s.waitsSummary('1索・4索', 8)), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-closed-no-yaku')), findsOneWidget);
      final wait1s = find.byKey(ValueKey('wait-${tileIdFromLabel('1s')}'));
      expect(
        find.descendant(of: wait1s, matching: find.text('ロン 役なし / ツモ 1,100')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: wait1s,
          matching: find.text('リーチ込み: ロン 1,300 / ツモ 2,000'),
        ),
        findsOneWidget,
      );
      expect(find.text('${s.riichiLocked}（Pro）'), findsOneWidget);
      expect(find.byKey(const ValueKey('riichi-advice')), findsNothing);
      // 13 枚は出題しない（何切るにならない）。
      expect(find.byKey(const ValueKey('result-publish')), findsNothing);
    });

    testWidgets('Pro はリーチ判断（推奨と比較）', (tester) async {
      final h = await pumpScreens(tester, pro: true);
      await h.push(Routes.result, ResultArgs(input: closedNoYakuHand));
      expect(find.byKey(const ValueKey('riichi-advice')), findsOneWidget);
      expect(find.textContaining(s.riichiRecommend), findsOneWidget);
      expect(find.text(s.riichiReason(RiichiReason.noYaku)), findsOneWidget);
    });

    testWidgets('門前・役ありテンパイは「リーチできます」', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: closedYakuHand));
      expect(find.byKey(const ValueKey('msg-riichi-possible')), findsOneWidget);
      final wait6p = find.byKey(ValueKey('wait-${tileIdFromLabel('6p')}'));
      expect(
        find.descendant(of: wait6p, matching: find.text('ロン 2,000 / ツモ 2,700')),
        findsOneWidget,
      );
    });

    testWidgets('鳴いて役なしテンパイは「あがれません」', (tester) async {
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: openNoYakuHand));
      expect(find.byKey(const ValueKey('msg-open-no-yaku')), findsOneWidget);
      expect(find.text(s.openNoYaku), findsOneWidget);
    });

    testWidgets('テンパイでなければ受け入れ', (tester) async {
      final input = hand('1m 2m 3m 4m 5m 6m 7p 8p 2s 3s 5z 5z 9s');
      final report = analyzeNow(input);
      final h = await pumpScreens(tester);
      await h.push(Routes.result, ResultArgs(input: input));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('thirteen-draws'))).data,
        s.ukeire(report.thirteen!.draws.kinds, report.thirteen!.draws.total),
      );
    });
  });

  testWidgets('和了形なら役と点数', (tester) async {
    final report = analyzeNow(winHand);
    expect(report.win, isNotNull);
    final h = await pumpScreens(tester);
    await h.push(Routes.result, ResultArgs(input: winHand));
    expect(find.byKey(const ValueKey('result-win')), findsOneWidget);
    expect(find.text(s.winTitle), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('result-win-points'))).data,
      '${s.hanFu(4, 20)}  ${s.points('5,200')}',
    );
    expect(find.textContaining('一気通貫'), findsWidgets);
  });

  testWidgets('履歴を作るときは判定した軸の正解の理由タグを入れる', (tester) async {
    final report = analyzeNow(oneChoiceHand);
    final entry = historyEntryFor(
      input: oneChoiceHand,
      report: report,
      chosenId: tileIdFromLabel('2m'),
      axis: StrategyAxis.balance,
      now: DateTime(2026, 10, 21, 12),
    );
    expect(entry.correct, isFalse);
    expect(entry.userChoice, '2m');
    expect(entry.reasonTags, contains('isolated_terminal'));
    expect(entry.best[StrategyAxis.speed], ['9s']);
  });
}
