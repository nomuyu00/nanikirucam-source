import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/models.dart';

/// 役の種類（仕様 4.3、設計書 4.2）。
///
/// `HandAnalyzer` が返す役名（[Yaku.name]、役牌は [Yaku.variant] も見る）をすべて
/// [yakuIdOf] で対応付ける。並び順は同じ確度の中での表示順（役満 → 高い役 → 1 翻 →
/// リーチ・偶然役 → ドラ）。
enum YakuId {
  // 役満（仕様 4.3: 役満は「狙える」のみ表示）
  kokushi,
  kokushi13,
  suuankou,
  suuankouTanki,
  daisangen,
  shousuushii,
  daisuushii,
  tsuuiisou,
  ryuuiisou,
  chinroutou,
  chuuren,
  junseiChuuren,
  suukantsu,
  tenhou,
  chiihou,
  // 2 翻以上
  chinitsu,
  honitsu,
  junchan,
  ryanpeikou,
  chanta,
  sanshoku,
  ittsu,
  toitoi,
  sanankou,
  shousangen,
  sanshokuDoukou,
  sankantsu,
  honroutou,
  chiitoitsu,
  // 役牌・1 翻
  doubleWind,
  yakuhaiHaku,
  yakuhaiHatsu,
  yakuhaiChun,
  yakuhaiSeatWind,
  yakuhaiRoundWind,
  tanyao,
  pinfu,
  iipeikou,
  // リーチ・和了の状況で付く役
  riichi,
  doubleRiichi,
  ippatsu,
  menzenTsumo,
  haitei,
  houtei,
  rinshan,
  chankan,
  renhou,
  // ドラ（役ではない。翻だけ足す）
  dora,
  akaDora,
  uraDora,
  kitaDora,
}

const Set<YakuId> _yakuman = {
  YakuId.kokushi,
  YakuId.kokushi13,
  YakuId.suuankou,
  YakuId.suuankouTanki,
  YakuId.daisangen,
  YakuId.shousuushii,
  YakuId.daisuushii,
  YakuId.tsuuiisou,
  YakuId.ryuuiisou,
  YakuId.chinroutou,
  YakuId.chuuren,
  YakuId.junseiChuuren,
  YakuId.suukantsu,
  YakuId.tenhou,
  YakuId.chiihou,
};

/// 手の形で決まらない（和了の状況やリーチ宣言で付く）もの。役の見込みには出さない。
const Set<YakuId> _situational = {
  YakuId.riichi,
  YakuId.doubleRiichi,
  YakuId.ippatsu,
  YakuId.menzenTsumo,
  YakuId.haitei,
  YakuId.houtei,
  YakuId.rinshan,
  YakuId.chankan,
  YakuId.renhou,
  YakuId.tenhou,
  YakuId.chiihou,
  YakuId.uraDora,
  YakuId.kitaDora,
};

const Map<YakuId, String> _jaNames = {
  YakuId.kokushi: '国士無双',
  YakuId.kokushi13: '国士無双十三面待ち',
  YakuId.suuankou: '四暗刻',
  YakuId.suuankouTanki: '四暗刻単騎',
  YakuId.daisangen: '大三元',
  YakuId.shousuushii: '小四喜',
  YakuId.daisuushii: '大四喜',
  YakuId.tsuuiisou: '字一色',
  YakuId.ryuuiisou: '緑一色',
  YakuId.chinroutou: '清老頭',
  YakuId.chuuren: '九蓮宝燈',
  YakuId.junseiChuuren: '純正九蓮宝燈',
  YakuId.suukantsu: '四槓子',
  YakuId.tenhou: '天和',
  YakuId.chiihou: '地和',
  YakuId.chinitsu: '清一色',
  YakuId.honitsu: '混一色',
  YakuId.junchan: '純全帯么九',
  YakuId.ryanpeikou: '二盃口',
  YakuId.chanta: '混全帯么九',
  YakuId.sanshoku: '三色同順',
  YakuId.ittsu: '一気通貫',
  YakuId.toitoi: '対々和',
  YakuId.sanankou: '三暗刻',
  YakuId.shousangen: '小三元',
  YakuId.sanshokuDoukou: '三色同刻',
  YakuId.sankantsu: '三槓子',
  YakuId.honroutou: '混老頭',
  YakuId.chiitoitsu: '七対子',
  YakuId.doubleWind: '連風牌',
  YakuId.yakuhaiHaku: '役牌 白',
  YakuId.yakuhaiHatsu: '役牌 發',
  YakuId.yakuhaiChun: '役牌 中',
  YakuId.yakuhaiSeatWind: '役牌 自風',
  YakuId.yakuhaiRoundWind: '役牌 場風',
  YakuId.tanyao: '断么九',
  YakuId.pinfu: '平和',
  YakuId.iipeikou: '一盃口',
  YakuId.riichi: '立直',
  YakuId.doubleRiichi: 'ダブル立直',
  YakuId.ippatsu: '一発',
  YakuId.menzenTsumo: '門前清自摸和',
  YakuId.haitei: '海底摸月',
  YakuId.houtei: '河底撈魚',
  YakuId.rinshan: '嶺上開花',
  YakuId.chankan: '槍槓',
  YakuId.renhou: '人和',
  YakuId.dora: 'ドラ',
  YakuId.akaDora: '赤ドラ',
  YakuId.uraDora: '裏ドラ',
  YakuId.kitaDora: '北ドラ',
};

