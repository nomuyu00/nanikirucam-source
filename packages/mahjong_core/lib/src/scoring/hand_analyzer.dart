// 流用元: reference/agari_cam/lib/scoring/hand_analyzer.dart（2026-10-21 時点）
import 'package:mahjong_core/src/hand_parser.dart';
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/scoring/han_yaku.dart';
import 'package:mahjong_core/src/scoring/ruleset_support.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';
import 'package:mahjong_core/src/scoring/scoring_engine.dart';
import 'package:mahjong_core/src/tile_utils.dart';
import 'package:mahjong_core/src/wait_type.dart';

class HandScore {
  final MaterializedHand hand;
  final List<Yaku> yaku;
  final int han;
  final int fu;
  final WaitType waitType;
  final bool closed;
  final bool isValid;
  final FuBreakdown? fuBreakdown;
  // 和了牌で完成した面子（hand.melds の添字）。七対子・国士・和了牌不明は null。
  final int? winningGroupIndex;
  final int basePoints;

  const HandScore({
    required this.hand,
    required this.yaku,
    required this.han,
    required this.fu,
    required this.waitType,
    required this.closed,
    required this.isValid,
    this.fuBreakdown,
    this.winningGroupIndex,
    this.basePoints = 0,
  });
}

class HandEvaluation {
  final ParsedHandPattern pattern;
  final HandScore score;
  const HandEvaluation(this.pattern, this.score);
}

/// 面子の副露フラグを、解析した分け方ごとに決める関数。
typedef OpenFlagsFor = List<bool> Function(MaterializedHand base);

class HandAnalyzer {
  final HandParser _parser = HandParser();

  /// 面子の分け方 × 和了牌の取り方（どの面子を完成させたか）をすべて試し、
  /// 実際の点数が最も高い解釈を返す。
  HandEvaluation? evaluateBest(
    List<String> labels,
    QuickContext ctx,
    Ruleset ruleset, {
    String? winningLabel,
    WaitType? manualWait,
    OpenFlagsFor? openFlagsFor,
  }) {
    HandEvaluation? best;
    HandEvaluation? bestMatchingWait;
    for (final pattern in _parser.parse(labels)) {
      final base = pattern.materialize(labels);
      if (base == null) continue;
      final flags = openFlagsFor?.call(base);
      final hand = flags == null
          ? base
          : pattern.materialize(labels, openFlags: flags);
      if (hand == null) continue;
      final score = scoreHand(
        hand,
        ctx,
        ruleset,
        winningLabel: winningLabel,
        manualWait: manualWait,
      );
      if (!score.isValid) continue;
      final evaluation = HandEvaluation(pattern, score);
      if (best == null || _compareScore(score, best.score) > 0) {
        best = evaluation;
      }
      if (manualWait != null &&
          score.waitType == manualWait &&
          (bestMatchingWait == null ||
              _compareScore(score, bestMatchingWait.score) > 0)) {
        bestMatchingWait = evaluation;
      }
    }
    return bestMatchingWait ?? best;
  }

  ParsedHandPattern? selectBestPattern(
    List<String> labels,
    QuickContext ctx,
    Ruleset ruleset, {
    String? winningLabel,
    WaitType? manualWait,
    OpenFlagsFor? openFlagsFor,
  }) {
    return evaluateBest(
      labels,
      ctx,
      ruleset,
      winningLabel: winningLabel,
      manualWait: manualWait,
      openFlagsFor: openFlagsFor,
    )?.pattern;
  }

  /// 和了牌から考えられる待ちの形（分け方をまたいだ和集合）。
  Set<WaitType> possibleWaits(List<String> labels, String? winningLabel) {
    if (winningLabel == null) return const {};
    final winningTile = tileFromLabel(winningLabel);
    final waits = <WaitType>{};
    for (final pattern in _parser.parse(labels)) {
      final hand = pattern.materialize(labels);
      if (hand == null) continue;
      if (hand.kokushi || hand.sevenPairs) {
        waits.add(WaitType.tanki);
        continue;
      }
      for (final index in _winningGroupCandidates(hand.melds, winningTile)) {
        waits.add(_waitForGroup(hand.melds[index], winningTile));
      }
    }
    return waits;
  }

