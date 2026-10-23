// 上がりやすさの表（設計書 4.6.3）をシミュレーションで作る。
//
// 1 人打ち（他家・ロン・他家の捨て牌なし）で、136 枚の山をシャッフルして 13 枚配り、
// 1〜18 巡目に「ツモ → 和了なら終了 → rankDiscards の速さ軸 1 位から打牌」を繰り返す。
// 各巡目の打牌後に (シャンテン数, 受け入れ合計, 巡目) を記録し、その局で最終的に
// 和了できたかを集計して `lib/src/engine/win_ease_table.g.dart` を書き出す。
//
// 使い方（パッケージのルートで。長い実行は exe にすると速い）:
//   dart run tool/sim_win_ease.dart --games 20000                 # 動作確認
//   dart compile exe tool/sim_win_ease.dart -o <exe の出力先>      # リポジトリには残さない
//   <exe> --games 1000000 --seed 20261021 --raw-out <raw.txt>
//   <exe> --raw-in <raw.txt>                                      # 集計済みの標本から表だけ作り直す
//
// 引数: --games N（局数）--seed S --workers W（Isolate 数、既定は CPU 数）
//       --chunk N（乱数を分ける単位、既定 1000）--out パス --min-samples N（既定 300）
//       --kokushi own|all（国士型の表を国士型の標本だけで作る（既定）／全標本の表を使う）
//       --raw-out パス / --raw-in パス（細かい標本をテキストで保存・読み込み）
//
// 結果は局数・シード・chunk だけで決まり、workers には依存しない（chunk ごとに乱数を作る）。
//
// 表は手の形ごと（一般形・七対子・国士）。標本の形は、打牌後の 13 枚の `shanten(...)` が返す
// type（最小のシャンテン数を出した形。同値なら一般形 > 七対子 > 国士）で分ける。
// 表ごとの作り方:
//   1. 標本を (シャンテン 0,1,2,3 以上) × (受け入れ合計の区分) × (巡目 1〜17) に集計する。
//   2. 標本が min-samples 未満のセルは、同じシャンテン・巡目で左右の十分なセルの間を受け入れ枚数で
//      線形補間して補う（左端より下は「受け入れ 0 枚なら 0」との補間、右端より上は端の値）。
//      七対子型は受け入れがシャンテンごとにほぼ 1 点に集中するので、その点の値を軸にした補間になる。
//      テンパイのセルは、待ちを引き続けるだけの手計算を下限にする。
//   3. 単調性（受け入れ↑で上がる・巡目↑で下がる・シャンテン↑で下がる）を、重み付き最小二乗の
//      単調回帰（Dykstra 法）で揃える。テンパイで受け入れ 0 枚と、残りツモがシャンテン数 + 1 回
//      未満のセルは構造上 0 に固定する。
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:mahjong_core/src/engine/discard_ranker.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';

/// 流局までのツモ回数（18 巡目まで）。
const int _drawTurns = 18;

/// 標本を取る巡目 1〜17（18 巡目の打牌後は残りツモ 0 なので常に 0）。
const int _sampleTurns = 17;

/// 細かい標本の次元。シャンテンは 7 以上、受け入れは 127 以上を端にまとめる。
const int _rawShanten = 8;
const int _rawUkeire = 128;

/// 手の形（[ShantenType] の添字: 0 一般形、1 七対子、2 国士）。最小のシャンテン数を出した形。
const int _rawTypes = 3;
const int _rawSize = _rawTypes * _rawShanten * _rawUkeire * _sampleTurns;

/// 出力する表のシャンテン区分（0, 1, 2, 3 以上）。
const int _tableShanten = 4;

/// 受け入れ合計の区分の下限。最後の区分は上限なし。
const List<int> _ukeireLower = [
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, //
  18, 20, 22, 24, 26, 28, 30, 33, 36, 39, 42, 46, 50, 55, 60, 66, 72, 80, 90,
];

int _rawIndex(int type, int s, int u, int t) =>
    ((type * _rawShanten + s) * _rawUkeire + u) * _sampleTurns + (t - 1);

int _ukeireBin(int u) {
  var bin = 0;
  for (var i = 0; i < _ukeireLower.length; i++) {
    if (_ukeireLower[i] <= u) bin = i;
  }
  return bin;
}

class _Options {
  int games = 1000000;
  int seed = 20261021;
  int workers = Platform.numberOfProcessors;
  int chunk = 1000;
  int minSamples = 300;

  /// 国士型の表を国士型の標本だけで作るか（false なら全標本の表を国士型にも使う）。
  bool kokushiOwn = true;
  String out = 'lib/src/engine/win_ease_table.g.dart';
  String? rawOut;
  String? rawIn;

  _Options(List<String> args) {
    for (var i = 0; i < args.length; i++) {
      final key = args[i];
      String value() {
        if (i + 1 >= args.length) throw ArgumentError('$key に値がない');
        return args[++i];
      }

      switch (key) {
        case '--games':
          games = int.parse(value());
        case '--seed':
          seed = int.parse(value());
        case '--workers':
          workers = int.parse(value());
        case '--chunk':
          chunk = int.parse(value());
        case '--min-samples':
          minSamples = int.parse(value());
        case '--kokushi':
          final v = value();
          if (v != 'own' && v != 'all') {
            throw ArgumentError('--kokushi は own か all');
          }
          kokushiOwn = v == 'own';
        case '--out':
          out = value();
        case '--raw-out':
          rawOut = value();
        case '--raw-in':
          rawIn = value();
        default:
          throw ArgumentError('知らない引数: $key');
      }
    }
    if (workers < 1) workers = 1;
  }
}