extension YakuIdInfo on YakuId {
  /// 表示用の日本語名。
  String get jaName => _jaNames[this]!;

  /// 役満（ダブル役満を含む）か。
  bool get isYakuman => _yakuman.contains(this);

  /// ドラ類（役ではない）か。
  bool get isDora =>
      this == YakuId.dora ||
      this == YakuId.akaDora ||
      this == YakuId.uraDora ||
      this == YakuId.kitaDora;

  /// 手の形で決まり、候補ごとの「狙える役」に出すもの。
  ///
  /// リーチ（門前なら別に付ける）・偶然役・裏ドラ・北ドラは含まない。赤ドラは
  /// [YakuId.dora] にまとめる（仕様 4.3 の「ドラ（枚数）」）。
  bool get isProspect => !_situational.contains(this) && this != YakuId.akaDora;
}

/// `HandAnalyzer` が返す [Yaku] を [YakuId] にする。
///
/// 役牌は [Yaku.variant]（'白' / '發' / '中' / '自風 東' / '場風 南' など）で分ける。
/// 対応のない名前（variant の無い役牌など、`HandAnalyzer` が返さないもの）は null。
YakuId? yakuIdOf(Yaku yaku) {
  switch (yaku.name) {
    case '役牌':
      final variant = yaku.variant;
      if (variant == null) return null;
      if (variant == '白') return YakuId.yakuhaiHaku;
      if (variant == '發') return YakuId.yakuhaiHatsu;
      if (variant == '中') return YakuId.yakuhaiChun;
      if (variant.startsWith('自風')) return YakuId.yakuhaiSeatWind;
      if (variant.startsWith('場風')) return YakuId.yakuhaiRoundWind;
      return null;
    case 'ダブ東':
    case 'ダブ南':
    case 'ダブ西':
    case 'ダブ北':
      return YakuId.doubleWind;
  }
  return _byName[yaku.name];
}

final Map<String, YakuId> _byName = {
  for (final e in _jaNames.entries)
    if (e.key != YakuId.doubleWind && !e.value.startsWith('役牌 '))
      e.value: e.key,
};

/// 役の確度（仕様 4.3）。並び順は表示の優先順。
enum YakuConfidence {
  /// 確定: この打牌後、どの経路で和了しても成立する。
  certain,

  /// 濃厚: 重み付きで 7 割以上の経路で成立する。
  likely,

  /// 狙える: 成立する経路がある（[YakuProspect.enablingTiles] の牌を引けば）。
  possible,

  /// 消える: 打牌前の手の経路にはあったが、この打牌で成立しなくなる。
  lost,
}

/// 候補ごとの役の見込み（設計書 4.2）。
class YakuProspect extends Equatable {
  final YakuId yaku;
  final YakuConfidence confidence;

  /// 「狙える」のとき、成立させる牌（テンパイなら和了牌、一向聴なら最初に引く牌）。
  /// id の昇順。確定・濃厚・消えるでは空。
  final List<int> enablingTiles;

  /// 重み付きの成立割合 0..1（消えるは 0）。二向聴以上の目安では確定 1・狙える 0。
  final double rate;

  /// [YakuId.dora] のとき、打牌後の手（副露・赤を含む）にあるドラの枚数。他は null。
  final int? count;

  YakuProspect({
    required this.yaku,
    required this.confidence,
    List<int> enablingTiles = const [],
    this.rate = 0,
    this.count,
  }) : enablingTiles = List.unmodifiable(enablingTiles);

  @override
  List<Object?> get props => [yaku, confidence, enablingTiles, rate, count];

  @override
  String toString() {
    final tiles = enablingTiles.isEmpty ? '' : ' $enablingTiles';
    final n = count == null ? '' : ' x$count';
    return '${yaku.jaName}(${confidence.name}$n$tiles)';
  }
}
