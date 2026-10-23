// 流用元: reference/agari_cam/lib/ui/recognition/recognition_page.dart（2026-10-21 時点）
// 改修（設計書 2.2・仕様 6.6）: 点数計算の UI を外し、ツモ牌・副露・ドラ表示牌・風・巡目の入力と
// シャンテン数／受け入れのプレビューに置き換えた。確定すると HandInput を持って Quiz（14 枚）か
// Result（13 枚）へ進む。手入力（仕様 3.3）は同じ画面を空の状態から使う（Routes.manualInput）。
// 編集ロジックは recognition_editor.dart に分けてある。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/recognition_strings.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_editor.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/ui/widgets/tile_picker.dart';

class RecognitionPage extends ConsumerStatefulWidget {
  /// [manual] が true なら（[Routes.manualInput]）、引数がなくても空の手牌で始める。
  const RecognitionPage({super.key, this.manual = false});

  final bool manual;

  @override
  ConsumerState<RecognitionPage> createState() => _RecognitionPageState();
}

class _RecognitionPageState extends ConsumerState<RecognitionPage> {
  late RecognitionEditor _editor;
  Uint8List? _imageBytes;
  int _imageQuarterTurns = 0;
  String? _notice;
  bool _initialized = false;
  bool _fromPhoto = false;

  /// 撮るだけモードの未解析の履歴から開いたとき、その記録の ID。
  String? _historyId;

  /// 点数計算モード（Pro）。確定ボタンが「点数を計算」になり、和了の点数画面へ進む。
  bool _scoring = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = context.routeArgs<RecognitionArgs>() ?? RecognitionArgs.manual;
    _editor = RecognitionEditor.fromArgs(args);
    _imageBytes = args.imageBytes;
    _imageQuarterTurns = args.imageQuarterTurns;
    _notice = args.notice;
    _fromPhoto = args.draft.length > 0 && !widget.manual;
    _historyId = args.historyId;
    _scoring = args.mode == HandEntryMode.score;
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  // --- 編集 ---------------------------------------------------------------

  /// [label] をもう 1 枚加えると 5 枚以上になるか。[replacing] は置き換える牌（数えない）。
  bool _isFull(String label, {String? replacing}) {
    var count = _editor.state.countOf(label);
    if (replacing != null &&
        normalizeTileLabel(replacing) == normalizeTileLabel(label)) {
      count--;
    }
    return count >= 4;
  }

  Future<void> _editTile(int index) async {
    final strings = context.recognitionStrings;
    final slot = _editor.state.slots[index];
    final isTsumo = _editor.state.tsumoIndex == index;
    final result = await showTilePicker(
      context,
      title: strings.fixTile,
      highlight: slot.label,
      suggestions: [
        for (final alt in slot.alternatives)
          if (alt != slot.label) alt,
      ],
      actions: [
        TilePickerAction(
          'tsumo',
          Icons.flag_outlined,
          _scoring
              ? (isTsumo ? strings.unmarkWinning : strings.markWinning)
              : (isTsumo ? strings.unmarkTsumo : strings.markTsumo),
        ),
        TilePickerAction(
          'delete',
          Icons.delete_outline,
          context.commonStrings.delete,
        ),
      ],
      isDisabled: (label) => _isFull(label, replacing: slot.label),
    );
    if (!mounted || result == null) return;
    switch (result) {
      case 'tsumo':
        _editor.toggleTsumo(index);
      case 'delete':
        _editor.removeTile(index);
        _logTileEdit('delete', from: slot.label);
      default:
        if (result != slot.label) {
          _editor.replaceTile(index, result);
          _logTileEdit('change', from: slot.label, to: result);
        }
    }
  }

  Future<void> _addTiles() async {
    final strings = context.recognitionStrings;
    await showTileMultiPicker(
      context,
      title: strings.addTilesTitle,
      counter: () => _editor.input.tileCount,
      isDisabled: _isFull,
      onPick: (label) {
        _editor.addTile(label);
        _logTileEdit('add', to: label);
      },
    );
  }

