import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/live_model_loader.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

void main() {
  group('openFirstLiveModel', () {
    test('先頭が開ければそのまま使い、控えは試さない', () async {
      final tried = <String>[];
      final opening = await openFirstLiveModel<String>(['a', 'b'], (asset) async {
        tried.add(asset);
        return 'worker-$asset';
      });
      expect(opening.value, 'worker-a');
      expect(opening.asset, 'a');
      expect(opening.usedFallback, isFalse);
      expect(opening.failures, isEmpty);
      expect(tried, ['a']);
    });

    test('先頭が開けなければ（アセット無し・壊れている）次の候補に切り替える', () async {
      final opening = await openFirstLiveModel<String>(['live_n', 'photo'], (
        asset,
      ) async {
        if (asset == 'live_n') throw StateError('Unable to load asset');
        return 'worker-$asset';
      });
      expect(opening.value, 'worker-photo');
      expect(opening.asset, 'photo');
      expect(opening.usedFallback, isTrue);
      expect(opening.failures.single.asset, 'live_n');
      expect(opening.failures.single.error, isA<StateError>());
    });

    test('全部だめなら、理由を並べて投げる', () async {
      await expectLater(
        openFirstLiveModel<String>(['a', 'b'], (asset) async {
          throw StateError('bad $asset');
        }),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('a:'), contains('b:'), contains('bad a')),
          ),
        ),
      );
    });
  });

  group('liveModelLabel', () {
    test('アセットのパス → 拡張子なしの名前', () {
      expect(
        liveModelLabel(ModelConfig.liveNInt8Model),
        'mahjong_yolo_live_n_int8',
      );
      expect(liveModelLabel(ModelConfig.int8Model), 'mahjong_yolo_int8');
      expect(liveModelLabel('model'), 'model');
    });
  });

  group('ModelConfig.liveCandidates', () {
    test('ライブ用モデルの次に写真用の int8 を試す', () {
      expect(ModelConfig.defaults.liveCandidates(), [
        ModelConfig.liveSInt8Model,
        ModelConfig.int8Model,
      ]);
      expect(
        ModelConfig.fromVariants(liveVariant: 'live_n_int8').liveCandidates(),
        [ModelConfig.liveNInt8Model, ModelConfig.int8Model],
      );
    });

    test('写真用の int8 が先頭なら重ねない', () {
      expect(ModelConfig.fromVariants(liveVariant: 'int8').liveCandidates(), [
        ModelConfig.int8Model,
      ]);
    });

    test('fp32 を指定しても最後は写真用の int8', () {
      expect(ModelConfig.fromVariants(liveVariant: 'fp32').liveCandidates(), [
        ModelConfig.fp32Model,
        ModelConfig.int8Model,
      ]);
    });

    test('保存した段があれば、そこから始める（先頭の候補を置き換える）', () {
      expect(
        ModelConfig.defaults.liveCandidates(
          storedTier: ModelConfig.liveNInt8Model,
        ),
        [ModelConfig.liveNInt8Model, ModelConfig.int8Model],
      );
      expect(
        ModelConfig.defaults.liveCandidates(
          storedTier: ModelConfig.liveN480Int8Model,
        ),
        [ModelConfig.liveN480Int8Model, ModelConfig.int8Model],
      );
    });

    test('段にないもの・壊れた値は使わない', () {
      for (final stored in [ModelConfig.int8Model, 'bogus', '', null]) {
        expect(ModelConfig.defaults.liveCandidates(storedTier: stored), [
          ModelConfig.liveSInt8Model,
          ModelConfig.int8Model,
        ]);
      }
    });

    test('variant が明示されていれば、保存した段は無視する', () {
      expect(
        ModelConfig.fromVariants(liveVariant: 'live_s_int8').liveCandidates(
          storedTier: ModelConfig.liveN480Int8Model,
        ),
        [ModelConfig.liveSInt8Model, ModelConfig.int8Model],
      );
    });
  });
}
