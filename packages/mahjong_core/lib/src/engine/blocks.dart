/// ブロック分解（設計書 4.7）。
///
/// 手牌を面子・搭子（両面・嵌張・辺張）・対子・雀頭・孤立牌に分ける。理由タグ
/// （`explain.dart`）と、Pro の候補の詳細（仕様 6.9）に使う。
library;

import 'package:mahjong_core/src/engine/block.dart';
import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/shanten.dart';

/// 手（13 枚か 14 枚、副露込み）を 1 通りに分解する。
///
/// 総合のシャンテン数の種類（[shanten] の [ShantenType]）で分け方を変える。
/// - 一般形: 「`8 − 2m − t − h`（`m + t ≤ 4`、副露は m に加算）が最小になる分け方」
///   のうち、次の順で最もよいもの。
///   1. 面子が多い
///   2. 雀頭がある（対子があれば必ず 1 つを雀頭にする）
///   3. 両面が多い → 嵌張が多い → 対子が多い → 辺張が多い
///   4. 孤立牌が「字牌 → 1・9 → 2・8 → 3〜7」の順に端寄り（端の牌を孤立に回し、
///      真ん中の牌をブロックに入れる）
///   雀頭は対子のうち 字牌 → 1・9 → 2・8 → 3〜7 → 牌 id の順で最初のもの。
///   同じ牌の対子 2 つ・刻子と対子（5 枚目が要る形）は作らない。
/// - 七対子（一般形より真に小さいとき）: 対子は [BlockRole.pair]、それ以外は孤立。
///   同じ牌の 3・4 枚目は孤立（七対子では同じ牌の対子 2 つにならない）。雀頭は無い。
/// - 国士（一般形・七対子より真に小さいとき）: 么九牌の対子 1 つを雀頭、それ以外は
///   すべて孤立（么九牌かどうかは牌 id で分かる）。
///
/// 副露・暗槓は最後に [BlockRole.meld]（[Block.declared] = true）として順に並べる。手牌の
/// ブロックは先頭の牌 id → 長い順に並べる。
List<Block> decomposeBlocks(HandState hand) {
  final count = hand.tileCount;
  if (count != 13 && count != 14) {
    throw ArgumentError.value(count, 'hand', '13 枚か 14 枚（副露込み）の手ではない');
  }
  final counts = hand.counts;
  final type = shantenFromCounts(counts, meldCount: hand.meldCount).type;
  final List<Block> closed;
  switch (type) {
    case ShantenType.sevenPairs:
      closed = _sevenPairsBlocks(counts);
    case ShantenType.kokushi:
      closed = _kokushiBlocks(counts);
    case ShantenType.standard:
      closed = _standardBlocks(counts, hand.meldCount);
  }
  closed.sort(_compareBlocks);
  return [
    ...closed,
    for (final meld in hand.openMelds)
      Block(
        tileIds: [for (final t in meld.tiles) tileIdOf(t)]..sort(),
        role: BlockRole.meld,
        declared: true,
      ),
  ];
}

int _compareBlocks(Block a, Block b) {
  final c = a.tileIds.first.compareTo(b.tileIds.first);
  if (c != 0) return c;
  final l = b.tileIds.length.compareTo(a.tileIds.length);
  if (l != 0) return l;
  return a.role.index.compareTo(b.role.index);
}

/// 端寄りの度合い: 字牌 0、1・9 は 1、2・8 は 2、3〜7 は 3。
int tileCentrality(int id) {
  if (id >= 27) return 0;
  final r = id % 9;
  if (r == 0 || r == 8) return 1;
  if (r == 1 || r == 7) return 2;
  return 3;
}

List<Block> _sevenPairsBlocks(List<int> counts) {
  final result = <Block>[];
  for (var id = 0; id < kTileKinds; id++) {
    final c = counts[id];
    if (c == 0) continue;
    var rest = c;
    if (c >= 2) {
      result.add(Block(tileIds: [id, id], role: BlockRole.pair));
      rest -= 2;
    }
    for (var k = 0; k < rest; k++) {
      result.add(Block(tileIds: [id], role: BlockRole.isolated));
    }
  }
  return result;
}

const List<int> _yaochuIds = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];

List<Block> _kokushiBlocks(List<int> counts) {
  final result = <Block>[];
  var headDone = false;
  for (var id = 0; id < kTileKinds; id++) {
    final c = counts[id];
    if (c == 0) continue;
    var rest = c;
    if (!headDone && c >= 2 && _yaochuIds.contains(id)) {
      result.add(Block(tileIds: [id, id], role: BlockRole.head));
      headDone = true;
      rest -= 2;
    }
    for (var k = 0; k < rest; k++) {
      result.add(Block(tileIds: [id], role: BlockRole.isolated));
    }
  }
  return result;
}

