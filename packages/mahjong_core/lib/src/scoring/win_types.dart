// 文脈つきの和了採点（WinScorer）の入出力の型。
//
// 入力は [WinRequest]（門前部分のラベル＋副露＋和了牌＋状況＋表示牌）、
// 出力は [WinOutcome]（成功なら [WinScored]、失敗なら [WinRejected]）。
// 牌はラベル（'1m'〜'9m'、赤5は '0m'、字牌 '1z'〜'7z' = 東南西北白發中）。
import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/yaku.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/wait_type.dart';

/// 副露（暗槓を含む）の種類。
enum CalledMeldType {
  /// チー（順子）。
  chi,

  /// ポン（刻子）。
  pon,

  /// 大明槓。
  minkan,

  /// 暗槓（門前のまま）。
  ankan,

  /// 加槓（ポンに 1 枚足した槓）。
  kakan,
}

/// 副露 1 つ。[tiles] はチー・ポンなら 3 枚、槓なら 4 枚のラベル。
class CalledMeld extends Equatable {
  final CalledMeldType type;
  final List<String> tiles;

  const CalledMeld(this.type, this.tiles);
  const CalledMeld.chi(this.tiles) : type = CalledMeldType.chi;
  const CalledMeld.pon(this.tiles) : type = CalledMeldType.pon;
  const CalledMeld.minkan(this.tiles) : type = CalledMeldType.minkan;
  const CalledMeld.ankan(this.tiles) : type = CalledMeldType.ankan;
  const CalledMeld.kakan(this.tiles) : type = CalledMeldType.kakan;

  /// 鳴いた面子か（暗槓だけは門前のまま）。
  bool get isOpen => type != CalledMeldType.ankan;

  /// 槓子か。
  bool get isKan =>
      type == CalledMeldType.minkan ||
      type == CalledMeldType.ankan ||
      type == CalledMeldType.kakan;

  @override
  List<Object?> get props => [type, tiles];
}

/// 和了 1 回分の入力。
///
/// - [handTiles]: 副露を除いた手牌（和了牌を含む）。枚数は `14 - 3 × 副露の数`。
/// - [winningTile]: 和了牌。[handTiles] の中にある牌（赤かどうかは問わない）。
/// - 親かどうかは自風（東 = 親）で決まる。
/// - [doraIndicators] / [uraDoraIndicators] は**表示牌**（ドラはその次の牌）。
///   裏ドラは立直（ダブル立直）したときだけ数える。
/// - 赤5は手牌・副露に含まれる '0m' / '0p' / '0s' の枚数をそのまま数える。
class WinRequest extends Equatable {
  final List<String> handTiles;
  final List<CalledMeld> melds;
  final String winningTile;
  final WinType winType;
  final Wind roundWind;
  final Wind seatWind;
  final bool riichi;
  final bool doubleRiichi;
  final bool ippatsu;
  final bool haitei;
  final bool houtei;
  final bool rinshan;
  final bool chankan;
  final bool tenhou;
  final bool chiihou;

  /// 人和（ルールの [RenhouValue] が none なら無視する）。
  final bool renhou;

  /// 本場（積み棒）。ロンは 300 点 × 本場、ツモは 1 人 100 点 × 本場。
  final int honba;

  /// 供託（リーチ棒の本数）。1 本 1000 点を和了者が受け取る。
  final int kyotaku;
  final List<String> doraIndicators;
  final List<String> uraDoraIndicators;

  const WinRequest({
    required this.handTiles,
    this.melds = const [],
    required this.winningTile,
    required this.winType,
    this.roundWind = Wind.east,
    this.seatWind = Wind.south,
    this.riichi = false,
    this.doubleRiichi = false,
    this.ippatsu = false,
    this.haitei = false,
    this.houtei = false,
    this.rinshan = false,
    this.chankan = false,
    this.tenhou = false,
    this.chiihou = false,
    this.renhou = false,
    this.honba = 0,
    this.kyotaku = 0,
    this.doraIndicators = const [],
    this.uraDoraIndicators = const [],
  });

  bool get isDealer => seatWind == Wind.east;
  bool get isTsumo => winType == WinType.tsumo;

