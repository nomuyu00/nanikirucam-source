// 流用元: reference/agari_cam/lib/camera/camera_page.dart（2026-10-21 時点）
// 改修: ガイド文言をなにきるカム用に変更。あがりかむ固有の「事前入力」「対局成績の撮影」を外し、
// 手入力・写真選択を追加。仕様 9 章により Camera には広告を出さないのでバナーも外した。
// 撮影後は RecognitionLoadingArgs を持って Routes.recognitionLoading へ進む。
// 写真解析の無料枠の残り回数を表示する（消費は認識画面で行う。camera/photo_quota.dart）。
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/camera/camera_session.dart';
import 'package:nanikiru_cam/camera/photo_quota.dart';
import 'package:nanikiru_cam/core/orientation_lock.dart';
import 'package:nanikiru_cam/core/route_observer.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/camera_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:url_launcher/url_launcher.dart';

class CameraPage extends HookConsumerWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.cameraStrings;
    final analytics = ref.read(appAnalyticsProvider);
    const analyticsSource = 'camera';
    // 点数計算（Pro）から来たら、認識のあとの修正画面を点数計算モードにする。
    final mode = context.routeArgs<CameraArgs>()?.mode ?? HandEntryMode.solve;
    final scoring = mode == HandEntryMode.score;
    useEffect(() {
      unawaited(
        analytics.logEvent(
          AnalyticsEvent.cameraOpened,
          parameters: {'source': analyticsSource},
        ),
      );
      return null;
    }, const []);
    useEffect(() {
      final handle = OrientationLock.instance.lockPortrait();
      return handle.release;
    }, const []);

    final session = useMemoized(CameraSession.new);
    useEffect(() {
      return session.dispose;
    }, [session]);
    final routeVisible = useState(true);
    final route = ModalRoute.of(context);
    useEffect(() {
      final observer = _CameraRouteVisibility(
        (visible) => routeVisible.value = visible,
      );
      if (route != null) appRouteObserver.subscribe(observer, route);
      return () => appRouteObserver.unsubscribe(observer);
    }, [route]);
    // Background transitions may stop frames. Release the camera directly
    // from the lifecycle callback, without waiting for another widget build.
    useOnAppLifecycleStateChange((previous, current) {
      unawaited(
        session.setActive(
          routeVisible.value && current == AppLifecycleState.resumed,
        ),
      );
    });
    useEffect(() {
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      unawaited(
        session.setActive(
          routeVisible.value &&
              (lifecycle == null || lifecycle == AppLifecycleState.resumed),
        ),
      );
      return null;
    }, [session, routeVisible.value]);
    useListenable(session);
    final controller = session.controller;
    final cameraError = session.error;
    useEffect(() {
      if (cameraError != null) {
        final errorCode = switch (cameraError.code) {
          'CameraAccessDenied' ||
          'CameraAccessDeniedWithoutPrompt' ||
          'CameraAccessRestricted' => 'permission_denied',
          'NoCameraAvailable' || 'NoBackCamera' => 'camera_unavailable',
          _ => 'camera_start_failed',
        };
        unawaited(
          analytics.logEvent(
            AnalyticsEvent.cameraFailed,
            parameters: {'source': analyticsSource, 'error_code': errorCode},
          ),
        );
      } else if (controller != null) {
        unawaited(
          analytics.logEvent(
            AnalyticsEvent.cameraReady,
            parameters: {'source': analyticsSource},
          ),
        );
      }
      return null;
    }, [controller, cameraError?.code]);
    final capturing = useState(false);
    final torch = useState(false);
    useEffect(() {
      torch.value = false;
      return null;
    }, [controller]);

    void openManualInput() => Navigator.of(context).pushNamed(
      Routes.manualInput,
      arguments: scoring
          ? RecognitionArgs(draft: RecognitionDraft.empty, mode: mode)
          : null,
    );

    // カメラ画面は黒地（プレビューを主役にする）。手入力は下部の操作列にだけ置く。
    return Scaffold(
      backgroundColor: AppColors.camera,
      appBar: AppBar(
        backgroundColor: AppColors.camera,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white),
        title: Text(scoring ? strings.scoreTitle : strings.title),
        actions: [
          if (controller != null && session.error == null)
            IconButton(
              tooltip: strings.light,
              onPressed: () async {
                final next = !torch.value;
                try {
                  await controller.setFlashMode(
                    next ? FlashMode.torch : FlashMode.off,
                  );
                  torch.value = next;
                } catch (_) {}
              },
              icon: Icon(
                torch.value ? Icons.flashlight_on : Icons.flashlight_off,
              ),
            ),
          IconButton(
            tooltip: strings.settings,
            onPressed: () => Navigator.of(context).pushNamed(Routes.settings),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: session.error != null
                ? ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: _CameraErrorView(
                      error: session.error!,
                      onRetry: session.retry,
                      onManualEntry: openManualInput,
                    ),
                  )
                : controller == null
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      // 写る範囲＝撮影される範囲になるよう、縦横比を保って全体を表示する。
                      ColoredBox(
                        color: AppColors.camera,
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: _portraitPreviewRatio(controller),
                            child: CameraPreview(controller),
                          ),
                        ),
                      ),
                      // 手牌の列は画面の長辺に沿って置くので、ガイドは 90° 回して表示する。
                      // 認識は写真を回してから行う（TfliteService.recognize）。
                      Center(
                        child: RotatedBox(
                          quarterTurns: 1,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _GuideLabel(
                                scoring
                                    ? strings.scoreTopGuide
                                    : strings.topGuide,
                              ),
                              const SizedBox(height: 8),
                              Builder(
                                builder: (context) {
                                  final height = MediaQuery.of(
                                    context,
                                  ).size.height;
                                  final frameWidth = height * 0.80;
                                  final frameHeight = frameWidth * 0.35;
                                  return Container(
                                    width: frameWidth,
                                    height: frameHeight,
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: AppColors.liveRecommend,
                                        width: 2,
                                      ),
                                      borderRadius: AppRadius.smAll,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              _GuideLabel(strings.bottomGuide),
                            ],
                          ),
                        ),
                      ),
                      // 写真解析の無料枠（仕様 3.2）。Pro は「無制限」。
                      const Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: Center(child: QuotaRemainingChip()),
                      ),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _SideAction(
                    icon: Icons.photo_library_outlined,
                    label: strings.pickPhoto,
                    onPressed: capturing.value
                        ? null
                        : () async {
                            capturing.value = true;
                            try {
                              await _onPickPhoto(context, strings, mode);
                            } finally {
                              if (context.mounted) capturing.value = false;
                            }
                          },
                  ),
                  RawMaterialButton(
                    key: const ValueKey('camera-shutter'),
                    onPressed:
                        controller == null ||
                            session.error != null ||
                            capturing.value
                        ? null
                        : () async {
                            // A second tap can arrive before the disabled button
                            // has been rebuilt in the next frame.
                            if (capturing.value) return;
                            capturing.value = true;
                            try {
                              await _onShutterPressed(
                                context,
                                controller,
                                strings,
                                analytics: analytics,
                                analyticsSource: analyticsSource,
                                isCameraActive: () =>
                                    identical(session.controller, controller),
                                mode: mode,
                              );
                            } finally {
                              if (context.mounted) capturing.value = false;
                            }
                          },
                    elevation: 0,
                    constraints: const BoxConstraints.tightFor(
                      width: 76,
                      height: 76,
                    ),
                    fillColor: Colors.white,
                    shape: const CircleBorder(
                      side: BorderSide(color: AppColors.jade, width: 4),
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: AppColors.jade,
                      size: 30,
                    ),
                  ),
                  _SideAction(
                    icon: Icons.grid_view_rounded,
                    label: strings.manualInput,
                    onPressed: openManualInput,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// シャッターの左右の小さな操作（アイコンと短い文字）。
class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null ? Colors.white38 : Colors.white;
    return SizedBox(
      width: 88,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: label,
            onPressed: onPressed,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              minimumSize: const Size(52, 52),
            ),
            icon: Icon(icon),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _GuideLabel extends StatelessWidget {
  const _GuideLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.liveScrim,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: Colors.white),
      ),
    );
  }
}

