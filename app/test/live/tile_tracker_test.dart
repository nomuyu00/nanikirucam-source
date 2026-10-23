// ライブの安定判定のテスト（設計書 4.9）: 記録したフレーム列（ラベルと確度の時系列）を入力に、
// stable になるタイミングと、誤った手で案内（canAdvise）が出ないことを固定する。
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

/// [hand14] から 7m を切った 13 枚。
const hand13 = [
  '1m', '2m', '3m', '5m', '4p', '5p', //
  '6p', '3s', '4s', '8s', '9s', '1z', '1z',
];

/// 5 fps（200ms ごと）のフレーム列を作る。
List<TrackerObservation> steady(
  List<String> labels, {
  required int fromMs,
  required int toMs,
  int stepMs = 200,
  List<double>? scores,
  double luminance = 0.5,
  List<String> Function(int frame)? mutate,
  double left = 0.1,
  double right = 0.9,
}) {
  final frames = <TrackerObservation>[];
  var i = 0;
  for (var t = fromMs; t <= toMs; t += stepMs, i++) {
    final current = mutate?.call(i) ?? labels;
    frames.add(
      obs(
        t,
        handBoxes(
          current,
          scores: scores,
          seed: t,
          jitter: 0.004,
          left: left,
          right: right,
        ),
        luminance: luminance,
      ),
    );
  }
  return frames;
}

/// 全フレームを流し、各フレームの結果を返す。
List<(TrackerObservation, TrackerSnapshot)> run(
  TileTracker tracker,
  List<TrackerObservation> frames,
) => [for (final f in frames) (f, tracker.update(f))];