  MaterializedHand? materializePattern(
    ParsedHandPattern pattern,
    List<String> labels, {
    List<bool>? openFlags,
  }) {
    return pattern.materialize(labels, openFlags: openFlags);
  }

  HandScore scoreHand(
    MaterializedHand hand,
    QuickContext ctx,
    Ruleset ruleset, {
    String? winningLabel,
    WaitType? manualWait,
    int? winningGroupIndex,
  }) {
    final calledMeld = hand.melds.any((meld) => meld.open);
    final effectiveCtx = RulesetSupport.effectiveContext(
      calledMeld ? ctx.copyWith(openMelds: true) : ctx,
      ruleset,
    );
    if (hand.kokushi) {
      final yaku = RulesetSupport.contextYaku(effectiveCtx, ruleset)
        ..add(_kokushiYaku(hand, ruleset, winningLabel));
      return _finish(
        hand: hand,
        yaku: yaku,
        closed: true,
        fu: 0,
        wait: WaitType.tanki,
        ruleset: ruleset,
      );
    }

    final melds = hand.melds;
    if (melds.isEmpty && !hand.sevenPairs) {
      return HandScore(
        hand: hand,
        yaku: const [],
        han: 0,
        fu: 0,
        waitType: manualWait ?? WaitType.ryanmen,
        closed: true,
        isValid: false,
      );
    }

    final closed = !effectiveCtx.openMelds;
    final tiles = [
      for (final group in hand.labelGroups)
        for (final label in group) tileFromLabel(label),
    ];

    if (hand.sevenPairs) {
      final yaku = _situationalYaku(effectiveCtx, ruleset, hasKan: false)
        ..add(YakuCatalog.chitoitsu);
      final hasTermOrHonor = tiles.any((t) => t.isHonor || t.isTerminal);
      if (!hasTermOrHonor && (closed || ruleset.kuitan)) {
        yaku.add(YakuCatalog.tanyao);
      }
      _applySuitYaku(yaku, tiles);
      _applyWholeHandYaku(yaku, tiles, hand, closed);
      yaku.addAll(_doraYaku(effectiveCtx, hand, ruleset));
      const breakdown = FuBreakdown(
        items: [FuItem(label: '七対子', value: 25)],
        total: 25,
      );
      return _finish(
        hand: hand,
        yaku: yaku,
        closed: closed,
        fu: breakdown.total,
        wait: WaitType.tanki,
        ruleset: ruleset,
        breakdown: breakdown,
      );
    }

    final winningTile = winningLabel != null
        ? tileFromLabel(winningLabel)
        : null;
    final candidates = <int?>[];
    if (winningGroupIndex != null) {
      candidates.add(winningGroupIndex);
    } else if (winningTile != null) {
      candidates.addAll(_winningGroupCandidates(melds, winningTile));
    }
    if (candidates.isEmpty) candidates.add(null);

    HandScore? best;
    HandScore? bestMatchingWait;
    for (final index in candidates) {
      final inferred = index == null || winningTile == null
          ? (manualWait ?? WaitType.ryanmen)
          : _waitForGroup(melds[index], winningTile);
      final score = _scoreStandard(
        hand,
        effectiveCtx,
        ruleset,
        tiles: tiles,
        closed: closed,
        wait: inferred,
        winningGroupIndex: index,
        winningLabel: winningLabel,
      );
      if (best == null || _compareScore(score, best) > 0) best = score;
      if (manualWait != null &&
          inferred == manualWait &&
          (bestMatchingWait == null ||
              _compareScore(score, bestMatchingWait) > 0)) {
        bestMatchingWait = score;
      }
    }
    return bestMatchingWait ?? best!;
  }

