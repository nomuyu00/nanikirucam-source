// 画面（quiz / result / history / home / onboarding / 撮影の無料枠）のテスト用の土台。
//
// 解析は別 Isolate ではなくその場で動かし（AnalysisService の runner を差し替え）、
// 広告・計測は偽物にする。自分の担当でない画面へ進むルートは、名前と引数を記録する
// 仮の画面にする。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/history_page.dart';
import 'package:nanikiru_cam/quiz/quiz_page.dart';
import 'package:nanikiru_cam/result/candidate_detail_page.dart';
import 'package:nanikiru_cam/result/explanation_page.dart';
import 'package:nanikiru_cam/result/result_page.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_page.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_loading_page.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 牌ラベルを空白区切りで書いた手。14 枚なら最後をツモ牌にする。
HandInput hand(
  String labels, {
  List<MeldInput> melds = const [],
  List<String> dora = const [],
}) {
  final tiles = labels.split(' ').where((t) => t.isNotEmpty).toList();
  final count = tiles.length + 3 * melds.length;
  return HandInput(
    tiles: tiles,
    tsumoIndex: count == 14 && melds.isEmpty ? tiles.length - 1 : null,
    melds: melds,
    doraIndicators: dora,
  );
}

/// 速さ（打東）と打点（打8筒、場風の東を残す）で答えが割れる一向聴の 14 枚。
/// 東場・南家なので東は場風（役牌）。
final splitHand = hand('2m 3m 4m 3p 4p 5p 5s 6s 7s 6s 6s 7p 8p 1z');

/// 3 軸とも打9索の 14 枚（孤立した端の牌）。
final oneChoiceHand = hand('2m 6m 7m 8m 2p 4p 5p 6p 7p 8p 4s 5s 6s 9s');

/// 門前・役なしのテンパイ（白の雀頭、1索・4索待ち）。
final closedNoYakuHand = hand('1m 2m 3m 4m 5m 6m 7p 8p 9p 2s 3s 5z 5z');

/// 門前・役ありのテンパイ（6筒・9筒待ち。6筒ならタンヤオ・平和）。
final closedYakuHand = hand('2m 3m 4m 3p 4p 5p 5s 6s 7s 6s 6s 7p 8p');

/// 西をポンした役なしのテンパイ。
final openNoYakuHand = hand(
  '1m 2m 3m 4p 5p 6p 7s 8s 9p 9p',
  melds: [
    MeldInput(kind: MeldKind.pon, tiles: const ['3z', '3z', '3z']),
  ],
);

/// ツモ和了の 14 枚（一気通貫・平和・門前ツモ）。
final winHand = hand('1m 2m 3m 4m 5m 6m 7m 8m 9m 2p 3p 4p 5s 5s');

/// 解析エンジンをその場で動かす（テストの偽の時間の中で終わるように）。
AnalysisService syncAnalysisService() => AnalysisService(
  runner: (hand, deep) async => DefaultNanikiruEngine().analyze(hand, deep: deep),
);

/// テストで期待値を出すための解析。
AnalysisReport analyzeNow(HandInput input, {bool deep = false}) =>
    DefaultNanikiruEngine().analyze(input.toHandState(), deep: deep);

class FakeInterstitial implements InterstitialController {
  int resultViews = 0;
  int nextHands = 0;
  int shares = 0;

  @override
  void onResultViewed() => resultViews++;

  @override
  void onShared() => shares++;

  @override
  Future<void> maybeShowBeforeNextHand() async => nextHands++;
}

class FakeRewardedGate extends RewardedGate {
  FakeRewardedGate({this.ready = true, this.result = true, this.watched});

  bool ready;
  bool result;

  /// [showTimed] が返す「広告を見た時間」（ライブ延長の段階づけ。null は時間が取れなかった）。
  Duration? watched;
  final List<RewardKind> shown = [];

  @override
  bool isReady(RewardKind kind) => ready;

  @override
  Future<bool> show(RewardKind kind) async {
    shown.add(kind);
    return result;
  }

  @override
  Future<RewardedShowResult> showTimed(RewardKind kind) async {
    shown.add(kind);
    return RewardedShowResult(earned: result, watched: result ? watched : null);
  }
}

class RecordingAnalyticsBackend implements AnalyticsBackend {
  final List<(String, Map<String, Object>)> events = [];

