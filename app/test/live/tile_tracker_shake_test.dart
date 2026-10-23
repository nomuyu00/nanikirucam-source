// 手持ち撮影の手ぶれへの耐性（設計書 3.3）: 短い取りこぼし・ぶれ・1 枚欠け・平行移動・傾きでは
// 案内を消さず、本当に牌を入れ替えたら 2〜3 フレームで古い案内を消すことを固定する。
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';

import 'support/live_fakes.dart';

const hand14 = [
  '1m', '2m', '3m', '5m', '7m', '4p', '5p', //
  '6p', '3s', '4s', '8s', '9s', '1z', '1z',
];

/// 5 fps（200ms ごと）で [hand14] を [fromMs] から [toMs] まで。
List<TrackerObservation> frames({
  required int fromMs,
  required int toMs,
  int stepMs = 200,
  List<String> labels = hand14,
  double sharpness = 0,
  double jitter = 0.004,
}) => [
  for (var t = fromMs; t <= toMs; t += stepMs)
    obs(
      t,
      handBoxes(labels, seed: t, jitter: jitter),
      sharpness: sharpness,
    ),
];

/// 手を置いて 1.4 秒（stable になって案内が出ている状態）。
TileTracker settled({int toMs = 1400, double sharpness = 0}) {
  final tracker = TileTracker();
  for (final f in frames(fromMs: 0, toMs: toMs, sharpness: sharpness)) {
    tracker.update(f);
  }
  expect(tracker.snapshot.canAdvise, isTrue);
  return tracker;
}

