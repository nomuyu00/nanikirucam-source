// 流用元: reference/agari_cam/lib/ui/recognition/recognition_page.dart（2026-10-21 時点）の
// 牌選択シート（_showTilePicker）を、他の画面（Today の回答など）でも使えるよう切り出した。
import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 牌選択シートの上部に並べるボタン。押すと [id] が結果として返る。
class TilePickerAction {
  const TilePickerAction(this.id, this.icon, this.label);

  final String id;
  final IconData icon;
  final String label;
}

/// 牌を 1 枚選ぶシートを出す。
///
/// 返り値は、選んだ牌のラベル（`5m` / `0p` など）か、押した [actions] の `id`。
/// 閉じただけなら null。[suggestions] は「もしかして」として先頭に並べる。
/// [isDisabled] が true を返す牌は選べない（4 枚そろっている牌など）。
Future<String?> showTilePicker(
  BuildContext context, {
  required String title,
  String? highlight,
  List<String> suggestions = const [],
  List<TilePickerAction> actions = const [],
  bool Function(String label)? isDisabled,
}) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _TilePickerSheet(
      title: title,
      highlight: highlight,
      suggestions: suggestions,
      actions: actions,
      isDisabled: isDisabled,
      onPick: (label) => Navigator.of(sheetContext).pop(label),
    ),
  );
}

/// 牌をタップするたびに [onPick] を呼ぶシートを出し、「完了」で閉じる。
/// [counter] はタイトルの横に出す現在の枚数。
Future<void> showTileMultiPicker(
  BuildContext context, {
  required String title,
  required void Function(String label) onPick,
  int Function()? counter,
  bool Function(String label)? isDisabled,
  List<String> Function()? selected,
  void Function(int index)? onRemoveSelected,
  VoidCallback? onClear,
  String? emptyHint,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _TilePickerSheet(
      title: title,
      isDisabled: isDisabled,
      counter: counter,
      selected: selected,
      onRemoveSelected: onRemoveSelected,
      onClear: onClear,
      emptyHint: emptyHint,
      multi: true,
      onPick: onPick,
      onDone: () => Navigator.of(sheetContext).pop(),
    ),
  );
}

class _TilePickerSheet extends StatefulWidget {
  const _TilePickerSheet({
    required this.title,
    required this.onPick,
    this.highlight,
    this.suggestions = const [],
    this.actions = const [],
    this.isDisabled,
    this.multi = false,
    this.counter,
    this.selected,
    this.onRemoveSelected,
    this.onClear,
    this.emptyHint,
    this.onDone,
  });

  final String title;
  final String? highlight;
  final List<String> suggestions;
  final List<TilePickerAction> actions;
  final bool Function(String label)? isDisabled;
  final bool multi;
  final int Function()? counter;
  final List<String> Function()? selected;
  final void Function(int index)? onRemoveSelected;
  final VoidCallback? onClear;
  final String? emptyHint;
  final void Function(String label) onPick;
  final VoidCallback? onDone;

  @override
  State<_TilePickerSheet> createState() => _TilePickerSheetState();
}

class _TilePickerSheetState extends State<_TilePickerSheet> {
  @override
  Widget build(BuildContext context) {
    final common = context.commonStrings;
    final choices = allTileLabels();
    final selected = widget.selected?.call() ?? const <String>[];
    final title = widget.counter == null
        ? widget.title
        : '${widget.title}  (${common.tileCount(widget.counter!())})';
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  for (final action in widget.actions)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: OutlinedButton.icon(
                        onPressed: () => widget.onPick(action.id),
                        icon: Icon(action.icon, size: 18),
                        label: Text(action.label),
                      ),
                    ),
                  if (widget.onClear != null)
                    TextButton(
                      onPressed: () {
                        widget.onClear!();
                        setState(() {});
                      },
                      child: Text(common.clear),
                    ),
                  if (widget.multi)
                    FilledButton(
                      onPressed: widget.onDone,
                      child: Text(common.done),
                    ),
                ],
              ),
            ),
            if (widget.selected != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < selected.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InputChip(
                            avatar: TileImage(selected[i], width: 16),
                            label: Text(common.tileName(selected[i])),
                            onDeleted: widget.onRemoveSelected == null
                                ? null
                                : () {
                                    widget.onRemoveSelected!(i);
                                    setState(() {});
                                  },
                          ),
                        ),
                      if (selected.isEmpty && widget.emptyHint != null)
                        Text(
                          widget.emptyHint!,
                          style: const TextStyle(color: Colors.black54),
                        ),
                    ],
                  ),
                ),
              ),
            if (widget.suggestions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    Text(
                      '${common.maybe}: ',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final label in widget.suggestions)
                      ActionChip(
                        avatar: TileImage(label, width: 18),
                        label: Text(common.tileName(label)),
                        onPressed: () => widget.onPick(label),
                      ),
                  ],
                ),
              ),
            const Divider(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 64,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 0.72,
                ),
                itemCount: choices.length,
                itemBuilder: (_, i) {
                  final label = choices[i];
                  final highlighted = label == widget.highlight;
                  final disabled = widget.isDisabled?.call(label) ?? false;
                  return Semantics(
                    button: true,
                    enabled: !disabled,
                    label: common.tileName(label),
                    child: InkWell(
                      key: ValueKey('tile-picker-$label'),
                      borderRadius: BorderRadius.circular(6),
                      onTap: disabled
                          ? null
                          : () {
                              widget.onPick(label);
                              if (widget.multi) setState(() {});
                            },
                      child: Opacity(
                        opacity: disabled ? 0.3 : 1,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: highlighted
                                  ? AppColors.jade
                                  : Colors.black12,
                              width: highlighted ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Column(
                            children: [
                              Expanded(child: TileImage(label, width: 34)),
                              Text(
                                common.tileName(label),
                                style: const TextStyle(fontSize: 10),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
