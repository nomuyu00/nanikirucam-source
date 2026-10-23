import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/live/frame_gate.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';

Duration ms(num v) => Duration(microseconds: (v * 1000).round());

/// 30 fps のカメラから [seconds] 秒ぶんのフレームを流し、通した時刻を返す。
List<Duration> feed(
  FrameGate gate, {
  double seconds = 1,
  Duration Function(Duration at)? processing,
}) {
  final accepted = <Duration>[];
  Duration? busyUntil;
  for (var i = 0; i < (seconds * 30).round(); i++) {
    final at = ms(i * 1000 / 30);
    if (busyUntil != null && at >= busyUntil) {
      gate.release();
      busyUntil = null;
    }
    if (gate.tryAcquire(at)) {
      accepted.add(at);
      final cost = processing?.call(at);
      if (cost == null) {
        gate.release();
      } else {
        busyUntil = at + cost;
      }
    }
  }
  return accepted;
}

void main() {
  group('FrameGate', () {
    test('目標 fps に間引く（30 fps → 5 fps）', () {
      final gate = FrameGate(targetFps: 5);
      final accepted = feed(gate, seconds: 2);
      expect(accepted.length, 10);
      for (var i = 1; i < accepted.length; i++) {
        expect(
          (accepted[i] - accepted[i - 1]).inMilliseconds,
          inInclusiveRange(180, 234),
        );
      }
      expect(gate.droppedRate, 60 - 10);
    });

    test('推論中のフレームは捨てる（溜めない）', () {
      final gate = FrameGate(targetFps: 30);
      // 1 推論 250ms かかると、30 fps を指定しても 4 fps しか通らない。
      final accepted = feed(gate, seconds: 1, processing: (_) => ms(250));
      expect(accepted.length, 4);
      expect(gate.droppedBusy, greaterThan(20));
      expect(gate.busy, isTrue);
      gate.release();
      expect(gate.busy, isFalse);
    });

    test('温度警告の 1 fps', () {
      final gate = FrameGate(targetFps: 1);
      expect(feed(gate, seconds: 3).length, 3);
    });

    test('reset で次のフレームをすぐ通す', () {
      final gate = FrameGate(targetFps: 1);
      expect(gate.tryAcquire(ms(0)), isTrue);
      gate.release();
      expect(gate.tryAcquire(ms(100)), isFalse);
      gate.reset();
      expect(gate.tryAcquire(ms(150)), isTrue);
    });

    test('おかしな fps は既定値にする', () {
      expect(FrameGate(targetFps: 0).targetFps, 5);
      expect(FrameGate(targetFps: double.nan).targetFps, 5);
    });
  });

  group('LiveFrameRatePolicy', () {
    const policy = LiveFrameRatePolicy(movingFps: 6);

    TrackerSnapshot stable(Duration stableFor, {bool rawAgrees = true}) =>
        TrackerSnapshot(
          state: LiveTrackState.stable,
          stableFor: stableFor,
          rawAgrees: rawAgrees,
        );

    test('動いている・探している間は 5〜8 fps', () {
      for (final state in [
        LiveTrackState.searching,
        LiveTrackState.moving,
        LiveTrackState.countMismatch,
      ]) {
        expect(
          policy.targetFps(
            snapshot: TrackerSnapshot(state: state),
            thermalWarning: false,
          ),
          6,
        );
      }
    });

    test('stable が 3 秒続いたら 2 fps（最新のフレームが食い違えば戻す）', () {
      expect(
        policy.targetFps(
          snapshot: stable(const Duration(seconds: 2)),
          thermalWarning: false,
        ),
        6,
      );
      expect(
        policy.targetFps(
          snapshot: stable(const Duration(seconds: 3)),
          thermalWarning: false,
        ),
        2,
      );
      expect(
        policy.targetFps(
          snapshot: stable(const Duration(seconds: 5), rawAgrees: false),
          thermalWarning: false,
        ),
        6,
      );
    });

    test('温度警告なら状態によらず 1 fps', () {
      expect(
        policy.targetFps(
          snapshot: stable(const Duration(seconds: 5)),
          thermalWarning: true,
        ),
        1,
      );
      expect(
        policy.targetFps(
          snapshot: TrackerSnapshot.initial,
          thermalWarning: true,
        ),
        1,
      );
    });

    test('Remote Config の live_target_fps は 5〜8 に収める', () {
      expect(LiveFrameRatePolicy.fromTarget(3).movingFps, 5);
      expect(LiveFrameRatePolicy.fromTarget(7).movingFps, 7);
      expect(LiveFrameRatePolicy.fromTarget(30).movingFps, 8);
    });
  });
}
