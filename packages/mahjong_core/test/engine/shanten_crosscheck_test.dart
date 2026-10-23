import 'dart:io';

import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';
import 'package:mahjong_core/src/engine/ukeire.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';

// 期待値は ml/crosscheck_shanten.py が Python の mahjong ライブラリで出したもの。
// 形式はフィクスチャ先頭のコメントを参照。
const _fixturePath = 'test/fixtures/shanten_crosscheck.txt';

class _Case {
  final int lineNo;
  final List<int> counts;
  final String meldSpec;
  final int standard;
  final int? sevenPairs;
  final int? kokushi;
  final int total;
  final List<int>? ukeire;
  final String category;

  _Case(
    this.lineNo,
    this.counts,
    this.meldSpec,
    this.standard,
    this.sevenPairs,
    this.kokushi,
    this.total,
    this.ukeire,
    this.category,
  );

  String describe() =>
      '行$lineNo [$category] ${notationOfCounts(counts)}'
      '${meldSpec == '-' ? '' : ' 副露 $meldSpec'}';
}

List<int> _digits(String s) =>
    s.split('').map(int.parse).toList(growable: false);

List<_Case> _loadCases() {
  final lines = File(_fixturePath).readAsLinesSync();
  final cases = <_Case>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final f = line.split(' ');
    if (f.length != 8 || f[0].length != kTileKinds) {
      throw FormatException('フィクスチャ ${i + 1} 行目の形式が違う: $line');
    }
    int? opt(String v) => v == '-' ? null : int.parse(v);
    cases.add(
      _Case(
        i + 1,
        _digits(f[0]),
        f[1],
        int.parse(f[2]),
        opt(f[3]),
        opt(f[4]),
        int.parse(f[5]),
        f[6] == '-' ? null : _digits(f[6]),
        f[7],
      ),
    );
  }
  return cases;
}

void main() {
  final cases = _loadCases();

  test('フィクスチャは 10,000 手', () {
    expect(cases, hasLength(10000));
  });

  test('一般形・七対子・国士・総合・受け入れがライブラリと全件一致', () {
    final failures = <String>[];
    final byCategory = <String, int>{};
    var ukeireChecked = 0;
    for (final c in cases) {
      byCategory[c.category] = (byCategory[c.category] ?? 0) + 1;
      final hand = HandState(
        counts: c.counts,
        openMelds: meldsFromSpec(c.meldSpec),
      );
      final problems = <String>[];

      final std = standardShanten(c.counts, hand.meldCount);
      if (std != c.standard) problems.add('一般形 $std≠${c.standard}');
      if (c.sevenPairs != null) {
        final v = sevenPairsShanten(c.counts);
        if (v != c.sevenPairs) problems.add('七対子 $v≠${c.sevenPairs}');
      }
      if (c.kokushi != null) {
        final v = kokushiShanten(c.counts);
        if (v != c.kokushi) problems.add('国士 $v≠${c.kokushi}');
      }
      final total = shanten(hand).shanten;
      if (total != c.total) problems.add('総合 $total≠${c.total}');

      if (c.ukeire != null) {
        ukeireChecked++;
        final expected = <int, int>{
          for (var id = 0; id < kTileKinds; id++)
            if (c.ukeire![id] > 0) id: c.ukeire![id],
        };
        final actual = ukeire(hand).tiles;
        if (!_sameMap(actual, expected)) {
          problems.add('受け入れ ${_fmt(actual)}≠${_fmt(expected)}');
        }
      }
      if (problems.isNotEmpty) {
        failures.add('${c.describe()}: ${problems.join(', ')}');
      }
    }
    expect(
      failures,
      isEmpty,
      reason:
          '不一致 ${failures.length} 件（先頭 30 件）:\n'
          '${failures.take(30).join('\n')}',
    );
    // 全カテゴリが入っていて、受け入れも十分な数を照合していること
    expect(byCategory.keys, hasLength(9));
    expect(ukeireChecked, greaterThan(4000));
  });
}

bool _sameMap(Map<int, int> a, Map<int, int> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

String _fmt(Map<int, int> m) =>
    '{${m.entries.map((e) => '${labelOfId(e.key)}:${e.value}').join(' ')}}';
