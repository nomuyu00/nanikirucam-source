// 流用元: reference/agari_cam/lib/ml/tflite_service.dart（2026-10-21 時点）
// 改修（設計書 3.2）: モデルのアセット名・しきい値を ModelConfig で切り替え可能にした。
// 打ち切り条件を「13 または 14 枚で全牌の確度が閾値以上」に変更（和了形の判定はしない）。
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:nanikiru_cam/ml/nms.dart';
import 'package:nanikiru_cam/ml/reshape.dart';
import 'package:nanikiru_cam/ml/tile_selection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

class TileDetection {
  final Rect box;
  final String label;
  final double score;
  final bool isRed;
  // 2番目に確からしい牌（修正候補として先頭に出す）。
  final String? alternative;
  final double alternativeScore;
  TileDetection({
    required this.box,
    required this.label,
    required this.score,
    this.isRed = false,
    this.alternative,
    this.alternativeScore = 0,
  });

  TileDetection withBox(Rect next) => TileDetection(
    box: next,
    label: label,
    score: score,
    isRed: isRed,
    alternative: alternative,
    alternativeScore: alternativeScore,
  );
}

/// 推論入力として描いた画像と、入力座標を写真の座標に戻す情報。
class RenderedRegion {
  const RenderedRegion({
    required this.rgba,
    required this.padLeft,
    required this.padTop,
    required this.scale,
    required this.source,
    required this.rotatedWidth,
    required this.rotatedHeight,
  });

  final Uint8List rgba;
  final double padLeft;
  final double padTop;
  final double scale;
  // 回転後画像のピクセル座標で、入力に描いた範囲。
  final Rect source;
  final double rotatedWidth;
  final double rotatedHeight;

  /// 640入力上の枠 → 回転後画像全体に対する 0〜1 の枠。
  Rect? toImageRect(Rect inputBox) {
    double x(double v) => ((v - padLeft) / scale + source.left) / rotatedWidth;
    double y(double v) => ((v - padTop) / scale + source.top) / rotatedHeight;
    final rect = Rect.fromLTRB(
      x(inputBox.left).clamp(0.0, 1.0),
      y(inputBox.top).clamp(0.0, 1.0),
      x(inputBox.right).clamp(0.0, 1.0),
      y(inputBox.bottom).clamp(0.0, 1.0),
    );
    if (rect.width <= 0 || rect.height <= 0) return null;
    return rect;
  }
}

/// 1枚の写真から選んだ手牌と、表示用の情報。
class RecognitionOutcome {
  const RecognitionOutcome({
    required this.selection,
    required this.quarterTurns,
    required this.strategy,
    required this.inferenceCount,
  });

  /// [selection] の枠は、写真を [quarterTurns] 回（時計回り90°）回した画像に対する 0〜1 の座標。
  final SelectedTiles selection;
  final int quarterTurns;
  // 'full' = 画像全体を1回で推論 / 'tiled' = 手牌の列を2分割して拡大推論
  final String strategy;
  final int inferenceCount;
}

class ImageDetectionVariant {
  const ImageDetectionVariant({
    required this.strategy,
    required this.width,
    required this.height,
    required this.detections,
  });

  final String strategy;
  final int width;
  final int height;
  final List<TileDetection> detections;
}

class _ImageTransform {
  const _ImageTransform({
    required this.srcWidth,
    required this.srcHeight,
    required this.scaledWidth,
    required this.scaledHeight,
    required this.padLeft,
    required this.padTop,
  });

  final int srcWidth;
  final int srcHeight;
  final int scaledWidth;
  final int scaledHeight;
  final int padLeft;
  final int padTop;

  double get scaleX => scaledWidth / srcWidth;
  double get scaleY => scaledHeight / srcHeight;
}

class _PreprocessedImage {
  const _PreprocessedImage({required this.rgba, required this.transform});

  final Uint8List rgba;
  final _ImageTransform transform;
}

class _ImageVariantSpec {
  const _ImageVariantSpec({
    required this.strategy,
    required this.source,
    required this.quarterTurns,
  });

  final String strategy;
  final Rect source;
  final int quarterTurns;
}

class _RenderedImageVariant {
  const _RenderedImageVariant({
    required this.strategy,
    required this.rgba,
    required this.width,
    required this.height,
  });

  final String strategy;
  final Uint8List rgba;
  final int width;
  final int height;
}

class TfliteService extends ChangeNotifier {
  TfliteService({this.config = ModelConfig.defaults})
    : _loadLabels = (() => rootBundle.loadString(config.labelsAsset)),
      _createOptions = tfl.InterpreterOptions.new,
      _createMetalDelegate = tfl.GpuDelegate.new,
      _openModel = _openBundledModel;

  @visibleForTesting
  TfliteService.withRuntime({
    this.config = ModelConfig.defaults,
    required this._loadLabels,
    required this._createOptions,
    required this._createMetalDelegate,
    required this._openModel,
  });

  /// モデルのアセット名としきい値。Remote Config で差し替える（[modelConfigProvider]）。
  final ModelConfig config;

  // Model export shows fixed [1,640,640,3] input and [1,42,8400] output.
  // Keep input at 640 to match anchor layout (8400=80*80+40*40+20*20).
  static const int _inputSize = 640;

  /// 同梱モデルの版（分析で精度の推移を比べるため）。
  static const String modelVersion = 'v1';
  final Future<String> Function() _loadLabels;
  final tfl.InterpreterOptions Function() _createOptions;
  final tfl.Delegate Function() _createMetalDelegate;
  final Future<tfl.Interpreter> Function(
    String asset,
    tfl.InterpreterOptions options,
    bool fromFile,
  )
  _openModel;
  tfl.Interpreter? _interpreter;
  tfl.Delegate? _delegate;
  tfl.IsolateInterpreter? _isolateInterpreter;
  Future<void>? _initializing;
  bool _disposed = false;
  bool _available = false;
  List<String> _labels = const [];
  String? lastError;

  bool get isAvailable => _available;
  List<String> get labelsList => _labels;

  Future<void> ensureInitialized() {
    if (_disposed || _available) return Future<void>.value();
    return _initializing ??= _initialize().whenComplete(() {
      _initializing = null;
    });
  }

