import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/orientation_lock.dart';
import 'package:nanikiru_cam/core/route_observer.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/camera_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/frame_gate.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/live_device.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_session_store.dart';
import 'package:nanikiru_cam/live/live_trial.dart';
import 'package:nanikiru_cam/live/widgets/live_advice_panel.dart';
import 'package:nanikiru_cam/live/widgets/live_overlays.dart';
import 'package:nanikiru_cam/live/widgets/live_preview.dart';
import 'package:nanikiru_cam/live/widgets/live_sheets.dart';
import 'package:nanikiru_cam/live/widgets/live_top_bar.dart';
import 'package:nanikiru_cam/ml/live_preprocess.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';

/// ライブナビ（仕様 3.1・6.3、設計書 3.3）。
///
/// カメラを向けるだけで、手牌の並びが 1 秒以上安定したときに切る牌を案内する。
/// この画面ではどの広告も読み込まない。無料の体験時間（1 日 5 分 + 動画で延長した分）が尽きたら
/// Paywall へ（設計書 10・11 章）。延長の動画は Paywall と Home で見せる。
class LivePage extends ConsumerWidget {
  const LivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trial = ref.watch(liveTrialProvider);
    final store = ref.watch(liveSessionStoreProvider);
    final prefs = ref.watch(sharedPreferencesProvider);
    if (trial.isLoading || store.isLoading || prefs.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.camera,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _LiveScreen(
      trial: trial.value,
      store: store.value,
      guideSeen: prefs.value?.getBool(liveGuideSeenKey) ?? false,
    );
  }
}

class _LiveScreen extends HookConsumerWidget {
  const _LiveScreen({
    required this.trial,
    required this.store,
    required this.guideSeen,
  });

  final LiveTrial? trial;
  final LiveSessionStore? store;
  final bool guideSeen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.liveStrings;
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final sink = ref.read(analyticsSinkProvider);
    final device = ref.read(liveDeviceProvider);

    useEffect(() {
      final handle = OrientationLock.instance.lockPortrait();
      return handle.release;
    }, const []);

    // --- 部品（画面ごとに作って破棄する） ---
    final camera = useMemoized(() => ref.read(liveCameraFactoryProvider)());
    final detector = useMemoized(() => ref.read(liveDetectorFactoryProvider)());
    final clock = useMemoized(() => ref.read(liveClockFactoryProvider)());
    final controller = useMemoized(
      () => LiveController(
        detector: detector,
        analysis: ref.read(analysisServiceProvider),
        clock: clock,
        log: (event, parameters) => sink(event, parameters),
        policy: LiveFrameRatePolicy.fromTarget(
          ref.read(modelConfigProvider).liveTargetFps,
        ),
        // 設定の「最初に表示する軸」（仕様 6.11）。
        initialAxis: ref.read(appSettingsProvider).liveDefaultAxis,
        // 遅い端末ではセッション中により速いモデルへ落ちる（Remote Config で固定していれば null）。
        modelTiering: ref.read(liveModelTieringProvider),
        onAdviceShown: (advice) {
          // 案内が変わったら軽く振動（既定 ON）。音は既定 OFF（仕様 3.1.3）。
          final settings = ref.read(appSettingsProvider);
          if (settings.liveHaptics) unawaited(HapticFeedback.lightImpact());
          if (settings.liveSound) {
            unawaited(SystemSound.play(SystemSoundType.click));
          }
        },
      ),
    );
    useEffect(
      () => () {
        camera.onFrame = null;
        camera.dispose();
        controller.dispose();
        unawaited(detector.dispose());
      },
      const [],
    );
    useListenable(camera);
    useListenable(controller);

    // 設定（仕様 6.11）。設定の読み込みが Live を開いた後に終わっても反映する。
    final settings = ref.watch(appSettingsProvider);
    useEffect(() {
      controller.applyDefaultAxis(settings.liveDefaultAxis);
      return null;
    }, [settings.liveDefaultAxis]);

