import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'mpsz_test_utils.dart';

// 文脈つき採点（WinScorer）の代表例。点数は手で計算した値（Mリーグ相当のルール）。
// 網羅的な確認は score_crosscheck_test.dart（Python mahjong==2.0.0 との突合）。

final _mLeague = WinScorer(Rulesets.mLeague());

WinRequest _req(
  String hand,
  String win, {
  WinType winType = WinType.ron,
  List<CalledMeld> melds = const [],
  Wind round = Wind.east,
  Wind seat = Wind.south,
  bool riichi = false,
  bool ippatsu = false,
  bool rinshan = false,
  bool chankan = false,
  int honba = 0,
  int kyotaku = 0,
  String dora = '-',
  String ura = '-',
}) => WinRequest(
  handTiles: parseMpsz(hand),
  melds: melds,
  winningTile: win,
  winType: winType,
  roundWind: round,
  seatWind: seat,
  riichi: riichi,
  ippatsu: ippatsu,
  rinshan: rinshan,
  chankan: chankan,
  honba: honba,
  kyotaku: kyotaku,
  doraIndicators: parseMpsz(dora),
  uraDoraIndicators: parseMpsz(ura),
);

WinScored _scored(WinRequest r, [WinScorer? scorer]) {
  final outcome = (scorer ?? _mLeague).score(r);
  if (outcome is! WinScored) fail('採点できなかった: $outcome');
  return outcome;
}

WinError _error(WinRequest r, [WinScorer? scorer]) {
  final outcome = (scorer ?? _mLeague).score(r);
  if (outcome is! WinRejected) fail('エラーにならなかった');
  return outcome.error;
}

Set<YakuId> _ids(WinResult r) => {for (final y in r.yaku) y.id};

CalledMeld _meld(CalledMeldType type, String tiles) =>
    CalledMeld(type, parseMpsz(tiles));