  Future<void> _initialize() async {
    lastError = null;
    try {
      final raw = await _loadLabels();
      if (_disposed) return;
      _labels = raw
          .split(RegExp(r'\r?\n'))
          .where((e) => e.trim().isNotEmpty)
          .toList();

      // Accuracy first: prefer FP32 on every platform, then fall back to the
      // lighter model if memory/delegate initialization fails.
      final models = config.photoModels;
      for (int attempt = 0; attempt < 3; attempt++) {
        for (final m in models) {
          // Create the delegate inside the attempt so even delegate creation
          // errors can fall back to CPU inference using the same FP32 model.
          final useMetalOptions = <bool>[
            if (defaultTargetPlatform == TargetPlatform.iOS &&
                !m.contains('int8'))
              true,
            false,
          ];
          for (final useMetal in useMetalOptions) {
            if (_disposed) return;
            try {
              await _tryLoadModel(m, useMetal: useMetal);
              if (_disposed) return;
              lastError = null;
              notifyListeners();
              return;
            } catch (e) {
              lastError = e.toString();
            }
          }
        }
        if (attempt < 2 && !_disposed) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      throw StateError('Interpreter load failed: $lastError');
    } catch (e) {
      _available = false;
      lastError = e.toString();
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _tryLoadModel(String asset, {required bool useMetal}) async {
    final options = _createOptions();
    tfl.Delegate? delegate;
    try {
      options.threads = useMetal ? 2 : 4;
      if (useMetal) {
        delegate = _createMetalDelegate();
        if (delegate.base.address == 0) {
          throw StateError('Metal delegate creation failed');
        }
        options.addDelegate(delegate);
      }

      Object? loadError;
      // Preserve the platform-specific asset/file fallback order. fromAsset
      // loads a byte buffer in tflite_flutter; it does not memory-map the file.
      final fromFileOptions = defaultTargetPlatform == TargetPlatform.iOS
          ? const [false, true]
          : const [true, false];
      for (final fromFile in fromFileOptions) {
        tfl.Interpreter? candidate;
        try {
          candidate = await _openModel(asset, options, fromFile);
          if (_disposed) return;
          final shape = candidate.getInputTensor(0).shape;
          if (!listEquals(shape, const [1, _inputSize, _inputSize, 3])) {
            candidate.resizeInputTensor(0, [1, _inputSize, _inputSize, 3]);
          }
          candidate.allocateTensors();

          // Publish only a fully allocated interpreter. Keep its delegate
          // alive until after the interpreter has been closed.
          _interpreter = candidate;
          candidate = null;
          _delegate = delegate;
          delegate = null;
          _available = true;
          return;
        } catch (e) {
          loadError = e;
        } finally {
          candidate?.close();
        }
      }
      throw StateError('Unable to load $asset: $loadError');
    } finally {
      // TfLiteInterpreterCreate copies options; delegates remain caller-owned.
      try {
        options.delete();
      } finally {
        delegate?.delete();
      }
    }
  }

  static Future<tfl.Interpreter> _openBundledModel(
    String asset,
    tfl.InterpreterOptions options,
    bool fromFile,
  ) async {
    if (!fromFile) {
      return tfl.Interpreter.fromAsset(asset, options: options);
    }
    final data = await rootBundle.load(asset);
    final directory = await getTemporaryDirectory();
    final mlDirectory = Directory('${directory.path}/ml');
    await mlDirectory.create(recursive: true);
    final file = File('${mlDirectory.path}/${asset.split('/').last}');
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    if (!await file.exists() || await file.length() != bytes.length) {
      await file.writeAsBytes(bytes, flush: true);
    }
    return tfl.Interpreter.fromFile(file, options: options);
  }

  @override
  void dispose() {
    _disposed = true;
    _available = false;
    final interpreter = _interpreter;
    final delegate = _delegate;
    final isolate = _isolateInterpreter;
    _interpreter = null;
    _delegate = null;
    _isolateInterpreter = null;
    try {
      if (isolate != null) unawaited(isolate.close());
      interpreter?.close();
    } finally {
      try {
        delegate?.delete();
      } finally {
        super.dispose();
      }
    }
  }

  Future<List<TileDetection>> detectRgba(
    Uint8List rgba,
    int width,
    int height,
  ) async {
    if (!_available || _interpreter == null) return [];
    final preprocessed = _letterboxRgba(
      rgba,
      width,
      height,
      _inputSize,
      _inputSize,
    );
    final resized = preprocessed.rgba;
    final inputT = _interpreter!.getInputTensor(0);
    final inputShape = inputT.shape; // [1,H,W,C]
    final inputType = inputT.type.toString().toLowerCase();
    final c = (inputShape.length >= 4) ? inputShape[3] : 3;
    final batch = 1;
    late Object input;
    if (inputType.contains('float32')) {
      // NHWC float32, normalize to 0..1 and drop alpha
      final floats = Float32List(_inputSize * _inputSize * (c == 4 ? 4 : 3));
      if (c == 4) {
        for (int px = 0, i = 0; px < _inputSize * _inputSize; px++, i += 4) {
          floats[i] = resized[i] / 255.0;
          floats[i + 1] = resized[i + 1] / 255.0;
          floats[i + 2] = resized[i + 2] / 255.0;
          floats[i + 3] = 1.0;
        }
        input = floats.reshape([batch, _inputSize, _inputSize, 4]);
      } else {
        for (int px = 0; px < _inputSize * _inputSize; px++) {
          final si = px * 4;
          final di = px * 3;
          floats[di] = resized[si] / 255.0;
          floats[di + 1] = resized[si + 1] / 255.0;
          floats[di + 2] = resized[si + 2] / 255.0;
        }
        input = floats.reshape([batch, _inputSize, _inputSize, 3]);
      }
    } else {
      // Quantized path (uint8/int8). Prefer 3 channels; drop alpha.
      if (inputType.contains('int8')) {
        final ints = Int8List(_inputSize * _inputSize * (c == 4 ? 4 : 3));
        if (c == 4) {
          for (int i = 0; i < _inputSize * _inputSize * 4; i += 4) {
            ints[i] = ((resized[i] - 128).clamp(-128, 127)).toInt();
            ints[i + 1] = ((resized[i + 1] - 128).clamp(-128, 127)).toInt();
            ints[i + 2] = ((resized[i + 2] - 128).clamp(-128, 127)).toInt();
            ints[i + 3] = 127; // opaque alpha
          }
          input = ints.reshape([batch, _inputSize, _inputSize, 4]);
        } else {
          for (int px = 0; px < _inputSize * _inputSize; px++) {
            final si = px * 4;
            final di = px * 3;
            ints[di] = ((resized[si] - 128).clamp(-128, 127)).toInt();
            ints[di + 1] = ((resized[si + 1] - 128).clamp(-128, 127)).toInt();
            ints[di + 2] = ((resized[si + 2] - 128).clamp(-128, 127)).toInt();
          }
          input = ints.reshape([batch, _inputSize, _inputSize, 3]);
        }
      } else {
        final bytes = Uint8List(_inputSize * _inputSize * (c == 4 ? 4 : 3));
        if (c == 4) {
          for (int i = 0; i < _inputSize * _inputSize * 4; i += 4) {
            bytes[i] = resized[i];
            bytes[i + 1] = resized[i + 1];
            bytes[i + 2] = resized[i + 2];
            bytes[i + 3] = 255;
          }
          input = bytes.reshape([batch, _inputSize, _inputSize, 4]);
        } else {
          for (int px = 0; px < _inputSize * _inputSize; px++) {
            final si = px * 4;
            final di = px * 3;
            bytes[di] = resized[si];
            bytes[di + 1] = resized[si + 1];
            bytes[di + 2] = resized[si + 2];
          }
          input = bytes.reshape([batch, _inputSize, _inputSize, 3]);
        }
      }
    }

    // Prepare output buffers; dequantize on demand after run
    final outTensors = _interpreter!.getOutputTensors();
    final outputs = <int, Object>{};
    for (var i = 0; i < outTensors.length; i++) {
      final t = outTensors[i];
      final numEls = t.shape.reduce((a, b) => a * b);
      final isFloatOut = t.type.toString().toLowerCase().contains('float32');
      if (isFloatOut) {
        final buf = Float32List(numEls);
        outputs[i] = buf.reshape(t.shape);
      } else {
        final buf = Uint8List(numEls);
        outputs[i] = buf.reshape(t.shape);
      }
    }

    _interpreter!.runForMultipleInputs([input], outputs);

    // Try to decode from fused or split heads
    return _decodeFromOutputs(outTensors, outputs, preprocessed.transform);
  }

  // Detect from image bytes (e.g., captured JPEG). Decodes to RGBA then runs.
  Future<List<TileDetection>> detectImageBytes(Uint8List bytes) async {
    if (!_available) await ensureInitialized();
    if (!_available || _interpreter == null) return [];
    final img = await _decodeUiImage(bytes);
    try {
      final bd = await img.toByteData(format: ImageByteFormat.rawRgba);
      if (bd == null) return [];
      final rgba = Uint8List.view(
        bd.buffer,
        bd.offsetInBytes,
        bd.lengthInBytes,
      );
      return detectRgba(rgba, img.width, img.height);
    } finally {
      img.dispose();
    }
  }

  Future<List<ImageDetectionVariant>> detectImageByteVariants(
    Uint8List bytes,
  ) async {
    if (!_available) await ensureInitialized();
    if (!_available || _interpreter == null) return const [];
    final img = await _decodeUiImage(bytes);
    try {
      final variants = <ImageDetectionVariant>[];
      final specs = _imageVariantSpecs(img.width, img.height);
      for (final spec in specs) {
        final rendered = await _renderImageVariant(img, spec);
        final detections = rendered.rgba.isEmpty
            ? <TileDetection>[]
            : await detectRgba(rendered.rgba, rendered.width, rendered.height);
        variants.add(
          ImageDetectionVariant(
            strategy: rendered.strategy,
            width: rendered.width,
            height: rendered.height,
            detections: detections,
          ),
        );
      }
      return variants;
    } finally {
      img.dispose();
    }
  }

  Future<Image> _decodeUiImage(Uint8List bytes) async {
    final codec = await instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  List<_ImageVariantSpec> _imageVariantSpecs(int width, int height) {
    final full = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final horizontalBand = _centerCropRect(
      width,
      height,
      widthFactor: 0.98,
      heightFactor: 0.58,
    );
    final verticalBand = _centerCropRect(
      width,
      height,
      widthFactor: 0.58,
      heightFactor: 0.98,
    );

    return [
      _ImageVariantSpec(strategy: 'full', source: full, quarterTurns: 0),
      _ImageVariantSpec(
        strategy: 'row-crop',
        source: horizontalBand,
        quarterTurns: 0,
      ),
      _ImageVariantSpec(strategy: 'rotate-90', source: full, quarterTurns: 1),
      _ImageVariantSpec(
        strategy: 'rotate-90-row-crop',
        source: verticalBand,
        quarterTurns: 1,
      ),
      _ImageVariantSpec(strategy: 'rotate-270', source: full, quarterTurns: 3),
      _ImageVariantSpec(
        strategy: 'rotate-270-row-crop',
        source: verticalBand,
        quarterTurns: 3,
      ),
      _ImageVariantSpec(strategy: 'rotate-180', source: full, quarterTurns: 2),
      _ImageVariantSpec(
        strategy: 'rotate-180-row-crop',
        source: horizontalBand,
        quarterTurns: 2,
      ),
    ];
  }

  Rect _centerCropRect(
    int width,
    int height, {
    required double widthFactor,
    required double heightFactor,
  }) {
    final cropWidth = math.max(1.0, width * widthFactor);
    final cropHeight = math.max(1.0, height * heightFactor);
    final left = (width - cropWidth) / 2;
    final top = (height - cropHeight) / 2;
    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  Future<_RenderedImageVariant> _renderImageVariant(
    Image image,
    _ImageVariantSpec spec,
  ) async {
    final q = spec.quarterTurns % 4;
    final sourceWidth = math.max(1, spec.source.width.round());
    final sourceHeight = math.max(1, spec.source.height.round());
    final rotated = q == 1 || q == 3;
    final outWidth = rotated ? sourceHeight : sourceWidth;
    final outHeight = rotated ? sourceWidth : sourceHeight;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..filterQuality = FilterQuality.high;
    switch (q) {
      case 1:
        canvas.translate(outWidth.toDouble(), 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2:
        canvas.translate(outWidth.toDouble(), outHeight.toDouble());
        canvas.rotate(math.pi);
        break;
      case 3:
        canvas.translate(0, outHeight.toDouble());
        canvas.rotate(-math.pi / 2);
        break;
      case 0:
      default:
        break;
    }
    canvas.drawImageRect(
      image,
      spec.source,
      Rect.fromLTWH(0, 0, sourceWidth.toDouble(), sourceHeight.toDouble()),
      paint,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(outWidth, outHeight);
    picture.dispose();
    try {
      final bd = await rendered.toByteData(format: ImageByteFormat.rawRgba);
      final rgba = bd == null
          ? Uint8List(0)
          : Uint8List.fromList(
              Uint8List.view(bd.buffer, bd.offsetInBytes, bd.lengthInBytes),
            );
      return _RenderedImageVariant(
        strategy: spec.strategy,
        rgba: rgba,
        width: outWidth,
        height: outHeight,
      );
    } finally {
      rendered.dispose();
    }
  }

  // --- 認識パイプライン（v1.2） --------------------------------------------
  //
  // 1. 写真を回転させながら全体を1回ずつ推論し、和了形かつ確度が高ければ打ち切る。
  // 2. 一番良かった向きで、手牌の列を左右2つに分けて拡大推論する（牌の画素が約2倍）。
  // 3. 2つの結果を統合し、良い方を採用する。
  // 縮小はGPUのキャンバスで行う（学習時と同じバイリニア）。

  @visibleForTesting
  static bool debugSkipTiledPass = false;

  /// 打ち切りの条件: 13/14 枚で全牌の確度がこの値以上、かつ平均が [_earlyExitScore] 以上。
  static const double _earlyExitTileScore = 0.6;
  static const double _earlyExitScore = 0.72;
  // 撮影ガイドは90°回して表示しているので、写真は反時計回りに90°回すと正立する
  // ことが多い（以前の共有画像も-90°補正していた）。その後、残りの向きを試す。
  static const List<int> _orientationOrder = [3, 1, 0, 2];

  Future<RecognitionOutcome?> recognize(
    Uint8List bytes, {
    TileSelectionEngine? engine,
  }) async {
    if (!_available) await ensureInitialized();
    if (!_available || _interpreter == null) return null;
    final selector = engine ?? TileSelectionEngine();
    final image = await _decodeUiImage(bytes);
    var inferences = 0;
    try {
      _Attempt? best;
      for (final q in _orientationOrder) {
        final detections = await _detectRegion(
          image,
          q,
          const Rect.fromLTWH(0, 0, 1, 1),
        );
        inferences++;
        final selection = selector.selectBest(detections);
        final attempt = _Attempt(selection, q, 'full');
        if (best == null || attempt.isBetterThan(best)) best = attempt;
        // 13 または 14 枚で全牌の確度が閾値以上なら、残りの向きは試さない。
        if (selection.isConfident(_earlyExitTileScore) &&
            selection.averageScore >= _earlyExitScore) {
          break;
        }
      }
      if (best == null || best.selection.detections.isEmpty) {
        return best == null
            ? null
            : RecognitionOutcome(
                selection: best.selection,
                quarterTurns: best.quarterTurns,
                strategy: best.strategy,
                inferenceCount: inferences,
              );
      }

      // 13/14 枚で全牌の確度が高ければ、拡大推論は省く（推論2回分速くなる）。
      final confident =
          best.selection.isConfident(_earlyExitTileScore) &&
          best.selection.averageScore >= 0.85;
      final row = debugSkipTiledPass || confident
          ? null
          : _rowRegion(best.selection.detections);
      if (row != null) {
        // 位置は全体推論のものを使い、拡大推論は確度の高い牌の種類の確認だけに使う。
        // （分割の境目で切れた牌を二重に数えると、別の牌が落ちるため）
        final halfWidth = row.width * 0.56;
        final halves = [
          Rect.fromLTWH(row.left, row.top, halfWidth, row.height),
          Rect.fromLTWH(row.right - halfWidth, row.top, halfWidth, row.height),
        ];
        final zoomed = <TileDetection>[];
        for (var i = 0; i < halves.length; i++) {
          final half = halves[i];
          final margin = _medianWidth(best.selection.detections) * 0.25;
          for (final d in await _detectRegion(image, best.quarterTurns, half)) {
            final cutAtRight = i == 0 && d.box.right > half.right - margin;
            final cutAtLeft = i == 1 && d.box.left < half.left + margin;
            if (!cutAtRight && !cutAtLeft) zoomed.add(d);
          }
          inferences++;
        }
        final refined = _refineLabels(best.selection.detections, zoomed);
        if (refined != null) {
          final candidate = _Attempt(
            selector.selectBest(refined),
            best.quarterTurns,
            'tiled',
          );
          // 完成していた（13/14 枚）選択を、完成していない選択にする修正は採らない。
          if (!(best.selection.isComplete && !candidate.selection.isComplete) &&
              candidate.selection.detections.length ==
                  best.selection.detections.length) {
            best = candidate;
          }
        }
      }
      return RecognitionOutcome(
        selection: best.selection,
        quarterTurns: best.quarterTurns,
        strategy: best.strategy,
        inferenceCount: inferences,
      );
    } finally {
      image.dispose();
    }
  }

  /// 選ばれた牌の列を囲む領域（回転後画像の 0〜1）。列が画像に対して十分大きいときだけ返す。
  Rect? _rowRegion(List<TileDetection> detections) {
    if (detections.length < 6) return null;
    var left = 1.0, top = 1.0, right = 0.0, bottom = 0.0;
    final widths = <double>[];
    final heights = <double>[];
    for (final d in detections) {
      left = math.min(left, d.box.left);
      top = math.min(top, d.box.top);
      right = math.max(right, d.box.right);
      bottom = math.max(bottom, d.box.bottom);
      widths.add(d.box.width);
      heights.add(d.box.height);
    }
    widths.sort();
    heights.sort();
    final w = widths[widths.length ~/ 2];
    final h = heights[heights.length ~/ 2];
    final region = Rect.fromLTRB(
      (left - w).clamp(0.0, 1.0),
      (top - h * 0.8).clamp(0.0, 1.0),
      (right + w).clamp(0.0, 1.0),
      (bottom + h * 0.8).clamp(0.0, 1.0),
    );
    // 牌が既に十分大きく写っているなら拡大推論は不要。
    if (w * _inputSize >= 60) return null;
    return region.width > 0.1 && region.height > 0.02 ? region : null;
  }

  static double _medianWidth(List<TileDetection> detections) {
    final widths = detections.map((d) => d.box.width).toList()..sort();
    return widths.isEmpty ? 0 : widths[widths.length ~/ 2];
  }

  /// 拡大推論で、同じ位置の牌を明らかに高い確度で別の牌と判定したときだけ置き換える。
  /// 変更がなければ null。
  List<TileDetection>? _refineLabels(
    List<TileDetection> base,
    List<TileDetection> zoomed,
  ) {
    var changed = false;
    final result = <TileDetection>[];
    for (final d in base) {
      TileDetection? match;
      var bestIou = 0.5;
      for (final z in zoomed) {
        final v = _boxIou(d.box, z.box);
        if (v >= bestIou) {
          bestIou = v;
          match = z;
        }
      }
      if (match != null &&
          match.label != d.label &&
          match.score >= d.score + 0.15) {
        changed = true;
        result.add(
          TileDetection(
            box: d.box,
            label: match.label,
            score: match.score,
            alternative: d.label,
            alternativeScore: d.score,
          ),
        );
      } else if (match != null &&
          match.label == d.label &&
          match.score > d.score) {
        result.add(
          TileDetection(
            box: d.box,
            label: d.label,
            score: match.score,
            alternative: d.alternative,
            alternativeScore: d.alternativeScore,
          ),
        );
      } else {
        result.add(d);
      }
    }
    return changed || !_sameScores(base, result) ? result : null;
  }

  static bool _sameScores(List<TileDetection> a, List<TileDetection> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].score != b[i].score) return false;
    }
    return true;
  }

  static double _boxIou(Rect a, Rect b) {
    final inter = a.intersect(b);
    if (inter.width <= 0 || inter.height <= 0) return 0;
    final i = inter.width * inter.height;
    final u = a.width * a.height + b.width * b.height - i;
    return u <= 0 ? 0 : i / u;
  }

  /// 写真を [quarterTurns] 回した画像の [region]（0〜1）を推論し、
  /// 枠を回転後画像全体の 0〜1 座標で返す。
  Future<List<TileDetection>> _detectRegion(
    Image image,
    int quarterTurns,
    Rect region,
  ) async {
    final rendered = await renderRegion(image, quarterTurns, region);
    final raw = await _runFloatModel(rendered.rgba);
    if (raw == null) {
      // 量子化入出力などのモデルは従来の経路で推論する（枠は入力に対する0〜1）。
      final legacy = await detectRgba(rendered.rgba, _inputSize, _inputSize);
      return [
        for (final d in legacy)
          if (rendered.toImageRect(
                Rect.fromLTRB(
                  d.box.left * _inputSize,
                  d.box.top * _inputSize,
                  d.box.right * _inputSize,
                  d.box.bottom * _inputSize,
                ),
              )
              case final box?)
            d.withBox(box),
      ];
    }
    return [
      for (final d in _decodeFloat(raw.$1, raw.$2))
        if (rendered.toImageRect(d.box) case final box?) d.withBox(box),
    ];
  }

  /// 推論入力（640×640 RGBA、114灰色で余白）を描く。
  @visibleForTesting
  Future<RenderedRegion> renderRegion(
    Image image,
    int quarterTurns,
    Rect region,
  ) async {
    final q = quarterTurns % 4;
    final rotatedW = (q.isOdd ? image.height : image.width).toDouble();
    final rotatedH = (q.isOdd ? image.width : image.height).toDouble();
    final src = Rect.fromLTRB(
      region.left * rotatedW,
      region.top * rotatedH,
      region.right * rotatedW,
      region.bottom * rotatedH,
    );
    final scale = math.min(_inputSize / src.width, _inputSize / src.height);
    final scaledW = src.width * scale;
    final scaledH = src.height * scale;
    final padLeft = (_inputSize - scaledW) / 2;
    final padTop = (_inputSize - scaledH) / 2;

    // 学習時（Ultralytics の線形補間）と同じく、バイリニアで1回だけ縮小する。
    // 実モデルでの比較では、ミップマップや段階縮小で滑らかにすると小さな牌の
    // 認識率が下がった（小さな牌72枚: バイリニア100% / 段階縮小93%）。
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _inputSize * 1.0, _inputSize * 1.0),
      Paint()..color = const Color(0xFF727272), // 114 gray (Ultralytics)
    );
    canvas.clipRect(Rect.fromLTWH(padLeft, padTop, scaledW, scaledH));
    canvas.translate(padLeft, padTop);
    canvas.scale(scale);
    canvas.translate(-src.left, -src.top);
    final sw = image.width.toDouble();
    final sh = image.height.toDouble();
    switch (q) {
      case 1:
        canvas.translate(sh, 0);
        canvas.rotate(math.pi / 2);
        break;
      case 2:
        canvas.translate(sw, sh);
        canvas.rotate(math.pi);
        break;
      case 3:
        canvas.translate(0, sw);
        canvas.rotate(-math.pi / 2);
        break;
    }
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.low,
    );
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(_inputSize, _inputSize);
    picture.dispose();
    final bd = await rendered.toByteData(format: ImageByteFormat.rawRgba);
    rendered.dispose();
    return RenderedRegion(
      rgba: bd == null
          ? Uint8List(0)
          : Uint8List.view(bd.buffer, bd.offsetInBytes, bd.lengthInBytes),
      padLeft: padLeft,
      padTop: padTop,
      scale: scale,
      source: src,
      rotatedWidth: rotatedW,
      rotatedHeight: rotatedH,
    );
  }

  /// float32入出力のモデルを実行し、出力をそのまま返す（形状と値）。
  /// CPU推論は別Isolateで行い、画面を止めない。Metal使用時は作成スレッドで実行する。
  Future<(Float32List, List<int>)?> _runFloatModel(Uint8List rgba) async {
    final interpreter = _interpreter;
    if (interpreter == null) return null;
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    if (!inputTensor.type.toString().toLowerCase().contains('float32') ||
        !outputTensor.type.toString().toLowerCase().contains('float32') ||
        interpreter.getOutputTensors().length != 1) {
      return null;
    }
    final input = Float32List(_inputSize * _inputSize * 3);
    for (var px = 0, si = 0, di = 0; px < _inputSize * _inputSize; px++) {
      input[di++] = rgba[si] / 255.0;
      input[di++] = rgba[si + 1] / 255.0;
      input[di++] = rgba[si + 2] / 255.0;
      si += 4;
    }
    final inputBytes = input.buffer.asUint8List();
    final shape = outputTensor.shape;
    final outputBytes = Uint8List(shape.reduce((a, b) => a * b) * 4);
    if (_delegate == null) {
      try {
        final isolate = _isolateInterpreter ??=
            await tfl.IsolateInterpreter.create(address: interpreter.address);
        await isolate.runForMultipleInputs([inputBytes], {0: outputBytes});
        return (outputBytes.buffer.asFloat32List(), shape);
      } catch (error) {
        debugPrint('[TfliteService] Isolate inference unavailable: $error');
      }
    }
    interpreter.runForMultipleInputs([inputBytes], {0: outputBytes});
    return (outputBytes.buffer.asFloat32List(), shape);
  }

  /// YOLO（[1,4+C,N] または [1,N,4+C]）の出力を、640入力座標の検出に変換する。
  List<TileDetection> _decodeFloat(Float32List out, List<int> shape) {
    if (shape.length != 3) return const [];
    final channelsFirst = shape[1] < shape[2];
    final channels = channelsFirst ? shape[1] : shape[2];
    final anchors = channelsFirst ? shape[2] : shape[1];
    final classes = channels - 4;
    if (classes <= 0) return const [];
    double at(int channel, int anchor) => channelsFirst
        ? out[channel * anchors + anchor]
        : out[anchor * channels + channel];

    // 座標が0〜1で出るモデルにも対応する。
    var maxCoord = 0.0;
    for (var a = 0; a < anchors; a += 97) {
      maxCoord = math.max(maxCoord, at(2, a));
    }
    final coordScale = maxCoord <= 1.5 ? _inputSize.toDouble() : 1.0;

    final boxes = <Rect>[];
    final scores = <double>[];
    final labels = <int>[];
    final seconds = <int>[];
    final secondScores = <double>[];
    for (var a = 0; a < anchors; a++) {
      var best = -1;
      var bestScore = 0.0;
      var second = -1;
      var secondScore = 0.0;
      for (var c = 0; c < classes; c++) {
        final v = at(4 + c, a);
        if (v > bestScore) {
          second = best;
          secondScore = bestScore;
          best = c;
          bestScore = v;
        } else if (v > secondScore) {
          second = c;
          secondScore = v;
        }
      }
      if (best < 0 || bestScore < config.scoreThreshold) continue;
      final cx = at(0, a) * coordScale;
      final cy = at(1, a) * coordScale;
      final w = at(2, a) * coordScale;
      final h = at(3, a) * coordScale;
      boxes.add(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));
      scores.add(bestScore);
      labels.add(best);
      seconds.add(second);
      secondScores.add(secondScore);
    }
    // 上位300件に絞ってから、クラスを区別しないNMS。
    final order = List<int>.generate(scores.length, (i) => i)
      ..sort((x, y) => scores[y].compareTo(scores[x]));
    final top = order.take(300).toList(growable: false);
    final keep = nonMaxSuppression(
      [for (final i in top) boxes[i]],
      [for (final i in top) scores[i]],
      iouThreshold: 0.5,
      maxPerClass: 60,
    );
    String name(int index) =>
        index >= 0 && index < _labels.length ? _labels[index] : '$index';
    return [
      for (final k in keep)
        TileDetection(
          box: boxes[top[k]],
          label: name(labels[top[k]]),
          score: scores[top[k]],
          alternative: seconds[top[k]] >= 0 ? name(seconds[top[k]]) : null,
          alternativeScore: secondScores[top[k]],
        ),
    ];
  }

