// 画面の見た目の確認用（UI の刷新 第 2 弾の before / after 比較）。ストア素材・審査の証跡には使わない。
//
// flutter test tool/capture_screens_wave2_test.dart \
//   --dart-define=CAPTURE_OUTPUT_DIR=/mnt/c/temp/screens/wave2/after \
//   --dart-define=CAPTURE_ONLY=quiz,live_advice
//
// capture_screens_test.dart（第 1 弾。別の作業者も編集する）と同じ下準備で、Quiz・Live（偽の
// カメラと偽の検出）・候補の詳細・解説・対局サマリー・設定（トップとサブページ）・履歴・公開・
// 出題した問題を描画し、iPhone 相当（390×844）と縦長（390×2000）の PNG に書き出す。
// 文字は日本語・英語・大きな文字（textScaler 1.3）の 3 通り。レイアウトのあふれは
// `<出力先>/errors.txt` に書く。日本語フォントは Windows のメイリオを読む。
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/app.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/ui/settings/settings_page.dart';
import 'package:nanikiru_cam/ui/theme/app_theme.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/live/support/live_fakes.dart';
import '../test/support/billing_fakes.dart';

const _fontFamily = 'CaptureJapanese';
const _today = '2026-10-23';
final _now = DateTime(2026, 10, 23, 20, 15);

const _outputDir = String.fromEnvironment(
  'CAPTURE_OUTPUT_DIR',
  defaultValue: '/tmp/nanikiru_screens_wave2',
);

/// 書き出す画面だけに絞る（カンマ区切り。空なら全部）。
const _only = String.fromEnvironment('CAPTURE_ONLY');

/// 書き出す文字の組み合わせだけに絞る（ja / en / ja_large。空なら全部）。
const _onlyVariants = String.fromEnvironment('CAPTURE_VARIANTS');

ThemeData _theme() => AppTheme.light(fontFamily: _fontFamily);

HandInput _hand(String labels, {List<String> dora = const []}) {
  final tiles = labels.split(' ');
  return HandInput(
    tiles: tiles,
    tsumoIndex: tiles.length == 14 ? 13 : null,
    doraIndicators: dora,
  );
}

/// 速さと打点で答えが割れる一向聴の 14 枚（test/screens の splitHand と同じ）。
final _splitHand = _hand(
  '2m 3m 4m 3p 4p 5p 5s 6s 7s 6s 6s 7p 8p 1z',
  dora: ['4s'],
);

typedef _Interact = Future<void> Function(WidgetTester tester);

class _Screen {
  const _Screen(
    this.name,
    this.route, {
    this.arguments,
    this.pro = false,
    this.interact,
    this.prefs = const {},
    this.live = false,
    this.fullPage = true,
  });

  final String name;
  final String route;
  final Object? arguments;
  final bool pro;

  /// 描画したあとに行う操作（牌を選ぶ・サブページを開く・偽のカメラのフレームを送るなど）。
  final _Interact? interact;

  /// 追加の SharedPreferences。
  final Map<String, Object> prefs;

  /// ライブ（偽のカメラ・検出器）で描く。
  final bool live;

  /// 縦長（ページ全体）も書き出す。
  final bool fullPage;
}

/// [key] があればタップする（before では無い部品もあるので、無ければ何もしない）。
_Interact _tapIfPresent(String key) => (tester) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) return;
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await _settle(tester);
};

/// 偽のカメラに [labels] の手を [count] フレーム送る（200ms ごと）。
_Interact _sendFrames(List<String> labels, {int count = 8}) => (tester) async {
  final rig = _LiveRig.current!;
  rig.detector.next = () => handBoxes(labels);
  for (var i = 0; i < count; i++) {
    rig.camera.emit();
    await tester.pump();
    rig.clock.now += const Duration(milliseconds: 200);
  }
  await tester.pump();
  await tester.pump();
};

