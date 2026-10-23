// 2 段階先（設計書 4.5）。受け入れを引いた後の受け入れ平均と、改良の牌。
import 'dart:math';

import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'engine_test_utils.dart';
import 'route_test_utils.dart';

int _id(String label) => idsFromNotation(label).single;

String drawString(TwoStepDraw d) =>
    '${labelOfId(d.tileId)}x${d.remaining}${d.progress ? '' : '改良'}'
    ' 打${d.discards.map(labelOfId).join(',')} ${d.shantenAfter}/${d.ukeireAfter}';

/// [HandState] の公開 API だけで組んだ参照実装（メモなし）。
({double? average, List<String> draws}) referenceTwoStep(
  HandState hand,
  int d,
) {
  final after = afterDiscard(hand, d);
  final s = shanten(after).shanten;
  final base = ukeire(after).total;
  final draws = <String>[];
  var weight = 0;
  var sum = 0;
  for (var t = 0; t < kTileKinds; t++) {
    if (after.counts[t] >= 4) continue;
    final r = after.remaining(t);
    if (r == 0) continue;
    final counts = List<int>.of(after.counts);
    counts[t]++;
    final drawn = after.copyWith(counts: counts);
    final s14 = shanten(drawn).shanten;
    final progress = s14 < s;
    if (progress && s == 0) continue; // テンパイからの受け入れは和了
    final target = progress ? s14 : s;
    var best = -1;
    final discards = <int>[];
    for (var d2 = 0; d2 < kTileKinds; d2++) {
      if (drawn.counts[d2] == 0) continue;
      final h13 = drawn.discard(d2);
      if (shanten(h13).shanten != target) continue;
      final u = ukeire(h13).total;
      if (u > best) {
        best = u;
        discards
          ..clear()
          ..add(d2);
      } else if (u == best) {
        discards.add(d2);
      }
    }
    if (!progress && best <= base) continue;
    if (progress) {
      weight += r;
      sum += r * best;
    }
    draws.add(
      drawString(
        TwoStepDraw(
          tileId: t,
          remaining: r,
          progress: progress,
          discards: discards,
          shantenAfter: target,
          ukeireAfter: best,
        ),
      ),
    );
  }
  return (average: weight == 0 ? null : sum / weight, draws: draws);
}

