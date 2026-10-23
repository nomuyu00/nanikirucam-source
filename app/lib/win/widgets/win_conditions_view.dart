import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/ui/widgets/tile_picker.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

/// 和了の条件の入力。よく使うもの（ツモ/ロン・リーチ・一発・風・ドラ）を上に、
/// 偶然役・本場・供託は「その他の条件」に畳む。変えるたびに [onChanged]（即再計算）。
class WinConditionsCard extends StatelessWidget {
  const WinConditionsCard({
    super.key,
    required this.hand,
    required this.conditions,
    required this.onChanged,
  });

  final WinHand hand;
  final WinConditions conditions;
  final ValueChanged<WinConditions> onChanged;

  WinConditions get _c => conditions;

  void _set(WinConditions next) => onChanged(next.sanitized(hand));

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final riichiBlocked = riichiBlocker(hand) != null;
    final ippatsuBlocked = ippatsuBlocker(hand, _c) != null;
    return AppCard(
      key: const ValueKey('win-conditions'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.conditionsHeader, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _LabeledRow(
            label: s.winTypeLabel,
            child: _Segments<WinType>(
              keyPrefix: 'win-type',
              values: WinType.values,
              selected: _c.winType,
              label: (t) => t == WinType.tsumo ? s.tsumo : s.ron,
              onChanged: (t) => _set(_c.copyWith(winType: t)),
            ),
          ),
          _LabeledRow(
            label: s.riichiLabel,
            child: _Segments<RiichiKind>(
              keyPrefix: 'win-riichi',
              values: RiichiKind.values,
              selected: _c.riichi,
              enabled: !riichiBlocked,
              label: (k) => switch (k) {
                RiichiKind.none => s.riichiNone,
                RiichiKind.riichi => s.riichi,
                RiichiKind.doubleRiichi => s.doubleRiichi,
              },
              onChanged: (k) => _set(_c.copyWith(riichi: k)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: _LabeledRow.labelWidth,
              bottom: AppSpacing.sm,
            ),
            child: riichiBlocked
                ? Text(
                    s.openHandNoRiichi,
                    key: const ValueKey('win-riichi-open'),
                    style: theme.textTheme.bodySmall,
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: FilterChip(
                      key: const ValueKey('win-ippatsu'),
                      label: Text(s.ippatsu),
                      selected: _c.ippatsu,
                      onSelected: ippatsuBlocked
                          ? null
                          : (v) => _set(_c.copyWith(ippatsu: v)),
                    ),
                  ),
          ),
          _LabeledRow(
            label: s.roundWind,
            child: _Segments<Wind>(
              keyPrefix: 'win-round',
              values: Wind.values,
              selected: _c.roundWind,
              label: common.windName,
              onChanged: (w) => _set(_c.copyWith(roundWind: w)),
            ),
          ),
          _LabeledRow(
            label: s.seatWind,
            child: _Segments<Wind>(
              keyPrefix: 'win-seat',
              values: Wind.values,
              selected: _c.seatWind,
              label: s.seatChoice,
              onChanged: (w) => _set(_c.copyWith(seatWind: w)),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _IndicatorRow(
            rowKey: const ValueKey('win-dora-row'),
            label: s.doraIndicators,
            tiles: _c.doraIndicators,
            onEdit: () => _editIndicators(context, ura: false),
          ),
          if (_c.isRiichi)
            _IndicatorRow(
              rowKey: const ValueKey('win-ura-row'),
              label: s.uraIndicators,
              tiles: _c.uraIndicators,
              onEdit: () => _editIndicators(context, ura: true),
            ),
          _MoreConditions(hand: hand, conditions: _c, onChanged: _set),
        ],
      ),
    );
  }

  Future<void> _editIndicators(BuildContext context, {required bool ura}) {
    final s = context.winStrings;
    // シートの中でも最新の条件を読めるよう、手元で持つ。
    var current = _c;
    List<String> list() => ura ? current.uraIndicators : current.doraIndicators;
    void update(List<String> next) {
      current = ura
          ? current.copyWith(uraIndicators: next)
          : current.copyWith(doraIndicators: next);
      _set(current);
    }

    return showTileMultiPicker(
      context,
      title: ura ? s.pickUraTitle : s.pickDoraTitle,
      emptyHint: s.pickIndicatorHint,
      selected: list,
      isDisabled: (label) =>
          list().length >= HandInput.maxDoraIndicators ||
          !canAddIndicator(label, hand, current),
      onPick: (label) {
        if (list().length >= HandInput.maxDoraIndicators) return;
        update([...list(), label]);
      },
      onRemoveSelected: (index) => update([...list()]..removeAt(index)),
      onClear: () => update(const []),
    );
  }
}

/// 「見出し ｜ 切り替え」の 1 行。
class _LabeledRow extends StatelessWidget {
  const _LabeledRow({required this.label, required this.child});

