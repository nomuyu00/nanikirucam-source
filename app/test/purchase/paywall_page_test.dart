import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/url_opener.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:nanikiru_cam/purchase/paywall_page.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_backend.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/screens_harness.dart' show FakeRewardedGate;
import '../support/billing_fakes.dart';

void main() {
  late FakeSubscriptionBackend backend;
  late RecordingAnalytics analytics;
  late List<Uri> opened;
  Object? popResult;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = FakeSubscriptionBackend();
    analytics = RecordingAnalytics();
    opened = [];
    popResult = null;
  });

  Future<void> openPaywall(
    WidgetTester tester, {
    PaywallArgs? args,
    String apiKey = 'test_key',
    Locale locale = const Locale('ja'),
    TargetPlatform platform = TargetPlatform.android,
    DateTime? referralUntil,
    EntitlementState? entitlement,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionBackendProvider.overrideWithValue(backend),
          revenueCatApiKeyProvider.overrideWithValue(apiKey),
          sharedPreferencesProvider.overrideWith(
            (ref) => SharedPreferences.getInstance(),
          ),
          authUidProvider.overrideWith((ref) async => 'uid-1'),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(
              UserProfile(uid: 'uid-1', referralProUntil: referralUntil),
            ),
          ),
          if (entitlement != null)
            entitlementsProvider.overrideWith((ref) => entitlement),
          analyticsSinkProvider.overrideWithValue(analytics.call),
          urlOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
          ...overrides,
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          locale: locale,
          supportedLocales: const [Locale('ja'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routes: {
            Routes.paywall: (_) => const PaywallPage(),
            Routes.live: (_) => const Scaffold(body: Text('live-screen')),
          },
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  key: const ValueKey('open'),
                  onPressed: () async {
                    popResult = await Navigator.of(
                      context,
                    ).pushNamed(Routes.paywall, arguments: args);
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
  }

  for (final locale in const [Locale('ja'), Locale('en')]) {
    testWidgets('iOSの解約案内はAppleの手順だけ（${locale.languageCode}）', (tester) async {
      await openPaywall(tester, platform: TargetPlatform.iOS, locale: locale);
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('paywall-cancel-info')))
          .data!;
      expect(label, contains('Apple Account'));
      expect(label, isNot(contains('Google Play')));
      expect(label, isNot(contains('Android')));
    });
  }

  group('未設定モード（RevenueCat のキーなし）', () {
    testWidgets('「準備中」を出し、購入・復元のボタンは出さない', (tester) async {
      await openPaywall(tester, apiKey: '');
      expect(find.byKey(const ValueKey('paywall-not-ready')), findsOneWidget);
      expect(find.text('準備中です'), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-cta')), findsNothing);
      expect(find.byKey(const ValueKey('paywall-restore')), findsNothing);
      // 規約類のリンクは出す。
      expect(find.byKey(const ValueKey('paywall-terms')), findsOneWidget);
      expect(backend.configureCalls, 0);
    });

    testWidgets('表示ごとに paywall_viewed{trigger} を記録する', (tester) async {
      await openPaywall(
        tester,
        apiKey: '',
        args: const PaywallArgs(trigger: PaywallTrigger.quotaExhausted),
      );
      expect(analytics.events, hasLength(1));
      expect(analytics.events.single.event, AnalyticsEvent.paywallViewed);
      expect(analytics.events.single.parameters, {'trigger': 'quota'});

      // 閉じて開き直すと、もう一度記録する。
      Navigator.of(tester.element(find.byType(PaywallPage))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(analytics.count(AnalyticsEvent.paywallViewed), 2);
    });
  });

  group('トリガー別の見出し', () {
    testWidgets('ライブ体験の終了: 直前のライブの案内回数と和了数を見せる', (tester) async {
      await openPaywall(
        tester,
        apiKey: '',
        args: const PaywallArgs(
          trigger: PaywallTrigger.liveTrialEnded,
          liveAdviceCount: 12,
          liveWinCount: 1,
        ),
      );
      expect(find.text('今日のライブ体験は終わりました'), findsOneWidget);
      expect(find.text('このセッションで12回案内、1回和了'), findsOneWidget);
      expect(analytics.last(AnalyticsEvent.paywallViewed)!.parameters, {
        'trigger': 'live_trial',
      });
    });

    testWidgets('ライブ以外のトリガーでは recap を出さない', (tester) async {
      await openPaywall(
        tester,
        apiKey: '',
        args: const PaywallArgs(
          trigger: PaywallTrigger.quotaExhausted,
          liveAdviceCount: 12,
          liveWinCount: 1,
        ),
      );
      expect(find.byKey(const ValueKey('paywall-recap')), findsNothing);
      expect(find.text('今日の解析回数を使い切りました'), findsOneWidget);
    });

    for (final (trigger, headline) in [
      (PaywallTrigger.candidateLocked, 'すべての候補と役の確度は Pro で'),
      (PaywallTrigger.explanationLocked, '解説の詳細は Pro で'),
      (PaywallTrigger.todayLimit, '今日の問題は 1 日 3 問までです'),
      (PaywallTrigger.winScore, '和了の役と点数は Pro で'),
      (PaywallTrigger.home, 'なにきるカム Pro'),
      (PaywallTrigger.settings, 'なにきるカム Pro'),
    ]) {
      testWidgets('${trigger.name}: $headline', (tester) async {
        await openPaywall(
          tester,
          apiKey: '',
          args: PaywallArgs(trigger: trigger),
        );
        expect(find.text(headline), findsOneWidget);
      });
    }

    testWidgets('引数なしなら settings 扱い', (tester) async {
      await openPaywall(tester, apiKey: '');
      expect(analytics.last(AnalyticsEvent.paywallViewed)!.parameters, {
        'trigger': 'settings',
      });
    });

    testWidgets('訴求は ライブナビ → 全候補と役 → 過去の今日の問題 → 役と点数 → 広告なし の順', (
      tester,
    ) async {
      await openPaywall(tester, apiKey: '');
      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('ライブナビが無制限'), lessThan(top('全候補と役の確度')));
      expect(top('全候補と役の確度'), lessThan(top('過去の今日の問題も解ける')));
      expect(top('過去の今日の問題も解ける'), lessThan(top('和了の役と点数を計算・共有')));
      expect(top('和了の役と点数を計算・共有'), lessThan(top('広告なし')));
    });

    testWidgets('winScore は paywall_viewed{trigger: win_score}', (
      tester,
    ) async {
      await openPaywall(
        tester,
        apiKey: '',
        args: const PaywallArgs(trigger: PaywallTrigger.winScore),
      );
      expect(analytics.last(AnalyticsEvent.paywallViewed)!.parameters, {
        'trigger': 'win_score',
      });
      expect(find.textContaining('役・符・点数・支払い'), findsOneWidget);
    });

    testWidgets('英語の端末では英語で出す', (tester) async {
      await openPaywall(
        tester,
        apiKey: '',
        locale: const Locale('en'),
        args: const PaywallArgs(trigger: PaywallTrigger.liveTrialEnded),
      );
      expect(find.text('Today\'s Live trial is over'), findsOneWidget);
      expect(find.text('Unlimited Live Navi'), findsOneWidget);
    });
  });

  group('購入', () {
    testWidgets('月額・年額と 7 日間無料を出し、既定は無料トライアル付きの月額', (tester) async {
      await openPaywall(tester);
      expect(
        find.byKey(const ValueKey('paywall-plan-monthly')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('paywall-plan-yearly')), findsOneWidget);
      expect(find.text('¥480 / 月'), findsOneWidget);
      expect(find.text('¥3,200 / 年'), findsOneWidget);
      expect(find.text('7日間無料'), findsOneWidget);
      expect(find.text('7日間無料で試す'), findsOneWidget);
      expect(
        find.textContaining('7日間無料のあと、¥480 / 月が自動で課金されます'),
        findsOneWidget,
      );
      // 解約方法。
      expect(find.byKey(const ValueKey('paywall-cancel-info')), findsOneWidget);
      expect(find.textContaining('Google Play'), findsOneWidget);
      expect(find.textContaining('Apple Account'), findsNothing);
    });

    for (final locale in const [Locale('en'), Locale('ja')]) {
      testWidgets('プランカード: 幅 430・文字 1.3 倍でも あふれない（${locale.languageCode}）', (
        tester,
      ) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openPaywall(tester, locale: locale);
        // RenderFlex のあふれは例外として記録される。
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('paywall-plan-yearly')),
          findsOneWidget,
        );
        expect(
          find.text(locale.languageCode == 'en' ? 'Best value' : 'おすすめ'),
          findsOneWidget,
        );
      });
    }

    testWidgets('年額を選ぶと CTA と注記が年額に変わる', (tester) async {
      await openPaywall(tester);
      await tester.tap(find.byKey(const ValueKey('paywall-plan-yearly')));
      await tester.pumpAndSettle();
      expect(find.text('Pro を始める'), findsOneWidget);
      expect(find.textContaining('¥3,200 が 1 年ごとに自動更新'), findsOneWidget);
    });

    testWidgets('購入に成功したら true を返して閉じ、trial_started を記録する', (tester) async {
      await openPaywall(tester);
      await tester.tap(find.byKey(const ValueKey('paywall-cta')));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsNothing);
      expect(popResult, true);
      expect(backend.purchased.single.kind, PlanKind.monthly);
      expect(analytics.names, contains(AnalyticsEvent.trialStarted));
      expect(find.text('Pro をご利用いただけます。ありがとうございます！'), findsOneWidget);
    });

    testWidgets('キャンセルしたら画面に残り、エラーは出さない', (tester) async {
      await openPaywall(tester);
      backend.purchaseError = const PurchaseCancelledException();
      await tester.tap(find.byKey(const ValueKey('paywall-cta')));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('失敗したらメッセージを出して画面に残る', (tester) async {
      await openPaywall(tester);
      backend.purchaseError = const StoreException('boom');
      await tester.tap(find.byKey(const ValueKey('paywall-cta')));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.text('購入できませんでした。もう一度お試しください。'), findsOneWidget);
    });

    testWidgets('購入中はボタンを無効にして進捗を出す', (tester) async {
      await openPaywall(tester);
      backend.purchaseGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('paywall-cta')));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      final cta = tester.widget<FilledButton>(
        find.byKey(const ValueKey('paywall-cta')),
      );
      expect(cta.onPressed, isNull);
      backend.purchaseGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsNothing);
    });

    testWidgets('RevenueCat を初期化できなかったときも再試行を出し、直れば購入できる', (tester) async {
      backend.configureError = const StoreException('offline');
      await openPaywall(tester);
      expect(
        find.byKey(const ValueKey('paywall-plans-failed')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('paywall-cta')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('paywall-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paywall-cta')), findsOneWidget);
    });

    testWidgets('プランを読み込めなかったら再試行を出す', (tester) async {
      backend.plansError = const StoreException('offline');
      await openPaywall(tester);
      expect(
        find.byKey(const ValueKey('paywall-plans-failed')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('paywall-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paywall-cta')), findsOneWidget);
    });
  });

  group('復元・リンク・Pro 利用中', () {
    testWidgets('復元: 見つからなければその旨、見つかれば復元しましたと出す', (tester) async {
      await openPaywall(tester);
      await tester.tap(find.byKey(const ValueKey('paywall-restore')));
      await tester.pumpAndSettle();
      expect(find.text('復元できる購入が見つかりませんでした。'), findsOneWidget);

      backend.restoreResult = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 12, 1),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('paywall-restore')));
      await tester.pumpAndSettle();
      expect(find.text('購入を復元しました。'), findsOneWidget);
      // 復元で Pro になったら、プラン選択は Pro の状態表示に変わる。
      expect(find.byKey(const ValueKey('paywall-pro-active')), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-cta')), findsNothing);
    });

    testWidgets('規約・プライバシー・特商法のリンクを開く', (tester) async {
      await openPaywall(tester, apiKey: '');
      for (final key in ['terms', 'privacy', 'tokushoho']) {
        final button = find.byKey(ValueKey('paywall-$key'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
      }
      expect(opened.map((u) => u.toString()), [
        'https://aile-net.jp/nanikirucam-terms/',
        'https://aile-net.jp/nanikirucam-privacy-policy/',
        'https://aile-net.jp/nanikirucam-test-purchases/',
      ]);
    });

    testWidgets('購読の管理（解約）はストアの購読ページを開く', (tester) async {
      await openPaywall(tester);
      final button = find.byKey(const ValueKey('paywall-manage-link'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(opened.single, subscriptionManagementUri());
    });

    testWidgets('すでに Pro なら状態と解約の導線を見せる', (tester) async {
      backend.entitlement = StoreEntitlement(
        pro: true,
        until: DateTime.utc(2026, 11, 20),
      );
      await openPaywall(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('paywall-pro-active')), findsOneWidget);
      expect(find.text('Pro をご利用中です'), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-cta')), findsNothing);
      expect(find.byKey(const ValueKey('paywall-manage')), findsOneWidget);
    });

    testWidgets('起動時に Pro と分かっているなら paywall_viewed を記録しない', (tester) async {
      await openPaywall(
        tester,
        entitlement: const EntitlementState(
          pro: true,
          source: EntitlementSource.store,
        ),
      );
      expect(analytics.count(AnalyticsEvent.paywallViewed), 0);
    });

    testWidgets('紹介特典の Pro は由来を出し、解約ボタンは出さない', (tester) async {
      await openPaywall(
        tester,
        apiKey: '',
        referralUntil: DateTime.now().add(const Duration(days: 5)),
      );
      await tester.pumpAndSettle();
      expect(find.text('紹介特典で Pro を利用中'), findsOneWidget);
      expect(find.byKey(const ValueKey('paywall-manage')), findsNothing);
    });
  });

  group('ライブ体験の延長（動画）', () {
    final today = DateTime(2026, 10, 21, 20);
    const liveEnded = PaywallArgs(trigger: PaywallTrigger.liveTrialEnded);
    const button = ValueKey('live-extend-button');

    /// 体験を使い切った状態で Paywall（liveTrialEnded）を開く。
    Future<void> openExhausted(
      WidgetTester tester, {
      required FakeRewardedGate gate,
      PaywallArgs args = liveEnded,
      int bonusSeconds = 0,
      int bonusGrants = 0,
      bool adsEnabled = true,
      Locale locale = const Locale('ja'),
      EntitlementState? entitlement,
      String apiKey = 'test_key',
    }) async {
      SharedPreferences.setMockInitialValues({
        LiveTrial.preferenceKey: jsonEncode({
          'date': '2026-10-21',
          'usedSeconds': 300 + bonusSeconds,
          'bonusSeconds': bonusSeconds,
          'bonusGrants': bonusGrants,
        }),
      });
      await openPaywall(
        tester,
        args: args,
        apiKey: apiKey,
        locale: locale,
        entitlement: entitlement,
        overrides: [
          clockProvider.overrideWithValue(() => today),
          adsEnabledProvider.overrideWithValue(adsEnabled),
          rewardedGateProvider.overrideWith((ref) => gate),
        ],
      );
      await tester.pumpAndSettle();
    }

    testWidgets('体験終了: 購入の下に延長ボタンと、報酬の説明を出す', (tester) async {
      final gate = FakeRewardedGate();
      await openExhausted(tester, gate: gate);
      final extend = find.byKey(button);
      expect(extend, findsOneWidget);
      expect(find.text('動画を見てライブを延長（+1〜3分）'), findsOneWidget);
      expect(find.text('広告が長いほど長く延長されます（今日はあと5回）'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(extend).onPressed, isNotNull);
      // 購入ボタンの邪魔をしない（プランの CTA より下）。
      expect(
        tester.getTopLeft(extend).dy,
        greaterThan(
          tester.getTopLeft(find.byKey(const ValueKey('paywall-cta'))).dy,
        ),
      );
    });

    testWidgets('広告が準備できていないときは無効で「広告を読み込み中」', (tester) async {
      await openExhausted(tester, gate: FakeRewardedGate(ready: false));
      expect(
        tester.widget<OutlinedButton>(find.byKey(button)).onPressed,
        isNull,
      );
      expect(find.text('広告を読み込み中'), findsOneWidget);
      expect(find.textContaining('広告が長いほど'), findsNothing);
    });

    testWidgets('英語の端末では英語で出す', (tester) async {
      await openExhausted(
        tester,
        gate: FakeRewardedGate(),
        locale: const Locale('en'),
        // プランカードの英語表示は狭い幅であふれることがあるので、ここでは出さない。
        apiKey: '',
      );
      expect(
        find.text('Watch a video to extend Live (+1-3 min)'),
        findsOneWidget,
      );
      expect(
        find.text('Longer ads extend Live for longer (5 left today)'),
        findsOneWidget,
      );
    });

    testWidgets('体験終了以外のトリガーでは出さない', (tester) async {
      await openExhausted(
        tester,
        gate: FakeRewardedGate(),
        args: const PaywallArgs(trigger: PaywallTrigger.quotaExhausted),
      );
      expect(find.byKey(const ValueKey('live-extend-panel')), findsNothing);
    });

    testWidgets('広告が使えない（同意なし等）なら出さない', (tester) async {
      await openExhausted(tester, gate: FakeRewardedGate(), adsEnabled: false);
      expect(find.byKey(const ValueKey('live-extend-panel')), findsNothing);
      expect(find.byKey(const ValueKey('paywall-cta')), findsOneWidget);
    });

    testWidgets('Pro なら出さない', (tester) async {
      await openExhausted(
        tester,
        gate: FakeRewardedGate(),
        entitlement: const EntitlementState(
          pro: true,
          source: EntitlementSource.store,
        ),
      );
      expect(find.byKey(const ValueKey('live-extend-panel')), findsNothing);
    });

    for (final (seconds, minutes) in [(8, 1), (15, 2), (30, 3)]) {
      testWidgets('$seconds 秒の広告 → +$minutes 分: 保存・計測・メッセージ・ライブへ戻る', (
        tester,
      ) async {
        final gate = FakeRewardedGate(watched: Duration(seconds: seconds));
        await openExhausted(tester, gate: gate);
        await tester.tap(find.byKey(button));
        await tester.pumpAndSettle();

        expect(gate.shown, [RewardKind.liveTrial]);
        // ライブへ戻る（Paywall は置き換えられる）。
        expect(find.text('live-screen'), findsOneWidget);
        expect(find.byType(PaywallPage), findsNothing);
        expect(find.text('ライブが+$minutes分延長されました'), findsOneWidget);

        final prefs = await SharedPreferences.getInstance();
        expect(jsonDecode(prefs.getString(LiveTrial.preferenceKey)!), {
          'date': '2026-10-21',
          'usedSeconds': 300,
          'bonusSeconds': minutes * 60,
          'bonusGrants': 1,
        });
        expect(analytics.last(AnalyticsEvent.liveTrialExtended)!.parameters, {
          'bonus_s': minutes * 60,
          'trigger': 'live_trial',
        });
        // Home 用の状態も読み直される。
        final container = ProviderScope.containerOf(
          tester.element(find.text('live-screen')),
        );
        final state = await container.read(liveTrialStateProvider.future);
        expect(state.limitSeconds, 300 + minutes * 60);
        expect(state.exhausted, isFalse);
      });
    }

    testWidgets('表示時刻が取れなかった（watched なし）ときは +1 分', (tester) async {
      final gate = FakeRewardedGate();
      await openExhausted(tester, gate: gate);
      await tester.tap(find.byKey(button));
      await tester.pumpAndSettle();
      expect(find.text('ライブが+1分延長されました'), findsOneWidget);
    });

    testWidgets('途中で閉じた（報酬なし）: 延長せず、Paywall に残る', (tester) async {
      final gate = FakeRewardedGate(
        result: false,
        watched: const Duration(seconds: 30),
      );
      await openExhausted(tester, gate: gate);
      await tester.tap(find.byKey(button));
      await tester.pumpAndSettle();

      expect(find.text('動画を最後まで見ると延長されます'), findsOneWidget);
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.text('live-screen'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString(LiveTrial.preferenceKey)!) as Map;
      expect(saved['bonusGrants'], 0);
      expect(analytics.count(AnalyticsEvent.liveTrialExtended), 0);
    });

    testWidgets('1 日 5 回に達していたらボタンを出さず「今日の延長は上限です」', (tester) async {
      await openExhausted(
        tester,
        gate: FakeRewardedGate(),
        bonusSeconds: 600,
        bonusGrants: 5,
      );
      expect(find.byKey(button), findsNothing);
      expect(find.byKey(const ValueKey('live-extend-limit')), findsOneWidget);
      expect(find.text('今日の延長は上限です'), findsOneWidget);
    });

    testWidgets('4 回延長済みなら「あと 1 回」と出す', (tester) async {
      await openExhausted(
        tester,
        gate: FakeRewardedGate(),
        bonusSeconds: 240,
        bonusGrants: 4,
      );
      expect(find.text('広告が長いほど長く延長されます（今日はあと1回）'), findsOneWidget);
    });
  });
}