  // Recursively dequantize a nested List/TypedList structure to List<double>
  Object _dequantizeRecursive(Object src, double scale, int zero) {
    if (src is Uint8List) {
      final out = List<double>.filled(src.length, 0, growable: false);
      for (var i = 0; i < src.length; i++) {
        out[i] = (src[i] - zero) * scale;
      }
      return out;
    } else if (src is Int8List) {
      final out = List<double>.filled(src.length, 0, growable: false);
      for (var i = 0; i < src.length; i++) {
        out[i] = (src[i] - zero) * scale;
      }
      return out;
    } else if (src is Float32List) {
      return src; // already float
    } else if (src is List) {
      return src
          .map((e) => _dequantizeRecursive(e as Object, scale, zero))
          .toList(growable: false);
    }
    return src;
  }

  int _argmax(List<double> xs) {
    var mi = 0;
    var mv = -1e9;
    for (var i = 0; i < xs.length; i++) {
      if (xs[i] > mv) {
        mv = xs[i];
        mi = i;
      }
    }
    return mi;
  }

  _PreprocessedImage _letterboxRgba(
    Uint8List rgba,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    final scale = math.min(dstW / srcW, dstH / srcH);
    final scaledW = math.max(1, (srcW * scale).round());
    final scaledH = math.max(1, (srcH * scale).round());
    final padLeft = ((dstW - scaledW) / 2).floor();
    final padTop = ((dstH - scaledH) / 2).floor();

    final out = Uint8List(dstW * dstH * 4);
    for (var i = 0; i < out.length; i += 4) {
      out[i] = 114;
      out[i + 1] = 114;
      out[i + 2] = 114;
      out[i + 3] = 255;
    }

    for (int y = 0; y < scaledH; y++) {
      final srcY = ((y + 0.5) / (scaledH / srcH)) - 0.5;
      final y0 = srcY.floor().clamp(0, srcH - 1);
      final y1 = (y0 + 1).clamp(0, srcH - 1);
      final wy = srcY - y0;
      for (int x = 0; x < scaledW; x++) {
        final srcX = ((x + 0.5) / (scaledW / srcW)) - 0.5;
        final x0 = srcX.floor().clamp(0, srcW - 1);
        final x1 = (x0 + 1).clamp(0, srcW - 1);
        final wx = srcX - x0;

        final topLeft = (y0 * srcW + x0) * 4;
        final topRight = (y0 * srcW + x1) * 4;
        final bottomLeft = (y1 * srcW + x0) * 4;
        final bottomRight = (y1 * srcW + x1) * 4;
        final dst = ((y + padTop) * dstW + (x + padLeft)) * 4;

        for (int channel = 0; channel < 3; channel++) {
          final top =
              (rgba[topLeft + channel] * (1.0 - wx)) +
              (rgba[topRight + channel] * wx);
          final bottom =
              (rgba[bottomLeft + channel] * (1.0 - wx)) +
              (rgba[bottomRight + channel] * wx);
          out[dst + channel] = ((top * (1.0 - wy)) + (bottom * wy))
              .round()
              .clamp(0, 255);
        }
        out[dst + 3] = 255;
      }
    }

    return _PreprocessedImage(
      rgba: out,
      transform: _ImageTransform(
        srcWidth: srcW,
        srcHeight: srcH,
        scaledWidth: scaledW,
        scaledHeight: scaledH,
        padLeft: padLeft,
        padTop: padTop,
      ),
    );
  }