  HandScore _scoreStandard(
    MaterializedHand hand,
    QuickContext ctx,
    Ruleset ruleset, {
    required List<Tile> tiles,
    required bool closed,
    required WaitType wait,
    required int? winningGroupIndex,
    required String? winningLabel,
  }) {
    final scoringMelds = _meldsForScoring(hand.melds, ctx, winningGroupIndex);
    final hasKan = hand.melds.any((meld) => meld.type == MeldType.kantsu);
    final yaku = _situationalYaku(ctx, ruleset, hasKan: hasKan);
    final pairMeld = scoringMelds.firstWhere(
      (m) => m.type == MeldType.pair,
      orElse: () => const Meld(type: MeldType.pair, tiles: [], open: false),
    );

    _applyStructureYaku(
      yaku,
      scoringMelds,
      hand,
      ctx,
      ruleset,
      closed,
      tiles,
      wait,
      pairMeld,
    );
    _applyWholeHandYaku(yaku, tiles, hand, closed);
    _upgradeYakumanVariants(yaku, hand, ruleset, wait, winningLabel);
    yaku.addAll(_doraYaku(ctx, hand, ruleset));

    final pinfu = _isPinfuCandidate(scoringMelds, wait, closed, ctx);
    final breakdown = _buildFuBreakdown(
      closed: closed,
      pinfu: pinfu,
      ron: ctx.winType == WinType.ron,
      melds: scoringMelds,
      pair: pairMeld,
      waitType: wait,
      ctx: ctx,
      ruleset: ruleset,
    );
    return _finish(
      hand: hand,
      yaku: yaku,
      closed: closed,
      fu: breakdown.total,
      wait: wait,
      ruleset: ruleset,
      breakdown: breakdown,
      winningGroupIndex: winningGroupIndex,
    );
  }

  HandScore _finish({
    required MaterializedHand hand,
    required List<Yaku> yaku,
    required bool closed,
    required int fu,
    required WaitType wait,
    required Ruleset ruleset,
    FuBreakdown? breakdown,
    int? winningGroupIndex,
  }) {
    final normalized = RulesetSupport.normalizeYakuList(
      yaku,
      open: !closed,
      ruleset: ruleset,
    );
    final han = RulesetSupport.totalHanForRuleset(
      normalized,
      open: !closed,
      ruleset: ruleset,
    );
    return HandScore(
      hand: hand,
      yaku: normalized,
      han: han,
      fu: fu,
      waitType: wait,
      closed: closed,
      isValid: true,
      fuBreakdown: breakdown,
      winningGroupIndex: winningGroupIndex,
      basePoints: ScoringEngine(
        ruleset,
      ).basePointsFor(han: han, fu: fu == 0 ? 20 : fu, yaku: normalized),
    );
  }

  List<Yaku> _situationalYaku(
    QuickContext ctx,
    Ruleset ruleset, {
    required bool hasKan,
  }) {
    final yaku = RulesetSupport.contextYaku(ctx, ruleset);
    // 嶺上開花は槓をした手でしか成立しない。
    if (!hasKan) {
      yaku.removeWhere((value) => value.name == YakuCatalog.rinshan.name);
    }
    return yaku;
  }

  List<Yaku> _doraYaku(
    QuickContext ctx,
    MaterializedHand hand,
    Ruleset ruleset,
  ) {
    return RulesetSupport.doraYaku(
      ctx,
      ruleset,
      labels: hand.labelGroups.expand((e) => e),
    );
  }

  /// 和了牌を含みうる面子（槓子は和了牌で完成しないので除外）。
  static List<int> _winningGroupCandidates(List<Meld> melds, Tile winning) {
    final result = <int>[];
    for (var i = 0; i < melds.length; i++) {
      final meld = melds[i];
      if (meld.type == MeldType.kantsu || meld.open) continue;
      if (meld.tiles.any(
        (t) => t.suit == winning.suit && t.value == winning.value,
      )) {
        result.add(i);
      }
    }
    // 副露した面子しか候補がない場合（入力の矛盾）も計算は続ける。
    if (result.isEmpty) {
      for (var i = 0; i < melds.length; i++) {
        if (melds[i].type == MeldType.kantsu) continue;
        if (melds[i].tiles.any(
          (t) => t.suit == winning.suit && t.value == winning.value,
        )) {
          result.add(i);
        }
      }
    }
    return result;
  }

  static WaitType _waitForGroup(Meld meld, Tile winning) {
    switch (meld.type) {
      case MeldType.pair:
        return WaitType.tanki;
      case MeldType.koutsu:
      case MeldType.kantsu:
        return WaitType.shanpon;
      case MeldType.shuntsu:
        final values = meld.tiles.map((t) => t.value).toList()..sort();
        final w = winning.value;
        if (values[1] == w) return WaitType.kanchan;
        if (values[0] == 1 && w == 3) return WaitType.penchan;
        if (values[0] == 7 && w == 7) return WaitType.penchan;
        return WaitType.ryanmen;
    }
  }

