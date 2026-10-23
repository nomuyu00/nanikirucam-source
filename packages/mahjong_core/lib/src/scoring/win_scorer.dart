// 文脈つきの和了採点。
//
// 手牌（門前部分）＋副露＋和了牌＋状況（ツモ/ロン・立直・一発・偶然役・風・本場・供託・
// ドラ表示牌）から、役・翻・符・点数・支払いを求める。
//
// - 高点法: 面子の分け方 × 和了牌の取り方（どのブロックを和了牌で完成させたか）の全組み合わせを
//   採点し、基本点 → 役満か → 翻 → 符 の順に最大のものを選ぶ。それでも並ぶときは参照実装
//   （Python の mahjong==2.0.0）と同じ順（素の符の合計 → 分け方の並び）で決める。
// - 副露はそのまま面子として使う（副露を含まない分け方は作らない）。
// - ロンで完成した刻子は明刻（符・暗刻の数）。
// - 役がない解釈は選ばない。どの解釈にも役がなければ [WinError.noYaku]。
// - 役満が成立したら役満だけを数え、通常の役は [WinResult.suppressedYaku] に分ける。
// - ドラは表示牌から求める（9→1、北→東、中→白）。
//
// 既存の HandAnalyzer / ScoringEngine には依存しない（それらの挙動は変えない）。
import 'package:mahjong_core/src/engine/yaku.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';
import 'package:mahjong_core/src/scoring/win_types.dart';
import 'package:mahjong_core/src/tile_utils.dart';
import 'package:mahjong_core/src/wait_type.dart';

/// 翻・符・役満の倍数から基本点（満貫 2000 など上限適用済み）を求める。
int winBasePoints({
  required int han,
  required int fu,
  int yakumanMultiplier = 0,
  required Ruleset ruleset,
}) {
  if (yakumanMultiplier > 0) return 8000 * yakumanMultiplier;
  if (han >= 13) return ruleset.countedYakuman ? 8000 : 6000;
  if (han >= 11) return 6000;
  if (han >= 8) return 4000;
  if (han >= 6) return 3000;
  if (han >= 5) return 2000;
  if (han <= 0) return 0;
  if (ruleset.kiriageMangan &&
      ((han == 4 && fu == 30) || (han == 3 && fu == 60))) {
    return 2000;
  }
  final base = fu * (1 << (han + 2));
  return base > 2000 ? 2000 : base;
}

/// 翻・符・役満の倍数から満貫以上の名称を求める。
HandRank winHandRank({
  required int han,
  required int fu,
  int yakumanMultiplier = 0,
  required Ruleset ruleset,
}) {
  if (yakumanMultiplier > 0) {
    const ranks = [
      HandRank.yakuman,
      HandRank.doubleYakuman,
      HandRank.tripleYakuman,
      HandRank.quadrupleYakuman,
      HandRank.quintupleYakuman,
      HandRank.sextupleYakuman,
    ];
    return ranks[(yakumanMultiplier > 6 ? 6 : yakumanMultiplier) - 1];
  }
  if (han >= 13) {
    return ruleset.countedYakuman ? HandRank.kazoeYakuman : HandRank.sanbaiman;
  }
  if (han >= 11) return HandRank.sanbaiman;
  if (han >= 8) return HandRank.baiman;
  if (han >= 6) return HandRank.haneman;
  final base = winBasePoints(han: han, fu: fu, ruleset: ruleset);
  return base >= 2000 ? HandRank.mangan : HandRank.none;
}

/// 文脈つきの和了採点器。ルールごとに 1 つ作って使い回せる（状態を持たない）。
class WinScorer {
  final Ruleset ruleset;
  const WinScorer(this.ruleset);

  /// 採点する。入力の誤り・状況の矛盾・和了形でない・役なしは [WinRejected]。
  WinOutcome score(WinRequest request) {
    if (ruleset.mode == MahjongMode.threePlayer) {
      return const WinRejected(WinError.unsupportedMode);
    }
    final parsed = _parse(request);
    if (parsed is WinRejected) return parsed;
    final input = parsed as _Input;
    final conflict = _checkSituation(request, input);
    if (conflict != null) return WinRejected(conflict);
    return _Evaluator(ruleset, request, input).run();
  }

  // ---------------------------------------------------------------- 入力

  static int _parseLabel(String label) {
    if (label.length != 2) return -1;
    return tileIdFromLabel(label);
  }

