import 'package:equatable/equatable.dart';
import 'package:mahjong_core/mahjong_core.dart';

/// 画面間の契約: 「この手を解析して」という入力（設計書 4.2、仕様 7.1）。
///
/// 写真（Recognition）・手入力・ライブ・問題ページ（Today / 共有リンク）のどこから来ても、
/// Quiz・Result・解析エンジンにはこの [HandInput] を渡す。画面はこれを直接 [HandState] に
/// 変換できる（[HandInput.toHandState]）。履歴・問題公開には [HandInput.toJson] を使う。
///
/// 牌は `1m`〜`9m` / `1p`〜`9p` / `1s`〜`9s` / `1z`〜`7z`（東南西北白發中）のラベルで持ち、
/// 赤5は `0m` `0p` `0s`。
class HandInput extends Equatable {
  /// 手牌（副露を除く）。ツモ牌がある場合も含む（位置は [tsumoIndex]）。
  final List<String> tiles;

  /// [tiles] の中でツモ牌（引いた牌）の添字。分からない・13 枚のときは null。
  final int? tsumoIndex;

  /// 副露（チー・ポン・カン）。
  final List<MeldInput> melds;

  /// ドラ表示牌（カンドラの表示牌も続けて入れる）。ドラそのものではない。
  final List<String> doraIndicators;

  /// 自風・場風。
  final Wind seatWind;
  final Wind roundWind;

  /// 親か。通常は `seatWind == Wind.east` と一致する（[withSeatWind] / [withDealer] で揃える）。
  final bool dealer;

  /// 巡目（1〜[maxTurn]）。上がりやすさの％に使う。未指定は null（中盤扱い）。
  final int? turn;

  /// 見えている牌（河・他家の副露。v1.1 以降）。表示牌は含めない。
  final List<String> visibleTiles;

  /// 解析できる手牌の枚数（副露込み。槓は 3 枚と数える）。
  static const int minTileCount = 13;
  static const int maxTileCount = 14;
  static const int maxTurn = 18;
  static const int maxDoraIndicators = 5;

  /// JSON の版。互換性を壊す変更をしたら上げる。
  static const int jsonVersion = 1;

  HandInput({
    required Iterable<String> tiles,
    this.tsumoIndex,
    Iterable<MeldInput> melds = const [],
    Iterable<String> doraIndicators = const [],
    this.seatWind = Wind.south,
    this.roundWind = Wind.east,
    bool? dealer,
    this.turn,
    Iterable<String> visibleTiles = const [],
  }) : tiles = List.unmodifiable(tiles),
       melds = List.unmodifiable(melds),
       doraIndicators = List.unmodifiable(doraIndicators),
       visibleTiles = List.unmodifiable(visibleTiles),
       dealer = dealer ?? seatWind == Wind.east;

  /// 何も入力していない状態（手入力の開始）。
  static final HandInput empty = HandInput(tiles: const []);

  // --- 派生値 ------------------------------------------------------------

  /// 副露込みの枚数。槓は 3 枚と数える（[HandState.tileCount] と同じ）。
  int get tileCount => tiles.length + 3 * melds.length;

  bool get hasTsumo =>
      tsumoIndex != null && tsumoIndex! >= 0 && tsumoIndex! < tiles.length;

  /// ツモ牌のラベル（なければ null）。
  String? get tsumoTile => hasTsumo ? tiles[tsumoIndex!] : null;

  /// 14 枚（ツモ後）か。
  bool get isFourteen => tileCount == maxTileCount;

  /// 副露が 1 つでもある（門前ではない）。暗槓だけなら門前扱い。
  bool get isOpen => melds.any((m) => m.isOpen);

  /// 手牌からツモ牌を除いた牌。
  List<String> get tilesWithoutTsumo => [
    for (var i = 0; i < tiles.length; i++)
      if (i != tsumoIndex) tiles[i],
  ];

  // --- 検証 --------------------------------------------------------------

