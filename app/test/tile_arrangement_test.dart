import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_arrangement.dart';
import 'package:nanikiru_cam/ml/tile_selection.dart';

/// 中心 [cx] に置いた牌。横向き（鳴いた牌）は幅と高さを入れ替える。
TileDetection tile(
  String label,
  double cx, {
  bool sideways = false,
  double y = 0.5,
  double score = 0.9,
}) {
  final width = sideways ? 0.075 : 0.04;
  final height = sideways ? 0.04 : 0.075;
  return TileDetection(
    box: Rect.fromCenter(center: Offset(cx, y), width: width, height: height),
    label: label,
    score: score,
  );
}

const standing10 = ['1m', '2m', '3m', '6m', '7m', '8m', '2p', '3p', '4p', '5p'];

/// 間隔 0.045 で [labels] を並べる（先頭の中心は [start]）。
List<TileDetection> row(List<String> labels, {double start = 0.08}) => [
  for (var i = 0; i < labels.length; i++) tile(labels[i], start + i * 0.045),
];

void main() {
  group('ツモ牌', () {
    final labels14 = [...standing10, '3s', '4s', '5s', '7z'];

    test('右端が平均間隔の 1.6 倍以上離れていればツモ牌', () {
      final tiles = [
        ...row(labels14.take(13).toList()),
        // 13 枚目の中心 = 0.08 + 12 * 0.045 = 0.62。ここから 2 倍の間隔（0.09）離す。
        tile('7z', 0.62 + 0.09),
      ];
      final arrangement = TileArrangementDetector.analyze(tiles);
      expect(arrangement.tsumoIndex, 13);
      expect(arrangement.melds, isEmpty);
    });

    test('1.65 倍離れていればツモ牌、1.3 倍ならツモ牌ではない', () {
      final base = row(labels14.take(13).toList());
      expect(
        TileArrangementDetector.analyze([
          ...base,
          tile('7z', 0.62 + 0.045 * 1.65),
        ]).tsumoIndex,
        13,
      );
      expect(
        TileArrangementDetector.analyze([
          ...base,
          tile('7z', 0.62 + 0.045 * 1.3),
        ]).tsumoIndex,
        isNull,
      );
    });

    test('等間隔の 14 枚にツモ牌はない', () {
      expect(TileArrangementDetector.analyze(row(labels14)).tsumoIndex, isNull);
    });

    test('13 枚だけの列は、右端が離れていてもツモ牌にしない（14 枚目がない）', () {
      final tiles = [
        ...row(labels14.take(12).toList()),
        tile('7z', 0.08 + 11 * 0.045 + 0.1),
      ];
      expect(tiles, hasLength(13));
      expect(TileArrangementDetector.analyze(tiles).tsumoIndex, isNull);
    });

    test('2 段にまたがる選択からは推定しない', () {
      final tiles = [
        ...row(labels14.take(7).toList()),
        for (var i = 0; i < 7; i++)
          tile(labels14[7 + i], 0.08 + i * 0.045, y: 0.8),
      ];
      expect(TileArrangementDetector.analyze(tiles).tsumoIndex, isNull);
      expect(TileArrangementDetector.analyze(tiles).melds, isEmpty);
    });
  });

  group('副露の候補', () {
    test('右端のポン（横向き 1 枚を含む同じ牌 3 枚）を見つける', () {
      final tiles = [
        ...row(standing10),
        tile('5z', 0.55 + 0.01, sideways: true),
        tile('5z', 0.55 + 0.055),
        tile('5z', 0.55 + 0.10),
      ];
      final arrangement = TileArrangementDetector.analyze(tiles);
      expect(arrangement.melds, hasLength(1));
      expect(arrangement.melds.single.indices, [10, 11, 12]);
      expect(arrangement.melds.single.kind, MeldKind.pon);
      expect(arrangement.tsumoIndex, isNull, reason: '論理 13 枚なのでツモ牌はない');
    });

    test('右端のチー（連続する数牌 3 枚）を見つける', () {
      final tiles = [
        ...row(standing10),
        tile('3s', 0.56, sideways: true),
        tile('4s', 0.61),
        tile('5s', 0.655),
      ];
      final melds = TileArrangementDetector.analyze(tiles).melds;
      expect(melds.single.kind, MeldKind.chi);
      expect(melds.single.indices, [10, 11, 12]);
    });

    test('槓（同じ牌 4 枚）は明槓の候補になる', () {
      final tiles = [
        ...row(standing10.take(9).toList()),
        tile('7z', 0.50, sideways: true),
        tile('7z', 0.55),
        tile('7z', 0.595),
        tile('7z', 0.64),
      ];
      // 物理 13 枚、論理 12 枚（槓は 3 枚）。メルドの検出は枚数に依存しない。
      final melds = TileArrangementDetector.detectMelds(tiles);
      expect(melds.single.kind, MeldKind.minkan);
      expect(melds.single.indices, [9, 10, 11, 12]);
    });

    test('横向きの牌がなければ副露にしない', () {
      final tiles = [
        ...row(standing10),
        tile('5z', 0.56),
        tile('5z', 0.605),
        tile('5z', 0.65),
      ];
      expect(TileArrangementDetector.analyze(tiles).melds, isEmpty);
    });

    test('チー・ポン・槓として成り立たない並びは誤検出として捨てる', () {
      final tiles = [
        ...row(standing10),
        tile('1m', 0.56, sideways: true),
        tile('5p', 0.61),
        tile('9s', 0.655),
      ];
      expect(TileArrangementDetector.analyze(tiles).melds, isEmpty);
    });

    test('副露を除いた 14 枚目が離れていればツモ牌、副露の牌は数えない', () {
      // 門前 10 枚 + ツモ牌 1 枚 + ポン 3 枚（物理 14 枚、論理 14 枚）。
      final tiles = [
        ...row(standing10),
        tile('7z', 0.08 + 9 * 0.045 + 0.09), // ツモ牌（2 倍離れる）
        tile('5z', 0.78, sideways: true),
        tile('5z', 0.83),
        tile('5z', 0.875),
      ];
      final arrangement = TileArrangementDetector.analyze(tiles);
      expect(arrangement.tsumoIndex, 10);
      expect(arrangement.melds.single.indices, [11, 12, 13]);
    });

    test('2 つの副露を右から順に返す', () {
      // 門前 7 枚 + ポン + チー = 論理 13 枚。
      final tiles = [
        ...row(standing10.take(7).toList()),
        tile('5z', 0.45, sideways: true),
        tile('5z', 0.50),
        tile('5z', 0.545),
        tile('3s', 0.62, sideways: true),
        tile('4s', 0.67),
        tile('5s', 0.715),
      ];
      final melds = TileArrangementDetector.analyze(tiles).melds;
      expect(melds, hasLength(2));
      expect(melds[0].kind, MeldKind.chi);
      expect(melds[0].indices, [10, 11, 12]);
      expect(melds[1].kind, MeldKind.pon);
      expect(melds[1].indices, [7, 8, 9]);
    });
  });

  group('傾いた列（手持ち撮影）', () {
    /// [tiles] の中心を (0.4, 0.5) を軸に [deg] 度回す（枠の大きさはそのまま）。
    List<TileDetection> tilt(List<TileDetection> tiles, double deg) {
      final a = deg * math.pi / 180;
      return [
        for (final d in tiles)
          TileDetection(
            box: Rect.fromCenter(
              center: Offset(
                0.4 +
                    (d.box.center.dx - 0.4) * math.cos(a) -
                    (d.box.center.dy - 0.5) * math.sin(a),
                0.5 +
                    (d.box.center.dx - 0.4) * math.sin(a) +
                    (d.box.center.dy - 0.5) * math.cos(a),
              ),
              width: d.box.width,
              height: d.box.height,
            ),
            label: d.label,
            score: d.score,
          ),
      ];
    }

    final labels14 = [...standing10, '3s', '4s', '5s', '7z'];

    for (final deg in [-15.0, 12.0, 15.0]) {
      test('$deg° 傾いていても 1 段として、ツモ牌と副露を推定する', () {
        final tsumo = tilt([
          ...row(labels14.take(13).toList()),
          tile('7z', 0.62 + 0.09),
        ], deg);
        expect(TileArrangementDetector.analyze(tsumo).tsumoIndex, 13);

        final chi = tilt([
          ...row(standing10),
          tile('3s', 0.56, sideways: true),
          tile('4s', 0.61),
          tile('5s', 0.655),
        ], deg);
        expect(
          TileArrangementDetector.analyze(chi).melds.single.kind,
          MeldKind.chi,
        );
      });
    }

    test('傾いていても、2 段にまたがる選択からは推定しない', () {
      final tiles = tilt([
        ...row(labels14.take(7).toList()),
        for (var i = 0; i < 7; i++)
          tile(labels14[7 + i], 0.08 + i * 0.045, y: 0.8),
      ], 10);
      expect(TileArrangementDetector.analyze(tiles).tsumoIndex, isNull);
      expect(TileArrangementDetector.analyze(tiles).melds, isEmpty);
    });

    test('左右で段がずれた（階段状の）選択も 1 段とはみなさない', () {
      // 1 段なら右端がツモ牌になる並び（右の 7 枚だけ 1.6 牌ぶん下にずれている）。
      final flat = [
        ...row(labels14.take(13).toList()),
        tile('7z', 0.62 + 0.09),
      ];
      expect(TileArrangementDetector.analyze(flat).tsumoIndex, 13);
      final stairs = [
        for (var i = 0; i < flat.length; i++)
          i < 7
              ? flat[i]
              : TileDetection(
                  box: flat[i].box.translate(0, 0.12),
                  label: flat[i].label,
                  score: flat[i].score,
                ),
      ];
      expect(TileArrangementDetector.analyze(stairs).tsumoIndex, isNull);
    });
  });

  group('SelectedTiles.arrangement', () {
    test('選んだ牌の並びから推定する', () {
      final engine = TileSelectionEngine();
      final selected = engine.selectBest([
        ...row(standing10),
        tile('3s', 0.56),
        tile('4s', 0.605),
        tile('5s', 0.65),
        tile('7z', 0.65 + 0.09),
      ]);
      expect(selected.detections, hasLength(14));
      expect(selected.arrangement.tsumoIndex, 13);
    });
  });
}
