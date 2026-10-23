import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/tile_utils.dart';

/// 牌の種類数（萬・筒・索 各 9 + 字 7）。
const int kTileKinds = 34;

/// [Tile] を 34 種のインデックス（0–8 萬、9–17 筒、18–26 索、27–33 字）に変換する。
int tileIdOf(Tile tile) {
  switch (tile.suit) {
    case Suit.m:
      return tile.value - 1;
    case Suit.p:
      return 9 + tile.value - 1;
    case Suit.s:
      return 18 + tile.value - 1;
    case Suit.z:
      return 27 + tile.value - 1;
  }
}

/// 解析エンジンへの入力（設計書 4.2）。
///
/// [counts] は手牌（副露を含まない）、[visible] はドラ表示牌・河・他家副露など
/// 自分の手と副露以外で見えている牌の枚数。どちらも長さ 34。
class HandState extends Equatable {
  final List<int> counts;
  final List<Meld> openMelds;
  final List<int> visible;
  final List<int> doraIds;
  final Set<int> redIds;
  final Wind seatWind;
  final Wind roundWind;
  final bool dealer;
  final int? turn;

  // 自分の副露に含まれる牌の枚数（槓は 4 枚）。
  final List<int> _meldTileCounts;

  HandState({
    required List<int> counts,
    List<Meld> openMelds = const [],
    List<int>? visible,
    List<int> doraIds = const [],
    Set<int> redIds = const {},
    this.seatWind = Wind.south,
    this.roundWind = Wind.east,
    this.dealer = false,
    this.turn,
  }) : counts = List.unmodifiable(counts),
       openMelds = List.unmodifiable(openMelds),
       visible = List.unmodifiable(visible ?? List<int>.filled(kTileKinds, 0)),
       doraIds = List.unmodifiable(doraIds),
       redIds = Set.unmodifiable(redIds),
       _meldTileCounts = _countMeldTiles(openMelds) {
    _validate();
  }

  /// ラベル列（'1m', '0p', '5z' など）から作る。'0m'/'0p'/'0s' は赤5として [redIds] に入る。
  factory HandState.fromLabels(
    Iterable<String> labels, {
    List<Meld> openMelds = const [],
    Iterable<String> visible = const [],
    List<int> doraIds = const [],
    Wind seatWind = Wind.south,
    Wind roundWind = Wind.east,
    bool dealer = false,
    int? turn,
  }) {
    final counts = List<int>.filled(kTileKinds, 0);
    final reds = <int>{};
    for (final label in labels) {
      final id = _idFromLabelOrThrow(label);
      counts[id]++;
      if (label.startsWith('0')) reds.add(id);
    }
    final seen = List<int>.filled(kTileKinds, 0);
    for (final label in visible) {
      seen[_idFromLabelOrThrow(label)]++;
    }
    return HandState(
      counts: counts,
      openMelds: openMelds,
      visible: seen,
      doraIds: doraIds,
      redIds: reds,
      seatWind: seatWind,
      roundWind: roundWind,
      dealer: dealer,
      turn: turn,
    );
  }

  /// 手牌（counts の合計）＋副露 3×n（槓も 3 として数える）。
  int get tileCount {
    var sum = 0;
    for (final c in counts) {
      sum += c;
    }
    return sum + 3 * openMelds.length;
  }

  /// 副露の数（暗槓を含む）。
  int get meldCount => openMelds.length;

  /// 自分の副露に含まれる [id] の枚数（槓は 4 枚）。
  int meldTileCount(int id) => _meldTileCounts[id];

  /// まだ山・他家の手にあり得る [id] の枚数。
  int remaining(int id) {
    final r = 4 - counts[id] - _meldTileCounts[id] - visible[id];
    return r < 0 ? 0 : r;
  }

  /// [id] を 1 枚切った後の状態。切った牌は河に出るので [visible] に移す。
  HandState discard(int id) {
    if (id < 0 || id >= kTileKinds || counts[id] == 0) {
      throw ArgumentError.value(id, 'id', '手牌にない牌は切れない');
    }
    final nextCounts = List<int>.of(counts);
    nextCounts[id]--;
    final nextVisible = List<int>.of(visible);
    nextVisible[id]++;
    return copyWith(counts: nextCounts, visible: nextVisible);
  }

  HandState copyWith({
    List<int>? counts,
    List<Meld>? openMelds,
    List<int>? visible,
    List<int>? doraIds,
    Set<int>? redIds,
    Wind? seatWind,
    Wind? roundWind,
    bool? dealer,
    int? turn,
  }) {
    return HandState(
      counts: counts ?? this.counts,
      openMelds: openMelds ?? this.openMelds,
      visible: visible ?? this.visible,
      doraIds: doraIds ?? this.doraIds,
      redIds: redIds ?? this.redIds,
      seatWind: seatWind ?? this.seatWind,
      roundWind: roundWind ?? this.roundWind,
      dealer: dealer ?? this.dealer,
      turn: turn ?? this.turn,
    );
  }

  void _validate() {
    if (counts.length != kTileKinds) {
      throw ArgumentError.value(counts.length, 'counts', '長さは 34');
    }
    if (visible.length != kTileKinds) {
      throw ArgumentError.value(visible.length, 'visible', '長さは 34');
    }
    if (openMelds.length > 4) {
      throw ArgumentError.value(openMelds.length, 'openMelds', '副露は 4 つまで');
    }
    for (final meld in openMelds) {
      if (meld.type == MeldType.pair) {
        throw ArgumentError.value(meld.type, 'openMelds', '対子は副露にできない');
      }
    }
    for (var i = 0; i < kTileKinds; i++) {
      if (counts[i] < 0 || visible[i] < 0) {
        throw ArgumentError('牌 $i の枚数が負');
      }
      if (counts[i] + _meldTileCounts[i] > 4) {
        throw ArgumentError('牌 $i が手牌と副露で 4 枚を超える');
      }
    }
  }

  static List<int> _countMeldTiles(List<Meld> melds) {
    final result = List<int>.filled(kTileKinds, 0);
    for (final meld in melds) {
      for (final tile in meld.tiles) {
        result[tileIdOf(tile)]++;
      }
    }
    return List.unmodifiable(result);
  }

  static int _idFromLabelOrThrow(String label) {
    final id = tileIdFromLabel(label);
    if (id < 0) throw ArgumentError.value(label, 'label', '牌のラベルではない');
    return id;
  }

  @override
  List<Object?> get props => [
    counts,
    openMelds,
    visible,
    doraIds,
    redIds,
    seatWind,
    roundWind,
    dealer,
    turn,
  ];
}
