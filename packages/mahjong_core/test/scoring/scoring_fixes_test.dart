// 流用元: reference/agari_cam/test/scoring_fixes_test.dart（2026-10-21 時点）
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

  HandScore best(
    String labels,
    String winning, {
    QuickContext context = childRon,
    Ruleset? rules,
    WaitType? manualWait,
  }) {
    final evaluation = analyzer.evaluateBest(
      labels.split(' '),
      context,
      rules ?? ruleset,
      winningLabel: winning,
      manualWait: manualWait,
    );
    expect(evaluation, isNotNull);
    return evaluation!.score;
  }

  ScoreResult points(
    HandScore score, {
    bool dealer = false,
    bool tsumo = false,
  }) {
    return ScoringEngine(ruleset).scoreByHanFu(
      han: score.han,
      fu: score.fu == 0 ? 20 : score.fu,
      ctx: WinContext(oya: dealer, tsumo: tsumo),
      yaku: score.yaku,
    );
  }

  Iterable<String> names(HandScore score) => score.yaku.map((y) => y.name);

  group('Winning tile that fits several groups', () {
    const hand3455 = '1m 2m 3m 4p 5p 6p 7s 8s 9s 3s 4s 5s 5s 5s';

    test('3455s ron on 5s is read as ryanmen: riichi pinfu 2000', () {
      final score = best(
        hand3455,
        '5s',
        context: childRon.copyWith(riichi: true),
      );
      expect(score.waitType, WaitType.ryanmen);
      expect(names(score), containsAll(['立直', '平和']));
      expect(score.han, 2);
      expect(score.fu, 30);
      expect(points(score).payout.koRon, 2000);
    });

    test('3455s tsumo on 5s keeps pinfu: 700/1300', () {
      final score = best(
        hand3455,
        '5s',
        context: childRon.copyWith(riichi: true, winType: WinType.tsumo),
      );
      expect(score.han, 3);
      expect(score.fu, 20);
      expect(points(score, tsumo: true).payout.koTsumo, (700, 1300));
    });

    test('4566p ron on 6p is read as ryanmen', () {
      final score = best(
        '1m 2m 3m 7m 8m 9m 2s 3s 4s 4p 5p 6p 6p 6p',
        '6p',
        context: childRon.copyWith(riichi: true),
      );
      expect(score.waitType, WaitType.ryanmen);
      expect(names(score), contains('平和'));
    });

    test('A tanki reading is still available as a manual wait', () {
      final score = best(hand3455, '5s', manualWait: WaitType.tanki);
      expect(score.waitType, WaitType.tanki);
      expect(names(score), isNot(contains('平和')));
    });

    test('possibleWaits lists only the readings the hand allows', () {
      expect(analyzer.possibleWaits(hand3455.split(' '), '5s'), {
        WaitType.ryanmen,
        WaitType.tanki,
      });
      expect(
        analyzer.possibleWaits(
          '1m 2m 3m 4p 5p 6p 7s 8s 9s 3s 4s 5s 9p 9p'.split(' '),
          '4s',
        ),
        {WaitType.kanchan},
      );
    });
  });

  group('Ron only opens the triplet the winning tile completed', () {
    const hand = '4m 4m 4m 4m 5m 6m 7p 7p 7p 9s 9s 9s 9p 9p';

    test('444m + 456m ron on 4m keeps sanankou: 6400', () {
      final score = best(hand, '4m', context: childRon.copyWith(riichi: true));
      expect(score.waitType, WaitType.ryanmen);
      expect(names(score), containsAll(['立直', '三暗刻']));
      expect(score.han, 3);
      expect(score.fu, 50);
      expect(points(score).payout.koRon, 6400);
    });

    test('A pure shanpon ron still counts the completed triplet as open', () {
      final score = best(
        '1m 2m 3m 5p 5p 5p 7s 7s 7s 9s 9s 9s 2p 2p',
        '5p',
        context: childRon.copyWith(riichi: true),
      );
      expect(score.waitType, WaitType.shanpon);
      expect(names(score), isNot(contains('三暗刻')));
      expect(
        score.fuBreakdown!.items,
        contains(const FuItem(label: '明刻(中張牌)', value: 2)),
      );
    });
  });

  test('Open tsumo does not list menzen tsumo', () {
    final score = best(
      '2m 3m 4m 5p 6p 7p 3s 4s 5s 6s 7s 8s 5m 5m',
      '8s',
      context: childRon.copyWith(openMelds: true, winType: WinType.tsumo),
    );
    expect(names(score), isNot(contains(YakuCatalog.tsumo.name)));
    expect(names(score), [YakuCatalog.tanyao.name]);
  });

  test('Thirteen dora are not a yakuman when kazoe is disabled', () {
    final engine = ScoringEngine(ruleset.copyWith(countedYakuman: false));
    final result = engine.scoreByHanFu(
      han: 14,
      fu: 30,
      ctx: const WinContext(oya: false, tsumo: false),
      yaku: const [
        YakuCatalog.riichi,
        Yaku(name: 'ドラ', hanClosed: 13, hanOpen: 13),
      ],
    );
    expect(result.analysis.basePoints, 6000);
  });

  test('Yakuhai names the tile that made it', () {
    final score = best(
      '7z 7z 7z 2m 3m 4m 5p 6p 7p 3s 4s 5s 1p 1p',
      '4m',
      context: childRon.copyWith(roundWind: Wind.east, seatWind: Wind.south),
    );
    final yakuhai = score.yaku.where((y) => y.name == '役牌').toList();
    expect(yakuhai.map((y) => y.variant), ['中']);
  });

  test('Seat and round wind yakuhai are distinguished', () {
    final score = best(
      '2z 2z 2z 1z 1z 1z 2m 3m 4m 5p 6p 7p 1p 1p',
      '4m',
      context: childRon.copyWith(roundWind: Wind.east, seatWind: Wind.south),
    );
    expect(
      score.yaku.where((y) => y.name == '役牌').map((y) => y.variant),
      unorderedEquals(['自風 南', '場風 東']),
    );
  });

  test('Dora are listed by kind', () {
    final score = best(
      '2m 3m 4m 0p 6p 7p 3s 4s 5s 6s 7s 8s 5m 5m',
      '8s',
      context: childRon.copyWith(
        riichi: true,
        doraIndicators: 1,
        uraDoraIndicators: 2,
      ),
    );
    final dora = {
      for (final y in score.yaku)
        if (YakuCatalog.isDora(y.name)) y.name: y.hanClosed,
    };
    expect(dora, {'ドラ': 1, '赤ドラ': 1, '裏ドラ': 2});
  });

  test('Renhou as mangan does not stack with other yaku', () {
    final rules = ruleset.copyWith(renhou: RenhouValue.mangan);
    final score = best(
      '2m 3m 4m 5p 6p 7p 3s 4s 5s 6s 7s 8s 5m 5m',
      '8s',
      context: childRon.copyWith(renhou: true),
      rules: rules,
    );
    expect(names(score), ['人和']);
    expect(score.han, 5);
  });

  test('Impossible situational yaku are ignored', () {
    final ctx = RulesetSupport.effectiveContext(
      childRon.copyWith(haitei: true, rinshan: true, tenho: true),
      ruleset,
    );
    expect(ctx.haitei, isFalse); // 海底はツモのみ
    expect(ctx.rinshan, isFalse); // 嶺上はツモのみ
    expect(ctx.tenho, isFalse);

    final noKan = best(
      '2m 3m 4m 5p 6p 7p 3s 4s 5s 6s 7s 8s 5m 5m',
      '8s',
      context: childRon.copyWith(winType: WinType.tsumo, rinshan: true),
    );
    expect(names(noKan), isNot(contains(YakuCatalog.rinshan.name)));
  });

  test('Double wind pair fu follows the ruleset', () {
    const hand = '2m 3m 4m 5p 6p 7p 3s 4s 5s 6s 7s 8s 1z 1z';
    const ctx = QuickContext(
      seatWind: Wind.east,
      roundWind: Wind.east,
      winType: WinType.ron,
    );
    final four = best(hand, '8s', context: ctx);
    final two = best(
      hand,
      '8s',
      context: ctx,
      rules: ruleset.copyWith(doubleWindPairFu: 2),
    );
    expect(
      four.fuBreakdown!.items,
      contains(const FuItem(label: '雀頭(連風牌 東)', value: 4)),
    );
    expect(
      two.fuBreakdown!.items,
      contains(const FuItem(label: '雀頭(連風牌 東)', value: 2)),
    );
  });

  test('North dora is only counted in three-player mode', () {
    final four = RulesetSupport.doraYaku(
      const QuickContext(nukiDora: 2),
      ruleset,
      labels: const [],
    );
    final three = RulesetSupport.doraYaku(
      const QuickContext(nukiDora: 2),
      ruleset.copyWith(mode: MahjongMode.threePlayer),
      labels: const [],
    );
    expect(four, isEmpty);
    expect(three.single.name, '北ドラ');
  });

  test('Ruleset survives a JSON round trip and ignores bad values', () {
    final custom = ruleset.copyWith(
      mode: MahjongMode.threePlayer,
      redFives: 4,
      kiriageMangan: true,
      renhou: RenhouValue.yakuman,
      doubleWindPairFu: 2,
    );
    final restored = Ruleset.fromJson(custom.toJson());
    expect(restored.toJson(), custom.toJson());
    final broken = Ruleset.fromJson({'mode': 'five', 'redFives': 'x'});
    expect(broken.toJson(), Rulesets.mLeague().toJson());
  });

  group('Quick context', () {
    test('seat wind decides dealer', () {
      expect(const QuickContext().withSeatWind(Wind.west).isDealer, isFalse);
      expect(
        initialQuickContext.withSeatWind(Wind.east).parentChild,
        ParentChild.parent,
      );
      final child = const QuickContext().withDealer(false);
      expect(child.seatWind, Wind.south);
    });

    test('next hand keeps winds and sticks, clears per-hand flags', () {
      const played = QuickContext(
        roundWind: Wind.south,
        seatWind: Wind.west,
        parentChild: ParentChild.child,
        winType: WinType.tsumo,
        riichi: true,
        ippatsu: true,
        doraIndicators: 3,
        openMelds: true,
        haitei: true,
        honba: 2,
        kyotaku: 1,
      );
      expect(
        played.nextHand(),
        const QuickContext(
          roundWind: Wind.south,
          seatWind: Wind.west,
          parentChild: ParentChild.child,
          honba: 2,
          kyotaku: 1,
        ),
      );
    });
  });

  test('Called triplets are open and break menzen', () {
    final tiles = '1m 1m 1m 5p 5p 5p 7s 7s 7s 2m 3m 4m 9p 9p'.split(' ');
    final evaluation = analyzer.evaluateBest(
      tiles,
      childRon,
      ruleset,
      winningLabel: '4m',
      openFlagsFor: (base) => [
        for (final group in base.labelGroups) group.join(' ') == '5p 5p 5p',
      ],
    )!;
    expect(evaluation.score.closed, isFalse);
    expect(evaluation.score.yaku.map((y) => y.name), isNot(contains('三暗刻')));
  });
}