  @override
  bool get supported => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> setCollectionEnabled(bool enabled) async {}

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    events.add((name, parameters));
  }

  @override
  Future<void> logScreen(String name) async {}

  List<Map<String, Object>> named(String name) => [
    for (final e in events)
      if (e.$1 == name) e.$2,
  ];
}

/// 担当外の画面への遷移の記録。
class RouteLog {
  final List<(String, Object?)> pushed = [];

  Object? lastArgs(String route) =>
      pushed.lastWhere((e) => e.$1 == route, orElse: () => (route, null)).$2;

  bool contains(String route) => pushed.any((e) => e.$1 == route);
}

class ScreenHarness {
  ScreenHarness(this.tester, this.container, this.navigator, this.routes);

  final WidgetTester tester;
  final ProviderContainer container;
  final GlobalKey<NavigatorState> navigator;
  final RouteLog routes;

  Future<void> push(String route, Object? arguments) async {
    unawaited(navigator.currentState!.pushNamed(route, arguments: arguments));
    await tester.pumpAndSettle();
  }

  void setPro(bool pro) => container.read(entitlementsProvider.notifier).state =
      EntitlementState(pro: pro);
}

/// 担当の画面を実物で、それ以外を仮の画面で組んだアプリを出す。
Future<ScreenHarness> pumpScreens(
  WidgetTester tester, {
  bool pro = false,
  Map<String, Object> prefs = const {},
  FakeInterstitial? interstitial,
  FakeRewardedGate? rewarded,
  RecordingAnalyticsBackend? analytics,
  List<Override> overrides = const [],
  Widget? home,
  Locale locale = const Locale('ja'),
  Map<String, WidgetBuilder> pages = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    AppAnalytics.preferenceKey: true,
    ...prefs,
  });
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final routeLog = RouteLog();
  final navigatorKey = GlobalKey<NavigatorState>();
  final backend = analytics ?? RecordingAnalyticsBackend();
  late ProviderContainer container;

  Route<Object?> build(RouteSettings settings) {
    final custom = pages[settings.name];
    if (custom != null) {
      routeLog.pushed.add((settings.name!, settings.arguments));
      return MaterialPageRoute(settings: settings, builder: custom);
    }
    final Widget page = switch (settings.name) {
      Routes.quiz => const QuizPage(),
      Routes.result => const ResultPage(),
      Routes.candidateDetail => const CandidateDetailPage(),
      Routes.explanation => const ExplanationPage(),
      Routes.history => const HistoryPage(),
      Routes.recognitionLoading => const RecognitionLoadingPage(),
      Routes.manualInput => const RecognitionPage(manual: true),
      Routes.onboarding => const OnboardingPage(),
      Routes.home => home ?? const Scaffold(body: Text('home')),
      _ => Scaffold(
        appBar: AppBar(),
        body: Text('route:${settings.name}'),
      ),
    };
    if (settings.name != Routes.home) {
      routeLog.pushed.add((settings.name!, settings.arguments));
    }
    return MaterialPageRoute(settings: settings, builder: (_) => page);
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        analysisServiceProvider.overrideWithValue(syncAnalysisService()),
        entitlementsProvider.overrideWith((ref) => EntitlementState(pro: pro)),
        adsEnabledProvider.overrideWithValue(false),
        interstitialControllerProvider.overrideWithValue(
          interstitial ?? FakeInterstitial(),
        ),
        rewardedGateProvider.overrideWith(
          (ref) => rewarded ?? FakeRewardedGate(ready: false),
        ),
        appAnalyticsProvider.overrideWith((ref) {
          final a = AppAnalytics(backend: backend);
          unawaited(a.initialize());
          return a;
        }),
        ...overrides,
      ],
      child: Consumer(
        builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(
            navigatorKey: navigatorKey,
            onGenerateRoute: build,
            locale: locale,
            supportedLocales: const [Locale('ja'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  // SharedPreferences と計測の初期化を終わらせる。
  await container.read(sharedPreferencesProvider.future);
  await container.read(appAnalyticsProvider).initialize();
  await tester.pumpAndSettle();
  return ScreenHarness(tester, container, navigatorKey, routeLog);
}

/// 修正画面（認識結果の修正）を実物にするときの [pumpScreens] の `pages`。
final Map<String, WidgetBuilder> realRecognitionPage = {
  Routes.recognition: (_) => const RecognitionPage(),
};

/// [finder] が見えるまでスクロールしてから返す。
Future<Finder> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return finder;
}
