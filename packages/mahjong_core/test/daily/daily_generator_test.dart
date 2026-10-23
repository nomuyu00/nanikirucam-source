// 今日の問題の生成器（DailyProblemGenerator）。決定性・手の正しさ・難易度の選別・速度。
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

List<String> _dates(String start, int days) {
  final first = DateTime.parse('${start}T00:00:00Z');
  return [
    for (var i = 0; i < days; i++) _dateKey(first.add(Duration(days: i))),
  ];
}

bool _splitOf(AnalysisReport report) {
  final sets = [
    for (final axis in StrategyAxis.values)
      (report.bestByAxis[axis] ?? const <int>[]).toSet(),
  ];
  return sets.any(
    (s) => s.length != sets.first.length || !s.containsAll(sets.first),
  );
}

void main() {
  group('DailyRandom / fnv1a32', () {
    test('FNV-1a 32 bit の既知の値', () {
      expect(fnv1a32(''), 0x811c9dc5);
      expect(fnv1a32('a'), 0xe40c292c);
      expect(fnv1a32('foobar'), 0xbf9cf968);
    });

    test('同じシードなら同じ列、違うシードなら違う列。値は 32 bit の範囲', () {
      List<int> take(String seed) {
        final r = DailyRandom.fromString(seed);
        return [for (var i = 0; i < 16; i++) r.nextUint32()];
      }

      final a = take('nanikiru-daily|v1|2026-10-22|1');
      expect(take('nanikiru-daily|v1|2026-10-22|1'), a);
      expect(take('nanikiru-daily|v1|2026-10-22|2'), isNot(a));
      for (final v in a) {
        expect(v, inInclusiveRange(0, 0xFFFFFFFF));
      }
      // 列そのものを固定する（変わったら kDailyGeneratorVersion を上げる）。
      expect(take('seed').take(4).toList(), _seedPrefix);
    });

    test('nextInt は 0 以上 max 未満で、偏りが小さい', () {
      final r = DailyRandom.fromString('dist');
      final counts = List<int>.filled(6, 0);
      for (var i = 0; i < 60000; i++) {
        counts[r.nextInt(6)]++;
      }
      for (final c in counts) {
        expect(c, inInclusiveRange(9400, 10600));
      }
      expect(() => r.nextInt(0), throwsRangeError);
    });
  });

  group('DailyProblemGenerator', () {
    test('同じ日付なら何度作っても（別の生成器でも）同じ 3 問', () {
      final a = DailyProblemGenerator().generate('2026-10-22');
      final b = DailyProblemGenerator().generate('2026-10-22');
      final generator = DailyProblemGenerator();
      final c = generator.generate('2026-10-22');
      final d = generator.generate('2026-10-22');
      expect(a, hasLength(kDailyProblemCount));
      expect(b, a);
      expect(c, a);
      expect(d, a);
    });

    test('1 問だけ作っても 3 問まとめて作ったものと同じ', () {
      final all = DailyProblemGenerator().generate('2026-11-03');
      for (var n = 1; n <= 3; n++) {
        expect(
          DailyProblemGenerator().generateOne('2026-11-03', n),
          all[n - 1],
        );
      }
    });

    test('2026-10-22 の 3 問は固定（変わったら kDailyGeneratorVersion を上げる）', () {
      final hands = DailyProblemGenerator().generate('2026-10-22');
      expect(kDailyGeneratorVersion, 1);
      expect([for (final h in hands) h.tiles.join(' ')], _golden20261022);
    });

    test('日付が変わると問題も変わる。3 問は互いに違う', () {
      final generator = DailyProblemGenerator();
      final seen = <String>{};
      for (final date in _dates('2026-10-01', 20)) {
        final hands = generator.generate(date);
        expect(hands.map((h) => h.date).toSet(), {date});
        expect([for (final h in hands) h.number], [1, 2, 3]);
        expect(
          [for (final h in hands) h.level],
          [DailyLevel.basic, DailyLevel.standard, DailyLevel.advanced],
        );
        for (final h in hands) {
          expect(seen.add(h.tiles.join()), isTrue, reason: '$h が重複');
        }
      }
    });

    test('どの日も必ず 3 問。14 枚・同じ牌は 4 枚まで・赤5は各色 1 枚まで・ツモ牌は末尾', () {
      final generator = DailyProblemGenerator();
      for (final date in _dates('2027-01-01', 60)) {
        final hands = generator.generate(date);
        expect(hands, hasLength(3));
        for (final h in hands) {
          expect(h.tiles, hasLength(14), reason: '$h');
          expect(h.tsumoIndex, 13);
          final counts = List<int>.filled(kTileKinds, 0);
          final reds = <String>{};
          for (final label in h.tiles) {
            final id = tileIdFromLabel(label);
            expect(id, inInclusiveRange(0, 33), reason: label);
            counts[id]++;
            if (label.startsWith('0')) {
              expect(reds.add(label), isTrue, reason: '赤5が 2 枚: $h');
            }
          }
          // ドラ表示牌も山の牌なので、合わせて 4 枚まで。
          counts[tileIdFromLabel(h.doraIndicator)]++;
          expect(counts.every((c) => c <= 4), isTrue, reason: '$h');
          // 先頭 13 枚は理牌済み（id の昇順。赤5は同じ 5 の先頭）。
          final head = [for (final t in h.tiles.take(13)) tileIdFromLabel(t)];
          expect(head, [...head]..sort(), reason: '$h');
          expect(h.turn, inInclusiveRange(5, 10));
          expect(h.roundWind, anyOf(Wind.east, Wind.south));
          expect(h.dealer, h.seatWind == Wind.east);
          expect(h.shanten, greaterThanOrEqualTo(0), reason: '和了形は出さない');
          expect(h.stage, inInclusiveRange(0, 3));
          final state = h.toHandState();
          expect(state.tileCount, 14);
          expect(shanten(state).shanten, h.shanten, reason: 'シャンテン数が手と合う');
        }
      }
    });

    test('難易度の条件: 基本・標準は割れない 1〜2 シャンテン、応用はほぼ必ず割れる', () {
      final generator = DailyProblemGenerator();
      final engine = DefaultNanikiruEngine();
      final dates = _dates('2026-12-01', 60);
      var advancedSplit = 0;
      var strict = 0;
      for (final date in dates) {
        final hands = generator.generate(date);
        for (final h in hands) {
          final report = engine.analyze(h.toHandState(), deep: false);
          expect(_splitOf(report), h.split, reason: '$h');
          if (h.stage == 0) strict++;
          if (h.level == DailyLevel.advanced) {
            if (h.split) advancedSplit++;
            continue;
          }
          if (h.stage == 0) {
            expect(h.split, isFalse, reason: '$h');
            expect(h.shanten, inInclusiveRange(1, 2), reason: '$h');
            final balance = report.bestByAxis[StrategyAxis.balance]!;
            if (h.level == DailyLevel.basic) {
              expect(balance, hasLength(1), reason: '基本は解が 1 枚: $h');
            }
            // 選ぶ余地がある（同じシャンテン数を保つ候補が 2 つ以上）。
            final keep = report.candidates
                .where((c) => c.shantenAfter == h.shanten)
                .length;
            expect(keep, greaterThan(balance.length), reason: '$h');
          }
        }
      }
      // 実測: 300 日で 3 問目は 300 日とも割れた（段階 0 が 297 日）。
      expect(advancedSplit / dates.length, greaterThanOrEqualTo(0.95));
      expect(strict / (dates.length * 3), greaterThanOrEqualTo(0.9));
    });

    test('速度: 1 日 3 問が数百 ms 以内（JIT のテストでの目安）', () {
      // 初回のシャンテン表の準備を除く。
      DailyProblemGenerator().generate('2026-01-01');
      final times = <int>[];
      for (final date in _dates('2026-02-01', 20)) {
        final watch = Stopwatch()..start();
        DailyProblemGenerator().generate(date);
        times.add(watch.elapsedMilliseconds);
      }
      times.sort();
      final mean = times.reduce((a, b) => a + b) / times.length;
      // ignore: avoid_print
      print(
        'daily 3 問: mean=${mean.toStringAsFixed(1)} ms '
        'median=${times[times.length ~/ 2]} ms max=${times.last} ms',
      );
      // AOT（端末に近い）では平均 38 ms・最大 113 ms（WSL、300 日）。JIT は遅いので緩める。
      expect(mean, lessThan(500));
    });

    test('日付の形式・問題番号が不正なら例外', () {
      final generator = DailyProblemGenerator();
      expect(() => generator.generate('2026/10/22'), throwsArgumentError);
      expect(() => generator.generateOne('2026-10-22', 0), throwsRangeError);
      expect(() => generator.generateOne('2026-10-22', 4), throwsRangeError);
    });
  });
}

const _seedPrefix = <int>[1327162122, 3359510752, 506033461, 1895205449];

const _golden20261022 = <String>[
  '4m 5m 6m 4p 0p 5p 7p 1s 0s 6s 7s 8s 9s 1z',
  '3m 4m 8m 9m 1p 1p 3p 4p 4s 5s 6s 6s 8s 2m',
  '2m 3m 3p 4p 5p 7p 8p 9p 7s 7s 7s 6z 6z 6z',
];