  /// 解析に渡せない理由。空なら [toHandState] が成功する。
  List<HandInputIssue> validate() {
    final issues = <HandInputIssue>[];
    for (final label in [
      ...tiles,
      ...doraIndicators,
      ...visibleTiles,
      for (final m in melds) ...m.tiles,
    ]) {
      if (tileIdFromLabel(label) < 0) {
        issues.add(HandInputIssue(HandInputIssueKind.invalidLabel, label));
      }
    }
    if (issues.isNotEmpty) return issues;

    for (final meld in melds) {
      if (!meld.isValid) {
        issues.add(
          HandInputIssue(HandInputIssueKind.invalidMeld, meld.tiles.join(',')),
        );
      }
    }
    if (melds.length > 4) {
      issues.add(const HandInputIssue(HandInputIssueKind.invalidMeld));
    }
    final count = tileCount;
    if (count < minTileCount) {
      issues.add(HandInputIssue(HandInputIssueKind.tooFewTiles, '$count'));
    } else if (count > maxTileCount) {
      issues.add(HandInputIssue(HandInputIssueKind.tooManyTiles, '$count'));
    }
    final perTile = <int, int>{};
    for (final label in [...tiles, for (final m in melds) ...m.tiles]) {
      perTile.update(tileIdFromLabel(label), (v) => v + 1, ifAbsent: () => 1);
    }
    for (final entry in perTile.entries) {
      if (entry.value > 4) {
        issues.add(
          HandInputIssue(
            HandInputIssueKind.tooManyOfOneTile,
            tileLabelOfId(entry.key),
          ),
        );
      }
    }
    if (tsumoIndex != null && !hasTsumo) {
      issues.add(
        HandInputIssue(HandInputIssueKind.tsumoOutOfRange, '$tsumoIndex'),
      );
    }
    if (doraIndicators.length > maxDoraIndicators) {
      issues.add(
        HandInputIssue(
          HandInputIssueKind.tooManyDoraIndicators,
          '${doraIndicators.length}',
        ),
      );
    }
    final t = turn;
    if (t != null && (t < 1 || t > maxTurn)) {
      issues.add(HandInputIssue(HandInputIssueKind.invalidTurn, '$t'));
    }
    return issues;
  }

  /// 解析にかけられる（検証の指摘がない）。
  bool get isAnalyzable => validate().isEmpty;

  // --- 解析エンジンへの変換 -------------------------------------------------

  /// 解析エンジン（mahjong_core）の入力に変換する。
  ///
  /// ドラ表示牌は [HandState.doraIds]（ドラそのもの）に直し、表示牌と [visibleTiles] は
  /// 残り枚数の計算用に [HandState.visible] に入れる。赤5は [HandState.redIds]。
  /// 検証に通らない入力では [HandInputException] を投げる（先に [validate] で確認する）。
  HandState toHandState() {
    final issues = validate();
    if (issues.isNotEmpty) throw HandInputException(issues);

    final counts = List<int>.filled(kTileKinds, 0);
    final reds = <int>{};
    for (final label in tiles) {
      final id = tileIdFromLabel(label);
      counts[id]++;
      if (label.startsWith('0')) reds.add(id);
    }
    final openMelds = <Meld>[];
    for (final meld in melds) {
      openMelds.add(meld.toMeld());
      for (final label in meld.tiles) {
        if (label.startsWith('0')) reds.add(tileIdFromLabel(label));
      }
    }
    final visible = List<int>.filled(kTileKinds, 0);
    for (final label in [...doraIndicators, ...visibleTiles]) {
      visible[tileIdFromLabel(label)]++;
    }
    final doraIds = [
      for (final indicator in doraIndicators)
        tileIdFromLabel(doraFromIndicator(indicator)),
    ];
    return HandState(
      counts: counts,
      openMelds: openMelds,
      visible: visible,
      doraIds: doraIds,
      redIds: reds,
      seatWind: seatWind,
      roundWind: roundWind,
      dealer: dealer,
      turn: turn,
    );
  }

