// 和了の点数画面（Pro）の状態と、WinScorer への入力の組み立て。
//
// 画面（win_score_page.dart）は [WinHand]（手牌と和了牌の位置）と [WinConditions]
// （ツモ/ロン・リーチ・風・ドラ・偶然役・本場・供託）を持ち、変えるたびに
// [scoreWin] で採点し直す（1 回数 µs なのでキャッシュしない）。
//
// 偶然役（海底・河底・嶺上・槍槓・天和・地和）と一発は、いまの条件で成立し得ないものを
// [situationBlocker] で無効にし、ツモ/ロン・リーチ・自風を変えたときは
// [WinConditions.sanitized] で成立しなくなったものを外す（矛盾のエラーを出さないため）。
import 'package:equatable/equatable.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';

/// リーチの種類。
enum RiichiKind { none, riichi, doubleRiichi }

/// 偶然役（チップで選ぶもの）。表示順。
enum WinSituation { haitei, houtei, rinshan, chankan, tenhou, chiihou }

extension WinSituationInfo on WinSituation {
  YakuId get yakuId => switch (this) {
    WinSituation.haitei => YakuId.haitei,
    WinSituation.houtei => YakuId.houtei,
    WinSituation.rinshan => YakuId.rinshan,
    WinSituation.chankan => YakuId.chankan,
    WinSituation.tenhou => YakuId.tenhou,
    WinSituation.chiihou => YakuId.chiihou,
  };
}

/// 本場・供託の上限（ステッパー）。
const int kMaxHonba = 20;
const int kMaxKyotaku = 20;

/// 和了の手: 門前の牌（副露を除く）・副露・和了牌の位置。
class WinHand extends Equatable {
  WinHand({
    required Iterable<String> tiles,
    required this.winIndex,
    Iterable<MeldInput> melds = const [],
  }) : tiles = List.unmodifiable(tiles),
       melds = List.unmodifiable(melds);

  /// [input] から作る。和了牌は [HandInput.tsumoIndex]（無ければ末尾）。
  factory WinHand.fromInput(HandInput input) {
    final tiles = input.tiles;
    final index = input.hasTsumo
        ? input.tsumoIndex!
        : (tiles.isEmpty ? 0 : tiles.length - 1);
    return WinHand(tiles: tiles, winIndex: index, melds: input.melds);
  }

  final List<String> tiles;
  final int winIndex;
  final List<MeldInput> melds;

  String? get winningTile =>
      winIndex >= 0 && winIndex < tiles.length ? tiles[winIndex] : null;

  /// 暗槓を除く副露があるか。
  bool get isOpen => melds.any((m) => m.isOpen);
  bool get hasKan => melds.any((m) => m.isKan);

  /// 副露込みの枚数（槓は 3 枚）。
  int get tileCount => tiles.length + 3 * melds.length;

  /// 表示の並び: 和了牌以外を理牌順に並べ、和了牌を末尾にする（[tiles] の添字）。
  List<int> get displayOrder {
    final rest = [
      for (var i = 0; i < tiles.length; i++)
        if (i != winIndex) i,
    ]..sort((a, b) => compareTileLabels(tiles[a], tiles[b]));
    return [...rest, if (winningTile != null) winIndex];
  }

  WinHand withWinIndex(int index) =>
      WinHand(tiles: tiles, winIndex: index, melds: melds);

  /// 和了牌をツモ牌にした [HandInput]（共有カード・修正画面に渡す）。
  HandInput toHandInput(WinConditions c) => HandInput(
    tiles: tiles,
    tsumoIndex: winningTile == null ? null : winIndex,
    melds: melds,
    doraIndicators: c.doraIndicators,
    seatWind: c.seatWind,
    roundWind: c.roundWind,
  );

  /// [label]（赤5は 5 と同じに数える）が手牌・副露にいくつあるか。
  int countOf(String label) {
    final id = tileIdFromLabel(label);
    var n = 0;
    for (final t in [...tiles, for (final m in melds) ...m.tiles]) {
      if (tileIdFromLabel(t) == id) n++;
    }
    return n;
  }