/// 細かい標本（シャンテン × 受け入れ × 巡目）。
class _Raw {
  final Uint32List samples;
  final Uint32List wins;
  int games;
  int seed;
  _Raw(this.samples, this.wins, {required this.games, required this.seed});

  factory _Raw.empty() =>
      _Raw(Uint32List(_rawSize), Uint32List(_rawSize), games: 0, seed: 0);

  void add(Uint32List s, Uint32List w) {
    for (var i = 0; i < _rawSize; i++) {
      samples[i] += s[i];
      wins[i] += w[i];
    }
  }

  void save(String path) {
    final buffer = StringBuffer('# games $games seed $seed\n');
    buffer.writeln('# type shanten ukeire turn samples wins');
    for (var k = 0; k < _rawTypes; k++) {
      for (var s = 0; s < _rawShanten; s++) {
        for (var u = 0; u < _rawUkeire; u++) {
          for (var t = 1; t <= _sampleTurns; t++) {
            final i = _rawIndex(k, s, u, t);
            if (samples[i] == 0) continue;
            buffer.writeln('$k $s $u $t ${samples[i]} ${wins[i]}');
          }
        }
      }
    }
    File(path).writeAsStringSync(buffer.toString());
  }

  factory _Raw.load(String path) {
    final raw = _Raw.empty();
    for (final line in File(path).readAsLinesSync()) {
      if (line.startsWith('# games')) {
        final parts = line.split(' ');
        raw.games = int.parse(parts[2]);
        raw.seed = int.parse(parts[4]);
        continue;
      }
      if (line.startsWith('#')) continue;
      final p = line.split(' ').map(int.parse).toList();
      final i = _rawIndex(p[0], p[1], p[2], p[3]);
      raw.samples[i] = p[4];
      raw.wins[i] = p[5];
    }
    return raw;
  }

  /// [types] の形の標本数の合計。
  int totalSamples(Set<int> types) {
    const perType = _rawShanten * _rawUkeire * _sampleTurns;
    var sum = 0;
    for (final k in types) {
      for (var i = k * perType; i < (k + 1) * perType; i++) {
        sum += samples[i];
      }
    }
    return sum;
  }
}

// ---------------------------------------------------------------------------
// シミュレーション

class _Job {
  final SendPort port;
  final int worker, workers, games, chunk, seed;
  _Job(this.port, this.worker, this.workers, this.games, this.chunk, this.seed);
}

class _Done {
  final Uint32List samples;
  final Uint32List wins;
  _Done(this.samples, this.wins);
}

/// chunk 番号ごとに独立した乱数を作る（splitmix64）。
int _mixSeed(int seed, int chunk) {
  var x = seed + (chunk + 1) * -7046029254386353131; // 0x9E3779B97F4A7C15
  x = (x ^ (x >>> 30)) * -4658895280553007687; // 0xBF58476D1CE4E5B9
  x = (x ^ (x >>> 27)) * -7723592293110705685; // 0x94D049BB133111EB
  x = x ^ (x >>> 31);
  return x & 0x7fffffffffffffff;
}

void _workerMain(_Job job) {
  final samples = Uint32List(_rawSize);
  final wins = Uint32List(_rawSize);
  final wall = List<int>.filled(136, 0);
  final chunks = (job.games + job.chunk - 1) ~/ job.chunk;
  for (var c = job.worker; c < chunks; c += job.workers) {
    final random = Random(_mixSeed(job.seed, c));
    for (var i = 0; i < 136; i++) {
      wall[i] = i;
    }
    final n = min(job.chunk, job.games - c * job.chunk);
    for (var g = 0; g < n; g++) {
      _playGame(random, wall, samples, wins);
    }
    job.port.send(n);
  }
  job.port.send(_Done(samples, wins));
}

/// 1 局。山の先頭 13 枚が配牌、14 枚目以降が 1 巡目からのツモ。
void _playGame(
  Random random,
  List<int> wall,
  Uint32List samples,
  Uint32List wins,
) {
  // 配牌 13 枚 + ツモ 18 枚 = 先頭 31 枚だけシャッフルすれば十分。
  for (var i = 0; i < 13 + _drawTurns; i++) {
    final j = i + random.nextInt(136 - i);
    final tmp = wall[i];
    wall[i] = wall[j];
    wall[j] = tmp;
  }
  final counts = List<int>.filled(kTileKinds, 0);
  for (var i = 0; i < 13; i++) {
    counts[wall[i] >> 2]++;
  }
  var hand = HandState(counts: counts);
  final recorded = <int>[];
  var won = false;
  for (var turn = 1; turn <= _drawTurns; turn++) {
    final next = List<int>.of(hand.counts);
    next[wall[12 + turn] >> 2]++;
    if (shantenFromCounts(next).shanten < 0) {
      won = true;
      break;
    }
    if (turn == _drawTurns) break;
    final hand14 = hand.copyWith(counts: next, turn: turn);
    final ranked = rankDiscards(hand14);
    final best = [
      for (final c in ranked)
        if (c.rankByAxis[StrategyAxis.speed] == 1) c,
    ];
    final pick = best[best.length == 1 ? 0 : random.nextInt(best.length)];
    hand = hand14.discard(pick.discardId);
    final s = min(max(pick.shantenAfter, 0), _rawShanten - 1);
    final u = min(pick.ukeire.total, _rawUkeire - 1);
    final type = shantenFromCounts(hand.counts).type.index;
    recorded.add(_rawIndex(type, s, u, turn));
  }
  for (final i in recorded) {
    samples[i]++;
    if (won) wins[i]++;
  }
}