  WinRequest copyWith({
    List<String>? handTiles,
    List<CalledMeld>? melds,
    String? winningTile,
    WinType? winType,
    Wind? roundWind,
    Wind? seatWind,
    bool? riichi,
    bool? doubleRiichi,
    bool? ippatsu,
    bool? haitei,
    bool? houtei,
    bool? rinshan,
    bool? chankan,
    bool? tenhou,
    bool? chiihou,
    bool? renhou,
    int? honba,
    int? kyotaku,
    List<String>? doraIndicators,
    List<String>? uraDoraIndicators,
  }) {
    return WinRequest(
      handTiles: handTiles ?? this.handTiles,
      melds: melds ?? this.melds,
      winningTile: winningTile ?? this.winningTile,
      winType: winType ?? this.winType,
      roundWind: roundWind ?? this.roundWind,
      seatWind: seatWind ?? this.seatWind,
      riichi: riichi ?? this.riichi,
      doubleRiichi: doubleRiichi ?? this.doubleRiichi,
      ippatsu: ippatsu ?? this.ippatsu,
      haitei: haitei ?? this.haitei,
      houtei: houtei ?? this.houtei,
      rinshan: rinshan ?? this.rinshan,
      chankan: chankan ?? this.chankan,
      tenhou: tenhou ?? this.tenhou,
      chiihou: chiihou ?? this.chiihou,
      renhou: renhou ?? this.renhou,
      honba: honba ?? this.honba,
      kyotaku: kyotaku ?? this.kyotaku,
      doraIndicators: doraIndicators ?? this.doraIndicators,
      uraDoraIndicators: uraDoraIndicators ?? this.uraDoraIndicators,
    );
  }

  @override
  List<Object?> get props => [
    handTiles,
    melds,
    winningTile,
    winType,
    roundWind,
    seatWind,
    riichi,
    doubleRiichi,
    ippatsu,
    haitei,
    houtei,
    rinshan,
    chankan,
    tenhou,
    chiihou,
    renhou,
    honba,
    kyotaku,
    doraIndicators,
    uraDoraIndicators,
  ];
}

/// 採点できなかった理由。
enum WinError {
  // --- 入力の形 ---
  /// 読めないラベルがある。
  invalidTile,

  /// 副露の形が不正（チーが連続しない・字牌のチー・ポンが同じ牌でない・槓が 4 枚でない等）。
  invalidMeld,

  /// 枚数が合わない（門前部分が `14 - 3 × 副露の数` 枚でない、副露が 5 つ以上）。
  wrongTileCount,

  /// 同じ牌が 5 枚以上ある（手牌・副露・ドラ表示牌・裏ドラ表示牌の合計）。
  tooManyCopies,

  /// 赤5がルールの枚数より多い（萬・索は各 1 枚、筒は赤4枚ルールで 2 枚）。
  tooManyRedFives,

  /// ドラ表示牌・裏ドラ表示牌がそれぞれ 5 枚を超える。
  tooManyIndicators,

  /// 和了牌が門前部分にない。
  winningTileNotInHand,

  /// 三人麻雀は未対応。
  unsupportedMode,

  // --- 状況の矛盾（参照実装 mahjong==2.0.0 と同じ順に調べる） ---
  /// 副露しているのに立直（ダブル立直）。
  riichiWithOpenHand,

  /// 立直していないのに一発。
  ippatsuWithoutRiichi,

  /// 槍槓なのにツモ。
  chankanWithTsumo,

  /// 嶺上開花なのにロン。
  rinshanWithoutTsumo,

  /// 海底摸月なのにロン。
  haiteiWithoutTsumo,

  /// 河底撈魚なのにツモ。
  houteiWithTsumo,

  /// 海底摸月と嶺上開花は同時に付かない。
  haiteiWithRinshan,

  /// 河底撈魚と槍槓は同時に付かない。
  houteiWithChankan,

  /// 天和は親だけ。
  tenhouNotDealer,

  /// 天和はツモだけ。
  tenhouWithoutTsumo,

  /// 天和は副露（暗槓を含む）があると成立しない。
  tenhouWithMeld,

  /// 地和は子だけ。
  chiihouAsDealer,

  /// 地和はツモだけ。
  chiihouWithoutTsumo,

  /// 地和は副露（暗槓を含む）があると成立しない。
  chiihouWithMeld,

  /// 人和は子だけ。
  renhouAsDealer,

  /// 人和はロンだけ。
  renhouWithTsumo,

  /// 人和は副露（暗槓を含む）があると成立しない。
  renhouWithMeld,

  // --- 状況の矛盾（参照実装は調べないが、実戦では起こらないもの） ---
  /// 嶺上開花なのに槓子がない。
  rinshanWithoutKan,

