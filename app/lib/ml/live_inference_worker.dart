import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nanikiru_cam/ml/live_frame.dart';
import 'package:nanikiru_cam/ml/live_preprocess.dart';
import 'package:nanikiru_cam/ml/live_yolo_decoder.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart' as tfl;

/// ライブ推論の設定。
class LiveInferenceConfig {
  const LiveInferenceConfig({
    this.inputSize,
    this.scoreThreshold = 0.25,
    this.iouThreshold = 0.5,
    this.threads = 4,
    this.roi,
  });

  /// モデルの入力の一辺（画素）。null ならモデルの入力形状から読む（640 / 480 などのモデルを
  /// そのまま差し替えられる）。指定すると、形状が違うモデルの入力をその大きさに変える。
  final int? inputSize;

  /// これ未満の検出は捨てる（ライブは数を数えるので、写真の 0.10 より高くする）。
  final double scoreThreshold;
  final double iouThreshold;

  /// CPU（XNNPACK）のスレッド数。
  final int threads;

  /// 推論範囲（正立フレームに対する 0〜1）。null なら中央の正方形。
  final Rect? roi;
}

/// 1 フレーム 1 推論を別 Isolate で行う（設計書 3.3）。
///
/// YUV/BGRA → RGB の変換・回転・縮小（重い処理）も推論も、すべて別 Isolate で行い、
/// UI の Isolate にはラベルと枠だけを返す。インタプリタはこの Isolate の中で作って閉じる。
/// GPU デリゲートはスレッドに縛られるため使わない（CPU + XNNPACK）。
class LiveInferenceWorker {
  LiveInferenceWorker._(this._isolate, this._requests, this._responses) {
    _subscription = _responses.listen(_onResponse);
    // 推論中に Isolate が落ちたら、待っている推論を失敗させる。
    _isolate.addOnExitListener(_exits.sendPort);
    _exits.listen((_) => _failAll('LiveInferenceWorker exited'));
  }

  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;
  final ReceivePort _exits = ReceivePort();
  late final StreamSubscription<Object?> _subscription;
  final Map<int, Completer<LiveDetections>> _pending = {};
  int _nextId = 0;
  bool _closed = false;
  bool _disposed = false;

  /// [modelPath] は端末内のファイル（[ensureLiveModelFile]）。読み込みに失敗したら投げる。
  static Future<LiveInferenceWorker> spawn({
    required String modelPath,
    required List<String> labels,
    LiveInferenceConfig config = const LiveInferenceConfig(),
  }) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _workerMain,
      _WorkerInit(ready.sendPort, modelPath, labels, config),
      debugName: 'LiveInference',
      // 準備の途中で落ちたら、エラー（List）か終了（null）が届く。
      onError: ready.sendPort,
      onExit: ready.sendPort,
    );
    final first = await ready.first;
    ready.close();
    if (first is _WorkerReady) {
      final responses = ReceivePort();
      first.requests.send(_Attach(responses.sendPort));
      return LiveInferenceWorker._(isolate, first.requests, responses);
    }
    isolate.kill(priority: Isolate.immediate);
    throw StateError('Live model load failed: $first');
  }

  /// [frame] を [quarterTurns] 回（時計回り 90°）回して推論する。
  Future<LiveDetections> detect(LiveFrame frame, {required int quarterTurns}) {
    if (_closed) return Future.error(StateError('LiveInferenceWorker closed'));
    final id = _nextId++;
    final completer = Completer<LiveDetections>();
    _pending[id] = completer;
    _requests.send(_DetectRequest(id, frame, quarterTurns));
    return completer.future;
  }

  void _onResponse(Object? message) {
    if (message is! _DetectResponse) return;
    final completer = _pending.remove(message.id);
    if (completer == null) return;
    final result = message.result;
    if (result != null) {
      completer.complete(result);
    } else {
      completer.completeError(StateError(message.error ?? 'inference failed'));
    }
  }

  /// Isolate が動いているか（閉じた・落ちたら false）。
  bool get isAlive => !_closed;

  void _failAll(String reason) {
    _closed = true;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final c in pending) {
      c.completeError(StateError(reason));
    }
    _exits.close();
  }

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    if (!_closed) _requests.send(const _Close());
    _failAll('LiveInferenceWorker closed');
    await _subscription.cancel();
    _responses.close();
    // インタプリタを閉じてから終了するのを少し待ち、残っていれば止める。
    Timer(const Duration(seconds: 2), () => _isolate.kill());
  }
}