  Object _parse(WinRequest r) {
    final closed = List<int>.filled(34, 0);
    final all = List<int>.filled(34, 0); // 手牌＋副露（ドラを数える対象）
    final physical = List<int>.filled(34, 0); // ＋表示牌（5 枚目の検出用）
    final reds = List<int>.filled(3, 0); // 手牌＋副露の赤（赤ドラ）
    final physicalReds = List<int>.filled(3, 0);

    int addTile(String label, {required bool inHand}) {
      final id = _parseLabel(label);
      if (id < 0) return -1;
      physical[id]++;
      final red = label[0] == '0';
      if (red) physicalReds[id ~/ 9]++;
      if (inHand) {
        all[id]++;
        if (red) reds[id ~/ 9]++;
      }
      return id;
    }

    if (r.melds.length > 4) {
      return WinRejected(WinError.wrongTileCount, '副露 ${r.melds.length} 個');
    }
    for (final label in r.handTiles) {
      final id = addTile(label, inHand: true);
      if (id < 0) return WinRejected(WinError.invalidTile, label);
      closed[id]++;
    }
    final win = _parseLabel(r.winningTile);
    if (win < 0) return WinRejected(WinError.invalidTile, r.winningTile);

    final meldGroups = <_Group>[];
    for (final meld in r.melds) {
      final ids = <int>[];
      for (final label in meld.tiles) {
        final id = addTile(label, inHand: true);
        if (id < 0) return WinRejected(WinError.invalidTile, label);
        ids.add(id);
      }
      final group = _meldGroup(meld.type, ids);
      if (group == null) {
        return WinRejected(
          WinError.invalidMeld,
          '${meld.type.name} ${meld.tiles.join()}',
        );
      }
      meldGroups.add(group);
    }
    final expected = 14 - 3 * r.melds.length;
    if (r.handTiles.length != expected) {
      return WinRejected(
        WinError.wrongTileCount,
        '門前部分 ${r.handTiles.length} 枚（$expected 枚のはず）',
      );
    }
    if (r.doraIndicators.length > 5 || r.uraDoraIndicators.length > 5) {
      return const WinRejected(WinError.tooManyIndicators);
    }
    final dora = <int>[];
    for (final label in r.doraIndicators) {
      final id = addTile(label, inHand: false);
      if (id < 0) return WinRejected(WinError.invalidTile, label);
      dora.add(id);
    }
    final ura = <int>[];
    for (final label in r.uraDoraIndicators) {
      final id = addTile(label, inHand: false);
      if (id < 0) return WinRejected(WinError.invalidTile, label);
      ura.add(id);
    }
    for (var id = 0; id < 34; id++) {
      if (physical[id] > 4) {
        return WinRejected(WinError.tooManyCopies, _label(id));
      }
    }
    if (ruleset.redFives > 0) {
      for (var suit = 0; suit < 3; suit++) {
        final allowed = suit == 1 && ruleset.redFives >= 4 ? 2 : 1;
        if (physicalReds[suit] > allowed) {
          return WinRejected(WinError.tooManyRedFives, '0${'mps'[suit]}');
        }
      }
    }
    if (closed[win] == 0) {
      return WinRejected(WinError.winningTileNotInHand, r.winningTile);
    }
    return _Input(
      closed: closed,
      all: all,
      win: win,
      meldGroups: meldGroups,
      akaCount: ruleset.redFives > 0 ? reds[0] + reds[1] + reds[2] : 0,
      doraIndicators: dora,
      uraIndicators: ura,
    );
  }

  static _Group? _meldGroup(CalledMeldType type, List<int> ids) {
    switch (type) {
      case CalledMeldType.chi:
        if (ids.length != 3) return null;
        final sorted = [...ids]..sort();
        final first = sorted[0];
        if (first >= 27 || first % 9 > 6) return null;
        if (sorted[1] != first + 1 || sorted[2] != first + 2) return null;
        return _Group(_GType.seq, first, meld: type);
      case CalledMeldType.pon:
        if (ids.length != 3 || ids.any((id) => id != ids[0])) return null;
        return _Group(_GType.trip, ids[0], meld: type);
      case CalledMeldType.minkan:
      case CalledMeldType.ankan:
      case CalledMeldType.kakan:
        if (ids.length != 4 || ids.any((id) => id != ids[0])) return null;
        return _Group(_GType.quad, ids[0], meld: type);
    }
  }