  /// 槍槓なのに和了牌と同じ牌が手牌・副露に 2 枚以上ある（加槓された牌は 1 枚しか残らない）。
  chankanImpossible,

  /// 一発と嶺上開花は同時に付かない（槓で一発は消える）。
  ippatsuWithRinshan,

  /// 天和・地和・人和に、立直・一発・海底・河底・嶺上・槍槓は付かない。
  blessingWithOtherSituation,

  // --- 和了の判定 ---
  /// 和了形でない。
  notWinningHand,

  /// 和了形だが役がない（ドラだけでは和了できない）。
  noYaku,
}

/// 符の内訳の項目。
enum FuReason {
  /// 副底 20 符。
  base,

  /// 門前ロン 10 符。
  menzenRon,

  /// ツモ 2 符（平和ツモには付かない）。
  tsumo,

  /// 七対子 25 符（固定）。
  chiitoitsu,

  /// 副露した手の平和形ロン・ツモ（20 符 → 30 符に上げる 10 符）。
  openPinfu,

  /// 嵌張待ち 2 符。
  kanchan,

  /// 辺張待ち 2 符。
  penchan,

  /// 単騎待ち 2 符。
  tanki,

  /// 三元牌の雀頭 2 符。
  pairDragon,

  /// 自風の雀頭 2 符。
  pairSeatWind,

  /// 場風の雀頭 2 符。
  pairRoundWind,

  /// 連風牌の雀頭（ルールで 2 符か 4 符）。
  pairDoubleWind,

  /// 明刻（中張牌 2 符・么九牌 4 符）。ロンで完成した刻子もここ。
  minko,

  /// 暗刻（中張牌 4 符・么九牌 8 符）。
  anko,

  /// 明槓（中張牌 8 符・么九牌 16 符）。
  minkan,

  /// 暗槓（中張牌 16 符・么九牌 32 符）。
  ankan,

  /// 10 符単位への切り上げ。
  roundUp,
}

/// 符の内訳 1 項目。[tile] は面子・雀頭の牌（ラベル、赤は 5 に直す）。
class FuPart extends Equatable {
  final FuReason reason;
  final int fu;
  final String? tile;
  const FuPart(this.reason, this.fu, {this.tile});

  @override
  List<Object?> get props => [reason, fu, tile];

  @override
  String toString() => '${reason.name}${tile == null ? '' : '($tile)'}=$fu';
}

/// 数えた役 1 つ。役満なら [yakumanMultiplier] が 1 以上（ダブル役満は 2）。
class ScoredYaku extends Equatable {
  final YakuId id;

  /// 翻。役満は 13 × 倍数。
  final int han;
  final int yakumanMultiplier;
  const ScoredYaku(this.id, this.han, {this.yakumanMultiplier = 0});

  bool get isYakuman => yakumanMultiplier > 0;

  @override
  List<Object?> get props => [id, han, yakumanMultiplier];

  @override
  String toString() => '${id.name}:$han';
}

/// 和了形の種類。
enum WinShape { standard, chiitoitsu, kokushi }

/// 分け方の中の 1 ブロック。
enum WinGroupType { sequence, triplet, quad, pair }

/// 分け方の 1 ブロック（面子か雀頭）。
class WinGroup extends Equatable {
  final WinGroupType type;

  /// 先頭の牌（ラベル、赤は 5 に直す）。順子なら一番小さい牌。
  final String tile;

  /// 副露（暗槓を含む）から来た面子なら、その種類。
  final CalledMeldType? meld;

  /// 暗刻・暗槓として数えるか（ロンで完成した刻子は false）。順子・雀頭は false。
  final bool concealed;

  const WinGroup({
    required this.type,
    required this.tile,
    this.meld,
    this.concealed = false,
  });

  /// ブロックの牌（ラベル、赤は 5 に直す）。
  List<String> get tiles {
    final value = int.parse(tile[0]);
    final suit = tile[1];
    switch (type) {
      case WinGroupType.sequence:
        return ['$value$suit', '${value + 1}$suit', '${value + 2}$suit'];
      case WinGroupType.triplet:
        return [tile, tile, tile];
      case WinGroupType.quad:
        return [tile, tile, tile, tile];
      case WinGroupType.pair:
        return [tile, tile];
    }
  }

  @override
  List<Object?> get props => [type, tile, meld, concealed];
}