  // ロンで完成させた刻子だけは明刻として符と暗刻数を数える。
  List<Meld> _meldsForScoring(
    List<Meld> melds,
    QuickContext ctx,
    int? winningGroupIndex,
  ) {
    if (ctx.winType != WinType.ron || winningGroupIndex == null) {
      return melds;
    }
    return [
      for (var i = 0; i < melds.length; i++)
        if (i == winningGroupIndex &&
            !melds[i].open &&
            melds[i].type == MeldType.koutsu)
          Meld(type: melds[i].type, tiles: melds[i].tiles, open: true)
        else
          melds[i],
    ];
  }

  int _compareScore(HandScore a, HandScore b) {
    if (a.basePoints != b.basePoints) {
      return a.basePoints.compareTo(b.basePoints);
    }
    if (a.han != b.han) return a.han.compareTo(b.han);
    if (a.fu != b.fu) return a.fu.compareTo(b.fu);
    return 0;
  }

  void _applyStructureYaku(
    List<Yaku> yaku,
    List<Meld> melds,
    MaterializedHand hand,
    QuickContext ctx,
    Ruleset ruleset,
    bool closed,
    List<Tile> tiles,
    WaitType waitType,
    Meld pair,
  ) {
    final sequences = <String, int>{};
    var tripletOnly = true;
    int concealedTriplets = 0;
    int kanCount = 0;
    final Set<int> dragonTripletValues = <int>{};
    final Set<int> windTripletValues = <int>{};
    final Map<int, Set<Suit>> tripletSuitMap = <int, Set<Suit>>{};
    for (final meld in melds) {
      switch (meld.type) {
        case MeldType.shuntsu:
          tripletOnly = false;
          final base = _sequenceKey(meld.tiles);
          sequences[base] = (sequences[base] ?? 0) + 1;
          break;
        case MeldType.koutsu:
          if (!meld.open) concealedTriplets += 1;
          _recordTripletSets(
            meld.tiles.first,
            dragonTripletValues,
            windTripletValues,
            tripletSuitMap,
          );
          break;
        case MeldType.kantsu:
          kanCount += 1;
          if (!meld.open) concealedTriplets += 1;
          _recordTripletSets(
            meld.tiles.first,
            dragonTripletValues,
            windTripletValues,
            tripletSuitMap,
          );
          break;
        case MeldType.pair:
          break;
      }
    }

    final pairTile = pair.tiles.isNotEmpty ? pair.tiles.first : null;

    final hasTermOrHonor = tiles.any((t) => t.isHonor || t.isTerminal);
    if (!hasTermOrHonor && (closed || ruleset.kuitan)) {
      yaku.add(YakuCatalog.tanyao);
    }

    if (tripletOnly) {
      yaku.add(YakuCatalog.toitoi);
    }

    if (closed && tripletOnly && concealedTriplets >= 4) {
      yaku.add(YakuCatalog.suuankou);
    }

    if (concealedTriplets >= 3) {
      yaku.add(YakuCatalog.sanankou);
    }

    if (kanCount == 4) {
      yaku.add(YakuCatalog.suukantsu);
    } else if (kanCount == 3) {
      yaku.add(YakuCatalog.sankantsu);
    }

    if (dragonTripletValues.length == 3) {
      yaku.add(YakuCatalog.daisangen);
    }

    if (dragonTripletValues.length >= 2 &&
        pairTile != null &&
        pairTile.suit == Suit.z &&
        pairTile.value >= 5 &&
        !dragonTripletValues.contains(pairTile.value)) {
      yaku.add(YakuCatalog.shousangen);
    }

    if (windTripletValues.length == 4) {
      yaku.add(YakuCatalog.daisushi);
    } else if (windTripletValues.length == 3 &&
        pairTile != null &&
        pairTile.suit == Suit.z &&
        pairTile.value >= 1 &&
        pairTile.value <= 4 &&
        !windTripletValues.contains(pairTile.value)) {
      yaku.add(YakuCatalog.shosushi);
    }

    if (tripletSuitMap.values.any((suits) => suits.length == 3)) {
      yaku.add(YakuCatalog.sanshokudoukou);
    }

    _applySequenceYaku(yaku, sequences, closed);
    _applySuitYaku(yaku, tiles);
    _applyChantaYaku(yaku, melds, tiles, hand);
    _applyYakuhai(yaku, melds, ctx);

    if (_isPinfuCandidate(melds, waitType, closed, ctx)) {
      yaku.add(YakuCatalog.pinfu);
    }
  }