  Rect? _projectRectToSource(
    double left,
    double top,
    double right,
    double bottom,
    _ImageTransform transform, {
    required bool normalizedInput,
  }) {
    final scaleX = transform.scaleX;
    final scaleY = transform.scaleY;
    final leftPx = normalizedInput ? left * _inputSize : left;
    final topPx = normalizedInput ? top * _inputSize : top;
    final rightPx = normalizedInput ? right * _inputSize : right;
    final bottomPx = normalizedInput ? bottom * _inputSize : bottom;

    final srcLeft = (leftPx - transform.padLeft) / scaleX;
    final srcTop = (topPx - transform.padTop) / scaleY;
    final srcRight = (rightPx - transform.padLeft) / scaleX;
    final srcBottom = (bottomPx - transform.padTop) / scaleY;

    if (srcRight <= 0 ||
        srcBottom <= 0 ||
        srcLeft >= transform.srcWidth ||
        srcTop >= transform.srcHeight) {
      return null;
    }

    return Rect.fromLTRB(
      (srcLeft / transform.srcWidth).clamp(0.0, 1.0),
      (srcTop / transform.srcHeight).clamp(0.0, 1.0),
      (srcRight / transform.srcWidth).clamp(0.0, 1.0),
      (srcBottom / transform.srcHeight).clamp(0.0, 1.0),
    );
  }

