import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/result/result_logic.dart';

import 'screens_harness.dart';

void main() {
  final id8p = tileIdFromLabel('8p');
  final id1z = tileIdFromLabel('1z');
  CandidateDetailArgs detail(int id) =>
      CandidateDetailArgs(input: splitHand, discardId: id);

  Future<void> scrollDetailTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('candidate-detail-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('候補の詳細（無料）: 切ったあとの手・受け入れ、Pro の項目は鍵', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.candidateDetail, detail(id8p));
    expect(find.text('打 8筒'), findsOneWidget);
    expect(find.text('この牌を切ったあとの手'), findsOneWidget);
    expect(find.text('受け入れ牌ごとの変化（Pro）'), findsOneWidget);
    await scrollDetailTo(tester, find.text('確度と成立条件（Pro）'));
    expect(find.text('タンヤオ'), findsOneWidget);
    expect(find.textContaining('濃厚'), findsNothing);
    await scrollDetailTo(tester, find.byKey(const ValueKey('detail-explanation')));
    expect(find.byKey(const ValueKey('reason-list')), findsNothing);
  });

  testWidgets('無料では上位 3 件より下の候補は開けない', (tester) async {
    final report = analyzeNow(splitHand);
    final hidden = orderedCandidates(report, StrategyAxis.balance).last;
    final h = await pumpScreens(tester);
    await h.push(Routes.candidateDetail, detail(hidden.discardId));
    expect(find.byKey(const ValueKey('candidate-locked')), findsOneWidget);
  });

  testWidgets('候補の詳細（Pro）: 2 段階先・確度の見方・理由・リーチ判断', (tester) async {
    final h = await pumpScreens(tester, pro: true);
    await h.push(Routes.candidateDetail, detail(id8p));
    await scrollDetailTo(tester, find.byKey(const ValueKey('two-step-list')));
    expect(find.textContaining('を引く → 打'), findsWidgets);
    await scrollDetailTo(tester, find.text('タンヤオ（濃厚）'));
    await scrollDetailTo(tester, find.byKey(const ValueKey('reason-list')));
    expect(find.text('役牌（場風）を残す'), findsOneWidget);

    // 打東はテンパイなのでリーチ判断が出る。
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await h.push(Routes.candidateDetail, detail(id1z));
    await scrollDetailTo(tester, find.byKey(const ValueKey('riichi-advice')));
    expect(find.byKey(const ValueKey('riichi-advice')), findsOneWidget);
  });

  testWidgets('解説（無料）: 鍵 → Paywall（explanationLocked）', (tester) async {
    final h = await pumpScreens(tester, rewarded: FakeRewardedGate(ready: false));
    await h.push(Routes.explanation, detail(id8p));
    expect(find.byKey(const ValueKey('explanation-locked')), findsOneWidget);
    // 動画が読み込めていなければボタンは押せない。
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('explanation-watch-video')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('explanation-paywall')));
    await tester.pumpAndSettle();
    expect(
      (h.routes.lastArgs(Routes.paywall) as PaywallArgs).trigger,
      PaywallTrigger.explanationLocked,
    );
  });

  testWidgets('解説（無料）: 動画を最後まで見るとこの手だけ見られる', (tester) async {
    final rewarded = FakeRewardedGate(ready: true, result: true);
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(
      tester,
      rewarded: rewarded,
      analytics: analytics,
    );
    await h.push(Routes.explanation, detail(id8p));
    await tester.tap(find.byKey(const ValueKey('explanation-watch-video')));
    await tester.pumpAndSettle();
    expect(rewarded.shown, [RewardKind.explanation]);
    expect(find.byKey(const ValueKey('explanation-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('blocks-view')), findsOneWidget);
    expect(analytics.named('explanation_opened').single['gate'], 'free');

    // 別の手は開いていない。
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await h.push(
      Routes.explanation,
      CandidateDetailArgs(
        input: oneChoiceHand,
        discardId: tileIdFromLabel('9s'),
      ),
    );
    expect(find.byKey(const ValueKey('explanation-locked')), findsOneWidget);
  });

  testWidgets('解説（無料）: 動画を最後まで見なければ開かない', (tester) async {
    final h = await pumpScreens(
      tester,
      rewarded: FakeRewardedGate(ready: true, result: false),
    );
    await h.push(Routes.explanation, detail(id8p));
    await tester.tap(find.byKey(const ValueKey('explanation-watch-video')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('explanation-locked')), findsOneWidget);
  });

  testWidgets('解説（Pro）: ブロック分解・比較表', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final h = await pumpScreens(tester, pro: true, analytics: analytics);
    await h.push(Routes.explanation, detail(id8p));
    expect(find.byKey(const ValueKey('explanation-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('blocks-view')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('compare-table')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const ValueKey('compare-table')), findsOneWidget);
    expect(analytics.named('explanation_opened').single['gate'], 'pro');
  });
}
