import 'package:mahjong_core/src/engine/hand_state.dart';
import 'package:mahjong_core/src/engine/points.dart';
import 'package:mahjong_core/src/engine/yaku.dart';
import 'package:mahjong_core/src/hand_parser.dart';
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/scoring/han_yaku.dart';
import 'package:mahjong_core/src/scoring/hand_analyzer.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';
import 'package:mahjong_core/src/scoring/scoring_engine.dart';

/// 赤5になり得る牌 id（5m・5p・5s）。
const List<int> kRedFiveIds = [4, 13, 22];

/// 和了形 1 つの評価（ロンとツモ、ダマとリーチ込み）。
class WinEvaluation {
  /// 役のある解釈のうち最も高いロン。役が無ければ null（ロンできない）。
  final HandScore? ron;

  /// 役のある解釈のうち最も高いツモ。役が無ければ null。
  final HandScore? tsumo;

  /// ダマのロンで受け取る点数。役なしは 0。
  final int ronPoints;

  /// ダマのツモで受け取る合計点数。役なしは 0。
  final int tsumoPoints;

  /// リーチ込み（一発・裏ドラなし）のロン。副露していれば null。
  final int? ronRiichiPoints;

  /// リーチ込みのツモ合計。副露していれば null。
  final int? tsumoRiichiPoints;

  /// ロンの最良解釈にある役（[YakuIdInfo.isProspect] のもの。赤は [YakuId.dora] に
  /// まとめる）。役が無いときは最も高い解釈のもの（ドラだけ）。
  final Set<YakuId> ronYaku;
  final Set<YakuId> tsumoYaku;

  /// 和了形にあるドラ（表ドラ + 赤）の枚数。
  final int doraCount;

  const WinEvaluation({
    required this.ron,
    required this.tsumo,
    required this.ronPoints,
    required this.tsumoPoints,
    required this.ronRiichiPoints,
    required this.tsumoRiichiPoints,
    required this.ronYaku,
    required this.tsumoYaku,
    required this.doraCount,
  });

  /// 順位付け・打牌の選択に使う値（ロン + ツモ）。門前はリーチ込み、副露はダマ。
  int get rankingValue =>
      (ronRiichiPoints ?? ronPoints) + (tsumoRiichiPoints ?? tsumoPoints);
}

/// `HandAnalyzer` で和了形を評価するラッパー。
///
/// 副露・ドラ・赤・自風・場風・親子は [context] から取る。1 回の解析の中で同じ
/// 和了形を何度も評価するので、結果をメモする。
///
/// `HandAnalyzer.evaluateBest` は和了形の分け方を全部試して最も点の高い解釈を返すが、
/// 副露を「その面子として取った分け方」に限らない（副露フラグを付けられない分け方も
/// 門前として数える）。ここでは `HandParser` の分け方のうち副露をそのまま含むものだけを
/// 使い、副露面子に [Meld.open] を付けてから `HandAnalyzer.scoreHand` で採点する。
/// また役の無い解釈を除いてから最高点を選ぶ（役なしの解釈が高点に見えても和了できない）。
class WinEvaluator {
  final HandState context;
  final Ruleset ruleset;

  final HandAnalyzer _analyzer = HandAnalyzer();
  final HandParser _parser = HandParser();
  final ScoringEngine _scoring;
  final Map<String, WinEvaluation?> _cache = {};
  final List<String> _meldLabels;
  final bool _open;
  final QuickContext _ron;
  final QuickContext _tsumo;

  WinEvaluator(this.context, {Ruleset? ruleset})
    : ruleset = ruleset ?? Rulesets.mLeague(),
      _scoring = ScoringEngine(ruleset ?? Rulesets.mLeague()),
      _meldLabels = [
        for (final meld in context.openMelds)
          for (final tile in meld.tiles) _labelOfTile(tile),
      ],
      _open = context.openMelds.any((m) => m.open),
      _ron = _baseContext(context, WinType.ron),
      _tsumo = _baseContext(context, WinType.tsumo);

  /// 門前（暗槓だけなら門前）か。
  bool get isClosed => !_open;

