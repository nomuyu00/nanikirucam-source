// 和了の点数画面の状態（win_score_logic.dart）と、ライブの winRank を HandRank に寄せた件。
import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/live/live_advice.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

final _input = HandInput(
  tiles: const [
    '2m', '3m', '4m', '5m', '6m', '7m', //
    '4p', '5p', '6s', '7s', '8s', '6s', '6s', '3p',
  ],
  tsumoIndex: 13,
  doraIndicators: const ['1m'],
);

void main() {
  test('HandInput から: 和了牌は tsumoIndex（無ければ末尾）、条件は風・ドラ表示牌', () {
    final hand = WinHand.fromInput(_input);
    expect(hand.winningTile, '3p');
    expect(hand.displayOrder.last, 13);
    final noTsumo = WinHand.fromInput(HandInput(tiles: _input.tiles));
    expect(noTsumo.winIndex, 13);
    final c = WinConditions.fromInput(_input.withSeatWind(Wind.east));
    expect(c.dealer, isTrue);
    expect(c.doraIndicators, ['1m']);
    expect(c.winType, WinType.tsumo);
  });

  test('buildWinRequest: 裏ドラはリーチのときだけ渡す、副露の種類を写す', () {
    final hand = WinHand(
      tiles: const [
        '2p',
        '3p',
        '4p',
        '5p',
        '6p',
        '7p',
        '3s',
        '4s',
        '5s',
        '6s',
        '6s',
      ],
      winIndex: 10,
      melds: [
        MeldInput(kind: MeldKind.ankan, tiles: const ['9m', '9m', '9m', '9m']),
      ],
    );
    final c = WinConditions(uraIndicators: const ['1p']);
    expect(buildWinRequest(hand, c).uraDoraIndicators, isEmpty);
    final r = buildWinRequest(hand, c.copyWith(riichi: RiichiKind.riichi));
    expect(r.uraDoraIndicators, ['1p']);
    expect(r.riichi, isTrue);
    expect(r.melds.single.type, CalledMeldType.ankan);
    expect(hand.isOpen, isFalse);
    expect(hand.hasKan, isTrue);
  });

  test('sanitized: ロンにすると海底・嶺上・天和系が外れ、リーチをやめると一発が外れる', () {
    final hand = WinHand.fromInput(_input);
    final c = WinConditions(
      riichi: RiichiKind.riichi,
      ippatsu: true,
      situations: const {WinSituation.haitei},
    );
    final ron = c.copyWith(winType: WinType.ron).sanitized(hand);
    expect(ron.situations, isEmpty);
    expect(ron.ippatsu, isTrue);
    final noRiichi = c.copyWith(riichi: RiichiKind.none).sanitized(hand);
    expect(noRiichi.ippatsu, isFalse);
    // 地和（子）は親にすると外れる。
    final chiihou = WinConditions(situations: const {WinSituation.chiihou});
    expect(
      chiihou.copyWith(seatWind: Wind.east).sanitized(hand).situations,
      isEmpty,
    );
  });

  test('situationBlocker: 成立し得ないものの理由', () {
    final hand = WinHand.fromInput(_input);
    final tsumo = WinConditions();
    expect(situationBlocker(WinSituation.haitei, hand, tsumo), isNull);
    expect(
      situationBlocker(WinSituation.houtei, hand, tsumo),
      WinError.houteiWithTsumo,
    );
    expect(
      situationBlocker(WinSituation.rinshan, hand, tsumo),
      WinError.rinshanWithoutKan,
    );
    expect(
      situationBlocker(WinSituation.tenhou, hand, tsumo),
      WinError.tenhouNotDealer,
    );
    expect(
      situationBlocker(
        WinSituation.chiihou,
        hand,
        tsumo.copyWith(riichi: RiichiKind.riichi),
      ),
      WinError.blessingWithOtherSituation,
    );
    final ron = WinConditions(winType: WinType.ron);
    expect(situationBlocker(WinSituation.chankan, hand, ron), isNull);
    // 6s（3 枚ある）で和了なら槍槓にはならない。
    expect(
      situationBlocker(WinSituation.chankan, hand.withWinIndex(11), ron),
      WinError.chankanImpossible,
    );
    expect(ippatsuBlocker(hand, tsumo), WinError.ippatsuWithoutRiichi);
  });

  test('表示牌は同じ牌 4 枚まで', () {
    final hand = WinHand.fromInput(_input);
    final c = WinConditions(doraIndicators: const ['6s']);
    // 6s は手牌に 3 枚 + 表示牌 1 枚 = 4 枚
    expect(canAddIndicator('6s', hand, c), isFalse);
    expect(canAddIndicator('9s', hand, c), isTrue);
  });

  test('役の表示順: リーチ・一発・ツモが先、残りは YakuId の順', () {
    final ordered = orderedYaku(const [
      ScoredYaku(YakuId.tanyao, 1),
      ScoredYaku(YakuId.menzenTsumo, 1),
      ScoredYaku(YakuId.pinfu, 1),
      ScoredYaku(YakuId.riichi, 1),
      ScoredYaku(YakuId.ippatsu, 1),
    ]);
    expect(
      [for (final y in ordered) y.id],
      [
        YakuId.riichi,
        YakuId.ippatsu,
        YakuId.menzenTsumo,
        YakuId.tanyao,
        YakuId.pinfu,
      ],
    );
  });

  test('ライブの winRank を HandRank に寄せても、もとの式と同じ値', () {
    String legacy(int han, int fu, bool yakuman) {
      if (yakuman || han >= 13) return 'yakuman';
      if (han >= 11) return 'sanbaiman';
      if (han >= 8) return 'baiman';
      if (han >= 6) return 'haneman';
      if (han >= 5 || (han == 4 && fu >= 40) || (han == 3 && fu >= 70)) {
        return 'mangan';
      }
      return 'none';
    }

    for (var han = 0; han <= 26; han++) {
      for (final fu in [20, 25, 30, 40, 50, 60, 70, 80, 90, 100, 110]) {
        expect(
          winRank(han: han, fu: fu),
          legacy(han, fu, false),
          reason: '$han翻$fu符',
        );
      }
    }
    expect(winRankParam(HandRank.kazoeYakuman), 'yakuman');
  });
}
