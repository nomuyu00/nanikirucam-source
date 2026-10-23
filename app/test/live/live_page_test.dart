import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/route_observer.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/live/live_camera.dart';
import 'package:nanikiru_cam/live/live_device.dart';
import 'package:nanikiru_cam/live/live_page.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/live/live_summary_page.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/live_fakes.dart';

class _ArgsProbe extends StatelessWidget {
  const _ArgsProbe(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final text = switch (args) {
      final PaywallArgs a =>
        '$name ${a.trigger.name} advice=${a.liveAdviceCount} wins=${a.liveWinCount}',
      final ShareCardArgs s =>
        '$name ${s.kind.name} first=${s.firstWin} '
            'win=${s.win?.points} live=${s.live?.adviceCount}',
      _ => '$name $args',
    };
    return Scaffold(body: Text(text, key: const ValueKey('probe')));
  }
}

void main() {
  late FakeLiveCamera camera;
  late ScriptedDetector detector;
  late ManualLiveClock clock;
  late FakeLiveDevice device;
  late List<RecordedEvent> events;
  final now = DateTime(2026, 10, 21, 20, 30);

  setUp(() {
    camera = FakeLiveCamera();
    detector = ScriptedDetector();
    clock = ManualLiveClock();
    device = FakeLiveDevice();
    events = [];
  });

  Future<void> pumpLive(
    WidgetTester tester, {
    bool pro = false,
    int usedSeconds = 0,
    int bonusSeconds = 0,
    bool guideSeen = true,
    AppSettings? settings,
  }) async {
    SharedPreferences.setMockInitialValues({
      liveGuideSeenKey: guideSeen,
      if (settings != null)
        AppSettingsNotifier.preferenceKey: jsonEncode(settings.toJson()),
      LiveTrial.preferenceKey: jsonEncode({
        'date': localDateKey(now),
        'usedSeconds': usedSeconds,
        if (bonusSeconds > 0) 'bonusSeconds': bonusSeconds,
        if (bonusSeconds > 0) 'bonusGrants': 1,
      }),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveCameraFactoryProvider.overrideWithValue(() => camera),
          liveDetectorFactoryProvider.overrideWithValue(() => detector),
          liveClockFactoryProvider.overrideWithValue(() => clock),
          liveDeviceProvider.overrideWithValue(device),
          clockProvider.overrideWithValue(() => now),
          analysisServiceProvider.overrideWithValue(inProcessAnalysis()),
          entitlementsProvider.overrideWith(
            (ref) => pro
                ? const EntitlementState(
                    pro: true,
                    source: EntitlementSource.store,
                  )
                : EntitlementState.free,
          ),
          analyticsSinkProvider.overrideWithValue((
            AnalyticsEvent event, [
            Map<String, Object> parameters = const {},
          ]) {
            events.add(RecordedEvent(event.name, parameters));
          }),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorObservers: [appRouteObserver],
          initialRoute: Routes.live,
          routes: {
            Routes.home: (_) => const Scaffold(body: Text('home')),
            Routes.live: (_) => const LivePage(),
            Routes.liveSummary: (_) => const LiveSummaryPage(),
            Routes.paywall: (_) => const _ArgsProbe('paywall'),
            Routes.result: (_) => const _ArgsProbe('result'),
            Routes.shareCard: (_) => const _ArgsProbe('share'),
          },
        ),
      ),
    );
    // SharedPreferences と FutureProvider の読み込み。
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  /// [labels] のフレームを 200ms ごとに [count] 枚送る。
  Future<void> sendFrames(
    WidgetTester tester,
    List<String> labels, {
    int count = 6,
  }) async {
    detector.next = () => handBoxes(labels);
    for (var i = 0; i < count; i++) {
      camera.emit();
      await tester.pump();
      clock.now += const Duration(milliseconds: 200);
    }
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('stable になったら切る牌を案内する（それまでは探索中）', (tester) async {
    await pumpLive(tester);
    expect(camera.active, isTrue, reason: 'カメラを開く');
    expect(detector.loaded, isTrue);
    expect(device.screenOn, [true], reason: '画面を点けたまま');
    expect(events.map((e) => e.name), contains('liveStarted'));
    expect(events.firstWhere((e) => e.name == 'liveStarted').parameters, {
      'gate': 'free_trial',
    });
    expect(find.byKey(const ValueKey('live-trial-remaining')), findsOneWidget);

    await sendFrames(tester, HandFixtures.fourteen, count: 3);
    expect(find.byKey(const ValueKey('live-discard-text')), findsNothing);

    await sendFrames(tester, HandFixtures.fourteen, count: 4);
    final best = DefaultNanikiruEngine()
        .analyze(
          HandInput(tiles: HandFixtures.fourteen).toHandState(),
          deep: false,
        )
        .bestByAxis[StrategyAxis.balance]!
        .first;
    final name = const CommonStrings(AppLang.ja).tileName(tileLabelOfId(best));
    expect(find.text('$nameを切る'), findsOneWidget);
    expect(find.text('確定'), findsOneWidget);
    expect(events.map((e) => e.name), contains('liveAdviceShown'));

    // 手を動かす（枚数が変わる）と案内が消える。
    await sendFrames(tester, HandFixtures.fourteen.take(12).toList(), count: 2);
    expect(find.text('$nameを切る'), findsNothing);

    await unmount(tester);
    expect(device.screenOn, [true, false]);
  });

  testWidgets('13 枚のテンパイは待ちと残り枚数、リーチ可否', (tester) async {
    await pumpLive(tester);
    // 123m 456m 789p 234s 白（白の単騎待ち）。
    final tenpai = [...HandFixtures.win]..removeLast();
    await sendFrames(tester, tenpai, count: 7);
    expect(find.byKey(const ValueKey('live-thirteen-shanten')), findsOneWidget);
    expect(find.text('テンパイ'), findsOneWidget);
    expect(
      find.byKey(ValueKey('live-wait-${tileIdFromLabel('5z')}')),
      findsOneWidget,
    );
    await unmount(tester);
  });

  testWidgets('和了形は「ツモ！」と点数、「次の局へ」で消える', (tester) async {
    await pumpLive(tester);
    await sendFrames(tester, HandFixtures.win, count: 7);
    expect(find.byKey(const ValueKey('live-win')), findsOneWidget);
    expect(events.map((e) => e.name), contains('liveWinDetected'));
    await tester.tap(find.text('次の局へ'));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-win')), findsNothing);
    await unmount(tester);
  });

  testWidgets('体験時間が尽きたら live_ended{trial_limit} → Paywall', (tester) async {
    await pumpLive(tester, usedSeconds: 297);
    await sendFrames(tester, HandFixtures.fourteen, count: 7);
    expect(find.textContaining('を切る'), findsWidgets);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('paywall liveTrialEnded advice=1 wins=0'), findsOneWidget);
    final ended = events.firstWhere((e) => e.name == 'liveEnded');
    expect(ended.parameters['ended_by'], 'trial_limit');
    expect(ended.parameters['gate'], 'free_trial');
    expect(ended.parameters['duration_s'], 3);
    expect(events.map((e) => e.name), contains('liveState'));
    expect(camera.active, isFalse);

    final prefs = await SharedPreferences.getInstance();
    final trial = jsonDecode(prefs.getString(LiveTrial.preferenceKey)!) as Map;
    expect(trial['usedSeconds'], 300);
    expect(LiveSessionStore(prefs).load().single.adviceCount, 1);
    await unmount(tester);
  });

  testWidgets('体験を使い切っていたらカメラを開かずに Paywall', (tester) async {
    await pumpLive(tester, usedSeconds: 300);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('paywall liveTrialEnded advice=0 wins=0'), findsOneWidget);
    expect(camera.activations, 0);
    expect(events.map((e) => e.name), isNot(contains('liveStarted')));
    await unmount(tester);
  });

  testWidgets('動画で延長した日は、300 秒を超えても続き、延長した上限で終わる', (tester) async {
    await pumpLive(tester, usedSeconds: 297, bonusSeconds: 60);
    expect(find.text('体験 残り1:03'), findsOneWidget);

    // 本来の上限（300 秒）を過ぎても Live のまま。
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(LivePage), findsOneWidget);
    expect(find.text('体験 残り1:00'), findsOneWidget);
    expect(find.textContaining('paywall'), findsNothing);

    // 延長した分（60 秒）を使い切ると、体験終了として Paywall へ。
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('paywall liveTrialEnded advice=0 wins=0'), findsOneWidget);
    final ended = events.firstWhere((e) => e.name == 'liveEnded');
    expect(ended.parameters['ended_by'], 'trial_limit');
    expect(ended.parameters['duration_s'], 63);

    // 滞在秒数を足しても延長分を落とさない。
    final prefs = await SharedPreferences.getInstance();
    final trial = jsonDecode(prefs.getString(LiveTrial.preferenceKey)!) as Map;
    expect(trial['usedSeconds'], 360);
    expect(trial['bonusSeconds'], 60);
    expect(trial['bonusGrants'], 1);
    await unmount(tester);
  });

  testWidgets('300 秒を使い切っていても、延長済みならカメラを開く', (tester) async {
    await pumpLive(tester, usedSeconds: 300, bonusSeconds: 120);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LivePage), findsOneWidget);
    expect(find.textContaining('paywall'), findsNothing);
    expect(camera.activations, greaterThan(0));
    expect(find.text('体験 残り2:00'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('Pro は体験時間を数えない', (tester) async {
    await pumpLive(tester, pro: true, usedSeconds: 299);
    expect(find.byKey(const ValueKey('live-trial-remaining')), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.byType(LivePage), findsOneWidget);
    expect(events.firstWhere((e) => e.name == 'liveStarted').parameters, {
      'gate': 'pro',
    });
    await unmount(tester);
  });

  testWidgets('終了で対局サマリーへ（live_ended{user}）', (tester) async {
    await pumpLive(tester, pro: true);
    await sendFrames(tester, HandFixtures.win, count: 7);
    await tester.tap(find.text('次の局へ'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.tap(find.byKey(const ValueKey('live-end')));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LiveSummaryPage), findsOneWidget);
    expect(find.text('対局サマリー'), findsOneWidget);
    expect(find.text('初めての和了！'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-summary-share')), findsOneWidget);
    final ended = events.firstWhere((e) => e.name == 'liveEnded');
    expect(ended.parameters['ended_by'], 'user');
    expect(ended.parameters['gate'], 'pro');

    // 和了があれば節目カード（初めての和了）。
    await tester.ensureVisible(
      find.byKey(const ValueKey('live-summary-share')),
    );
    await tester.tap(find.byKey(const ValueKey('live-summary-share')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.textContaining(RegExp(r'^share liveMilestone first=true win=\d+')),
      findsOneWidget,
    );
    Navigator.of(tester.element(find.byKey(const ValueKey('probe')))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // 今日の成果（サマリーカード）。
    final summary = find.byKey(const ValueKey('live-summary-share-summary'));
    await tester.ensureVisible(summary);
    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('share liveSummary'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('「終了」を通らずに閉じても live_ended を送る', (tester) async {
    await pumpLive(tester, pro: true);
    await sendFrames(tester, HandFixtures.fourteen, count: 7);
    await unmount(tester);
    final ended = events.where((e) => e.name == 'liveEnded').single;
    expect(ended.parameters['ended_by'], 'user');
  });

  testWidgets('初回は置き方の案内を出し、了解するまでカメラを開かない', (tester) async {
    await pumpLive(tester, guideSeen: false);
    expect(find.byKey(const ValueKey('live-guide-accept')), findsOneWidget);
    expect(camera.active, isFalse);
    await tester.ensureVisible(find.byKey(const ValueKey('live-guide-accept')));
    await tester.tap(find.byKey(const ValueKey('live-guide-accept')));
    await tester.pump();
    await tester.pump();
    expect(camera.active, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(liveGuideSeenKey), isTrue);
    await unmount(tester);
  });

  testWidgets('カメラの権限がないと案内と再試行', (tester) async {
    camera.failure = const LiveCameraError('CameraAccessDenied');
    await pumpLive(tester);
    expect(find.byKey(const ValueKey('live-error')), findsOneWidget);
    expect(find.text('再試行'), findsOneWidget);
    final failed = events.firstWhere((e) => e.name == 'cameraFailed');
    expect(failed.parameters, {
      'source': 'live',
      'error_code': 'permission_denied',
    });
    await tester.tap(find.text('再試行'));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-error')), findsNothing);
    await unmount(tester);
  });

  testWidgets('モデルを読み込めないと案内と再試行', (tester) async {
    detector.failLoad = true;
    await pumpLive(tester);
    expect(find.text('認識モデルを読み込めませんでした。'), findsOneWidget);
    detector.failLoad = false;
    await tester.tap(find.text('再試行'));
    await tester.pump();
    await tester.pump();
    expect(find.text('認識モデルを読み込めませんでした。'), findsNothing);
    await unmount(tester);
  });

  for (final failure in ['モデル', 'カメラ']) {
    testWidgets('$failureが使えない間は体験時間を数えず、閉じても記録・サマリーを出さない', (tester) async {
      if (failure == 'モデル') {
        detector.failLoad = true;
      } else {
        camera.failure = const LiveCameraError('CameraAccessDenied');
      }
      await pumpLive(tester, usedSeconds: 100);
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('体験 残り3:20'), findsOneWidget, reason: '200 秒のまま');

      await tester.tap(find.text('閉じる'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(LivePage), findsNothing);
      expect(find.byType(LiveSummaryPage), findsNothing);
      expect(find.text('home'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      final trial =
          jsonDecode(prefs.getString(LiveTrial.preferenceKey)!) as Map;
      expect(trial['usedSeconds'], 100);
      expect(LiveSessionStore(prefs).load(), isEmpty);
      final names = events.map((e) => e.name);
      expect(names, isNot(contains('liveStarted')));
      expect(names, isNot(contains('liveEnded')));
      await unmount(tester);
      expect(
        events.map((e) => e.name),
        isNot(contains('liveEnded')),
        reason: '破棄のときも送らない',
      );
    });
  }

  testWidgets('モデルの再試行で使えるようになったら、そこから数え始める', (tester) async {
    detector.failLoad = true;
    await pumpLive(tester, usedSeconds: 100);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    detector.failLoad = false;
    await tester.tap(find.text('再試行'));
    await tester.pump();
    await tester.pump();
    expect(events.where((e) => e.name == 'liveStarted').single.parameters, {
      'gate': 'free_trial',
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.text('体験 残り3:17'), findsOneWidget);
    await unmount(tester);
  });

  group('設定（仕様 6.11）', () {
    late int haptics;

    setUp(() => haptics = 0);

    void recordHaptics(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics++;
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    StrategyAxis selectedAxis(WidgetTester tester) => tester
        .widget<SegmentedButton<StrategyAxis>>(
          find.byType(SegmentedButton<StrategyAxis>),
        )
        .selected
        .single;

    testWidgets('既定: バランス、案内が出たら振動、明るさは触らない', (tester) async {
      recordHaptics(tester);
      await pumpLive(tester);
      expect(selectedAxis(tester), StrategyAxis.balance);
      await sendFrames(tester, HandFixtures.fourteen, count: 7);
      expect(find.textContaining('を切る'), findsWidgets);
      expect(haptics, 1);
      await unmount(tester);
      expect(device.brightnessLocks, isEmpty);
    });

    testWidgets('最初の軸・振動 OFF・明るさ固定を反映する', (tester) async {
      recordHaptics(tester);
      await pumpLive(
        tester,
        settings: const AppSettings(
          liveDefaultAxis: StrategyAxis.points,
          liveHaptics: false,
          liveLockBrightness: true,
        ),
      );
      expect(selectedAxis(tester), StrategyAxis.points);
      expect(device.brightnessLocks, [true]);
      await sendFrames(tester, HandFixtures.fourteen, count: 7);
      expect(find.textContaining('を切る'), findsWidgets);
      expect(haptics, 0);
      expect(
        events.where((e) => e.name == 'axisChanged'),
        isEmpty,
        reason: '設定による軸は計測しない',
      );
      final shown = events.firstWhere((e) => e.name == 'liveAdviceShown');
      expect(shown.parameters['axis'], 'points');
      await unmount(tester);
      expect(device.brightnessLocks, [true, false]);
    });
  });

  testWidgets('温度警告で 1 fps と表示、暗いとヒント', (tester) async {
    device.thermalStatus = const ThermalStatus(warning: true);
    await pumpLive(tester);
    expect(find.textContaining('端末が熱くなっています'), findsOneWidget);
    detector.luminance = 0.02;
    await sendFrames(tester, HandFixtures.fourteen, count: 2);
    expect(find.text('暗い'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('上部は状態・残り時間・一時停止・終了だけ。軸と局の設定・置き方は下部', (tester) async {
    await pumpLive(tester);
    final top = find.byKey(const ValueKey('live-state-badge'));
    final axis = find.byType(SegmentedButton<StrategyAxis>);
    expect(
      tester.getTopLeft(axis).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('live-advice-panel'))).dy,
      ),
      reason: '軸の切替は案内パネルの下',
    );
    expect(tester.getTopLeft(top).dy, lessThan(100));
    // 局の設定・置き方はメニューから開く。
    await tester.tap(find.byKey(const ValueKey('live-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('局の設定'));
    await tester.pumpAndSettle();
    expect(find.text('ドラ表示牌'), findsOneWidget);
    Navigator.of(tester.element(find.text('ドラ表示牌'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置き方'));
    await tester.pumpAndSettle();
    expect(find.text('ライブナビの置き方'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    await unmount(tester);
  });
}