  void _applyYakuhai(List<Yaku> yaku, List<Meld> melds, QuickContext ctx) {
    final seat = _windValue(ctx.seatWind);
    final round = _windValue(ctx.roundWind);
    final sameWind = seat == round;
    for (final meld in melds) {
      if (meld.type != MeldType.koutsu && meld.type != MeldType.kantsu) {
        continue;
      }
      final tile = meld.tiles.first;
      if (tile.suit != Suit.z) continue;
      if (tile.value >= 5) {
        yaku.add(YakuCatalog.yakuhaiFor(_dragonLabel(tile.value)));
        continue;
      }
      if (sameWind && tile.value == seat) {
        yaku.add(_doubleWindYaku(ctx.seatWind));
        continue;
      }
      if (tile.value == seat) {
        yaku.add(YakuCatalog.yakuhaiFor('自風 ${_windLabel(ctx.seatWind)}'));
      }
      if (!sameWind && tile.value == round) {
        yaku.add(YakuCatalog.yakuhaiFor('場風 ${_windLabel(ctx.roundWind)}'));
      }
    }
  }

  void _applySequenceYaku(
    List<Yaku> yaku,
    Map<String, int> sequences,
    bool closed,
  ) {
    int pairRuns = 0;
    final suitMap = <String, Set<int>>{};
    sequences.forEach((key, count) {
      final parts = key.split(':');
      final suit = parts[0];
      final start = int.parse(parts[1]);
      pairRuns += count ~/ 2;
      suitMap.putIfAbsent(suit, () => <int>{}).add(start);
    });
    if (pairRuns >= 2) {
      if (closed) {
        yaku.add(YakuCatalog.ryanpeikou);
      }
    } else if (pairRuns >= 1 && closed) {
      yaku.add(YakuCatalog.iipeikou);
    }

    for (final entry in suitMap.entries) {
      if (entry.value.containsAll({0, 3, 6})) {
        yaku.add(YakuCatalog.ittsu);
      }
    }

    for (var start = 0; start <= 6; start++) {
      var present = 0;
      for (var suit = 0; suit < 3; suit++) {
        if ((sequences['$suit:$start'] ?? 0) > 0) {
          present += 1;
        }
      }
      if (present == 3) {
        yaku.add(YakuCatalog.sanshoku);
        break;
      }
    }
  }

  void _applySuitYaku(List<Yaku> yaku, List<Tile> tiles) {
    final suitUsed = <Suit, bool>{Suit.m: false, Suit.p: false, Suit.s: false};
    var hasHonor = false;
    for (final tile in tiles) {
      if (tile.suit == Suit.z) {
        hasHonor = true;
      } else {
        suitUsed[tile.suit] = true;
      }
    }
    final suitCount = suitUsed.values.where((v) => v).length;
    if (suitCount == 1 && !hasHonor) {
      yaku.add(YakuCatalog.chinitsu);
    } else if (suitCount == 1 && hasHonor) {
      yaku.add(YakuCatalog.honitsu);
    }
  }

  void _applyChantaYaku(
    List<Yaku> yaku,
    List<Meld> melds,
    List<Tile> tiles,
    MaterializedHand hand,
  ) {
    // 全刻子形は混老頭・清老頭として扱い、全帯系とは複合しない。
    if (!melds.any((meld) => meld.type == MeldType.shuntsu)) return;
    var allChanta = true;
    final hasHonor = tiles.any((t) => t.suit == Suit.z);
    for (final meld in melds) {
      if (!meld.tiles.any((t) => t.isHonor || t.isTerminal)) {
        allChanta = false;
        break;
      }
    }
    if (!allChanta || hand.kokushi) return;
    yaku.add(hasHonor ? YakuCatalog.chanta : YakuCatalog.junchan);
  }