  // --- 変更 --------------------------------------------------------------

  static const Object _keep = Object();

  /// [tsumoIndex] と [turn] は null を渡すと消える（渡さなければそのまま）。
  HandInput copyWith({
    Iterable<String>? tiles,
    Object? tsumoIndex = _keep,
    Iterable<MeldInput>? melds,
    Iterable<String>? doraIndicators,
    Wind? seatWind,
    Wind? roundWind,
    bool? dealer,
    Object? turn = _keep,
    Iterable<String>? visibleTiles,
  }) {
    return HandInput(
      tiles: tiles ?? this.tiles,
      tsumoIndex: identical(tsumoIndex, _keep)
          ? this.tsumoIndex
          : tsumoIndex as int?,
      melds: melds ?? this.melds,
      doraIndicators: doraIndicators ?? this.doraIndicators,
      seatWind: seatWind ?? this.seatWind,
      roundWind: roundWind ?? this.roundWind,
      dealer: dealer ?? this.dealer,
      turn: identical(turn, _keep) ? this.turn : turn as int?,
      visibleTiles: visibleTiles ?? this.visibleTiles,
    );
  }

  /// 自風を変える。東なら親、それ以外は子にそろえる。
  HandInput withSeatWind(Wind wind) =>
      copyWith(seatWind: wind, dealer: wind == Wind.east);

  /// 親・子を変える。親なら自風を東に、子で自風が東なら南にそろえる。
  HandInput withDealer(bool isDealer) {
    if (isDealer) return copyWith(seatWind: Wind.east, dealer: true);
    return copyWith(
      seatWind: seatWind == Wind.east ? Wind.south : seatWind,
      dealer: false,
    );
  }

  /// 理牌した形: ツモ牌以外を萬・筒・索・字の順に並べ、ツモ牌を末尾にする。
  /// ツモ牌がなければ全体を並べる。
  HandInput normalized() {
    final tsumo = tsumoTile;
    final rest = tsumo == null ? [...tiles] : tilesWithoutTsumo;
    rest.sort(compareTileLabels);
    return copyWith(
      tiles: [...rest, ?tsumo],
      tsumoIndex: tsumo == null ? null : rest.length,
    );
  }

  // --- JSON --------------------------------------------------------------

  Map<String, Object?> toJson() => {
    'v': jsonVersion,
    'tiles': tiles,
    if (tsumoIndex != null) 'tsumoIndex': tsumoIndex,
    if (melds.isNotEmpty) 'melds': [for (final m in melds) m.toJson()],
    if (doraIndicators.isNotEmpty) 'dora': doraIndicators,
    'seatWind': seatWind.name,
    'roundWind': roundWind.name,
    'dealer': dealer,
    if (turn != null) 'turn': turn,
    if (visibleTiles.isNotEmpty) 'visible': visibleTiles,
  };

  /// [toJson] の逆。型が違う・必須項目がないときは [FormatException]。
  /// 風の名前が未知なら既定値（自風=南、場風=東）にする。
  factory HandInput.fromJson(Map<String, Object?> json) {
    List<String> strings(Object? value, String key) {
      if (value == null) return const [];
      if (value is! List || value.any((e) => e is! String)) {
        throw FormatException('HandInput: "$key" は文字列の配列', value);
      }
      return value.cast<String>();
    }

    final tilesJson = json['tiles'];
    if (tilesJson == null) {
      throw const FormatException('HandInput: "tiles" がない');
    }
    final tsumo = json['tsumoIndex'];
    if (tsumo != null && tsumo is! int) {
      throw FormatException('HandInput: "tsumoIndex" は整数', tsumo);
    }
    final turnJson = json['turn'];
    if (turnJson != null && turnJson is! int) {
      throw FormatException('HandInput: "turn" は整数', turnJson);
    }
    final meldsJson = json['melds'];
    if (meldsJson != null && meldsJson is! List) {
      throw FormatException('HandInput: "melds" は配列', meldsJson);
    }
    final dealerJson = json['dealer'];
    if (dealerJson != null && dealerJson is! bool) {
      throw FormatException('HandInput: "dealer" は真偽値', dealerJson);
    }
    return HandInput(
      tiles: strings(tilesJson, 'tiles'),
      tsumoIndex: tsumo as int?,
      melds: [
        for (final m in (meldsJson as List?) ?? const [])
          if (m is Map)
            MeldInput.fromJson(m.cast<String, Object?>())
          else
            throw FormatException('HandInput: "melds" の要素が不正', m),
      ],
      doraIndicators: strings(json['dora'], 'dora'),
      seatWind: _windFromName(json['seatWind']) ?? Wind.south,
      roundWind: _windFromName(json['roundWind']) ?? Wind.east,
      dealer: dealerJson as bool?,
      turn: turnJson as int?,
      visibleTiles: strings(json['visible'], 'visible'),
    );
  }