/// アセットのモデルを端末内のファイルにする（ファイルから読むとメモリに複製しない）。
///
/// 写真用（`TfliteService`）と同時に書き込まないよう、別のディレクトリを使う。
Future<String> ensureLiveModelFile(String asset) async {
  final data = await rootBundle.load(asset);
  final directory = await getTemporaryDirectory();
  final mlDirectory = Directory('${directory.path}/ml_live');
  await mlDirectory.create(recursive: true);
  final file = File('${mlDirectory.path}/${asset.split('/').last}');
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  if (!await file.exists() || await file.length() != bytes.length) {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
  return file.path;
}

// --- Isolate の中 ----------------------------------------------------------

class _WorkerInit {
  const _WorkerInit(this.reply, this.modelPath, this.labels, this.config);
  final SendPort reply;
  final String modelPath;
  final List<String> labels;
  final LiveInferenceConfig config;
}

class _WorkerReady {
  const _WorkerReady(this.requests);
  final SendPort requests;
}

class _Attach {
  const _Attach(this.responses);
  final SendPort responses;
}

class _DetectRequest {
  const _DetectRequest(this.id, this.frame, this.quarterTurns);
  final int id;
  final LiveFrame frame;
  final int quarterTurns;
}

class _DetectResponse {
  const _DetectResponse(this.id, this.result, this.error);
  final int id;
  final LiveDetections? result;
  final String? error;
}

class _Close {
  const _Close();
}

void _workerMain(_WorkerInit init) {
  final requests = ReceivePort();
  final _LiveModel model;
  try {
    model = _LiveModel.open(init.modelPath, init.labels, init.config);
  } catch (error) {
    init.reply.send('$error');
    requests.close();
    return;
  }
  init.reply.send(_WorkerReady(requests.sendPort));
  SendPort? responses;
  requests.listen((message) {
    if (message is _Attach) {
      responses = message.responses;
    } else if (message is _DetectRequest) {
      try {
        final result = model.detect(message.frame, message.quarterTurns);
        responses?.send(_DetectResponse(message.id, result, null));
      } catch (error) {
        responses?.send(_DetectResponse(message.id, null, '$error'));
      }
    } else if (message is _Close) {
      model.close();
      requests.close();
    }
  });
}

/// モデルの入力形状 `[1, S, S, 3]` から一辺 S を読む。正方形でなければ [fallback]。
@visibleForTesting
int liveModelInputSize(List<int> shape, {int fallback = 640}) {
  if (shape.length == 4 && shape[1] > 0 && shape[1] == shape[2]) {
    return shape[1];
  }
  return fallback;
}

class _LiveModel {
  _LiveModel._(this._interpreter, this._labels, this._config, this._inputSize)
    : _rgb = Uint8List(_inputSize * _inputSize * 3);

  factory _LiveModel.open(
    String path,
    List<String> labels,
    LiveInferenceConfig config,
  ) {
    final options = tfl.InterpreterOptions()..threads = config.threads;
    tfl.Interpreter? interpreter;
    try {
      interpreter = tfl.Interpreter.fromFile(File(path), options: options);
      final shape = interpreter.getInputTensor(0).shape;
      final s = config.inputSize ?? liveModelInputSize(shape);
      if (!listEquals(shape, [1, s, s, 3])) {
        interpreter.resizeInputTensor(0, [1, s, s, 3]);
      }
      interpreter.allocateTensors();
      if (interpreter.getOutputTensors().length != 1) {
        throw StateError('出力が 1 つのモデル（YOLO の融合ヘッド）だけ対応');
      }
      final model = _LiveModel._(interpreter, labels, config, s);
      interpreter = null;
      return model;
    } finally {
      interpreter?.close();
      // TfLiteInterpreterCreate はオプションを複製する。
      options.delete();
    }
  }

  final tfl.Interpreter _interpreter;
  final List<String> _labels;
  final LiveInferenceConfig _config;

  /// モデルに渡す入力の一辺（画素）。前処理のレターボックスも出力の座標の倍率もこれに合わせる。
  final int _inputSize;
  final Uint8List _rgb;
  Float32List? _floatInput;
  Uint8List? _quantInput;
  Uint8List? _quantLut;

  LiveDetections detect(LiveFrame frame, int quarterTurns) {
    final watch = Stopwatch()..start();
    final transform = LiveInputTransform.compute(
      rawWidth: frame.width,
      rawHeight: frame.height,
      quarterTurns: quarterTurns,
      roi: _config.roi,
      inputSize: _inputSize,
    );
    final luminance = preprocessLiveFrame(frame, transform, _rgb);
    final sharpness = liveSharpness(_rgb, transform);
    _writeInput();
    final preprocessMicros = watch.elapsedMicroseconds;

    _interpreter.invoke();
    final inferenceMicros = watch.elapsedMicroseconds - preprocessMicros;

    final outTensor = _interpreter.getOutputTensor(0);
    final raw = outTensor.data;
    final type = outTensor.type.toString().toLowerCase();
    final Float32List values;
    if (type.contains('float32')) {
      values = raw.buffer.asFloat32List(
        raw.offsetInBytes,
        raw.lengthInBytes ~/ 4,
      );
    } else {
      final params = outTensor.params;
      values = dequantize(
        raw,
        signed: type.contains('int8') && !type.contains('uint8'),
        scale: params.scale,
        zeroPoint: params.zeroPoint,
      );
    }
    final boxes = decodeYoloOutput(
      values,
      outTensor.shape,
      scoreThreshold: _config.scoreThreshold,
      inputSize: _inputSize,
      iouThreshold: _config.iouThreshold,
    );
    final tiles = <LiveTileBox>[];
    for (final b in boxes) {
      final rect = transform.toUprightNormalized(b.box);
      if (rect == null) continue;
      final label = b.classIndex < _labels.length
          ? _labels[b.classIndex]
          : '${b.classIndex}';
      tiles.add(LiveTileBox(box: rect, label: label, score: b.score));
    }
    return LiveDetections(
      tiles: tiles,
      luminance: luminance,
      sharpness: sharpness,
      uprightWidth: transform.uprightWidth,
      uprightHeight: transform.uprightHeight,
      preprocessMicros: preprocessMicros,
      inferenceMicros: inferenceMicros,
    );
  }

  void _writeInput() {
    final tensor = _interpreter.getInputTensor(0);
    final type = tensor.type.toString().toLowerCase();
    if (type.contains('float32')) {
      final floats = _floatInput ??= Float32List(_rgb.length);
      const k = 1 / 255;
      for (var i = 0; i < _rgb.length; i++) {
        floats[i] = _rgb[i] * k;
      }
      tensor.data = floats.buffer.asUint8List();
      return;
    }
    // 量子化入力: 0..255 を (x/255)/scale + zero に写す表を一度だけ作る。
    final signed = type.contains('int8') && !type.contains('uint8');
    final lut = _quantLut ??= () {
      final params = tensor.params;
      final scale = params.scale == 0 ? 1 / 255 : params.scale;
      final table = Uint8List(256);
      for (var v = 0; v < 256; v++) {
        var q = ((v / 255) / scale).round() + params.zeroPoint;
        if (signed) {
          q = q.clamp(-128, 127);
          table[v] = q & 0xFF;
        } else {
          table[v] = q.clamp(0, 255);
        }
      }
      return table;
    }();
    final bytes = _quantInput ??= Uint8List(_rgb.length);
    for (var i = 0; i < _rgb.length; i++) {
      bytes[i] = lut[_rgb[i]];
    }
    tensor.data = bytes;
  }

  void close() {
    try {
      _interpreter.close();
    } catch (_) {}
  }
}
