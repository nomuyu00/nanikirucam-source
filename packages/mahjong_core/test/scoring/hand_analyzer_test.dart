// 流用元: reference/agari_cam/test/hand_analyzer_test.dart（2026-10-21 時点）
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

void main() {
  final analyzer = HandAnalyzer();
  final ruleset = Rulesets.mLeague();
  const baseContext = QuickContext(winType: WinType.ron);

  MaterializedHand materialize(ParsedHandPattern pattern, List<String> tiles) {
    final hand = pattern.materialize(tiles);
    expect(hand, isNotNull);
    return hand!;
  }

  test('Scores concealed toitoi hand', () {
    final tiles = [
      '1m',
      '1m',
      '1m',
      '2m',
      '2m',
      '2m',
      '3m',
      '3m',
      '3m',
      '4p',
      '4p',
      '4p',
      '5s',
      '5s',
    ];
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '4p',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '4p',
    );
    expect(score.isValid, isTrue);
    expect(score.waitType, WaitType.shanpon);
    expect(
      score.yaku.where((y) => y.name == YakuCatalog.toitoi.name).length,
      greaterThan(0),
    );
    expect(score.han, greaterThanOrEqualTo(2));
    expect(score.fuBreakdown, isNotNull);
    expect(score.fuBreakdown!.items.first.label, equals('基本符'));
    expect(score.fuBreakdown!.total, greaterThan(20));
  });

  test('Pinfu ron gives 30fu (menzen ron 10fu is applied)', () {
    final tiles = [
      '2m',
      '3m',
      '4m',
      '4p',
      '5p',
      '6p',
      '6s',
      '7s',
      '8s',
      '3s',
      '4s',
      '5s',
      '2p',
      '2p',
    ];
    // 和了牌を両面待ちにするため 4p でロン
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '4p',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '4p',
    );
    expect(score.isValid, isTrue);
    expect(score.fu, 30);
    // 内訳: 基本符20 + 門前ロン10, 待ち・雀頭は0（平和形）
    expect(
      score.fuBreakdown!.items.any((e) => e.label == '門前ロン' && e.value == 10),
      isTrue,
    );
  });

  test('Edge wait (penchan) is detected and adds 2 fu', () {
    final tiles = [
      '1m', '2m', '3m', // penchan on 3m
      '4p', '5p', '6p',
      '7s', '8s', '9s',
      '5m', '5m', '5m',
      '6p', '6p',
    ];
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '3m',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '3m',
    );
    expect(score.waitType, WaitType.penchan);
    expect(
      score.fuBreakdown!.items.any((e) => e.label.contains('待ち(ペンチャン)')),
      isTrue,
    );
  });

  test('Two-sided wait 1-2-3 on 1 is ryanmen (no penchan fu)', () {
    final tiles = [
      '1m', '2m', '3m', // winning on 1m should be ryanmen (2-3 wait 1)
      '4p', '5p', '6p',
      '7s', '8s', '9s',
      '5m', '5m', '5m',
      '6p', '6p',
    ];
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '1m',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '1m',
    );
    expect(score.waitType, WaitType.ryanmen);
    expect(
      score.fuBreakdown!.items.any((e) => e.label.contains('待ち(ペンチャン)')),
      isFalse,
    );
  });

  test('Scores seven pairs', () {
    final tiles = [
      '1m',
      '1m',
      '2m',
      '2m',
      '3p',
      '3p',
      '4p',
      '4p',
      '5s',
      '5s',
      '6s',
      '6s',
      '7z',
      '7z',
    ];
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '7z',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '7z',
    );
    expect(score.isValid, isTrue);
    expect(score.waitType, WaitType.tanki);
    expect(
      score.yaku.where((y) => y.name == YakuCatalog.chitoitsu.name).length,
      greaterThan(0),
    );
    expect(score.fu, 25);
    expect(score.fuBreakdown, isNotNull);
    expect(score.fuBreakdown!.total, 25);
    expect(
      score.fuBreakdown!.items.any((item) => item.label.contains('七対子')),
      isTrue,
    );
  });

  test('Detects kokushi musou', () {
    final tiles = [
      '1m',
      '9m',
      '1p',
      '9p',
      '1s',
      '9s',
      '1z',
      '2z',
      '3z',
      '4z',
      '5z',
      '6z',
      '7z',
      '1m',
    ];
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '1m',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '1m',
    );
    expect(score.isValid, isTrue);
    expect(score.waitType, WaitType.tanki);
    expect(
      score.yaku.where((y) => y.name == YakuCatalog.kokushi.name).length,
      greaterThan(0),
    );
    expect(score.han, greaterThanOrEqualTo(13));
  });

  test('Does not award ippatsu when the ruleset disables it', () {
    final tiles = [
      '2m',
      '3m',
      '4m',
      '4p',
      '5p',
      '6p',
      '6s',
      '7s',
      '8s',
      '3m',
      '4m',
      '5m',
      '7p',
      '7p',
    ];
    final noIppatsuRuleset = ruleset.copyWith(ippatsu: false);
    const ctx = QuickContext(winType: WinType.ron, riichi: true, ippatsu: true);
    final pattern = analyzer.selectBestPattern(
      tiles,
      ctx,
      noIppatsuRuleset,
      winningLabel: '4p',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      ctx,
      noIppatsuRuleset,
      winningLabel: '4p',
    );
    expect(score.yaku.any((y) => y.name == YakuCatalog.ippatsu.name), isFalse);
  });

  test('Counts red fives as dora automatically from tiles', () {
    final tiles = [
      '0m',
      '6m',
      '7m',
      '2p',
      '3p',
      '4p',
      '2s',
      '3s',
      '4s',
      '6s',
      '7s',
      '8s',
      '5p',
      '5p',
    ];
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      ruleset,
      winningLabel: '0m',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      ruleset,
      winningLabel: '0m',
    );
    final dora = score.yaku.firstWhere((y) => y.name == '赤ドラ');
    expect(dora.hanClosed, 1);
  });

  test('Applies renhou according to the ruleset', () {
    final tiles = [
      '2m',
      '3m',
      '4m',
      '4p',
      '5p',
      '6p',
      '6s',
      '7s',
      '8s',
      '3m',
      '4m',
      '5m',
      '7p',
      '7p',
    ];
    final renhouRuleset = ruleset.copyWith(renhou: RenhouValue.mangan);
    // 人和は子だけの役。
    const ctx = QuickContext(
      winType: WinType.ron,
      renhou: true,
      seatWind: Wind.south,
      parentChild: ParentChild.child,
    );
    final pattern = analyzer.selectBestPattern(
      tiles,
      ctx,
      renhouRuleset,
      winningLabel: '4p',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      ctx,
      renhouRuleset,
      winningLabel: '4p',
    );
    expect(score.yaku.any((y) => y.name == '人和'), isTrue);
    expect(score.han, greaterThanOrEqualTo(5));
  });

  test('Upgrades kokushi 13-sided wait to double yakuman when enabled', () {
    final tiles = [
      '1m',
      '9m',
      '1p',
      '9p',
      '1s',
      '9s',
      '1z',
      '2z',
      '3z',
      '4z',
      '5z',
      '6z',
      '7z',
      '1m',
    ];
    final doubleRuleset = ruleset.copyWith(doubleYakuman: true);
    final pattern = analyzer.selectBestPattern(
      tiles,
      baseContext,
      doubleRuleset,
      winningLabel: '1m',
    );
    expect(pattern, isNotNull);
    final hand = materialize(pattern!, tiles);
    final score = analyzer.scoreHand(
      hand,
      baseContext,
      doubleRuleset,
      winningLabel: '1m',
    );
    expect(score.yaku.any((y) => y.name == '国士無双十三面待ち'), isTrue);
    expect(score.han, 26);
  });
}
