import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/tile_tracker.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';

import 'support/live_fakes.dart';

void main() {
  late List<RecordedEvent> events;
  late ScriptedDetector detector;
  late ManualLiveClock clock;
  late LiveController controller;
  late List<LiveAdvice> shown;

  setUp(() {
    events = [];
    shown = [];
    detector = ScriptedDetector()..loaded = true;
    clock = ManualLiveClock();
    controller = LiveController(
      detector: detector,
      analysis: inProcessAnalysis(),
      clock: clock,
      log: (event, parameters) =>
          events.add(RecordedEvent(event.name, parameters)),
      onAdviceShown: shown.add,
    );
  });

  tearDown(() => controller.dispose());

  /// [labels] を [fromMs] から [toMs] まで 200ms ごとに入れ、解析の完了を待つ。
  Future<void> feed(List<String> labels, int fromMs, int toMs) async {
    for (var t = fromMs; t <= toMs; t += 200) {
      controller.observe(obs(t, handBoxes(labels, seed: t)));
      await Future<void>.delayed(Duration.zero);
    }
  }

  int bestBalance(List<String> labels) => DefaultNanikiruEngine()
      .analyze(HandInput(tiles: labels).toHandState(), deep: false)
      .bestByAxis[StrategyAxis.balance]!
      .first;

  test('stable になるまで案内せず、なったら 14 枚の切る牌を案内する', () async {
    await feed(HandFixtures.fourteen, 0, 800);
    expect(controller.advice, isNull);
    expect(controller.snapshot.isStable, isFalse);

    await feed(HandFixtures.fourteen, 1000, 1000);
    final advice = controller.advice;
    expect(advice, isNotNull);
    expect(advice!.kind, LiveAdviceKind.discard);
    expect(
      advice.discardFor(StrategyAxis.balance),
      bestBalance(HandFixtures.fourteen),
    );
    expect(controller.adviceCount, 1);
    expect(shown, hasLength(1));
    final adviceShown = events.where((e) => e.name == 'liveAdviceShown').single;
    expect(adviceShown.parameters, {
      'hand_size': 14,
      'stable_ms': 1000,
      'low_confidence_tiles': 0,
      'axis': 'balance',
    });

    // 同じ手が続く間は数え直さない。
    await feed(HandFixtures.fourteen, 1200, 2000);
    expect(controller.adviceCount, 1);
  });

  test('手が動いたら案内を消す（stable 以外では出さない）', () async {
    await feed(HandFixtures.fourteen, 0, 1200);
    expect(controller.advice, isNotNull);
    controller.observe(
      obs(1400, handBoxes(HandFixtures.fourteen.take(11).toList())),
    );
    controller.observe(
      obs(1600, handBoxes(HandFixtures.fourteen.take(12).toList())),
    );
    expect(controller.snapshot.isStable, isFalse);
    expect(controller.advice, isNull);
  });

  test(
    '案内した牌を切った 13 枚が stable になれば live_advice_followed{followed: 1}',
    () async {
      await feed(HandFixtures.fourteen, 0, 1200);
      final discard = controller.advice!.discardFor(StrategyAxis.balance)!;
      final hand13 = [...HandFixtures.fourteen]..remove(tileLabelOfId(discard));
      await feed(hand13, 1400, 3000);
      expect(controller.advice?.kind, LiveAdviceKind.thirteen);
      expect(controller.followChecks, 1);
      expect(controller.followedCount, 1);
      expect(
        events.where((e) => e.name == 'liveAdviceFollowed').single.parameters,
        {'followed': 1},
      );
      expect(controller.adviceCount, 2);
    },
  );

  test('別の牌を切ったら followed: 0', () async {
    await feed(HandFixtures.fourteen, 0, 1200);
    final discard = controller.advice!.discardFor(StrategyAxis.balance)!;
    final other = HandFixtures.fourteen.firstWhere(
      (l) => tileIdFromLabel(l) != discard,
    );
    final hand13 = [...HandFixtures.fourteen]..remove(other);
    await feed(hand13, 1400, 3000);
    expect(controller.followChecks, 1);
    expect(controller.followedCount, 0);
    expect(
      events.where((e) => e.name == 'liveAdviceFollowed').single.parameters,
      {'followed': 0},
    );
  });

  test('和了形の 14 枚は「ツモ！」を記録し、live_win_detected を送る', () async {
    await feed(HandFixtures.win, 0, 1400);
    expect(controller.advice?.kind, LiveAdviceKind.win);
    expect(controller.wins, hasLength(1));
    final win = controller.wins.single;
    expect(win.winType, 'tsumo');
    expect(win.points, greaterThan(0));
    expect(win.hand?.tiles, HandFixtures.win);
    expect(controller.activeWin, isNotNull);
    final event = events.where((e) => e.name == 'liveWinDetected').single;
    expect(event.parameters['win_type'], 'tsumo');
    expect(event.parameters['rank'], 'none');

    controller.dismissWin();
    expect(controller.activeWin, isNull);
    await feed(HandFixtures.win, 1600, 2400);
    expect(controller.wins, hasLength(1), reason: '同じ手は 1 回だけ');
    expect(controller.activeWin, isNull, reason: '次の局へで消したまま');
  });

  test('確度の低い牌が 2 枚以上なら解析もしない', () async {
    final scores = List<double>.filled(14, 0.9)
      ..[0] = 0.4
      ..[1] = 0.4;
    for (var t = 0; t <= 1600; t += 200) {
      controller.observe(
        obs(t, handBoxes(HandFixtures.fourteen, scores: scores)),
      );
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.snapshot.isStable, isTrue);
    expect(controller.snapshot.block, AdviceBlock.lowConfidence);
    expect(controller.advice, isNull);
    expect(events.where((e) => e.name == 'liveAdviceShown'), isEmpty);
  });

  test('軸を切り替えると axis_changed を送り、採用の判定もその軸の牌にする', () async {
    await feed(HandFixtures.fourteen, 0, 1200);
    controller.setAxis(StrategyAxis.points);
    expect(events.where((e) => e.name == 'axisChanged').single.parameters, {
      'axis_from': 'balance',
      'axis_to': 'points',
      'screen': 'live',
    });
    expect(controller.axis, StrategyAxis.points);
  });

  test('設定の既定の軸は、画面で選んだ後は上書きしない', () async {
    controller.applyDefaultAxis(StrategyAxis.speed);
    expect(controller.axis, StrategyAxis.speed);
    expect(events.where((e) => e.name == 'axisChanged'), isEmpty);
    controller.setAxis(StrategyAxis.balance);
    controller.applyDefaultAxis(StrategyAxis.points);
    expect(controller.axis, StrategyAxis.balance);
  });

  test('一時停止で最初から（案内も消える）', () async {
    await feed(HandFixtures.fourteen, 0, 1200);
    expect(controller.advice, isNotNull);
    controller.setPaused(true);
    expect(controller.advice, isNull);
    expect(controller.snapshot.state, LiveTrackState.searching);
  });

  test('状態の割合（live_state 用）', () async {
    controller.observe(obs(0, const []));
    controller.observe(obs(1000, const []));
    await feed(HandFixtures.fourteen, 1200, 3200);
    final ratios = controller.stateRatiosPct();
    expect(
      ratios.keys,
      containsAll([LiveTrackState.searching, LiveTrackState.stable]),
    );
    expect(
      ratios.values.fold<int>(0, (a, b) => a + b),
      inInclusiveRange(99, 101),
    );
  });

  test('フレームは FrameGate を通して推論する（温度警告で 1 fps）', () async {
    detector.next = () => handBoxes(HandFixtures.fourteen);
    for (var i = 0; i < 30; i++) {
      clock.now = Duration(milliseconds: i * 33);
      controller.onFrame(FakeLiveCamera.frame, quarterTurns: 1);
      await Future<void>.delayed(Duration.zero);
    }
    expect(detector.calls, inInclusiveRange(5, 7), reason: '約 1 秒で 6 fps');

    controller.setThermalWarning(true);
    expect(controller.targetFps, 1);
    detector.calls = 0;
    for (var i = 30; i < 120; i++) {
      clock.now = Duration(milliseconds: i * 33);
      controller.onFrame(FakeLiveCamera.frame, quarterTurns: 1);
      await Future<void>.delayed(Duration.zero);
    }
    expect(detector.calls, inInclusiveRange(2, 4), reason: '約 3 秒で 1 fps');
  });

  test('解析中に手が変わったら、古い解析結果では案内しない', () async {
    await feed(HandFixtures.fourteen, 0, 1200);
    expect(controller.advice?.handKey, controller.snapshot.handKey);
    final changed = [...HandFixtures.fourteen]..[13] = '7z';
    await feed(changed, 1400, 2000);
    final advice = controller.advice;
    if (advice != null) {
      expect(advice.handKey, controller.snapshot.handKey);
      expect(advice.input.tiles, changed);
    }
  });

  test('局の設定を変えると解析し直す', () async {
    await feed(HandFixtures.win, 0, 1400);
    final before = controller.wins.single.points;
    controller.setHandContext(
      const LiveHandContext(seatWind: Wind.east, doraIndicators: ['7z']),
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.advice?.input.dealer, isTrue);
    expect(controller.advice!.report.winPoints, greaterThan(before));
  });

  test('events は許可された名前だけ', () {
    expect(
      AnalyticsEvent.values.map((e) => e.name),
      containsAll([
        'liveStarted',
        'liveEnded',
        'liveAdviceShown',
        'liveAdviceFollowed',
        'liveState',
        'liveWinDetected',
      ]),
    );
  });

  group('手持ちの揺れ', () {
    test('canAdvise が落ちても、同じ手なら 0.7 秒は直前の案内を保ち（薄く出す）、その後消す', () async {
      await feed(HandFixtures.fourteen, 0, 1200);
      expect(controller.advice, isNotNull);
      expect(controller.adviceHeld, isFalse);
      // 2 枚の確度が落ちる（反射など。列には残る 0.3）→ しばらくして平均が 0.6 を割り、
      // 確度の低い牌が 2 枚になって canAdvise が落ちる。
      final scores = List<double>.filled(14, 0.92)
        ..[0] = 0.3
        ..[1] = 0.3;
      int? blockedAt;
      for (var t = 1400; t <= 4000; t += 200) {
        controller.observe(
          obs(t, handBoxes(HandFixtures.fourteen, scores: scores, seed: t)),
        );
        await Future<void>.delayed(Duration.zero);
        if (controller.snapshot.canAdvise) continue;
        blockedAt ??= t;
        final since = t - blockedAt;
        if (since + 200 <= 700) {
          // 最後に canAdvise だったフレームから 0.7 秒以内は保つ。
          expect(controller.advice, isNotNull, reason: '$t ms');
          expect(controller.adviceHeld, isTrue, reason: '$t ms');
        } else if (since >= 800) {
          expect(controller.advice, isNull, reason: '$t ms');
          expect(controller.adviceHeld, isFalse);
        }
      }
      expect(blockedAt, isNotNull);
      expect(controller.snapshot.block, AdviceBlock.lowConfidence);
      expect(controller.adviceCount, 1, reason: '保っている間に数え直さない');
    });

    test('手が変わった（同じ別の並びが 2 フレーム）ら、保たずにすぐ消す', () async {
      await feed(HandFixtures.fourteen, 0, 1200);
      final changed = [...HandFixtures.fourteen]..[13] = '7z';
      controller.observe(obs(1400, handBoxes(changed, seed: 1400)));
      await Future<void>.delayed(Duration.zero);
      controller.observe(obs(1600, handBoxes(changed, seed: 1600)));
      await Future<void>.delayed(Duration.zero);
      expect(controller.snapshot.handChanging, isTrue);
      expect(controller.advice, isNull);
      expect(controller.adviceHeld, isFalse);
    });

    test('短い取りこぼし（0.8 秒以内）では案内が途切れない', () async {
      await feed(HandFixtures.fourteen, 0, 1200);
      for (final t in [1400, 1600, 1800]) {
        controller.observe(obs(t, const []));
        await Future<void>.delayed(Duration.zero);
        expect(controller.advice, isNotNull, reason: '$t ms');
        expect(controller.adviceHeld, isFalse);
      }
    });

    // 右端が 789p（チーとして成り立つ）の 14 枚。
    const chiAtRight = [
      '1m', '2m', '3m', '4m', '5m', '6m', '3p', '4p', //
      '2s', '3s', '1z', '7p', '8p', '9p',
    ];
    List<LiveTileBox> sideways(List<LiveTileBox> boxes, int index) {
      final b = boxes[index].box;
      return [...boxes]
        ..[index] = LiveTileBox(
          box: Rect.fromCenter(
            center: b.center,
            width: b.height,
            height: b.width,
          ),
          label: boxes[index].label,
          score: boxes[index].score,
        );
    }

    test('1 フレームだけ横向きに見えた（偽の副露）では、案内を止め続けない', () async {
      for (var t = 0; t <= 1600; t += 200) {
        final boxes = handBoxes(chiAtRight, seed: t);
        // stable になる瞬間（1000ms）のフレームだけ、右から 3 枚目が横向きに見える。
        controller.observe(obs(t, t == 1000 ? sideways(boxes, 11) : boxes));
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.snapshot.isStable, isTrue);
      expect(controller.meldSuspected, isFalse);
      expect(controller.advice, isNotNull);
    });

    test('横向きの牌が続けて見える（本当に鳴いた手）なら、従来どおり案内しない', () async {
      for (var t = 0; t <= 1600; t += 200) {
        controller.observe(
          obs(t, sideways(handBoxes(chiAtRight, seed: t), 11)),
        );
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.snapshot.isStable, isTrue);
      expect(controller.meldSuspected, isTrue);
      expect(controller.advice, isNull);
    });
  });
}
