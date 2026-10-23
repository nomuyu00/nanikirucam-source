// シャンテン数・候補順位の速さを測る。
//   dart run tool/bench_shanten.dart            （JIT）
//   dart compile exe tool/bench_shanten.dart -o /tmp/bench && /tmp/bench   （AOT、端末のリリースビルドに近い）
import 'dart:io';
import 'dart:math';

import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';

List<int> _randomCounts(Random random, int n) {
  final counts = List<int>.filled(kTileKinds, 0);
  var left = n;
  while (left > 0) {
    final t = random.nextInt(kTileKinds);
    if (counts[t] == 4) continue;
    counts[t]++;
    left--;
  }
  return counts;
}

double _perCallMicros(Stopwatch sw, int calls) =>
    sw.elapsedMicroseconds / calls;

void main(List<String> args) {
  final random = Random(20261021);
  const handCount = 20000;
  final hands = [
    for (var i = 0; i < handCount; i++) _randomCounts(random, 13 + i % 2),
  ];

  // 測る前に JIT を温める（メモは捨てる）
  for (var i = 0; i < 2000; i++) {
    shantenFromCounts(hands[i]);
  }
  clearShantenCache();

  var sink = 0;
  final cold = Stopwatch()..start();
  for (final h in hands) {
    sink += shantenFromCounts(h).shanten;
  }
  cold.stop();

  final warm = Stopwatch()..start();
  for (var r = 0; r < 5; r++) {
    for (final h in hands) {
      sink += shantenFromCounts(h).shanten;
    }
  }
  warm.stop();

  // 毎回メモを捨てる（4 色とも DP を計算し直す最悪の場合）
  const noMemoCount = 2000;
  final noMemo = Stopwatch();
  for (var i = 0; i < noMemoCount; i++) {
    clearShantenCache();
    noMemo.start();
    sink += shantenFromCounts(hands[i]).shanten;
    noMemo.stop();
  }

  stdout.writeln('シャンテン数（総合、ランダム 13/14 枚 $handCount 手）');
  stdout.writeln(
    '  メモなし  : ${_perCallMicros(noMemo, noMemoCount).toStringAsFixed(2)} µs/回',
  );
  stdout.writeln(
    '  メモ空から: ${_perCallMicros(cold, handCount).toStringAsFixed(2)} µs/回',
  );
  stdout.writeln(
    '  メモ済み  : ${_perCallMicros(warm, handCount * 5).toStringAsFixed(2)} µs/回',
  );

  // 14 枚の候補順位（各打牌のシャンテン + 受け入れ）
  const rankCount = 2000;
  final rankHands = [
    for (var i = 0; i < rankCount; i++)
      HandState(counts: _randomCounts(random, 14)),
  ];
  clearShantenCache();
  final rank = Stopwatch()..start();
  for (final h in rankHands) {
    sink += rankDiscards(h).length;
  }
  rank.stop();
  stdout.writeln('候補順位（ランダム 14 枚 $rankCount 手、メモ空から）');
  stdout.writeln(
    '  ${(rank.elapsedMicroseconds / rankCount / 1000).toStringAsFixed(3)} ms/回',
  );

  // 2 段階先の目安: 打牌 × ツモ × 受け入れ判定 ≈ 14×34×34 回のシャンテン
  const deepCount = 50;
  var deepCalls = 0;
  clearShantenCache();
  final deep = Stopwatch()..start();
  for (var i = 0; i < deepCount; i++) {
    final counts = List<int>.of(rankHands[i].counts);
    for (var d = 0; d < kTileKinds; d++) {
      if (counts[d] == 0) continue;
      counts[d]--;
      for (var t = 0; t < kTileKinds; t++) {
        if (counts[t] == 4) continue;
        counts[t]++;
        for (var u = 0; u < kTileKinds; u++) {
          if (counts[u] == 0) continue;
          counts[u]--;
          sink += shantenFromCounts(counts).shanten;
          deepCalls++;
          counts[u]++;
        }
        counts[t]--;
      }
      counts[d]++;
    }
  }
  deep.stop();
  stdout.writeln(
    '2 段階先の目安（14 枚 $deepCount 手、1 手あたり平均 ${deepCalls ~/ deepCount} 回）',
  );
  stdout.writeln(
    '  ${(deep.elapsedMicroseconds / deepCount / 1000).toStringAsFixed(1)} ms/手',
  );
  if (sink == 42) stdout.writeln('');
}