void main() {
  group('stable になるタイミング', () {
    test('同じ 14 枚が 1.0 秒続いたら stable（それまでは案内しない）', () {
      final tracker = TileTracker();
      final results = run(tracker, steady(hand14, fromMs: 0, toMs: 2000));
      for (final (frame, snap) in results) {
        final ms = frame.timestamp.inMilliseconds;
        if (ms < 1000) {
          expect(snap.isStable, isFalse, reason: '$ms ms');
          expect(snap.canAdvise, isFalse, reason: '$ms ms');
          expect(snap.state, LiveTrackState.searching, reason: '$ms ms');
        } else {
          expect(snap.state, LiveTrackState.stable, reason: '$ms ms');
          expect(snap.canAdvise, isTrue);
          expect(snap.labels, hand14);
          expect(snap.count, 14);
          expect(snap.stableFor.inMilliseconds, ms - 1000);
        }
      }
    });

    test('13 枚でも同じ（stable は 13/14 枚だけ）', () {
      final tracker = TileTracker();
      final last = run(tracker, steady(hand13, fromMs: 0, toMs: 1200)).last.$2;
      expect(last.isStable, isTrue);
      expect(last.labels, hand13);
    });

    test('低い fps でも 2 フレームだけでは決めない（最小 3 フレーム）', () {
      final tracker = TileTracker();
      final results = run(
        tracker,
        steady(hand14, fromMs: 0, toMs: 2000, stepMs: 1000),
      );
      expect(results[1].$2.isStable, isFalse, reason: '1000ms は 2 フレーム目');
      expect(results[2].$2.isStable, isTrue);
    });

    test('記録したフレーム列: 手を置いて、1 枚だけ一瞬読み違えても 1 秒で stable', () {
      // 時刻ms 輝度 牌:確度 …（1z が 1 フレームだけ 2z に、7m が 1 フレームだけ低確度）
      const recording = '''
0    0.42 1m 2m 3m 5m 7m 4p 5p 6p 3s 4s 8s 9s 1z 1z
180  0.43 1m 2m 3m 5m 7m 4p 5p 6p 3s 4s 8s 9s 1z 1z
390  0.41 1m 2m 3m 5m 7m 4p 5p 6p 3s 4s 8s 9s 2z:.41 1z  # 読み違い
600  0.42 1m 2m 3m 5m 7m:.55 4p 5p 6p 3s 4s 8s 9s 1z 1z
790  0.44 1m 2m 3m 5m 7m 4p 5p 6p 3s 4s 8s 9s 1z 1z
1010 0.43 1m 2m 3m 5m 7m 4p 5p 6p 3s 4s 8s 9s 1z 1z
1190 0.42 1m 2m 3m 5m 7m 4p 5p 6p 3s 4s 8s 9s 1z 1z
''';
      final tracker = TileTracker();
      final results = run(tracker, parseRecording(recording));
      final states = [for (final r in results) r.$2.state];
      expect(states.take(5), everyElement(isNot(LiveTrackState.stable)));
      expect(results[5].$2.isStable, isTrue);
      expect(results[5].$2.labels, hand14);
      expect(results[5].$2.lowConfidenceCount, 0);
      expect(results.last.$2.canAdvise, isTrue);
    });
  });

  group('1 枚だけ揺れる', () {
    test('4 フレームに 1 回だけ別の牌に見えても、stable のまま正しい手を保つ', () {
      final tracker = TileTracker();
      final frames = steady(
        hand14,
        fromMs: 0,
        toMs: 6000,
        mutate: (i) {
          if (i % 4 != 2) return hand14;
          return [...hand14]..[4] = '8m';
        },
      );
      final results = run(tracker, frames);
      for (final (frame, snap) in results) {
        if (snap.canAdvise) expect(snap.labels, hand14);
        if (frame.timestamp.inMilliseconds >= 1200) {
          expect(snap.isStable, isTrue, reason: '${frame.timestamp}');
        }
      }
    });

    test('半々で揺れる牌は確度が下がり、別の牌で stable にならない', () {
      final tracker = TileTracker();
      final frames = steady(
        hand14,
        fromMs: 0,
        toMs: 6000,
        mutate: (i) => i.isEven ? hand14 : ([...hand14]..[4] = '8m'),
      );
      final results = run(tracker, frames);
      for (final (frame, snap) in results) {
        expect(
          snap.canAdvise && snap.labels[4] == '8m',
          isFalse,
          reason: '読み違いの手で案内してはいけない',
        );
        if (snap.tiles.length == 14 && frame.timestamp.inMilliseconds >= 600) {
          expect(snap.tiles[4].lowConfidence, isTrue);
        }
      }
    });
  });

  group('手を動かしているとき', () {
    test('枚数もラベルも変わり続ける間は stable にならない', () {
      final random = Random(42);
      const pool = [
        '1m', '2m', '3m', '4m', '5m', '6m', '7m', '8m', '9m', //
        '1p', '2p', '3p', '4p', '5p', '6p', '7p', '8p', '9p',
        '1s', '2s', '3s', '4s', '5s', '6s', '7s', '8s', '9s',
        '1z', '2z', '3z', '4z', '5z', '6z', '7z',
      ];
      final tracker = TileTracker();
      for (var t = 0; t <= 5000; t += 150) {
        final n = 11 + random.nextInt(5);
        final labels = [for (var k = 0; k < n; k++) pool[random.nextInt(34)]];
        final snap = tracker.update(
          obs(t, handBoxes(labels, seed: t, jitter: 0.01)),
        );
        expect(snap.isStable, isFalse, reason: '$t ms');
        expect(snap.canAdvise, isFalse);
      }
    });

    test('14 枚 → 手を動かす → 13 枚: 案内は元の 14 枚か新しい 13 枚だけ', () {
      final random = Random(7);
      final tracker = TileTracker();
      final frames = <TrackerObservation>[
        ...steady(hand14, fromMs: 0, toMs: 2000),
        // 牌を取って捨てる間（手が牌を隠す・枚数が揺れる）。
        for (var t = 2200; t <= 2800; t += 200)
          obs(
            t,
            handBoxes(
              [...hand13]..removeRange(0, random.nextInt(4)),
              seed: t,
              jitter: 0.02,
              left: 0.1 + random.nextDouble() * 0.1,
            ),
          ),
        ...steady(hand13, fromMs: 3000, toMs: 5000),
      ];
      int? firstStable13;
      for (final (frame, snap) in run(tracker, frames)) {
        final ms = frame.timestamp.inMilliseconds;
        if (snap.canAdvise) {
          final ok =
              (snap.labels.join() == hand14.join() && ms <= 2400) ||
              snap.labels.join() == hand13.join();
          expect(ok, isTrue, reason: '$ms ms で ${snap.labels}');
        }
        if (snap.isStable && snap.count == 13) firstStable13 ??= ms;
      }
      // 手が止まって（3000ms）から 1.0 秒 + 1 フレームで案内できる。
      expect(firstStable13, isNotNull);
      expect(firstStable13! - 3000, lessThanOrEqualTo(1200));
    });

    test('同じ枚数で 1 枚入れ替えたら、古い手の案内は 2 フレームで消える', () {
      final changed = [...hand14]..[12] = '7z';
      final tracker = TileTracker();
      final results = run(tracker, [
        ...steady(hand14, fromMs: 0, toMs: 2000),
        ...steady(changed, fromMs: 2200, toMs: 5000),
      ]);
      for (final (frame, snap) in results) {
        final ms = frame.timestamp.inMilliseconds;
        if (ms >= 2400 && snap.canAdvise) {
          expect(snap.labels, changed, reason: '$ms ms');
        }
      }
      expect(results.last.$2.canAdvise, isTrue);
      expect(results.last.$2.labels, changed);
    });
  });

  group('確度が低い', () {
    test('確度 0.6 未満が 2 枚以上なら stable でも案内しない', () {
      final scores = List<double>.filled(14, 0.9)
        ..[3] = 0.45
        ..[9] = 0.5;
      final tracker = TileTracker();
      final last = run(
        tracker,
        steady(hand14, fromMs: 0, toMs: 1600, scores: scores),
      ).last.$2;
      expect(last.isStable, isTrue);
      expect(last.lowConfidenceCount, 2);
      expect(last.block, AdviceBlock.lowConfidence);
      expect(last.canAdvise, isFalse);
    });

    test('1 枚だけなら案内する（その牌に印を付ける）', () {
      final scores = List<double>.filled(14, 0.9)..[3] = 0.45;
      final tracker = TileTracker();
      final last = run(
        tracker,
        steady(hand14, fromMs: 0, toMs: 1600, scores: scores),
      ).last.$2;
      expect(last.canAdvise, isTrue);
      expect(last.lowConfidenceCount, 1);
      expect(last.tiles[3].lowConfidence, isTrue);
    });

    test('同じ牌が 5 枚に見えたら案内しない', () {
      final labels = [...hand14]
        ..[0] = '1z'
        ..[1] = '1z'
        ..[2] = '1z';
      final tracker = TileTracker();
      final last = run(tracker, steady(labels, fromMs: 0, toMs: 1600)).last.$2;
      expect(last.isStable, isTrue);
      expect(last.block, AdviceBlock.impossibleHand);
      expect(last.canAdvise, isFalse);
    });
  });

  group('枚数・暗い・遠い', () {
    test('12 枚・15 枚は count_mismatch で、stable にならない', () {
      for (final n in [12, 15]) {
        final labels = [...hand14, '9m'].take(n).toList();
        final tracker = TileTracker();
        for (final (_, snap) in run(
          tracker,
          steady(labels, fromMs: 0, toMs: 3000),
        )) {
          expect(snap.state, LiveTrackState.countMismatch);
          expect(snap.count, n);
          expect(snap.canAdvise, isFalse);
        }
      }
    });

    test('暗いと dark。短い暗さ（0.8 秒以内）は無視し、続けば最初から', () {
      final tracker = TileTracker();
      final dark = run(
        tracker,
        steady(hand14, fromMs: 0, toMs: 1000, luminance: 0.05),
      );
      expect(dark.every((r) => r.$2.state == LiveTrackState.dark), isTrue);

      final t2 = TileTracker();
      run(t2, steady(hand14, fromMs: 0, toMs: 1400));
      expect(t2.snapshot.isStable, isTrue);
      // 1 フレームだけ暗い → stable のまま。
      expect(
        t2.update(obs(1600, handBoxes(hand14), luminance: 0.05)).isStable,
        isTrue,
      );
      expect(t2.update(obs(1800, handBoxes(hand14))).isStable, isTrue);
      // 2〜4 フレーム続けて暗くても、最後に見えてから 0.8 秒以内なら stable のまま
      // （手持ちで一瞬影になった・ぶれた。以前は 2 フレームで最初からだった）。
      for (final t in [2000, 2200, 2400, 2600]) {
        expect(
          t2.update(obs(t, handBoxes(hand14), luminance: 0.05)).isStable,
          isTrue,
          reason: '$t ms',
        );
      }
      // 0.8 秒を超えて暗い → dark にして、明るくなってから 1 秒待つ。
      expect(
        t2.update(obs(2800, handBoxes(hand14), luminance: 0.05)).state,
        LiveTrackState.dark,
      );
      final after = run(t2, steady(hand14, fromMs: 3000, toMs: 4200));
      expect(after.first.$2.isStable, isFalse);
      expect(
        after.where((r) => r.$2.isStable).first.$1.timestamp.inMilliseconds,
        4000,
      );
    });

    test('手牌の幅が画面の 50% 未満なら far', () {
      final tracker = TileTracker();
      final results = run(
        tracker,
        steady(hand14, fromMs: 0, toMs: 2000, left: 0.3, right: 0.7),
      );
      for (final (_, snap) in results) {
        expect(snap.state, LiveTrackState.far);
        expect(snap.handWidth, closeTo(0.4, 0.05));
      }
    });

    test('牌がない・少ないと searching', () {
      final tracker = TileTracker();
      expect(tracker.update(obs(0, const [])).state, LiveTrackState.searching);
      expect(
        tracker.update(obs(200, handBoxes(['1m', '2m']))).state,
        LiveTrackState.searching,
      );
    });

    test('フレームが 2 秒以上空いたら（一時停止など）最初から', () {
      final tracker = TileTracker();
      run(tracker, steady(hand14, fromMs: 0, toMs: 1400));
      expect(tracker.snapshot.isStable, isTrue);
      expect(tracker.update(obs(5000, handBoxes(hand14))).isStable, isFalse);
    });
  });

  group('手牌の列の選び方', () {
    test('上の段の河・裏向き・低確度の枠は列に入れない', () {
      final tracker = TileTracker();
      final row = handBoxes(hand14);
      final river = handBoxes(
        ['2m', '3m', '4m', '5m'],
        y: 0.25,
        left: 0.3,
        right: 0.6,
      );
      final noise = [
        const LiveTileBox(
          box: Rect.fromLTWH(0.92, 0.5, 0.05, 0.07),
          label: '0b',
          score: 0.9,
        ),
        const LiveTileBox(
          box: Rect.fromLTWH(0.02, 0.48, 0.05, 0.07),
          label: '9p',
          score: 0.1,
        ),
      ];
      final selected = tracker.extractRow([...river, ...noise, ...row]);
      expect([for (final t in selected) t.label], hand14);
    });

    test('同じ位置に重なった枠は確度の高い方だけ', () {
      final tracker = TileTracker();
      final row = handBoxes(hand14);
      final duplicate = LiveTileBox(
        box: row[5].box.translate(0.002, 0),
        label: '9p',
        score: 0.4,
      );
      final selected = tracker.extractRow([...row, duplicate]);
      expect(selected.length, 14);
      expect(selected[5].label, hand14[5]);
    });
  });
}
