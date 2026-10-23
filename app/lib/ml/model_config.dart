import 'package:equatable/equatable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 推論モデルとしきい値の設定（設計書 3.4）。
///
/// Remote Config の `photo_model_variant`, `live_model_variant`, `score_threshold`,
/// `live_target_fps` は [ModelConfig.fromVariants] で組み立てて [modelConfigProvider] に入れる
/// （`lib/core/remote_config.dart`）。
class ModelConfig extends Equatable {
  const ModelConfig({
    this.photoModels = defaultPhotoModels,
    this.liveModel = defaultLiveModel,
    this.liveModelExplicit = false,
    this.labelsAsset = defaultLabelsAsset,
    this.scoreThreshold = defaultScoreThreshold,
    this.liveTargetFps = defaultLiveTargetFps,
  });

  static const String modelsDir = 'assets/models';
  static const String defaultLabelsAsset = 'assets/labels/tiles_labels.txt';
  static const String fp32Model = '$modelsDir/mahjong_yolo_fp32.tflite';
  static const String int8Model = '$modelsDir/mahjong_yolo_int8.tflite';

  /// ライブ用の軽量モデル（クリーン分割で学習した YOLO11n / YOLO11s、入力 640、
  /// 動的レンジ量子化の int8 重み + float 入出力。出力は写真用と同じ `[1, 42, 8400]`）。
  /// 学習・書き出しは `ml/README_training.md` の「ライブ用モデル」。
  static const String liveNInt8Model =
      '$modelsDir/mahjong_yolo_live_n_int8.tflite';
  static const String liveSInt8Model =
      '$modelsDir/mahjong_yolo_live_s_int8.tflite';

  /// YOLO11n を入力 480 で学習・書き出したもの（出力は `[1, 42, 4725]`）。n の 640 より約 1.8 倍
  /// 速いが、小さい牌は取りこぼしやすい。入力の大きさは `LiveInferenceConfig` が
  /// モデルの入力形状から読む。
  static const String liveN480Int8Model =
      '$modelsDir/mahjong_yolo_live_n480_int8.tflite';

  /// ライブの自動切り替えの段（精度が高く遅い順）。遅い端末では 1 段ずつ右へ落ち、戻さない
  /// （`lib/live/live_model_tier.dart`）。
  static const List<String> liveTiers = [
    liveSInt8Model,
    liveNInt8Model,
    liveN480Int8Model,
  ];

  /// 写真は精度優先で fp32 を先に試し、失敗したら int8 に落とす（あがりかむと同じ）。
  static const List<String> defaultPhotoModels = [fp32Model, int8Model];

  /// ライブの既定は YOLO11s（int8）。端末が遅ければ自動で n → n 480 に落ちる
  /// （[liveTiers]）。Remote Config の `live_model_variant` で明示すると、そのモデルに固定して
  /// 自動切り替えをしない（`live_n_int8` / `live_n480_int8`、写真用に戻すなら `int8`）。
  static const String defaultLiveModel = liveSInt8Model;
  static const double defaultScoreThreshold = 0.10;
  static const double defaultLiveTargetFps = 5;

  /// 既定の設定。
  static const ModelConfig defaults = ModelConfig();

  /// 写真解析で上から順に読み込みを試すモデル（アセットのパス）。
  final List<String> photoModels;

  /// ライブナビ用のモデル（アセットのパス）。
  final String liveModel;

  /// Remote Config の `live_model_variant` で明示された（既知の名前だった）か。
  /// 明示されていれば運用で固定する意図なので、自動切り替えも保存した段も使わない。
  final bool liveModelExplicit;

  /// ライブで順に読み込みを試すモデル。先頭は [liveModel]（自動切り替えの途中なら、前回端末に保存した
  /// 段 [storedTier]。明示された variant があるときは使わない）。それが読み込めなければ（アセットが無い・
  /// 壊れている）写真用の int8 に落として続ける。
  List<String> liveCandidates({String? storedTier}) {
    final stored = !liveModelExplicit && liveTiers.contains(storedTier)
        ? storedTier
        : null;
    final first = stored ?? liveModel;
    return [first, if (first != int8Model) int8Model];
  }

  final String labelsAsset;

  /// 検出を捨てる確度のしきい値（ここ未満は候補にしない）。
  final double scoreThreshold;

  /// ライブナビの目標 fps（`moving` 中）。
  final double liveTargetFps;

  /// Remote Config の値（`fp32` / `int8` / `live_n_int8` / `live_s_int8` / `live_n480_int8`）から
  /// アセットのパスを決める。
  /// 未知の名前や null は無視して既定値のままにする。
  factory ModelConfig.fromVariants({
    String? photoVariant,
    String? liveVariant,
    double? scoreThreshold,
    double? liveTargetFps,
  }) {
    // 写真用は fp32 / int8 だけ受け付ける（ライブ用の名前が紛れ込んでも無視する）。
    final photoAsset = assetForVariant(photoVariant);
    final photo = photoAsset == fp32Model || photoAsset == int8Model
        ? photoAsset
        : null;
    final live = assetForVariant(liveVariant);
    return ModelConfig(
      photoModels: photo == null
          ? defaultPhotoModels
          : [photo, ...defaultPhotoModels.where((m) => m != photo)],
      liveModel: live ?? defaultLiveModel,
      liveModelExplicit: live != null,
      scoreThreshold: scoreThreshold != null && scoreThreshold > 0
          ? scoreThreshold
          : defaultScoreThreshold,
      liveTargetFps: liveTargetFps != null && liveTargetFps > 0
          ? liveTargetFps
          : defaultLiveTargetFps,
    );
  }

  /// バリアント名 → アセットのパス。未知なら null。
  ///
  /// `fp32` / `int8` は写真用（ライブに指定すると従来どおり写真用で動く）。
  /// `live_int8` は `live_n_int8` の別名（旧名）。
  static String? assetForVariant(String? variant) => switch (variant) {
    'fp32' => fp32Model,
    'int8' => int8Model,
    'live_n_int8' || 'live_int8' => liveNInt8Model,
    'live_s_int8' => liveSInt8Model,
    'live_n480_int8' => liveN480Int8Model,
    _ => null,
  };

  @override
  List<Object?> get props => [
    photoModels,
    liveModel,
    liveModelExplicit,
    labelsAsset,
    scoreThreshold,
    liveTargetFps,
  ];
}

/// 現在のモデル設定。Remote Config 連携ではここへ代入する。
final modelConfigProvider = StateProvider<ModelConfig>(
  (ref) => ModelConfig.defaults,
);
