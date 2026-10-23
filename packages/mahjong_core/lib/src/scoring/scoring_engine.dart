// 流用元: reference/agari_cam/lib/scoring/scoring_engine.dart（2026-10-21 時点）
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/scoring/han_yaku.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';

class PayoutBreakdown {
  final int koRon; // child ron
  final (int, int) koTsumo; // (non-dealer pays, dealer pays)
  final int oyaRon;
  final int oyaTsumo; // each non-dealer pays
  const PayoutBreakdown({
    required this.koRon,
    required this.koTsumo,
    required this.oyaRon,
    required this.oyaTsumo,
  });
}

class ScoreResult {
  final WinContext ctx;
  final AnalysisResult analysis;
  final PayoutBreakdown payout;
  const ScoreResult({
    required this.ctx,
    required this.analysis,
    required this.payout,
  });
}

class ScoringEngine {
  final Ruleset ruleset;
  const ScoringEngine(this.ruleset);

  ScoreResult scoreByHanFu({
    required int han,
    required int fu,
    required WinContext ctx,
    List<Yaku> yaku = const [],
    FuBreakdown? fuBreakdown,
  }) {
    final roundedFu = _roundedFu(fu);
    final base = _cappedBase(roundedFu, han, yaku: yaku);
    final analysis = AnalysisResult(
      yaku: yaku,
      han: han,
      fu: roundedFu,
      basePoints: base,
      fuBreakdown: fuBreakdown,
    );
    final p = _payouts(base);
    return ScoreResult(ctx: ctx, analysis: analysis, payout: p);
  }

  int _roundedFu(int fu) {
    if (fu == 25) return 25; // chiitoitsu fixed
    if (fu % 10 != 0) return ((fu / 10).floor() + 1) * 10;
    return fu;
  }

  /// 翻・符・役から基本点（満貫以上は上限適用済み）を求める。
  int basePointsFor({
    required int han,
    required int fu,
    List<Yaku> yaku = const [],
  }) => _cappedBase(_roundedFu(fu), han, yaku: yaku);

  int _cappedBase(int fu, int han, {List<Yaku> yaku = const []}) {
    // ドラは13枚以上あっても役満ではない（数え役満の設定に従う）。
    final yakumanHan = yaku
        .where((value) => !YakuCatalog.isDora(value.name))
        .map(
          (value) =>
              value.hanClosed > value.hanOpen ? value.hanClosed : value.hanOpen,
        )
        .where((value) => value >= 13)
        .toList(growable: false);
    if (yakumanHan.isNotEmpty) {
      var multiplier = 0;
      for (final value in yakumanHan) {
        multiplier += value ~/ 13;
      }
      return 8000 * multiplier;
    }
    final bp = fu * (1 << (han + 2));
    if (han >= 13) {
      if (ruleset.countedYakuman) return 8000; // 数え役満
      // 数え役満なし → 三倍満止まり
      return 6000;
    }
    if (han >= 11) return 6000; // sanbaiman
    if (han >= 8) return 4000; // baiman
    if (han >= 6) return 3000; // haneman
    // 切り上げ満貫（3翻60符/4翻30符）
    if (ruleset.kiriageMangan &&
        ((han == 3 && fu == 60) || (han == 4 && fu == 30))) {
      return 2000;
    }
    if (han >= 5 || bp >= 2000) return 2000; // mangan
    return bp;
  }

  PayoutBreakdown _payouts(int base) {
    int ceil100(num value) {
      final intCeil = value.ceil();
      final rem = intCeil % 100;
      return rem == 0 ? intCeil : intCeil + (100 - rem);
    }

    final isSanma = ruleset.mode == MahjongMode.threePlayer;
    final sanmaTsumoLoss = ruleset.sanmaTsumoLoss;

    final koRon = ceil100(base * 4);
    final oyaRon = ceil100(base * 6);

    num koTsumoChildRaw = base.toDouble();
    num koTsumoOyaRaw = (base * 2).toDouble();
    if (isSanma) {
      if (!sanmaTsumoLoss) {
        final missingShare = base.toDouble();
        final totalWeight = koTsumoChildRaw + koTsumoOyaRaw;
        if (totalWeight > 0) {
          final childWeight = koTsumoChildRaw / totalWeight;
          final oyaWeight = koTsumoOyaRaw / totalWeight;
          koTsumoChildRaw += missingShare * childWeight;
          koTsumoOyaRaw += missingShare * oyaWeight;
        }
      }
    } else {
      // 四麻は既存仕様のまま
      // nothing extra
    }

    num oyaTsumoEachRaw = (base * 2).toDouble();
    if (isSanma && !sanmaTsumoLoss) {
      final missingShare = (base * 2).toDouble();
      oyaTsumoEachRaw += missingShare / 2; // 残り二人で折半
    }

    final koTsumoKo = ceil100(koTsumoChildRaw);
    final koTsumoOya = ceil100(koTsumoOyaRaw);
    final oyaTsumoEach = ceil100(oyaTsumoEachRaw);
    return PayoutBreakdown(
      koRon: koRon,
      koTsumo: (koTsumoKo, koTsumoOya),
      oyaRon: oyaRon,
      oyaTsumo: oyaTsumoEach,
    );
  }
}
