import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';

void main() {
  group('設定のルールが解析に効く', () {
    // チー 234p ＋ 345m 678s 456s 6m（6m 単騎）。役は断么九だけ。
    final openTanyaoOnly = HandInput(
      tiles: const [
        '3m', '4m', '5m', '6s', '7s', '8s', '4s', '5s', '6s', '6m', //
      ],
      melds: [
        MeldInput(kind: MeldKind.chi, tiles: const ['2p', '3p', '4p']),
      ],
    );

    test('喰いタンありなら役あり、なしなら役なしのテンパイ', () async {
      final on = AnalysisService(
        ruleset: rulesetFromSettings(redFives: true, openTanyao: true),
      );
      final off = AnalysisService(
        ruleset: rulesetFromSettings(redFives: true, openTanyao: false),
      );
      final withKuitan = await on.analyze(openTanyaoOnly, deep: false);
      final withoutKuitan = await off.analyze(openTanyaoOnly, deep: false);
      expect(withKuitan.thirteen!.shanten.shanten, 0);
      expect(withKuitan.thirteen!.hasYaku, isTrue);
      expect(withoutKuitan.thirteen!.hasYaku, isFalse);
    });

    test('赤ドラなしなら赤 5 を数えない（ツモ和了の点数が下がる）', () async {
      // 123m 456p 789s 345s 5m 0m（赤 5 萬）。最後の牌をツモ。
      final hand = HandInput(
        tiles: const [
          '1m', '2m', '3m', '4p', '5p', '6p', '7s', '8s', '9s', //
          '3s', '4s', '5s', '5m', '0m',
        ],
        tsumoIndex: 13,
      );
      final red = AnalysisService(
        ruleset: rulesetFromSettings(redFives: true, openTanyao: true),
      );
      final noRed = AnalysisService(
        ruleset: rulesetFromSettings(redFives: false, openTanyao: true),
      );
      final withRed = await red.analyze(hand, deep: false);
      final withoutRed = await noRed.analyze(hand, deep: false);
      expect(withRed.winPoints, isNotNull);
      expect(withoutRed.winPoints, isNotNull);
      expect(withRed.winPoints!, greaterThan(withoutRed.winPoints!));
    });
  });
}
