// 今日の問題の生成器（DailyProblemGenerator）の速度と、条件を緩めた割合を測る。
//   dart run tool/bench_daily.dart [日数=200] [開始日=2026-10-22]      （JIT）
//   dart compile exe tool/bench_daily.dart -o /tmp/bench_daily && /tmp/bench_daily
//                                                （AOT、端末のリリースビルドに近い）
//
// 1 日ごとに新しい生成器（= 新しいエンジン、Isolate で毎回作る場合に近い）で 3 問作り、
// 1 日あたりの時間（平均・中央値・最大）、問題番号ごとの段階（stage）の分布、試行回数、
// 3 問目が 3 軸の割れる手になった割合、14 枚のシャンテン数の分布を出す。
import 'dart:io';

import 'package:mahjong_core/mahjong_core.dart';

void main(List<String> args) {
  final days = args.isNotEmpty ? int.parse(args[0]) : 200;
  var date = DateTime.utc(2026, 10, 22);
  if (args.length > 1) date = DateTime.parse('${args[1]}T00:00:00Z');

  String key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  final times = <int>[];
  final stages = List.generate(3, (_) => List<int>.filled(4, 0));
  final attempts = List<int>.filled(3, 0);
  final maxAttempts = List<int>.filled(3, 0);
  final shanten = List.generate(3, (_) => <int, int>{});
  var advancedSplit = 0;
  for (var i = 0; i < days; i++) {
    final watch = Stopwatch()..start();
    final hands = DailyProblemGenerator().generate(key(date));
    watch.stop();
    times.add(watch.elapsedMicroseconds);
    for (final h in hands) {
      final n = h.number - 1;
      stages[n][h.stage]++;
      attempts[n] += h.attempts;
      if (h.attempts > maxAttempts[n]) maxAttempts[n] = h.attempts;
      shanten[n].update(h.shanten, (v) => v + 1, ifAbsent: () => 1);
    }
    if (hands[2].split) advancedSplit++;
    if (i < 3) {
      for (final h in hands) {
        stdout.writeln(h);
      }
    }
    date = date.add(const Duration(days: 1));
  }
  times.sort();
  final mean = times.reduce((a, b) => a + b) / times.length / 1000;
  stdout
    ..writeln(
      'days=$days  3 問/日の時間 (ms): '
      'mean=${mean.toStringAsFixed(1)} '
      'median=${(times[times.length ~/ 2] / 1000).toStringAsFixed(1)} '
      'p95=${(times[(times.length * 0.95).floor()] / 1000).toStringAsFixed(1)} '
      'max=${(times.last / 1000).toStringAsFixed(1)}',
    )
    ..writeln('3 問目が割れる手: $advancedSplit / $days');
  for (var n = 0; n < 3; n++) {
    stdout.writeln(
      '${n + 1} 問目 ${DailyLevel.ofNumber(n + 1).name}: stage=${stages[n]} '
      'attempts mean=${(attempts[n] / days).toStringAsFixed(1)} max=${maxAttempts[n]} '
      'shanten=${shanten[n]}',
    );
  }
}
