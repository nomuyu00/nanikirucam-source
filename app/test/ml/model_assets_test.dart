import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ml/model_config.dart';

/// ライブの既定が指すモデルや、控え（写真用 int8）のアセットが実際に同梱されているか。
/// （アセットが無いと Live 画面が止まる。読み込み失敗の控えはあるが、同梱し忘れは先に気づきたい）
void main() {
  final models = {
    'live n': ModelConfig.liveNInt8Model,
    'live s': ModelConfig.liveSInt8Model,
    'live n 480': ModelConfig.liveN480Int8Model,
    '写真用 int8': ModelConfig.int8Model,
    '写真用 fp32': ModelConfig.fp32Model,
  };

  for (final entry in models.entries) {
    test('${entry.key} (${entry.value}) は tflite として同梱されている', () {
      final file = File(entry.value);
      expect(file.existsSync(), isTrue, reason: '${entry.value} がない');
      // FlatBuffers のファイル識別子 "TFL3"（先頭から 4〜7 バイト目）。
      final head = file.openSync().readSync(8);
      expect(String.fromCharCodes(head.sublist(4, 8)), 'TFL3');
      expect(file.lengthSync(), greaterThan(1000000));
    });
  }

  test('ラベルは 38 クラスで、モデルの出力（4 + 38 チャンネル）と並びを合わせる', () {
    final labels = File(ModelConfig.defaultLabelsAsset)
        .readAsLinesSync()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    expect(labels, hasLength(38));
    expect(labels.first, '0b');
    expect(labels.last, '9s');
  });
}
