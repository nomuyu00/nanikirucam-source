import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/live_overlay_painter.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/live/widgets/live_sheets.dart';
import 'package:nanikiru_cam/live/widgets/live_top_bar.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 下部の案内パネル（仕様 6.3）。切る牌を大きく朱で、理由は 1 行で。
/// 手の揺れで案内を保っている間（[LiveController.adviceHeld]）は薄くする。
class LiveAdvicePanel extends StatelessWidget {
  const LiveAdvicePanel({
    super.key,
    required this.controller,
    required this.paused,
    required this.onLight,
  });

  final LiveController controller;
  final bool paused;

  /// 暗いときに出すライトのボタン（点けられないときは null）。
  final VoidCallback? onLight;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final advice = controller.advice;
    final snapshot = controller.snapshot;
    Widget body;
    if (paused) {
      body = _hint(context, strings.statePaused, Icons.pause_circle_outline);
    } else if (advice != null) {
      body = switch (advice.kind) {
        LiveAdviceKind.discard => _DiscardAdvice(
          advice: advice,
          axis: controller.axis,
        ),
        LiveAdviceKind.thirteen => _ThirteenAdvice(
          advice: advice,
          controller: controller,
        ),
        LiveAdviceKind.win => _WinSummaryLine(advice: advice),
      };
    } else if (controller.meldSuspected) {
      body = _hint(context, strings.hintMeld, Icons.photo_camera_outlined);
    } else if (snapshot.isStable && snapshot.block != null) {
      body = _hint(
        context,
        snapshot.block == AdviceBlock.lowConfidence
            ? strings.hintLowConfidence
            : strings.hintImpossible,
        Icons.visibility_outlined,
      );
    } else if (controller.analyzing) {
      body = _hint(context, strings.analyzing, Icons.hourglass_top_rounded);
    } else {
      body = switch (snapshot.state) {
        LiveTrackState.searching =>
          snapshot.tiles.isEmpty
              ? _hint(context, strings.hintSearching, Icons.center_focus_weak)
              : _hint(
                  context,
                  strings.hintConfirming,
                  Icons.center_focus_strong,
                ),
        LiveTrackState.moving => _hint(
          context,
          strings.hintMoving,
          Icons.back_hand_outlined,
        ),
        LiveTrackState.dark => Row(
          children: [
            Expanded(
              child: _hint(
                context,
                strings.hintDark,
                Icons.wb_twilight_rounded,
              ),
            ),
            if (onLight != null)
              TextButton.icon(
                onPressed: onLight,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.liveAccent,
                ),
                icon: const Icon(Icons.flashlight_on_rounded),
                label: Text(strings.light),
              ),
          ],
        ),
        LiveTrackState.far => _hint(
          context,
          strings.hintFar,
          Icons.zoom_in_rounded,
        ),
        LiveTrackState.countMismatch => _hint(
          context,
          strings.hintCount(snapshot.count),
          Icons.view_week_outlined,
        ),
        LiveTrackState.stable => _hint(
          context,
          strings.analyzing,
          Icons.hourglass_top_rounded,
        ),
      };
    }
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('live-advice-panel'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: const BoxDecoration(
        borderRadius: AppRadius.xlAll,
        border: Border.fromBorderSide(
          BorderSide(color: AppColors.liveHairline),
        ),
      ),
      child: Material(
        color: AppColors.livePanel,
        borderRadius: AppRadius.xlAll,
        clipBehavior: Clip.antiAlias,
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(
            color: AppColors.liveText,
          ),
          child: IconTheme(
            data: const IconThemeData(color: AppColors.liveTextMuted),
            // 手の揺れで案内を保っている間は少し薄くする。
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: controller.adviceHeld
                  ? LiveOverlayPainter.dimmedOpacity
                  : 1,
              child: body,
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(BuildContext context, String text, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.lg,
    ),
    child: Row(
      children: [
        Icon(icon, size: 22, color: AppColors.liveTextMuted),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            key: const ValueKey('live-hint'),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.liveText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// 14 枚: 切る牌（大きく朱で）、一択か軸のバッジ、理由 1 行、別解、狙える役と打点。
/// タップで Result（同じ内容をくわしく）。
class _DiscardAdvice extends StatelessWidget {
  const _DiscardAdvice({required this.advice, required this.axis});

  final LiveAdvice advice;
  final StrategyAxis axis;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final discard = advice.discardFor(axis);
    if (discard == null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(strings.analyzing),
      );
    }
    final candidate = advice.candidate(discard);
    final badges = advice.unanimous
        ? [strings.unanimous]
        : [for (final a in advice.axesFor(discard)) strings.axisBadge(a)];
    final alternatives = advice.unanimous
        ? const <String>[]
        : [
            for (final e in advice.bestPerAxis.entries)
              if (e.value != discard)
                strings.alternative(
                  e.key,
                  common.tileName(tileLabelOfId(e.value)),
                ),
          ];
    final prospects = advice.prospects(discard);
    final points = advice.points(discard);
    final shantenAfter = candidate?.shantenAfter;
    final reason = [
      if (shantenAfter != null) common.shanten(shantenAfter),
      if (candidate != null)
        strings.ukeire(candidate.ukeire.kinds, candidate.ukeire.total),
      if (candidate != null) strings.winEase(candidate.winEase),
    ].join(' · ');
    final yaku = [
      prospects.isEmpty
          ? strings.noProspect
          : prospects
                .map(
                  (p) => strings.prospect(strings.yakuOf(p.yaku), p.confidence),
                )
                .join('、'),
      if (points != null) strings.pointRange(points.min, points.max),
    ].join('  ');
    final label = tileLabelOfId(discard);
    return InkWell(
      onTap: () => Navigator.of(
        context,
      ).pushNamed(Routes.result, arguments: ResultArgs(input: advice.input)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md + AppSpacing.xxs,
          AppSpacing.sm,
          AppSpacing.md + AppSpacing.xxs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // 切る牌（Result の結論カードと同じ、牌の面に朱の枠）。
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.tileFace,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(
                      color: AppColors.liveDiscard,
                      width: 2.5,
                    ),
                  ),
                  child: TileImage(
                    label,
                    width: 40,
                    semanticLabel: common.tileName(label),
                  ),
                ),
                const SizedBox(width: AppSpacing.md + AppSpacing.xxs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        strings.discard(common.tileName(label)),
                        key: const ValueKey('live-discard-text'),
                        maxLines: 2,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.liveDiscard,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [for (final b in badges) _Badge(b)],
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.liveTextMuted,
                    ),
                    Text(
                      strings.openDetail,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.liveTextMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm + AppSpacing.xxs),
            // 理由は 1 行（シャンテン・受け入れ・上がりやすさ）。
            Text(
              reason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.liveText,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (alternatives.isNotEmpty)
              Text(
                alternatives.join('  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.liveLink,
                ),
              ),
            Text(
              yaku,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.liveTextMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 13 枚: 向聴、テンパイなら待ちと残り枚数・リーチ可否。待ち牌をタップでロン時の点数。
class _ThirteenAdvice extends StatelessWidget {
  const _ThirteenAdvice({required this.advice, required this.controller});

  final LiveAdvice advice;
  final LiveController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final report = advice.report.thirteen;
    const padding = EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md + AppSpacing.xxs,
      AppSpacing.lg,
      AppSpacing.md + AppSpacing.xxs,
    );
    if (report == null) {
      return Padding(padding: padding, child: Text(strings.analyzing));
    }
    final titleStyle = theme.textTheme.headlineSmall?.copyWith(
      color: AppColors.liveText,
      fontWeight: FontWeight.w800,
    );
    final shanten = report.shanten.shanten;
    if (shanten > 0 || report.waits.isEmpty) {
      return InkWell(
        onTap: () => Navigator.of(
          context,
        ).pushNamed(Routes.result, arguments: ResultArgs(input: advice.input)),
        child: Padding(
          padding: padding,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      common.shanten(shanten),
                      key: const ValueKey('live-thirteen-shanten'),
                      style: titleStyle,
                    ),
                    Text(
                      strings.ukeire(report.draws.kinds, report.draws.total),
                      style: const TextStyle(color: AppColors.liveTextMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
    }
    final total = report.waits.fold<int>(0, (s, w) => s + w.remaining);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.sm + AppSpacing.xxs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                common.shanten(0),
                key: const ValueKey('live-thirteen-shanten'),
                style: titleStyle,
              ),
              Text(
                strings.remaining(total),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.liveText,
                ),
              ),
              Text(
                report.hasYaku ? strings.riichiPossible : strings.noYaku,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: report.hasYaku
                      ? AppColors.liveGood
                      : AppColors.liveCaution,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final w in report.waits)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: ValueKey('live-wait-${w.tileId}'),
                    borderRadius: AppRadius.smAll,
                    onTap: () => showLiveRon(context, controller, advice, w),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 44),
                      padding: const EdgeInsets.fromLTRB(5, 5, 5, 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.liveHairline),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(1.5),
                            decoration: BoxDecoration(
                              color: AppColors.tileFace,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: TileImage(
                              tileLabelOfId(w.tileId),
                              width: 28,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            strings.remaining(w.remaining),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.liveTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            strings.tapWaitHint,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.liveTextFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _WinSummaryLine extends StatelessWidget {
  const _WinSummaryLine({required this.advice});

  final LiveAdvice advice;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final win = advice.report.win;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Text(
        [
          strings.tsumoWin,
          if (win != null) strings.hanFu(win.han, win.fu),
          strings.points(advice.report.winPoints ?? 0),
        ].join('  '),
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: AppColors.liveAccent),
      ),
    );
  }
}

/// 「一択」「最速」などの小さな札。
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.liveInfo.withValues(alpha: 0.9),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: AppColors.liveText),
      ),
    );
  }
}

/// 下部の操作（仕様 6.3 の戦略軸の切替、ライト、局の設定と置き方のメニュー）。
/// 親指の届く位置に置く。
class LiveControlBar extends StatelessWidget {
  const LiveControlBar({
    super.key,
    required this.controller,
    required this.torch,
    required this.onTorch,
    required this.onSettings,
    required this.onHelp,
  });

  final LiveController controller;
  final bool torch;
  final VoidCallback? onTorch;
  final VoidCallback onSettings;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<StrategyAxis>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: AppColors.livePanel,
                foregroundColor: AppColors.liveText,
                selectedBackgroundColor: AppColors.liveText,
                selectedForegroundColor: AppColors.camera,
                side: const BorderSide(color: AppColors.liveHairline),
                minimumSize: const Size(0, 44),
                textStyle: theme.textTheme.labelLarge,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                shape: const StadiumBorder(),
              ),
              segments: [
                for (final axis in StrategyAxis.values)
                  ButtonSegment(
                    value: axis,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(strings.axisName(axis), maxLines: 1),
                    ),
                  ),
              ],
              selected: {controller.axis},
              onSelectionChanged: (s) => controller.setAxis(s.first),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          LiveRoundButton(
            tooltip: strings.light,
            icon: torch
                ? Icons.flashlight_on_rounded
                : Icons.flashlight_off_rounded,
            active: torch,
            onPressed: onTorch,
          ),
          const SizedBox(width: AppSpacing.xs),
          PopupMenuButton<_LiveMenu>(
            key: const ValueKey('live-menu'),
            tooltip: strings.more,
            position: PopupMenuPosition.over,
            onSelected: (item) => switch (item) {
              _LiveMenu.settings => onSettings(),
              _LiveMenu.help => onHelp(),
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _LiveMenu.settings,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune_rounded),
                  title: Text(strings.handSettings),
                ),
              ),
              PopupMenuItem(
                value: _LiveMenu.help,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help_outline_rounded),
                  title: Text(strings.help),
                ),
              ),
            ],
            icon: const Icon(Icons.more_horiz_rounded),
            iconColor: AppColors.liveText,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              backgroundColor: AppColors.liveGlass,
            ),
          ),
        ],
      ),
    );
  }
}

enum _LiveMenu { settings, help }
