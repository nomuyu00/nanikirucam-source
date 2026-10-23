// 画面の見た目の確認用（UI の刷新の before / after 比較）。ストア素材・審査の証跡には使わない。
//
// flutter test tool/capture_screens_test.dart \
//   --dart-define=CAPTURE_OUTPUT_DIR=/mnt/c/temp/screens/after
//
// 実際の画面（ルート表 appRoutes の画面）を、テスト用の偽の課金・解析・今日の問題で描画し、
// iPhone 相当（390×844）と、ページ全体が入る縦長（390×2000）の PNG に書き出す。
// 文字は日本語・英語・大きな文字（textScaler 1.3）の 3 通り。レイアウトのあふれ
// （RenderFlex overflowed 等）は `<出力先>/errors.txt` に書く。
// 日本語フォントは Windows のメイリオ（WSL では /mnt/c/Windows/Fonts/meiryo.ttc）を読む。
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
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/ui/settings/settings_page.dart';
import 'package:nanikiru_cam/ui/theme/app_theme.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/billing_fakes.dart';

const _fontFamily = 'CaptureJapanese';
const _today = '2026-10-23';
final _now = DateTime(2026, 10, 23, 20, 15);

const _outputDir = String.fromEnvironment(
  'CAPTURE_OUTPUT_DIR',
  defaultValue: '/tmp/nanikiru_screens',
);

/// 書き出す画面だけに絞る（カンマ区切り。空なら全部）。
const _only = String.fromEnvironment('CAPTURE_ONLY');

/// アプリのテーマ（テスト環境にはシステムフォントが無いので、日本語フォントを差す）。
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

class _Screen {
  const _Screen(
    this.name,
    this.route, {
    this.arguments,
    this.pro = false,
    this.prepare,
    this.narrow = false,
  });

  final String name;
  final String route;
  final Object? arguments;
  final bool pro;

  /// 書き出す前の操作（条件を変えるなど）。
  final Future<void> Function(WidgetTester tester)? prepare;

  /// 幅 360px・文字 1.3 倍でも書き出す。
  final bool narrow;
}

// --- 和了の役と点数（Pro） ---------------------------------------------------

HandInput _win(
  String labels, {
  List<String> dora = const [],
  List<MeldInput> melds = const [],
}) {
  final tiles = labels.split(' ');
  return HandInput(
    tiles: tiles,
    tsumoIndex: tiles.length - 1,
    doraIndicators: dora,
    melds: melds,
  );
}

/// 子の門前ツモ・平和・断么九・赤1・ドラ1 = 5 翻の満貫ツモ（2,000・4,000）。
final _winMangan = _win(
  '2m 3m 4m 0m 6m 7m 4p 5p 6s 7s 8s 6s 6s 3p',
  dora: ['1m'],
);

/// 四暗刻（ツモ）。
final _winYakuman = _win('2m 2m 2m 4p 4p 4p 6s 6s 8s 8s 8s 1p 1p 6s');

/// 中をポンした手（副露の表示）。
final _winOpen = _win(
  '2p 3p 4p 5p 6p 7p 3s 4s 5s 6s 6s',
  melds: [
    MeldInput(kind: MeldKind.pon, tiles: const ['7z', '7z', '7z']),
  ],
);

/// 和了形でない 14 枚。
final _winBroken = _win('2m 3m 4m 5m 6m 7m 6p 7p 8p 3s 4s 5s 2p 9p');

/// 共有カード用の計算結果（子の満貫ツモ）。
WinShareData _winShare() {
  final hand = WinHand.fromInput(_winMangan);
  final conditions = WinConditions.fromInput(_winMangan);
  final outcome = scoreWin(WinScorer(Rulesets.mLeague()), hand, conditions);
  return WinShareData(
    hand: hand.toHandInput(conditions),
    request: buildWinRequest(hand, conditions),
    result: (outcome as WinScored).best,
  );
}

