import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

void main() {
  group('ronPayment / tsumoPayment は ScoringEngine の支払いと一致する', () {
    final engine = ScoringEngine(Rulesets.mLeague());
    // 1 翻 30 符 〜 役満まで、符と翻を一通り
    final cases = <(int, int)>[
      for (final fu in [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110])
        for (var han = 1; han <= 13; han++) (han, fu),
    ];
    for (final (han, fu) in cases) {
      if (fu == 20 && han == 1) continue; // 平和ツモは 2 翻から
      if (fu == 25 && han < 2) continue;
      test('$han翻$fu符', () {
        final base = engine.basePointsFor(han: han, fu: fu);
        final child = engine.scoreByHanFu(
          han: han,
          fu: fu,
          ctx: const WinContext(oya: false, tsumo: false),
        );
        expect(ronPayment(base, dealer: false), child.payout.koRon);
        expect(ronPayment(base, dealer: true), child.payout.oyaRon);
        final (ko, oya) = child.payout.koTsumo;
        expect(tsumoPayment(base, dealer: false), 2 * ko + oya);
        expect(tsumoPayment(base, dealer: true), 3 * child.payout.oyaTsumo);
      });
    }

    test('代表値', () {
      // 1 翻 30 符: 子ロン 1000、子ツモ 300/500、親ロン 1500、親ツモ 500 オール
      expect(ronPayment(240, dealer: false), 1000);
      expect(tsumoPayment(240, dealer: false), 1100);
      expect(ronPayment(240, dealer: true), 1500);
      expect(tsumoPayment(240, dealer: true), 1500);
      // 満貫
      expect(ronPayment(2000, dealer: false), 8000);
      expect(tsumoPayment(2000, dealer: false), 8000);
      expect(tsumoPayment(2000, dealer: true), 12000);
    });
  });

  group('PointRange.fromWeighted', () {
    test('最小・最大と、累積が半分に達する最小の値を中央値にする', () {
      final r = PointRange.fromWeighted([
        (2700, 4),
        (1000, 4),
        (2000, 4),
        (1500, 4),
      ]);
      // 1000(4) 1500(8) で累積 8 = 16 の半分 → 1500
      expect(r, const PointRange(min: 1000, median: 1500, max: 2700));
    });

    test('重みで中央値が動く', () {
      expect(PointRange.fromWeighted([(1000, 1), (8000, 3)]).median, 8000);
      expect(PointRange.fromWeighted([(1000, 3), (8000, 1)]).median, 1000);
    });

    test('重み 0 は無視し、空なら zero', () {
      expect(PointRange.fromWeighted([(5000, 0)]), PointRange.zero);
      expect(PointRange.fromWeighted([]), PointRange.zero);
      expect(
        PointRange.fromWeighted([(5000, 0), (1000, 2)]),
        const PointRange(min: 1000, median: 1000, max: 1000),
      );
    });
  });
}