void main() {
  group('和了牌の取り方（高点法）', () {
    test('3455s の 5s ロンは両面（平和）に取って 1300 → 2000 点', () {
      final s = _scored(_req('234m567m678p34555s', '5s'));
      final best = s.best;
      expect(_ids(best), {YakuId.pinfu, YakuId.tanyao});
      expect(best.han, 2);
      expect(best.fu, 30);
      expect(best.wait, WaitType.ryanmen);
      expect(best.payment.ron, 2000);
      // 単騎に取った解釈（断么九のみ 1 翻 40 符 = 1300 点）は次善として返す。
      final tanki = s.alternatives.firstWhere((r) => r.wait == WaitType.tanki);
      expect(tanki.han, 1);
      expect(tanki.fu, 40);
      expect(tanki.payment.ron, 1300);
    });
  });

  group('ロンで完成した刻子は明刻', () {
    test('四暗刻形のシャンポンロンは三暗刻・対々和（跳満にならず満貫）', () {
      final best = _scored(
        _req('222m444p666s888s11p', '6s', riichi: true),
      ).best;
      expect(best.isYakuman, isFalse);
      expect(_ids(best), {YakuId.riichi, YakuId.sanankou, YakuId.toitoi});
      expect(best.han, 5);
      expect(best.rank, HandRank.mangan);
      expect(best.payment.ron, 8000);
      final six = best.groups.firstWhere((g) => g.tile == '6s');
      expect(six.concealed, isFalse);
    });

    test('同じ形のツモは四暗刻（役満）', () {
      final best = _scored(
        _req('222m444p666s888s11p', '6s', winType: WinType.tsumo),
      ).best;
      expect(_ids(best), {YakuId.suuankou});
      expect(best.rank, HandRank.yakuman);
      expect(best.payment.tsumoFromDealer, 16000);
      expect(best.payment.tsumoFromChild, 8000);
      expect(best.payment.total, 32000);
      // 役満に吸収された役は別に返す（三暗刻は 4 つ暗刻なので付かない）。
      expect(
        {for (final y in best.suppressedYaku) y.id},
        {YakuId.menzenTsumo, YakuId.toitoi},
      );
    });

    test('単騎ロンは四暗刻単騎（Mリーグ相当はシングル役満）', () {
      final best = _scored(_req('222m444p666s888s11p', '1p')).best;
      expect(_ids(best), {YakuId.suuankouTanki});
      expect(best.yakumanMultiplier, 1);
      expect(best.payment.ron, 32000);
      final dbl = WinScorer(Rulesets.mLeague().copyWith(doubleYakuman: true));
      final d = _scored(_req('222m444p666s888s11p', '1p'), dbl).best;
      expect(d.yakumanMultiplier, 2);
      expect(d.rank, HandRank.doubleYakuman);
      expect(d.payment.ron, 64000);
    });
  });

  group('副露', () {
    test('副露のツモに門前清自摸和は付かない（役がなければ役なし）', () {
      final r = _req(
        '456p789p234s55s',
        '5s',
        winType: WinType.tsumo,
        melds: [_meld(CalledMeldType.chi, '123m')],
      );
      expect(_error(r), WinError.noYaku);
    });

    test('副露の分け方: チー 123m があるとき三暗刻・門前ツモは付かない', () {
      final r = _req(
        '112233m777z55p',
        '5p',
        winType: WinType.tsumo,
        melds: [_meld(CalledMeldType.chi, '123m')],
      );
      final best = _scored(r).best;
      expect(best.closed, isFalse);
      expect(_ids(best), {YakuId.yakuhaiChun});
      expect(
        best.groups.where((g) => g.meld == CalledMeldType.chi),
        hasLength(1),
      );
    });

    test('喰いタンあり: チーした断么九は 1 翻 30 符 1000 点。なしのルールでは役なし', () {
      final r = _req(
        '567p345s678s55m',
        '3s',
        melds: [_meld(CalledMeldType.chi, '234m')],
      );
      final best = _scored(r).best;
      expect(_ids(best), {YakuId.tanyao});
      expect(best.fu, 30);
      expect(best.payment.ron, 1000);
      // 副露の平和形ロンは 20 符 → 30 符
      expect(best.fuParts.map((p) => p.reason), contains(FuReason.openPinfu));
      final noKuitan = WinScorer(Rulesets.mLeague().copyWith(kuitan: false));
      expect(_error(r, noKuitan), WinError.noYaku);
    });

    test('立直は副露があるとエラー（暗槓だけなら門前）', () {
      expect(
        _error(
          _req(
            '567p345s678s55m',
            '5m',
            riichi: true,
            melds: [_meld(CalledMeldType.chi, '234m')],
          ),
        ),
        WinError.riichiWithOpenHand,
      );
      final best = _scored(
        _req(
          '567p345s678s55m',
          '5m',
          riichi: true,
          melds: [_meld(CalledMeldType.ankan, '2222p')],
        ),
      ).best;
      expect(best.closed, isTrue);
    });
  });

  group('符', () {
    test('平和ツモは 20 符（ツモ符なし）、子 700/1300', () {
      final best = _scored(
        _req('234m567m678p345s22p', '3s', winType: WinType.tsumo),
      ).best;
      expect(_ids(best), {YakuId.menzenTsumo, YakuId.pinfu, YakuId.tanyao});
      expect(best.fu, 20);
      expect(best.payment.tsumoFromChild, 700);
      expect(best.payment.tsumoFromDealer, 1300);
      expect(best.payment.total, 2700);
    });

    test('七対子は 25 符 2 翻 1600 点', () {
      final best = _scored(_req('11m33m55p77p99s22z66z', '1m')).best;
      expect(best.shape, WinShape.chiitoitsu);
      expect(best.fu, 25);
      expect(best.han, 2);
      expect(best.payment.ron, 1600);
    });

    test('暗槓 么九 32 符: 立直 1 翻 70 符 2300 点', () {
      final best = _scored(
        _req(
          '234p567p345s66s',
          '6s',
          riichi: true,
          melds: [_meld(CalledMeldType.ankan, '9999m')],
        ),
      ).best;
      // 30（副底＋門前ロン）＋ 32（暗槓）＋ 2（単騎）= 64 → 70
      expect(best.fu, 70);
      expect(best.payment.ron, 2300);
      expect(best.fuParts.firstWhere((p) => p.reason == FuReason.ankan).fu, 32);
    });

    test('明槓 字牌 16 符: 中 1 翻 40 符 1300 点', () {
      final best = _scored(
        _req(
          '234p567p345s66s',
          '6s',
          melds: [_meld(CalledMeldType.minkan, '7777z')],
        ),
      ).best;
      expect(best.fu, 40); // 20 ＋ 16 ＋ 2 = 38 → 40
      expect(best.payment.ron, 1300);
    });

    test('連風牌の雀頭は 4 符（ルールで 2 符も選べる）', () {
      // 親（東家・東場）の 東東 雀頭、111m 暗刻、立直ロン
      final r = _req(
        '111m567m678p789s11z',
        '9s',
        riichi: true,
        seat: Wind.east,
      );
      final best = _scored(r).best;
      // 30 ＋ 8（么九暗刻）＋ 4（連風牌）= 42 → 50。1 翻 50 符の親ロン 2400
      expect(best.fu, 50);
      expect(best.payment.ron, 2400);
      final twoFu = WinScorer(Rulesets.mLeague().copyWith(doubleWindPairFu: 2));
      final b2 = _scored(r, twoFu).best;
      expect(b2.fu, 40);
      expect(b2.payment.ron, 2000);
    });
  });

  group('役満・数え役満', () {
    test('数え役満: 立直・ツモ・平和・一通・清一色・ドラ3 = 14 翻', () {
      final r = _req(
        '123m234m456m789m55m',
        '9m',
        winType: WinType.tsumo,
        riichi: true,
        dora: '4m',
      );
      final best = _scored(r).best;
      expect(best.isYakuman, isFalse);
      expect(best.han, 14);
      expect(best.doraCount, 3);
      expect(best.rank, HandRank.kazoeYakuman);
      expect(best.payment.total, 32000);
      final noKazoe = WinScorer(
        Rulesets.mLeague().copyWith(countedYakuman: false),
      );
      final b = _scored(r, noKazoe).best;
      expect(b.rank, HandRank.sanbaiman);
      expect(b.payment.total, 24000);
    });

    test('役満の複合: 字一色＋大三元はダブル役満', () {
      // 四暗刻単騎にならないよう東はポン。
      final pon = [_meld(CalledMeldType.pon, '111z')];
      final best = _scored(_req('555z666z777z22z', '2z', melds: pon)).best;
      expect(_ids(best), {YakuId.tsuuiisou, YakuId.daisangen});
      expect(best.yakumanMultiplier, 2);
      expect(best.rank, HandRank.doubleYakuman);
      expect(best.payment.ron, 64000);
      // 役満が成立したらドラは数えない
      final withDora = _scored(
        _req('555z666z777z22z', '2z', melds: pon, dora: '1z'),
      ).best;
      expect(withDora.han, 26);
      expect(withDora.doraCount, 2); // 表示用には数える
      expect(withDora.countedDora, 0);
    });

    test('大四喜（Mリーグ相当はシングル）＋字一色', () {
      final best = _scored(
        _req(
          '111z222z333z55z',
          '5z',
          melds: [_meld(CalledMeldType.pon, '444z')],
        ),
      ).best;
      expect(_ids(best), {YakuId.daisuushii, YakuId.tsuuiisou});
      expect(best.yakumanMultiplier, 2);
    });

    test('国士無双十三面・純正九蓮宝燈はダブル役満のルールでだけ 2 倍', () {
      final kokushi = _req('19m19p19s12345677z', '7z');
      final k1 = _scored(kokushi).best;
      expect(_ids(k1), {YakuId.kokushi13});
      expect(k1.yakumanMultiplier, 1);
      expect(k1.fu, 0);
      final chuuren = _req('11123455678999p', '5p', winType: WinType.tsumo);
      final c1 = _scored(chuuren).best;
      expect(_ids(c1), {YakuId.junseiChuuren});
      final dbl = WinScorer(Rulesets.mLeague().copyWith(doubleYakuman: true));
      expect(_scored(kokushi, dbl).best.yakumanMultiplier, 2);
      expect(_scored(chuuren, dbl).best.yakumanMultiplier, 2);
      // 九蓮の 1 面待ち（9p ツモ以外で 2 枚目ができない形）
      final c2 = _scored(
        _req('11123455678999p', '4p', winType: WinType.tsumo),
      ).best;
      expect(_ids(c2), {YakuId.chuuren});
    });
  });

  group('支払い・本場・供託', () {
    test('親の満貫ツモは 4000 オール、1 本場で 4100 オール', () {
      // 立直・ツモ・平和・断么九・ドラ1 = 5 翻
      final r = _req(
        '234m567m345p678s66s',
        '3p',
        winType: WinType.tsumo,
        riichi: true,
        seat: Wind.east,
        dora: '1m',
      );
      final best = _scored(r).best;
      expect(best.han, 5);
      expect(best.rank, HandRank.mangan);
      expect(best.payment.tsumoFromChild, 4000);
      expect(best.payment.tsumoFromDealer, 0);
      expect(best.payment.total, 12000);
      final honba = _scored(r.copyWith(honba: 1)).best.payment;
      expect(honba.tsumoFromChild, 4100);
      expect(honba.tsumoFromChildBase, 4000);
      expect(honba.total, 12300);
      expect(honba.baseTotal, 12000);
    });

    test('子のロン 1000 点、2 本場・供託 1 本で 2600', () {
      final r = _req(
        '567p345s678s55m',
        '3s',
        melds: [_meld(CalledMeldType.chi, '234m')],
        honba: 2,
        kyotaku: 1,
      );
      final p = _scored(r).best.payment;
      expect(p.ronBase, 1000);
      expect(p.ron, 1600);
      expect(p.honbaPoints, 600);
      expect(p.kyotakuPoints, 1000);
      expect(p.total, 2600);
      expect(p.baseTotal, 1000);
    });

    test('WinPayment.compute の代表値', () {
      // 子 30 符 4 翻 = 基本点 1920
      final ko = WinPayment.compute(
        basePoints: 1920,
        dealer: false,
        winType: WinType.ron,
      );
      expect(ko.ron, 7700);
      final kt = WinPayment.compute(
        basePoints: 1920,
        dealer: false,
        winType: WinType.tsumo,
      );
      expect((kt.tsumoFromChild, kt.tsumoFromDealer), (2000, 3900));
      final oya = WinPayment.compute(
        basePoints: 1920,
        dealer: true,
        winType: WinType.ron,
      );
      expect(oya.ron, 11600);
      final ot = WinPayment.compute(
        basePoints: 1920,
        dealer: true,
        winType: WinType.tsumo,
      );
      expect(ot.tsumoFromChild, 3900);
      expect(ot.total, 11700);
    });
  });

  group('ドラ', () {
    test('表示牌の次がドラ（9→1、北→東、中→白）。赤は枚数をそのまま数える', () {
      final best = _scored(
        _req(
          '123m406p789s111z55z',
          '5z',
          riichi: true,
          dora: '9m4z',
          ura: '7z',
        ),
      ).best;
      expect(best.doraCount, 1 + 3); // 1m ×1、東 ×3
      expect(best.uraDoraCount, 2); // 白 ×2
      expect(best.akaDoraCount, 1); // 0p
      final noRed = WinScorer(Rulesets.mLeague().copyWith(redFives: 0));
      expect(
        _scored(
          _req('123m406p789s111z55z', '5z', riichi: true),
          noRed,
        ).best.akaDoraCount,
        0,
      );
    });

    test('裏ドラは立直したときだけ数える', () {
      final r = _req('234m567m678p345s22p', '3s', ura: '1p');
      final best = _scored(r.copyWith(winType: WinType.tsumo)).best;
      expect(best.uraDoraCount, 0);
    });

    test('ドラだけでは和了にならない', () {
      final r = _req(
        '456p789p234s55s',
        '5s',
        melds: [_meld(CalledMeldType.chi, '123m')],
        dora: '4s',
      );
      expect(_error(r), WinError.noYaku);
    });
  });

  group('入力の検証', () {
    test('読めない牌・枚数違い・5 枚目・和了牌なし・副露の形', () {
      final valid = _req('234m567m678p345s22p', '3s');
      expect(
        _error(valid.copyWith(handTiles: [...valid.handTiles.take(13), '2x'])),
        WinError.invalidTile,
      );
      expect(_error(valid.copyWith(winningTile: '8z')), WinError.invalidTile);
      expect(_error(_req('234m567m678p345s2p', '3s')), WinError.wrongTileCount);
      expect(
        _error(_req('234m567m678p345s22p', '3s', dora: '2p2p2p')),
        WinError.tooManyCopies,
      );
      expect(
        _error(_req('234m567m678p345s22p', '9s')),
        WinError.winningTileNotInHand,
      );
      expect(
        _error(
          _req(
            '567p345s678s55m',
            '5m',
            melds: [_meld(CalledMeldType.chi, '124m')],
          ),
        ),
        WinError.invalidMeld,
      );
      expect(
        _error(
          _req(
            '567p345s678s55m',
            '5m',
            melds: [_meld(CalledMeldType.chi, '123z')],
          ),
        ),
        WinError.invalidMeld,
      );
      expect(
        _error(_req('234m005m678p345s22p', '2p')),
        WinError.tooManyRedFives,
      );
    });

    test('和了形でない・状況の矛盾', () {
      expect(
        _error(_req('234m567m678p345s29p', '3s')),
        WinError.notWinningHand,
      );
      expect(
        _error(_req('234m567m678p345s22p', '3s', ippatsu: true)),
        WinError.ippatsuWithoutRiichi,
      );
      expect(
        _error(_req('234m567m678p345s22p', '3s', rinshan: true)),
        WinError.rinshanWithoutTsumo,
      );
      expect(
        _error(
          _req(
            '234m567m678p345s22p',
            '3s',
            winType: WinType.tsumo,
            rinshan: true,
          ),
        ),
        WinError.rinshanWithoutKan,
      );
      // 槍槓: 和了牌と同じ牌が他にもあると加槓された牌になれない
      expect(
        _error(_req('234m567m678p345s22p', '2p', chankan: true)),
        WinError.chankanImpossible,
      );
      expect(
        _error(
          WinRequest(
            handTiles: parseMpsz('234m567m678p345s22p'),
            winningTile: '3s',
            winType: WinType.ron,
            seatWind: Wind.east,
            tenhou: true,
          ),
        ),
        WinError.tenhouWithoutTsumo,
      );
    });

    test('三人麻雀は未対応', () {
      final sanma = WinScorer(
        Rulesets.mLeague().copyWith(mode: MahjongMode.threePlayer),
      );
      expect(
        _error(_req('234m567m678p345s22p', '3s'), sanma),
        WinError.unsupportedMode,
      );
    });
  });

  group('満貫以上の名称', () {
    final rules = Rulesets.mLeague();
    HandRank rank(int han, int fu, [Ruleset? r]) =>
        winHandRank(han: han, fu: fu, ruleset: r ?? rules);

    test('境目', () {
      expect(rank(4, 30), HandRank.none); // 7700
      expect(rank(3, 60), HandRank.none); // 7700
      expect(rank(4, 40), HandRank.mangan);
      expect(rank(3, 70), HandRank.mangan);
      expect(rank(5, 30), HandRank.mangan);
      expect(rank(6, 30), HandRank.haneman);
      expect(rank(8, 30), HandRank.baiman);
      expect(rank(11, 30), HandRank.sanbaiman);
      expect(rank(13, 30), HandRank.kazoeYakuman);
      final kiriage = rules.copyWith(kiriageMangan: true);
      expect(rank(4, 30, kiriage), HandRank.mangan);
      expect(rank(3, 60, kiriage), HandRank.mangan);
      expect(
        winHandRank(han: 26, fu: 0, yakumanMultiplier: 2, ruleset: rules),
        HandRank.doubleYakuman,
      );
      expect(HandRank.haneman.jaName, '跳満');
      expect(HandRank.kazoeYakuman.isYakumanLevel, isTrue);
    });
  });
}
