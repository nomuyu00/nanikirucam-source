import 'package:equatable/equatable.dart';

enum Suit { m, p, s, z }

class Tile extends Equatable {
  final Suit suit; // man, pin, sou, honors
  final int
  value; // 1-9 (1-7 valid for honors as mapping E,S,W,N,P,F,C -> 1..7)
  final bool red; // aka 5
  const Tile(this.suit, this.value, {this.red = false});

  bool get isHonor => suit == Suit.z;
  bool get isTerminal => !isHonor && (value == 1 || value == 9);
  bool get isSimple => !isHonor && value >= 2 && value <= 8;

  @override
  List<Object?> get props => [suit, value, red];
}

enum MeldType { shuntsu, koutsu, kantsu, pair }

class Meld extends Equatable {
  final MeldType type;
  final List<Tile> tiles; // length 2/3/4
  final bool open;
  const Meld({required this.type, required this.tiles, required this.open});

  @override
  List<Object?> get props => [type, tiles, open];
}

class WinContext extends Equatable {
  final bool oya; // dealer
  final bool tsumo; // win by tsumo
  final bool riichi;
  final bool ippatsu;
  final int dora; // total visible + ura
  final int honba; // number of successive continuances
  final int kyotaku; // riichi sticks
  const WinContext({
    required this.oya,
    required this.tsumo,
    this.riichi = false,
    this.ippatsu = false,
    this.dora = 0,
    this.honba = 0,
    this.kyotaku = 0,
  });

  WinContext copyWith({
    bool? oya,
    bool? tsumo,
    bool? riichi,
    bool? ippatsu,
    int? dora,
    int? honba,
    int? kyotaku,
  }) {
    return WinContext(
      oya: oya ?? this.oya,
      tsumo: tsumo ?? this.tsumo,
      riichi: riichi ?? this.riichi,
      ippatsu: ippatsu ?? this.ippatsu,
      dora: dora ?? this.dora,
      honba: honba ?? this.honba,
      kyotaku: kyotaku ?? this.kyotaku,
    );
  }

  @override
  List<Object?> get props => [
    oya,
    tsumo,
    riichi,
    ippatsu,
    dora,
    honba,
    kyotaku,
  ];
}

class Hand extends Equatable {
  final List<Tile> tiles; // 14 tiles (including the winning tile)
  final List<Meld> openMelds; // calls
  const Hand({required this.tiles, this.openMelds = const []});

  @override
  List<Object?> get props => [tiles, openMelds];
}

class Yaku extends Equatable {
  final String name;
  final int hanClosed;
  final int hanOpen; // 0 if not available when open
  // Which tile made the yaku, e.g. '中' or '自風 南' for 役牌. Display only.
  final String? variant;
  const Yaku({
    required this.name,
    required this.hanClosed,
    required this.hanOpen,
    this.variant,
  });

  @override
  List<Object?> get props => [name, hanClosed, hanOpen, variant];
}

class AnalysisResult extends Equatable {
  final List<Yaku> yaku;
  final int han;
  final int fu;
  final int basePoints; // capped base (mangan=2000 etc.)
  final FuBreakdown? fuBreakdown;
  const AnalysisResult({
    required this.yaku,
    required this.han,
    required this.fu,
    required this.basePoints,
    this.fuBreakdown,
  });

  @override
  List<Object?> get props => [yaku, han, fu, basePoints, fuBreakdown];
}

class FuItem extends Equatable {
  final String label;
  final int value;
  const FuItem({required this.label, required this.value});

  @override
  List<Object?> get props => [label, value];
}

class FuBreakdown extends Equatable {
  final List<FuItem> items;
  final int total;
  const FuBreakdown({required this.items, required this.total});

  @override
  List<Object?> get props => [items, total];
}
