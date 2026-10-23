import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_selection.dart';

/// 認識の確度がこれ未満の牌は、ユーザーに確認を促す（赤枠）。
const double lowConfidenceThreshold = 0.6;

/// 第 2 候補として出す最小の確度。
const double minAlternativeScore = 0.05;

/// 副露の候補。[indices] は [RecognitionDraft.labels] の連続した添字。
class MeldCandidate extends Equatable {
  const MeldCandidate({required this.indices, required this.kind});

  final List<int> indices;
  final MeldKind kind;

  @override
  List<Object?> get props => [indices, kind];
}

/// 写真の認識結果（設計書 3.1）。ユーザーが修正する前の下書き。
///
/// [labels] は写真に写っていた全ての牌で、次の並びにする:
/// `[門前の牌（理牌順）…, 副露候補の牌（右端のものから順にまとめて）…, ツモ牌]`。
/// 副露候補の牌は [melds] の添字で連続して指す。副露は候補にすぎないので、[toHandInput] は
/// 既定では全ての牌を手牌として扱う（`applyMelds: true` で副露に移す）。
class RecognitionDraft extends Equatable {
  RecognitionDraft({
    required Iterable<String> labels,
    this.tsumoIndex,
    Iterable<MeldCandidate> melds = const [],
    Iterable<double?>? confidences,
    Iterable<List<String>>? alternatives,
    Iterable<Rect?>? boxes,
  }) : labels = List.unmodifiable(labels),
       melds = List.unmodifiable(melds),
       confidences = List.unmodifiable(
         confidences ?? List<double?>.filled(labels.length, null),
       ),
       alternatives = List.unmodifiable(
         alternatives ?? List<List<String>>.filled(labels.length, const []),
       ),
       boxes = List.unmodifiable(
         boxes ?? List<Rect?>.filled(labels.length, null),
       );

  /// 認識結果なし（手入力の開始）。
  static final RecognitionDraft empty = RecognitionDraft(labels: const []);

  final List<String> labels;

  /// [labels] の中のツモ牌の添字。推定できなかったときは null。
  final int? tsumoIndex;

  final List<MeldCandidate> melds;

  /// 牌ごとの確度 0..1。手入力した牌は null。
  final List<double?> confidences;

  /// 牌ごとの修正候補（確からしい順）。なければ空。
  final List<List<String>> alternatives;

  /// 写真（回転後）の上での位置 0..1。手入力した牌は null。
  final List<Rect?> boxes;

  int get length => labels.length;

  /// 確度が [threshold] 未満の牌の添字。
  List<int> lowConfidenceIndices({double threshold = lowConfidenceThreshold}) =>
      [
        for (var i = 0; i < confidences.length; i++)
          if (confidences[i] != null && confidences[i]! < threshold) i,
      ];

  /// 認識の選択結果から下書きを作る。
  ///
  /// 検出順は左から右。ツモ牌（右端が離れている）と副露候補を取り出し、残りを理牌する。
  factory RecognitionDraft.fromSelection(SelectedTiles selection) {
    final detections = selection.detections;
    final arrangement = selection.arrangement;
    final tsumo = arrangement.tsumoIndex;
    final inMeld = {for (final m in arrangement.melds) ...m.indices};

    final standing =
        [
          for (var i = 0; i < detections.length; i++)
            if (i != tsumo && !inMeld.contains(i)) i,
        ]..sort(
          (a, b) => compareTileLabels(detections[a].label, detections[b].label),
        );

    // 右端の副露を先頭にしないよう、左にあるものから並べる。
    final meldGroups = [...arrangement.melds].reversed.toList();

    final order = <int>[...standing];
    final candidates = <MeldCandidate>[];
    for (final group in meldGroups) {
      final start = order.length;
      order.addAll(group.indices);
      candidates.add(
        MeldCandidate(
          indices: [for (var k = 0; k < group.indices.length; k++) start + k],
          kind: group.kind,
        ),
      );
    }
    if (tsumo != null) order.add(tsumo);

    return RecognitionDraft(
      labels: [for (final i in order) detections[i].label],
      tsumoIndex: tsumo == null ? null : order.length - 1,
      melds: candidates,
      confidences: [for (final i in order) detections[i].score],
      alternatives: [
        for (final i in order)
          detections[i].alternative != null &&
                  detections[i].alternativeScore >= minAlternativeScore
              ? [detections[i].alternative!]
              : const <String>[],
      ],
      boxes: [for (final i in order) detections[i].box],
    );
  }

  /// 画面に渡す [HandInput] に変換する。局の条件（風・ドラ表示牌など）は [base] から引き継ぐ。
  ///
  /// [applyMelds] が true なら、副露候補の牌を [HandInput.melds] に移す。
  HandInput toHandInput({HandInput? base, bool applyMelds = false}) {
    final start = base ?? HandInput.empty;
    final inMeld = applyMelds
        ? {for (final m in melds) ...m.indices}
        : const <int>{};
    final tiles = <String>[];
    int? tsumo;
    for (var i = 0; i < labels.length; i++) {
      if (inMeld.contains(i)) continue;
      if (i == tsumoIndex) tsumo = tiles.length;
      tiles.add(labels[i]);
    }
    return start.copyWith(
      tiles: tiles,
      tsumoIndex: tsumo,
      melds: applyMelds
          ? [
              ...start.melds,
              for (final m in melds)
                MeldInput(
                  kind: m.kind,
                  tiles: [for (final i in m.indices) labels[i]],
                ),
            ]
          : start.melds,
    );
  }

  @override
  List<Object?> get props => [
    labels,
    tsumoIndex,
    melds,
    confidences,
    alternatives,
    boxes,
  ];
}

extension RecognitionOutcomeDraft on RecognitionOutcome {
  /// この認識結果の下書き。
  RecognitionDraft toDraft() => RecognitionDraft.fromSelection(selection);
}