  /// メモした和了形の数（テスト・計測用）。
  int get cacheSize => _cache.length;

  /// [closed14] は副露を除いた手牌（和了牌を含む）、[winTile] は和了牌。
  /// [redHeld] は赤5を持っている牌 id（[kRedFiveIds] のうち）。
  /// 和了形でなければ null。
  WinEvaluation? evaluate(
    List<int> closed14,
    int winTile, {
    Set<int> redHeld = const {},
  }) {
    final key = _key(closed14, winTile, redHeld);
    if (_cache.containsKey(key)) return _cache[key];
    final result = _evaluate(closed14, winTile, redHeld);
    _cache[key] = result;
    return result;
  }

  WinEvaluation? _evaluate(List<int> closed, int winTile, Set<int> redHeld) {
    final labels = <String>[];
    for (var id = 0; id < kTileKinds; id++) {
      for (var k = 0; k < closed[id]; k++) {
        labels.add(
          k == 0 && redHeld.contains(id) && kRedFiveIds.contains(id)
              ? _redLabel(id)
              : _label(id),
        );
      }
    }
    labels.addAll(_meldLabels);

    var dora = 0;
    for (final d in context.doraIds) {
      dora += closed[d] + context.meldTileCount(d);
    }
    final ronCtx = _ron.copyWith(doraIndicators: dora);
    final tsumoCtx = _tsumo.copyWith(doraIndicators: dora);
    final winLabel = _label(winTile);

    final ron = _Best();
    final tsumo = _Best();
    var found = false;
    for (final pattern in _parser.parse(labels)) {
      final melds = context.openMelds;
      if (melds.isNotEmpty && (pattern.kokushi || pattern.sevenPairs)) continue;
      final base = pattern.materialize(labels);
      if (base == null) continue;
      MaterializedHand hand = base;
      if (melds.isNotEmpty) {
        final flags = _openFlags(base);
        if (flags == null) continue;
        final opened = pattern.materialize(labels, openFlags: flags);
        if (opened == null) continue;
        hand = opened;
      }
      found = true;
      ron.add(
        _analyzer.scoreHand(hand, ronCtx, ruleset, winningLabel: winLabel),
        this,
      );
      tsumo.add(
        _analyzer.scoreHand(hand, tsumoCtx, ruleset, winningLabel: winLabel),
        this,
      );
    }
    final ronAny = ron.any;
    final tsumoAny = tsumo.any;
    if (!found || ronAny == null || tsumoAny == null) return null;

    final dealer = context.dealer;
    return WinEvaluation(
      ron: ron.valid,
      tsumo: tsumo.valid,
      ronPoints: ron.valid == null
          ? 0
          : ronPayment(ron.valid!.basePoints, dealer: dealer),
      tsumoPoints: tsumo.valid == null
          ? 0
          : tsumoPayment(tsumo.valid!.basePoints, dealer: dealer),
      ronRiichiPoints: _open
          ? null
          : ronPayment(ron.riichiBase, dealer: dealer),
      tsumoRiichiPoints: _open
          ? null
          : tsumoPayment(tsumo.riichiBase, dealer: dealer),
      ronYaku: prospectYakuOf(ron.valid ?? ronAny),
      tsumoYaku: prospectYakuOf(tsumo.valid ?? tsumoAny),
      doraCount: dora + _redCount(labels),
    );
  }

  int _redCount(List<String> labels) {
    var n = 0;
    for (final l in labels) {
      if (l.startsWith('0')) n++;
    }
    return n > ruleset.redFives ? ruleset.redFives : n;
  }

  /// リーチ（1 翻）を足したときの基本点。役満は変わらない。
  int _riichiBase(HandScore score) {
    if (score.yaku.any((y) => _hanOf(y, score.closed) >= 13)) {
      return score.basePoints;
    }
    return _scoring.basePointsFor(
      han: score.han + 1,
      fu: score.fu == 0 ? 20 : score.fu,
      yaku: score.yaku,
    );
  }

