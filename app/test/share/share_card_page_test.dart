import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/share_card_page.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/share/share_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../problems/fakes.dart';

class _FakeInterstitial implements InterstitialController {
  int shared = 0;

  @override
  void onResultViewed() {}

  @override
  void onShared() => shared++;

  @override
  Future<void> maybeShowBeforeNextHand() async {}
}

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final share = FakeShareService();
  final interstitial = _FakeInterstitial();
  final repository = FakeProblemRepository();
  final analyticsBackend = RecordingBackend();
  final routes = <(String, Object?)>[];
  bool? popResult;

  Future<void> pump(
    ShareCardArgs? args, {
    bool pro = false,
    UserProfile? profile = const UserProfile(
      uid: 'me',
      nickname: 'まじゃおう',
      referralCode: 'ABCD2345',
    ),
    StreakState streak = const StreakState(current: 5, best: 9),
  }) async {
    SharedPreferences.setMockInitialValues({
      'analytics.collection_consent.v1': true,
    });
    final analytics = AppAnalytics(backend: analyticsBackend);
    await analytics.initialize();
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          shareServiceProvider.overrideWithValue(share),
          interstitialControllerProvider.overrideWithValue(interstitial),
          analysisServiceProvider.overrideWithValue(fakeAnalysisService()),
          problemRepositoryProvider.overrideWithValue(repository),
          appAnalyticsProvider.overrideWith((ref) => analytics),
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          streakProvider.overrideWith(() => _FixedStreak(streak)),
          entitlementsProvider.overrideWith(
            (ref) => pro
                ? const EntitlementState(
                    pro: true,
                    source: EntitlementSource.store,
                  )
                : EntitlementState.free,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: testLocalizationsDelegates,
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute<void>(
                settings: RouteSettings(name: '/', arguments: args),
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () async {
                        popResult = await Navigator.of(
                          context,
                        ).pushNamed<bool>(Routes.shareCard, arguments: args);
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              );
            }
            if (settings.name == Routes.shareCard) {
              return MaterialPageRoute<bool>(
                settings: settings,
                builder: (_) => const ShareCardPage(),
              );
            }
            routes.add((settings.name ?? '', settings.arguments));
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: Text('route:${settings.name}')),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder get frame => find.byType(ShareCardFrame);
  CardQr get qr => tester.widget<CardQr>(find.byType(CardQr));
  List<String> get events => analyticsBackend.events;
}

class _FixedStreak extends StreakNotifier {
  _FixedStreak(this._state);

  final StreakState _state;

  @override
  StreakState build() => _state;
}