Future<_Raw> _simulate(_Options opts) async {
  final stopwatch = Stopwatch()..start();
  final progress = ReceivePort();
  final raw = _Raw.empty()
    ..games = opts.games
    ..seed = opts.seed;
  var finished = 0;
  var gamesDone = 0;
  var nextReport = 0.1;
  final allDone = Completer<void>();
  progress.listen((message) {
    if (message is int) {
      gamesDone += message;
      if (gamesDone / opts.games >= nextReport) {
        stdout.writeln(
          '  $gamesDone / ${opts.games} 局 '
          '(${stopwatch.elapsed.inSeconds} 秒)',
        );
        nextReport += 0.1;
      }
    } else if (message is _Done) {
      raw.add(message.samples, message.wins);
      if (++finished == opts.workers) allDone.complete();
    }
  });
  for (var w = 0; w < opts.workers; w++) {
    await Isolate.spawn(
      _workerMain,
      _Job(
        progress.sendPort,
        w,
        opts.workers,
        opts.games,
        opts.chunk,
        opts.seed,
      ),
    );
  }
  await allDone.future;
  progress.close();
  stdout.writeln(
    '${opts.games} 局、標本 ${raw.totalSamples({0, 1, 2})} 件、'
    '${stopwatch.elapsed.inSeconds} 秒（${opts.workers} 並列）',
  );
  return raw;
}

// ---------------------------------------------------------------------------
// 表の作成

class _Table {
  /// 区分ごとの標本数・和了数・補った後の率・最終値（1/10000 単位）。
  final int bins = _ukeireLower.length;
  late final Float64List n = Float64List(_tableShanten * bins * _sampleTurns);
  late final Float64List w = Float64List(_tableShanten * bins * _sampleTurns);
  late final Float64List estimate = Float64List(
    _tableShanten * bins * _sampleTurns,
  );
  late final Float64List weight = Float64List(
    _tableShanten * bins * _sampleTurns,
  );
  late final Int32List value = Int32List(_tableShanten * bins * _sampleTurns);
  late final List<bool> imputed = List<bool>.filled(
    _tableShanten * bins * _sampleTurns,
    false,
  );

  int idx(int s, int b, int t) => (s * bins + b) * _sampleTurns + t;
  int get size => n.length;

  /// 値を 0 に固定したセル（構造上和了できない）。
  late final List<bool> pinned = List<bool>.filled(
    _tableShanten * bins * _sampleTurns,
    false,
  );

  int pinnedCount = 0;

  /// 標本が minSamples 未満で隣接セルから補ったセル（うち標本ゼロ、近傍から借りたもの）。
  int imputedCount = 0;
  int emptyCount = 0;
  int unknownCount = 0;

  /// 標本が十分なセルのうち、単調性の補正で動いたもの（0.5 ポイント以上 / 0.005 ポイント以上）。
  int reliableCount = 0;
  int adjustedBig = 0;
  int adjustedAny = 0;
  double adjustedMax = 0;
  double adjustedMeanWeighted = 0;

  /// 補ったセルのうち、単調性の補正で 0.5 ポイント以上動いたもの。
  int imputedAdjustedBig = 0;

  /// テンパイの手計算（下限）に引き上げたセル（0.5 ポイント以上）。
  int floorRaisedReliable = 0;
  int floorRaisedImputed = 0;
  int repaired = 0;
}

/// テンパイで受け入れ [ukeire] 枚のまま [turn] 巡目の打牌後から引き続けたときの和了率。
/// 他家なしの山は 123 - 巡目 枚から 1 枚ずつ減る（受け入れの割合 = 受け入れ / 山）。
double _naiveTenpai(double ukeire, int turn) {
  var miss = 1.0;
  for (var k = 0; k < _drawTurns - turn; k++) {
    miss *= 1 - min(1.0, ukeire / (123 - turn - k));
  }
  return 1 - miss;
}

