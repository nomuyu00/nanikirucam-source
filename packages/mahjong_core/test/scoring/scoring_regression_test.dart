// 流用元: reference/agari_cam/test/scoring_regression_test.dart（2026-10-21 時点）
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

void main() {
  final analyzer = HandAnalyzer();
  final ruleset = Rulesets.mLeague();
  const childRon = QuickContext(
    seatWind: Wind.south,
    parentChild: ParentChild.child,
    winType: WinType.ron,
  );

  HandScore scoreTiles(
    String labels, {
    required String winningLabel,
    QuickContext context = childRon,
    String? openMeld,
  }) {
    final tiles = labels.split(' ');
    final pattern = analyzer.selectBestPattern(
      tiles,
      context,
      ruleset,
      winningLabel: winningLabel,
    );
    expect(pattern, isNotNull);
    final baseHand = pattern!.materialize(tiles)!;
    final openFlags = List<bool>.filled(baseHand.melds.length, false);
    if (openMeld != null) {
      final index = baseHand.labelGroups.indexWhere(
        (group) => group.join(' ') == openMeld,
      );
      expect(index, greaterThanOrEqualTo(0));
      openFlags[index] = true;
    }
    return analyzer.scoreHand(
      pattern.materialize(tiles, openFlags: openFlags)!,
      context,
      ruleset,
      winningLabel: winningLabel,
    );
  }

  int childRonPoints(HandScore score) {
    return ScoringEngine(ruleset)
        .scoreByHanFu(
          han: score.han,
          fu: score.fu,
          ctx: const WinContext(oya: false, tsumo: false),
          yaku: score.yaku,
        )
        .payout
        .koRon;
  }

  group('Seven pairs requires seven distinct tile kinds', () {
    for (final quadruple in ['1m 1m 1m 1m', '0m 5m 5m 5m']) {
      test('Rejects four identical tiles: $quadruple', () {
        final tiles = '$quadruple 2p 2p 4p 4p 6s 6s 8s 8s 1z 1z'.split(' ');
        expect(HandParser().parse(tiles), isEmpty);
        expect(
          analyzer.selectBestPattern(
            tiles,
            childRon,
            ruleset,
            winningLabel: '1z',
          ),
          isNull,
        );
      });
    }

    test('A red five and a normal five form one valid pair', () {
      final score = scoreTiles(
        '0m 5m 2p 2p 4p 4p 6s 6s 8s 8s 1z 1z 2z 2z',
        winningLabel: '2z',
      );
      expect(score.isValid, isTrue);
      expect(score.hand.sevenPairs, isTrue);
      expect(
        score.yaku.map((yaku) => yaku.name),
        contains(YakuCatalog.chitoitsu.name),
      );
      expect(score.fu, 25);
      expect(score.han, 3); // Seven pairs and one red dora.
    });
  });

  group('Chanta yaku do not stack with their stronger forms', () {
    const junchanTiles = '1m 2m 3m 7m 8m 9m 1p 2p 3p 7s 8s 9s 9p 9p';

    test('Closed junchan and pinfu score 4 han 30 fu', () {
      final score = scoreTiles(junchanTiles, winningLabel: '1m');
      expect(
        score.yaku.map((yaku) => yaku.name),
        unorderedEquals([YakuCatalog.junchan.name, YakuCatalog.pinfu.name]),
      );
      expect(score.han, 4);
      expect(score.fu, 30);
      expect(childRonPoints(score), 7700);
    });

    test('Open junchan scores 2 han without chanta or pinfu', () {
      final score = scoreTiles(
        junchanTiles,
        winningLabel: '1m',
        context: childRon.copyWith(openMelds: true),
        openMeld: '1p 2p 3p',
      );
      expect(score.yaku.map((yaku) => yaku.name), [YakuCatalog.junchan.name]);
      expect(score.han, 2);
      expect(childRonPoints(score), 2000);
    });

    test('Chanta with an honor pair remains valid', () {
      final score = scoreTiles(
        '1m 2m 3m 7m 8m 9m 1p 2p 3p 7s 8s 9s 1z 1z',
        winningLabel: '1m',
      );
      expect(score.yaku.map((yaku) => yaku.name), [YakuCatalog.chanta.name]);
      expect(score.han, 2);
      expect(score.fu, 40);
      expect(childRonPoints(score), 2600);
    });

    test('Honroutou triplets do not also receive chanta', () {
      final score = scoreTiles(
        '1m 1m 1m 9m 9m 9m 1p 1p 1p 9s 9s 9s 2z 2z',
        winningLabel: '9s',
      );
      expect(
        score.yaku.map((yaku) => yaku.name),
        unorderedEquals([
          YakuCatalog.toitoi.name,
          YakuCatalog.sanankou.name,
          YakuCatalog.honroutou.name,
        ]),
      );
      expect(score.han, 6);
    });
  });

  group('All-sequence hand fu', () {
    const tiles = '2m 3m 4m 3p 4p 5p 4s 5s 6s 6m 7m 8m 2p 2p';

    test('Open ryanmen ron uses 30 fu and pays 1000 points', () {
      final score = scoreTiles(
        tiles,
        winningLabel: '4m',
        context: childRon.copyWith(openMelds: true),
        openMeld: '6m 7m 8m',
      );
      expect(score.han, 1);
      expect(score.fu, 30);
      expect(childRonPoints(score), 1000);
      expect(
        score.fuBreakdown!.items,
        contains(const FuItem(label: '副露平和形ロン', value: 10)),
      );
      expect(
        score.fuBreakdown!.items.fold<int>(0, (sum, item) => sum + item.value),
        score.fu,
      );
    });

    test('Open tsumo still uses the tsumo fu and normal rounding', () {
      final score = scoreTiles(
        tiles,
        winningLabel: '4m',
        context: childRon.copyWith(openMelds: true, winType: WinType.tsumo),
        openMeld: '6m 7m 8m',
      );
      expect(score.fu, 30);
      expect(
        score.fuBreakdown!.items,
        contains(const FuItem(label: 'ツモ', value: 2)),
      );
      expect(
        score.fuBreakdown!.items.any((item) => item.label == '副露平和形ロン'),
        isFalse,
      );
    });

    test('Closed pinfu tsumo remains 20 fu', () {
      final score = scoreTiles(
        tiles,
        winningLabel: '4m',
        context: childRon.copyWith(winType: WinType.tsumo),
      );
      expect(score.han, 3);
      expect(score.fu, 20);
      expect(score.fuBreakdown!.items, [const FuItem(label: '基本符', value: 20)]);
    });
  });
}