Future<void> _tapKey(WidgetTester tester, String key) async {
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
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder);
  // 折りたたみの開閉などのアニメーションを終わらせる。
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 共有カードを 9:16（ストーリー）にする。
Future<void> _storyFormat(WidgetTester tester) async {
  await tester.tap(find.textContaining('9:16'));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 1 本場・供託 1 本・ロン・リーチ（その他の条件を開く）。
Future<void> _honbaKyotaku(WidgetTester tester) async {
  await _tapKey(tester, 'win-type-ron');
  await _tapKey(tester, 'win-riichi-riichi');
  await _tapKey(tester, 'win-more');
  await _tapKey(tester, 'win-honba-plus');
  await _tapKey(tester, 'win-kyotaku-plus');
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  await tester.pump(const Duration(milliseconds: 300));
}

final _screens = <_Screen>[
  const _Screen('home', Routes.home),
  const _Screen('home_pro', Routes.home, pro: true),
  _Screen('result', Routes.result, arguments: ResultArgs(input: _splitHand)),
  _Screen(
    'result_quiz',
    Routes.result,
    arguments: ResultArgs(
      input: _splitHand,
      chosenDiscardId: tileIdFromLabel('8p'),
      chosenAxis: StrategyAxis.balance,
      fromQuiz: true,
    ),
  ),
  _Screen('quiz', Routes.quiz, arguments: QuizArgs(input: _splitHand)),
  const _Screen('settings', Routes.settings),
  const _Screen(
    'paywall',
    Routes.paywall,
    arguments: PaywallArgs(trigger: PaywallTrigger.home),
  ),
  const _Screen('today', Routes.today),
  _Screen(
    'recognition',
    Routes.recognition,
    arguments: RecognitionArgs(
      draft: RecognitionDraft(
        labels: _splitHand.tiles,
        tsumoIndex: 13,
        confidences: [for (var i = 0; i < 14; i++) i == 4 ? 0.42 : 0.95],
      ),
    ),
  ),
  const _Screen('manual', Routes.manualInput),
  const _Screen('history', Routes.history),
  const _Screen('onboarding', Routes.onboarding),
  // 和了の役と点数（Pro）。
  _Screen(
    'win_mangan',
    Routes.winScore,
    arguments: WinScoreArgs(input: _winMangan),
    pro: true,
    narrow: true,
  ),
  _Screen(
    'win_yakuman',
    Routes.winScore,
    arguments: WinScoreArgs(input: _winYakuman),
    pro: true,
  ),
  _Screen(
    'win_honba',
    Routes.winScore,
    arguments: WinScoreArgs(input: _winMangan),
    pro: true,
    prepare: _honbaKyotaku,
    narrow: true,
  ),
  _Screen(
    'win_open',
    Routes.winScore,
    arguments: WinScoreArgs(input: _winOpen),
    pro: true,
  ),
  _Screen(
    'win_error',
    Routes.winScore,
    arguments: WinScoreArgs(input: _winBroken),
    pro: true,
  ),
  _Screen(
    'win_locked',
    Routes.winScore,
    arguments: WinScoreArgs(input: _winMangan),
  ),
  _Screen(
    'win_result_free',
    Routes.result,
    arguments: ResultArgs(input: _winMangan),
  ),
  _Screen(
    'win_result_pro',
    Routes.result,
    arguments: ResultArgs(input: _winMangan),
    pro: true,
  ),
  _Screen(
    'win_recognition',
    Routes.recognition,
    arguments: RecognitionArgs(
      draft: RecognitionDraft(labels: _winMangan.tiles, tsumoIndex: 13),
      mode: HandEntryMode.score,
    ),
    pro: true,
    narrow: true,
  ),
  _Screen(
    'win_card',
    Routes.shareCard,
    arguments: ShareCardArgs(kind: ShareCardKind.win, winShare: _winShare()),
    pro: true,
  ),
  _Screen(
    'win_card_quiz',
    Routes.shareCard,
    arguments: ShareCardArgs(
      kind: ShareCardKind.winQuiz,
      winShare: _winShare(),
    ),
    pro: true,
  ),
  _Screen(
    'win_card_story',
    Routes.shareCard,
    arguments: ShareCardArgs(kind: ShareCardKind.win, winShare: _winShare()),
    pro: true,
    prepare: _storyFormat,
  ),
  _Screen(
    'win_card_quiz_story',
    Routes.shareCard,
    arguments: ShareCardArgs(
      kind: ShareCardKind.winQuiz,
      winShare: _winShare(),
    ),
    pro: true,
    prepare: _storyFormat,
  ),
  const _Screen(
    'win_paywall',
    Routes.paywall,
    arguments: PaywallArgs(trigger: PaywallTrigger.winScore),
  ),
  const _Screen('win_home', Routes.home, narrow: true),
];

class _Variant {
  const _Variant(this.name, this.locale, this.scale, {this.width = 390});

  final String name;
  final Locale locale;
  final double scale;

  /// 画面の幅（論理ピクセル）。
  final double width;
}

const _variants = [
  _Variant('ja', Locale('ja'), 1),
  _Variant('en', Locale('en'), 1),
  _Variant('ja_large', Locale('ja'), 1.3),
];

/// [_Screen.narrow] の画面だけ追加で書き出す（幅 360px）。
const _narrowVariants = [
  _Variant('ja_large_360', Locale('ja'), 1.3, width: 360),
  _Variant('en_large_360', Locale('en'), 1.3, width: 360),
];

final _errors = StringBuffer();

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
  for (final screen in _screens) {
    if (only != null && !only.contains(screen.name)) continue;
    for (final variant in [
      ..._variants,
      if (screen.narrow) ..._narrowVariants,
    ]) {
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
  });
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(variant.width * 2, 844 * 2);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

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
  if (screen.prepare != null) {
    await screen.prepare!(tester);
    await _settle(tester);
  }
  _recordErrors(tester, '${screen.name}_${variant.name}');
  await _write(tester, captureKey, '${screen.name}_${variant.name}.png');

  // ページ全体（縦長）。
  tester.view.physicalSize = Size(variant.width * 2, 2000 * 2);
  await _settle(tester);
  await _precacheImages(tester);
  await _settle(tester);
  _recordErrors(tester, '${screen.name}_${variant.name}_full');
  await _write(tester, captureKey, '${screen.name}_${variant.name}_full.png');
}

/// 秒読み・アニメーションで止まらない画面もあるので、時間を区切って進める。
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var i = 0; i < 10; i++) {
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