  void _applyWholeHandYaku(
    List<Yaku> yaku,
    List<Tile> tiles,
    MaterializedHand hand,
    bool closed,
  ) {
    if (_isRyuuiisou(tiles)) {
      yaku.add(YakuCatalog.ryuuiisou);
    }
    if (_isChinroutou(tiles)) {
      yaku.add(YakuCatalog.chinroutou);
    }
    if (_isTsuiisou(tiles)) {
      yaku.add(YakuCatalog.tsuiisou);
    }
    if (_isHonroutou(tiles)) {
      yaku.add(YakuCatalog.honroutou);
    }
    if (!hand.kokushi && closed && _isChuuren(tiles)) {
      yaku.add(YakuCatalog.chuuren);
    }
  }

  void _recordTripletSets(
    Tile tile,
    Set<int> dragonTripletValues,
    Set<int> windTripletValues,
    Map<int, Set<Suit>> tripletSuitMap,
  ) {
    if (tile.suit == Suit.z) {
      if (tile.value >= 5) {
        dragonTripletValues.add(tile.value);
      } else {
        windTripletValues.add(tile.value);
      }
      return;
    }
    tripletSuitMap.putIfAbsent(tile.value, () => <Suit>{}).add(tile.suit);
  }

  bool _isRyuuiisou(List<Tile> tiles) {
    if (tiles.isEmpty) return false;
    const allowedSouValues = {2, 3, 4, 6, 8};
    for (final tile in tiles) {
      if (tile.suit == Suit.z) {
        if (tile.value != 6) return false;
        continue;
      }
      if (tile.suit != Suit.s) return false;
      if (!allowedSouValues.contains(tile.value)) return false;
    }
    return true;
  }

  bool _isChinroutou(List<Tile> tiles) {
    if (tiles.isEmpty) return false;
    for (final tile in tiles) {
      if (tile.suit == Suit.z) return false;
      if (!(tile.value == 1 || tile.value == 9)) return false;
    }
    return true;
  }

  bool _isTsuiisou(List<Tile> tiles) {
    if (tiles.isEmpty) return false;
    return tiles.every((tile) => tile.isHonor);
  }

  bool _isHonroutou(List<Tile> tiles) {
    if (tiles.isEmpty) return false;
    var hasTerminal = false;
    var hasHonor = false;
    for (final tile in tiles) {
      if (tile.isHonor) {
        hasHonor = true;
      } else if (tile.isTerminal) {
        hasTerminal = true;
      } else {
        return false;
      }
    }
    return hasTerminal && hasHonor;
  }

  bool _isChuuren(List<Tile> tiles) {
    if (tiles.length != 14) return false;
    final first = tiles.first;
    if (first.suit == Suit.z) return false;
    final suit = first.suit;
    final counts = List<int>.filled(10, 0);
    for (final tile in tiles) {
      if (tile.suit != suit || tile.isHonor) {
        return false;
      }
      counts[tile.value] += 1;
    }
    if (counts[1] < 3 || counts[9] < 3) return false;
    for (var v = 2; v <= 8; v++) {
      if (counts[v] < 1) return false;
    }
    return true;
  }