/// 満貫以上の名称（点数の段階）。
enum HandRank {
  /// 満貫未満。
  none,
  mangan,
  haneman,
  baiman,
  sanbaiman,

  /// 数え役満（役満ではない役とドラで 13 翻以上）。
  kazoeYakuman,
  yakuman,
  doubleYakuman,
  tripleYakuman,
  quadrupleYakuman,
  quintupleYakuman,
  sextupleYakuman,
}

const Map<HandRank, String> _rankJaNames = {
  HandRank.none: '',
  HandRank.mangan: '満貫',
  HandRank.haneman: '跳満',
  HandRank.baiman: '倍満',
  HandRank.sanbaiman: '三倍満',
  HandRank.kazoeYakuman: '数え役満',
  HandRank.yakuman: '役満',
  HandRank.doubleYakuman: 'ダブル役満',
  HandRank.tripleYakuman: 'トリプル役満',
  HandRank.quadrupleYakuman: '四倍役満',
  HandRank.quintupleYakuman: '五倍役満',
  HandRank.sextupleYakuman: '六倍役満',
};

extension HandRankInfo on HandRank {
  /// 表示用の日本語名（満貫未満は空文字）。
  String get jaName => _rankJaNames[this]!;

  /// 満貫以上か。
  bool get isLimit => this != HandRank.none;

  /// 役満（数え役満を含む）か。
  bool get isYakumanLevel => index >= HandRank.kazoeYakuman.index;
}

/// 和了者が受け取る点と、誰がいくら払うか。
///
/// `...Base` は本場を含まない素点。本場はロンなら 300 × 本場を放銃者が、
/// ツモなら 100 × 本場を各自が足して払う。供託は [kyotakuPoints] として [total] にだけ足す。
class WinPayment extends Equatable {
  final WinType winType;
  final bool dealer;

  /// ロン: 放銃者の支払い（本場込み）。ツモなら 0。
  final int ron;
  final int ronBase;

  /// 子のツモ: 親の支払い（本場込み）。親のツモ・ロンなら 0。
  final int tsumoFromDealer;
  final int tsumoFromDealerBase;

  /// ツモ: 子 1 人の支払い（本場込み）。親のツモなら子 3 人がそれぞれこの額。ロンなら 0。
  final int tsumoFromChild;
  final int tsumoFromChildBase;

  /// 本場で増えた合計。
  final int honbaPoints;

  /// 供託（1000 × 本数）。
  final int kyotakuPoints;

  /// 和了者が受け取る合計（本場・供託込み）。
  final int total;

  /// 素点の合計（本場・供託を含まない）。
  final int baseTotal;

  const WinPayment({
    required this.winType,
    required this.dealer,
    required this.ron,
    required this.ronBase,
    required this.tsumoFromDealer,
    required this.tsumoFromDealerBase,
    required this.tsumoFromChild,
    required this.tsumoFromChildBase,
    required this.honbaPoints,
    required this.kyotakuPoints,
    required this.total,
    required this.baseTotal,
  });

  /// 基本点（満貫 = 2000）から支払いを求める（四人麻雀）。
  factory WinPayment.compute({
    required int basePoints,
    required bool dealer,
    required WinType winType,
    int honba = 0,
    int kyotaku = 0,
  }) {
    int ceil100(int v) => (v + 99) ~/ 100 * 100;
    final kyotakuPoints = 1000 * kyotaku;
    if (winType == WinType.ron) {
      final base = ceil100(basePoints * (dealer ? 6 : 4));
      final bonus = 300 * honba;
      return WinPayment(
        winType: winType,
        dealer: dealer,
        ron: base + bonus,
        ronBase: base,
        tsumoFromDealer: 0,
        tsumoFromDealerBase: 0,
        tsumoFromChild: 0,
        tsumoFromChildBase: 0,
        honbaPoints: bonus,
        kyotakuPoints: kyotakuPoints,
        total: base + bonus + kyotakuPoints,
        baseTotal: base,
      );
    }
    final each = 100 * honba;
    if (dealer) {
      final child = ceil100(basePoints * 2);
      return WinPayment(
        winType: winType,
        dealer: dealer,
        ron: 0,
        ronBase: 0,
        tsumoFromDealer: 0,
        tsumoFromDealerBase: 0,
        tsumoFromChild: child + each,
        tsumoFromChildBase: child,
        honbaPoints: each * 3,
        kyotakuPoints: kyotakuPoints,
        total: (child + each) * 3 + kyotakuPoints,
        baseTotal: child * 3,
      );
    }
    final fromDealer = ceil100(basePoints * 2);
    final fromChild = ceil100(basePoints);
    return WinPayment(
      winType: winType,
      dealer: dealer,
      ron: 0,
      ronBase: 0,
      tsumoFromDealer: fromDealer + each,
      tsumoFromDealerBase: fromDealer,
      tsumoFromChild: fromChild + each,
      tsumoFromChildBase: fromChild,
      honbaPoints: each * 3,
      kyotakuPoints: kyotakuPoints,
      total: fromDealer + each + (fromChild + each) * 2 + kyotakuPoints,
      baseTotal: fromDealer + fromChild * 2,
    );
  }