  @override
  List<Object?> get props => [
    tiles,
    tsumoIndex,
    melds,
    doraIndicators,
    seatWind,
    roundWind,
    dealer,
    turn,
    visibleTiles,
  ];

  @override
  String toString() =>
      'HandInput(${tiles.join(' ')}'
      '${tsumoIndex == null ? '' : ' ツモ=${tiles[tsumoIndex!]}'}'
      '${melds.isEmpty ? '' : ' 副露=$melds'}'
      '${doraIndicators.isEmpty ? '' : ' ドラ表示=${doraIndicators.join(' ')}'}'
      ' 自風=${seatWind.name} 場風=${roundWind.name}'
      '${dealer ? ' 親' : ''}${turn == null ? '' : ' $turn巡目'})';
}

Wind? _windFromName(Object? name) {
  for (final wind in Wind.values) {
    if (wind.name == name) return wind;
  }
  return null;
}

/// 牌の id（0–8 萬、9–17 筒、18–26 索、27–33 字）から通常の牌のラベル（赤5にはならない）を返す。
String tileLabelOfId(int id) {
  if (id >= 27) return '${id - 26}z';
  return '${id % 9 + 1}${const ['m', 'p', 's'][id ~/ 9]}';
}

/// 副露の種類。
enum MeldKind {
  /// チー（順子）。
  chi,

  /// ポン（刻子）。
  pon,

  /// 明槓（大明槓・加槓）。
  minkan,

  /// 暗槓（門前のまま）。
  ankan,
}

/// 副露 1 組。[tiles] は 3 枚（チー・ポン）か 4 枚（槓）。
class MeldInput extends Equatable {
  final MeldKind kind;
  final List<String> tiles;

  MeldInput({required this.kind, required Iterable<String> tiles})
    : tiles = List.unmodifiable(tiles);

  bool get isKan => kind == MeldKind.minkan || kind == MeldKind.ankan;

  /// 暗槓以外は副露（明らかになっている）。
  bool get isOpen => kind != MeldKind.ankan;

  /// 牌のラベルと枚数が種類と矛盾しない。
  bool get isValid {
    if (tiles.any((t) => tileIdFromLabel(t) < 0)) return false;
    final ids = tiles.map(tileIdFromLabel).toList()..sort();
    switch (kind) {
      case MeldKind.chi:
        if (ids.length != 3) return false;
        return ids.first < 27 &&
            ids.first ~/ 9 == ids.last ~/ 9 &&
            ids[1] == ids[0] + 1 &&
            ids[2] == ids[1] + 1;
      case MeldKind.pon:
        return ids.length == 3 && ids.toSet().length == 1;
      case MeldKind.minkan:
      case MeldKind.ankan:
        return ids.length == 4 && ids.toSet().length == 1;
    }
  }

  /// mahjong_core の [Meld] に変換する。
  Meld toMeld() => Meld(
    type: switch (kind) {
      MeldKind.chi => MeldType.shuntsu,
      MeldKind.pon => MeldType.koutsu,
      MeldKind.minkan || MeldKind.ankan => MeldType.kantsu,
    },
    tiles: [for (final t in tiles) tileFromLabel(t)],
    open: isOpen,
  );

