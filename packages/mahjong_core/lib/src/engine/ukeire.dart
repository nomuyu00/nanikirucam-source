import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';

/// 受け入れ（設計書 4.4）。引くとシャンテン数が下がる牌と、その残り枚数。
class Ukeire extends Equatable {
  /// 牌 id → 残り枚数（id の昇順）。
  final Map<int, int> tiles;
  final int _total;

  Ukeire(Map<int, int> tiles)
    : tiles = Map.unmodifiable(
        Map.fromEntries(
          tiles.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
        ),
      ),
      _total = tiles.values.fold(0, (sum, n) => sum + n);

  /// 受け入れの種類数。
  int get kinds => tiles.length;

  /// 受け入れの合計枚数。
  int get total => _total;

  @override
  List<Object?> get props => [tiles];

  @override
  String toString() => 'Ukeire($kinds種$total枚 $tiles)';
}

/// 13 枚（副露込みで 3n+1 枚）の手の受け入れ。
///
/// 手の中に 4 枚ある牌と残り 0 枚の牌は除く。値は [HandState.remaining]。
Ukeire ukeire(HandState hand13) {
  if (hand13.tileCount != 13) {
    throw ArgumentError.value(hand13.tileCount, 'hand13', '13 枚（副露込み）の手ではない');
  }
  final counts = List<int>.of(hand13.counts);
  final meldCount = hand13.meldCount;
  final s0 = shantenFromCounts(counts, meldCount: meldCount).shanten;
  final tiles = <int, int>{};
  for (var id = 0; id < kTileKinds; id++) {
    if (counts[id] >= 4) continue;
    final left = hand13.remaining(id);
    if (left == 0) continue;
    counts[id]++;
    final s = shantenFromCounts(counts, meldCount: meldCount).shanten;
    counts[id]--;
    if (s < s0) tiles[id] = left;
  }
  return Ukeire(tiles);
}