class _CameraRouteVisibility extends RouteAware {
  _CameraRouteVisibility(this.onChanged);

  final ValueChanged<bool> onChanged;

  @override
  void didPushNext() => onChanged(false);

  @override
  void didPopNext() => onChanged(true);
}

double _portraitPreviewRatio(CameraController controller) {
  final size = controller.value.previewSize;
  if (size == null || size.width <= 0 || size.height <= 0) return 9 / 16;
  final shortSide = size.shortestSide;
  final longSide = size.longestSide;
  return shortSide / longSide;
}

class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({
    required this.error,
    required this.onRetry,
    required this.onManualEntry,
  });

  final CameraException error;
  final VoidCallback onRetry;
  final VoidCallback onManualEntry;

  bool get _permissionError =>
      error.code == 'CameraAccessDenied' ||
      error.code == 'CameraAccessDeniedWithoutPrompt';

  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    final strings = context.cameraStrings;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(strings.errorMessage(error.code), textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_permissionError &&
                    defaultTargetPlatform == TargetPlatform.iOS)
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse('app-settings:')),
                    icon: const Icon(Icons.settings),
                    label: Text(common.openSettings),
                  ),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: Text(common.retry),
                ),
                OutlinedButton.icon(
                  onPressed: onManualEntry,
                  icon: const Icon(Icons.keyboard_alt_outlined),
                  label: Text(strings.manualInput),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _onShutterPressed(
  BuildContext context,
  CameraController controller,
  CameraStrings strings, {
  required AppAnalytics analytics,
  required String analyticsSource,
  required bool Function() isCameraActive,
  HandEntryMode mode = HandEntryMode.solve,
}) async {
  final watch = Stopwatch()..start();
  var captureCompleted = false;
  unawaited(
    analytics.logEvent(
      AnalyticsEvent.captureStarted,
      parameters: {'source': analyticsSource},
    ),
  );
  try {
    await configureCaptureQuality(controller);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!context.mounted || !isCameraActive()) return;
    final shot = await controller.takePicture();
    final bytes = await shot.readAsBytes();
    captureCompleted = true;
    unawaited(
      analytics.logEvent(
        AnalyticsEvent.captureSucceeded,
        parameters: {
          'source': analyticsSource,
          'duration_ms': watch.elapsedMilliseconds,
        },
      ),
    );
    if (!context.mounted || !isCameraActive()) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    await Navigator.of(context).pushNamed<Object?>(
      Routes.recognitionLoading,
      arguments: RecognitionLoadingArgs(imageBytes: bytes, mode: mode),
    );
  } catch (error) {
    if (!captureCompleted) {
      unawaited(
        analytics.logEvent(
          AnalyticsEvent.captureFailed,
          parameters: {
            'source': analyticsSource,
            'duration_ms': watch.elapsedMilliseconds,
            'error_code': 'capture_failed',
          },
        ),
      );
    }
    if (!context.mounted || !isCameraActive()) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${strings.captureFailed}: $error')));
  }
}

/// 端末の写真から 1 枚選んで認識に進む。
Future<void> _onPickPhoto(
  BuildContext context,
  CameraStrings strings,
  HandEntryMode mode,
) async {
  try {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed<Object?>(
      Routes.recognitionLoading,
      arguments: RecognitionLoadingArgs(imageBytes: bytes, mode: mode),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${strings.pickFailed}: $error')));
  }
}
