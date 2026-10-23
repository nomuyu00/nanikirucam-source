// 役の確度・想定打点・良形率のゴールデン（設計書 4.9）。テンパイ 25 手・一向聴 25 手。
//
// 前提: 子は南家・東場（1z は場風）、親は東家。ドラはドラそのもの（表示牌ではない）。
// 打点は「最小/中央値/最大」。ダマはロンとツモを 1 経路ずつ同じ重みで数え、役なしは 0。
// リーチ込みは門前のときだけ（副露は '-'）。良形率は待ち 5 枚以上のテンパイ形の割合。
//
// 「手計算」とある手はコメントの計算で値を確かめた。それ以外は実装の出力で固定した
// スナップショット（回帰テスト）。
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

import 'route_test_utils.dart';

class _G {
  final String id;
  final String hand;
  final String melds;
  final String dora;
  final String visible;
  final bool dealer;
  final String yaku;
  final String dama;
  final String riichi;
  final double good;
  final Map<YakuId, double> rates;

  const _G(
    this.id,
    this.hand, {
    this.melds = '',
    this.dora = '',
    this.visible = '',
    this.dealer = false,
    required this.yaku,
    required this.dama,
    this.riichi = '-',
    required this.good,
    this.rates = const {},
  });
}

const _cases = <_G>[
  // ---- テンパイ ------------------------------------------------------------
  // 手計算: 待ち 1m・4m（各 4 枚）とも平和。ロン 1 翻 30 符 1000、ツモ 2 翻 20 符
  // 400/700 = 1500。リーチ込みはロン 2000、ツモ 3 翻 20 符 700/1300 = 2700。
  // 重みは 1000・1500 が半々なので中央値は 1000（累積がちょうど半分）。
  _G(
    'T01',
    '23m456p789s23455s',
    yaku: 'pinfu:certain riichi:certain',
    dama: '1000/1000/1500',
    riichi: '2000/2000/2700',
    good: 1,
  ),
  // 手計算: 1m なら平和のみ（1000 / ツモ 1500）、4m なら断么九が付く（2 翻 30 符 2000 /
  // ツモ 3 翻 20 符 2700）。断么九は 4 枚 / 8 枚 = 0.5 で「狙える（4m）」。
  // 中央値: 1000(4) 1500(4) で累積 8 = 16 の半分 → 1500。
  _G(
    'T02',
    '23m456p678s23455s',
    yaku: 'pinfu:certain riichi:certain tanyao:possible[4m]',
    dama: '1000/1500/2700',
    riichi: '2000/2700/5200',
    good: 1,
    rates: {YakuId.tanyao: 0.5},
  ),
  // 手計算: 4m なら 234 の三色。ロン 平和+三色 3 翻 30 符 3900、ツモ 4 翻 20 符 5200。
  // 1m は平和のみ 1000 / 1500。リーチ込みの 4m はロン 7700、ツモ 5 翻 満貫 8000。
  _G(
    'T03',
    '23m234p234s567s99s',
    yaku: 'pinfu:certain riichi:certain sanshoku:possible[4m]',
    dama: '1000/1500/5200',
    riichi: '2000/2700/8000',
    good: 1,
  ),
  // 手計算: 待ち 1m(4)・4m(3)・7m(3)。1m だけ一気通貫（平和+一通 3900 / ツモ 5200）。
  // 一通の割合 4/10 = 0.4。4m・7m は平和のみ。
  _G(
    'T04',
    '23456789m345p77s',
    yaku: 'pinfu:certain riichi:certain ittsu:possible[1m]',
    dama: '1000/1500/5200',
    riichi: '2000/2700/8000',
    good: 1,
    rates: {YakuId.ittsu: 0.4},
  ),
  // 手計算: 1z・7z のシャンポン（各 2 枚）。7z なら中、1z なら場風。ロンは刻子が明刻
  // 扱いで 20+10+4+2 = 36 → 40 符 1 翻 1300。ツモは 20+2+8+2 = 32 → 40 符 2 翻
  // 700/1300 = 2700。待ち 4 枚なので良形ではない。
  _G(
    'T05',
    '234m456p789s1177z',
    yaku:
        'riichi:certain yakuhaiChun:possible[7z] yakuhaiRoundWind:possible[1z]',
    dama: '1300/1300/2700',
    riichi: '2600/2600/5200',
    good: 0,
    rates: {YakuId.yakuhaiChun: 0.5, YakuId.yakuhaiRoundWind: 0.5},
  ),
  // 手計算: チー 567p・ポン 666s、待ち 2s・5s とも喰いタン。ロン 20+2 = 22 → 30 符
  // 1000、ツモ 24 → 30 符 300/500 = 1100。
  _G(
    'T06',
    '234m34s88s',
    melds: 'chi:5p,pon:6s',
    yaku: 'tanyao:certain',
    dama: '1000/1000/1100',
    good: 1,
  ),
  // 手計算: ポン 6s・雀頭 1z で役なしの副露テンパイ。ロンもツモもできない。
  // 6s はポンで 3 枚使っているので残り 1、9s が 4（待ち 5 枚で良形）。
  _G(
    'T07',
    '234m456p78s11z',
    melds: 'pon:6s',
    yaku: '',
    dama: '0/0/0',
    good: 1,
  ),
  // 手計算: 暗槓 9p は門前のまま。ダマのロンは役なし 0、ツモ 60 符 1 翻 500/1000 = 2000。
  // リーチ: ロン 70 符 1 翻 2300、ツモ 60 符 2 翻 1000/2000 = 4000。
  _G(
    'T08',
    '234m456p78s11z',
    melds: 'ankan:9p',
    yaku: 'riichi:certain',
    dama: '0/0/2000',
    riichi: '2300/2300/4000',
    good: 1,
  ),
  // 手計算: T08 の親（東家、1z は連風牌の雀頭 4 符でも 60/70 符は同じ）。
  // ツモ 60 符 1 翻 1000 オール = 3000、リーチのロン 70 符 3360 → 3400、ツモ 2000 オール。
  _G(
    'T09',
    '234m456p78s11z',
    melds: 'ankan:9p',
    dealer: true,
    yaku: 'riichi:certain',
    dama: '0/0/3000',
    riichi: '3400/3400/6000',
    good: 1,
  ),
  // 手計算: 七対子 5z 単騎（残り 3）。ロン 2 翻 25 符 1600、ツモ 3 翻 25 符 800/1600 = 3200。
  _G(
    'T10',
    '1199m2288p3366s5z',
    yaku: 'chiitoitsu:certain riichi:certain',
    dama: '1600/1600/3200',
    riichi: '3200/3200/6400',
    good: 0,
  ),
  // 手計算: 国士 13 面待ち（各 3 枚、計 39）。ダブル役満なしのルールで子 32000。
  // 役満は「狙える」のみ表示（仕様 4.3）。
  _G(
    'T11',
    '19m19p19s1234567z',
    yaku:
        'riichi:certain kokushi:possible[1m,9m,1p,9p,1s,9s,1z,2z,3z,4z,5z,6z,7z]',
    dama: '32000/32000/32000',
    riichi: '32000/32000/32000',
    good: 1,
  ),
  // 手計算: 1z・5z のシャンポン。混一色 3 + 一通 2 + 役牌 1 = 6 翻で跳満 12000、
  // ツモ 7 翻も跳満。リーチ込みのツモは 8 翻で倍満 16000。
  _G(
    'T12',
    '123m456m789m1155z',
    yaku:
        'honitsu:certain ittsu:certain riichi:certain yakuhaiHaku:possible[5z] '
        'yakuhaiRoundWind:possible[1z]',
    dama: '12000/12000/12000',
    riichi: '12000/12000/16000',
    good: 0,
  ),
  // 手計算: 4s・5z のシャンポン。ロンは対々 2 + 三暗刻 2（ロンした刻子は明刻）= 4 翻
  // 50 符で満貫 8000（5z なら白も付いて 5 翻）。ツモは四暗刻 32000。役満の結果は役が
  // 四暗刻だけになるので、対々和・三暗刻の割合は役満を除いて数え「確定」。
  // リーチ込み: 4s ロン 5 翻 8000、5z ロン 6 翻 12000 → 中央値 12000。
  _G(
    'T13',
    '111m222p333s44s55z',
    yaku:
        'toitoi:certain sanankou:certain riichi:certain '
        'suuankou:possible[4s,5z] yakuhaiHaku:possible[5z]',
    dama: '8000/8000/32000',
    riichi: '8000/12000/32000',
    good: 0,
    rates: {YakuId.yakuhaiHaku: 0.5, YakuId.suuankou: 0.5},
  ),
  // 手計算: 3m 嵌張だけ。断么九 1 翻、ロン 20+10+2 = 32 → 40 符 1300、ツモ 24 → 30 符
  // 2 翻 500/1000 = 2000。
  _G(
    'T14',
    '24m456p678s34555s',
    yaku: 'tanyao:certain riichi:certain',
    dama: '1300/1300/2000',
    riichi: '2600/2600/4000',
    good: 0,
  ),
  // 手計算: 3m 辺張、役なし。ダマのロン 0、ツモは門前清自摸和 24 → 30 符 300/500 = 1100。
  // リーチ: ロン 32 → 40 符 1300、ツモ 2 翻 30 符 2000。
  _G(
    'T15',
    '12m456p789s23455s',
    yaku: 'riichi:certain',
    dama: '0/0/1100',
    riichi: '1300/1300/2000',
    good: 0,
  ),
  // 手計算: 2345m の延べ単（2m・5m 各 3 枚）。単騎なので平和なし、断么九 40 符 1300。
  // 待ちは 6 枚あるので良形（定義は残り 5 枚以上）。
  _G(
    'T16',
    '2345m456p678s345s',
    yaku: 'tanyao:certain riichi:certain',
    dama: '1300/1300/2000',
    riichi: '2600/2600/4000',
    good: 1,
  ),
  // 手計算: 112233m の一盃口 + 平和、待ち 6s(4)・9s(2)。ロン 2 翻 30 符 2000、
  // ツモ 3 翻 20 符 700/1300 = 2700。
  _G(
    'T17',
    '112233m456p78s99s',
    yaku: 'pinfu:certain iipeikou:certain riichi:certain',
    dama: '2000/2000/2700',
    riichi: '3900/3900/5200',
    good: 1,
  ),
  // 手計算: 親、雀頭 1z は連風牌（役牌の雀頭なので平和なし）。ダマのロンは役なし、
  // ツモ 20+2+4 = 26 → 30 符 1 翻 500 オール = 1500。リーチ: ロン 34 → 40 符
  // 1920 → 2000、ツモ 2 翻 30 符 1000 オール = 3000。
  _G(
    'T18',
    '234m456p678s56s11z',
    dealer: true,
    yaku: 'riichi:certain',
    dama: '0/0/1500',
    riichi: '2000/2000/3000',
    good: 1,
  ),
  // 手計算: 9m・1z のシャンポン（各 2 枚）で混全帯么九。9m ロン 2 翻 40 符 2600、
  // 1z ロン（場風が付く）3 翻 40 符 5200、9m ツモ 3 翻 40 符 1300/2600 = 5200、
  // 1z ツモ 4 翻 30 符 2000/3900 = 7900。中央値は累積 4/8 の 5200。
  _G(
    'T19',
    '123m789p789s99m11z',
    yaku: 'chanta:certain riichi:certain yakuhaiRoundWind:possible[1z]',
    dama: '2600/5200/7900',
    riichi: '5200/8000/8000',
    good: 0,
    rates: {YakuId.yakuhaiRoundWind: 0.5},
  ),
  // 手計算: 9p 単騎で純全帯 3 + 三色 2 = 5 翻 満貫 8000、ツモ 6 翻 跳満 12000。
  _G(
    'T20',
    '123m123p123s789m9p',
    yaku: 'junchan:certain sanshoku:certain riichi:certain',
    dama: '8000/8000/12000',
    riichi: '12000/12000/12000',
    good: 0,
  ),
  // 手計算: ポン中・チー 123m、待ち 1m(3)・4m(4)。混一色 2 + 中 1、1m なら混全帯 1 が
  // 付いて 4 翻 40 符 満貫 8000、4m は 3 翻 40 符 5200（ツモも 5200）。
  // 混全帯の割合 6/14 ≒ 0.429。
  _G(
    'T21',
    '23999m55z',
    melds: 'pon:7z,chi:1m',
    yaku: 'honitsu:certain yakuhaiChun:certain chanta:possible[1m]',
    dama: '5200/5200/8000',
    good: 1,
    rates: {YakuId.chanta: 6 / 14},
  ),
  // 手計算: ドラ 3s 1 枚 + 赤 5p 1 枚。平和 + ドラ 2 = 3 翻 30 符 3900、ツモ 4 翻 20 符 5200。
  // リーチ: ロン 4 翻 30 符 7700、ツモ 5 翻 満貫 8000。
  _G(
    'T22',
    '34m406p789s23455s',
    dora: '3s',
    yaku: 'pinfu:certain riichi:certain dora:certain x2',
    dama: '3900/3900/5200',
    riichi: '7700/7700/8000',
    good: 1,
  ),
  // 手計算: 親の断么九・平和。ロン 2 翻 30 符 2880 → 2900、ツモ 3 翻 20 符 1300 オール
  // = 3900。リーチ: ロン 5760 → 5800、ツモ 4 翻 20 符 2600 オール = 7800。
  _G(
    'T23',
    '34m456p678s23455s',
    dealer: true,
    yaku: 'tanyao:certain pinfu:certain riichi:certain',
    dama: '2900/2900/3900',
    riichi: '5800/5800/7800',
    good: 1,
  ),
  // 手計算: チー 789s、1z・6s のシャンポン（片あがり）。1z なら場風: ロン 24 → 30 符
  // 1000、ツモ 30 符 300/500 = 1100。6s は役なしで 0。中央値は累積半分の 0。
  _G(
    'T24',
    '234m456p11z66s',
    melds: 'chi:7s',
    yaku: 'yakuhaiRoundWind:possible[1z]',
    dama: '0/0/1100',
    good: 0,
    rates: {YakuId.yakuhaiRoundWind: 0.5},
  ),
  // 手計算: 23456m の三面張 1m(4)・4m(3)・7m(4)、どれも平和のみ。
  _G(
    'T25',
    '23456m456p789s55s',
    yaku: 'pinfu:certain riichi:certain',
    dama: '1000/1000/1500',
    riichi: '2000/2000/2700',
    good: 1,
  ),

  // ---- 一向聴 --------------------------------------------------------------
  // 手計算: 受け入れ 1m・4m・1s(各 4)・4s(2)・7z(3)。7z を引いて 7z 雀頭にした経路
  // （重み 3×8）だけ平和が消える（役牌の雀頭）。平和 96/120 = 0.8 で濃厚。
  // 7z 経路のダマのロンは役なし 0 → 最小 0。リーチの最小は 7z 雀頭 40 符 1300。
  _G(
    'O01',
    '23m456p789s2344s7z',
    yaku: 'riichi:certain pinfu:likely',
    dama: '0/1000/1500',
    riichi: '1300/2000/2700',
    good: 1,
    rates: {YakuId.pinfu: 0.8},
  ),
  // 手計算: 受け入れ 1z(3)・7z(3)・5s(2)。1z/7z を引くと 5s とのシャンポン（各 2 枚）、
  // 5s を引くと 1z 単騎と 7z 単騎が同じ評価なので等分。1z 和了だけ場風（ロン 40 符 1300、
  // ツモ 30 符 2 翻 2000）、5s・単騎はダマのロン 0・ツモ 1100。中の割合 12/60 = 0.2。
  // ダマ: 0 と 1100 が各 18/60 → 中央値 1100。リーチ: 1300 と 2000 が各 18/60 → 2000。
  _G(
    'O02',
    '123m456p789s55s17z',
    yaku:
        'riichi:certain yakuhaiChun:possible[7z] yakuhaiRoundWind:possible[1z]',
    dama: '0/1100/2000',
    riichi: '1300/2000/4000',
    good: 0,
    rates: {YakuId.yakuhaiChun: 0.2, YakuId.yakuhaiRoundWind: 0.2},
  ),
  // 手計算: 23m・56p の両面両面（99s 雀頭）。どれを引いてももう一方の両面待ち（8 枚）
  // で平和のみ。ロン 1000、ツモ 1500。良形率 1。
  _G(
    'O03',
    '23m56p456s789s99s1z',
    yaku: 'pinfu:certain riichi:certain',
    dama: '1000/1000/1500',
    riichi: '2000/2000/2700',
    good: 1,
  ),
  // 手計算: O03 の 5p が赤。赤は切られない（1z を切る）ので全経路で平和 + 赤 1:
  // ロン 2 翻 30 符 2000、ツモ 3 翻 20 符 2700。
  _G(
    'O04',
    '23m06p456s789s99s1z',
    yaku: 'pinfu:certain riichi:certain dora:certain x1',
    dama: '2000/2000/2700',
    riichi: '3900/3900/5200',
    good: 1,
  ),
  // 手計算: ポン 6s・雀頭 1z（場風の対子）・浮き 5z。受け入れ 4p・7p・6s(1)・9s で
  // 5z を切ってテンパイするが、1z は雀頭のままで役なし。どの経路も和了できない。
  _G(
    'O05',
    '234m56p78s115z',
    melds: 'pon:6s',
    yaku: '',
    dama: '0/0/0',
    good: 1,
  ),
  // 手計算: 七対子の一向聴（対子 5 組 + 6s・5z・7z）。どれを引いても単騎 3 枚待ちで
  // 七対子 1600 / ツモ 3200。
  _G(
    'O06',
    '1199m2288p336s57z',
    yaku: 'chiitoitsu:certain riichi:certain',
    dama: '1600/1600/3200',
    riichi: '3200/3200/6400',
    good: 0,
  ),
  // 手計算: 国士の一向聴（7z が無い 12 種 + 5m）。受け入れは么九牌 40 枚。7z(4) を引けば
  // 13 面待ち（良形）、他の 36 枚は 7z 待ち 4 枚 → 良形率 4/40 = 0.1。
  _G(
    'O07',
    '19m19p19s123456z5m',
    yaku:
        'riichi:certain kokushi:possible[1m,9m,1p,9p,1s,9s,1z,2z,3z,4z,5z,6z,7z]',
    dama: '32000/32000/32000',
    riichi: '32000/32000/32000',
    good: 0.1,
  ),
  // 手計算: 受け入れ 8m(4)・1z(2)・5z(2)。どの経路も混一色 3 + 一通 2 + 役牌 1 の
  // 6 翻以上で跳満 12000。
  _G(
    'O08',
    '12345679m11z55z7z',
    yaku:
        'honitsu:certain ittsu:certain riichi:certain '
        'yakuhaiHaku:possible[8m,5z] yakuhaiRoundWind:possible[8m,1z]',
    dama: '12000/12000/12000',
    riichi: '12000/12000/16000',
    good: 0,
  ),
  // 手計算: 34s 両面 + 浮き 5z・9m、雀頭なし。受け入れ 2s・5s(各 4) は単騎 3 枚待ち、
  // 5z・9m(各 3) は 2s/5s 両面 8 枚待ち。平和は 9m 雀頭の経路だけ（5z 雀頭は役牌）:
  // 3×8 / (4×3+4×3+3×8+3×8) = 24/72 ≒ 0.333。良形率 (3+3)/14 ≒ 0.4286。
  _G(
    'O09',
    '234m567p34s678s5z9m',
    yaku: 'riichi:certain pinfu:possible[9m]',
    dama: '0/1000/1500',
    riichi: '1300/2000/2700',
    good: 6 / 14,
    rates: {YakuId.pinfu: 1 / 3},
  ),
  // 手計算: 23m 両面 + 浮き 1z・9p。4m で 234 の三色。三色の重み: 4m 引き 12 + 1z 引き
  // →4m 12 + 9p 引き→4m 12 = 36 / 72 = 0.5（濃厚に届かず「狙える」）。平和は 9p 雀頭の
  // 経路だけ 24/72。
  _G(
    'O10',
    '23m234p234s567s1z9p',
    yaku: 'riichi:certain sanshoku:possible[4m,9p,1z] pinfu:possible[9p]',
    dama: '0/1500/5200',
    riichi: '1300/2700/8000',
    good: 6 / 14,
    rates: {YakuId.sanshoku: 0.5, YakuId.pinfu: 1 / 3},
  ),
  // 手計算: チー 234s・ポン 444p。5p/8p を引くと 8s 単騎（喰いタン）か 1z 単騎（役なし）
  // で、評価値の高い 8s 単騎を選ぶ。8s を引くと 5p/8p 待ちで喰いタン、1z を引くと 1z
  // 雀頭で役なし。断么九の重み 48/72 ≒ 0.667 で「狙える」（成立させる牌 5p・8p・8s）。
  // ロン 1000（30 符）、ツモ 1100、役なし 0 → 中央値は 0 の 48/144 を越えた 1000。
  _G(
    'O11',
    '345m67p8s1z',
    melds: 'chi:2s,pon:4p',
    yaku: 'tanyao:possible[5p,8p,8s]',
    dama: '0/1000/1100',
    good: 6 / 14,
    rates: {YakuId.tanyao: 2 / 3},
  ),
  // 以下はスナップショット。
  _G(
    'O12',
    '1112345678m99m5z',
    yaku:
        'riichi:certain chinitsu:likely '
        'chuuren:possible[1m,2m,3m,4m,5m,6m,7m,8m,9m] '
        'honitsu:possible[1m,4m,7m,9m,5z] ittsu:possible[1m,7m,8m,5z] '
        'yakuhaiHaku:possible[5z] iipeikou:possible[7m,8m]',
    dama: '5200/12000/32000',
    riichi: '8000/16000/32000',
    good: 0.7778,
  ),
  _G(
    'O13',
    '23m456p789s2344s7z',
    dora: '4s',
    visible: '1m1m4m',
    yaku: 'riichi:certain dora:certain x2 pinfu:likely',
    dama: '0/5200/8000',
    riichi: '2600/8000/12000',
    good: 1,
  ),
  _G(
    'O14',
    '34m456p678s2345s7z',
    yaku: 'riichi:certain tanyao:likely pinfu:possible[2s,5s,8s]',
    dama: '0/2000/2700',
    riichi: '1300/3900/5200',
    good: 1,
  ),
  _G(
    'O15',
    '34m456p678s2345s7z',
    dealer: true,
    yaku: 'riichi:certain tanyao:likely pinfu:possible[2s,5s,8s]',
    dama: '0/2900/3900',
    riichi: '2000/5800/7800',
    good: 1,
  ),
  _G(
    'O16',
    '345m456p4567s577z',
    yaku:
        'riichi:certain yakuhaiHaku:possible[5z] '
        'yakuhaiChun:possible[4s,7s,5z,7z]',
    dama: '0/1100/2700',
    riichi: '1300/2000/5200',
    good: 0.4848,
  ),
  _G(
    'O17',
    '2234m567p345s68s1z',
    yaku: 'riichi:certain tanyao:likely pinfu:possible[7s]',
    dama: '0/2000/2700',
    riichi: '1300/3900/5200',
    good: 0.3077,
  ),
  _G(
    'O18',
    '13m456p78s22s9p',
    melds: 'pon:5z',
    yaku: 'yakuhaiHaku:certain',
    dama: '1000/1000/1100',
    good: 0.3333,
  ),
  _G(
    'O19',
    '22m4467p345s678s9s',
    yaku: 'tanyao:certain riichi:certain',
    dama: '1300/1300/2000',
    riichi: '2600/2600/4000',
    good: 0.3333,
  ),
  _G(
    'O20',
    '123m11p456s7s9p',
    melds: 'pon:6z',
    yaku: 'yakuhaiHatsu:certain',
    dama: '1000/1100/1500',
    good: 0.3902,
  ),
  _G(
    'O21',
    '11223m456p789s5z7z',
    yaku: 'iipeikou:certain riichi:certain',
    dama: '1300/1300/2000',
    riichi: '2600/2600/4000',
    good: 0,
  ),
  _G(
    'O22',
    '24m067p345s666s9p1z',
    dora: '6s',
    yaku: 'riichi:certain dora:certain x4',
    dama: '0/0/8000',
    riichi: '8000/8000/12000',
    good: 0,
  ),
  _G(
    'O23',
    '1235m789p789s11z4z',
    dora: '1z',
    yaku:
        'riichi:certain dora:certain x2 chanta:possible[1z,4z] '
        'yakuhaiRoundWind:possible[5m,1z,4z]',
    dama: '0/4000/12000',
    riichi: '5200/7900/16000',
    good: 0.3478,
  ),
  _G(
    'O24',
    '24689m345p345s55s',
    yaku: 'riichi:certain tanyao:possible[3m,7m]',
    dama: '0/1300/2000',
    riichi: '1300/2600/4000',
    good: 0,
    rates: {YakuId.tanyao: 2 / 3},
  ),
  _G(
    'O25',
    '111m345p77s8s9p',
    melds: 'pon:1z',
    yaku: 'yakuhaiRoundWind:certain',
    dama: '1300/1300/1500',
    good: 0.2083,
  ),
];

