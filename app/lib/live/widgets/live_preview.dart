import 'package:flutter/material.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/live/live_camera.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/live_overlay_painter.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/ml/live_preprocess.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';

/// カメラのプレビューと、認識した牌の枠・おすすめの矢印（仕様 6.3）。
class LivePreviewArea extends StatelessWidget {
  const LivePreviewArea({
    super.key,
    required this.camera,
    required this.controller,
    required this.paused,
  });

  final LiveCamera camera;
  final LiveController controller;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final common = context.commonStrings;
    final ratio = camera.previewAspectRatio;
    final snapshot = controller.snapshot;
    final advice = controller.advice;
    final axis = controller.axis;

    final overlayTiles = <LiveOverlayTile>[];
    int? highlight;
    String? highlightText;
    if (snapshot.tiles.isNotEmpty &&
        snapshot.state != LiveTrackState.dark &&
        snapshot.state != LiveTrackState.far) {
      final tags = <int, String>{};
      if (advice != null && advice.kind == LiveAdviceKind.discard) {
        final labels = snapshot.labels;
        final discard = advice.discardFor(axis);
        if (discard != null) {
          highlight = slotForDiscard(
            labels,
            discard,
            tsumoIndex: controller.tsumoIndex,
          );
          final unsure =
              highlight != null && snapshot.tiles[highlight].lowConfidence;
          highlightText = strings.discard(
            common.tileName(tileLabelOfId(discard)),
            unsure: unsure,
          );
        }
        if (!advice.unanimous) {
          for (final e in advice.bestPerAxis.entries) {
            if (e.key == axis || e.value == discard) continue;
            final slot = slotForDiscard(labels, e.value);
            if (slot != null && slot != highlight) {
              tags[slot] = strings.axisBadge(e.key);
            }
          }
        }
      }
      for (var i = 0; i < snapshot.tiles.length; i++) {
        final t = snapshot.tiles[i];
        overlayTiles.add(
          LiveOverlayTile(
            box: t.box,
            role: advice != null && i < advice.roles.length
                ? advice.roles[i]
                : null,
            lowConfidence: t.lowConfidence,
            label: t.lowConfidence ? '${common.tileName(t.label)}?' : null,
            tag: tags[i],
          ),
        );
      }
    } else {
      for (final t in snapshot.rawTiles) {
        overlayTiles.add(LiveOverlayTile(box: t.box));
      }
    }

    // 手の揺れで案内を保っている間は、推論範囲の案内を出さない（点滅させない）。
    final held = controller.adviceHeld;
    final showRoi = !snapshot.isStable && !held;
    return ColoredBox(
      color: AppColors.camera,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 止まっている間（案内の表示中・一時停止・失敗）は回り続ける表示を出さない。
              camera.isReady
                  ? camera.buildPreview()
                  : ColoredBox(
                      color: AppColors.camera,
                      child: camera.isInitializing
                          ? const Center(child: CircularProgressIndicator())
                          : null,
                    ),
              CustomPaint(
                painter: LiveOverlayPainter(
                  tiles: overlayTiles,
                  highlight: highlight,
                  highlightText: highlightText,
                  roi: _roiFor(ratio),
                  showRoi: showRoi,
                  roiText: showRoi ? strings.roiGuide : null,
                  dimmed: held,
                ),
              ),
              if (paused)
                ColoredBox(
                  color: AppColors.liveScrim,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.pause_circle_outline_rounded,
                          size: 48,
                          color: AppColors.liveText,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.statePaused,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: AppColors.liveText),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 推論範囲（中央の正方形）をプレビューの 0〜1 で。
  static Rect _roiFor(double aspect) {
    if (aspect <= 0) return const Rect.fromLTRB(0, 0, 1, 1);
    // 幅 1000 として、プレビューと同じ縦横比のフレームで中央の正方形を求める。
    return centeredSquareRoi(1000, (1000 / aspect).round());
  }
}