void main() {
  group('手計算できる例', () {
    // 12m 456m 678p 23s 67s 99m（5 ブロックの一向聴）
    final hand = stateOf('12m 456m 678p 23s 67s 99m');
    final calc = TwoStepCalculator(hand);

    test('辺張を外す（打 1m）: 受け入れ 4 種どれを引いても両面テンパイ（8 枚）で平均 8', () {
      // 打 1m 後: 2m 456m 678p 23s 67s 99m。受け入れは 1s・4s（23s）と 5s・8s（67s）
      // の各 4 枚。1s・4s を引けば 2m を切って 67s の 5s・8s 待ち（8 枚）、5s・8s を
      // 引けば 2m を切って 23s の 1s・4s 待ち（8 枚）。平均 = 8。
      final r = calc.of(_id('1m'));
      expect(r.average, 8.0);
      final progress = r.draws.where((d) => d.progress).map(drawString);
      expect(progress, [
        '1sx4 打2m 0/8',
        '4sx4 打2m 0/8',
        '5sx4 打2m 0/8',
        '8sx4 打2m 0/8',
      ]);
    });

    test('両面を崩す（打 2s）: 3m を引けば両面、5s・8s を引けば辺張待ち。平均 16/3', () {
      // 打 2s 後: 12m 456m 678p 3s 67s 99m。受け入れは 3m（辺張）・5s・8s の各 4 枚。
      // 3m → 3s を切って 67s の両面（8 枚）。5s・8s → 3s を切って 12m の 3m 待ち（4 枚）。
      // 平均 = (4×8 + 4×4 + 4×4) / 12 = 16/3。
      final r = calc.of(_id('2s'));
      expect(r.average, closeTo(16 / 3, 1e-12));
      expect(r.draws.where((d) => d.progress).map(drawString), [
        '3mx4 打3s 0/8',
        '5sx4 打3s 0/4',
        '8sx4 打3s 0/4',
      ]);
    });

    test('テンパイの候補: 平均は null、改良は待ちが増える牌だけ', () {
      // 24m 111z 222z 333z 55z 7z の打 7z は 24m 嵌張の 3m 待ち（4 枚）。
      // 5m を引いて 2m を切ると 45m の 3m・6m 待ち（8 枚）で改良。1m（12m 辺張 4 枚）・
      // 2m・4m（シャンポン 2+2 枚）・6m（46m 嵌張 4 枚）・5z（単騎 3 枚）は 4 枚以下で改良でない。
      final r = TwoStepCalculator(
        stateOf('24m 111z 222z 333z 55z 7z'),
      ).of(_id('7z'));
      expect(r.average, isNull);
      expect(r.draws.map(drawString), ['5mx4改良 打2m 0/8']);
      expect(r.improvement.tiles, {_id('5m'): 4});
    });

    test('受け入れが同じ 2 候補では形の良い方が 2 段階先で上回る', () {
      // 22m 456m 23p 57p 34s 678s。打 7p（23p・34s の両面 2 つ）と打 2p（3p57p の両嵌 +
      // 34s）はどちらも受け入れ 16 枚。打 7p はどれを引いても両面テンパイで 8。打 2p は
      // 4p・6p（各 4 枚）なら 34s の両面で 8、2s・5s なら両嵌の片方の嵌張で 4、平均 6。
      final h = stateOf('22m 456m 23p 57p 34s 678s');
      final list = analyzeDiscards(h);
      final c7p = list.firstWhere((c) => c.discardId == _id('7p'));
      final c2p = list.firstWhere((c) => c.discardId == _id('2p'));
      expect(c7p.ukeire.total, 16);
      expect(c2p.ukeire.total, 16);
      expect(c7p.twoStepAverage, 8.0);
      expect(c2p.twoStepAverage, 6.0);
    });
  });

  group('性質', () {
    test('参照実装（HandState の API だけ、メモなし）と一致する', () {
      final random = Random(20261021);
      var compared = 0;
      for (var n = 0; n < 24; n++) {
        // 和了形に近い手（一向聴前後）と一様な手を交互に
        final counts = List<int>.filled(kTileKinds, 0);
        var left = 14;
        final range = n.isEven ? 18 : kTileKinds;
        while (left > 0) {
          final t = random.nextInt(range);
          if (counts[t] == 4) continue;
          counts[t]++;
          left--;
        }
        final visible = List<int>.filled(kTileKinds, 0);
        for (var k = 0; k < 5; k++) {
          final t = random.nextInt(kTileKinds);
          if (counts[t] + visible[t] < 4) visible[t]++;
        }
        final hand = HandState(counts: counts, visible: visible);
        final calc = TwoStepCalculator(hand);
        final ids = [
          for (var i = 0; i < kTileKinds; i++)
            if (counts[i] > 0) i,
        ]..shuffle(random);
        for (final d in ids.take(3)) {
          final got = calc.of(d);
          final want = referenceTwoStep(hand, d);
          final label = '${notationOfCounts(counts)} 打${labelOfId(d)}';
          expect(got.draws.map(drawString).toList(), want.draws, reason: label);
          if (want.average == null) {
            expect(got.average, isNull, reason: label);
          } else {
            expect(got.average, closeTo(want.average!, 1e-9), reason: label);
          }
          compared++;
        }
      }
      expect(compared, 72);
    });

    test('受け入れの残り枚数の合計は候補の受け入れ枚数、改良は受け入れより増える', () {
      final hand = stateOf('234m 567p 678s 33z 9m 3s 4z');
      final list = analyzeDiscards(hand);
      for (final c in list) {
        final ts = c.twoStep!;
        final progress = ts.draws.where((d) => d.progress);
        if (c.shantenAfter == 0) {
          expect(progress, isEmpty);
          expect(ts.average, isNull);
        } else {
          expect(
            progress.fold(0, (s, d) => s + d.remaining),
            c.ukeire.total,
            reason: labelOfId(c.discardId),
          );
          for (final d in progress) {
            expect(d.shantenAfter, c.shantenAfter - 1);
            expect(c.ukeire.tiles.containsKey(d.tileId), isTrue);
          }
        }
        for (final d in ts.draws.where((d) => !d.progress)) {
          expect(d.shantenAfter, c.shantenAfter);
          expect(d.ukeireAfter, greaterThan(c.ukeire.total));
          expect(c.ukeire.tiles.containsKey(d.tileId), isFalse);
        }
      }
    });

    test('副露した手も計算する（副露の牌は残り枚数から除く）', () {
      final hand = stateOf('12m 45p 67s 234s 99m', melds: 'pon:6z');
      final calc = TwoStepCalculator(hand);
      // 打 1m: 45p・67s の両面 2 つ。どれを引いても両面テンパイ（8 枚）
      expect(calc.of(_id('1m')).average, 8.0);
      final want = referenceTwoStep(hand, _id('4p'));
      expect(calc.of(_id('4p')).draws.map(drawString).toList(), want.draws);
    });

    test('14 枚でない手・手にない牌は ArgumentError', () {
      expect(
        () => TwoStepCalculator(stateOf('12m 456m 678p 23s 67s 9m')),
        throwsArgumentError,
      );
      final calc = TwoStepCalculator(stateOf('12m 456m 678p 23s 67s 99m'));
      expect(() => calc.of(_id('5z')), throwsArgumentError);
    });

    test('無料（deep=false）では 2 段階先を出さない', () {
      final hand = stateOf('12m 456m 678p 23s 67s 99m');
      for (final c in analyzeDiscards(hand, deep: false)) {
        expect(c.twoStep, isNull);
        expect(c.twoStepAverage, isNull);
      }
      for (final c in analyzeDiscards(hand)) {
        expect(c.twoStep, isNotNull);
      }
    });
  });
}
