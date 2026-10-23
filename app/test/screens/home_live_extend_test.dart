import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:nanikiru_cam/ui/home/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_harness.dart';

/// Home の「動画を見てライブを延長」（体験時間を使い切ったとき）。
void main() {
  final now = DateTime(2026, 10, 21, 20);
  final clock = clockProvider.overrideWithValue(() => now);
  const panel = ValueKey('live-extend-panel');
  const button = ValueKey('live-extend-button');

  Future<ScreenHarness> pumpHome(
    WidgetTester tester, {
    int usedSeconds = 300,
    int bonusSeconds = 0,
    int bonusGrants = 0,
    bool pro = false,
    bool adsEnabled = true,
    FakeRewardedGate? rewarded,
    RecordingAnalyticsBackend? analytics,
  }) => pumpScreens(
    tester,
    pro: pro,
    analytics: analytics,
    rewarded: rewarded ?? FakeRewardedGate(),
    prefs: {
      LiveTrial.preferenceKey: jsonEncode({
        'date': '2026-10-21',
        'usedSeconds': usedSeconds,
        'bonusSeconds': bonusSeconds,
        'bonusGrants': bonusGrants,
      }),
    },
    overrides: [clock, adsEnabledProvider.overrideWithValue(adsEnabled)],
    home: const HomePage(),
  );

  testWidgets('使い切り: 主ボタンの下に延長ボタンと報酬の説明を出す', (tester) async {
    await pumpHome(tester);
    expect(find.text('今日の体験は終了（Pro は無制限）'), findsOneWidget);
    expect(find.byKey(panel), findsOneWidget);
    expect(find.text('動画を見てライブを延長（+1〜3分）'), findsOneWidget);
    expect(find.text('広告が長いほど長く延長されます（今日はあと5回）'), findsOneWidget);
    expect(
      tester.widget<OutlinedButton>(find.byKey(button)).onPressed,
      isNotNull,
    );
    // ライブの入口と写真の入口の間にある。
    final liveBottom = tester
        .getBottomLeft(find.byKey(const ValueKey('home-live')))
        .dy;
    final photoTop = tester
        .getTopLeft(find.byKey(const ValueKey('home-photo')))
        .dy;
    final y = tester.getTopLeft(find.byKey(button)).dy;
    expect(y, greaterThan(liveBottom));
    expect(y, lessThan(photoTop));
  });

  testWidgets('広告が準備できていないときは無効で「広告を読み込み中」', (tester) async {
    await pumpHome(tester, rewarded: FakeRewardedGate(ready: false));
    expect(tester.widget<OutlinedButton>(find.byKey(button)).onPressed, isNull);
    expect(find.text('広告を読み込み中'), findsOneWidget);
  });

  testWidgets('体験が残っているうちは出さない', (tester) async {
    await pumpHome(tester, usedSeconds: 100);
    expect(find.text('今日の体験 残り 3 分 20 秒'), findsOneWidget);
    expect(find.byKey(panel), findsNothing);
  });

  testWidgets('Pro なら出さない', (tester) async {
    await pumpHome(tester, pro: true);
    expect(find.byKey(panel), findsNothing);
  });

  testWidgets('広告が使えない（同意なし等）なら出さない', (tester) async {
    await pumpHome(tester, adsEnabled: false);
    expect(find.byKey(panel), findsNothing);
  });

  testWidgets('見終えると延長され、Home の残り表示が変わる（15 秒の広告 → +2 分）', (tester) async {
    final analytics = RecordingAnalyticsBackend();
    final rewarded = FakeRewardedGate(watched: const Duration(seconds: 15));
    await pumpHome(tester, rewarded: rewarded, analytics: analytics);
    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();

    expect(rewarded.shown, [RewardKind.liveTrial]);
    expect(find.text('ライブが+2分延長されました'), findsOneWidget);
    expect(find.text('今日の体験 残り 2 分 00 秒'), findsOneWidget);
    expect(find.byKey(panel), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(LiveTrial.preferenceKey)!), {
      'date': '2026-10-21',
      'usedSeconds': 300,
      'bonusSeconds': 120,
      'bonusGrants': 1,
    });
    expect(analytics.named('live_trial_extended').single, {
      'bonus_s': 120,
      'trigger': 'home',
    });
  });

  testWidgets('途中で閉じたら延長しない', (tester) async {
    final rewarded = FakeRewardedGate(result: false);
    await pumpHome(tester, rewarded: rewarded);
    await tester.tap(find.byKey(button));
    await tester.pumpAndSettle();
    expect(find.text('動画を最後まで見ると延長されます'), findsOneWidget);
    expect(find.text('今日の体験は終了（Pro は無制限）'), findsOneWidget);
    expect(find.byKey(panel), findsOneWidget);
  });

  testWidgets('延長を使い切った日の使い切りは、上限の表示だけ', (tester) async {
    await pumpHome(
      tester,
      usedSeconds: 1200,
      bonusSeconds: 900,
      bonusGrants: 5,
    );
    expect(find.byKey(button), findsNothing);
    expect(find.text('今日の延長は上限です'), findsOneWidget);
  });

  testWidgets('延長して使い切るとまた出る（残り回数が減る）', (tester) async {
    await pumpHome(tester, usedSeconds: 420, bonusSeconds: 120, bonusGrants: 1);
    expect(find.text('広告が長いほど長く延長されます（今日はあと4回）'), findsOneWidget);
  });
}