  /// 副露面子を分け方の中から探して副露フラグを付ける。含まない分け方なら null。
  List<bool>? _openFlags(MaterializedHand base) {
    final flags = List<bool>.filled(base.melds.length, false);
    final used = List<bool>.filled(base.melds.length, false);
    for (final meld in context.openMelds) {
      final want = _sortedIds(meld.tiles);
      var matched = false;
      for (var i = 0; i < base.melds.length; i++) {
        if (used[i] || base.melds[i].type != meld.type) continue;
        if (!_sameIds(_sortedIds(base.melds[i].tiles), want)) continue;
        used[i] = true;
        flags[i] = meld.open;
        matched = true;
        break;
      }
      if (!matched) return null;
    }
    return flags;
  }

  String _key(List<int> closed, int winTile, Set<int> redHeld) {
    final codes = List<int>.generate(kTileKinds + 2, (i) {
      if (i < kTileKinds) return 48 + closed[i];
      if (i == kTileKinds) return 48 + winTile;
      var mask = 0;
      for (var r = 0; r < kRedFiveIds.length; r++) {
        if (redHeld.contains(kRedFiveIds[r])) mask |= 1 << r;
      }
      return 48 + mask;
    });
    return String.fromCharCodes(codes);
  }

  static QuickContext _baseContext(HandState hand, WinType winType) =>
      QuickContext(
        roundWind: hand.roundWind,
        seatWind: hand.seatWind,
        parentChild: hand.dealer ? ParentChild.parent : ParentChild.child,
        winType: winType,
        openMelds: hand.openMelds.any((m) => m.open),
      );
}

/// 役のある最高点の解釈と、リーチ込みの最高基本点を集める。
class _Best {
  HandScore? valid;
  HandScore? any;
  int riichiBase = 0;

  void add(HandScore score, WinEvaluator owner) {
    if (!score.isValid) return;
    if (any == null || _compare(score, any!) > 0) any = score;
    if (scoreHasYaku(score) && (valid == null || _compare(score, valid!) > 0)) {
      valid = score;
    }
    final r = owner._riichiBase(score);
    if (r > riichiBase) riichiBase = r;
  }

  // HandAnalyzer の _compareScore と同じ順（基本点 → 翻 → 符）。
  static int _compare(HandScore a, HandScore b) {
    if (a.basePoints != b.basePoints) {
      return a.basePoints.compareTo(b.basePoints);
    }
    if (a.han != b.han) return a.han.compareTo(b.han);
    return a.fu.compareTo(b.fu);
  }
}

/// ドラ以外で翻のある役が 1 つでもあるか（役なしでは和了できない）。
bool scoreHasYaku(HandScore score) {
  for (final y in score.yaku) {
    if (YakuCatalog.isDora(y.name)) continue;
    if (_hanOf(y, score.closed) > 0) return true;
  }
  return false;
}

/// [score] の役のうち「狙える役」に出すもの（赤は [YakuId.dora] にまとめる）。
Set<YakuId> prospectYakuOf(HandScore score) {
  final result = <YakuId>{};
  for (final y in score.yaku) {
    final id = yakuIdOf(y);
    if (id == null) continue;
    if (id == YakuId.dora || id == YakuId.akaDora) {
      if (_hanOf(y, score.closed) > 0) result.add(YakuId.dora);
      continue;
    }
    if (!id.isProspect) continue;
    if (_hanOf(y, score.closed) > 0) result.add(id);
  }
  return result;
}

int _hanOf(Yaku y, bool closed) => closed ? y.hanClosed : y.hanOpen;

String _label(int id) => '${id % 9 + 1}${'mpsz'[id ~/ 9]}';

String _redLabel(int id) => '0${'mpsz'[id ~/ 9]}';

String _labelOfTile(Tile tile) {
  if (tile.red && tile.suit != Suit.z && tile.value == 5) {
    return '0${tile.suit.name}';
  }
  return '${tile.value}${tile.suit.name}';
}

List<int> _sortedIds(List<Tile> tiles) =>
    [for (final t in tiles) tileIdOf(t)]..sort();

bool _sameIds(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
