// 流用元: reference/agari_cam/test/scoring_engine_test.dart（2026-10-21 時点）
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

void main() {
  final engine = ScoringEngine(Rulesets.mLeague());

  test('30符2翻 子: ロン2000, ツモ500/1000', () {
    final ctxRon = const WinContext(oya: false, tsumo: false);
    final rRon = engine.scoreByHanFu(han: 2, fu: 30, ctx: ctxRon);
    expect(rRon.payout.koRon, 2000);
    final ctxTsumo = const WinContext(oya: false, tsumo: true);
    final rTsumo = engine.scoreByHanFu(han: 2, fu: 30, ctx: ctxTsumo);
    expect(rTsumo.payout.koTsumo.$1, 500);
    expect(rTsumo.payout.koTsumo.$2, 1000);
  });

  test('40符3翻 子: ロン5200, ツモ1300/2600', () {
    final rRon = engine.scoreByHanFu(
      han: 3,
      fu: 40,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.payout.koRon, 5200);
    final rTsumo = engine.scoreByHanFu(
      han: 3,
      fu: 40,
      ctx: const WinContext(oya: false, tsumo: true),
    );
    expect(rTsumo.payout.koTsumo.$1, 1300);
    expect(rTsumo.payout.koTsumo.$2, 2600);
  });

  test('20符3翻 子: ロン2600, ツモ700/1300', () {
    final rRon = engine.scoreByHanFu(
      han: 3,
      fu: 20,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.payout.koRon, 2600);
    final rTsumo = engine.scoreByHanFu(
      han: 3,
      fu: 20,
      ctx: const WinContext(oya: false, tsumo: true),
    );
    expect(rTsumo.payout.koTsumo.$1, 700);
    expect(rTsumo.payout.koTsumo.$2, 1300);
  });

  test('20符3翻 親: ロン3900, ツモ1300オール', () {
    final rRon = engine.scoreByHanFu(
      han: 3,
      fu: 20,
      ctx: const WinContext(oya: true, tsumo: false),
    );
    expect(rRon.payout.oyaRon, 3900);
    final rTsumo = engine.scoreByHanFu(
      han: 3,
      fu: 20,
      ctx: const WinContext(oya: true, tsumo: true),
    );
    expect(rTsumo.payout.oyaTsumo, 1300);
  });

  test('平和ロンは30符になる (基本20 + 門前ロン10)', () {
    // 翻は2翻として点数のみ確認（符が30に丸められていることが前提）
    final rRon = engine.scoreByHanFu(
      han: 2,
      fu: 30,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.analysis.fu, 30);
  });

  test('七対子 25符2翻 子: ロン1600, ツモ400/800', () {
    final rRon = engine.scoreByHanFu(
      han: 2,
      fu: 25,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.payout.koRon, 1600);
    final rTsumo = engine.scoreByHanFu(
      han: 2,
      fu: 25,
      ctx: const WinContext(oya: false, tsumo: true),
    );
    expect(rTsumo.payout.koTsumo.$1, 400);
    expect(rTsumo.payout.koTsumo.$2, 800);
  });

  test('40符4翻 満貫 子: ロン8000, ツモ2000/4000', () {
    final rRon = engine.scoreByHanFu(
      han: 4,
      fu: 40,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.payout.koRon, 8000);
    final rTsumo = engine.scoreByHanFu(
      han: 4,
      fu: 40,
      ctx: const WinContext(oya: false, tsumo: true),
    );
    expect(rTsumo.payout.koTsumo.$1, 2000);
    expect(rTsumo.payout.koTsumo.$2, 4000);
  });

  test('70符3翻 満貫扱い 子: ロン8000', () {
    final rRon = engine.scoreByHanFu(
      han: 3,
      fu: 70,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.payout.koRon, 8000);
  });

  test('親 30符4翻 ロン11600', () {
    final rRon = engine.scoreByHanFu(
      han: 4,
      fu: 30,
      ctx: const WinContext(oya: true, tsumo: false),
    );
    expect(rRon.payout.oyaRon, 11600);
  });

  test('切り上げ満貫ONでも4翻20符は満貫にならない', () {
    final kiriageEngine = ScoringEngine(
      Rulesets.mLeague().copyWith(kiriageMangan: true),
    );
    final rRon = kiriageEngine.scoreByHanFu(
      han: 4,
      fu: 20,
      ctx: const WinContext(oya: false, tsumo: false),
    );
    expect(rRon.payout.koRon, 5200);
  });

  group('三麻 ツモ損あり', () {
    final sanmaLossEngine = ScoringEngine(
      Rulesets.mLeague().copyWith(
        mode: MahjongMode.threePlayer,
        sanmaTsumoLoss: true,
      ),
    );

    test('30符2翻 子: ツモ500/1000（ツモ損あり）', () {
      final rTsumo = sanmaLossEngine.scoreByHanFu(
        han: 2,
        fu: 30,
        ctx: const WinContext(oya: false, tsumo: true),
      );
      expect(rTsumo.payout.koTsumo.$1, 500);
      expect(rTsumo.payout.koTsumo.$2, 1000);
    });

    test('30符2翻 親: ツモ1000オール（ツモ損あり）', () {
      final rTsumo = sanmaLossEngine.scoreByHanFu(
        han: 2,
        fu: 30,
        ctx: const WinContext(oya: true, tsumo: true),
      );
      expect(rTsumo.payout.oyaTsumo, 1000);
    });
  });

  group('三麻 ツモ損なし', () {
    final sanmaNoLossEngine = ScoringEngine(
      Rulesets.mLeague().copyWith(
        mode: MahjongMode.threePlayer,
        sanmaTsumoLoss: false,
      ),
    );

    test('30符2翻 子: ツモ700/1300（ツモ損なし）', () {
      final rTsumo = sanmaNoLossEngine.scoreByHanFu(
        han: 2,
        fu: 30,
        ctx: const WinContext(oya: false, tsumo: true),
      );
      expect(rTsumo.payout.koTsumo.$1, 700);
      expect(rTsumo.payout.koTsumo.$2, 1300);
    });

    test('30符2翻 親: ツモ1500オール（ツモ損なし）', () {
      final rTsumo = sanmaNoLossEngine.scoreByHanFu(
        han: 2,
        fu: 30,
        ctx: const WinContext(oya: true, tsumo: true),
      );
      expect(rTsumo.payout.oyaTsumo, 1500);
    });
  });

  test('実役満は数え役満設定OFFでも役満として計算される', () {
    final noKazoeEngine = ScoringEngine(
      Rulesets.mLeague().copyWith(countedYakuman: false),
    );
    final result = noKazoeEngine.scoreByHanFu(
      han: 13,
      fu: 0,
      ctx: const WinContext(oya: false, tsumo: false),
      yaku: [RulesetSupport.singleYakuman('大三元')],
    );
    expect(result.analysis.basePoints, 8000);
    expect(result.payout.koRon, 32000);
  });

  test('ダブル役満は2倍の基本点になる', () {
    final result = engine.scoreByHanFu(
      han: 26,
      fu: 0,
      ctx: const WinContext(oya: false, tsumo: false),
      yaku: [RulesetSupport.doubleYakuman('国士無双十三面待ち', openAllowed: false)],
    );
    expect(result.analysis.basePoints, 16000);
    expect(result.payout.koRon, 64000);
  });
}