  WinError? _checkSituation(WinRequest r, _Input input) {
    final open = r.melds.any((m) => m.isOpen);
    final anyRiichi = r.riichi || r.doubleRiichi;
    final tsumo = r.isTsumo;
    final dealer = r.isDealer;
    final hasMeld = r.melds.isNotEmpty;
    final renhou = r.renhou && ruleset.renhou != RenhouValue.none;
    // 参照実装と同じ順。
    if (anyRiichi && open) return WinError.riichiWithOpenHand;
    if (r.ippatsu && !anyRiichi) return WinError.ippatsuWithoutRiichi;
    if (r.chankan && tsumo) return WinError.chankanWithTsumo;
    if (r.rinshan && !tsumo) return WinError.rinshanWithoutTsumo;
    if (r.haitei && !tsumo) return WinError.haiteiWithoutTsumo;
    if (r.houtei && tsumo) return WinError.houteiWithTsumo;
    if (r.haitei && r.rinshan) return WinError.haiteiWithRinshan;
    if (r.houtei && r.chankan) return WinError.houteiWithChankan;
    if (r.tenhou && !dealer) return WinError.tenhouNotDealer;
    if (r.tenhou && !tsumo) return WinError.tenhouWithoutTsumo;
    if (r.tenhou && hasMeld) return WinError.tenhouWithMeld;
    if (r.chiihou && dealer) return WinError.chiihouAsDealer;
    if (r.chiihou && !tsumo) return WinError.chiihouWithoutTsumo;
    if (r.chiihou && hasMeld) return WinError.chiihouWithMeld;
    if (renhou && dealer) return WinError.renhouAsDealer;
    if (renhou && tsumo) return WinError.renhouWithTsumo;
    if (renhou && hasMeld) return WinError.renhouWithMeld;
    // 参照実装は調べないもの。
    if (r.rinshan && !r.melds.any((m) => m.isKan)) {
      return WinError.rinshanWithoutKan;
    }
    if (r.chankan && input.all[input.win] > 1) {
      return WinError.chankanImpossible;
    }
    if (r.ippatsu && r.rinshan) return WinError.ippatsuWithRinshan;
    if ((r.tenhou || r.chiihou || renhou) &&
        (anyRiichi ||
            r.ippatsu ||
            r.haitei ||
            r.houtei ||
            r.rinshan ||
            r.chankan)) {
      return WinError.blessingWithOtherSituation;
    }
    return null;
  }
}

String _label(int id) => '${id % 9 + 1}${'mpsz'[id ~/ 9]}';

bool _isHonor(int id) => id >= 27;
bool _isTerminal(int id) => id < 27 && (id % 9 == 0 || id % 9 == 8);
bool _isYaochu(int id) => _isHonor(id) || _isTerminal(id);
bool _isDragon(int id) => id >= 31;
bool _isWind(int id) => id >= 27 && id <= 30;

const _kokushiTiles = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33];
const _greenTiles = {19, 20, 21, 23, 25, 32};

/// 表示牌からドラ（34 種の番号）を求める。
int _doraOf(int indicator) {
  if (indicator < 27) return indicator ~/ 9 * 9 + (indicator % 9 + 1) % 9;
  if (indicator <= 30) return 27 + (indicator - 27 + 1) % 4;
  return 31 + (indicator - 31 + 1) % 3;
}

enum _GType { quad, trip, pair, seq } // 並びは参照実装の分け方の並べ順に合わせる

class _Group {
  final _GType type;
  final int tile;
  final CalledMeldType? meld;
  const _Group(this.type, this.tile, {this.meld});

  bool get isSet => type != _GType.pair;
  bool get isTripletLike => type == _GType.trip || type == _GType.quad;
  bool containsTile(int id) =>
      type == _GType.seq ? id >= tile && id <= tile + 2 : id == tile;
  bool get hasYaochu =>
      type == _GType.seq ? (tile % 9 == 0 || tile % 9 == 6) : _isYaochu(tile);
  bool get hasTerminal =>
      type == _GType.seq ? (tile % 9 == 0 || tile % 9 == 6) : _isTerminal(tile);

  int compareTo(_Group other) {
    if (tile != other.tile) return tile.compareTo(other.tile);
    return type.index.compareTo(other.type.index);
  }
}

class _Input {
  final List<int> closed;
  final List<int> all;
  final int win;
  final List<_Group> meldGroups;
  final int akaCount;
  final List<int> doraIndicators;
  final List<int> uraIndicators;
  const _Input({
    required this.closed,
    required this.all,
    required this.win,
    required this.meldGroups,
    required this.akaCount,
    required this.doraIndicators,
    required this.uraIndicators,
  });
}

/// 1 つの解釈の採点（並べ替え用のキーつき）。
class _Candidate {
  final WinResult result;
  final bool hasYaku;
  final int tieRawFu; // 参照実装と同じ数え方の切り上げ前の符
  final int order; // 参照実装の列挙順
  const _Candidate(this.result, this.hasYaku, this.tieRawFu, this.order);

  /// よいほうが負。
  static int compare(_Candidate a, _Candidate b) {
    final ra = a.result;
    final rb = b.result;
    if (ra.basePoints != rb.basePoints) {
      return rb.basePoints.compareTo(ra.basePoints);
    }
    if (ra.isYakuman != rb.isYakuman) return ra.isYakuman ? -1 : 1;
    if (ra.han != rb.han) return rb.han.compareTo(ra.han);
    if (ra.fu != rb.fu) return rb.fu.compareTo(ra.fu);
    if (a.tieRawFu != b.tieRawFu) return b.tieRawFu.compareTo(a.tieRawFu);
    return a.order.compareTo(b.order);
  }
}