  List<TileDetection> _decodeFromOutputs(
    List<tfl.Tensor> outTensors,
    Map<int, Object> outputs,
    _ImageTransform transform,
  ) {
    // Prefer fused head if present, otherwise handle split (boxes + scores)
    // Heuristics: fused if any tensor has channel dimension == 4 + numClasses
    final numClasses = _labels.length;
    int? fusedIdx;
    for (var i = 0; i < outTensors.length; i++) {
      final shape = outTensors[i].shape;
      final dims = (shape.isNotEmpty && shape.first == 1)
          ? shape.sublist(1)
          : shape;
      if (dims.length == 2 &&
          (dims[1] == 4 + numClasses || dims[0] == 4 + numClasses)) {
        fusedIdx = i;
        break;
      }
      if (dims.length == 3 &&
          (dims[1] == 4 + numClasses || dims[2] == 4 + numClasses)) {
        fusedIdx = i;
        break;
      }
    }

    if (fusedIdx != null) {
      final headTensor = outTensors[fusedIdx];
      final raw = outputs[fusedIdx]!;
      final isFloat = headTensor.type.toString().toLowerCase().contains(
        'float32',
      );
      final head = isFloat
          ? raw
          : _dequantizeRecursive(
              raw,
              headTensor.params.scale,
              headTensor.params.zeroPoint,
            );
      return _decodeYoloFused(head, headTensor.shape, transform);
    }

    // Split: find boxes tensor (dim contains 4) and scores tensor (dim contains numClasses)
    int? boxIdx;
    int? clsIdx;
    bool boxesTransposed = false;
    bool classesTransposed = false;
    for (var i = 0; i < outTensors.length; i++) {
      final s = outTensors[i].shape;
      final dims = (s.isNotEmpty && s.first == 1) ? s.sublist(1) : s;
      if (dims.length == 2) {
        if (dims[1] == 4) {
          boxIdx = i;
          boxesTransposed = false;
        }
        if (dims[0] == 4) {
          boxIdx = i;
          boxesTransposed = true;
        }
        if (dims[1] == numClasses) {
          clsIdx = i;
          classesTransposed = false;
        }
        if (dims[0] == numClasses) {
          clsIdx = i;
          classesTransposed = true;
        }
      } else if (dims.length == 3) {
        // [A,B,C] cases: try to match any axis to 4/numClasses
        final axes = dims;
        for (int ax = 0; ax < 3; ax++) {
          if (axes[ax] == 4) {
            boxIdx = i;
            boxesTransposed = ax != 1;
          }
          if (axes[ax] == numClasses) {
            clsIdx = i;
            classesTransposed = ax != 1;
          }
        }
      }
    }
    if (boxIdx != null && clsIdx != null) {
      final boxT = outTensors[boxIdx];
      final clsT = outTensors[clsIdx];
      final boxRaw = outputs[boxIdx]!;
      final clsRaw = outputs[clsIdx]!;
      final boxIsFloat = boxT.type.toString().toLowerCase().contains('float32');
      final clsIsFloat = clsT.type.toString().toLowerCase().contains('float32');
      final boxes = boxIsFloat
          ? boxRaw
          : _dequantizeRecursive(
              boxRaw,
              boxT.params.scale,
              boxT.params.zeroPoint,
            );
      final classes = clsIsFloat
          ? clsRaw
          : _dequantizeRecursive(
              clsRaw,
              clsT.params.scale,
              clsT.params.zeroPoint,
            );
      return _decodeYoloSplit(
        boxes,
        boxT.shape,
        boxesTransposed,
        classes,
        clsT.shape,
        classesTransposed,
        transform,
      );
    }

    // Try TF-OD style NMS outputs: boxes [1,K,4], scores [1,K], classes [1,K]
    final nmsBoxes = <int, int>{}; // idx -> K
    final nmsScores = <int, int>{};
    final nmsClasses = <int, int>{};
    for (var i = 0; i < outTensors.length; i++) {
      final s = outTensors[i].shape;
      if (s.length == 3 && s[0] == 1 && s[2] == 4) {
        nmsBoxes[i] = s[1];
      } else if (s.length == 2 && s[0] == 1) {
        // could be scores or classes or num_detections
        nmsScores[i] = s[1];
        nmsClasses[i] = s[1];
      }
    }
    for (final e in nmsBoxes.entries) {
      final k = e.value;
      final bIdx = e.key;
      // find matching scores and classes with same K
      final sIdx = nmsScores.entries
          .firstWhere((x) => x.value == k, orElse: () => const MapEntry(-1, -1))
          .key;
      final cIdx = nmsClasses.entries
          .firstWhere(
            (x) => x.value == k && x.key != sIdx,
            orElse: () => const MapEntry(-1, -1),
          )
          .key;
      if (sIdx >= 0 && cIdx >= 0) {
        final bT = outTensors[bIdx];
        final sT = outTensors[sIdx];
        final cT = outTensors[cIdx];
        final bRaw = outputs[bIdx]!;
        final sRaw = outputs[sIdx]!;
        final cRaw = outputs[cIdx]!;
        final bIsFloat = bT.type.toString().toLowerCase().contains('float32');
        final sIsFloat = sT.type.toString().toLowerCase().contains('float32');
        final cIsFloat = cT.type.toString().toLowerCase().contains('float32');
        final boxes = bIsFloat
            ? bRaw
            : _dequantizeRecursive(bRaw, bT.params.scale, bT.params.zeroPoint);
        final scores = sIsFloat
            ? sRaw
            : _dequantizeRecursive(sRaw, sT.params.scale, sT.params.zeroPoint);
        final classes = cIsFloat
            ? cRaw
            : _dequantizeRecursive(cRaw, cT.params.scale, cT.params.zeroPoint);
        return _decodeYoloNms(
          boxes,
          bT.shape,
          scores,
          sT.shape,
          classes,
          cT.shape,
          transform,
        );
      }
    }

    // Fallback: attempt with the first tensor as fused
    final headTensor = outTensors.first;
    final raw = outputs[0]!;
    final isFloat = headTensor.type.toString().toLowerCase().contains(
      'float32',
    );
    final head = isFloat
        ? raw
        : _dequantizeRecursive(
            raw,
            headTensor.params.scale,
            headTensor.params.zeroPoint,
          );
    return _decodeYoloFused(head, headTensor.shape, transform);
  }

