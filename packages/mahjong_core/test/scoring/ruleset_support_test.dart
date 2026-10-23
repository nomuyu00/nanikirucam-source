// 流用元: reference/agari_cam/test/ruleset_support_test.dart（2026-10-21 時点）
import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

void main() {
  test('Yakuman stacking follows the ruleset', () {
    final yaku = [
      YakuCatalog.daisangen,
      YakuCatalog.suuankou,
      const Yaku(name: 'ドラ', hanClosed: 3, hanOpen: 3),
    ];

    expect(
      RulesetSupport.totalHanForRuleset(
        yaku,
        open: false,
        ruleset: Rulesets.mLeague().copyWith(yakumanMultiple: true),
      ),
      26,
    );
    expect(
      RulesetSupport.totalHanForRuleset(
        yaku,
        open: false,
        ruleset: Rulesets.mLeague().copyWith(yakumanMultiple: false),
      ),
      13,
    );
  });
}