class _Evaluator {
  final Ruleset ruleset;
  final WinRequest r;
  final _Input input;
  late final bool closedHand = !r.melds.any((m) => m.isOpen);
  late final bool ron = r.winType == WinType.ron;
  late final int seat = 27 + r.seatWind.index;
  late final int round = 27 + r.roundWind.index;
  late final int doraCount;
  late final int uraCount;
  late final bool allSimple;
  late final bool allYaochu;
  late final bool hasHonor;
  late final bool hasTerminal;
  late final int suitMask; // 萬 1 / 筒 2 / 索 4
  late final List<ScoredYaku> situational;

  _Evaluator(this.ruleset, this.r, this.input) {
    final all = input.all;
    var dora = 0;
    final doraInd = ruleset.kanDora
        ? input.doraIndicators
        : input.doraIndicators.take(1);
    for (final ind in doraInd) {
      dora += all[_doraOf(ind)];
    }
    doraCount = dora;
    var ura = 0;
    if ((r.riichi || r.doubleRiichi) && ruleset.uraDora) {
      final uraInd = ruleset.kanUra
          ? input.uraIndicators
          : input.uraIndicators.take(1);
      for (final ind in uraInd) {
        ura += all[_doraOf(ind)];
      }
    }
    uraCount = ura;
    var simple = true;
    var yaochu = true;
    var honor = false;
    var terminal = false;
    var mask = 0;
    for (var id = 0; id < 34; id++) {
      if (all[id] == 0) continue;
      if (_isYaochu(id)) {
        simple = false;
      } else {
        yaochu = false;
      }
      if (_isHonor(id)) {
        honor = true;
      } else {
        mask |= 1 << (id ~/ 9);
        if (_isTerminal(id)) terminal = true;
      }
    }
    allSimple = simple;
    allYaochu = yaochu;
    hasHonor = honor;
    hasTerminal = terminal;
    suitMask = mask;
    situational = _situationalYaku();
  }

  int get _doubleMultiplier => ruleset.doubleYakuman ? 2 : 1;

  List<ScoredYaku> _situationalYaku() {
    final ys = <ScoredYaku>[];
    if (r.doubleRiichi) {
      ys.add(const ScoredYaku(YakuId.doubleRiichi, 2));
    } else if (r.riichi) {
      ys.add(const ScoredYaku(YakuId.riichi, 1));
    }
    if (r.ippatsu && ruleset.ippatsu) {
      ys.add(const ScoredYaku(YakuId.ippatsu, 1));
    }
    if (r.isTsumo && closedHand) {
      ys.add(const ScoredYaku(YakuId.menzenTsumo, 1));
    }
    if (r.haitei) ys.add(const ScoredYaku(YakuId.haitei, 1));
    if (r.houtei) ys.add(const ScoredYaku(YakuId.houtei, 1));
    if (r.rinshan) ys.add(const ScoredYaku(YakuId.rinshan, 1));
    if (r.chankan) ys.add(const ScoredYaku(YakuId.chankan, 1));
    if (r.renhou) {
      switch (ruleset.renhou) {
        case RenhouValue.none:
          break;
        case RenhouValue.mangan:
          ys.add(const ScoredYaku(YakuId.renhou, 5));
        case RenhouValue.yakuman:
          ys.add(const ScoredYaku(YakuId.renhou, 13, yakumanMultiplier: 1));
      }
    }
    if (r.tenhou) {
      ys.add(const ScoredYaku(YakuId.tenhou, 13, yakumanMultiplier: 1));
    }
    if (r.chiihou) {
      ys.add(const ScoredYaku(YakuId.chiihou, 13, yakumanMultiplier: 1));
    }
    return ys;
  }

  WinOutcome run() {
    final candidates = <_Candidate>[];
    final closed = input.closed;
    final meldGroups = input.meldGroups;
    final sets = 4 - meldGroups.length;

    // 標準形と七対子（参照実装と同じく分け方を並べ替えてから列挙する）。
    final decompositions = <List<_Group>>[];
    _decompose(closed, sets, decompositions);
    for (final d in decompositions) {
      d.addAll(meldGroups);
      d.sort((a, b) => a.compareTo(b));
    }
    if (meldGroups.isEmpty) {
      final pairs = <_Group>[];
      var ok = true;
      for (var id = 0; id < 34 && ok; id++) {
        if (closed[id] == 0) continue;
        if (closed[id] != 2) ok = false;
        pairs.add(_Group(_GType.pair, id));
      }
      if (ok && pairs.length == 7) decompositions.add(pairs);
    }
    decompositions.sort(_compareDecomposition);

    var order = 0;
    for (final groups in decompositions) {
      if (groups.length == 7) {
        candidates.add(_chiitoitsu(order++));
        continue;
      }
      // 和了牌を含む門前のブロック（同じ形は 1 回だけ）。副露（暗槓を含む）は和了牌で
      // 完成しない。
      final seen = <int>{};
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        if (g.meld != null || !g.containsTile(input.win)) continue;
        if (!seen.add(g.type.index * 64 + g.tile)) continue;
        candidates.add(_standard(groups, i, order++));
      }
    }
    if (meldGroups.isEmpty && _isKokushi(closed)) {
      candidates.add(_kokushi(order++));
    }
    if (candidates.isEmpty) return const WinRejected(WinError.notWinningHand);