  @override
  List<Object?> get props => [tiles, winIndex, melds];
}

/// 和了の条件。
class WinConditions extends Equatable {
  WinConditions({
    this.winType = WinType.tsumo,
    this.riichi = RiichiKind.none,
    this.ippatsu = false,
    this.roundWind = Wind.east,
    this.seatWind = Wind.south,
    this.honba = 0,
    this.kyotaku = 0,
    Iterable<String> doraIndicators = const [],
    Iterable<String> uraIndicators = const [],
    Set<WinSituation> situations = const {},
  }) : doraIndicators = List.unmodifiable(doraIndicators),
       uraIndicators = List.unmodifiable(uraIndicators),
       situations = Set.unmodifiable(situations);

  /// [input] の風・ドラ表示牌を初期値にする（ツモ・リーチなし）。
  factory WinConditions.fromInput(HandInput input) => WinConditions(
    roundWind: input.roundWind,
    seatWind: input.seatWind,
    doraIndicators: input.doraIndicators.take(HandInput.maxDoraIndicators),
  );

  final WinType winType;
  final RiichiKind riichi;
  final bool ippatsu;
  final Wind roundWind;

  /// 自風。東なら親。
  final Wind seatWind;
  final int honba;
  final int kyotaku;
  final List<String> doraIndicators;

  /// 裏ドラ表示牌（リーチのときだけ使う）。
  final List<String> uraIndicators;
  final Set<WinSituation> situations;

  bool get dealer => seatWind == Wind.east;
  bool get isRiichi => riichi != RiichiKind.none;
  bool get isTsumo => winType == WinType.tsumo;
  bool get hasBlessing =>
      situations.contains(WinSituation.tenhou) ||
      situations.contains(WinSituation.chiihou);

  /// 「その他の条件」に入れたものの数（偶然役・本場・供託）。
  int get extraCount =>
      situations.length + (honba > 0 ? 1 : 0) + (kyotaku > 0 ? 1 : 0);

  WinConditions copyWith({
    WinType? winType,
    RiichiKind? riichi,
    bool? ippatsu,
    Wind? roundWind,
    Wind? seatWind,
    int? honba,
    int? kyotaku,
    List<String>? doraIndicators,
    List<String>? uraIndicators,
    Set<WinSituation>? situations,
  }) => WinConditions(
    winType: winType ?? this.winType,
    riichi: riichi ?? this.riichi,
    ippatsu: ippatsu ?? this.ippatsu,
    roundWind: roundWind ?? this.roundWind,
    seatWind: seatWind ?? this.seatWind,
    honba: honba ?? this.honba,
    kyotaku: kyotaku ?? this.kyotaku,
    doraIndicators: doraIndicators ?? this.doraIndicators,
    uraIndicators: uraIndicators ?? this.uraIndicators,
    situations: situations ?? this.situations,
  );

  /// 偶然役をひとつ切り替える。
  WinConditions toggle(WinSituation s) {
    final next = {...situations};
    if (!next.remove(s)) next.add(s);
    return copyWith(situations: next);
  }

  /// いまの手と条件で成立しなくなった一発・偶然役を外す（ツモ/ロン・リーチ・自風・
  /// 和了牌を変えたあとに呼ぶ）。副露しているならリーチも外す。
  WinConditions sanitized(WinHand hand) {
    var c = this;
    if (hand.isOpen && c.isRiichi) {
      c = c.copyWith(riichi: RiichiKind.none);
    }
    // 外すと別の役が成立し得るようになることはない（条件が減るだけ）ので、1 回で足りる。
    var changed = true;
    while (changed) {
      changed = false;
      if (c.ippatsu && ippatsuBlocker(hand, c) != null) {
        c = c.copyWith(ippatsu: false);
        changed = true;
      }
      for (final s in WinSituation.values) {
        if (c.situations.contains(s) &&
            situationBlocker(s, hand, c, ignoreSelf: true) != null) {
          c = c.copyWith(situations: {...c.situations}..remove(s));
          changed = true;
        }
      }
    }
    return c;
  }

