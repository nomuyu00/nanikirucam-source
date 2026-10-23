import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/live/live_controller.dart';
import 'package:nanikiru_cam/live/live_model_tier.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/live_fakes.dart';

const _s = ModelConfig.liveSInt8Model;
const _n = ModelConfig.liveNInt8Model;
const _n480 = ModelConfig.liveN480Int8Model;

void main() {
  group('LiveSpeedWindow', () {
    test('最初の捨てフレームを数えず、そろったら complete', () {
      final w = LiveSpeedWindow(warmupFrames: 2, sampleFrames: 3);
      expect(w.medianMs, isNull);
      expect(w.add(900000), isFalse);
      expect(w.add(900000), isFalse);
      expect(w.medianMs, isNull);
      expect(w.add(100000), isFalse);
      expect(w.add(300000), isFalse);
      expect(w.complete, isFalse);
      expect(w.add(200000), isTrue);
      expect(w.complete, isTrue);
      expect(w.medianMs, 200);
      // そろったあとは増やさない。
      expect(w.add(1), isFalse);
      expect(w.medianMs, 200);
      w.reset();
      expect(w.medianMs, isNull);
      expect(w.complete, isFalse);
    });

    test('偶数個は真ん中 2 つの平均', () {
      final w = LiveSpeedWindow(warmupFrames: 0, sampleFrames: 4)
        ..add(100000)
        ..add(400000)
        ..add(200000)
        ..add(300000);
      expect(w.medianMs, 250);
    });
  });

  group('LiveModelTiering', () {
    test('既定: 180 ms、10 フレーム捨てて 20 フレームの中央値、s → n → n 480', () {
      const tiering = LiveModelTiering();
      expect(tiering.slowThresholdMs, 180);
      expect(tiering.warmupFrames, 10);
      expect(tiering.sampleFrames, 20);
      expect(tiering.tiers, [_s, _n, _n480]);
    });

    test('次の段は 1 つ右。右端と段にないモデルは null', () {
      const tiering = LiveModelTiering();
      expect(tiering.nextTier(_s), _n);
      expect(tiering.nextTier(_n), _n480);
      expect(tiering.nextTier(_n480), isNull);
      expect(tiering.nextTier(ModelConfig.int8Model), isNull);
      expect(tiering.nextTier(null), isNull);
    });
  });

  group('LiveController のモデル自動切り替え', () {
    late ScriptedDetector detector;
    late ManualLiveClock clock;
    late List<String> saved;
    late LiveController controller;

    LiveController create({LiveModelTiering? tiering}) => LiveController(
      detector: detector,
      analysis: inProcessAnalysis(),
      clock: clock,
      modelTiering: tiering,
    );

    setUp(() {
      detector = ScriptedDetector()
        ..loaded = true
        ..activeModel = _s;
      clock = ManualLiveClock();
      saved = [];
      controller = create(tiering: LiveModelTiering(onSwitched: saved.add));
    });

    tearDown(() => controller.dispose());

    /// [count] フレーム、[stepMs] 間隔でカメラから届いたことにする。
    /// 手が安定して 3 秒たつと目標が 2 fps に下がるので、安定を保つ間は 500 ms 以上空ける。
    Future<void> frames(int count, {int stepMs = 200}) async {
      for (var i = 0; i < count; i++) {
        clock.now += Duration(milliseconds: stepMs);
        controller.onFrame(FakeLiveCamera.frame, quarterTurns: 0);
        await Future<void>.delayed(Duration.zero);
      }
    }

    void takes(int ms) {
      detector
        ..preprocessMicros = ms * 100 // 前処理 1 割
        ..inferenceMicros = ms * 900; // 推論 9 割
    }

    test('遅い（中央値 210 ms）と、30 フレーム目で 1 段落ちて保存する', () async {
      takes(210);
      await frames(29);
      expect(detector.switchRequests, isEmpty);
      await frames(1);
      expect(detector.switchRequests, [_n]);
      expect(detector.activeModel, _n);
      expect(saved, [_n]);
      expect(controller.switching, isFalse);
      expect(controller.modelLabel, _n);
      // 新しいモデルで測り直す。
      expect(controller.speedMedianMs, isNull);
    });

    test('速い（100 ms）と落ちない。あとで遅くなっても判定は最初の区間だけ', () async {
      takes(100);
      await frames(30);
      expect(detector.switchRequests, isEmpty);
      expect(controller.speedMedianMs, closeTo(100, 0.01));
      takes(500);
      await frames(90);
      expect(detector.switchRequests, isEmpty);
      expect(saved, isEmpty);
      expect(detector.activeModel, _s);
    });

    test('ちょうど 180 ms は遅くない（超えたら）', () async {
      takes(180);
      await frames(60);
      expect(detector.switchRequests, isEmpty);
      takes(181);
      // 判定は終わっているので、その後に遅くなっても落ちない。
      await frames(60);
      expect(detector.switchRequests, isEmpty);
    });

    test('最初の 10 フレームは捨てる（読み込み直後の遅さで落ちない）', () async {
      takes(600);
      await frames(10);
      takes(100);
      await frames(20);
      expect(detector.switchRequests, isEmpty);
      expect(controller.speedMedianMs, closeTo(100, 0.01));
    });

    test('平均ではなく中央値（たまの遅いフレームでは落ちない）', () async {
      takes(100);
      await frames(10); // 捨てる分
      // 20 フレームのうち 6 つが 900 ms。平均は 340 ms だが中央値は 100 ms。
      for (var i = 0; i < 20; i++) {
        takes(i % 3 == 0 && i < 18 ? 900 : 100);
        await frames(1);
      }
      expect(detector.switchRequests, isEmpty);
      expect(controller.speedMedianMs, closeTo(100, 0.01));
    });

    test('1 段ずつ落ち、戻さず、n 480 より先へは行かない', () async {
      takes(250);
      await frames(30);
      expect(detector.switchRequests, [_n]);
      await frames(29);
      expect(detector.switchRequests, [_n]);
      await frames(1);
      expect(detector.switchRequests, [_n, _n480]);
      expect(saved, [_n, _n480]);
      // n 480 でも遅い: もう落とす先はない。s にも戻さない。
      await frames(120);
      expect(detector.switchRequests, [_n, _n480]);
      expect(detector.activeModel, _n480);
    });

    test('n に落ちて速くなったら、そこで止まる', () async {
      takes(250);
      await frames(30);
      takes(120);
      await frames(60);
      expect(detector.switchRequests, [_n]);
      expect(saved, [_n]);
      expect(controller.speedMedianMs, closeTo(120, 0.01));
    });

    test('保存した段（n）から始まっていれば、そこを基準に 1 段落ちる', () async {
      detector.activeModel = _n;
      takes(250);
      await frames(30);
      expect(detector.switchRequests, [_n480]);
    });

    test('写真用の int8 に落ちている（段にない）ときは切り替えない', () async {
      detector.activeModel = ModelConfig.int8Model;
      takes(400);
      await frames(90);
      expect(detector.switchRequests, isEmpty);
      expect(controller.speedMedianMs, closeTo(400, 0.01));
    });

    test('Remote Config で明示されたとき（modelTiering なし）は遅くても落ちない', () async {
      controller.dispose();
      controller = create(tiering: null);
      takes(400);
      await frames(90);
      expect(detector.switchRequests, isEmpty);
      expect(detector.activeModel, _s);
      // debug 表示用の中央値は出る。
      expect(controller.speedMedianMs, closeTo(400, 0.01));
    });

    test('新しいモデルを開けなかったら、今のモデルのまま続けてもう切り替えない', () async {
      detector.failSwitch = true;
      takes(250);
      await frames(30);
      expect(detector.switchRequests, [_n]);
      expect(detector.activeModel, _s);
      expect(saved, isEmpty);
      expect(controller.switching, isFalse);
      final callsBefore = detector.calls;
      await frames(90);
      expect(detector.switchRequests, [_n]);
      expect(detector.calls, greaterThan(callsBefore));
    });

    test('切り替えの間は検出を止め、案内を出さない。追跡は最初からやり直す', () async {
      detector.next = () => handBoxes(HandFixtures.fourteen);
      takes(250);
      await frames(29, stepMs: 600);
      // 30 フレーム目の前: 手が安定して案内が出ている。
      expect(controller.snapshot.isStable, isTrue);
      expect(controller.advice, isNotNull);
      expect(controller.adviceCount, 1);

      final gate = Completer<void>();
      detector.switchGate = gate;
      await frames(1, stepMs: 600);
      expect(detector.switchRequests, [_n]);
      expect(controller.switching, isTrue);
      expect(controller.advice, isNull);
      expect(controller.snapshot.isStable, isFalse);
      expect(controller.snapshot.count, 0);

      // 切り替え中に届いたフレームは推論に回さない。
      final calls = detector.calls;
      await frames(5, stepMs: 600);
      expect(detector.calls, calls);
      expect(controller.advice, isNull);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(controller.switching, isFalse);
      expect(saved, [_n]);
      // 追跡はやり直し: 切り替え直後はまだ案内しない。
      expect(controller.advice, isNull);
      expect(controller.snapshot.isStable, isFalse);

      // 新しいモデルで同じ手が安定したら、また案内が出る（案内の回数は数え直さない）。
      takes(100);
      await frames(2, stepMs: 600);
      expect(controller.snapshot.isStable, isFalse);
      expect(controller.advice, isNull);
      await frames(3, stepMs: 600);
      expect(controller.snapshot.isStable, isTrue);
      expect(controller.advice, isNotNull);
      expect(controller.adviceCount, 1);
    });

    test('切り替えを決めたフレームの結果は、追跡に使わない', () async {
      takes(250);
      await frames(29);
      final gate = Completer<void>();
      detector.switchGate = gate;
      await frames(1);
      expect(controller.switching, isTrue);
      final processed = controller.framesProcessed;
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      // 切り替えを決めたフレーム自体は追跡に入れない。
      expect(controller.framesProcessed, processed);
      expect(controller.snapshot.count, 0);
    });
  });

  group('LiveModelTierStore（live_model_tier_v1）', () {
    const version = '1.0.0+1';

    Future<LiveModelTierStore> store([Map<String, Object> values = const {}]) async {
      SharedPreferences.setMockInitialValues(values);
      return LiveModelTierStore(await SharedPreferences.getInstance());
    }

    test('保存した段を次回の開始に使う', () async {
      final s = await store();
      expect(
        await s.resolveStart(explicit: false, appVersion: version),
        isNull,
      );
      await s.save(_n, appVersion: version);
      // 別の起動（同じ保存先を読み直す）。
      final prefs = await SharedPreferences.getInstance();
      final next = LiveModelTierStore(prefs);
      expect(
        await next.resolveStart(explicit: false, appVersion: version),
        _n,
      );
      await next.save(_n480, appVersion: version);
      expect(
        await next.resolveStart(explicit: false, appVersion: version),
        _n480,
      );
    });

    test('アプリが更新されたら捨てて、既定の段から測り直す', () async {
      final s = await store();
      await s.save(_n, appVersion: version);
      expect(
        await s.resolveStart(explicit: false, appVersion: '1.0.1+2'),
        isNull,
      );
      // 捨てたので、元のバージョンに戻っても復活しない。
      expect(
        await s.resolveStart(explicit: false, appVersion: version),
        isNull,
      );
    });

    test('Remote Config で variant が明示されたら捨てる', () async {
      final s = await store();
      await s.save(_n, appVersion: version);
      expect(await s.resolveStart(explicit: true, appVersion: version), isNull);
      // 明示がなくなっても、保存はもう無い。
      expect(
        await s.resolveStart(explicit: false, appVersion: version),
        isNull,
      );
    });

    test('壊れた値・段にないモデルは無視して消す', () async {
      for (final raw in [
        'not json',
        '{"tier":"assets/models/mahjong_yolo_int8.tflite","app":"1.0.0+1"}',
        '{"tier":"bogus","app":"1.0.0+1"}',
        '[]',
      ]) {
        final s = await store({LiveModelTierStore.preferenceKey: raw});
        expect(
          await s.resolveStart(explicit: false, appVersion: version),
          isNull,
          reason: raw,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(LiveModelTierStore.preferenceKey), isNull);
      }
    });

    test('キー名', () {
      expect(LiveModelTierStore.preferenceKey, 'live_model_tier_v1');
    });
  });

  group('liveModelTieringProvider', () {
    ProviderContainer container(ModelConfig config) {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer(
        overrides: [
          modelConfigProvider.overrideWith((ref) => config),
          liveAppVersionProvider.overrideWith((ref) async => '1.0.0+1'),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('既定は自動切り替えあり。切り替えたら落ちた段を端末に保存する', () async {
      final c = container(ModelConfig.defaults);
      final tiering = c.read(liveModelTieringProvider);
      expect(tiering, isNotNull);
      expect(tiering!.tiers, ModelConfig.liveTiers);
      tiering.onSwitched!(_n);
      final store = await c.read(liveModelTierStoreProvider.future);
      // 保存は非同期（onSwitched は待たない）。済むまで少し待つ。
      String? stored;
      for (var i = 0; i < 50 && stored == null; i++) {
        await Future<void>.delayed(Duration.zero);
        stored = await store.resolveStart(
          explicit: false,
          appVersion: '1.0.0+1',
        );
      }
      expect(stored, _n);
    });

    test('Remote Config で variant が明示されていれば自動切り替えなし', () {
      for (final variant in [
        'live_s_int8',
        'live_n_int8',
        'live_n480_int8',
        'int8',
      ]) {
        final c = container(ModelConfig.fromVariants(liveVariant: variant));
        expect(c.read(liveModelTieringProvider), isNull, reason: variant);
      }
    });

    test('未知の variant は無視されるので自動切り替えあり', () {
      final c = container(ModelConfig.fromVariants(liveVariant: 'huge'));
      expect(c.read(liveModelTieringProvider), isNotNull);
    });
  });
}