  List<TileDetection> _decodeYoloFused(
    Object head,
    List<int> headShape,
    _ImageTransform transform,
  ) {
    final dets = <TileDetection>[];
    try {
      if (head is List) {
        // Build rows [N, C] from possible shapes
        // Typical Ultralytics: [1, 8400, 4+nc] or [1, 4+nc, 8400]
        Iterable<List<double>> rows = const [];
        if (headShape.length == 3 && headShape[0] == 1) {
          final d1 = headShape[1];
          final d2 = headShape[2];
          // [1, N, C]
          if (d1 > d2) {
            // likely [1, 8400, 84]
            final twoD = (head).first as List; // N x C
            rows = twoD.map<List<double>>(
              (r) => (r as List).map((e) => (e as num).toDouble()).toList(),
            );
          } else {
            // [1, C, N] -> transpose to [N, C]
            final cn = (head).first as List; // C x N
            final c = d1;
            final n = d2;
            final transposed = List.generate(
              n,
              (i) => List<double>.filled(c, 0, growable: false),
              growable: false,
            );
            for (int ci = 0; ci < c; ci++) {
              final col = (cn[ci] as List);
              for (int ni = 0; ni < n; ni++) {
                transposed[ni][ci] = (col[ni] as num).toDouble();
              }
            }
            rows = transposed;
          }
        } else if (head.isNotEmpty && head.first is List) {
          // 2D [N, C]
          rows = (head).map<List<double>>(
            (r) => (r as List).map((e) => (e as num).toDouble()).toList(),
          );
        }

        final boxes = <Rect>[];
        final scores = <double>[];
        final clsIdxs = <int>[];
        for (final row in rows) {
          if (row.length < 6) continue;
          // Layout A (YOLOv5系): [cx,cy,w,h,obj, c0..cK)
          // Layout B (YOLOv8/11系): [cx,cy,w,h, c0..cK)  (objなし)
          final cx = row[0];
          final cy = row[1];
          final w = row[2];
          final h = row[3];
          final expectedB = 4 + _labels.length;
          final expectedA = expectedB + 1;
          int classStart = 5; // default A
          double obj = 1.0;
          if (row.length == expectedB) {
            classStart = 4; // B 形式（objなし）
            obj = 1.0;
          } else if (row.length >= expectedA) {
            classStart = 5; // A 形式
            obj = row[4];
          } else {
            // 不明な形式。最小限でB形式として扱う
            classStart = 4;
            obj = 1.0;
          }
          var classScores = row.sublist(classStart);
          // Many exports output logits; map to probabilities if values not in [0,1]
          if (classScores.any((v) => v < 0.0 || v > 1.0)) {
            classScores = classScores
                .map((x) => 1.0 / (1.0 + math.exp(-x)))
                .toList();
          }
          final ci = _argmax(classScores);
          final prob = classScores[ci];
          if (!(obj >= 0.0 && obj <= 1.0)) {
            obj = 1.0 / (1.0 + math.exp(-obj));
          }
          final score = (obj * prob).clamp(0.0, 1.0);
          if (score < 0.10) continue;

          // 出力がピクセル値か正規化値かを自動判別（ヒューリスティック）
          // 大半が0..1内に収まっていれば正規化とみなし、そのまま使う。
          final bool looksNormalized =
              (cx <= 1.2 && cy <= 1.2 && w <= 1.2 && h <= 1.2);
          final left = cx - (w / 2);
          final top = cy - (h / 2);
          final right = cx + (w / 2);
          final bottom = cy + (h / 2);
          final rect = _projectRectToSource(
            left,
            top,
            right,
            bottom,
            transform,
            normalizedInput: looksNormalized,
          );
          if (rect == null) continue;
          boxes.add(rect);
          scores.add(score);
          clsIdxs.add(ci);
        }

        // 上位だけに絞ってからNMS（量を減らして高速化）
        final idxSorted = List<int>.generate(scores.length, (i) => i)
          ..sort((a, b) => scores[b].compareTo(scores[a]));
        final topK = 300; // まずは上位300に制限
        final sel = idxSorted.take(topK).toList(growable: false);
        final kBoxes = [for (final i in sel) boxes[i]];
        final kScores = [for (final i in sel) scores[i]];
        final kCls = [for (final i in sel) clsIdxs[i]];

        final keepLocal = nonMaxSuppression(
          kBoxes,
          kScores,
          iouThreshold: 0.50,
          maxPerClass: 60,
        );
        for (final i in keepLocal) {
          final label = (kCls[i] >= 0 && kCls[i] < _labels.length)
              ? _labels[kCls[i]]
              : 'unknown';
          dets.add(
            TileDetection(
              box: kBoxes[i],
              label: label,
              score: kScores[i],
              isRed:
                  label.contains('_red') ||
                  label.contains('aka') ||
                  label.contains('red'),
            ),
          );
        }
      }
    } catch (e) {
      // ignore
    }
    return dets;
  }

