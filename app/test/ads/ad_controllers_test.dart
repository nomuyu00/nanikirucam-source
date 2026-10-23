import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/ads/banner_loader.dart';
import 'package:nanikiru_cam/ads/interstitial_controller.dart';
import 'package:nanikiru_cam/ads/interstitial_pacing.dart';
import 'package:nanikiru_cam/ads/rewarded_ads.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/billing_fakes.dart';

class _FakeInterstitialPort implements InterstitialPort {
  @override
  bool enabled = true;
  int loads = 0;
  int shows = 0;
  bool showResult = true;

  @override
  Future<void> load() async => loads++;

  @override
  Future<bool> show() async {
    shows++;
    return showResult;
  }
}

class _FakeRewardedHandle extends RewardedHandle {
  _FakeRewardedHandle(this.earned, [this.watched]);
  final bool earned;

  /// showTimed が返す「広告を見た時間」。
  final Duration? watched;
  int shows = 0;
  bool disposed = false;

  @override
  Future<bool> show() async {
    shows++;
    return earned;
  }

  @override
  Future<RewardedShowResult> showTimed() async {
    shows++;
    return RewardedShowResult(earned: earned, watched: earned ? watched : null);
  }

  @override
  void dispose() => disposed = true;
}

class _FakeRewardedPort implements RewardedAdsPort {
  final List<AdPlacement> loads = [];
  final List<_FakeRewardedHandle> handles = [];

  /// null の要素は読み込み失敗。空なら成功（動画を最後まで見る）。
  final List<bool?> script = [];
  Completer<void>? gate;

  /// 次に読み込む広告が返す「見た時間」。
  Duration? watched;

  @override
  Future<RewardedHandle?> load(AdPlacement placement) async {
    loads.add(placement);
    final g = gate;
    if (g != null) await g.future;
    final next = script.isEmpty ? true : script.removeAt(0);
    if (next == null) return null;
    final handle = _FakeRewardedHandle(next, watched);
    handles.add(handle);
    return handle;
  }
}

/// show だけを実装した偽物（showTimed の既定実装の確認用）。
class _ShowOnlyGate extends RewardedGate {
  _ShowOnlyGate(this.result);
  final bool result;

  @override
  bool isReady(RewardKind kind) => true;

  @override
  Future<bool> show(RewardKind kind) async => result;
}