  static const double labelWidth = 60;

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// 選択肢の切り替え。幅が足りない（英語・大きな文字）ときは文字を縮めて 1 行に収める。
class _Segments<T> extends StatelessWidget {
  const _Segments({
    required this.keyPrefix,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final String keyPrefix;
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      showSelectedIcon: false,
      style: const ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(0, 40)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      segments: [
        for (final v in values)
          ButtonSegment<T>(
            value: v,
            enabled: enabled,
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label(v),
                key: ValueKey('$keyPrefix-${v is Enum ? v.name : v}'),
                maxLines: 1,
              ),
            ),
          ),
      ],
      selected: {selected},
      onSelectionChanged: (set) {
        if (set.isNotEmpty && set.first != selected) onChanged(set.first);
      },
    );
  }
}

/// ドラ表示牌・裏ドラ表示牌の行。押すと牌の選択シート（追加・外す）。
class _IndicatorRow extends StatelessWidget {
  const _IndicatorRow({
    required this.rowKey,
    required this.label,
    required this.tiles,
    required this.onEdit,
  });

  final Key rowKey;
  final String label;
  final List<String> tiles;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    return InkWell(
      key: rowKey,
      borderRadius: AppRadius.smAll,
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  if (tiles.isEmpty)
                    Text(
                      s.noIndicators,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final t in tiles)
                          TileImage(
                            t,
                            width: 26,
                            semanticLabel: common.tileName(t),
                          ),
                        const Icon(
                          Icons.arrow_right_alt,
                          size: 18,
                          color: AppColors.inkMuted,
                        ),
                        for (final t in tiles)
                          Opacity(
                            opacity: 0.85,
                            child: TileImage(
                              doraFromIndicator(t),
                              width: 20,
                              semanticLabel:
                                  '${s.dora} ${common.tileName(doraFromIndicator(t))}',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.edit_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}

/// その他の条件（偶然役・本場・供託）。何か設定されていれば最初から開く。
class _MoreConditions extends StatelessWidget {
  const _MoreConditions({
    required this.hand,
    required this.conditions,
    required this.onChanged,
  });

  final WinHand hand;
  final WinConditions conditions;
  final ValueChanged<WinConditions> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    final c = conditions;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('win-more'),
        initiallyExpanded: c.extraCount > 0,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        title: Text(s.moreConditions, style: theme.textTheme.labelLarge),
        subtitle: Text(
          s.moreConditionsSummary(c.extraCount),
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Text(s.luckyYaku, style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs + 2,
            runSpacing: AppSpacing.xs,
            children: [
              for (final sit in WinSituation.values)
                FilterChip(
                  key: ValueKey('win-sit-${sit.name}'),
                  label: Text(s.situationName(sit.yakuId)),
                  selected: c.situations.contains(sit),
                  onSelected:
                      !c.situations.contains(sit) &&
                          situationBlocker(sit, hand, c) != null
                      ? null
                      : (_) => onChanged(c.toggle(sit)),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _Stepper(
            stepKey: 'win-honba',
            label: s.honba,
            value: c.honba,
            display: s.honbaValue(c.honba),
            max: kMaxHonba,
            onChanged: (v) => onChanged(c.copyWith(honba: v)),
          ),
          _Stepper(
            stepKey: 'win-kyotaku',
            label: s.kyotaku,
            value: c.kyotaku,
            display: s.kyotakuValue(c.kyotaku),
            max: kMaxKyotaku,
            onChanged: (v) => onChanged(c.copyWith(kyotaku: v)),
          ),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.stepKey,
    required this.label,
    required this.value,
    required this.display,
    required this.max,
    required this.onChanged,
  });

  final String stepKey;
  final String label;
  final int value;
  final String display;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        IconButton(
          key: ValueKey('$stepKey-minus'),
          tooltip: s.decrease,
          onPressed: value <= 0 ? null : () => onChanged(value - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56),
          child: Text(
            display,
            key: ValueKey('$stepKey-value'),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton(
          key: ValueKey('$stepKey-plus'),
          tooltip: s.increase,
          onPressed: value >= max ? null : () => onChanged(value + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }
}