    final valid = candidates.where((c) => c.hasYaku).toList()
      ..sort(_Candidate.compare);
    if (valid.isEmpty) return const WinRejected(WinError.noYaku);

    final best = valid.first.result;
    final alternatives = <WinResult>[];
    final signatures = <String>{_signature(best)};
    for (final c in valid.skip(1)) {
      if (signatures.add(_signature(c.result))) alternatives.add(c.result);
    }
    return WinScored(best, alternatives);
  }

  static String _signature(WinResult res) =>
      '${res.basePoints}/${res.han}/${res.fu}/${res.wait.name}/'
      '${res.yaku.map((y) => '${y.id.name}${y.han}').join(',')}';

  static int _compareDecomposition(List<_Group> a, List<_Group> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final c = a[i].compareTo(b[i]);
      if (c != 0) return c;
    }
    return a.length.compareTo(b.length);
  }

  static void _decompose(List<int> counts, int sets, List<List<_Group>> out) {
    for (var p = 0; p < 34; p++) {
      if (counts[p] < 2) continue;
      counts[p] -= 2;
      _decomposeSets(counts, 0, [_Group(_GType.pair, p)], out);
      counts[p] += 2;
    }
  }

  static void _decomposeSets(
    List<int> counts,
    int start,
    List<_Group> acc,
    List<List<_Group>> out,
  ) {
    var i = start;
    while (i < 34 && counts[i] == 0) {
      i++;
    }
    if (i == 34) {
      out.add([...acc]);
      return;
    }
    if (counts[i] >= 3) {
      counts[i] -= 3;
      acc.add(_Group(_GType.trip, i));
      _decomposeSets(counts, i, acc, out);
      acc.removeLast();
      counts[i] += 3;
    }
    if (i < 27 && i % 9 <= 6 && counts[i + 1] > 0 && counts[i + 2] > 0) {
      counts[i]--;
      counts[i + 1]--;
      counts[i + 2]--;
      acc.add(_Group(_GType.seq, i));
      _decomposeSets(counts, i, acc, out);
      acc.removeLast();
      counts[i]++;
      counts[i + 1]++;
      counts[i + 2]++;
    }
  }

  static bool _isKokushi(List<int> closed) {
    var total = 0;
    for (final id in _kokushiTiles) {
      if (closed[id] == 0) return false;
      total += closed[id];
    }
    return total == 14;
  }

  // ------------------------------------------------------------ 標準形

  _Candidate _standard(List<_Group> groups, int w, int order) {
    final win = input.win;
    final wg = groups[w];
    final wait = _waitOf(wg, win);

    // 暗刻（暗槓を含む）。ロンで完成した刻子は明刻。
    bool concealed(int i) {
      final g = groups[i];
      if (g.type == _GType.trip) return g.meld == null && !(ron && i == w);
      if (g.type == _GType.quad) return g.meld == CalledMeldType.ankan;
      return false;
    }

    late _Group pair;
    final seqStarts = <int>[];
    var tripletLike = 0;
    var concealedCount = 0;
    var kans = 0;
    var dragonTriplets = 0;
    var windTriplets = 0;
    final tripletTiles = <int>{};
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      switch (g.type) {
        case _GType.pair:
          pair = g;
        case _GType.seq:
          seqStarts.add(g.tile);
        case _GType.trip:
        case _GType.quad:
          tripletLike++;
          if (g.type == _GType.quad) kans++;
          if (concealed(i)) concealedCount++;
          if (_isDragon(g.tile)) dragonTriplets++;
          if (_isWind(g.tile)) windTriplets++;
          tripletTiles.add(g.tile);
      }
    }
    final pairTile = pair.tile;
    final valuedPair =
        _isDragon(pairTile) || pairTile == seat || pairTile == round;

    // --- 役満 ---
    final yakuman = <ScoredYaku>[
      for (final y in situational)
        if (y.isYakuman) y,
    ];
    if (closedHand && concealedCount == 4) {
      yakuman.add(
        wait == WaitType.tanki
            ? ScoredYaku(
                YakuId.suuankouTanki,
                13 * _doubleMultiplier,
                yakumanMultiplier: _doubleMultiplier,
              )
            : const ScoredYaku(YakuId.suuankou, 13, yakumanMultiplier: 1),
      );
    }
    if (dragonTriplets == 3) {
      yakuman.add(const ScoredYaku(YakuId.daisangen, 13, yakumanMultiplier: 1));
    }
    if (windTriplets == 4) {
      yakuman.add(
        ScoredYaku(
          YakuId.daisuushii,
          13 * _doubleMultiplier,
          yakumanMultiplier: _doubleMultiplier,
        ),
      );
    } else if (windTriplets == 3 && _isWind(pairTile)) {
      yakuman.add(
        const ScoredYaku(YakuId.shousuushii, 13, yakumanMultiplier: 1),
      );
    }
    if (suitMask == 0) {
      yakuman.add(const ScoredYaku(YakuId.tsuuiisou, 13, yakumanMultiplier: 1));
    }
    if (_allGreen()) {
      yakuman.add(const ScoredYaku(YakuId.ryuuiisou, 13, yakumanMultiplier: 1));
    }
    if (allYaochu && !hasHonor) {
      yakuman.add(
        const ScoredYaku(YakuId.chinroutou, 13, yakumanMultiplier: 1),
      );
    }
    if (r.melds.isEmpty && _isChuuren()) {
      final c = input.closed[win];
      yakuman.add(
        c == 2 || c == 4
            ? ScoredYaku(
                YakuId.junseiChuuren,
                13 * _doubleMultiplier,
                yakumanMultiplier: _doubleMultiplier,
              )
            : const ScoredYaku(YakuId.chuuren, 13, yakumanMultiplier: 1),
      );
    }
    if (kans == 4) {
      yakuman.add(const ScoredYaku(YakuId.suukantsu, 13, yakumanMultiplier: 1));
    }

    // --- 通常の役 ---
    final ys = <ScoredYaku>[
      for (final y in situational)
        if (!y.isYakuman) y,
    ];
    final pinfu =
        closedHand &&
        seqStarts.length == 4 &&
        !valuedPair &&
        wait == WaitType.ryanmen;
    if (pinfu) ys.add(const ScoredYaku(YakuId.pinfu, 1));
    if (allSimple && (closedHand || ruleset.kuitan)) {
      ys.add(const ScoredYaku(YakuId.tanyao, 1));
    }
    if (closedHand && seqStarts.length >= 2) {
      final counts = <int, int>{};
      for (final s in seqStarts) {
        counts[s] = (counts[s] ?? 0) + 1;
      }
      var pairs = 0;
      for (final c in counts.values) {
        pairs += c ~/ 2;
      }
      if (pairs >= 2) {
        ys.add(const ScoredYaku(YakuId.ryanpeikou, 3));
      } else if (pairs == 1) {
        ys.add(const ScoredYaku(YakuId.iipeikou, 1));
      }
    }
    for (final t in tripletTiles) {
      if (t == 31) ys.add(const ScoredYaku(YakuId.yakuhaiHaku, 1));
      if (t == 32) ys.add(const ScoredYaku(YakuId.yakuhaiHatsu, 1));
      if (t == 33) ys.add(const ScoredYaku(YakuId.yakuhaiChun, 1));
      if (t == seat && t == round) {
        ys.add(const ScoredYaku(YakuId.doubleWind, 2));
      } else if (t == seat) {
        ys.add(const ScoredYaku(YakuId.yakuhaiSeatWind, 1));
      } else if (t == round) {
        ys.add(const ScoredYaku(YakuId.yakuhaiRoundWind, 1));
      }
    }
    final seqSet = seqStarts.toSet();
    for (var v = 0; v <= 6; v++) {
      if (seqSet.contains(v) &&
          seqSet.contains(9 + v) &&
          seqSet.contains(18 + v)) {
        ys.add(ScoredYaku(YakuId.sanshoku, closedHand ? 2 : 1));
        break;
      }
    }
    for (var s = 0; s < 27; s += 9) {
      if (seqSet.contains(s) &&
          seqSet.contains(s + 3) &&
          seqSet.contains(s + 6)) {
        ys.add(ScoredYaku(YakuId.ittsu, closedHand ? 2 : 1));
        break;
      }
    }
    if (tripletLike == 4) ys.add(const ScoredYaku(YakuId.toitoi, 2));
    if (concealedCount == 3) ys.add(const ScoredYaku(YakuId.sanankou, 2));
    for (var v = 0; v < 9; v++) {
      if (tripletTiles.contains(v) &&
          tripletTiles.contains(9 + v) &&
          tripletTiles.contains(18 + v)) {
        ys.add(const ScoredYaku(YakuId.sanshokuDoukou, 2));
        break;
      }
    }
    if (kans == 3) ys.add(const ScoredYaku(YakuId.sankantsu, 2));
    if (dragonTriplets == 2 && _isDragon(pairTile)) {
      ys.add(const ScoredYaku(YakuId.shousangen, 2));
    }
    if (allYaochu && hasHonor && hasTerminal) {
      ys.add(const ScoredYaku(YakuId.honroutou, 2));
    }
    if (seqStarts.isNotEmpty && groups.every((g) => g.hasYaochu)) {
      if (hasHonor) {
        ys.add(ScoredYaku(YakuId.chanta, closedHand ? 2 : 1));
      } else {
        ys.add(ScoredYaku(YakuId.junchan, closedHand ? 3 : 2));
      }
    }
    _addSuitYaku(ys);

    // --- 符 ---
    final parts = <FuPart>[const FuPart(FuReason.base, 20)];
    if (closedHand && ron) parts.add(const FuPart(FuReason.menzenRon, 10));
    var structural = 0;
    void add(FuReason reason, int fu, int tile) {
      parts.add(FuPart(reason, fu, tile: _label(tile)));
      structural += fu;
    }

    switch (wait) {
      case WaitType.kanchan:
        add(FuReason.kanchan, 2, wg.tile + 1);
      case WaitType.penchan:
        add(FuReason.penchan, 2, win);
      case WaitType.tanki:
        add(FuReason.tanki, 2, wg.tile);
      case WaitType.ryanmen:
      case WaitType.shanpon:
        break;
    }
    if (_isDragon(pairTile)) {
      add(FuReason.pairDragon, 2, pairTile);
    } else if (pairTile == seat && pairTile == round) {
      add(FuReason.pairDoubleWind, ruleset.doubleWindPairFu, pairTile);
    } else if (pairTile == seat) {
      add(FuReason.pairSeatWind, 2, pairTile);
    } else if (pairTile == round) {
      add(FuReason.pairRoundWind, 2, pairTile);
    }
    final wgroups = <WinGroup>[];
    for (var i = 0; i < groups.length; i++) {
      final g = groups[i];
      final yaochu = _isYaochu(g.tile);
      final isConcealed = concealed(i);
      if (g.type == _GType.trip) {
        if (isConcealed) {
          add(FuReason.anko, yaochu ? 8 : 4, g.tile);
        } else {
          add(FuReason.minko, yaochu ? 4 : 2, g.tile);
        }
      } else if (g.type == _GType.quad) {
        if (isConcealed) {
          add(FuReason.ankan, yaochu ? 32 : 16, g.tile);
        } else {
          add(FuReason.minkan, yaochu ? 16 : 8, g.tile);
        }
      }
      wgroups.add(
        WinGroup(
          type: switch (g.type) {
            _GType.seq => WinGroupType.sequence,
            _GType.trip => WinGroupType.triplet,
            _GType.quad => WinGroupType.quad,
            _GType.pair => WinGroupType.pair,
          },
          tile: _label(g.tile),
          meld: g.meld,
          concealed: isConcealed,
        ),
      );
    }
    var openPinfu = false;
    if (!ron && structural > 0) {
      parts.add(const FuPart(FuReason.tsumo, 2));
    }
    if (!closedHand && structural == 0) {
      parts.add(const FuPart(FuReason.openPinfu, 10));
      openPinfu = true;
    }
    var raw = 0;
    for (final p in parts) {
      raw += p.fu;
    }
    final fu = (raw + 9) ~/ 10 * 10;
    if (fu > raw) parts.add(FuPart(FuReason.roundUp, fu - raw));
    // 参照実装は副露の平和形に 2 符を足して切り上げる（並べ替えの同点処理だけに使う）。
    final tieRaw = openPinfu ? raw - 8 : raw;

    return _finish(
      yaku: ys,
      yakuman: yakuman,
      fu: fu,
      fuParts: parts,
      wait: wait,
      shape: WinShape.standard,
      groups: wgroups,
      winningGroupIndex: w,
      tieRaw: tieRaw,
      order: order,
    );
  }

  static WaitType _waitOf(_Group g, int win) {
    switch (g.type) {
      case _GType.pair:
        return WaitType.tanki;
      case _GType.trip:
      case _GType.quad:
        return WaitType.shanpon;
      case _GType.seq:
        if (win == g.tile + 1) return WaitType.kanchan;
        final rank = g.tile % 9;
        if ((rank == 0 && win == g.tile + 2) || (rank == 6 && win == g.tile)) {
          return WaitType.penchan;
        }
        return WaitType.ryanmen;
    }
  }

  bool _allGreen() {
    final all = input.all;
    for (var id = 0; id < 34; id++) {
      if (all[id] > 0 && !_greenTiles.contains(id)) return false;
    }
    return true;
  }

  bool _isChuuren() {
    if (hasHonor || !(suitMask == 1 || suitMask == 2 || suitMask == 4)) {
      return false;
    }
    final s = suitMask == 1 ? 0 : (suitMask == 2 ? 9 : 18);
    final c = input.closed;
    if (c[s] < 3 || c[s + 8] < 3) return false;
    for (var v = 1; v <= 7; v++) {
      if (c[s + v] < 1) return false;
    }
    return true; // 14 枚が 1 色なので、残り 1 枚はどれかの重なり
  }

  void _addSuitYaku(List<ScoredYaku> ys) {
    if (suitMask == 1 || suitMask == 2 || suitMask == 4) {
      if (hasHonor) {
        ys.add(ScoredYaku(YakuId.honitsu, closedHand ? 3 : 2));
      } else {
        ys.add(ScoredYaku(YakuId.chinitsu, closedHand ? 6 : 5));
      }
    }
  }

  // ------------------------------------------------------------ 七対子・国士

  _Candidate _chiitoitsu(int order) {
    final yakuman = <ScoredYaku>[
      for (final y in situational)
        if (y.isYakuman) y,
    ];
    if (suitMask == 0) {
      yakuman.add(const ScoredYaku(YakuId.tsuuiisou, 13, yakumanMultiplier: 1));
    }
    final ys = <ScoredYaku>[
      for (final y in situational)
        if (!y.isYakuman) y,
      const ScoredYaku(YakuId.chiitoitsu, 2),
    ];
    if (allSimple) ys.add(const ScoredYaku(YakuId.tanyao, 1));
    if (allYaochu && hasHonor && hasTerminal) {
      ys.add(const ScoredYaku(YakuId.honroutou, 2));
    }
    _addSuitYaku(ys);
    return _finish(
      yaku: ys,
      yakuman: yakuman,
      fu: 25,
      fuParts: const [FuPart(FuReason.chiitoitsu, 25)],
      wait: WaitType.tanki,
      shape: WinShape.chiitoitsu,
      groups: const [],
      winningGroupIndex: null,
      tieRaw: 25,
      order: order,
    );
  }

  _Candidate _kokushi(int order) {
    final yakuman = <ScoredYaku>[
      if (input.closed[input.win] == 2)
        ScoredYaku(
          YakuId.kokushi13,
          13 * _doubleMultiplier,
          yakumanMultiplier: _doubleMultiplier,
        )
      else
        const ScoredYaku(YakuId.kokushi, 13, yakumanMultiplier: 1),
      for (final y in situational)
        if (y.isYakuman) y,
    ];
    final ys = <ScoredYaku>[
      for (final y in situational)
        if (!y.isYakuman) y,
    ];
    return _finish(
      yaku: ys,
      yakuman: yakuman,
      fu: 0,
      fuParts: const [],
      wait: WaitType.tanki,
      shape: WinShape.kokushi,
      groups: const [],
      winningGroupIndex: null,
      tieRaw: 0,
      order: order,
    );
  }

  // ------------------------------------------------------------ 仕上げ

  _Candidate _finish({
    required List<ScoredYaku> yaku,
    required List<ScoredYaku> yakuman,
    required int fu,
    required List<FuPart> fuParts,
    required WaitType wait,
    required WinShape shape,
    required List<WinGroup> groups,
    required int? winningGroupIndex,
    required int tieRaw,
    required int order,
  }) {
    final List<ScoredYaku> counted;
    final List<ScoredYaku> suppressed;
    var multiplier = 0;
    var han = 0;
    var hasYaku = true;
    if (yakuman.isNotEmpty) {
      counted = yakuman;
      suppressed = yaku;
      for (final y in yakuman) {
        if (ruleset.yakumanMultiple) {
          multiplier += y.yakumanMultiplier;
        } else if (y.yakumanMultiplier > multiplier) {
          multiplier = y.yakumanMultiplier;
        }
      }
      han = 13 * multiplier;
    } else {
      counted = yaku;
      suppressed = const [];
      for (final y in yaku) {
        han += y.han;
      }
      if (han == 0) {
        hasYaku = false;
      } else {
        han += doraCount + input.akaCount + uraCount;
      }
    }
    final base = hasYaku
        ? winBasePoints(
            han: han,
            fu: fu,
            yakumanMultiplier: multiplier,
            ruleset: ruleset,
          )
        : 0;
    final result = WinResult(
      yaku: List.unmodifiable(counted),
      suppressedYaku: List.unmodifiable(suppressed),
      doraCount: doraCount,
      akaDoraCount: input.akaCount,
      uraDoraCount: uraCount,
      han: han,
      fu: fu,
      fuParts: List.unmodifiable(fuParts),
      yakumanMultiplier: multiplier,
      rank: hasYaku
          ? winHandRank(
              han: han,
              fu: fu,
              yakumanMultiplier: multiplier,
              ruleset: ruleset,
            )
          : HandRank.none,
      basePoints: base,
      payment: WinPayment.compute(
        basePoints: base,
        dealer: r.isDealer,
        winType: r.winType,
        honba: r.honba,
        kyotaku: r.kyotaku,
      ),
      wait: wait,
      closed: closedHand,
      shape: shape,
      groups: List.unmodifiable(groups),
      winningGroupIndex: winningGroupIndex,
    );
    return _Candidate(result, hasYaku, tieRaw, order);
  }
}