// ---- 一般形 -----------------------------------------------------------------

/// 部分的な分け方の特徴（面子・両面・嵌張・辺張・対子の数と、孤立牌の端寄り度の和）。
class _Partial {
  final int melds;
  final int ryanmen;
  final int kanchan;
  final int penchan;
  final int pairs;

  /// 孤立牌の「端寄りの度合い」の和（字牌 4、1・9 は 3、2・8 は 2、3〜7 は 1）。
  /// 大きいほど端の牌を孤立に回している。
  final int edge;
  final _Node? blocks;

  const _Partial(
    this.melds,
    this.ryanmen,
    this.kanchan,
    this.penchan,
    this.pairs,
    this.edge,
    this.blocks,
  );

  static const empty = _Partial(0, 0, 0, 0, 0, 0, null);

  int get key =>
      ((((melds * 8 + ryanmen) * 8 + kanchan) * 8 + penchan) * 8 + pairs);

  _Partial plus(_Partial o) => _Partial(
    melds + o.melds,
    ryanmen + o.ryanmen,
    kanchan + o.kanchan,
    penchan + o.penchan,
    pairs + o.pairs,
    edge + o.edge,
    _Node.concat(blocks, o.blocks),
  );

  _Partial withBlock(int start, _Kind kind) {
    switch (kind) {
      case _Kind.sequence:
        return _Partial(
          melds + 1,
          ryanmen,
          kanchan,
          penchan,
          pairs,
          edge,
          _Node(start, kind, blocks),
        );
      case _Kind.triplet:
        return _Partial(
          melds + 1,
          ryanmen,
          kanchan,
          penchan,
          pairs,
          edge,
          _Node(start, kind, blocks),
        );
      case _Kind.ryanmen:
        return _Partial(
          melds,
          ryanmen + 1,
          kanchan,
          penchan,
          pairs,
          edge,
          _Node(start, kind, blocks),
        );
      case _Kind.kanchan:
        return _Partial(
          melds,
          ryanmen,
          kanchan + 1,
          penchan,
          pairs,
          edge,
          _Node(start, kind, blocks),
        );
      case _Kind.penchan:
        return _Partial(
          melds,
          ryanmen,
          kanchan,
          penchan + 1,
          pairs,
          edge,
          _Node(start, kind, blocks),
        );
      case _Kind.pair:
        return _Partial(
          melds,
          ryanmen,
          kanchan,
          penchan,
          pairs + 1,
          edge,
          _Node(start, kind, blocks),
        );
      case _Kind.isolated:
        return _Partial(
          melds,
          ryanmen,
          kanchan,
          penchan,
          pairs,
          edge + 4 - tileCentrality(start),
          _Node(start, kind, blocks),
        );
    }
  }
}

enum _Kind { sequence, triplet, ryanmen, kanchan, penchan, pair, isolated }

/// ブロックの連結リスト（分け方ごとにリストを複製しないため）。
class _Node {
  final int start;
  final _Kind kind;
  final _Node? next;
  const _Node(this.start, this.kind, this.next);

  static _Node? concat(_Node? a, _Node? b) {
    if (a == null) return b;
    if (b == null) return a;
    return _Node(a.start, a.kind, concat(a.next, b));
  }
}

List<Block> _standardBlocks(List<int> counts, int meldCount) {
  final suits = <Map<int, _Partial>>[
    for (final base in const [0, 9, 18]) _suitPartials(counts, base),
    {0: _honorPartial(counts)},
  ];

  _Partial? best;
  List<int>? bestScore;
  void visit(int suit, _Partial acc) {
    if (suit == suits.length) {
      final score = _score(acc, meldCount);
      if (bestScore == null || _compareScore(score, bestScore!) < 0) {
        best = acc;
        bestScore = score;
      }
      return;
    }
    for (final p in suits[suit].values) {
      visit(suit + 1, acc.plus(p));
    }
  }

  visit(0, _Partial.empty);
  return _materialize(best!.blocks);
}

/// 比べる値（小さいほどよい）: シャンテン数（式）、−面子、−雀頭、−両面、−嵌張、
/// −対子、−辺張、−端寄り度。
List<int> _score(_Partial p, int meldCount) {
  final m = p.melds + meldCount;
  final h = p.pairs > 0 ? 1 : 0;
  final taatsu = p.ryanmen + p.kanchan + p.penchan + p.pairs - h;
  var room = 4 - m;
  if (room < 0) room = 0;
  final t = taatsu < room ? taatsu : room;
  return [
    8 - 2 * m - t - h,
    -m,
    -h,
    -p.ryanmen,
    -p.kanchan,
    -p.pairs,
    -p.penchan,
    -p.edge,
  ];
}

