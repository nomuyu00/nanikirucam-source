import 'package:equatable/equatable.dart';

enum Wind { east, south, west, north }

enum ParentChild { parent, child }

enum WinType { tsumo, ron }

class QuickContext extends Equatable {
  final Wind roundWind; // 場風
  final Wind seatWind; // 自風
  final ParentChild parentChild; // 親/子
  final WinType winType; // ツモ/ロン
  final bool riichi;
  final bool doubleRiichi;
  final bool ippatsu;
  final bool renhou;
  final int kanDoraIndicators; // カンドラ枚数
  final int uraDoraIndicators; // 裏ドラ枚数
  final int kanUraIndicators; // カン裏枚数
  final bool openMelds; // 副露があり（食い下がり判定に使用）
  final bool chankan; // 槍槓
  final bool rinshan; // 嶺上
  final bool haitei; // 海底
  final bool houtei; // 河底
  final bool tenho; // 天和
  final bool chiho; // 地和
  final int doraIndicators; // 表/カン/裏の合計枚数（UIで入力）
  final bool redFivesManual; // 手動切替
  final int honba; // 本場数（積み棒）
  final int kyotaku; // 供託
  final int nukiDora; // 三麻の抜きドラ（北）枚数

  const QuickContext({
    this.roundWind = Wind.east,
    this.seatWind = Wind.east,
    this.parentChild = ParentChild.parent,
    this.winType = WinType.ron,
    this.riichi = false,
    this.doubleRiichi = false,
    this.ippatsu = false,
    this.renhou = false,
    this.kanDoraIndicators = 0,
    this.uraDoraIndicators = 0,
    this.kanUraIndicators = 0,
    this.openMelds = false,
    this.chankan = false,
    this.rinshan = false,
    this.haitei = false,
    this.houtei = false,
    this.tenho = false,
    this.chiho = false,
    this.doraIndicators = 0,
    this.redFivesManual = false,
    this.honba = 0,
    this.kyotaku = 0,
    this.nukiDora = 0,
  });

  bool get isDealer => parentChild == ParentChild.parent;

  /// 自風を変えると親/子も連動させる（東家＝親）。
  QuickContext withSeatWind(Wind wind) => copyWith(
    seatWind: wind,
    parentChild: wind == Wind.east ? ParentChild.parent : ParentChild.child,
  );

  /// 親/子を変えると自風も矛盾しない値にそろえる。
  QuickContext withDealer(bool dealer) {
    if (dealer) {
      return copyWith(seatWind: Wind.east, parentChild: ParentChild.parent);
    }
    return copyWith(
      seatWind: seatWind == Wind.east ? Wind.south : seatWind,
      parentChild: ParentChild.child,
    );
  }

  /// 次の手に持ち越さない状態（リーチ・偶然役・ドラ・副露・ツモ）を戻す。
  /// 風・本場・供託は局をまたいで使うので残す。
  QuickContext nextHand() => QuickContext(
    roundWind: roundWind,
    seatWind: seatWind,
    parentChild: parentChild,
    honba: honba,
    kyotaku: kyotaku,
  );

  QuickContext copyWith({
    Wind? roundWind,
    Wind? seatWind,
    ParentChild? parentChild,
    WinType? winType,
    bool? riichi,
    bool? doubleRiichi,
    bool? ippatsu,
    bool? renhou,
    int? kanDoraIndicators,
    int? uraDoraIndicators,
    int? kanUraIndicators,
    bool? openMelds,
    bool? chankan,
    bool? rinshan,
    bool? haitei,
    bool? houtei,
    bool? tenho,
    bool? chiho,
    int? doraIndicators,
    bool? redFivesManual,
    int? honba,
    int? kyotaku,
    int? nukiDora,
  }) {
    return QuickContext(
      roundWind: roundWind ?? this.roundWind,
      seatWind: seatWind ?? this.seatWind,
      parentChild: parentChild ?? this.parentChild,
      winType: winType ?? this.winType,
      riichi: riichi ?? this.riichi,
      doubleRiichi: doubleRiichi ?? this.doubleRiichi,
      ippatsu: ippatsu ?? this.ippatsu,
      renhou: renhou ?? this.renhou,
      kanDoraIndicators: kanDoraIndicators ?? this.kanDoraIndicators,
      uraDoraIndicators: uraDoraIndicators ?? this.uraDoraIndicators,
      kanUraIndicators: kanUraIndicators ?? this.kanUraIndicators,
      openMelds: openMelds ?? this.openMelds,
      chankan: chankan ?? this.chankan,
      rinshan: rinshan ?? this.rinshan,
      haitei: haitei ?? this.haitei,
      houtei: houtei ?? this.houtei,
      tenho: tenho ?? this.tenho,
      chiho: chiho ?? this.chiho,
      doraIndicators: doraIndicators ?? this.doraIndicators,
      redFivesManual: redFivesManual ?? this.redFivesManual,
      honba: honba ?? this.honba,
      kyotaku: kyotaku ?? this.kyotaku,
      nukiDora: nukiDora ?? this.nukiDora,
    );
  }

  @override
  List<Object?> get props => [
    roundWind,
    seatWind,
    parentChild,
    winType,
    riichi,
    doubleRiichi,
    ippatsu,
    renhou,
    kanDoraIndicators,
    uraDoraIndicators,
    kanUraIndicators,
    openMelds,
    chankan,
    rinshan,
    haitei,
    houtei,
    tenho,
    chiho,
    doraIndicators,
    redFivesManual,
    honba,
    kyotaku,
    nukiDora,
  ];
}

/// 和了の4回に3回は子なので、初期値は南家（子）にする。
const initialQuickContext = QuickContext(
  seatWind: Wind.south,
  parentChild: ParentChild.child,
);