_Table _buildTable(_Raw raw, _Options opts, Set<int> types) {
  final table = _Table();
  final bins = table.bins;

  // 1. 区分に集計
  for (final k in types) {
    for (var s = 0; s < _rawShanten; s++) {
      final ts = min(s, _tableShanten - 1);
      for (var u = 0; u < _rawUkeire; u++) {
        final b = _ukeireBin(u);
        for (var t = 1; t <= _sampleTurns; t++) {
          final i = table.idx(ts, b, t - 1);
          table.n[i] += raw.samples[_rawIndex(k, s, u, t)];
          table.w[i] += raw.wins[_rawIndex(k, s, u, t)];
        }
      }
    }
  }

  // 2. 0 に固定するセル: テンパイで受け入れ 0 枚（区分 0）と、残りツモがシャンテン数 + 1
  //    回に満たない（どう引いても和了できない）セル。標本でも 0 になっている。
  for (var s = 0; s < _tableShanten; s++) {
    for (var b = 0; b < bins; b++) {
      for (var t = 0; t < _sampleTurns; t++) {
        final drawsLeft = _drawTurns - (t + 1);
        if ((s == 0 && b == 0) || drawsLeft < s + 1) {
          table.pinned[table.idx(s, b, t)] = true;
          table.pinnedCount++;
        }
      }
    }
  }

  // 3. 標本の少ないセルを隣接セルで補う。
  //    (a) 同じシャンテン・巡目で、標本が十分な左右のセルの間を受け入れ枚数で線形補間する
  //        （左端より下は「受け入れ 0 枚なら率 0」の点との補間、右端より上は端の値を保つ）。
  //    (b) その行（シャンテン・巡目）に標本が十分なセルが 1 つも無いときは、同じシャンテン・
  //        同じ受け入れ区分で、(a) で補えた近い巡目の行の間を巡目で線形補間する（端は端の値）。
  //    (c) シャンテン全体で (a) の行が 1 つも無いときだけ、受け入れ区分・巡目 ±r の窓の平均、
  //        それも無ければ同じシャンテンで最も近い既知セルの値を借りる。
  const maxRadius = 8;
  final known = List<bool>.filled(table.size, false);
  final rowResolved = List<bool>.filled(_tableShanten * _sampleTurns, false);
  double binCenter(int b) {
    final lower = _ukeireLower[b];
    final upper = b + 1 < bins ? _ukeireLower[b + 1] - 1 : lower + 2;
    return (lower + upper) / 2;
  }

  for (var s = 0; s < _tableShanten; s++) {
    for (var t = 0; t < _sampleTurns; t++) {
      final reliable = <int>[
        for (var b = 0; b < bins; b++)
          if (!table.pinned[table.idx(s, b, t)] &&
              table.n[table.idx(s, b, t)] >= opts.minSamples)
            b,
      ];
      rowResolved[s * _sampleTurns + t] = reliable.isNotEmpty;
      double rate(int r) {
        final j = table.idx(s, r, t);
        return table.w[j] / table.n[j];
      }

      for (var b = 0; b < bins; b++) {
        final i = table.idx(s, b, t);
        if (table.pinned[i]) {
          known[i] = true;
          continue;
        }
        if (table.n[i] >= opts.minSamples) {
          table.estimate[i] = table.w[i] / table.n[i];
          known[i] = true;
          continue;
        }
        table.imputed[i] = true;
        table.imputedCount++;
        if (table.n[i] == 0) table.emptyCount++;
        if (reliable.isEmpty) continue;
        int? left, right;
        for (final r in reliable) {
          if (r < b) left = r;
          if (r > b && right == null) right = r;
        }
        final xl = left == null ? 0.0 : binCenter(left);
        final yl = left == null ? 0.0 : rate(left);
        if (right == null) {
          table.estimate[i] = yl;
        } else {
          final xr = binCenter(right);
          final f = ((binCenter(b) - xl) / (xr - xl)).clamp(0.0, 1.0);
          table.estimate[i] = yl + (rate(right) - yl) * f;
        }
        known[i] = true;
      }
    }
  }
  // (b) 標本が十分なセルが無い行は、近い巡目の補えた行から巡目方向に補間する。
  for (var s = 0; s < _tableShanten; s++) {
    for (var t = 0; t < _sampleTurns; t++) {
      if (rowResolved[s * _sampleTurns + t]) continue;
      int? before, after;
      for (var u = 0; u < _sampleTurns; u++) {
        if (!rowResolved[s * _sampleTurns + u]) continue;
        if (u < t) before = u;
        if (u > t && after == null) after = u;
      }
      if (before == null && after == null) continue;
      for (var b = 0; b < bins; b++) {
        final i = table.idx(s, b, t);
        if (known[i]) continue;
        if (before == null || after == null) {
          table.estimate[i] = table.estimate[table.idx(s, b, before ?? after!)];
        } else {
          final y0 = table.estimate[table.idx(s, b, before)];
          final y1 = table.estimate[table.idx(s, b, after)];
          table.estimate[i] = y0 + (y1 - y0) * (t - before) / (after - before);
        }
        known[i] = true;
      }
    }
  }
  // (c) シャンテン全体に補える行が無いときの窓の平均。
  for (var s = 0; s < _tableShanten; s++) {
    for (var b = 0; b < bins; b++) {
      for (var t = 0; t < _sampleTurns; t++) {
        final i = table.idx(s, b, t);
        if (known[i]) continue;
        double sumN = 0, sumW = 0;
        for (var r = 1; r <= maxRadius; r++) {
          sumN = 0;
          sumW = 0;
          for (var db = max(0, b - r); db <= min(bins - 1, b + r); db++) {
            for (
              var dt = max(0, t - r);
              dt <= min(_sampleTurns - 1, t + r);
              dt++
            ) {
              final j = table.idx(s, db, dt);
              sumN += table.n[j];
              sumW += table.w[j];
            }
          }
          if (sumN >= opts.minSamples) break;
        }
        if (sumN > 0) {
          table.estimate[i] = sumW / sumN;
          known[i] = true;
        }
      }
    }
  }
  // 窓にも標本が 1 つも無いセルは、同じシャンテンで最も近い既知セルの値を借りる。
  for (var s = 0; s < _tableShanten; s++) {
    for (var b = 0; b < bins; b++) {
      for (var t = 0; t < _sampleTurns; t++) {
        final i = table.idx(s, b, t);
        if (known[i]) continue;
        table.unknownCount++;
        var bestDist = 1 << 30;
        var sum = 0.0;
        var count = 0;
        for (var db = 0; db < bins; db++) {
          for (var dt = 0; dt < _sampleTurns; dt++) {
            final j = table.idx(s, db, dt);
            if (!known[j]) continue;
            final d = max((db - b).abs(), (dt - t).abs());
            if (d < bestDist) {
              bestDist = d;
              sum = 0;
              count = 0;
            }
            if (d == bestDist) {
              sum += table.estimate[j];
              count++;
            }
          }
        }
        table.estimate[i] = count == 0 ? 0 : sum / count;
      }
    }
  }
  // テンパイのセルは、待ちを引き続けるだけの手計算（待ちを替えても下がらないので下限）
  // を下回らない。標本の端を保つだけでは、国士の十三面待ち（受け入れ 39 枚）などが低すぎるし、
  // 受け入れ 12 枚以上の標本の少ないセルは、手計算より標本の揺れの方が大きい。
  for (var b = 1; b < bins; b++) {
    for (var t = 0; t < _sampleTurns; t++) {
      final i = table.idx(0, b, t);
      if (table.pinned[i]) continue;
      final floor = _naiveTenpai(binCenter(b), t + 1);
      if (table.estimate[i] >= floor) continue;
      if (floor - table.estimate[i] >= 0.005) {
        if (table.imputed[i]) {
          table.floorRaisedImputed++;
        } else {
          table.floorRaisedReliable++;
        }
      }
      table.estimate[i] = floor;
    }
  }
  for (var i = 0; i < table.size; i++) {
    if (table.pinned[i]) {
      table.estimate[i] = 0;
      table.weight[i] = 1e9;
    } else {
      table.weight[i] = max(table.n[i], 1);
    }
  }

  // 4. 単調性（受け入れ↑で上がる、巡目↑で下がる、シャンテン↑で下がる）への最小補正。
  //    重み付き最小二乗の単調回帰を Dykstra 法（方向ごとの PAVA の交互射影）で解く。
  final x = Float64List.fromList(table.estimate);
  _monotoneProject(table, x);

  // 5. 補正量を数える（標本が十分なセルと、補ったセルを分ける）
  var weightedSum = 0.0;
  var weightTotal = 0.0;
  for (var i = 0; i < table.size; i++) {
    if (table.pinned[i]) continue;
    final d = (x[i] - table.estimate[i]).abs();
    if (table.imputed[i]) {
      if (d >= 0.005) table.imputedAdjustedBig++;
      continue;
    }
    table.reliableCount++;
    if (d >= 0.005) table.adjustedBig++;
    if (d >= 0.00005) table.adjustedAny++;
    if (d > table.adjustedMax) table.adjustedMax = d;
    weightedSum += d * table.n[i];
    weightTotal += table.n[i];
  }
  table.adjustedMeanWeighted = weightTotal == 0 ? 0 : weightedSum / weightTotal;

  // 6. 1/10000 に丸め、丸めで崩れた単調性だけ直す（下げる側を揃える）
  for (var i = 0; i < table.size; i++) {
    table.value[i] = (x[i].clamp(0.0, 1.0) * 10000).round();
  }
  table.repaired = _repairRounded(table);
  return table;
}

