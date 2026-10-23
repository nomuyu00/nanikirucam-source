import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/live/live_detector.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';
import 'package:nanikiru_cam/ml/live_inference_worker.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

class _FakeWorker implements LiveInferenceWorker {
  _FakeWorker(this.asset);

  final String asset;
  bool closed = false;
  int detects = 0;

  @override
  bool get isAlive => !closed;

  @override
  Future<LiveDetections> detect(LiveFrame frame, {required int quarterTurns}) {
    detects++;
    return Future.value(const LiveDetections(tiles: [], luminance: 0.5));
  }

  @override
  Future<void> close() async => closed = true;
}

const _frame = LiveFrame(
  width: 2,
  height: 2,
  format: LiveFrameFormat.bgra8888,
  planes: [],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TfliteLiveDetector のモデル読み込み', () {
    test('既定は YOLO11s。読み込めればそのモデルで動く', () async {
      final tried = <String>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          tried.add(asset);
          expect(labels, hasLength(38));
          return _FakeWorker(asset);
        },
      );
      expect(detector.isReady, isFalse);
      expect(detector.activeModel, isNull);
      await detector.load();
      expect(detector.isReady, isTrue);
      expect(tried, [ModelConfig.liveSInt8Model]);
      expect(detector.activeModel, ModelConfig.liveSInt8Model);
      expect(detector.fallbackFrom, isNull);
      expect(detector.modelLabel, 'mahjong_yolo_live_s_int8');
      await detector.dispose();
    });

    test('ライブ用モデルのアセットが無ければ写真用の int8 に切り替えて続ける', () async {
      final tried = <String>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          tried.add(asset);
          if (asset == ModelConfig.liveSInt8Model) {
            throw StateError('Unable to load asset: $asset');
          }
          return _FakeWorker(asset);
        },
      );
      await detector.load();
      expect(detector.isReady, isTrue);
      expect(tried, [ModelConfig.liveSInt8Model, ModelConfig.int8Model]);
      expect(detector.activeModel, ModelConfig.int8Model);
      expect(detector.fallbackFrom, ModelConfig.liveSInt8Model);
      expect(detector.modelLabel, 'mahjong_yolo_int8 (fallback)');
      // 切り替えたあとも推論できる。
      final result = await detector.detect(_frame, quarterTurns: 0);
      expect(result.tiles, isEmpty);
      await detector.dispose();
    });

    test('Remote Config の variant が不正でも既定の s → 写真用 int8 の順に試す', () async {
      final tried = <String>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.fromVariants(liveVariant: 'live_xl_int8'),
        openWorker: (asset, labels, inference) async {
          tried.add(asset);
          throw StateError('broken: $asset');
        },
      );
      await expectLater(detector.load(), throwsStateError);
      expect(tried, [ModelConfig.liveSInt8Model, ModelConfig.int8Model]);
      expect(detector.isReady, isFalse);
      expect(detector.activeModel, isNull);
      await detector.dispose();
    });

    test('写真用の int8 を指定したときは 1 回だけ試す', () async {
      final tried = <String>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.fromVariants(liveVariant: 'int8'),
        openWorker: (asset, labels, inference) async {
          tried.add(asset);
          throw StateError('broken');
        },
      );
      await expectLater(detector.load(), throwsStateError);
      expect(tried, [ModelConfig.int8Model]);
      await detector.dispose();
    });

    test('読み込み中に dispose されたら、開けたワーカーを閉じる', () async {
      _FakeWorker? opened;
      late TfliteLiveDetector detector;
      detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          await detector.dispose();
          return opened = _FakeWorker(asset);
        },
      );
      await detector.load();
      expect(opened?.closed, isTrue);
      expect(detector.isReady, isFalse);
    });
  });

  group('保存した段から始める', () {
    Future<List<String>> loadWith(
      ModelConfig config,
      Future<String?> Function()? stored,
    ) async {
      final tried = <String>[];
      final detector = TfliteLiveDetector(
        config: config,
        storedTier: stored,
        openWorker: (asset, labels, inference) async {
          tried.add(asset);
          return _FakeWorker(asset);
        },
      );
      await detector.load();
      await detector.dispose();
      return tried;
    }

    test('前回 n に落ちていたら n から始める', () async {
      expect(
        await loadWith(
          ModelConfig.defaults,
          () async => ModelConfig.liveNInt8Model,
        ),
        [ModelConfig.liveNInt8Model],
      );
      expect(
        await loadWith(
          ModelConfig.defaults,
          () async => ModelConfig.liveN480Int8Model,
        ),
        [ModelConfig.liveN480Int8Model],
      );
    });

    test('保存がない・段にない値なら既定の s', () async {
      expect(await loadWith(ModelConfig.defaults, () async => null), [
        ModelConfig.liveSInt8Model,
      ]);
      expect(await loadWith(ModelConfig.defaults, () async => 'bogus'), [
        ModelConfig.liveSInt8Model,
      ]);
      expect(await loadWith(ModelConfig.defaults, null), [
        ModelConfig.liveSInt8Model,
      ]);
    });

    test('保存の読み出しに失敗しても既定の s で始める', () async {
      expect(
        await loadWith(ModelConfig.defaults, () async {
          throw StateError('prefs unavailable');
        }),
        [ModelConfig.liveSInt8Model],
      );
    });

    test('Remote Config で variant が明示されていれば、保存した段は使わない', () async {
      expect(
        await loadWith(
          ModelConfig.fromVariants(liveVariant: 'live_s_int8'),
          () async => ModelConfig.liveN480Int8Model,
        ),
        [ModelConfig.liveSInt8Model],
      );
    });
  });

  group('switchModel（自動切り替え）', () {
    test('新しいモデルを開いてから差し替え、古いワーカーを閉じる', () async {
      final workers = <_FakeWorker>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          expect(labels, hasLength(38));
          final w = _FakeWorker(asset);
          workers.add(w);
          return w;
        },
      );
      await detector.load();
      expect(await detector.switchModel(ModelConfig.liveNInt8Model), isTrue);
      expect(workers.map((w) => w.asset), [
        ModelConfig.liveSInt8Model,
        ModelConfig.liveNInt8Model,
      ]);
      expect(workers[0].closed, isTrue);
      expect(workers[1].closed, isFalse);
      expect(detector.activeModel, ModelConfig.liveNInt8Model);
      expect(detector.modelLabel, 'mahjong_yolo_live_n_int8');
      expect(detector.isReady, isTrue);
      await detector.detect(_frame, quarterTurns: 0);
      expect(workers[1].detects, 1);
      expect(workers[0].detects, 0);
      await detector.dispose();
    });

    test('新しいモデルが開けなければ今のモデルのまま false', () async {
      final workers = <_FakeWorker>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          if (asset == ModelConfig.liveNInt8Model) {
            throw StateError('Unable to load asset');
          }
          final w = _FakeWorker(asset);
          workers.add(w);
          return w;
        },
      );
      await detector.load();
      expect(await detector.switchModel(ModelConfig.liveNInt8Model), isFalse);
      expect(detector.activeModel, ModelConfig.liveSInt8Model);
      expect(workers.single.closed, isFalse);
      expect(detector.isReady, isTrue);
      await detector.dispose();
    });

    test('読み込み前・同じモデル・dispose 後は何もしない', () async {
      final workers = <_FakeWorker>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          final w = _FakeWorker(asset);
          workers.add(w);
          return w;
        },
      );
      expect(await detector.switchModel(ModelConfig.liveNInt8Model), isFalse);
      expect(workers, isEmpty);
      await detector.load();
      expect(await detector.switchModel(ModelConfig.liveSInt8Model), isFalse);
      expect(workers, hasLength(1));
      await detector.dispose();
      expect(await detector.switchModel(ModelConfig.liveNInt8Model), isFalse);
      expect(workers, hasLength(1));
    });

    test('開いている間に dispose されたら、開けたワーカーを閉じる', () async {
      final gate = Completer<void>();
      final workers = <_FakeWorker>[];
      final detector = TfliteLiveDetector(
        config: ModelConfig.defaults,
        openWorker: (asset, labels, inference) async {
          if (workers.isNotEmpty) await gate.future;
          final w = _FakeWorker(asset);
          workers.add(w);
          return w;
        },
      );
      await detector.load();
      final switching = detector.switchModel(ModelConfig.liveNInt8Model);
      await detector.dispose();
      gate.complete();
      expect(await switching, isFalse);
      expect(workers.every((w) => w.closed), isTrue);
    });
  });
}
