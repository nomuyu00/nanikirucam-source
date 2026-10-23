// 流用元: reference/agari_cam/lib/scoring/han_yaku.dart（2026-10-21 時点）
import 'package:mahjong_core/src/models.dart';

class YakuCatalog {
  static const String doraName = 'ドラ';
  static const String redDoraName = '赤ドラ';
  static const String uraDoraName = '裏ドラ';
  static const String nukiDoraName = '北ドラ';
  static const Set<String> doraNames = {
    doraName,
    redDoraName,
    uraDoraName,
    nukiDoraName,
  };

  /// ドラは翻を足すが役ではない（ドラだけでは和了できない）。
  static bool isDora(String name) => doraNames.contains(name);

  /// 役牌に「どの牌で成立したか」を付ける。
  static Yaku yakuhaiFor(String variant) => Yaku(
    name: yakuhai.name,
    hanClosed: yakuhai.hanClosed,
    hanOpen: yakuhai.hanOpen,
    variant: variant,
  );

  static const Yaku riichi = Yaku(name: '立直', hanClosed: 1, hanOpen: 0);
  static const Yaku ippatsu = Yaku(name: '一発', hanClosed: 1, hanOpen: 0);
  static const Yaku tsumo = Yaku(name: '門前清自摸和', hanClosed: 1, hanOpen: 0);
  static const Yaku tanyao = Yaku(name: '断么九', hanClosed: 1, hanOpen: 1);
  static const Yaku pinfu = Yaku(name: '平和', hanClosed: 1, hanOpen: 0);
  static const Yaku iipeikou = Yaku(name: '一盃口', hanClosed: 1, hanOpen: 0);
  static const Yaku ryanpeikou = Yaku(name: '二盃口', hanClosed: 3, hanOpen: 0);
  static const Yaku yakuhai = Yaku(name: '役牌', hanClosed: 1, hanOpen: 1);
  static const Yaku sanshoku = Yaku(name: '三色同順', hanClosed: 2, hanOpen: 1);
  static const Yaku ittsu = Yaku(name: '一気通貫', hanClosed: 2, hanOpen: 1);
  static const Yaku toitoi = Yaku(name: '対々和', hanClosed: 2, hanOpen: 2);
  static const Yaku sanankou = Yaku(name: '三暗刻', hanClosed: 2, hanOpen: 2);
  static const Yaku shousangen = Yaku(name: '小三元', hanClosed: 2, hanOpen: 2);
  static const Yaku honitsu = Yaku(name: '混一色', hanClosed: 3, hanOpen: 2);
  static const Yaku chinitsu = Yaku(name: '清一色', hanClosed: 6, hanOpen: 5);
  static const Yaku chitoitsu = Yaku(name: '七対子', hanClosed: 2, hanOpen: 0);
  static const Yaku chanta = Yaku(name: '混全帯么九', hanClosed: 2, hanOpen: 1);
  static const Yaku junchan = Yaku(name: '純全帯么九', hanClosed: 3, hanOpen: 2);
  static const Yaku daburii = Yaku(name: 'ダブル立直', hanClosed: 2, hanOpen: 0);
  static const Yaku chankan = Yaku(name: '槍槓', hanClosed: 1, hanOpen: 1);
  static const Yaku rinshan = Yaku(name: '嶺上開花', hanClosed: 1, hanOpen: 1);
  static const Yaku haitei = Yaku(name: '海底摸月', hanClosed: 1, hanOpen: 1);
  static const Yaku houtei = Yaku(name: '河底撈魚', hanClosed: 1, hanOpen: 1);
  static const Yaku tenho = Yaku(name: '天和', hanClosed: 13, hanOpen: 13);
  static const Yaku chiho = Yaku(name: '地和', hanClosed: 13, hanOpen: 13);
  static const Yaku kokushi = Yaku(name: '国士無双', hanClosed: 13, hanOpen: 0);
  static const Yaku ryuuiisou = Yaku(name: '緑一色', hanClosed: 13, hanOpen: 13);
  static const Yaku daisushi = Yaku(name: '大四喜', hanClosed: 13, hanOpen: 13);
  static const Yaku shosushi = Yaku(name: '小四喜', hanClosed: 13, hanOpen: 13);
  static const Yaku suuankou = Yaku(name: '四暗刻', hanClosed: 13, hanOpen: 0);
  static const Yaku chuuren = Yaku(name: '九蓮宝燈', hanClosed: 13, hanOpen: 0);
  static const Yaku chinroutou = Yaku(name: '清老頭', hanClosed: 13, hanOpen: 13);
  static const Yaku tsuiisou = Yaku(name: '字一色', hanClosed: 13, hanOpen: 13);
  static const Yaku doubleEast = Yaku(name: 'ダブ東', hanClosed: 2, hanOpen: 2);
  static const Yaku doubleSouth = Yaku(name: 'ダブ南', hanClosed: 2, hanOpen: 2);
  static const Yaku doubleWest = Yaku(name: 'ダブ西', hanClosed: 2, hanOpen: 2);
  static const Yaku doubleNorth = Yaku(name: 'ダブ北', hanClosed: 2, hanOpen: 2);
  static const Yaku daisangen = Yaku(name: '大三元', hanClosed: 13, hanOpen: 13);
  static const Yaku suukantsu = Yaku(name: '四槓子', hanClosed: 13, hanOpen: 13);
  static const Yaku sankantsu = Yaku(name: '三槓子', hanClosed: 2, hanOpen: 2);
  static const Yaku sanshokudoukou = Yaku(
    name: '三色同刻',
    hanClosed: 2,
    hanOpen: 2,
  );
  static const Yaku honroutou = Yaku(name: '混老頭', hanClosed: 2, hanOpen: 2);

  static List<Yaku> all() => const [
    riichi,
    daburii,
    ippatsu,
    tsumo,
    tanyao,
    pinfu,
    iipeikou,
    ryanpeikou,
    yakuhai,
    sanshoku,
    ittsu,
    toitoi,
    sanankou,
    shousangen,
    honitsu,
    chinitsu,
    chitoitsu,
    chanta,
    junchan,
    chankan,
    rinshan,
    haitei,
    houtei,
    tenho,
    chiho,
    kokushi,
    ryuuiisou,
    daisushi,
    shosushi,
    suuankou,
    chuuren,
    chinroutou,
    tsuiisou,
    daisangen,
    suukantsu,
    sankantsu,
    sanshokudoukou,
    honroutou,
    doubleEast,
    doubleSouth,
    doubleWest,
    doubleNorth,
  ];
}

int totalHan(List<Yaku> yakus, {required bool open}) {
  var han = 0;
  for (final y in yakus) {
    han += open ? y.hanOpen : y.hanClosed;
  }
  return han;
}