  Yaku _kokushiYaku(
    MaterializedHand hand,
    Ruleset ruleset,
    String? winningLabel,
  ) {
    if (!ruleset.doubleYakuman || winningLabel == null) {
      return YakuCatalog.kokushi;
    }
    final winningId = tileIdFromLabel(winningLabel);
    final counts = <int, int>{};
    for (final label in hand.kokushiLabels) {
      final id = tileIdFromLabel(label);
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if ((counts[winningId] ?? 0) == 2 && counts.length == 13) {
      return RulesetSupport.doubleYakuman('国士無双十三面待ち', openAllowed: false);
    }
    return YakuCatalog.kokushi;
  }

  void _upgradeYakumanVariants(
    List<Yaku> yaku,
    MaterializedHand hand,
    Ruleset ruleset,
    WaitType waitType,
    String? winningLabel,
  ) {
    if (!ruleset.doubleYakuman) return;
    if (waitType == WaitType.tanki) {
      _replaceYakuman(
        yaku,
        from: YakuCatalog.suuankou,
        to: RulesetSupport.doubleYakuman('四暗刻単騎', openAllowed: false),
      );
    }
    _replaceYakuman(
      yaku,
      from: YakuCatalog.daisushi,
      to: RulesetSupport.doubleYakuman('大四喜'),
    );
    if (_isPureChuuren(hand, winningLabel)) {
      _replaceYakuman(
        yaku,
        from: YakuCatalog.chuuren,
        to: RulesetSupport.doubleYakuman('純正九蓮宝燈', openAllowed: false),
      );
    }
  }

  void _replaceYakuman(
    List<Yaku> yaku, {
    required Yaku from,
    required Yaku to,
  }) {
    final index = yaku.indexWhere((value) => value.name == from.name);
    if (index == -1) return;
    yaku[index] = to;
  }

  bool _isPureChuuren(MaterializedHand hand, String? winningLabel) {
    if (winningLabel == null) return false;
    final labels = hand.labelGroups.expand((e) => e).toList(growable: false);
    if (labels.length != 14) return false;
    final winningTile = tileFromLabel(winningLabel);
    if (winningTile.suit == Suit.z) return false;
    final counts = List<int>.filled(10, 0);
    for (final label in labels) {
      final tile = tileFromLabel(label);
      if (tile.suit != winningTile.suit || tile.suit == Suit.z) {
        return false;
      }
      counts[tile.value] += 1;
    }
    const required = <int, int>{
      1: 3,
      2: 1,
      3: 1,
      4: 1,
      5: 1,
      6: 1,
      7: 1,
      8: 1,
      9: 3,
    };
    final needed = required[winningTile.value] ?? 0;
    return counts[winningTile.value] > needed;
  }

  FuBreakdown _buildFuBreakdown({
    required bool closed,
    required bool pinfu,
    required bool ron,
    required List<Meld> melds,
    required Meld pair,
    required WaitType waitType,
    required QuickContext ctx,
    required Ruleset ruleset,
  }) {
    if (melds.isEmpty) {
      return const FuBreakdown(items: [], total: 0);
    }
    final items = <FuItem>[const FuItem(label: '基本符', value: 20)];
    var fu = 20;

    // 門前ロン10符は平和ロンでも加算する（平和=30符）
    if (ron && closed) {
      fu += 10;
      items.add(const FuItem(label: '門前ロン', value: 10));
    }
    if (!ron && !pinfu) {
      fu += 2;
      items.add(const FuItem(label: 'ツモ', value: 2));
    }

    for (final head in _headFuItems(pair, ctx, ruleset)) {
      fu += head.value;
      items.add(head);
    }

    for (final meld in melds) {
      final item = _meldFuItem(meld);
      if (item != null) {
        fu += item.value;
        items.add(item);
      }
    }

    final waitItem = _waitFuItem(waitType, pinfu);
    if (waitItem != null) {
      fu += waitItem.value;
      items.add(waitItem);
    }

    if (ron && !closed && fu == 20) {
      fu += 10;
      items.add(const FuItem(label: '副露平和形ロン', value: 10));
    }

    if (fu % 10 != 0) {
      final rounded = ((fu / 10).floor() + 1) * 10;
      items.add(FuItem(label: '切り上げ', value: rounded - fu));
      fu = rounded;
    }

    return FuBreakdown(items: items, total: fu);
  }

  List<FuItem> _headFuItems(Meld pair, QuickContext ctx, Ruleset ruleset) {
    if (pair.tiles.isEmpty) return const [];
    final tile = pair.tiles.first;
    if (tile.suit != Suit.z) return const [];
    if (tile.value >= 5) {
      return [FuItem(label: '雀頭(役牌 ${_dragonLabel(tile.value)})', value: 2)];
    }
    final seat = _windValue(ctx.seatWind);
    final round = _windValue(ctx.roundWind);
    if (tile.value == seat && tile.value == round) {
      return [
        FuItem(
          label: '雀頭(連風牌 ${_windLabel(ctx.seatWind)})',
          value: ruleset.doubleWindPairFu,
        ),
      ];
    }
    return [
      if (tile.value == seat)
        FuItem(label: '雀頭(自風 ${_windLabel(ctx.seatWind)})', value: 2),
      if (tile.value == round)
        FuItem(label: '雀頭(場風 ${_windLabel(ctx.roundWind)})', value: 2),
    ];
  }

  FuItem? _meldFuItem(Meld meld) {
    if (meld.tiles.isEmpty) return null;
    switch (meld.type) {
      case MeldType.koutsu:
        final tile = meld.tiles.first;
        final terminalOrHonor = tile.isHonor || tile.isTerminal;
        final base = meld.open ? 2 : 4;
        final fu = base * (terminalOrHonor ? 2 : 1);
        final label =
            '${meld.open ? '明刻' : '暗刻'}(${terminalOrHonor ? 'ヤオ九牌' : '中張牌'})';
        return FuItem(label: label, value: fu);
      case MeldType.kantsu:
        final tile = meld.tiles.first;
        final terminalOrHonor = tile.isHonor || tile.isTerminal;
        final base = meld.open ? 8 : 16;
        final fu = base * (terminalOrHonor ? 2 : 1);
        final label =
            '${meld.open ? '明槓' : '暗槓'}(${terminalOrHonor ? 'ヤオ九牌' : '中張牌'})';
        return FuItem(label: label, value: fu);
      case MeldType.shuntsu:
      case MeldType.pair:
        return null;
    }
  }

  FuItem? _waitFuItem(WaitType waitType, bool pinfu) {
    if (pinfu) return null;
    switch (waitType) {
      case WaitType.tanki:
        return const FuItem(label: '待ち(単騎待ち)', value: 2);
      case WaitType.kanchan:
        return const FuItem(label: '待ち(カンチャン)', value: 2);
      case WaitType.penchan:
        return const FuItem(label: '待ち(ペンチャン)', value: 2);
      case WaitType.ryanmen:
      case WaitType.shanpon:
        return null;
    }
  }

  static String _windLabel(Wind wind) {
    switch (wind) {
      case Wind.east:
        return '東';
      case Wind.south:
        return '南';
      case Wind.west:
        return '西';
      case Wind.north:
        return '北';
    }
  }

  static String _dragonLabel(int value) {
    switch (value) {
      case 5:
        return '白';
      case 6:
        return '發';
      case 7:
        return '中';
      default:
        return '役牌';
    }
  }

  static int _windValue(Wind wind) {
    switch (wind) {
      case Wind.east:
        return 1;
      case Wind.south:
        return 2;
      case Wind.west:
        return 3;
      case Wind.north:
        return 4;
    }
  }

  static Yaku _doubleWindYaku(Wind wind) {
    switch (wind) {
      case Wind.east:
        return YakuCatalog.doubleEast;
      case Wind.south:
        return YakuCatalog.doubleSouth;
      case Wind.west:
        return YakuCatalog.doubleWest;
      case Wind.north:
        return YakuCatalog.doubleNorth;
    }
  }

  static String _sequenceKey(List<Tile> tiles) {
    if (tiles.isEmpty) return '0:0';
    final suit = tiles.first.suit;
    final values = tiles.map((t) => t.value).toList()..sort();
    final start = values.first;
    final suitIndex = suit == Suit.m
        ? 0
        : suit == Suit.p
        ? 1
        : 2;
    return '$suitIndex:${start - 1}';
  }

  static bool _isPinfuCandidate(
    List<Meld> melds,
    WaitType waitType,
    bool closed,
    QuickContext ctx,
  ) {
    if (!closed) return false;
    if (waitType != WaitType.ryanmen) return false;
    Meld? pair;
    for (final m in melds) {
      if (m.type == MeldType.pair) {
        pair = m;
      } else if (m.type != MeldType.shuntsu) {
        return false;
      }
    }
    if (pair == null) return false;
    final tile = pair.tiles.first;
    if (tile.suit == Suit.z) {
      if (tile.value >= 5) return false;
      if (tile.value == _windValue(ctx.seatWind)) return false;
      if (tile.value == _windValue(ctx.roundWind)) return false;
    }
    return true;
  }
}