  List<TileDetection> _decodeYoloSplit(
    Object boxes,
    List<int> boxShape,
    bool boxesTransposed,
    Object classes,
    List<int> clsShape,
    bool classesTransposed,
    _ImageTransform transform,
  ) {
    // boxes: [N,4] or [4,N] or [1,N,4]/[1,4,N]
    // classes: [N,C] or [C,N] / [1,N,C]/[1,C,N]
    final List<List<double>> boxes2D = _to2D(boxes, boxShape, boxesTransposed);
    final List<List<double>> scores2D = _to2D(
      classes,
      clsShape,
      classesTransposed,
    );
    final dets = <TileDetection>[];
    final boxesNorm = <Rect>[];
    final scores = <double>[];
    final clsIdxs = <int>[];
    final n = boxes2D.length;
    for (int i = 0; i < n; i++) {
      final b = boxes2D[i];
      if (b.length < 4) continue;
      final cx = b[0], cy = b[1], w = b[2], h = b[3];
      final row = (i < scores2D.length) ? scores2D[i] : <double>[];
      if (row.isEmpty) continue;
      // logits -> prob if必要
      final probs = (row.any((v) => v < 0.0 || v > 1.0))
          ? row.map((x) => 1.0 / (1.0 + math.exp(-x))).toList()
          : row;
      final ci = _argmax(probs);
      final score = probs[ci].clamp(0.0, 1.0);
      if (score < 0.10) continue;
      final bool looksNormalized =
          (cx <= 1.2 && cy <= 1.2 && w <= 1.2 && h <= 1.2);
      final rect = _projectRectToSource(
        cx - (w / 2),
        cy - (h / 2),
        cx + (w / 2),
        cy + (h / 2),
        transform,
        normalizedInput: looksNormalized,
      );
      if (rect == null) continue;
      boxesNorm.add(rect);
      scores.add(score);
      clsIdxs.add(ci);
    }
    // NMS
    final idxSorted = List<int>.generate(scores.length, (i) => i)
      ..sort((a, b) => scores[b].compareTo(scores[a]));
    final topK = 300;
    final sel = idxSorted.take(topK).toList(growable: false);
    final kBoxes = [for (final i in sel) boxesNorm[i]];
    final kScores = [for (final i in sel) scores[i]];
    final kCls = [for (final i in sel) clsIdxs[i]];
    final keepLocal = nonMaxSuppression(
      kBoxes,
      kScores,
      iouThreshold: 0.50,
      maxPerClass: 60,
    );
    for (final i in keepLocal) {
      final label = (kCls[i] >= 0 && kCls[i] < _labels.length)
          ? _labels[kCls[i]]
          : 'unknown';
      dets.add(
        TileDetection(
          box: kBoxes[i],
          label: label,
          score: kScores[i],
          isRed:
              label.contains('_red') ||
              label.contains('aka') ||
              label.contains('red'),
        ),
      );
    }
    return dets;
  }