/// 方向ごとの [lo, hi] の組（value[lo] <= value[hi] が成り立つべき）を列挙する。
void _forEachPair(_Table table, void Function(int lo, int hi) f) {
  for (var s = 0; s < _tableShanten; s++) {
    for (var b = 0; b < table.bins; b++) {
      for (var t = 0; t < _sampleTurns; t++) {
        final i = table.idx(s, b, t);
        if (b > 0) f(table.idx(s, b - 1, t), i); // 受け入れが多いほど高い
        if (t > 0) f(i, table.idx(s, b, t - 1)); // 巡目が進むほど低い
        if (s > 0) f(i, table.idx(s - 1, b, t)); // シャンテンが大きいほど低い
      }
    }
  }
}

int _repairRounded(_Table table) {
  var repaired = 0;
  var changed = true;
  var guard = 0;
  while (changed && guard++ < 10000) {
    changed = false;
    _forEachPair(table, (lo, hi) {
      if (table.value[lo] > table.value[hi]) {
        table.value[lo] = table.value[hi];
        repaired++;
        changed = true;
      }
    });
  }
  return repaired;
}

/// [x] を重み付き最小二乗で 3 方向の単調性を満たす点に射影する（Dykstra 法）。
void _monotoneProject(_Table table, Float64List x) {
  final size = table.size;
  final bins = table.bins;
  final increments = [for (var k = 0; k < 3; k++) Float64List(size)];
  final z = Float64List(size);
  final line = Float64List(max(bins, max(_sampleTurns, _tableShanten)));
  final lineW = Float64List(line.length);
  final scratch = _Pava(line.length);

  // 方向 0: 受け入れ区分↑で非減少、1: 巡目↑で非増加、2: シャンテン↑で非増加
  void project(int dir, Float64List v) {
    final count = dir == 0 ? bins : (dir == 1 ? _sampleTurns : _tableShanten);
    final stride = dir == 0
        ? _sampleTurns
        : (dir == 1 ? 1 : bins * _sampleTurns);
    final increasing = dir == 0;
    // 各直線の開始位置
    for (var s = 0; s < _tableShanten; s++) {
      for (var b = 0; b < bins; b++) {
        for (var t = 0; t < _sampleTurns; t++) {
          final skip = switch (dir) {
            0 => b != 0,
            1 => t != 0,
            _ => s != 0,
          };
          if (skip) continue;
          final start = table.idx(s, b, t);
          for (var k = 0; k < count; k++) {
            final src = start + k * stride;
            final pos = increasing ? k : count - 1 - k;
            line[pos] = v[src];
            lineW[pos] = table.weight[src];
          }
          scratch.increasing(line, lineW, count);
          for (var k = 0; k < count; k++) {
            final pos = increasing ? k : count - 1 - k;
            v[start + k * stride] = line[pos];
          }
        }
      }
    }
  }

  for (var iter = 0; iter < 30000; iter++) {
    var change = 0.0;
    for (var k = 0; k < 3; k++) {
      final p = increments[k];
      for (var i = 0; i < size; i++) {
        z[i] = x[i] + p[i];
      }
      final projected = Float64List.fromList(z);
      project(k, projected);
      for (var i = 0; i < size; i++) {
        p[i] = z[i] - projected[i];
        final d = (projected[i] - x[i]).abs();
        if (d > change) change = d;
        x[i] = projected[i];
      }
    }
    if (change < 1e-13) break;
  }
}