  @override
  List<Object?> get props => [
    winType,
    dealer,
    ron,
    ronBase,
    tsumoFromDealer,
    tsumoFromDealerBase,
    tsumoFromChild,
    tsumoFromChildBase,
    honbaPoints,
    kyotakuPoints,
    total,
    baseTotal,
  ];
}

/// 1 つの解釈（分け方 × 和了牌の取り方）の採点結果。
class WinResult extends Equatable {
  /// 数えた役（ドラ類を除く）。役満が成立したら役満だけ。
  final List<ScoredYaku> yaku;

  /// 役満に吸収されて数えなかった通常の役（表示用。役満でなければ空）。
  final List<ScoredYaku> suppressedYaku;

  /// ドラ・赤ドラ・裏ドラの枚数（表示用）。役満・役なしでは翻に足さない。
  final int doraCount;
  final int akaDoraCount;
  final int uraDoraCount;

  /// 翻（役＋ドラ類）。役満は 13 × 倍数。
  final int han;

  /// 符（切り上げ後。七対子 25、国士無双は 0）。
  final int fu;
  final List<FuPart> fuParts;

  /// 役満の倍数（役満でなければ 0。数え役満も 0）。
  final int yakumanMultiplier;
  final HandRank rank;

  /// 基本点（満貫 2000、跳満 3000、…、役満 8000 × 倍数）。
  final int basePoints;
  final WinPayment payment;
  final WaitType wait;

  /// 門前か（暗槓だけなら門前）。
  final bool closed;
  final WinShape shape;

  /// 分け方（標準形のみ。面子 4 つと雀頭。七対子・国士は空）。
  final List<WinGroup> groups;

  /// 和了牌で完成したブロック（[groups] の添字）。七対子・国士は null。
  final int? winningGroupIndex;

  const WinResult({
    required this.yaku,
    required this.suppressedYaku,
    required this.doraCount,
    required this.akaDoraCount,
    required this.uraDoraCount,
    required this.han,
    required this.fu,
    required this.fuParts,
    required this.yakumanMultiplier,
    required this.rank,
    required this.basePoints,
    required this.payment,
    required this.wait,
    required this.closed,
    required this.shape,
    required this.groups,
    required this.winningGroupIndex,
  });

  /// ドラ類の合計枚数。
  int get totalDora => doraCount + akaDoraCount + uraDoraCount;

  /// 役満（ダブル以上を含む。数え役満は含まない）か。
  bool get isYakuman => yakumanMultiplier > 0;

  /// 翻に足したドラ類（役満なら 0）。
  int get countedDora => isYakuman ? 0 : totalDora;

  @override
  List<Object?> get props => [
    yaku,
    suppressedYaku,
    doraCount,
    akaDoraCount,
    uraDoraCount,
    han,
    fu,
    fuParts,
    yakumanMultiplier,
    rank,
    basePoints,
    payment,
    wait,
    closed,
    shape,
    groups,
    winningGroupIndex,
  ];
}

/// 採点の結果。
sealed class WinOutcome {
  const WinOutcome();
}

/// 採点できた。[best] が高点法で選んだ解釈、[alternatives] はそれ以外で点数・役・待ちが
/// 違う解釈（よい順）。和了牌の取り方で点数が変わることを示すのに使う。
final class WinScored extends WinOutcome {
  final WinResult best;
  final List<WinResult> alternatives;
  const WinScored(this.best, this.alternatives);
}

/// 採点できなかった。
final class WinRejected extends WinOutcome {
  final WinError error;

  /// 補足（開発者向け。どの牌・副露が原因か等）。
  final String? detail;
  const WinRejected(this.error, [this.detail]);

  @override
  String toString() =>
      'WinRejected(${error.name}${detail == null ? '' : ': $detail'})';
}