  @override
  List<Object?> get props => [
    winType,
    riichi,
    ippatsu,
    roundWind,
    seatWind,
    honba,
    kyotaku,
    doraIndicators,
    uraIndicators,
    situations,
  ];
}

/// 一発を選べない理由（選べるなら null）。
WinError? ippatsuBlocker(WinHand hand, WinConditions c) {
  if (!c.isRiichi) return WinError.ippatsuWithoutRiichi;
  if (c.situations.contains(WinSituation.rinshan)) {
    return WinError.ippatsuWithRinshan;
  }
  return null;
}

/// リーチを選べない理由（選べるなら null）。
WinError? riichiBlocker(WinHand hand) =>
    hand.isOpen ? WinError.riichiWithOpenHand : null;

/// 偶然役 [s] を（いまの条件に加えて）選べない理由。選べるなら null。
///
/// [ignoreSelf] は「[s] がすでに選ばれているとき、自分自身との組み合わせは見ない」。
WinError? situationBlocker(
  WinSituation s,
  WinHand hand,
  WinConditions c, {
  bool ignoreSelf = true,
}) {
  final others = {...c.situations};
  if (ignoreSelf) others.remove(s);
  final blessing =
      others.contains(WinSituation.tenhou) ||
      others.contains(WinSituation.chiihou);
  switch (s) {
    case WinSituation.haitei:
      if (!c.isTsumo) return WinError.haiteiWithoutTsumo;
      if (others.contains(WinSituation.rinshan)) {
        return WinError.haiteiWithRinshan;
      }
      if (blessing) return WinError.blessingWithOtherSituation;
    case WinSituation.houtei:
      if (c.isTsumo) return WinError.houteiWithTsumo;
      if (others.contains(WinSituation.chankan)) {
        return WinError.houteiWithChankan;
      }
      if (blessing) return WinError.blessingWithOtherSituation;
    case WinSituation.rinshan:
      if (!c.isTsumo) return WinError.rinshanWithoutTsumo;
      if (!hand.hasKan) return WinError.rinshanWithoutKan;
      if (others.contains(WinSituation.haitei)) {
        return WinError.haiteiWithRinshan;
      }
      if (c.ippatsu) return WinError.ippatsuWithRinshan;
      if (blessing) return WinError.blessingWithOtherSituation;
    case WinSituation.chankan:
      if (c.isTsumo) return WinError.chankanWithTsumo;
      if (others.contains(WinSituation.houtei)) {
        return WinError.houteiWithChankan;
      }
      final win = hand.winningTile;
      if (win != null && hand.countOf(win) >= 2) {
        return WinError.chankanImpossible;
      }
      if (blessing) return WinError.blessingWithOtherSituation;
    case WinSituation.tenhou:
    case WinSituation.chiihou:
      final tenhou = s == WinSituation.tenhou;
      if (tenhou && !c.dealer) return WinError.tenhouNotDealer;
      if (!tenhou && c.dealer) return WinError.chiihouAsDealer;
      if (!c.isTsumo) {
        return tenhou
            ? WinError.tenhouWithoutTsumo
            : WinError.chiihouWithoutTsumo;
      }
      if (hand.melds.isNotEmpty) {
        return tenhou ? WinError.tenhouWithMeld : WinError.chiihouWithMeld;
      }
      if (c.isRiichi || c.ippatsu || others.isNotEmpty) {
        return WinError.blessingWithOtherSituation;
      }
  }
  return null;
}

CalledMeld _calledMeld(MeldInput m) => switch (m.kind) {
  MeldKind.chi => CalledMeld.chi(m.tiles),
  MeldKind.pon => CalledMeld.pon(m.tiles),
  MeldKind.minkan => CalledMeld.minkan(m.tiles),
  MeldKind.ankan => CalledMeld.ankan(m.tiles),
};