  /// 牌の並びから副露の種類を推定する。チー・ポン・槓のどれでもなければ null。
  /// 槓は明槓とする（暗槓かどうかは見た目では分からないので、ユーザーが選ぶ）。
  static MeldKind? guessKind(List<String> labels) {
    if (labels.any((t) => tileIdFromLabel(t) < 0)) return null;
    final ids = labels.map(tileIdFromLabel).toList()..sort();
    if (ids.length == 4 && ids.toSet().length == 1) return MeldKind.minkan;
    if (ids.length != 3) return null;
    if (ids.toSet().length == 1) return MeldKind.pon;
    if (MeldInput(kind: MeldKind.chi, tiles: labels).isValid) {
      return MeldKind.chi;
    }
    return null;
  }

  Map<String, Object?> toJson() => {'kind': kind.name, 'tiles': tiles};

  factory MeldInput.fromJson(Map<String, Object?> json) {
    final kindName = json['kind'];
    final kind = MeldKind.values.where((k) => k.name == kindName).firstOrNull;
    final tilesJson = json['tiles'];
    if (kind == null) {
      throw FormatException('MeldInput: "kind" が不正', kindName);
    }
    if (tilesJson is! List || tilesJson.any((e) => e is! String)) {
      throw FormatException('MeldInput: "tiles" は文字列の配列', tilesJson);
    }
    return MeldInput(kind: kind, tiles: tilesJson.cast<String>());
  }

  @override
  List<Object?> get props => [kind, tiles];

  @override
  String toString() => '${kind.name}(${tiles.join(' ')})';
}

/// [HandInput.validate] の指摘の種類。画面側で文言にする。
enum HandInputIssueKind {
  /// 牌のラベルではない文字列がある（detail = そのラベル）。
  invalidLabel,

  /// 13 枚に満たない（detail = 現在の枚数）。
  tooFewTiles,

  /// 14 枚を超える（detail = 現在の枚数）。
  tooManyTiles,

  /// 同じ牌が 4 枚を超える（detail = ラベル）。
  tooManyOfOneTile,

  /// 副露が不正（detail = 牌のラベル）。
  invalidMeld,

  /// ツモ牌の位置が手牌の範囲外（detail = 添字）。
  tsumoOutOfRange,

  /// ドラ表示牌が多すぎる（detail = 枚数）。
  tooManyDoraIndicators,

  /// 巡目が範囲外（detail = 巡目）。
  invalidTurn,
}

class HandInputIssue extends Equatable {
  final HandInputIssueKind kind;
  final String? detail;

  const HandInputIssue(this.kind, [this.detail]);

  @override
  List<Object?> get props => [kind, detail];

  @override
  String toString() =>
      'HandInputIssue(${kind.name}${detail == null ? '' : ': $detail'})';
}

/// 検証に通らない [HandInput] を [HandInput.toHandState] に渡したとき。
class HandInputException implements Exception {
  final List<HandInputIssue> issues;

  const HandInputException(this.issues);

  @override
  String toString() => 'HandInputException($issues)';
}

/// 牌ラベルの並び順（萬・筒・索・字、数の小さい順、赤5は同じ5の中で先頭）。
int compareTileLabels(String a, String b) {
  final suit = _suitOrder(a).compareTo(_suitOrder(b));
  if (suit != 0) return suit;
  final value = _tileValue(a).compareTo(_tileValue(b));
  if (value != 0) return value;
  return a.compareTo(b);
}

int _suitOrder(String label) {
  if (label.length < 2) return 4;
  return switch (label[1]) {
    'm' => 0,
    'p' => 1,
    's' => 2,
    'z' => 3,
    _ => 4,
  };
}

int _tileValue(String label) {
  final value = label.isEmpty ? 0 : int.tryParse(label[0]) ?? 0;
  if (label.endsWith('z')) return value;
  return value == 0 ? 5 : value;
}