/// 履歴の見本（正解・不正解・未解析・13 枚・前日）。
String _historyJson() {
  HistoryEntry entry(
    String id,
    DateTime at, {
    HandInput? input,
    String? choice,
    bool? correct,
    StrategyAxis? axis,
    List<String> tags = const [],
    int? shanten,
    bool pending = false,
  }) => HistoryEntry(
    id: id,
    createdAt: at,
    input: input ?? _splitHand,
    userChoice: choice,
    axis: axis,
    best: (input ?? _splitHand).isFourteen && !pending
        ? const {
            StrategyAxis.speed: ['1z'],
            StrategyAxis.points: ['8p'],
            StrategyAxis.balance: ['8p'],
          }
        : const {},
    correct: correct,
    reasonTags: tags,
    engineVersion: '1.1.0',
    shanten: shanten,
    pending: pending,
    source: pending ? 'photo' : 'manual',
  );
  final thirteen = HandInput(
    tiles: '1m 2m 3m 4m 5m 6m 7p 8p 9p 2s 3s 4s 5z'.split(' '),
  );
  final entries = [
    entry(
      'h1',
      DateTime(2026, 10, 23, 20, 2),
      choice: '8p',
      correct: true,
      axis: StrategyAxis.balance,
      shanten: 1,
    ),
    entry(
      'h2',
      DateTime(2026, 10, 23, 19, 41),
      choice: '2m',
      correct: false,
      axis: StrategyAxis.speed,
      tags: [ReasonTag.isolatedHonor.code, ReasonTag.penchanFix.code],
      shanten: 1,
    ),
    entry('h3', DateTime(2026, 10, 23, 12, 5), pending: true),
    entry('h4', DateTime(2026, 10, 22, 22, 30), input: thirteen, shanten: 0),
    entry('h5', DateTime(2026, 10, 22, 21, 10), shanten: 1),
  ];
  return jsonEncode([for (final e in entries) e.toJson()]);
}

final _screens = <_Screen>[
  _Screen('quiz', Routes.quiz, arguments: QuizArgs(input: _splitHand)),
  _Screen(
    'quiz_selected',
    Routes.quiz,
    arguments: QuizArgs(input: _splitHand),
    interact: _tapIfPresent('quiz-tile-7'),
  ),
  _Screen(
    'quiz_timed',
    Routes.quiz,
    arguments: QuizArgs(
      input: _splitHand,
      timed: true,
      source: 'today',
      problemId: localDailyProblemId(_today, 2),
    ),
    interact: _tapIfPresent('quiz-tile-13'),
  ),
  const _Screen('live_searching', Routes.live, live: true, fullPage: false),
  _Screen(
    'live_advice',
    Routes.live,
    live: true,
    fullPage: false,
    interact: _sendFrames(HandFixtures.fourteen),
  ),
  _Screen(
    'live_tenpai',
    Routes.live,
    live: true,
    fullPage: false,
    interact: _sendFrames([...HandFixtures.win]..removeLast()),
  ),
  _Screen(
    'candidate_detail',
    Routes.candidateDetail,
    arguments: CandidateDetailArgs(
      input: _splitHand,
      discardId: tileIdFromLabel('8p'),
    ),
  ),
  _Screen(
    'candidate_detail_pro',
    Routes.candidateDetail,
    pro: true,
    arguments: CandidateDetailArgs(
      input: _splitHand,
      discardId: tileIdFromLabel('8p'),
    ),
  ),
  _Screen(
    'explanation_pro',
    Routes.explanation,
    pro: true,
    arguments: CandidateDetailArgs(
      input: _splitHand,
      discardId: tileIdFromLabel('8p'),
    ),
  ),
  _Screen(
    'live_summary',
    Routes.liveSummary,
    arguments: LiveSummaryArgs(
      startedAt: DateTime(2026, 10, 23, 19, 30),
      durationSec: 1460,
      adviceCount: 18,
      followedCount: 9,
      followChecks: 12,
      wins: const [
        LiveWinSummary(
          han: 3,
          fu: 30,
          points: 3900,
          yaku: ['riichi', 'tanyao'],
        ),
      ],
    ),
  ),
  const _Screen('settings', Routes.settings),
  _Screen(
    'settings_live',
    Routes.settings,
    interact: _tapIfPresent('settings-open-live'),
  ),
  _Screen(
    'settings_notifications',
    Routes.settings,
    interact: _tapIfPresent('settings-open-notifications'),
  ),
  _Screen(
    'settings_rules',
    Routes.settings,
    interact: _tapIfPresent('settings-open-rules'),
  ),
  _Screen(
    'history',
    Routes.history,
    prefs: {LocalHistory.preferenceKey: _historyJson()},
  ),
  _Screen(
    'history_pro',
    Routes.history,
    pro: true,
    prefs: {LocalHistory.preferenceKey: _historyJson()},
  ),
  _Screen('publish', Routes.publish, arguments: PublishArgs(input: _splitHand)),
  const _Screen('my_problems', Routes.myProblems),
];