void main() {
  group('短い取りこぼし（時間で判定）', () {
    test('見つからない・暗い・遠いが混ざって 4 フレーム（0.8 秒）続いても案内は続く', () {
      final tracker = settled();
      final stableFor = tracker.snapshot.stableFor;
      final glitches = [
        obs(1600, const []), // 見失った
        obs(1800, handBoxes(hand14), luminance: 0.05), // 暗い
        obs(2000, handBoxes(hand14, left: 0.35, right: 0.65)), // 遠い
        obs(2200, handBoxes(['1m', '2m'])), // 2 枚しか見えない
      ];
      for (final g in glitches) {
        final snap = tracker.update(g);
        expect(snap.canAdvise, isTrue, reason: '${g.timestamp}');
        expect(snap.labels, hand14);
        // stable の経過は延ばさない。
        expect(snap.stableFor, stableFor);
      }
      // 戻ったら、待たずにそのまま案内できる（履歴を消していない）。
      final back = tracker.update(obs(2400, handBoxes(hand14)));
      expect(back.canAdvise, isTrue);
      expect(back.labels, hand14);
    });

    test('0.8 秒を超えて見えなければ、従来どおり最初から', () {
      final tracker = settled();
      for (final t in [1600, 1800, 2000, 2200]) {
        expect(tracker.update(obs(t, const [])).isStable, isTrue);
      }
      final lost = tracker.update(obs(2400, const []));
      expect(lost.state, LiveTrackState.searching);
      expect(lost.tiles, isEmpty);
      final again = tracker.update(obs(2600, handBoxes(hand14)));
      expect(again.isStable, isFalse, reason: '見えてから 1 秒待ち直す');
    });

    test('低い fps（2 fps）でも、1 フレームの取りこぼしは無視する', () {
      final tracker = TileTracker();
      for (final f in frames(fromMs: 0, toMs: 2000, stepMs: 500)) {
        tracker.update(f);
      }
      expect(tracker.snapshot.isStable, isTrue);
      expect(tracker.update(obs(2500, const [])).isStable, isTrue);
      expect(tracker.update(obs(3000, handBoxes(hand14))).isStable, isTrue);
    });

    test('取りこぼしの間は fps を落とさない（rawAgrees を false にして早く見直す）', () {
      final tracker = settled(toMs: 4000);
      expect(tracker.snapshot.rawAgrees, isTrue);
      final held = tracker.update(obs(4200, const []));
      expect(held.isStable, isTrue);
      expect(held.rawAgrees, isFalse);
    });
  });

  group('1 枚欠け・読み違いの揺れ', () {
    test('30% のフレームで 1 枚欠けても（欠ける牌は毎回違う）、案内は途切れない', () {
      final tracker = TileTracker();
      var i = 0;
      for (var t = 0; t <= 8000; t += 200, i++) {
        final missing = i % 10 == 2 || i % 10 == 5 || i % 10 == 8;
        final labels = missing
            ? ([...hand14]..removeAt((i * 5) % 14))
            : hand14;
        final snap = tracker.update(
          obs(t, handBoxes(labels, seed: t, jitter: 0.004)),
        );
        if (t >= 1200) {
          expect(snap.canAdvise, isTrue, reason: '$t ms');
          expect(snap.labels, hand14, reason: '$t ms');
        }
      }
    });

    test('1 枚欠けが 3 フレーム続いても、欠ける牌が毎回違えば古い手を捨てない', () {
      final tracker = settled();
      for (final (t, k) in [(1600, 0), (1800, 6), (2000, 13)]) {
        final snap = tracker.update(
          obs(t, handBoxes([...hand14]..removeAt(k), seed: t)),
        );
        expect(snap.canAdvise, isTrue, reason: '$t ms');
        expect(snap.labels, hand14);
      }
    });

    test('ばらばらな 1 枚の読み違いが続いても moving にしない', () {
      final tracker = settled();
      for (final (t, k) in [(1600, 2), (1800, 9), (2000, 4), (2200, 11)]) {
        final labels = [...hand14]..[k] = '9m';
        final snap = tracker.update(obs(t, handBoxes(labels, seed: t)));
        expect(snap.canAdvise, isTrue, reason: '$t ms');
        expect(snap.handChanging, isFalse);
      }
    });

    test('交互に揺れる牌は、同票なら今のラベルを保つ（並びが反転し続けない）', () {
      final tracker = settled(toMs: 2000);
      final keys = <String>{};
      var i = 0;
      for (var t = 2200; t <= 5000; t += 200, i++) {
        final labels = i.isEven ? ([...hand14]..[4] = '8m') : hand14;
        keys.add(tracker.update(obs(t, handBoxes(labels, seed: t))).handKey);
      }
      expect(keys, hasLength(1), reason: '並びが入れ替わり続けない');
      expect(tracker.snapshot.labels, hand14);
      // 半々に揺れる牌の確度は下がる（確度の低い牌として印が付く）。
      expect(tracker.snapshot.tiles[4].lowConfidence, isTrue);
    });
  });

  group('確度のヒステリシス', () {
    test('ぶれで全体の確度が 2 フレーム下がっても、確定した並びと案内を保つ', () {
      final tracker = settled();
      final low = List<double>.filled(14, 0.45);
      for (final t in [1600, 1800]) {
        final snap = tracker.update(
          obs(t, handBoxes(hand14, scores: low, seed: t)),
        );
        expect(snap.canAdvise, isTrue, reason: '$t ms');
        expect(snap.block, isNull);
        expect(snap.labels, hand14);
      }
    });

    test('確度の低い牌は 0.6 未満で印が付き、0.65 以上に戻るまで外れない', () {
      final config = const TrackerConfig();
      final tracker = TileTracker(config: config);
      List<double> scores(double v) => List<double>.filled(14, 0.9)
        ..[3] = v
        ..[9] = v;
      // 0.5 で手を置く → 2 枚低い → 止める。
      for (var t = 0; t <= 2000; t += 200) {
        tracker.update(obs(t, handBoxes(hand14, scores: scores(0.5), seed: t)));
      }
      expect(tracker.snapshot.block, AdviceBlock.lowConfidence);
      // 0.62（入るしきい値 0.6 より上、出るしきい値 0.65 より下）に上がっても止めたまま。
      for (var t = 2200; t <= 5000; t += 200) {
        final snap = tracker.update(
          obs(t, handBoxes(hand14, scores: scores(0.62), seed: t)),
        );
        expect(snap.block, AdviceBlock.lowConfidence, reason: '$t ms');
      }
      // 0.8 に上がれば外れる。
      for (var t = 5200; t <= 7400; t += 200) {
        tracker.update(obs(t, handBoxes(hand14, scores: scores(0.8), seed: t)));
      }
      expect(tracker.snapshot.block, isNull);
      expect(tracker.snapshot.canAdvise, isTrue);

      // 最初から 0.62 なら印は付かない（入るしきい値は 0.6 のまま）。
      final fresh = TileTracker(config: config);
      for (var t = 0; t <= 1600; t += 200) {
        fresh.update(obs(t, handBoxes(hand14, scores: scores(0.62), seed: t)));
      }
      expect(fresh.snapshot.lowConfidenceCount, 0);
      expect(fresh.snapshot.canAdvise, isTrue);
    });
  });

  group('ぶれたフレーム（鮮鋭度）', () {
    test('鮮鋭度が大きく下がったフレームは投票に入れない（読み違いがあっても案内が続く）', () {
      final tracker = settled(sharpness: 0.05);
      // ぶれたフレームでは 2 枚の読み違いと 1 枚欠けが出る（同じ並びが 2 フレーム続いても
      // 手の変化とはみなさない）。
      final blurred = [...hand14]
        ..[2] = '4m'
        ..[8] = '7s'
        ..removeAt(12);
      var t = 1600;
      for (var round = 0; round < 5; round++) {
        // 2 フレーム続けてぶれ、3 フレームはっきり見える。
        for (final sharp in [false, false, true, true, true]) {
          final snap = tracker.update(
            obs(
              t,
              handBoxes(sharp ? hand14 : blurred, seed: t),
              sharpness: sharp ? 0.05 : 0.015,
            ),
          );
          expect(snap.canAdvise, isTrue, reason: '$t ms');
          expect(snap.labels, hand14, reason: '$t ms');
          expect(snap.handChanging, isFalse);
          t += 200;
        }
      }
    });

    test('鮮鋭度を測っていない（0）フレームは、ぶれの判定をしない', () {
      final tracker = settled();
      final changed = [...hand14]..[12] = '7z';
      tracker.update(obs(1600, handBoxes(changed, seed: 1600)));
      final snap = tracker.update(obs(1800, handBoxes(changed, seed: 1800)));
      expect(snap.handChanging, isTrue);
      expect(snap.canAdvise, isFalse);
    });

    test('ぶれが長く続けば（0.8 秒超）、ぶれたフレームでも判定に使う', () {
      final tracker = settled(sharpness: 0.05);
      final changed = [...hand14]..[12] = '7z';
      final results = [
        for (var t = 1600; t <= 3000; t += 200)
          tracker.update(
            obs(t, handBoxes(changed, seed: t), sharpness: 0.01),
          ),
      ];
      // 最初の 0.8 秒は保つが、その後は（中央値が追いつく前でも）新しい並びを見る。
      expect(results.first.canAdvise, isTrue);
      expect(results.last.canAdvise, isFalse);
      expect(results.any((s) => s.handChanging), isTrue);
    });
  });

  group('手全体の平行移動・傾き', () {
    test('手全体がゆっくり動き、細かく揺れても案内は続き、枠の揺れは小さくなる', () {
      final tracker = TileTracker();
      final random = Random(42);
      double noise() => (random.nextDouble() - 0.5) * 2 * 0.008;
      final rawX = <double>[];
      final shownX = <double>[];
      for (var t = 0; t <= 6000; t += 200) {
        final drift = 0.04 * sin(t / 1000);
        // 牌ごとに独立な揺れ（検出枠の位置のぶれ）。
        final boxes = [
          for (final b in handBoxes(hand14, dx: drift, dy: drift / 2))
            LiveTileBox(
              box: b.box.translate(noise(), noise()),
              label: b.label,
              score: b.score,
            ),
        ];
        final snap = tracker.update(obs(t, boxes));
        if (t >= 1200) {
          expect(snap.canAdvise, isTrue, reason: '$t ms');
          expect(snap.labels, hand14);
          final ideal = 0.1 + 0.8 / 14 * 5.5 + drift;
          rawX.add(snap.rawTiles[5].box.center.dx - ideal);
          shownX.add(snap.tiles[5].box.center.dx - ideal);
        }
      }
      double jitterOf(List<double> xs) {
        var sum = 0.0;
        for (var i = 1; i < xs.length; i++) {
          sum += (xs[i] - xs[i - 1]).abs();
        }
        return sum / (xs.length - 1);
      }

      expect(jitterOf(shownX), lessThan(jitterOf(rawX) * 0.8));
    });

    test('手全体を大きく動かしたら、枠は遅れずにそのまま追う', () {
      final tracker = settled();
      final snap = tracker.update(
        obs(1600, handBoxes(hand14, seed: 1600, dy: 0.1)),
      );
      expect(snap.tiles[0].box.center.dy, closeTo(0.6, 0.01));
    });

    for (final angle in [-15.0, -10.0, 10.0, 15.0]) {
      test('カメラが $angle° 傾いても 14 枚を拾い、stable になる', () {
        final tracker = TileTracker();
        final row = tracker.extractRow(
          handBoxes(hand14, angleDeg: angle, jitter: 0.004, seed: 3),
        );
        expect([for (final t in row) t.label], hand14);

        for (var t = 0; t <= 1600; t += 200) {
          tracker.update(
            obs(t, handBoxes(hand14, angleDeg: angle, jitter: 0.004, seed: t)),
          );
        }
        expect(tracker.snapshot.canAdvise, isTrue);
        expect(tracker.snapshot.labels, hand14);
      });
    }

    test('傾いた手牌と河（別の列）が写っていても、手牌の列だけを拾う', () {
      final tracker = TileTracker();
      final hand = handBoxes(hand14, angleDeg: 12, jitter: 0.003, seed: 9);
      final river = handBoxes(
        ['2m', '3m', '4m', '5m', '6m'],
        y: 0.22,
        left: 0.3,
        right: 0.65,
        angleDeg: 12,
      );
      final row = tracker.extractRow([...river, ...hand]);
      expect([for (final t in row) t.label], hand14);
    });

    test('13 枚の列で途中の 1 枚を見落としても、傾いた列の残りを拾う', () {
      final tracker = TileTracker();
      final boxes = handBoxes(hand14, angleDeg: 15, seed: 4)..removeAt(6);
      final row = tracker.extractRow(boxes);
      expect(row, hasLength(13));
    });
  });

  group('本当に牌を入れ替えたら素早く消す', () {
    test('揺れ（1 枚欠け・ジッター・ぶれ）の中でも、入れ替えたら 2 フレームで古い案内を消す', () {
      final tracker = TileTracker();
      final changed = [...hand14]..[12] = '7z';
      var i = 0;
      for (var t = 0; t <= 2000; t += 200, i++) {
        final labels = i % 4 == 3 ? ([...hand14]..removeAt(i % 14)) : hand14;
        tracker.update(
          obs(
            t,
            handBoxes(labels, seed: t, jitter: 0.006),
            sharpness: 0.05,
          ),
        );
      }
      expect(tracker.snapshot.canAdvise, isTrue);
      final first = tracker.update(
        obs(2200, handBoxes(changed, seed: 2200, jitter: 0.006), sharpness: .05),
      );
      expect(first.labels, hand14, reason: '1 フレームだけでは揺れと区別できない');
      final second = tracker.update(
        obs(2400, handBoxes(changed, seed: 2400, jitter: 0.006), sharpness: .05),
      );
      expect(second.canAdvise, isFalse, reason: '2 フレーム目で古い案内を消す');
      expect(second.handChanging, isTrue);
      // 新しい手は（見え始めから）1 秒ほどで案内できる。
      TrackerSnapshot? last;
      int? firstAdvice;
      for (var t = 2600; t <= 4400; t += 200) {
        last = tracker.update(
          obs(t, handBoxes(changed, seed: t, jitter: 0.006), sharpness: 0.05),
        );
        if (last.canAdvise) {
          expect(last.labels, changed, reason: '$t ms');
          firstAdvice ??= t;
        }
      }
      expect(firstAdvice, isNotNull);
      expect(firstAdvice! - 2200, lessThanOrEqualTo(1200));
    });

    test('1 枚切ったら（14 → 13 枚）2 フレームで 14 枚の案内を消す', () {
      final tracker = settled();
      final cut = [...hand14]..removeAt(4);
      tracker.update(obs(1600, handBoxes(cut, seed: 1600)));
      final snap = tracker.update(obs(1800, handBoxes(cut, seed: 1800)));
      expect(snap.canAdvise, isFalse);
      expect(snap.handChanging, isTrue);
    });

    test('手で牌を隠しながら動かす（毎回 2 枚以上違う）と 2 フレームで消す', () {
      final tracker = settled();
      tracker.update(
        obs(1600, handBoxes(hand14.sublist(0, 11), seed: 1600)),
      );
      final snap = tracker.update(
        obs(1800, handBoxes(hand14.sublist(3), seed: 1800)),
      );
      expect(snap.canAdvise, isFalse);
      expect(snap.state, LiveTrackState.moving);
    });
  });

  group('処理時間', () {
    test('河や他家の牌を含む 1 フレーム（60 枠）の更新は数 ms 以内', () {
      final random = Random(1);
      final tracker = TileTracker();
      final inputs = [
        for (var k = 0; k < 200; k++)
          obs(k * 200, [
            ...handBoxes(hand14, seed: k, jitter: 0.006, angleDeg: 8),
            for (var j = 0; j < 46; j++)
              LiveTileBox(
                box: Rect.fromCenter(
                  center: Offset(random.nextDouble(), random.nextDouble() * 0.4),
                  width: 0.05,
                  height: 0.07,
                ),
                label: '${1 + random.nextInt(9)}p',
                score: 0.3 + random.nextDouble() * 0.6,
              ),
          ]),
      ];
      // 暖機（JIT）。
      for (final o in inputs.take(50)) {
        tracker.update(o);
      }
      final watch = Stopwatch()..start();
      for (final o in inputs.skip(50)) {
        tracker.update(o);
      }
      final perFrameUs = watch.elapsedMicroseconds / 150;
      // ignore: avoid_print
      print('TileTracker.update: ${perFrameUs.toStringAsFixed(0)} us/frame');
      expect(perFrameUs, lessThan(5000));
    });
  });
}