void main() {
  group('全画面広告の間隔制御（PacedInterstitialController）', () {
    late DateTime now;
    late SharedPreferences prefs;
    late _FakeInterstitialPort port;
    late PacedInterstitialController controller;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      now = DateTime(2026, 10, 21, 12);
      port = _FakeInterstitialPort();
      controller = PacedInterstitialController(
        pacing: () async => InterstitialPacing(prefs, now: () => now),
        port: port,
        now: () => now,
      );
    });

    Future<void> results(int n) async {
      for (var i = 0; i < n; i++) {
        await controller.onResultViewed();
      }
    }

    test('最初の 3 回の結果では出さない。4 回目から出せる', () async {
      await results(3);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 0);
      await results(1);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
    });

    test('出したあとは結果 3 回たまるまで出さない', () async {
      await results(4);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
      now = now.add(const Duration(minutes: 10));
      await results(2);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
      await results(1);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 2);
    });

    test('前回から 4 分以上空ける', () async {
      await results(4);
      await controller.maybeShowBeforeNextHand();
      await results(3);
      now = now.add(const Duration(minutes: 3, seconds: 59));
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
      now = now.add(const Duration(seconds: 1));
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 2);
    });

    test('共有した直後は出さない。次の結果を見れば元に戻る', () async {
      await results(5);
      controller.onShared();
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 0);
      await controller.onResultViewed();
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
    });

    test('共有から 2 分たてば「直後」ではない', () async {
      await results(5);
      controller.onShared();
      now = now.add(const Duration(minutes: 2, seconds: 1));
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
    });

    test('Pro・同意なし（enabled=false）では出さず、読み込みもしない', () async {
      port.enabled = false;
      await results(6);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 0);
      expect(port.loads, 0);
    });

    test('出せる条件に近づいたら先に読み込んでおく', () async {
      await results(3);
      expect(port.loads, 0, reason: '最初の 3 回は読み込まない');
      await results(1);
      expect(port.loads, 1);
    });

    test('表示できなかった（読み込み前など）ときは間隔を進めない', () async {
      port.showResult = false;
      await results(4);
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 1);
      port.showResult = true;
      await controller.maybeShowBeforeNextHand();
      expect(port.shows, 2);
    });

    test('InterstitialController の契約（void の onResultViewed など）で使える', () async {
      final adapter = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWith(
            (ref) => SharedPreferences.getInstance(),
          ),
          adsEnabledProvider.overrideWithValue(false),
        ],
      );
      addTearDown(adapter.dispose);
      final c = adapter.read(interstitialControllerProvider);
      c.onResultViewed();
      c.onShared();
      await c.maybeShowBeforeNextHand();
      await pumpEventQueue();
    });
  });

  group('動画広告（RewardedAdsGate）', () {
    late _FakeRewardedPort port;
    late RecordingAnalytics analytics;
    var enabled = true;
    late RewardedAdsGate gate;

    setUp(() {
      port = _FakeRewardedPort();
      analytics = RecordingAnalytics();
      enabled = true;
      gate = RewardedAdsGate(
        port: port,
        enabled: () => enabled,
        analytics: analytics.call,
        retryDelay: const Duration(milliseconds: 10),
        maxRetries: 2,
      );
      addTearDown(gate.dispose);
    });

    test('読み込み済みになるまでは ready ではない。読み込めたら通知する', () async {
      var notified = 0;
      gate.addListener(() => notified++);
      expect(gate.isReady(RewardKind.quota), isFalse);
      await pumpEventQueue();
      expect(port.loads, [AdPlacement.quotaReward]);
      expect(gate.isReady(RewardKind.quota), isTrue);
      expect(notified, 1);
    });

    test('用途ごとに別のユニットを読み込む', () async {
      gate.preload(RewardKind.quota);
      gate.isReady(RewardKind.explanation);
      await pumpEventQueue();
      expect(port.loads, containsAll([
        AdPlacement.quotaReward,
        AdPlacement.explanationReward,
      ]));
    });

    test('最後まで見たら true と rewarded_granted{reward} を返し、次を読み込む', () async {
      gate.preload(RewardKind.quota);
      await pumpEventQueue();
      expect(await gate.show(RewardKind.quota), isTrue);
      expect(analytics.last(AnalyticsEvent.rewardedGranted)!.parameters, {
        'reward': 'quota',
      });
      expect(port.handles.first.disposed, isTrue);
      await pumpEventQueue();
      expect(port.loads, hasLength(2));
      expect(gate.isReady(RewardKind.quota), isTrue);
    });

    test('途中で閉じたら false。報酬は記録しない', () async {
      port.script.add(false);
      gate.preload(RewardKind.quota);
      await pumpEventQueue();
      expect(await gate.show(RewardKind.quota), isFalse);
      expect(analytics.count(AnalyticsEvent.rewardedGranted), 0);
    });

    test('ライブ延長（liveTrial）は専用のユニットを読み込み、見た時間を返す。reward は live_trial', () async {
      port.watched = const Duration(seconds: 17);
      expect(gate.isReady(RewardKind.liveTrial), isFalse);
      await pumpEventQueue();
      expect(port.loads, [AdPlacement.liveTrialReward]);
      expect(gate.isReady(RewardKind.liveTrial), isTrue);

      final result = await gate.showTimed(RewardKind.liveTrial);
      expect(result.earned, isTrue);
      expect(result.watched, const Duration(seconds: 17));
      expect(analytics.last(AnalyticsEvent.rewardedGranted)!.parameters, {
        'reward': 'live_trial',
      });
      expect(port.handles.first.disposed, isTrue);
    });

    test('ライブ延長の広告は、聞かれるまで読み込まない（起動時に読まない）', () async {
      gate.preload(RewardKind.quota);
      await pumpEventQueue();
      expect(port.loads, [AdPlacement.quotaReward]);
    });

    test('ライブ延長: 報酬なし（途中で閉じた）なら earned=false・見た時間なし・記録なし', () async {
      port.script.add(false);
      port.watched = const Duration(seconds: 30);
      expect(gate.isReady(RewardKind.liveTrial), isFalse);
      await pumpEventQueue();
      final result = await gate.showTimed(RewardKind.liveTrial);
      expect(result.earned, isFalse);
      expect(result.watched, isNull);
      expect(analytics.count(AnalyticsEvent.rewardedGranted), 0);
    });

    test('見た時間が取れなかったときは watched が null（延長は +1 分扱い）', () async {
      expect(gate.isReady(RewardKind.liveTrial), isFalse);
      await pumpEventQueue();
      final result = await gate.showTimed(RewardKind.liveTrial);
      expect(result.earned, isTrue);
      expect(result.watched, isNull);
      expect(LiveTrial.bonusSecondsFor(result.watched), 60);
    });

    test('show(liveTrial) も使える（契約は変わらない）', () async {
      expect(gate.isReady(RewardKind.liveTrial), isFalse);
      await pumpEventQueue();
      expect(await gate.show(RewardKind.liveTrial), isTrue);
    });

    test('読み込み前・無効なときの showTimed は報酬なし', () async {
      expect((await gate.showTimed(RewardKind.liveTrial)).earned, isFalse);
      enabled = false;
      expect((await gate.showTimed(RewardKind.quota)).earned, isFalse);
    });

    test('RewardedGate.showTimed の既定実装は show を呼び、時間なしを返す', () async {
      final yes = await _ShowOnlyGate(true).showTimed(RewardKind.liveTrial);
      expect(yes.earned, isTrue);
      expect(yes.watched, isNull);
      final no = await _ShowOnlyGate(false).showTimed(RewardKind.liveTrial);
      expect(no.earned, isFalse);
    });

    test('読み込み前の show は false（広告を出さない）', () async {
      expect(await gate.show(RewardKind.quota), isFalse);
    });

    test('読み込みに失敗したら少し待って再試行し、上限で止まる', () async {
      port.script.addAll([null, null, null, null]);
      gate.preload(RewardKind.quota);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 最初の 1 回 + 再試行 2 回。
      expect(port.loads, hasLength(3));
      expect(gate.isReady(RewardKind.quota), isFalse);
    });

    test('Pro・同意なしでは読み込まず、ready にもならない', () async {
      enabled = false;
      gate.preload(RewardKind.quota);
      expect(gate.isReady(RewardKind.quota), isFalse);
      await pumpEventQueue();
      expect(port.loads, isEmpty);
    });

    test('読み込み後に無効になったら、読み込み済みの広告は出さない', () async {
      gate.preload(RewardKind.quota);
      await pumpEventQueue();
      enabled = false;
      expect(gate.isReady(RewardKind.quota), isFalse);
      expect(await gate.show(RewardKind.quota), isFalse);
      expect(port.handles.first.shows, 0);
    });

    test('破棄すると読み込み済みの広告も破棄する', () async {
      gate.preload(RewardKind.quota);
      await pumpEventQueue();
      final handle = port.handles.single;
      gate.dispose();
      expect(handle.disposed, isTrue);
    });

    test('読み込み中に破棄されて届いた広告は捨てる', () async {
      port.gate = Completer<void>();
      gate.preload(RewardKind.quota);
      await pumpEventQueue();
      gate.dispose();
      port.gate!.complete();
      await pumpEventQueue();
      expect(port.handles.single.disposed, isTrue);
    });
  });

  group('AdBannerSlot', () {
    Widget app({
      required bool enabled,
      required BannerLoader loader,
      AdPlacement placement = AdPlacement.homeBanner,
    }) {
      return ProviderScope(
        overrides: [
          adsEnabledProvider.overrideWithValue(enabled),
          bannerLoaderProvider.overrideWithValue(loader),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AdBannerSlot(placement: placement),
          ),
        ),
      );
    }

    testWidgets('Pro・同意なしでは読み込まず、何も描かない', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        app(
          enabled: false,
          loader: (placement, width) async {
            loads++;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(loads, 0);
      expect(find.byKey(const ValueKey('test-banner')), findsNothing);
      expect(tester.getSize(find.byType(AdBannerSlot)).height, 0);
    });

    testWidgets('有効なら幅を渡して読み込み、読み込めたバナーを出す', (tester) async {
      AdPlacement? seenPlacement;
      int? seenWidth;
      var disposed = false;
      await tester.pumpWidget(
        app(
          enabled: true,
          placement: AdPlacement.resultBanner,
          loader: (placement, width) async {
            seenPlacement = placement;
            seenWidth = width;
            return BannerHandle(
              widget: const SizedBox(key: ValueKey('test-banner')),
              height: 60,
              dispose: () => disposed = true,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(seenPlacement, AdPlacement.resultBanner);
      expect(seenWidth, 800);
      expect(find.byKey(const ValueKey('test-banner')), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('test-banner'))).height, 60);

      await tester.pumpWidget(const SizedBox());
      expect(disposed, isTrue);
    });

    testWidgets('読み込みに失敗したら何も描かず、再試行もしない', (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        app(
          enabled: true,
          loader: (placement, width) async {
            loads++;
            return null;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(loads, 1);
      expect(tester.getSize(find.byType(AdBannerSlot)).height, 0);
    });

    testWidgets('Pro になったらバナーを外して破棄する', (tester) async {
      var disposed = false;
      final enabled = StateProvider<bool>((ref) => true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            adsEnabledProvider.overrideWith((ref) => ref.watch(enabled)),
            bannerLoaderProvider.overrideWithValue(
              (placement, width) async => BannerHandle(
                widget: const SizedBox(key: ValueKey('test-banner')),
                height: 50,
                dispose: () => disposed = true,
              ),
            ),
            ],
          child: const MaterialApp(
            home: Scaffold(
              bottomNavigationBar: AdBannerSlot(
                placement: AdPlacement.historyBanner,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-banner')), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AdBannerSlot)),
      );
      container.read(enabled.notifier).state = false;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('test-banner')), findsNothing);
      expect(disposed, isTrue);
    });
  });
}
