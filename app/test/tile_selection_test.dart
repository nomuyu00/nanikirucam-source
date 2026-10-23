// 流用元: reference/agari_cam/test/tile_selection_test.dart（2026-10-21 時点）
// 改修: 14 枚固定から「13 または 14 枚」へ。和了形判定（validHand）は isComplete に置き換え。
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_selection.dart';

TileDetection detection(
  String label,
  double x,
  double y, {
  double width = 0.04,
  double height = 0.10,
  double score = 0.9,
}) {
  return TileDetection(
    box: Rect.fromLTWH(x, y, width, height),
    label: label,
    score: score,
  );
}

const hand14 = [
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
  '5p',
  '3s',
  '4s',
  '5s',
];

void main() {
  test('prefers a consistent 14-tile row over central noise', () {
    final engine = TileSelectionEngine();
    final detections = <TileDetection>[
      for (var i = 0; i < hand14.length; i++)
        detection(
          hand14[i],
          0.10 + (i * 0.05),
          0.58,
          score: 0.82 + (i * 0.005),
        ),
      detection('1m', 0.44, 0.34, score: 0.97),
      detection('1m', 0.48, 0.33, score: 0.96),
      detection('1m', 0.52, 0.35, score: 0.95),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.labels, equals(hand14));
    expect(selected.isComplete, isTrue);
    expect(selected.strategy, isNot('legacy'));
  });

  test('keeps a complete 14-tile hand when no better alternative exists', () {
    final engine = TileSelectionEngine();
    final detections = [
      for (var i = 0; i < hand14.length; i++)
        detection(hand14[i], 0.10 + (i * 0.05), 0.55),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.labels, hand14);
    expect(selected.isComplete, isTrue);
  });

  test('prefers the centered horizontal row over an upper edge row', () {
    final engine = TileSelectionEngine();
    final detections = <TileDetection>[
      for (var i = 0; i < hand14.length; i++)
        detection(hand14[i], 0.10 + (i * 0.05), 0.07, score: 0.96),
      for (var i = 0; i < hand14.length; i++)
        detection(hand14[i], 0.10 + (i * 0.05), 0.50, score: 0.87),
    ];

    final selected = engine.selectBest(detections);
    final averageY =
        selected.detections
            .map((d) => d.box.center.dy)
            .reduce((a, b) => a + b) /
        selected.detections.length;

    expect(selected.labels, equals(hand14));
    expect(averageY, greaterThan(0.45));
  });

  test('a row of 13 tiles is selected as 13 tiles', () {
    final engine = TileSelectionEngine();
    final hand13 = hand14.take(13).toList();
    final detections = [
      for (var i = 0; i < hand13.length; i++)
        detection(hand13[i], 0.10 + (i * 0.05), 0.55),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.labels, hand13);
    expect(selected.isComplete, isTrue);
  });

  test('a 13-tile row is not padded with a stray tile from another row', () {
    final engine = TileSelectionEngine();
    final hand13 = hand14.take(13).toList();
    final detections = [
      for (var i = 0; i < hand13.length; i++)
        detection(hand13[i], 0.10 + (i * 0.05), 0.55, score: 0.9),
      detection('9s', 0.45, 0.10, score: 0.75),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.labels, hand13);
  });

  test('a 14-tile row with the drawn tile set apart stays 14 tiles', () {
    final engine = TileSelectionEngine();
    final detections = [
      for (var i = 0; i < 13; i++)
        detection(hand14[i], 0.05 + (i * 0.05), 0.55),
      // ツモ牌は 1 牌ぶん離して右に置く。
      detection(hand14[13], 0.05 + (13 * 0.05) + 0.04, 0.55),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.labels, hand14);
    expect(selected.isComplete, isTrue);
  });

  test('never selects 15 or more tiles (kan windows are not supported)', () {
    final engine = TileSelectionEngine();
    final labels = [...hand14, '5p']; // 15 枚の列
    final detections = [
      for (var i = 0; i < labels.length; i++)
        detection(labels[i], 0.05 + (i * 0.05), 0.55),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.detections.length, lessThanOrEqualTo(14));
  });

  test('tiles are returned from left to right regardless of label order', () {
    final engine = TileSelectionEngine();
    // ラベルの順と x 座標の順を入れ替えた並び。
    final labels = [
      '9s',
      '1m',
      '5p',
      '2z',
      '7m',
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
    final detections = [
      for (var i = labels.length - 1; i >= 0; i--)
        detection(labels[i], 0.10 + (i * 0.05), 0.55),
    ];

    final selected = engine.selectBest(detections);

    expect(selected.labels, labels);
  });

  test('isComplete requires 13 or 14 tiles and at most four of a kind', () {
    expect(TileSelectionEngine.isCompleteSet(hand14), isTrue);
    expect(TileSelectionEngine.isCompleteSet(hand14.take(13).toList()), isTrue);
    expect(
      TileSelectionEngine.isCompleteSet(hand14.take(12).toList()),
      isFalse,
    );
    expect(
      TileSelectionEngine.isCompleteSet([...hand14, '7z']),
      isFalse,
      reason: '15 枚は無効',
    );
    expect(
      TileSelectionEngine.isCompleteSet([
        '1m',
        '1m',
        '1m',
        '1m',
        '1m',
        ...hand14.skip(5).take(8),
      ]),
      isFalse,
      reason: '同じ牌が 5 枚',
    );
  });

  test(
    'isConfident needs a complete set with every score at the threshold',
    () {
      final engine = TileSelectionEngine();
      final good = engine.selectBest([
        for (var i = 0; i < 13; i++)
          detection(hand14[i], 0.10 + (i * 0.05), 0.55, score: 0.7),
      ]);
      expect(good.isConfident(0.6), isTrue);
      expect(good.isConfident(0.8), isFalse);

      final oneWeak = engine.selectBest([
        for (var i = 0; i < 13; i++)
          detection(
            hand14[i],
            0.10 + (i * 0.05),
            0.55,
            score: i == 4 ? 0.4 : 0.9,
          ),
      ]);
      expect(oneWeak.isComplete, isTrue);
      expect(oneWeak.isConfident(0.6), isFalse);

      final short = engine.selectBest([
        for (var i = 0; i < 12; i++)
          detection(hand14[i], 0.10 + (i * 0.05), 0.55, score: 0.95),
      ]);
      expect(short.isComplete, isFalse);
      expect(short.isConfident(0.6), isFalse);
    },
  );
}