    // --- 体験時間・終了 ---
    final startedAt = useMemoized(() => ref.read(clockProvider)());
    final initialTrial = useMemoized(
      () =>
          trial?.load(pro: pro) ??
          LiveTrialState(date: localDateKey(startedAt), unlimited: pro),
    );
    final staySeconds = useRef(0);
    final unsavedTrialSeconds = useRef(0);
    final usedSeconds = useState(initialTrial.usedSeconds);
    final ended = useRef(false);
    // カメラと推論が使える状態に一度でもなったか（`live_started` を送ったか）。
    final started = useRef(false);
    final guideAccepted = useState(guideSeen);
    final paused = useState(false);
    final routeVisible = useState(true);
    final resumed = useState(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    final detectorStatus = useState<_DetectorStatus>(_DetectorStatus.loading);
    final thermal = useState(ThermalStatus.normal);
    final battery = useState(BatteryStatus.unknown);
    final torch = useState(false);
    final gate = pro ? 'pro' : 'free_trial';

    Future<void> flushTrial() async {
      final seconds = unsavedTrialSeconds.value;
      unsavedTrialSeconds.value = 0;
      if (seconds > 0 && !pro) await trial?.addSeconds(seconds, pro: pro);
    }

    final container = ProviderScope.containerOf(context, listen: false);

    /// 終了の計測（`live_state` の割合と `live_ended`）と、このセッションの記録。
    (LiveSession, bool) recordEnd(String endedBy) {
      final duration = staySeconds.value;
      for (final e in controller.stateRatiosPct().entries) {
        sink(AnalyticsEvent.liveState, {
          'state': e.key.analyticsName,
          'ratio_pct': e.value,
        });
      }
      sink(AnalyticsEvent.liveEnded, {
        'duration_s': duration,
        'gate': gate,
        'ended_by': endedBy,
      });
      final session = controller.buildSession(
        startedAt: startedAt,
        durationSec: duration,
        endedBy: endedBy,
      );
      // 開いてすぐ閉じただけのセッションは残さない。
      final meaningful =
          duration >= 5 || session.adviceCount > 0 || session.wins.isNotEmpty;
      return (session, meaningful);
    }

    Future<void> end(String endedBy) async {
      if (ended.value) return;
      ended.value = true;
      camera.onFrame = null;
      unawaited(camera.setActive(false));
      await flushTrial();
      if (!started.value) {
        // カメラか推論が使える状態になる前に閉じた（準備中・モデルやカメラの失敗）。
        // 体験時間は数えておらず、計測もセッションの記録もサマリーも出さない。
        if (context.mounted) Navigator.of(context).pop();
        return;
      }
      final (session, meaningful) = recordEnd(endedBy);
      if (meaningful) await store?.add(session);
      container.invalidate(liveTrialStateProvider);
      container.invalidate(liveSessionsProvider);
      if (!context.mounted) return;
      final navigator = Navigator.of(context);
      if (endedBy == 'trial_limit') {
        await navigator.pushReplacementNamed(
          Routes.paywall,
          arguments: PaywallArgs(
            trigger: PaywallTrigger.liveTrialEnded,
            liveAdviceCount: session.adviceCount,
            liveWinCount: session.wins.length,
          ),
        );
      } else if (!meaningful) {
        navigator.pop();
      } else {
        await navigator.pushReplacementNamed(
          Routes.liveSummary,
          arguments: session.toSummaryArgs(),
        );
      }
    }

    // 体験を使い切っていたら、カメラを開かずに Paywall へ。
    final exhaustedAtStart = !pro && initialTrial.exhausted;
    useEffect(() {
      if (exhaustedAtStart) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted || ended.value) return;
          ended.value = true;
          unawaited(
            Navigator.of(context).pushReplacementNamed(
              Routes.paywall,
              arguments: const PaywallArgs(
                trigger: PaywallTrigger.liveTrialEnded,
                liveAdviceCount: 0,
                liveWinCount: 0,
              ),
            ),
          );
        });
        return null;
      }
      unawaited(device.keepScreenOn(true));
      return () {
        unawaited(device.keepScreenOn(false));
        // 「終了」を通らずに閉じられた（別の処理が pop した）ときも計測と記録は残す。
        // 使える状態になる前なら何も残さない。
        if (ended.value || !started.value) return;
        ended.value = true;
        final (session, meaningful) = recordEnd('user');
        Future.microtask(() async {
          try {
            if (meaningful) await store?.add(session);
            container.invalidate(liveTrialStateProvider);
            container.invalidate(liveSessionsProvider);
          } catch (error) {
            // アプリ全体を閉じたとき（ProviderScope ごと破棄）など。
            debugPrint('[Live] finishing on dispose failed: $error');
          }
        });
      };
    }, const []);

    // 画面の明るさ固定（設定、既定 OFF）。閉じたら端末の設定に戻す。
    useEffect(() {
      if (exhaustedAtStart || !settings.liveLockBrightness) return null;
      unawaited(device.lockBrightness(true));
      return () => unawaited(device.lockBrightness(false));
    }, [settings.liveLockBrightness]);

    // --- モデルの読み込み ---
    Future<void> loadDetector() async {
      detectorStatus.value = _DetectorStatus.loading;
      try {
        await detector.load();
        if (context.mounted) detectorStatus.value = _DetectorStatus.ready;
      } catch (error) {
        debugPrint('[Live] model load failed: $error');
        if (context.mounted) detectorStatus.value = _DetectorStatus.failed;
      }
    }

    useEffect(() {
      if (!exhaustedAtStart) unawaited(loadDetector());
      return null;
    }, const []);

    // --- カメラの開閉（画面に出ている・前面・一時停止でない・案内を了承済み） ---
    final route = ModalRoute.of(context);
    useEffect(() {
      final observer = _RouteVisibility((v) => routeVisible.value = v);
      if (route != null) appRouteObserver.subscribe(observer, route);
      return () => appRouteObserver.unsubscribe(observer);
    }, [route]);
    useOnAppLifecycleStateChange((previous, current) {
      resumed.value = current == AppLifecycleState.resumed;
    });
    final visible = routeVisible.value && resumed.value && !ended.value;
    final cameraWanted =
        visible && guideAccepted.value && !paused.value && !exhaustedAtStart;
    useEffect(() {
      camera.onFrame = (frame) => controller.onFrame(
        frame,
        quarterTurns: liveQuarterTurns(
          sensorOrientation: camera.sensorOrientation,
          width: frame.width,
          height: frame.height,
        ),
      );
      return null;
    }, const []);
    useEffect(() {
      unawaited(camera.setActive(cameraWanted));
      if (!cameraWanted) torch.value = false;
      return null;
    }, [cameraWanted]);
    useEffect(() {
      controller.setPaused(!cameraWanted);
      return null;
    }, [cameraWanted]);
    final cameraError = camera.error;
    useEffect(() {
      if (cameraError != null) {
        sink(AnalyticsEvent.cameraFailed, {
          'source': 'live',
          'error_code': cameraError.analyticsCode,
        });
      }
      return null;
    }, [cameraError?.code]);

    // --- 使える状態: モデルを読み込み済みで、カメラが動いている（一時停止中を含む） ---
    // それまで（準備中・モデルやカメラの失敗）は体験時間を数えず、セッションも始めない。
    final operational =
        !exhaustedAtStart &&
        detectorStatus.value == _DetectorStatus.ready &&
        cameraError == null &&
        (camera.isReady || (paused.value && started.value));
    useEffect(() {
      if (operational && !started.value && !ended.value) {
        started.value = true;
        sink(AnalyticsEvent.liveStarted, {'gate': gate});
      }
      return null;
    }, [operational]);

    // --- 滞在時間（1 秒ごと）。使える状態で Live 画面に出ている間だけ数える
    // （stable の累積ではない） ---
    final counting = visible && guideAccepted.value && operational;
    useEffect(() {
      if (!counting) return null;
      final timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (ended.value) return;
        staySeconds.value++;
        if (pro) return;
        unsavedTrialSeconds.value++;
        usedSeconds.value++;
        if (unsavedTrialSeconds.value >= 5) unawaited(flushTrial());
        if (usedSeconds.value >= initialTrial.limitSeconds) {
          unawaited(end('trial_limit'));
        }
      });
      return () {
        timer.cancel();
        unawaited(flushTrial());
      };
    }, [counting, pro]);

    // --- 温度・電池 ---
    useEffect(() {
      if (exhaustedAtStart) return null;
      Future<void> pollThermal() async {
        final status = await device.thermal();
        if (!context.mounted || ended.value) return;
        thermal.value = status;
        controller.setThermalWarning(status.warning);
        if (status.critical) unawaited(end('thermal'));
      }

      Future<void> pollBattery() async {
        final status = await device.battery();
        if (!context.mounted || ended.value) return;
        battery.value = status;
        if (status.critical) unawaited(end('battery'));
      }

      unawaited(pollThermal());
      unawaited(pollBattery());
      final thermalTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) => pollThermal(),
      );
      final batteryTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => pollBattery(),
      );
      return () {
        thermalTimer.cancel();
        batteryTimer.cancel();
      };
    }, const []);

    Future<void> acceptGuide() async {
      guideAccepted.value = true;
      try {
        final prefs = await ref.read(sharedPreferencesProvider.future);
        await prefs.setBool(liveGuideSeenKey, true);
      } catch (_) {}
    }

    Future<void> showGuide() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.guideTitle),
        content: const SingleChildScrollView(child: LiveGuideBody()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.commonStrings.close),
          ),
        ],
      ),
    );

    final remaining = pro
        ? null
        : (initialTrial.limitSeconds - usedSeconds.value).clamp(
            0,
            initialTrial.limitSeconds,
          );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(end('user'));
      },
      child: Scaffold(
        key: const ValueKey('live-page'),
        backgroundColor: AppColors.camera,
        body: Stack(
          children: [
            Positioned.fill(
              child: LivePreviewArea(
                camera: camera,
                controller: controller,
                paused: paused.value,
              ),
            ),
            // 上部: 状態・残り時間・一時停止・終了だけ（仕様 6.3）。
            SafeArea(
              child: Column(
                children: [
                  LiveTopBar(
                    controller: controller,
                    remainingSeconds: remaining,
                    paused: paused.value,
                    onPause: () => paused.value = !paused.value,
                    onEnd: () => unawaited(end('user')),
                  ),
                  if (thermal.value.warning)
                    LiveWarningBanner(
                      icon: Icons.thermostat,
                      text: strings.thermalWarning,
                    ),
                  if (battery.value.low)
                    LiveWarningBanner(
                      icon: Icons.battery_alert,
                      text: strings.batteryLow(battery.value.level ?? 0),
                    ),
                ],
              ),
            ),
            // 下部: 案内パネルと、軸・ライト・局の設定・置き方（親指の届く位置）。
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiveAdvicePanel(
                      controller: controller,
                      paused: paused.value,
                      onLight: camera.isReady && !torch.value
                          ? () async {
                              if (await camera.setTorch(true)) {
                                torch.value = true;
                              }
                            }
                          : null,
                    ),
                    LiveControlBar(
                      controller: controller,
                      torch: torch.value,
                      onTorch: camera.isReady
                          ? () async {
                              final next = !torch.value;
                              if (await camera.setTorch(next)) {
                                torch.value = next;
                              }
                            }
                          : null,
                      onHelp: showGuide,
                      onSettings: () =>
                          showLiveHandSettings(context, controller),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.activeWin != null)
              LiveWinOverlay(
                win: controller.activeWin!,
                onNext: controller.dismissWin,
              ),
            if (cameraError != null)
              Positioned.fill(
                child: LiveErrorView(
                  message: context.cameraStrings.errorMessage(cameraError.code),
                  permission: cameraError.isPermission,
                  onRetry: camera.retry,
                  onClose: () => unawaited(end('user')),
                ),
              )
            else if (detectorStatus.value == _DetectorStatus.failed)
              Positioned.fill(
                child: LiveErrorView(
                  message: strings.modelFailed,
                  onRetry: loadDetector,
                  onClose: () => unawaited(end('user')),
                ),
              ),
            if (!guideAccepted.value && !exhaustedAtStart)
              Positioned.fill(child: LiveGuideOverlay(onAccept: acceptGuide)),
          ],
        ),
      ),
    );
  }
}

enum _DetectorStatus { loading, ready, failed }

class _RouteVisibility extends RouteAware {
  _RouteVisibility(this.onChanged);

  final ValueChanged<bool> onChanged;

  @override
  void didPushNext() => onChanged(false);

  @override
  void didPopNext() => onChanged(true);
}