/// 重み付き PAVA（非減少の単調回帰）。
class _Pava {
  final Float64List _value;
  final Float64List _weight;
  final Int32List _length;
  _Pava(int capacity)
    : _value = Float64List(capacity),
      _weight = Float64List(capacity),
      _length = Int32List(capacity);

  void increasing(Float64List v, Float64List w, int n) {
    var m = 0;
    for (var i = 0; i < n; i++) {
      _value[m] = v[i];
      _weight[m] = w[i];
      _length[m] = 1;
      m++;
      while (m > 1 && _value[m - 2] > _value[m - 1]) {
        final total = _weight[m - 2] + _weight[m - 1];
        _value[m - 2] =
            (_value[m - 2] * _weight[m - 2] + _value[m - 1] * _weight[m - 1]) /
            total;
        _weight[m - 2] = total;
        _length[m - 2] += _length[m - 1];
        m--;
      }
    }
    var k = 0;
    for (var b = 0; b < m; b++) {
      for (var j = 0; j < _length[b]; j++) {
        v[k++] = _value[b];
      }
    }
  }
}

// ---------------------------------------------------------------------------
// 出力

String _fmt(int v) => '${v ~/ 10000}.${(v % 10000).toString().padLeft(4, '0')}';

const List<String> _typeNames = ['一般形', '七対子', '国士'];

/// 出力する表 1 枚分（手の形ごと）。
class _Spec {
  /// 生成するコードの定数名。
  final String constName;

  /// 表の見出し（コメント用）。
  final String label;

  /// この表に使う標本の形（[ShantenType] の添字）。
  final Set<int> types;
  const _Spec(this.constName, this.label, this.types);
}

/// 手の形ごとの表。国士は標本が少ないので、[_Options.kokushiOwn] が false なら全標本の表を使う。
List<_Spec> _specs(_Options opts) => [
  const _Spec('kWinEaseTableStandard', '一般形（ShantenType.standard）', {0}),
  const _Spec('kWinEaseTableSevenPairs', '七対子（ShantenType.sevenPairs）', {1}),
  if (opts.kokushiOwn)
    const _Spec('kWinEaseTableKokushi', '国士（ShantenType.kokushi）', {2})
  else
    const _Spec('kWinEaseTableKokushi', '国士（標本が少ないので全標本の表）', {0, 1, 2}),
];