void main() {
  final hand = sampleHand().normalized();

  group('問題カード（公開済みの問題の再共有）', () {
    testWidgets('QR は問題ページ（?ref= つき）、出題者名はプロフィール、回答数も載る', (tester) async {
      final h = _Harness(tester);
      h.repository.problems['AbC12345'] = sampleProblem(
        stats: const ProblemStats(total: 52, correct: 20),
      );
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      expect(h.qr.url, 'https://nanikiru-cam.web.app/p/AbC12345?ref=ABCD2345');
      expect(find.text('出題: まじゃおう'), findsOneWidget);
      expect(find.text('52人が回答'), findsOneWidget);
      expect(find.text('この手、何切る？'), findsOneWidget);
    });

    testWidgets('透かしは無料のときだけ', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      expect(
        find.byKey(const ValueKey('share-card-watermark')),
        findsOneWidget,
      );

      final pro = _Harness(tester);
      await pro.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
        pro: true,
      );
      expect(find.byKey(const ValueKey('share-card-watermark')), findsNothing);
    });

    testWidgets('サイズを 1:1 とストーリー（9:16）で切り替えられる', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      expect(tester.getSize(h.frame), ShareCardFormat.square.logicalSize);
      await tester.tap(find.text('ストーリー 9:16'));
      await tester.pumpAndSettle();
      expect(tester.getSize(h.frame), ShareCardFormat.story.logicalSize);
    });

    testWidgets('共有: 1080px 幅で書き出して共有シートへ。広告の間隔制御と分析に伝える', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();

      expect(h.share.capturePixelRatios, [3.0]);
      final shared = h.share.shared.single;
      expect(shared.files, 1);
      expect(shared.subject, 'なにきるカム');
      expect(
        shared.text,
        contains('https://nanikiru-cam.web.app/p/AbC12345?ref=ABCD2345'),
      );
      expect(shared.text, contains('この手、何切る？'));
      expect(h.interstitial.shared, 1);
      expect(h.events, ['share_tapped', 'result_shared']);
      expect(h.analyticsBackend.parameters.last, {
        'share_format': 'feed',
        'share_variant': 'quiz',
        'share_target': 'x',
      });
    });

    testWidgets('ストーリーで共有しても同じ 1080px 幅（ストーリーの比率）', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      await tester.tap(find.text('ストーリー 9:16'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();
      expect(h.share.capturePixelRatios, [3.0]);
      expect(h.analyticsBackend.parameters.last['share_format'], 'story');
    });

    testWidgets('共有シートを閉じただけ（未完了）なら共有済みにしない', (tester) async {
      final h = _Harness(tester);
      h.share.completed = false;
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();
      expect(h.events, ['share_tapped']);
      expect(h.interstitial.shared, 0);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(h.popResult, isFalse);
    });

    testWidgets('共有できたら戻り値 true で戻る', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(h.popResult, isTrue);
    });

    testWidgets('共有に失敗しても画面は残り、メッセージを出す', (tester) async {
      final h = _Harness(tester);
      h.share.shareError = StateError('boom');
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();
      expect(find.text('共有できませんでした'), findsOneWidget);
      expect(find.byKey(const ValueKey('share-card-share')), findsOneWidget);
    });

    testWidgets('画像の保存（許可なしならメッセージ）', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.problem,
          input: hand,
          problemId: 'AbC12345',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('share-card-save')));
      await tester.pumpAndSettle();
      expect(h.share.saved, 1);
      expect(find.text('写真に保存しました'), findsOneWidget);
      expect(h.events, ['share_card_saved']);

      h.share.saveAllowed = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('share-card-save')));
      await tester.pumpAndSettle();
      expect(find.textContaining('許可されていません'), findsOneWidget);
    });

    testWidgets('未公開の問題（problemId なし）は公開画面へ進む', (tester) async {
      final h = _Harness(tester);
      await h.pump(ShareCardArgs(kind: ShareCardKind.problem, input: hand));
      final (name, args) = h.routes.single;
      expect(name, Routes.publish);
      expect((args! as PublishArgs).input, hand);
    });
  });

  group('結果カード', () {
    testWidgets('あなた／正解／受け入れ／みんなの正解率／ストリーク。QR は問題へ', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.result,
          input: hand,
          chosenDiscardId: 17, // 9p（速さ軸の解）
          problemId: 'AbC12345',
          outcome: ProblemAnswerOutcome.fromJson(
            answerResponseJson(correct: false),
          ),
        ),
      );
      expect(find.text('惜しい！'), findsOneWidget);
      expect(find.text('速さ重視なら正解'), findsOneWidget);
      expect(find.text('受け入れ 8枚 vs 31枚'), findsOneWidget);
      expect(find.text('みんなの正解率 58%'), findsOneWidget);
      expect(find.text('連続 5日'), findsOneWidget);
      expect(h.qr.url, 'https://nanikiru-cam.web.app/p/AbC12345?ref=ABCD2345');
      // 共有文言。
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();
      expect(h.share.shared.single.text, contains('#何切る'));
      expect(h.analyticsBackend.parameters.last['share_variant'], 'result');
    });

    testWidgets('回答の集計が渡されていなければ、問題から正解率を読む', (tester) async {
      final h = _Harness(tester);
      h.repository.problems['AbC12345'] = sampleProblem(
        stats: const ProblemStats(total: 10, correct: 2),
      );
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.result,
          input: hand,
          chosenDiscardId: 4, // 5m
          problemId: 'AbC12345',
        ),
      );
      expect(find.text('正解！'), findsOneWidget);
      expect(find.text('みんなの正解率 20%'), findsOneWidget);
      // 低正解率の難問に正解 → 共有文言に正解率が入る。
      await tester.tap(find.byKey(const ValueKey('share-card-share')));
      await tester.pumpAndSettle();
      expect(h.share.shared.single.text, contains('正解率20%の難問に正解'));
    });

    testWidgets('問題の公開前の手: 正解率は載せず、QR はストア（または Web）', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.result,
          input: hand,
          chosenDiscardId: 4,
        ),
      );
      expect(find.byKey(const ValueKey('result-card-community')), findsNothing);
      expect(h.qr.url, isNot(contains('/p/')));
      expect(h.qr.url, contains('nanikiru'));
    });

    testWidgets('解析できない手ならカードを作れない旨を出す', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.result,
          input: HandInput(tiles: const ['1m', '1m', '1m', '1m', '1m']),
        ),
      );
      expect(find.text('このカードに必要なデータがありません'), findsOneWidget);
    });
  });

  group('その他のカード', () {
    testWidgets('ライブ節目（初和了）', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        const ShareCardArgs(
          kind: ShareCardKind.liveMilestone,
          win: LiveWinSummary(han: 3, fu: 30, points: 3900, yaku: ['リーチ']),
          firstWin: true,
        ),
      );
      expect(find.text('ナビ付きで初和了！'), findsOneWidget);
      expect(find.text('友人戦・練習用'), findsOneWidget);
      expect(
        h.qr.url,
        anyOf(contains('play.google.com'), contains('nanikiru-cam.web.app')),
      );
    });

    testWidgets('ライブのサマリー', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.liveSummary,
          live: LiveSummaryArgs(
            startedAt: DateTime(2026, 10, 21),
            durationSec: 600,
            adviceCount: 4,
            followedCount: 3,
            wins: const [LiveWinSummary(han: 1, fu: 30, points: 1000)],
          ),
        ),
      );
      expect(find.text('今日の成果'), findsOneWidget);
      expect(find.text('10分'), findsOneWidget);
    });

    testWidgets('ストリークは streakProvider を読む', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        const ShareCardArgs(kind: ShareCardKind.streak),
        streak: const StreakState(current: 30, best: 41),
      );
      expect(find.text('30日'), findsOneWidget);
      expect(find.text('自己ベスト 41日'), findsOneWidget);
    });

    testWidgets('週間', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        ShareCardArgs(
          kind: ShareCardKind.weekly,
          weekly: WeeklySummary(
            weekStart: DateTime(2026, 10, 19),
            answered: 10,
            correct: 6,
            hardProblems: const [
              WeeklyProblemResult(correct: true, communityRate: 0.2),
            ],
          ),
        ),
      );
      expect(find.text('正解率 60%'), findsOneWidget);
      expect(find.text('みんなの正解率 20%'), findsOneWidget);
    });

    testWidgets('必要な引数がなければ案内を出す', (tester) async {
      final h = _Harness(tester);
      await h.pump(const ShareCardArgs(kind: ShareCardKind.weekly));
      expect(find.text('このカードに必要なデータがありません'), findsOneWidget);
      await h.pump(null);
      expect(find.text('このカードに必要なデータがありません'), findsOneWidget);
    });
  });
}
