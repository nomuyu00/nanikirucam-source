// 文脈つき和了採点（WinScorer.score）の速さを測る。
//   dart run tool/bench_win_scorer.dart            （JIT）
//   dart compile exe tool/bench_win_scorer.dart -o /tmp/bench_win && /tmp/bench_win   （AOT）
// 入力は突合フィクスチャ（test/fixtures/score_crosscheck.txt）の全件と、分け方の多い重い手。
import 'dart:io';

import 'package:mahjong_core/mahjong_core.dart';

List<String> _mpsz(String s) {
  if (s == '-') return const [];
  final out = <String>[];
  final digits = <String>[];
  for (final ch in s.split('')) {
    if ('mpsz'.contains(ch)) {
      out.addAll(digits.map((d) => '$d$ch'));
      digits.clear();
    } else {
      digits.add(ch);
    }
  }
  return out;
}

const _kinds = {
  'c': CalledMeldType.chi,
  'p': CalledMeldType.pon,
  'm': CalledMeldType.minkan,
  'a': CalledMeldType.ankan,
  'k': CalledMeldType.kakan,
};

List<WinRequest> _loadFixture(String path) {
  final requests = <WinRequest>[];
  for (final line in File(path).readAsLinesSync()) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final f = line.split(' ');
    if (f[0] != 'A') continue;
    final ctx = f[4].split(',');
    requests.add(
      WinRequest(
        handTiles: _mpsz(f[1]),
        melds: f[2] == '-'
            ? const []
            : [
                for (final m in f[2].split(','))
                  CalledMeld(_kinds[m[0]]!, _mpsz(m.substring(1))),
              ],
        winningTile: f[3],
        winType: ctx[0] == 'T' ? WinType.tsumo : WinType.ron,
        roundWind: Wind.values[int.parse(ctx[1]) - 1],
        seatWind: Wind.values[int.parse(ctx[2]) - 1],
        honba: int.parse(ctx[3]),
        kyotaku: int.parse(ctx[4]),
        riichi: ctx[5].contains('r'),
        doubleRiichi: ctx[5].contains('d'),
        ippatsu: ctx[5].contains('i'),
        haitei: ctx[5].contains('h'),
        houtei: ctx[5].contains('H'),
        rinshan: ctx[5].contains('n'),
        chankan: ctx[5].contains('c'),
        tenhou: ctx[5].contains('t'),
        chiihou: ctx[5].contains('j'),
        doraIndicators: _mpsz(f[5]),
        uraDoraIndicators: _mpsz(f[6]),
      ),
    );
  }
  return requests;
}

/// 分け方・和了牌の取り方が多い手（清一色の多面待ちなど）。
final _heavy = [
  WinRequest(
    handTiles: _mpsz('11122233344455m'),
    winningTile: '2m',
    winType: WinType.ron,
    riichi: true,
  ),
  WinRequest(
    handTiles: _mpsz('22334455667788p'),
    winningTile: '5p',
    winType: WinType.tsumo,
  ),
  WinRequest(
    handTiles: _mpsz('11112345678999s'),
    winningTile: '1s',
    winType: WinType.tsumo,
  ),
  WinRequest(
    handTiles: _mpsz('11223344556677m'),
    winningTile: '4m',
    winType: WinType.ron,
  ),
];

void main(List<String> args) {
  final scorer = WinScorer(Rulesets.mLeague());
  final requests = _loadFixture(
    args.isNotEmpty ? args.first : 'test/fixtures/score_crosscheck.txt',
  );
  // 温める
  for (final r in requests.take(2000)) {
    scorer.score(r);
  }
  var worst = 0;
  WinRequest? worstRequest;
  final sw = Stopwatch()..start();
  for (final r in requests) {
    final t = sw.elapsedMicroseconds;
    scorer.score(r);
    final d = sw.elapsedMicroseconds - t;
    if (d > worst) {
      worst = d;
      worstRequest = r;
    }
  }
  sw.stop();
  stdout.writeln(
    'fixture ${requests.length} 件: 平均 '
    '${(sw.elapsedMicroseconds / requests.length).toStringAsFixed(1)} µs/回, '
    '最大 $worst µs (${worstRequest?.handTiles.join()})',
  );
  for (final r in _heavy) {
    const n = 5000;
    final s = Stopwatch()..start();
    late WinOutcome o;
    for (var i = 0; i < n; i++) {
      o = scorer.score(r);
    }
    s.stop();
    final alt = o is WinScored ? o.alternatives.length : -1;
    stdout.writeln(
      '${r.handTiles.join()} 和了 ${r.winningTile}: '
      '${(s.elapsedMicroseconds / n).toStringAsFixed(1)} µs/回（次善 $alt 件）',
    );
  }
}