class _Variant {
  const _Variant(this.name, this.locale, this.scale);

  final String name;
  final Locale locale;
  final double scale;
}

const _variants = [
  _Variant('ja', Locale('ja'), 1),
  _Variant('en', Locale('en'), 1),
  _Variant('ja_large', Locale('ja'), 1.3),
];

final _errors = StringBuffer();

/// ライブの偽の部品（1 画面ごとに作り直す）。
class _LiveRig {
  _LiveRig() : camera = _TableCamera();

  static _LiveRig? current;

  final _TableCamera camera;
  final ScriptedDetector detector = ScriptedDetector();
  final ManualLiveClock clock = ManualLiveClock();
  final FakeLiveDevice device = FakeLiveDevice();
}

/// 雀卓の上の手牌を写しているように見せる偽のカメラ（検出の枠と同じ位置に牌の画像を置く）。
class _TableCamera extends FakeLiveCamera {
  List<String> labels = const [];

  @override
  Widget buildPreview() => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      final boxes = handBoxes(labels);
      return Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [Color(0xFF2F6B4A), Color(0xFF173726)],
                ),
              ),
            ),
          ),
          for (final b in boxes)
            Positioned(
              left: b.box.left * size.width,
              top: b.box.top * size.height,
              width: b.box.width * size.width,
              height: b.box.height * size.height,
              child: FittedBox(child: TileImage(b.label, width: 40)),
            ),
        ],
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fontPath = String.fromEnvironment(
      'JAPANESE_FONT_PATH',
      defaultValue: '/mnt/c/Windows/Fonts/meiryo.ttc',
    );
    final japanese = FontLoader(_fontFamily)
      ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
    await japanese.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await Directory(_outputDir).create(recursive: true);
  });

  tearDownAll(() async {
    await File('$_outputDir/errors.txt').writeAsString(
      _errors.isEmpty ? 'no layout errors\n' : _errors.toString(),
    );
  });

  final only = _only.isEmpty ? null : _only.split(',').toSet();
  final onlyVariants = _onlyVariants.isEmpty
      ? null
      : _onlyVariants.split(',').toSet();
  for (final screen in _screens) {
    if (only != null && !only.contains(screen.name)) continue;
    for (final variant in _variants) {
      if (onlyVariants != null && !onlyVariants.contains(variant.name)) {
        continue;
      }
      testWidgets('${screen.name} ${variant.name}', (tester) async {
        await _capture(tester, screen, variant);
      });
    }
  }
}