int _compareScore(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return 0;
}

/// 字牌は分け方が 1 通り（1 枚: 孤立、2 枚: 対子、3 枚: 刻子、4 枚: 刻子 + 孤立）。
_Partial _honorPartial(List<int> counts) {
  var p = _Partial.empty;
  for (var id = 27; id < kTileKinds; id++) {
    final c = counts[id];
    if (c >= 3) p = p.withBlock(id, _Kind.triplet);
    if (c == 2) p = p.withBlock(id, _Kind.pair);
    if (c == 1 || c == 4) p = p.withBlock(id, _Kind.isolated);
  }
  return p;
}

/// 数牌 1 色の分け方を、特徴（[_Partial.key]）ごとに端寄り度が最大のものだけ残して返す。
Map<int, _Partial> _suitPartials(List<int> counts, int base) {
  final local = List<int>.generate(9, (i) => counts[base + i]);
  final memo = <int, Map<int, _Partial>>{};
  // pairUsed: この色で対子を作った牌のビット（同じ牌の対子 2 つを作らない）。
  Map<int, _Partial> solve(int pairUsed) {
    var i = 0;
    while (i < 9 && local[i] == 0) {
      i++;
    }
    if (i == 9) return {0: _Partial.empty};
    // i より前の牌はもう無いので、そこの対子の印はキーに入れない。
    var code = pairUsed & ~((1 << i) - 1);
    for (var k = 0; k < 9; k++) {
      code = code * 5 + local[k];
    }
    final cached = memo[code];
    if (cached != null) return cached;

    final result = <int, _Partial>{};
    void take(_Kind kind, List<int> used, int nextPairUsed) {
      for (final u in used) {
        local[u]--;
      }
      final sub = solve(nextPairUsed);
      for (final u in used) {
        local[u]++;
      }
      for (final p in sub.values) {
        final q = p.withBlock(base + i, kind);
        final prev = result[q.key];
        if (prev == null || q.edge > prev.edge) result[q.key] = q;
      }
    }

    final c = local[i];
    final bit = 1 << i;
    if (i <= 6 && local[i + 1] > 0 && local[i + 2] > 0) {
      take(_Kind.sequence, [i, i + 1, i + 2], pairUsed);
    }
    // 刻子は、同じ牌で対子を作っていないときだけ（4 枚目は孤立・順子・搭子に回る）。
    if (c >= 3 && pairUsed & bit == 0) {
      take(_Kind.triplet, [i, i, i], pairUsed | bit);
    }
    if (c >= 2 && pairUsed & bit == 0) {
      take(_Kind.pair, [i, i], pairUsed | bit);
    }
    if (i <= 7 && local[i + 1] > 0) {
      take(i == 0 || i == 7 ? _Kind.penchan : _Kind.ryanmen, [
        i,
        i + 1,
      ], pairUsed);
    }
    if (i <= 6 && local[i + 2] > 0) {
      take(_Kind.kanchan, [i, i + 2], pairUsed);
    }
    take(_Kind.isolated, [i], pairUsed);

    memo[code] = result;
    return result;
  }

  return solve(0);
}

List<Block> _materialize(_Node? node) {
  final result = <Block>[];
  final pairs = <int>[];
  for (var n = node; n != null; n = n.next) {
    final s = n.start;
    switch (n.kind) {
      case _Kind.sequence:
        result.add(Block(tileIds: [s, s + 1, s + 2], role: BlockRole.meld));
      case _Kind.triplet:
        result.add(Block(tileIds: [s, s, s], role: BlockRole.meld));
      case _Kind.ryanmen:
        result.add(Block(tileIds: [s, s + 1], role: BlockRole.ryanmen));
      case _Kind.penchan:
        result.add(Block(tileIds: [s, s + 1], role: BlockRole.penchan));
      case _Kind.kanchan:
        result.add(Block(tileIds: [s, s + 2], role: BlockRole.kanchan));
      case _Kind.pair:
        pairs.add(s);
      case _Kind.isolated:
        result.add(Block(tileIds: [s], role: BlockRole.isolated));
    }
  }
  if (pairs.isNotEmpty) {
    // 雀頭: 字牌 → 1・9 → 2・8 → 3〜7 → 牌 id の順で最初の対子。
    pairs.sort((a, b) {
      final c = tileCentrality(a).compareTo(tileCentrality(b));
      return c != 0 ? c : a.compareTo(b);
    });
    for (var k = 0; k < pairs.length; k++) {
      result.add(
        Block(
          tileIds: [pairs[k], pairs[k]],
          role: k == 0 ? BlockRole.head : BlockRole.pair,
        ),
      );
    }
  }
  return result;
}
