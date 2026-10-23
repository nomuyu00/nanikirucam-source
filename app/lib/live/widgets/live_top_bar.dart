import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';

/// ライブの上部（仕様 6.3）。状態バッジ・体験の残り時間・一時停止・終了だけを置き、
/// 軸の切替・ライト・局の設定・置き方は下部（[LiveControlBar]）に置く。
class LiveTopBar extends StatelessWidget {
  const LiveTopBar({
    super.key,
    required this.controller,
    required this.remainingSeconds,
    required this.paused,
    required this.onPause,
    required this.onEnd,
  });

  final LiveController controller;

  /// 体験の残り秒数（Pro は null で出さない）。
  final int? remainingSeconds;
  final bool paused;
  final VoidCallback onPause;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状態と残り時間。並ばなければ残り時間を 2 行目に送る（状態の文字を削らない）。
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: AppSpacing.xs + AppSpacing.xxs,
                  runSpacing: AppSpacing.xs + AppSpacing.xxs,
                  children: [
                    LiveStateBadge(controller: controller, paused: paused),
                    if (remainingSeconds != null)
                      Container(
                        key: const ValueKey('live-trial-remaining'),
                        height: 36,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.liveGlass,
                          borderRadius: AppRadius.pillAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              size: 16,
                              color: AppColors.liveTextMuted,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              strings.trialRemaining(remainingSeconds!),
                              maxLines: 1,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.liveText,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                if (kDebugMode || kProfileMode)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Text(
                      '${controller.lastInferenceMs}ms+${controller.lastPreprocessMs}ms '
                      '${controller.targetFps.toStringAsFixed(0)}fps '
                      '${controller.modelLabel ?? '-'} '
                      'med ${controller.speedMedianMs?.toStringAsFixed(0) ?? '-'}ms'
                      '${controller.switching ? ' (switching)' : ''}',
                      style: const TextStyle(
                        color: AppColors.liveTextFaint,
                        fontSize: 10,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          LiveRoundButton(
            tooltip: paused ? strings.resume : strings.pause,
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            onPressed: onPause,
          ),
          const SizedBox(width: AppSpacing.xs),
          TextButton(
            key: const ValueKey('live-end'),
            onPressed: onEnd,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.liveText,
              backgroundColor: AppColors.liveGlass,
              minimumSize: const Size(56, 44),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              shape: const StadiumBorder(
                side: BorderSide(color: AppColors.liveHairline),
              ),
            ),
            child: Text(strings.end),
          ),
        ],
      ),
    );
  }
}

/// 暗い地の丸いボタン（一時停止・ライトなど）。当たり判定は 44pt。
class LiveRoundButton extends StatelessWidget {
  const LiveRoundButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  /// オンの状態（ライトが点いているなど）。白い地に黒いアイコンにする。
  final bool active;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: active ? AppColors.liveText : AppColors.liveGlass,
        foregroundColor: active ? AppColors.camera : AppColors.liveText,
        disabledBackgroundColor: AppColors.liveGlass,
        disabledForegroundColor: AppColors.liveTextFaint,
      ),
    );
  }
}

/// 状態バッジ（探索中・確定・手が動いています・暗い・遠い・枚数 n・一時停止中）。
/// 色だけに頼らず文字を添え、色は点で見せる。
class LiveStateBadge extends StatelessWidget {
  const LiveStateBadge({
    super.key,
    required this.controller,
    required this.paused,
  });

  final LiveController controller;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final snapshot = controller.snapshot;
    final (text, color) = paused
        ? (strings.statePaused, AppColors.liveIdle)
        : switch (snapshot.state) {
            LiveTrackState.searching => (
              strings.stateSearching,
              AppColors.liveSearching,
            ),
            LiveTrackState.stable => (strings.stateStable, AppColors.liveOk),
            LiveTrackState.moving => (strings.stateMoving, AppColors.liveWarn),
            LiveTrackState.dark => (strings.stateDark, AppColors.liveDark),
            LiveTrackState.far => (strings.stateFar, AppColors.liveFar),
            LiveTrackState.countMismatch => (
              strings.stateCount(snapshot.count),
              AppColors.liveMismatch,
            ),
          };
    return Container(
      key: const ValueKey('live-state-badge'),
      height: 36,
      padding: const EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md + AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.liveGlass,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.liveText),
            ),
          ),
        ],
      ),
    );
  }
}

/// 温度・電池の注意の帯。
class LiveWarningBanner extends StatelessWidget {
  const LiveWarningBanner({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.liveNotice.withValues(alpha: 0.92),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.liveText, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.liveText),
            ),
          ),
        ],
      ),
    );
  }
}