Future<void> _capture(
  WidgetTester tester,
  _Screen screen,
  _Variant variant,
) async {
  // test/ 外に置いた、flutter test で起動する画像生成ツール。
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({
    'onboarding.completed.v1': true,
    AppAnalytics.preferenceKey: true,
    'streak_v1': '{"current":3,"best":5,"lastAnsweredDate":"2026-10-22"}',
    'daily_solved_v1': '["${localDailyProblemId(_today, 1)}"]',
    'live_trial_v1':
        '{"date":"$_today","usedSeconds":80,"bonusSeconds":0,"bonusGrants":0}',
    liveGuideSeenKey: true,
    ...screen.prefs,
  });
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(390 * 2, 844 * 2);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final rig = screen.live ? _LiveRig() : null;
  _LiveRig.current = rig;
  if (rig != null && screen.name != 'live_searching') {
    rig.camera.labels = screen.name == 'live_tenpai'
        ? ([...HandFixtures.win]..removeLast())
        : HandFixtures.fourteen;
  }

  final captureKey = GlobalKey();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        subscriptionBackendProvider.overrideWithValue(
          FakeSubscriptionBackend(),
        ),
        entitlementsProvider.overrideWith(
          (ref) => screen.pro
              ? const EntitlementState(pro: true)
              : EntitlementState.free,
        ),
        revenueCatApiKeyProvider.overrideWithValue('capture-only'),
        sharedPreferencesProvider.overrideWith(
          (ref) => SharedPreferences.getInstance(),
        ),
        authUidProvider.overrideWith((ref) async => null),
        appAnalyticsProvider.overrideWith((ref) => AppAnalytics()),
        appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
        clockProvider.overrideWithValue(() => _now),
        todayDateProvider.overrideWithValue(_today),
        adsEnabledProvider.overrideWithValue(false),
        analysisServiceProvider.overrideWithValue(
          AnalysisService(
            runner: (hand, deep) async =>
                DefaultNanikiruEngine().analyze(hand, deep: deep),
          ),
        ),
        problemRepositoryProvider.overrideWithValue(
          LocalDailyProblemRepository(
            generate: (date) async => DailyProblemGenerator().generate(date),
          ),
        ),
        if (rig != null) ...[
          liveCameraFactoryProvider.overrideWithValue(() => rig.camera),
          liveDetectorFactoryProvider.overrideWithValue(() => rig.detector),
          liveClockFactoryProvider.overrideWithValue(() => rig.clock),
          liveDeviceProvider.overrideWithValue(rig.device),
        ],
      ],
      child: RepaintBoundary(
        key: captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: variant.locale,
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: _theme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(variant.scale)),
            child: child ?? const SizedBox.shrink(),
          ),
          initialRoute: '/capture',
          onGenerateRoute: (settings) {
            final name = settings.name == '/capture'
                ? screen.route
                : settings.name;
            final builder = appRoutes[name];
            return MaterialPageRoute<void>(
              settings: RouteSettings(
                name: name,
                arguments: settings.name == '/capture'
                    ? screen.arguments
                    : settings.arguments,
              ),
              builder:
                  builder ??
                  (_) => Scaffold(body: Center(child: Text('route:$name'))),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  await _precacheImages(tester);
  await _settle(tester);
  if (screen.interact != null) {
    await screen.interact!(tester);
    await _precacheImages(tester);
    await tester.pump();
  }
  _recordErrors(tester, '${screen.name}_${variant.name}');
  await _write(tester, captureKey, '${screen.name}_${variant.name}.png');

  if (screen.fullPage) {
    // ページ全体（縦長）。
    tester.view.physicalSize = const Size(390 * 2, 2000 * 2);
    await _settle(tester);
    await _precacheImages(tester);
    await _settle(tester);
    _recordErrors(tester, '${screen.name}_${variant.name}_full');
    await _write(tester, captureKey, '${screen.name}_${variant.name}_full.png');
  }

  // 秒読み・ライブのタイマーを止める（画面を外す）。
  await tester.pumpWidget(const SizedBox.shrink());
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  _recordErrors(tester, '${screen.name}_${variant.name}_dispose');
  _LiveRig.current = null;
}

/// 秒読み・アニメーションで止まらない画面もあるので、時間を区切って進める。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _precacheImages(WidgetTester tester) async {
  final elements = find.byType(Image).evaluate().toList();
  await tester.runAsync(() async {
    for (final element in elements) {
      final image = element.widget as Image;
      await precacheImage(image.image, element);
    }
  });
}

void _recordErrors(WidgetTester tester, String label) {
  Object? error;
  while ((error = tester.takeException()) != null) {
    final text = error.toString().split('\n').take(6).join('\n');
    _errors.writeln('[$label] $text\n');
  }
}

Future<void> _write(WidgetTester tester, GlobalKey key, String file) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$_outputDir/$file').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}