  List<List<double>> _to2D(Object arr, List<int> shape, bool transposed) {
    // Flatten nested List to 2D [N, M]; transpose if necessary
    List<List<double>> rows = const [];
    if (arr is List) {
      if (shape.length >= 3 && shape.first == 1) {
        // drop batch
        final twoD = (arr).first as List;
        rows = twoD
            .map<List<double>>(
              (r) => (r as List).map((e) => (e as num).toDouble()).toList(),
            )
            .toList();
      } else if (arr.isNotEmpty && arr.first is List) {
        rows = (arr)
            .map<List<double>>(
              (r) => (r as List).map((e) => (e as num).toDouble()).toList(),
            )
            .toList();
      }
    }
    if (rows.isEmpty) return const <List<double>>[];
    if (!transposed) return rows;
    // transpose [M,N] -> [N,M]
    final m = rows.length;
    final n = rows.first.length;
    final out = List.generate(n, (_) => List<double>.filled(m, 0.0));
    for (int i = 0; i < m; i++) {
      final r = rows[i];
      for (int j = 0; j < n; j++) {
        out[j][i] = r[j];
      }
    }
    return out;
  }

  List<TileDetection> _decodeYoloNms(
    Object boxes,
    List<int> boxShape,
    Object scores,
    List<int> scoreShape,
    Object classes,
    List<int> classShape,
    _ImageTransform transform,
  ) {
    // boxes: [1,K,4] normalized 0..1; scores: [1,K]; classes: [1,K]
    if (boxes is! List || (boxes).isEmpty) return const [];
    final k = (boxShape.length >= 2) ? boxShape[1] : (boxes).length;
    final b2d = ((boxes).first as List)
        .cast<List>()
        .map<List<double>>((r) => r.map((e) => (e as num).toDouble()).toList())
        .toList();
    final s1d = (scores is List && (scores).isNotEmpty)
        ? ((scores).first as List).map((e) => (e as num).toDouble()).toList()
        : <double>[];
    final c1dRaw = (classes is List && (classes).isNotEmpty)
        ? ((classes).first as List)
        : <Object>[];
    final dets = <TileDetection>[];
    for (
      int i = 0;
      i < k && i < b2d.length && i < s1d.length && i < c1dRaw.length;
      i++
    ) {
      final b = b2d[i];
      if (b.length < 4) continue;
      // assume boxes are [ymin, xmin, ymax, xmax] or [cx,cy,w,h]; try ymin/xmin first
      double l = b[1], t = b[0], r = b[3], bt = b[2];
      bool normalizedInput = true;
      if (!(l >= 0 && t >= 0 && r <= 1.1 && bt <= 1.1 && r > l && bt > t)) {
        final cx = b[0], cy = b[1], w = b[2], h = b[3];
        l = cx - (w / 2);
        t = cy - (h / 2);
        r = cx + (w / 2);
        bt = cy + (h / 2);
        normalizedInput = false;
      }
      final score = s1d[i].clamp(0.0, 1.0);
      if (score < 0.10) continue;
      int ci;
      final v = c1dRaw[i];
      if (v is num) {
        ci = v.toInt().clamp(0, _labels.length - 1);
      } else {
        ci = 0;
      }
      final rect = _projectRectToSource(
        l,
        t,
        r,
        bt,
        transform,
        normalizedInput: normalizedInput,
      );
      if (rect == null) continue;
      dets.add(
        TileDetection(
          box: rect,
          label: (ci >= 0 && ci < _labels.length) ? _labels[ci] : 'unknown',
          score: score,
          isRed: (ci >= 0 && ci < _labels.length)
              ? _labels[ci].contains('red')
              : false,
        ),
      );
    }
    return dets;
  }
}

class _Attempt {
  const _Attempt(this.selection, this.quarterTurns, this.strategy);

  final SelectedTiles selection;
  final int quarterTurns;
  final String strategy;

  bool isBetterThan(_Attempt other) {
    final a = selection;
    final b = other.selection;
    if (a.isComplete != b.isComplete) return a.isComplete;
    final lengthDelta = a.detections.length - b.detections.length;
    if (!a.isComplete && lengthDelta.abs() >= 2) return lengthDelta > 0;
    final qualityDelta = a.quality - b.quality;
    if (qualityDelta.abs() > 3.0) return qualityDelta > 0;
    return a.averageScore > b.averageScore;
  }
}