void main() {
  test('ケース数（テンパイ 25・一向聴 25）', () {
    expect(_cases.where((c) => c.id.startsWith('T')), hasLength(25));
    expect(_cases.where((c) => c.id.startsWith('O')), hasLength(25));
  });

  for (final c in _cases) {
    test('${c.id} ${c.hand}${c.melds.isEmpty ? '' : ' +${c.melds}'}', () {
      final hand = stateOf(
        c.hand,
        melds: c.melds,
        dora: c.dora,
        visible: c.visible,
        dealer: c.dealer,
      );
      final s = RouteEnumerator(hand).summarize(hand);
      expect(s.shanten, c.id.startsWith('T') ? 0 : 1);
      expect(s.isEstimate, isFalse);
      expect(yakuString(s.yaku), c.yaku);
      expect(rangeString(s.points), c.dama);
      expect(rangeString(s.riichiPoints), c.riichi);
      expect(s.goodShapeRate, closeTo(c.good, 1e-4));
      for (final MapEntry(key: y, value: rate) in c.rates.entries) {
        final p = s.yaku.firstWhere((p) => p.yaku == y);
        expect(p.rate, closeTo(rate, 1e-9), reason: y.name);
      }
      // 確度と割合の整合（役満とリーチは別扱い）
      for (final p in s.yaku) {
        if (p.yaku.isYakuman || p.yaku == YakuId.riichi) continue;
        switch (p.confidence) {
          case YakuConfidence.certain:
            expect(p.rate, 1.0, reason: p.yaku.name);
          case YakuConfidence.likely:
            expect(p.rate, inInclusiveRange(0.7, 1.0), reason: p.yaku.name);
            expect(p.rate, lessThan(1.0), reason: p.yaku.name);
          case YakuConfidence.possible:
            expect(p.rate, lessThan(0.7), reason: p.yaku.name);
            expect(p.enablingTiles, isNotEmpty, reason: p.yaku.name);
          case YakuConfidence.lost:
            fail('13 枚の集計に「消える」は出ない');
        }
      }
      expect(s.points.min, lessThanOrEqualTo(s.points.median));
      expect(s.points.median, lessThanOrEqualTo(s.points.max));
    });
  }
}