/// [WinScorer] への入力にする。和了牌が無い（手牌が空）ときは '' を和了牌にする
/// （[WinError.invalidTile] になる）。
WinRequest buildWinRequest(WinHand hand, WinConditions c) => WinRequest(
  handTiles: hand.tiles,
  melds: [for (final m in hand.melds) _calledMeld(m)],
  winningTile: hand.winningTile ?? '',
  winType: c.winType,
  roundWind: c.roundWind,
  seatWind: c.seatWind,
  riichi: c.riichi == RiichiKind.riichi,
  doubleRiichi: c.riichi == RiichiKind.doubleRiichi,
  ippatsu: c.ippatsu,
  haitei: c.situations.contains(WinSituation.haitei),
  houtei: c.situations.contains(WinSituation.houtei),
  rinshan: c.situations.contains(WinSituation.rinshan),
  chankan: c.situations.contains(WinSituation.chankan),
  tenhou: c.situations.contains(WinSituation.tenhou),
  chiihou: c.situations.contains(WinSituation.chiihou),
  honba: c.honba,
  kyotaku: c.kyotaku,
  doraIndicators: c.doraIndicators,
  uraDoraIndicators: c.isRiichi ? c.uraIndicators : const [],
);

/// 設定のルール（赤ドラ・喰いタン）の [WinScorer]。Mリーグ相当が元。
WinScorer winScorerFor({required bool redFives, required bool openTanyao}) =>
    WinScorer(rulesetFromSettings(redFives: redFives, openTanyao: openTanyao));

/// 採点する。
WinOutcome scoreWin(WinScorer scorer, WinHand hand, WinConditions c) =>
    scorer.score(buildWinRequest(hand, c));

/// [best] と点数の違う解釈のうち、いちばんよいもの（なければ null）。
WinResult? differentScoreAlternative(WinScored scored) {
  for (final alt in scored.alternatives) {
    if (alt.payment.total != scored.best.payment.total &&
        alt.wait != scored.best.wait) {
      return alt;
    }
  }
  return null;
}

/// 手牌そのものを直す必要があるエラー（条件の切り替えでは直らない）。
bool isHandError(WinError e) => switch (e) {
  WinError.invalidTile ||
  WinError.invalidMeld ||
  WinError.wrongTileCount ||
  WinError.tooManyCopies ||
  WinError.tooManyRedFives ||
  WinError.winningTileNotInHand ||
  WinError.notWinningHand => true,
  _ => false,
};

/// 表示牌を足せるか（同じ牌が手牌・副露・表示牌の合計で 4 枚まで）。
bool canAddIndicator(String label, WinHand hand, WinConditions c) {
  final id = tileIdFromLabel(label);
  var n = hand.countOf(label);
  for (final t in [...c.doraIndicators, ...c.uraIndicators]) {
    if (tileIdFromLabel(t) == id) n++;
  }
  return n < 4;
}

/// 表示の並び: リーチ・一発・ツモ・偶然役を先に、残りは [YakuId] の順（役満 → 高い役 → 1 翻）。
const List<YakuId> _situationalOrder = [
  YakuId.doubleRiichi,
  YakuId.riichi,
  YakuId.ippatsu,
  YakuId.menzenTsumo,
  YakuId.rinshan,
  YakuId.chankan,
  YakuId.haitei,
  YakuId.houtei,
  YakuId.tenhou,
  YakuId.chiihou,
  YakuId.renhou,
];

/// 役を表示の順に並べる。
List<ScoredYaku> orderedYaku(Iterable<ScoredYaku> yaku) {
  int rank(ScoredYaku y) {
    final i = _situationalOrder.indexOf(y.id);
    return i >= 0 ? i : _situationalOrder.length + y.id.index;
  }

  return [...yaku]..sort((a, b) => rank(a).compareTo(rank(b)));
}

/// 計測の `rank`（`AppAnalytics` の許可リストの値）。
String winRankParam(HandRank rank) => switch (rank) {
  HandRank.none => 'none',
  HandRank.mangan => 'mangan',
  HandRank.haneman => 'haneman',
  HandRank.baiman => 'baiman',
  HandRank.sanbaiman => 'sanbaiman',
  _ => 'yakuman',
};
