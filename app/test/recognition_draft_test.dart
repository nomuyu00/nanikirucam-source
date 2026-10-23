import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_selection.dart';

TileDetection tile(
  String label,
  double cx, {
  bool sideways = false,
  double score = 0.9,
  String? alternative,
  double alternativeScore = 0,
}) {
  return TileDetection(
    box: Rect.fromCenter(
      center: Offset(cx, 0.5),
      width: sideways ? 0.075 : 0.04,
      height: sideways ? 0.04 : 0.075,
    ),
    label: label,
    score: score,
    alternative: alternative,
    alternativeScore: alternativeScore,
  );
}

SelectedTiles select(List<TileDetection> detections) =>
    TileSelectionEngine().selectBest(detections);

void main() {
  test('並びがばらばらでも理牌し、ツモ牌を末尾に置いて添字を指す', () {
    // 写真の左から右へ: 手牌 13 枚（理牌されていない）+ 離れたツモ牌 7m。
    final labels = [
      '9s',
      '1m',
      '5p',
      '2z',
      '3s',
      '1p',
      '8s',
      '4m',
      '6p',
      '7z',
      '2m',
      '9p',
      '5s',
    ];
    final draft = RecognitionDraft.fromSelection(
      select([
        for (var i = 0; i < labels.length; i++)
          tile(labels[i], 0.08 + i * 0.045),
        tile('7m', 0.08 + 12 * 0.045 + 0.1),
      ]),
    );

    expect(draft.length, 14);
    expect(draft.tsumoIndex, 13);
    expect(draft.labels.last, '7m');
    expect(draft.labels.take(13).toList(), [
      '1m',
      '2m',
      '4m',
      '1p',
      '5p',
      '6p',
      '9p',
      '3s',
      '5s',
      '8s',
      '9s',
      '2z',
      '7z',
    ]);
    expect(draft.melds, isEmpty);
  });

  test('確度・第 2 候補・枠が理牌後の並びについてくる', () {
    final draft = RecognitionDraft.fromSelection(
      select([
        tile('9m', 0.10, score: 0.95),
        tile('1m', 0.15, score: 0.4, alternative: '7m', alternativeScore: 0.3),
        for (var i = 0; i < 11; i++) tile('${i % 9 + 1}p', 0.20 + i * 0.045),
      ]),
    );

    // 1m は先頭に来る。
    expect(draft.labels.first, '1m');
    expect(draft.confidences.first, 0.4);
    expect(draft.alternatives.first, ['7m']);
    expect(draft.boxes.first!.center.dx, closeTo(0.15, 1e-9));
    expect(draft.lowConfidenceIndices(), [0]);
    expect(draft.labels[1], '9m');
    expect(draft.confidences[1], 0.95);
    expect(draft.alternatives[1], isEmpty);
  });

  test('第 2 候補の確度が低すぎるものは出さない', () {
    final draft = RecognitionDraft.fromSelection(
      select([
        tile('1m', 0.10, alternative: '7m', alternativeScore: 0.02),
        for (var i = 0; i < 12; i++) tile('${i % 9 + 1}p', 0.15 + i * 0.045),
      ]),
    );
    expect(draft.alternatives.first, isEmpty);
  });

  group('副露の候補', () {
    final standing = [
      '1m',
      '2m',
      '3m',
      '6m',
      '7m',
      '8m',
      '2p',
      '3p',
      '4p',
      '5p',
    ];
    final detections = [
      for (var i = 0; i < standing.length; i++)
        tile(standing[i], 0.08 + i * 0.045),
      tile('5z', 0.56, sideways: true),
      tile('5z', 0.605),
      tile('5z', 0.65),
    ];

    test('候補は labels の連続した添字で指す', () {
      final draft = RecognitionDraft.fromSelection(select(detections));

      expect(draft.length, 13);
      expect(draft.tsumoIndex, isNull);
      expect(draft.melds, hasLength(1));
      expect(draft.melds.single.indices, [10, 11, 12]);
      expect(draft.melds.single.kind, MeldKind.pon);
      expect(
        [for (final i in draft.melds.single.indices) draft.labels[i]],
        ['5z', '5z', '5z'],
      );
    });

    test('既定では副露にせず、全部を手牌として渡す', () {
      final input = RecognitionDraft.fromSelection(
        select(detections),
      ).toHandInput();

      expect(input.tiles, hasLength(13));
      expect(input.melds, isEmpty);
      expect(input.validate(), isEmpty);
    });

    test('applyMelds: true で候補の牌を副露に移す（論理枚数は変わらない）', () {
      final input = RecognitionDraft.fromSelection(
        select(detections),
      ).toHandInput(applyMelds: true);

      expect(input.tiles, standing);
      expect(input.melds.single.kind, MeldKind.pon);
      expect(input.melds.single.tiles, ['5z', '5z', '5z']);
      expect(input.tileCount, 13);
      expect(input.validate(), isEmpty);
    });

    test('ツモ牌と副露が両方あっても、ツモ牌の位置が副露を除いた手牌の末尾になる', () {
      final draft = RecognitionDraft.fromSelection(
        select([
          for (var i = 0; i < standing.length; i++)
            tile(standing[i], 0.08 + i * 0.045),
          tile('7z', 0.08 + 9 * 0.045 + 0.09),
          tile('5z', 0.78, sideways: true),
          tile('5z', 0.83),
          tile('5z', 0.875),
        ]),
      );
      expect(draft.length, 14);
      expect(draft.tsumoIndex, 13);
      expect(draft.labels.last, '7z');
      expect(draft.melds.single.indices, [10, 11, 12]);

      final input = draft.toHandInput(applyMelds: true);
      expect(input.tiles, [...standing, '7z']);
      expect(input.tsumoIndex, 10);
      expect(input.tsumoTile, '7z');
      expect(input.melds, hasLength(1));
      expect(input.tileCount, 14);
      expect(input.validate(), isEmpty);
    });
  });

  test('toHandInput は局の条件（base）を引き継ぐ', () {
    final base = HandInput(
      tiles: const [],
      seatWind: Wind.west,
      roundWind: Wind.south,
      doraIndicators: const ['3p'],
      turn: 8,
    );
    final draft = RecognitionDraft(
      labels: const ['1m', '2m', '3m'],
      tsumoIndex: 2,
    );
    final input = draft.toHandInput(base: base);
    expect(input.tiles, ['1m', '2m', '3m']);
    expect(input.tsumoIndex, 2);
    expect(input.seatWind, Wind.west);
    expect(input.roundWind, Wind.south);
    expect(input.doraIndicators, ['3p']);
    expect(input.turn, 8);
    expect(input.dealer, isFalse);
  });

  test('空の下書きは手入力の開始に使える', () {
    expect(RecognitionDraft.empty.length, 0);
    expect(RecognitionDraft.empty.toHandInput().tiles, isEmpty);
    expect(RecognitionDraft.empty.lowConfidenceIndices(), isEmpty);
  });
}