void _printReport(_Raw raw, _Spec spec, _Table table, _Options opts) {
  stdout.writeln('');
  stdout.writeln('==== ${spec.label} ====');
  stdout.writeln(
    '--- 手の形別の標本数: '
    '${[
      for (var k = 0; k < _rawTypes; k++) '${_typeNames[k]} ${raw.totalSamples({k})}',
    ].join('、')}'
    '（この表に使う形: ${[for (final k in spec.types) _typeNames[k]].join('・')}）---',
  );
  stdout.writeln('--- 標本の分布（この表に使う形、シャンテン別）---');
  for (var s = 0; s < _rawShanten; s++) {
    var total = 0;
    var wins = 0;
    var maxU = 0;
    final us = <int>{};
    for (final k in spec.types) {
      for (var u = 0; u < _rawUkeire; u++) {
        for (var t = 1; t <= _sampleTurns; t++) {
          final i = _rawIndex(k, s, u, t);
          if (raw.samples[i] > 0) {
            if (u > maxU) maxU = u;
            us.add(u);
          }
          total += raw.samples[i];
          wins += raw.wins[i];
        }
      }
    }
    if (total == 0) continue;
    stdout.writeln(
      '  シャンテン${s == _rawShanten - 1 ? "$s 以上" : s}: 標本 $total '
      '和了率 ${(wins / total).toStringAsFixed(3)} 受け入れ最大 $maxU（種類 ${us.length}）',
    );
  }
  stdout.writeln(
    '--- 標本数別のセル数（シャンテン別: 5000 以上 / 1000 以上 / ${opts.minSamples} 以上 / 1 以上 / 0）---',
  );
  for (var s = 0; s < _tableShanten; s++) {
    final c = [0, 0, 0, 0, 0];
    for (var b = 0; b < table.bins; b++) {
      for (var t = 0; t < _sampleTurns; t++) {
        final n = table.n[table.idx(s, b, t)];
        c[n >= 5000
            ? 0
            : n >= 1000
            ? 1
            : n >= opts.minSamples
            ? 2
            : n >= 1
            ? 3
            : 4]++;
      }
    }
    stdout.writeln('  シャンテン$s: ${c.join(" / ")}');
  }
  stdout.writeln(
    '--- セル数 ${table.size}: 0 に固定 ${table.pinnedCount}、'
    '標本 ${opts.minSamples} 以上 ${table.reliableCount}、'
    '標本 ${opts.minSamples} 未満を補った ${table.imputedCount}'
    '（標本ゼロ ${table.emptyCount}、窓にも標本が無く近傍から借りた ${table.unknownCount}）---',
  );
  stdout.writeln(
    '  単調性の補正（標本が十分なセル）: 0.5 ポイント以上 ${table.adjustedBig} セル、'
    '0.005 ポイント以上 ${table.adjustedAny} セル、最大 '
    '${(table.adjustedMax * 100).toStringAsFixed(2)} ポイント、'
    '標本数で重み付けした平均 ${(table.adjustedMeanWeighted * 100).toStringAsFixed(3)} ポイント'
    '（補ったセルで 0.5 ポイント以上 ${table.imputedAdjustedBig}、丸め後の修正 ${table.repaired} 回）',
  );
  stdout.writeln(
    '  テンパイの手計算（下限）に 0.5 ポイント以上引き上げたセル: '
    '標本十分 ${table.floorRaisedReliable}、補ったセル ${table.floorRaisedImputed}',
  );
  stdout.writeln('--- 代表値（和了率 %）行: シャンテン/受け入れ区分、列: 巡目 ---');
  const sampleTurnList = [1, 3, 6, 9, 12, 15, 17];
  stdout.writeln(
    '  s  受入       ${[for (final t in sampleTurnList) '$t'.padLeft(6)].join()}',
  );
  for (var s = 0; s < _tableShanten; s++) {
    for (var b = 0; b < table.bins; b++) {
      final nTurn6 = table.n[table.idx(s, b, 5)];
      if (nTurn6 < 100 && table.n[table.idx(s, b, 8)] < 100) continue;
      final lower = _ukeireLower[b];
      final upper = b + 1 < table.bins ? _ukeireLower[b + 1] - 1 : 999;
      final label = lower == upper
          ? '$lower'
          : '$lower-${upper == 999 ? "" : upper}';
      final cells = [
        for (final t in sampleTurnList)
          (table.value[table.idx(s, b, t - 1)] / 100)
              .toStringAsFixed(1)
              .padLeft(6),
      ];
      stdout.writeln('  $s  ${label.padRight(9)}  ${cells.join()}');
    }
  }
}