  Future<void> _addMeld() async {
    final strings = context.recognitionStrings;
    final kind = await showModalBottomSheet<MeldKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                strings.meldPickerTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final kind in MeldKind.values)
              ListTile(
                key: ValueKey('meld-kind-${kind.name}'),
                title: Text(strings.meldKind(kind)),
                onTap: () => Navigator.of(sheetContext).pop(kind),
              ),
          ],
        ),
      ),
    );
    if (!mounted || kind == null) return;
    final label = await showTilePicker(
      context,
      title: kind == MeldKind.chi
          ? strings.meldPickerHintChi
          : strings.meldPickerHintOther,
      isDisabled: (label) {
        final id = tileIdFromLabel(label);
        if (kind == MeldKind.chi) {
          // 順子の先頭は 1〜7 の数牌。
          return id < 0 || id >= 27 || id % 9 > 6;
        }
        return false;
      },
    );
    if (!mounted || label == null) return;
    final meld = _buildMeld(kind, label);
    if (meld != null) _editor.addMeld(meld);
  }

  /// 手牌に赤5があれば、副露の 5 にもそれを使う（赤ドラを失わないため）。
  String _preferRed(String normal) {
    if (normal.length != 2 || normal[0] != '5' || normal[1] == 'z') {
      return normal;
    }
    final red = '0${normal[1]}';
    return _editor.state.labels.contains(red) ? red : normal;
  }

  MeldInput? _buildMeld(MeldKind kind, String picked) {
    final id = tileIdFromLabel(picked);
    if (id < 0) return null;
    if (kind == MeldKind.chi) {
      if (id >= 27 || id % 9 > 6) return null;
      return MeldInput(
        kind: kind,
        tiles: [for (var k = 0; k < 3; k++) _preferRed(tileLabelOfId(id + k))],
      );
    }
    final count = kind == MeldKind.pon ? 3 : 4;
    final normal = tileLabelOfId(id);
    return MeldInput(
      kind: kind,
      tiles: [picked, for (var k = 1; k < count; k++) normal],
    );
  }

  Future<void> _pickDora() async {
    final strings = context.recognitionStrings;
    await showTileMultiPicker(
      context,
      title: strings.doraTitle,
      emptyHint: strings.doraTapHint,
      selected: () => _editor.state.doraIndicators,
      onPick: (label) {
        final current = _editor.state.doraIndicators;
        if (current.length >= HandInput.maxDoraIndicators) return;
        _editor.setDoraIndicators([...current, label]);
      },
      onRemoveSelected: (index) {
        final next = [..._editor.state.doraIndicators]..removeAt(index);
        _editor.setDoraIndicators(next);
      },
      onClear: () => _editor.setDoraIndicators(const []),
    );
  }

  void _logTileEdit(String action, {String? from, String? to}) {
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.tileEdited,
            parameters: {
              'source': _fromPhoto ? 'camera' : 'manual',
              'tile_count': _editor.input.tileCount,
              'edit_action': action,
              'tile_from': ?from,
              'tile_to': ?to,
            },
          ),
    );
  }

  // --- 画面遷移 -----------------------------------------------------------

  void _recapture() {
    Navigator.of(context).popUntil(
      (route) => route.settings.name == Routes.camera || route.isFirst,
    );
  }

  void _goNext() {
    final input = _editor.input.normalized();
    if (!input.isAnalyzable) return;
    // 写真から来た手は photo、手入力は manual（計測と履歴。無料枠は手入力では使わない）。
    final source = _fromPhoto ? 'photo' : 'manual';
    if (_scoring) {
      Navigator.of(context).pushNamed(
        Routes.winScore,
        arguments: WinScoreArgs(input: input, source: source, fromEditor: true),
      );
      return;
    }
    if (input.tileCount == HandInput.maxTileCount) {
      Navigator.of(context).pushNamed(
        Routes.quiz,
        arguments: QuizArgs(
          input: input,
          source: source,
          historyId: _historyId,
        ),
      );
    } else {
      Navigator.of(context).pushNamed(
        Routes.result,
        arguments: ResultArgs(
          input: input,
          source: source,
          historyId: _historyId,
        ),
      );
    }
  }

  // --- 画面 ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final strings = context.recognitionStrings;
    final common = context.commonStrings;
    return ListenableBuilder(
      listenable: _editor,
      builder: (context, _) {
        final input = _editor.input;
        final issues = input.validate();
        final preview = issues.isEmpty ? previewHand(input) : null;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _scoring
                  ? (widget.manual
                        ? strings.scoreManualTitle
                        : strings.scoreTitle)
                  : (widget.manual ? strings.manualTitle : strings.title),
            ),
            actions: [
              if (_imageBytes != null)
                TextButton.icon(
                  onPressed: _recapture,
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: Text(strings.recapture),
                ),
              if (_editor.canUndo)
                IconButton(
                  key: const ValueKey('recognition-undo'),
                  tooltip: common.undo,
                  onPressed: _editor.undo,
                  icon: const Icon(Icons.undo),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.sm,
                    AppSpacing.gutter,
                    AppSpacing.xl,
                  ),
                  // 手牌・副露・局の条件・ドラを、それぞれ見出しつきのカードに分ける。
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _handSection(strings, input),
                      const SizedBox(height: AppSpacing.md),
                      _meldsSection(strings),
                      const SizedBox(height: AppSpacing.md),
                      _conditionsSection(strings, common),
                      const SizedBox(height: AppSpacing.md),
                      _doraSection(strings),
                    ],
                  ),
                ),
              ),
              _bottomBar(strings, input, issues, preview),
            ],
          ),
        );
      },
    );
  }

  Widget _handSection(RecognitionStrings strings, HandInput input) {
    final state = _editor.state;
    final scheme = Theme.of(context).colorScheme;
    final lowCount = state.slots.where((s) => s.isLowConfidence).length;
    final notice =
        _notice ??
        (lowCount > 0
            ? strings.lowConfidenceNotice
            : (state.slots.isEmpty ? strings.emptyHint : strings.editHint));
    final highlight = _editor.lastEditedIndex;
    final theme = Theme.of(context);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_imageBytes != null) ...[
          _PhotoThumb(
            bytes: _imageBytes!,
            quarterTurns: _imageQuarterTurns,
            boxes: [for (final s in state.slots) s.box],
            scores: [for (final s in state.slots) s.confidence],
            highlight: highlight,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: lowCount > 0 ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  for (var i = 0; i < state.slots.length; i++)
                    Padding(
                      // ツモ牌は少し離して右に置く。
                      padding: EdgeInsets.only(
                        left: i == state.tsumoIndex && i > 0 ? 10 : 0,
                      ),
                      child: _tileChip(strings, i, highlight),
                    ),
                  IconButton.filledTonal(
                    key: const ValueKey('recognition-add-tile'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(38, 48),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.smAll,
                      ),
                    ),
                    onPressed: _addTiles,
                    icon: const Icon(Icons.add),
                    tooltip: strings.addTile,
                  ),
                ],
              ),
              if (state.slots.length >= 13 && state.tsumoIndex == null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _scoring ? strings.winningHint : strings.tsumoHint,
                    key: const ValueKey('recognition-tsumo-hint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _scoring ? AppColors.vermilion : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    return _SectionCard(
      title: strings.handHeader(input.tileCount),
      child: content,
    );
  }

  Widget _tileChip(RecognitionStrings strings, int index, int? highlight) {
    final common = context.commonStrings;
    final slot = _editor.state.slots[index];
    final isTsumo = _editor.state.tsumoIndex == index;
    final low = slot.isLowConfidence;
    final borderColor = isTsumo
        ? (_scoring ? AppColors.vermilion : AppColors.jade)
        : low
        ? AppColors.danger
        : highlight == index
        ? AppColors.gold
        : Colors.transparent;
    return Semantics(
      button: true,
      label:
          '${common.tileName(slot.label)}'
          '${isTsumo ? ' ${_scoring ? strings.winningBadge : strings.tsumoBadge}' : ''}',
      child: InkWell(
        key: ValueKey('recognition-tile-$index'),
        borderRadius: BorderRadius.circular(6),
        onTap: () => _editTile(index),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              TileImage(slot.label, width: 30),
              if (isTsumo)
                Positioned(
                  top: -8,
                  right: -8,
                  child: _scoring
                      ? _badge(strings.winningBadge, AppColors.vermilion)
                      : _badge(strings.tsumoBadge, AppColors.jade),
                )
              else if (low)
                Positioned(
                  top: -8,
                  right: -8,
                  child: _badge('?', AppColors.danger),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(color: color, borderRadius: AppRadius.pillAll),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: Colors.white, fontSize: 10),
    ),
  );

  Widget _meldsSection(RecognitionStrings strings) {
    final state = _editor.state;
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: strings.meldsHeader,
      trailing: TextButton.icon(
        key: const ValueKey('recognition-add-meld'),
        onPressed: state.melds.length >= 4 ? null : _addMeld,
        icon: const Icon(Icons.add, size: 18),
        label: Text(strings.addMeld),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.melds.isEmpty)
            Text(
              strings.noMelds,
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < state.melds.length; i++)
                  _meldFrame(strings, i, state.melds[i]),
              ],
            ),
          for (final i in state.applicableSuggestions)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _suggestedMeld(strings, i, state.suggestedMelds[i]),
            ),
        ],
      ),
    );
  }

  Widget _meldTiles(MeldInput meld, {double width = 24}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < meld.tiles.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: TileImage(
              meld.tiles[i],
              width: width,
              // 鳴いた牌は横向き（暗槓は両端が伏せ牌だが、ここでは横向きにしない）。
              sideways: meld.isOpen && i == 0,
            ),
          ),
      ],
    );
  }

  Widget _meldFrame(RecognitionStrings strings, int index, MeldInput meld) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 1.5),
        borderRadius: AppRadius.smAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _meldTiles(meld),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (meld.isKan)
                SegmentedButton<MeldKind>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    ButtonSegment(
                      value: MeldKind.minkan,
                      label: Text(strings.meldKind(MeldKind.minkan)),
                    ),
                    ButtonSegment(
                      value: MeldKind.ankan,
                      label: Text(strings.meldKind(MeldKind.ankan)),
                    ),
                  ],
                  selected: {meld.kind},
                  onSelectionChanged: (set) =>
                      _editor.setMeldKind(index, set.first),
                )
              else
                Text(
                  strings.meldKind(meld.kind),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              IconButton(
                key: ValueKey('recognition-remove-meld-$index'),
                tooltip: strings.removeMeld,
                visualDensity: VisualDensity.compact,
                onPressed: () => _editor.removeMeld(index),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _suggestedMeld(RecognitionStrings strings, int index, MeldInput meld) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${strings.meldSuggestion}（${strings.meldKind(meld.kind)}）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                _meldTiles(meld),
              ],
            ),
          ),
          TextButton(
            key: ValueKey('recognition-dismiss-suggestion-$index'),
            onPressed: () => _editor.dismissSuggestedMeld(index),
            child: Text(strings.dismiss),
          ),
          FilledButton.tonal(
            key: ValueKey('recognition-adopt-suggestion-$index'),
            onPressed: () => _editor.applySuggestedMeld(index),
            child: Text(strings.adoptMeld),
          ),
        ],
      ),
    );
  }

  Widget _conditionsSection(RecognitionStrings strings, CommonStrings common) {
    final state = _editor.state;
    final theme = Theme.of(context);
    return _SectionCard(
      title: strings.conditionsHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _choiceGroup<Wind>(
                strings.seatWind,
                state.seatWind,
                Wind.values,
                strings.seatWindChoice,
                _editor.setSeatWind,
                keyPrefix: 'seat',
              ),
              _choiceGroup<Wind>(
                strings.roundWind,
                state.roundWind,
                Wind.values,
                common.windName,
                _editor.setRoundWind,
                keyPrefix: 'round',
              ),
              _choiceGroup<bool>(
                strings.dealerLabel,
                state.dealer,
                const [true, false],
                (v) => v ? common.dealer : common.nonDealer,
                _editor.setDealer,
                keyPrefix: 'dealer',
              ),
            ],
          ),
          // 巡目は点数に関係しないので、点数計算モードでは出さない。
          if (!_scoring) ...[
            const SizedBox(height: AppSpacing.md),
            Text(strings.turnLabel, style: theme.textTheme.labelLarge),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('recognition-turn-minus'),
                  tooltip: strings.decrease,
                  onPressed: state.turn == null
                      ? null
                      : () => _editor.setTurn(
                          state.turn! <= 1 ? null : state.turn! - 1,
                        ),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    state.turn == null
                        ? strings.turnUnset
                        : strings.turnValue(state.turn!),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const ValueKey('recognition-turn-plus'),
                  tooltip: strings.increase,
                  onPressed: (state.turn ?? 0) >= HandInput.maxTurn
                      ? null
                      : () => _editor.setTurn(
                          state.turn == null ? 6 : state.turn! + 1,
                        ),
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Expanded(
                  child: Text(
                    strings.turnHint,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _choiceGroup<T>(
    String title,
    T current,
    List<T> values,
    String Function(T) label,
    void Function(T) onChanged, {
    required String keyPrefix,
  }) {
    // 1 行に「見出し」と切り替え（SegmentedButton）。キーは各選択肢の文字に付ける。
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(title, style: Theme.of(context).textTheme.labelLarge),
          ),
          Expanded(
            child: SegmentedButton<T>(
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
                    // 幅が足りない（「東（親）」・英語・大きな文字）ときは縮めて 1 行に収める。
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
              selected: {current},
              onSelectionChanged: (set) {
                if (set.isNotEmpty) onChanged(set.first);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _doraSection(RecognitionStrings strings) {
    final indicators = _editor.state.doraIndicators;
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: strings.doraHeader,
      trailing: TextButton.icon(
        key: const ValueKey('recognition-pick-dora'),
        onPressed: _pickDora,
        icon: const Icon(Icons.search, size: 18),
        label: Text(strings.pickDora),
      ),
      child: Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          if (indicators.isEmpty)
            Text(
              strings.noDora,
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            for (final label in indicators) TileImage(label, width: 28),
        ],
      ),
    );
  }

  Widget _bottomBar(
    RecognitionStrings strings,
    HandInput input,
    List<HandInputIssue> issues,
    HandPreview? preview,
  ) {
    final scheme = Theme.of(context).colorScheme;
    String message;
    var warning = false;
    var canProceed = issues.isEmpty && preview != null;
    if (input.tiles.isEmpty && input.melds.isEmpty) {
      message = strings.emptyHint;
      warning = true;
    } else if (issues.isNotEmpty) {
      message = strings.issueText(issues.first);
      warning = true;
    } else if (_scoring) {
      // 点数計算は和了形の 14 枚だけ。
      if (preview == null || preview.tileCount != HandInput.maxTileCount) {
        message = strings.scoreNeedFourteen;
        warning = true;
        canProceed = false;
      } else if (preview.shanten >= 0) {
        message = strings.scoreNotWinning(preview.shanten);
        warning = true;
        canProceed = false;
      } else {
        final tsumo = input.tsumoTile;
        message = tsumo == null
            ? strings.scoreReadyNoWinning
            : strings.scoreReady(tsumo);
      }
    } else if (preview != null) {
      final best = preview.bestDiscardId;
      message = strings.previewLine(
        shanten: preview.shanten,
        ukeireTotal: preview.ukeireTotal,
        tileCount: preview.tileCount,
        bestDiscard: best == null ? null : tileLabelOfId(best),
      );
    } else {
      message = '';
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.sm + 2,
            AppSpacing.md,
            AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message,
                  key: const ValueKey('recognition-preview'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: warning ? AppColors.caution : scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                key: const ValueKey('recognition-next'),
                onPressed: canProceed ? _goNext : null,
                icon: Icon(
                  _scoring ? Icons.calculate_outlined : Icons.arrow_forward,
                ),
                label: Text(
                  _scoring
                      ? strings.scoreButton
                      : input.tileCount == HandInput.maxTileCount
                      ? strings.solveFourteen
                      : strings.solveThirteen,
                ),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 修正画面の 1 区画（見出し・右上の操作・中身）のカード。
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// 撮影写真の縮小表示と検出枠。タップで拡大。
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.bytes,
    required this.quarterTurns,
    required this.boxes,
    required this.scores,
    this.highlight,
  });

  final Uint8List bytes;
  final int quarterTurns;
  final List<Rect?> boxes;
  final List<double?> scores;
  final int? highlight;

  Widget _photo(double width) {
    return RotatedBox(
      quarterTurns: quarterTurns,
      child: Image.memory(
        bytes,
        width: width,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.recognitionStrings;
    return Semantics(
      button: true,
      label: strings.photoZoom,
      child: GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              maxScale: 5,
              child: CustomPaint(
                foregroundPainter: _BoxesPainter(boxes, scores, highlight),
                child: _photo(900),
              ),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            foregroundPainter: _BoxesPainter(boxes, scores, highlight),
            child: _photo(96),
          ),
        ),
      ),
    );
  }
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter(this.boxes, this.scores, this.highlight);

  final List<Rect?> boxes;
  final List<double?> scores;
  final int? highlight;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < boxes.length; i++) {
      final box = boxes[i];
      if (box == null) continue;
      final score = i < scores.length ? scores[i] : null;
      final low = score != null && score < lowConfidenceThreshold;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = i == highlight ? 3 : 1.5
        ..color = i == highlight
            ? AppColors.liveRecommend
            : (low ? AppColors.liveError : AppColors.liveOk);
      canvas.drawRect(
        Rect.fromLTRB(
          box.left * size.width,
          box.top * size.height,
          box.right * size.width,
          box.bottom * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BoxesPainter old) =>
      old.boxes != boxes || old.scores != scores || old.highlight != highlight;
}
