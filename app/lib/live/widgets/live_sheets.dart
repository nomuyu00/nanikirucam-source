import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/ui/widgets/tile_picker.dart';

/// 待ち牌をタップしたときの「ロン時の役・点数」（仕様 6.3）。
Future<void> showLiveRon(
  BuildContext context,
  LiveController controller,
  LiveAdvice advice,
  WaitInfo wait,
) {
  final strings = context.liveStrings;
  final common = context.commonStrings;
  final ron = wait.ronScore;
  final tile = common.tileName(tileLabelOfId(wait.tileId));
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            0,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TileImage(tileLabelOfId(wait.tileId), width: 36),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      strings.ronWith(tile),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                ron == null ? strings.ronImpossible : strings.ronPossible,
                style: theme.textTheme.headlineSmall,
              ),
              if (ron != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${yakuNames(ron).map(strings.yakuName).join('・')}  '
                  '${strings.hanFu(ron.han, ron.fu)}  '
                  '${strings.points(wait.ronPoints ?? 0)}',
                  style: theme.textTheme.bodyLarge,
                ),
              ],
              if (wait.tsumoPoints != null)
                Text(
                  '${strings.tsumoLabel}: ${strings.points(wait.tsumoPoints!)}',
                  style: theme.textTheme.bodyMedium,
                ),
              if (wait.ronRiichiPoints != null)
                Text(
                  '${strings.riichiLabel} ${strings.ronLabel}: '
                  '${strings.points(wait.ronRiichiPoints!)}',
                  style: theme.textTheme.bodyMedium,
                ),
              const SizedBox(height: AppSpacing.lg),
              if (ron != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      final record = controller.recordRon(wait);
                      Navigator.of(sheetContext).pop();
                      if (record != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(strings.ronRecorded)),
                        );
                      }
                    },
                    icon: const Icon(Icons.emoji_events_outlined),
                    label: Text(strings.recordRon),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// 局の設定（場風・自風・ドラ表示牌。仕様 6.3）。
Future<void> showLiveHandSettings(
  BuildContext context,
  LiveController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _HandSettingsSheet(controller: controller),
  );
}

class _HandSettingsSheet extends HookWidget {
  const _HandSettingsSheet({required this.controller});

  final LiveController controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.liveStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final value = useState(controller.handContext);
    void update(LiveHandContext next) {
      value.value = next;
      controller.setHandContext(next);
    }

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.handSettings, style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(strings.handSettingsNote, style: theme.textTheme.bodySmall),
            label(strings.roundWind),
            SegmentedButton<Wind>(
              showSelectedIcon: false,
              segments: [
                for (final w in [Wind.east, Wind.south])
                  ButtonSegment(value: w, label: Text(common.windName(w))),
              ],
              selected: {value.value.roundWind},
              onSelectionChanged: (s) =>
                  update(value.value.copyWith(roundWind: s.first)),
            ),
            label(strings.seatWind),
            SegmentedButton<Wind>(
              showSelectedIcon: false,
              segments: [
                for (final w in Wind.values)
                  ButtonSegment(value: w, label: Text(common.windName(w))),
              ],
              selected: {value.value.seatWind},
              onSelectionChanged: (s) =>
                  update(value.value.copyWith(seatWind: s.first)),
            ),
            label(strings.doraIndicators),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (value.value.doraIndicators.isEmpty)
                  Text(strings.noDora, style: theme.textTheme.bodyMedium),
                for (var i = 0; i < value.value.doraIndicators.length; i++)
                  InputChip(
                    avatar: TileImage(value.value.doraIndicators[i], width: 18),
                    label: Text(common.tileName(value.value.doraIndicators[i])),
                    onDeleted: () => update(
                      value.value.copyWith(
                        doraIndicators: [...value.value.doraIndicators]
                          ..removeAt(i),
                      ),
                    ),
                  ),
                if (value.value.doraIndicators.length <
                    HandInput.maxDoraIndicators)
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: Text(strings.addDora),
                    onPressed: () async {
                      final picked = await showTilePicker(
                        context,
                        title: strings.doraIndicators,
                      );
                      if (picked == null || tileIdFromLabel(picked) < 0) return;
                      update(
                        value.value.copyWith(
                          doraIndicators: [
                            ...value.value.doraIndicators,
                            picked,
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
