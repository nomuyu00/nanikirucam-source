// 流用元: reference/agari_cam/lib/scoring/rulesets.dart（2026-10-21 時点）
enum MahjongMode { fourPlayer, threePlayer }

class Ruleset {
  final String name;
  final MahjongMode mode; // 四麻/三麻
  final bool sanmaTsumoLoss; // 三麻のツモ損あり
  final int redFives; // total aka dora count (m/p/s)
  final bool uraDora;
  final bool ippatsu;
  final bool countedYakuman; // kazoe
  // 四暗刻単騎・国士十三面・純正九蓮・大四喜をダブル役満にする
  final bool doubleYakuman;
  final bool
  kiriageMangan; // 60fu3han/30fu4han not applied by default in M-League (false)
  // — additional rule toggles —
  final bool kuitan; // 食いタン可
  final bool atozuke; // 後付け可
  final bool kanDora; // カンドラ
  final bool kanUra; // カン裏ドラ
  final bool yakumanMultiple; // 役満複合可
  final bool pao; // パオ責任払い
  final RenhouValue renhou; // 人和の価値
  final bool forbidKuikae; // 喰い替え禁止
  final int doubleWindPairFu; // 連風牌（ダブ東など）の雀頭: 2符 or 4符

  const Ruleset({
    required this.name,
    this.mode = MahjongMode.fourPlayer,
    this.sanmaTsumoLoss = true,
    this.redFives = 3,
    this.uraDora = true,
    this.ippatsu = true,
    this.countedYakuman = true,
    this.doubleYakuman = false,
    this.kiriageMangan = false,
    this.kuitan = true,
    this.atozuke = true,
    this.kanDora = true,
    this.kanUra = true,
    this.yakumanMultiple = true,
    this.pao = true,
    this.renhou = RenhouValue.none,
    this.forbidKuikae = true,
    this.doubleWindPairFu = 4,
  });

  Ruleset copyWith({
    String? name,
    MahjongMode? mode,
    bool? sanmaTsumoLoss,
    int? redFives,
    bool? uraDora,
    bool? ippatsu,
    bool? countedYakuman,
    bool? doubleYakuman,
    bool? kiriageMangan,
    bool? kuitan,
    bool? atozuke,
    bool? kanDora,
    bool? kanUra,
    bool? yakumanMultiple,
    bool? pao,
    RenhouValue? renhou,
    bool? forbidKuikae,
    int? doubleWindPairFu,
  }) {
    return Ruleset(
      name: name ?? this.name,
      mode: mode ?? this.mode,
      sanmaTsumoLoss: sanmaTsumoLoss ?? this.sanmaTsumoLoss,
      redFives: redFives ?? this.redFives,
      uraDora: uraDora ?? this.uraDora,
      ippatsu: ippatsu ?? this.ippatsu,
      countedYakuman: countedYakuman ?? this.countedYakuman,
      doubleYakuman: doubleYakuman ?? this.doubleYakuman,
      kiriageMangan: kiriageMangan ?? this.kiriageMangan,
      kuitan: kuitan ?? this.kuitan,
      atozuke: atozuke ?? this.atozuke,
      kanDora: kanDora ?? this.kanDora,
      kanUra: kanUra ?? this.kanUra,
      yakumanMultiple: yakumanMultiple ?? this.yakumanMultiple,
      pao: pao ?? this.pao,
      renhou: renhou ?? this.renhou,
      forbidKuikae: forbidKuikae ?? this.forbidKuikae,
      doubleWindPairFu: doubleWindPairFu ?? this.doubleWindPairFu,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'mode': mode.name,
    'sanmaTsumoLoss': sanmaTsumoLoss,
    'redFives': redFives,
    'uraDora': uraDora,
    'ippatsu': ippatsu,
    'countedYakuman': countedYakuman,
    'doubleYakuman': doubleYakuman,
    'kiriageMangan': kiriageMangan,
    'kuitan': kuitan,
    'kanDora': kanDora,
    'kanUra': kanUra,
    'yakumanMultiple': yakumanMultiple,
    'renhou': renhou.name,
    'doubleWindPairFu': doubleWindPairFu,
  };

  /// Restores saved settings on top of [base]; unknown or malformed values
  /// keep the base value so an old or corrupt file never blocks scoring.
  static Ruleset fromJson(Map<Object?, Object?> json, {Ruleset? base}) {
    final b = base ?? Rulesets.mLeague();
    bool flag(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    T byName<T extends Enum>(List<T> values, String key, T fallback) {
      final value = json[key];
      for (final v in values) {
        if (v.name == value) return v;
      }
      return fallback;
    }

    final red = json['redFives'];
    final windFu = json['doubleWindPairFu'];
    return b.copyWith(
      mode: byName(MahjongMode.values, 'mode', b.mode),
      sanmaTsumoLoss: flag('sanmaTsumoLoss', b.sanmaTsumoLoss),
      redFives: red is int && red >= 0 && red <= 4 ? red : b.redFives,
      uraDora: flag('uraDora', b.uraDora),
      ippatsu: flag('ippatsu', b.ippatsu),
      countedYakuman: flag('countedYakuman', b.countedYakuman),
      doubleYakuman: flag('doubleYakuman', b.doubleYakuman),
      kiriageMangan: flag('kiriageMangan', b.kiriageMangan),
      kuitan: flag('kuitan', b.kuitan),
      kanDora: flag('kanDora', b.kanDora),
      kanUra: flag('kanUra', b.kanUra),
      yakumanMultiple: flag('yakumanMultiple', b.yakumanMultiple),
      renhou: byName(RenhouValue.values, 'renhou', b.renhou),
      doubleWindPairFu: windFu == 2 || windFu == 4 ? windFu as int : null,
    );
  }
}

class Rulesets {
  static Ruleset mLeague() => const Ruleset(name: 'M-League-like');
}

enum RenhouValue { none, mangan, yakuman }
