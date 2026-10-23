import 'package:flutter_test/flutter_test.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/result/result_logic.dart';

import 'screens_harness.dart';

const ja = ReasonText(AppLang.ja);
const en = ReasonText(AppLang.en);

int id(String label) => tileIdFromLabel(label);

void main() {
  group('理由タグの文（設計書 4.7、数字入り）', () {
    test('タグごとの日本語', () {
      expect(
        ja.sentence(Reason(ReasonTag.isolatedHonor)),
        '孤立した字牌。受け入れに関係しない',
      );
      expect(
        ja.sentence(Reason(ReasonTag.isolatedTerminal)),
        '端の孤立牌。くっついても良形になりにくい',
      );
      expect(
        ja.sentence(
          Reason(ReasonTag.penchanFix, count: 4, tileIds: [id('1m'), id('2m')]),
        ),
        '辺張（1萬・2萬）を外すと受け入れが 4 枚増える',
      );
      expect(
        ja.sentence(
          Reason(
            ReasonTag.kanchanVsRyanmen,
            count: 2,
            tileIds: [id('3p'), id('5p')],
          ),
        ),
        '両面を残し嵌張（3筒・5筒）を外す。両面を崩すより受け入れが 2 枚多い',
      );
      expect(
        ja.sentence(Reason(ReasonTag.keepDora, count: 1)),
        'ドラを切る打牌。ドラを残す方が打点が高い（ドラが 1 枚減る）',
      );
      expect(
        ja.sentence(Reason(ReasonTag.yakuLoss, yaku: [YakuId.tanyao])),
        'この打牌だとタンヤオがなくなる',
      );
      expect(
        ja.sentence(Reason(ReasonTag.sevenPairsRoute, count: 5)),
        '対子が 5 組。七対子も見える',
      );
      expect(
        ja.sentence(Reason(ReasonTag.floatingMiddle, tileIds: [id('5s')])),
        '中張牌の浮き牌（5索）を残す。くっつきで両面になる',
      );
      expect(
        ja.sentence(
          Reason(ReasonTag.yakuGain, yaku: [YakuId.sanshoku, YakuId.ittsu]),
        ),
        '三色同順・一気通貫を残す',
      );
      expect(
        ja.sentence(Reason(ReasonTag.riichiOnlyYaku)),
        'リーチしか役がない（ダマではロンであがれない）',
      );
    });

    test('すべてのタグに日本語と英語の文と短い名前がある', () {
      for (final tag in ReasonTag.values) {
        final r = Reason(tag, count: 2, tileIds: [id('1m')], yaku: [YakuId.pinfu]);
        expect(ja.sentence(r), isNotEmpty);
        expect(en.sentence(r), isNotEmpty);
        expect(ja.tagLabel(tag), isNotEmpty);
        expect(ja.tagLabelOfCode(tag.code), ja.tagLabel(tag));
      }
      expect(ja.tagLabelOfCode('unknown_tag'), 'unknown_tag');
    });

    test('1 行: 選ぶ理由 ＋ 速さ 1 位との比較（仕様 4.6 の「理由」）', () {
      final report = analyzeNow(splitHand, deep: true);
      final c8p = candidateOf(report, id('8p'))!;
      // 打8筒は場風（東）を残す代わりにシャンテン数が戻る。
      expect(c8p.reasonTags, contains(ReasonTag.yakuGain));
      expect(
        ja.oneLine(c8p, report.candidates),
        '役牌（場風）を残す。シャンテン数が 1 つ戻る（東なら戻らない）',
      );
      // 速さ 1 位で理由タグの無い候補は「受け入れが最も多い」。
      final c1z = candidateOf(report, id('1z'))!;
      expect(c1z.reasons, isEmpty);
      expect(ja.oneLine(c1z, report.candidates), '受け入れが最も多い');
    });

    test('同じシャンテン数なら受け入れの差を書く', () {
      final report = analyzeNow(oneChoiceHand);
      final best = candidateOf(report, id('9s'))!;
      final other = orderedCandidates(report, StrategyAxis.speed).firstWhere(
        (c) =>
            c.shantenAfter == best.shantenAfter &&
            c.ukeire.total < best.ukeire.total,
      );
      final diff = best.ukeire.total - other.ukeire.total;
      expect(
        ja.comparison(other, report.candidates),
        '9索より受け入れが $diff 枚少ない',
      );
    });

    test('役の表示名（よく使う呼び方）', () {
      expect(ja.yaku(YakuId.tanyao), 'タンヤオ');
      expect(ja.yaku(YakuId.pinfu), '平和');
      expect(ja.yaku(YakuId.yakuhaiChun), '役牌（中）');
      expect(ja.yaku(YakuId.sanshoku), '三色同順');
      expect(en.yaku(YakuId.tanyao), 'All simples');
      for (final y in YakuId.values) {
        expect(ja.yaku(y), isNotEmpty);
        expect(en.yaku(y), isNotEmpty);
      }
    });
  });

  group('表示の決まり', () {
    const s = ResultStrings(AppLang.ja);

    test('点数の 3 桁区切りとレンジ', () {
      expect(formatPoints(1000), '1,000');
      expect(formatPoints(12000), '12,000');
      expect(formatPoints(800), '800');
      expect(
        formatRange(const PointRange(min: 2000, median: 3900, max: 7700), s),
        '2,000〜7,700（中央 3,900）',
      );
      expect(
        formatRange(
          const PointRange(min: 1000, median: 2000, max: 8000, isEstimate: true),
          s,
        ),
        '目安 1,000〜8,000（中央 2,000）',
      );
      expect(formatRange(PointRange.zero, s), '—');
    });

    test('無料の打点の目安（子は 2,600 以下が安い、満貫以上が高い）', () {
      expect(pointsLevelOf(2600, dealer: false), PointsLevel.cheap);
      expect(pointsLevelOf(3900, dealer: false), PointsLevel.normal);
      expect(pointsLevelOf(8000, dealer: false), PointsLevel.high);
      expect(pointsLevelOf(3900, dealer: true), PointsLevel.cheap);
      expect(pointsLevelOf(12000, dealer: true), PointsLevel.high);
    });

    test('役は最大 3 件。消える役は 1 枠残し、リーチは後ろ', () {
      final report = analyzeNow(splitHand, deep: true);
      final c1z = candidateOf(report, id('1z'))!;
      final picked = pickYaku(c1z);
      expect(picked, hasLength(3));
      expect(picked.last.confidence, YakuConfidence.lost);
      expect(picked.last.yaku, YakuId.yakuhaiRoundWind);
      expect(picked.map((y) => y.yaku), isNot(contains(YakuId.riichi)));
    });

    test('3 軸の判定とクイズの正誤', () {
      final report = analyzeNow(splitHand);
      expect(agreementOf(report), AnswerAgreement.split);
      expect(agreementOf(analyzeNow(oneChoiceHand)), AnswerAgreement.single);
      expect(agreementOf(analyzeNow(closedYakuHand)), AnswerAgreement.none);
      expect(bestAxesOf(report, id('8p')), [StrategyAxis.points]);
      final v = judgeChoice(report, id('1z'), StrategyAxis.speed);
      expect(v.correct, isTrue);
      expect(v.correctAxisCode, 'speed');
      final miss = judgeChoice(report, id('2m'), StrategyAxis.speed);
      expect(miss.correct, isFalse);
      expect(miss.correctAxisCode, 'none');
    });
  });
}