void _write(_Raw raw, List<_Spec> specs, List<_Table> tables, _Options opts) {
  final now = DateTime.now();
  final date =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';
  final all = raw.totalSamples({0, 1, 2});
  final shares = [
    for (var k = 0; k < _rawTypes; k++)
      '${_typeNames[k]} ${(raw.totalSamples({k}) * 100 / all).toStringAsFixed(1)}%',
  ].join('、');
  final buffer = StringBuffer()
    ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
    ..writeln('//')
    ..writeln('// 上がりやすさの表（設計書 4.6.3）。`tool/sim_win_ease.dart` が生成する。')
    ..writeln('// 生成日: $date')
    ..writeln(
      '// 再生成: dart run tool/sim_win_ease.dart --games ${raw.games} '
      '--seed ${raw.seed} --chunk ${opts.chunk} --min-samples ${opts.minSamples} '
      '--kokushi ${opts.kokushiOwn ? "own" : "all"}',
    )
    ..writeln(
      '// シード: ${raw.seed}  局数: ${raw.games}  標本数: $all'
      '（chunk ${opts.chunk}、局ごとの乱数は chunk 番号から作る）',
    )
    ..writeln('// 前提: 1 人打ち（他家・ロン・他家の捨て牌なし）。136 枚の山から 13 枚を配り、')
    ..writeln('//   1〜18 巡目に「ツモ → 和了なら終了 → rankDiscards の速さ軸 1 位から打牌')
    ..writeln('//   （シャンテン最小 → 受け入れ最大、同順位は乱数）」を繰り返す。')
    ..writeln('//   和了は形の完成（役の有無は見ない）。自分の河は見える牌に入れる。')
    ..writeln('// 値: 各巡目の打牌後の (シャンテン, 受け入れ合計) の手が、残りのツモ')
    ..writeln('//   （18 - 巡目 回）で和了できた割合。巡目 18 以降は 0（コード側で扱う）。')
    ..writeln('// 表は手の形ごと。標本の形は打牌後の 13 枚の `shanten(...)` が返す type')
    ..writeln('//   （最小のシャンテン数を出した形。同値なら一般形 > 七対子 > 国士）で分けた。')
    ..writeln('//   標本の形の割合: $shares。')
    ..writeln('// 補間と補正は表ごとに行う:')
    ..writeln('//   - 構造上 0 に固定: テンパイで受け入れ 0 枚、残りツモがシャンテン数 + 1 回未満。')
    ..writeln('//   - 標本 ${opts.minSamples} 未満のセルは、同じシャンテン・巡目で標本が十分な左右のセルの間を')
    ..writeln('//     受け入れ枚数で線形補間して補う。左端より下は「受け入れ 0 枚なら率 0」との補間、')
    ..writeln('//     右端より上は端の値を保つ。その行（シャンテン・巡目）に十分なセルが無ければ、')
    ..writeln('//     同じシャンテン・受け入れ区分で近い巡目の補えた行の間を巡目で補間する。')
    ..writeln('//   - テンパイのセルは、待ちを引き続けるだけの手計算（山は 123 - 巡目 - k 枚、')
    ..writeln('//     1 - Π(1 - 受け入れ / 山)。待ちを替えても下がらないので下限）を下回らない。')
    ..writeln('//     国士の十三面待ちなどが端の値で低すぎないように、受け入れ 12 枚以上の標本の揺れを')
    ..writeln('//     抑えるための処置で、標本が十分なセルでは受け入れ 8 枚以下ならほぼ働かない。')
    ..writeln('//   - 七対子型は受け入れがシャンテンごとにほぼ 1 点（0 向聴 3 枚、1 向聴 9 枚、')
    ..writeln('//     2 向聴 15 枚、3 向聴 21 枚。1 つ見えていれば −1 枚）に集中する。十分な標本があるのは')
    ..writeln('//     その点だけなので、他の受け入れの値は「その点に向かって受け入れに比例して下がる')
    ..writeln('//     （左側）／その点の値を保つ（右側）」補間になる。実際の七対子の手は集中点にほぼ')
    ..writeln('//     一致するので、補間の値はまず使われない。')
    ..writeln(
      opts.kokushiOwn
          ? '//   - 国士型は標本 ${raw.totalSamples({2})} 件（${(raw.totalSamples({2}) * 100 / all).toStringAsFixed(1)}%）、'
                '標本十分なセル ${tables[2].reliableCount}、単調性の補正が小さい（0.5 ポイント以上 ${tables[2].adjustedBig} セル）ので別表にした。'
          : '//   - 国士型は標本が少ないので、全標本（一般形・七対子・国士）の表を使う。',
    )
    ..writeln('//   - 単調性（受け入れ多いほど高い・巡目が進むほど低い・シャンテンが小さいほど高い）は')
    ..writeln('//     重み付き最小二乗の単調回帰（標本数で重み付け）で揃えた。');
  buffer.writeln('// 表ごとの内訳（セル ${tables.first.size}）:');
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final table = tables[i];
    buffer
      ..writeln(
        '//   ${spec.label}: 標本 ${raw.totalSamples(spec.types)}、'
        '0 に固定 ${table.pinnedCount}、標本十分 ${table.reliableCount}、'
        '補った ${table.imputedCount}（標本ゼロ ${table.emptyCount}、近傍から借りた ${table.unknownCount}）',
      )
      ..writeln(
        '//     手計算の下限に引き上げた（0.5 ポイント以上）: 標本十分 ${table.floorRaisedReliable} セル、'
        '補ったセル ${table.floorRaisedImputed} セル',
      )
      ..writeln(
        '//     単調性の補正: 標本十分なセルのうち 0.5 ポイント以上動いたのは ${table.adjustedBig} セル'
        '（0.005 ポイント以上 ${table.adjustedAny}、最大 '
        '${(table.adjustedMax * 100).toStringAsFixed(2)} ポイント、'
        '標本数で重み付けした平均 ${(table.adjustedMeanWeighted * 100).toStringAsFixed(3)} ポイント）',
      );
  }
  buffer
    ..writeln('// ignore_for_file: lines_longer_than_80_chars')
    ..writeln()
    ..writeln('// dart format off')
    ..writeln('/// 受け入れ合計枚数の区分の下限（昇順、先頭は 0）。最後の区分は上限なし。全部の表で共通。')
    ..writeln('const List<int> kWinEaseUkeireLowerBounds = [')
    ..writeln('  ${_ukeireLower.join(', ')},')
    ..writeln('];');
  for (var i = 0; i < specs.length; i++) {
    final spec = specs[i];
    final table = tables[i];
    buffer
      ..writeln()
      ..writeln(
        '/// ${spec.label}の表。添字は [シャンテン 0,1,2,3 以上][受け入れ区分][巡目 - 1]（巡目 1〜17）。',
      )
      ..writeln('const List<List<List<double>>> ${spec.constName} = [');
    for (var s = 0; s < _tableShanten; s++) {
      buffer.writeln('  [');
      for (var b = 0; b < table.bins; b++) {
        final row = [
          for (var t = 0; t < _sampleTurns; t++)
            _fmt(table.value[table.idx(s, b, t)]),
        ];
        buffer.writeln('    [${row.join(', ')}],');
      }
      buffer.writeln('  ],');
    }
    buffer.writeln('];');
  }
  buffer.writeln('// dart format on');
  File(opts.out).writeAsStringSync(buffer.toString());
  stdout.writeln('書き出し: ${opts.out}');
}

Future<void> main(List<String> args) async {
  final opts = _Options(args);
  final _Raw raw;
  if (opts.rawIn != null) {
    raw = _Raw.load(opts.rawIn!);
    stdout.writeln('標本を読み込み: ${opts.rawIn}（${raw.games} 局、シード ${raw.seed}）');
  } else {
    stdout.writeln('${opts.games} 局、シード ${opts.seed}、${opts.workers} 並列を開始');
    raw = await _simulate(opts);
  }
  if (opts.rawOut != null) {
    raw.save(opts.rawOut!);
    stdout.writeln('標本を保存: ${opts.rawOut}');
  }
  final specs = _specs(opts);
  final tables = [for (final spec in specs) _buildTable(raw, opts, spec.types)];
  for (var i = 0; i < specs.length; i++) {
    _printReport(raw, specs[i], tables[i], opts);
  }
  _write(raw, specs, tables, opts);
}
