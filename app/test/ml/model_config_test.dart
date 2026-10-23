import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

void main() {
  group('ModelConfig のライブ用モデル', () {
    test('既定は YOLO11s（int8）。自動切り替えの段は s → n → n 480', () {
      expect(ModelConfig.defaults.liveModel, ModelConfig.liveSInt8Model);
      expect(ModelConfig.defaults.liveModelExplicit, isFalse);
      expect(ModelConfig.liveTiers, [
        ModelConfig.liveSInt8Model,
        ModelConfig.liveNInt8Model,
        ModelConfig.liveN480Int8Model,
      ]);
      expect(
        ModelConfig.liveNInt8Model,
        'assets/models/mahjong_yolo_live_n_int8.tflite',
      );
      expect(
        ModelConfig.liveSInt8Model,
        'assets/models/mahjong_yolo_live_s_int8.tflite',
      );
      expect(
        ModelConfig.liveN480Int8Model,
        'assets/models/mahjong_yolo_live_n480_int8.tflite',
      );
    });

    test('live_model_variant で n / s / 従来の写真用を切り替える', () {
      String live(String? variant) =>
          ModelConfig.fromVariants(liveVariant: variant).liveModel;
      expect(live('live_n_int8'), ModelConfig.liveNInt8Model);
      expect(live('live_s_int8'), ModelConfig.liveSInt8Model);
      expect(live('live_n480_int8'), ModelConfig.liveN480Int8Model);
      expect(live('int8'), ModelConfig.int8Model);
      expect(live('fp32'), ModelConfig.fp32Model);
      // 旧名は n の別名。
      expect(live('live_int8'), ModelConfig.liveNInt8Model);
      // 未知・未指定は既定の s。
      expect(live('live_xl_int8'), ModelConfig.liveSInt8Model);
      expect(live(null), ModelConfig.liveSInt8Model);
    });

    test('variant が明示されたか（明示されたら自動切り替えをしない）', () {
      bool explicit(String? variant) =>
          ModelConfig.fromVariants(liveVariant: variant).liveModelExplicit;
      expect(explicit('live_s_int8'), isTrue);
      expect(explicit('live_n_int8'), isTrue);
      expect(explicit('live_n480_int8'), isTrue);
      expect(explicit('int8'), isTrue);
      expect(explicit('live_xl_int8'), isFalse);
      expect(explicit(null), isFalse);
      // 明示の有無で設定は別物（既定と等しくならない）。
      expect(
        ModelConfig.fromVariants(liveVariant: 'live_s_int8'),
        isNot(ModelConfig.defaults),
      );
    });

    test('photo_model_variant にライブ用の名前が来ても写真用の並びは変えない', () {
      final config = ModelConfig.fromVariants(photoVariant: 'live_s_int8');
      expect(config.photoModels, ModelConfig.defaultPhotoModels);
      final int8First = ModelConfig.fromVariants(photoVariant: 'int8');
      expect(int8First.photoModels, [
        ModelConfig.int8Model,
        ModelConfig.fp32Model,
      ]);
    });
  });
}
