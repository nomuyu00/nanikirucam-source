// 解析エンジン（NanikiruEngine.analyze）の 1 回あたりの時間を測る（設計書 15 章の目安:
// 無料 200 ms・Pro 1 秒。Pro は経路列挙・2 段階先・ブロック分解・理由タグ・リーチ判断込み）。
// Pro の内訳として、2 段階先（全候補）とブロック分解だけの時間も出す（理由タグは無料にも
// 含まれる）。
//   dart run tool/bench_engine.dart              （JIT）
//   dart compile exe tool/bench_engine.dart -o /tmp/bench_engine && /tmp/bench_engine
//                                                （AOT、端末のリリースビルドに近い）
//
// 手は「ランダムな和了形から 1〜3 枚入れ替えた 14 枚」で、打牌後がテンパイ・一向聴に
// なるもの（経路列挙が重い）と、一様ランダムの 14 枚（ほとんど二向聴以上の目安）を測る。
// キャッシュが効かないよう、毎回新しいエンジンを作り、シャンテン数のメモも捨てる
// （compute() で毎回新しい Isolate を使う場合に近い）。
import 'dart:io';
import 'dart:math';

import 'package:mahjong_core/mahjong_core.dart';

List<int> _completeHand(Random random) {
  while (true) {
    final counts = List<int>.filled(kTileKinds, 0);
    var ok = true;
    for (var g = 0; g < 4 && ok; g++) {
      if (random.nextInt(3) == 0) {
        final t = random.nextInt(kTileKinds);
        counts[t] += 3;
      } else {
        final suit = random.nextInt(3);
        final start = suit * 9 + random.nextInt(7);
        for (var k = 0; k < 3; k++) {
          counts[start + k]++;
        }
      }
    }
    counts[random.nextInt(kTileKinds)] += 2;
    for (final c in counts) {
      if (c > 4) ok = false;
    }
    if (ok) return counts;
  }
}

List<int> _perturb(Random random, List<int> base, int swaps) {
  final counts = List<int>.of(base);
  for (var i = 0; i < swaps; i++) {
    while (true) {
      final out = random.nextInt(kTileKinds);
      if (counts[out] == 0) continue;
      final inn = random.nextInt(kTileKinds);
      if (inn == out || counts[inn] >= 4) continue;
      counts[out]--;
      counts[inn]++;
      break;
    }
  }
  return counts;
}

List<int> _uniform(Random random) {
  final counts = List<int>.filled(kTileKinds, 0);
  var left = 14;
  while (left > 0) {
    final t = random.nextInt(kTileKinds);
    if (counts[t] == 4) continue;
    counts[t]++;
    left--;
  }
  return counts;
}

HandState _state(Random random, List<int> counts) {
  final dora = random.nextInt(kTileKinds);
  final visible = List<int>.filled(kTileKinds, 0);
  for (var i = 0; i < 6; i++) {
    final t = random.nextInt(kTileKinds);
    if (counts[t] + visible[t] < 4) visible[t]++;
  }
  return HandState(
    counts: counts,
    visible: visible,
    doraIds: [dora],
    redIds: {
      for (final id in kRedFiveIds)
        if (counts[id] > 0 && random.nextBool()) id,
    },
    dealer: random.nextInt(4) == 0,
  );
}

class _Stats {
  final List<double> ms = [];
  void add(Duration d) => ms.add(d.inMicroseconds / 1000);
  String get summary {
    final s = List<double>.of(ms)..sort();
    double at(double q) => s[((s.length - 1) * q).round()];
    final mean = s.reduce((a, b) => a + b) / s.length;
    return '平均 ${mean.toStringAsFixed(1)} ms, 中央 ${at(0.5).toStringAsFixed(1)}, '
        '95% ${at(0.95).toStringAsFixed(1)}, 最大 ${s.last.toStringAsFixed(1)} '
        '(${s.length} 手)';
  }
}

void _run(String label, List<HandState> hands) {
  final free = _Stats();
  final pro = _Stats();
  final twoStep = _Stats();
  final blocks = _Stats();
  for (final hand in hands) {
    clearShantenCache();
    var sw = Stopwatch()..start();
    DefaultNanikiruEngine().analyze(hand, deep: false);
    free.add(sw.elapsed);
    clearShantenCache();
    sw = Stopwatch()..start();
    DefaultNanikiruEngine().analyze(hand, deep: true);
    pro.add(sw.elapsed);
    // 内訳: 2 段階先（全候補）とブロック分解だけ
    clearShantenCache();
    sw = Stopwatch()..start();
    final calc = TwoStepCalculator(hand);
    for (var id = 0; id < kTileKinds; id++) {
      if (hand.counts[id] > 0) calc.of(id);
    }
    twoStep.add(sw.elapsed);
    sw = Stopwatch()..start();
    decomposeBlocks(hand);
    blocks.add(sw.elapsed);
  }
  stdout.writeln(label);
  stdout.writeln('  無料 deep=false: ${free.summary}');
  stdout.writeln('  Pro  deep=true : ${pro.summary}');
  stdout.writeln('    うち 2 段階先（全候補）: ${twoStep.summary}');
  stdout.writeln('    うちブロック分解      : ${blocks.summary}');
}

void main(List<String> args) {
  final random = Random(20261021);
  final near = <HandState>[];
  final byShanten = <int, int>{};
  while (near.length < 300) {
    final counts = _perturb(
      random,
      _completeHand(random),
      1 + random.nextInt(3),
    );
    final s = shantenFromCounts(counts).shanten;
    if (s > 1) continue;
    byShanten[s] = (byShanten[s] ?? 0) + 1;
    near.add(_state(random, counts));
  }
  final uniform = [
    for (var i = 0; i < 300; i++) _state(random, _uniform(random)),
  ];
  final oneSuit = <HandState>[];
  while (oneSuit.length < 100) {
    final counts = List<int>.filled(kTileKinds, 0);
    var left = 14;
    while (left > 0) {
      final t = random.nextInt(9);
      if (counts[t] == 4) continue;
      counts[t]++;
      left--;
    }
    if (shantenFromCounts(counts).shanten > 1) continue;
    oneSuit.add(_state(random, counts));
  }

  // JIT を温める。
  for (var i = 0; i < 40; i++) {
    DefaultNanikiruEngine().analyze(near[i], deep: true);
    DefaultNanikiruEngine().analyze(uniform[i], deep: true);
  }

  stdout.writeln('14 枚のシャンテン数の内訳（近い手）: $byShanten');
  _run('和了形から 1〜3 枚入れ替え（打牌後テンパイ・一向聴が中心）', near);
  _run('一様ランダムの 14 枚（ほとんど二向聴以上）', uniform);
  _run('萬子だけの 14 枚（一向聴以内、待ち・分け方が多い最悪寄り）', oneSuit);

  // キャッシュが効く 2 回目
  final engine = DefaultNanikiruEngine();
  final hit = _Stats();
  for (final hand in near.take(50)) {
    engine.analyze(hand, deep: true);
    final sw = Stopwatch()..start();
    engine.analyze(hand, deep: true);
    hit.add(sw.elapsed);
  }
  stdout.writeln('同じ手の 2 回目（LRU）: ${hit.summary}');
}
