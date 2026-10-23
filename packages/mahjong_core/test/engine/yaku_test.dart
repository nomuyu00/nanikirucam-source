import 'package:mahjong_core/mahjong_core.dart';
import 'package:test/test.dart';

void main() {
  group('yakuIdOf: HandAnalyzer の役名の対応表', () {
    // YakuCatalog.all() のうち variant の無い「役牌」以外はすべて名前で決まる。
    const byName = <String, YakuId>{
      '立直': YakuId.riichi,
      'ダブル立直': YakuId.doubleRiichi,
      '一発': YakuId.ippatsu,
      '門前清自摸和': YakuId.menzenTsumo,
      '断么九': YakuId.tanyao,
      '平和': YakuId.pinfu,
      '一盃口': YakuId.iipeikou,
      '二盃口': YakuId.ryanpeikou,
      '三色同順': YakuId.sanshoku,
      '一気通貫': YakuId.ittsu,
      '対々和': YakuId.toitoi,
      '三暗刻': YakuId.sanankou,
      '小三元': YakuId.shousangen,
      '混一色': YakuId.honitsu,
      '清一色': YakuId.chinitsu,
      '七対子': YakuId.chiitoitsu,
      '混全帯么九': YakuId.chanta,
      '純全帯么九': YakuId.junchan,
      '槍槓': YakuId.chankan,
      '嶺上開花': YakuId.rinshan,
      '海底摸月': YakuId.haitei,
      '河底撈魚': YakuId.houtei,
      '天和': YakuId.tenhou,
      '地和': YakuId.chiihou,
      '国士無双': YakuId.kokushi,
      '緑一色': YakuId.ryuuiisou,
      '大四喜': YakuId.daisuushii,
      '小四喜': YakuId.shousuushii,
      '四暗刻': YakuId.suuankou,
      '九蓮宝燈': YakuId.chuuren,
      '清老頭': YakuId.chinroutou,
      '字一色': YakuId.tsuuiisou,
      '大三元': YakuId.daisangen,
      '四槓子': YakuId.suukantsu,
      '三槓子': YakuId.sankantsu,
      '三色同刻': YakuId.sanshokuDoukou,
      '混老頭': YakuId.honroutou,
      'ダブ東': YakuId.doubleWind,
      'ダブ南': YakuId.doubleWind,
      'ダブ西': YakuId.doubleWind,
      'ダブ北': YakuId.doubleWind,
    };

    test('YakuCatalog.all() の役がすべて対応付く', () {
      for (final yaku in YakuCatalog.all()) {
        if (yaku.name == '役牌') continue; // variant 付きで別に確かめる
        expect(yakuIdOf(yaku), byName[yaku.name], reason: yaku.name);
        expect(byName.containsKey(yaku.name), isTrue, reason: yaku.name);
      }
      // 対応表の側にも余りが無い（YakuCatalog に無い名前を書いていない）
      final catalogNames = YakuCatalog.all().map((y) => y.name).toSet();
      expect(catalogNames.containsAll(byName.keys), isTrue);
    });

    test('役牌は variant で分ける（HandAnalyzer が付ける 5 種）', () {
      expect(yakuIdOf(YakuCatalog.yakuhaiFor('白')), YakuId.yakuhaiHaku);
      expect(yakuIdOf(YakuCatalog.yakuhaiFor('發')), YakuId.yakuhaiHatsu);
      expect(yakuIdOf(YakuCatalog.yakuhaiFor('中')), YakuId.yakuhaiChun);
      for (final w in ['東', '南', '西', '北']) {
        expect(
          yakuIdOf(YakuCatalog.yakuhaiFor('自風 $w')),
          YakuId.yakuhaiSeatWind,
        );
        expect(
          yakuIdOf(YakuCatalog.yakuhaiFor('場風 $w')),
          YakuId.yakuhaiRoundWind,
        );
      }
      // variant の無い役牌（HandAnalyzer は返さない）は対応なし
      expect(yakuIdOf(YakuCatalog.yakuhai), isNull);
    });

    test('ダブル役満・人和・ドラ類', () {
      Yaku named(String name) => Yaku(name: name, hanClosed: 1, hanOpen: 1);
      expect(
        yakuIdOf(RulesetSupport.doubleYakuman('国士無双十三面待ち')),
        YakuId.kokushi13,
      );
      expect(
        yakuIdOf(RulesetSupport.doubleYakuman('四暗刻単騎')),
        YakuId.suuankouTanki,
      );
      expect(
        yakuIdOf(RulesetSupport.doubleYakuman('純正九蓮宝燈')),
        YakuId.junseiChuuren,
      );
      expect(yakuIdOf(RulesetSupport.doubleYakuman('大四喜')), YakuId.daisuushii);
      for (final v in RenhouValue.values) {
        expect(yakuIdOf(RulesetSupport.renhouYaku(v)), YakuId.renhou);
      }
      expect(yakuIdOf(named(YakuCatalog.doraName)), YakuId.dora);
      expect(yakuIdOf(named(YakuCatalog.redDoraName)), YakuId.akaDora);
      expect(yakuIdOf(named(YakuCatalog.uraDoraName)), YakuId.uraDora);
      expect(yakuIdOf(named(YakuCatalog.nukiDoraName)), YakuId.kitaDora);
      expect(yakuIdOf(named('存在しない役')), isNull);
    });

    test('HandAnalyzer が実際に返す役（役牌の variant 込み）が対応付く', () {
      final analyzer = HandAnalyzer();
      final ruleset = Rulesets.mLeague();
      final hands = <(String, String, QuickContext)>[
        // 中・場風（東）・自風（南）の刻子、三暗刻、混一色
        (
          '7z 7z 7z 1z 1z 1z 2z 2z 2z 2m 3m 4m 9m 9m',
          '4m',
          initialQuickContext,
        ),
        // ダブ東（親・東場）
        (
          '1z 1z 1z 2m 3m 4m 5p 6p 7p 3s 4s 5s 9m 9m',
          '4m',
          const QuickContext(),
        ),
        // 立直・一発・門前ツモ・平和・断么九・赤ドラ・ドラ
        (
          '2m 3m 4m 0p 6p 7p 3s 4s 5s 6s 7s 8s 5m 5m',
          '8s',
          initialQuickContext.copyWith(
            riichi: true,
            ippatsu: true,
            winType: WinType.tsumo,
            doraIndicators: 1,
          ),
        ),
      ];
      for (final (labels, win, ctx) in hands) {
        final ev = analyzer.evaluateBest(
          labels.split(' '),
          ctx,
          ruleset,
          winningLabel: win,
        )!;
        for (final y in ev.score.yaku) {
          expect(yakuIdOf(y), isNotNull, reason: '${y.name} ${y.variant}');
        }
      }
    });
  });

  test('日本語名は重複しない・役満とドラの分類', () {
    final names = YakuId.values.map((y) => y.jaName).toList();
    expect(names.toSet(), hasLength(names.length));
    expect(YakuId.kokushi.isYakuman, isTrue);
    expect(YakuId.suuankouTanki.isYakuman, isTrue);
    expect(YakuId.chinitsu.isYakuman, isFalse);
    expect(YakuId.akaDora.isDora, isTrue);
    expect(YakuId.riichi.isProspect, isFalse);
    expect(YakuId.menzenTsumo.isProspect, isFalse);
    expect(YakuId.akaDora.isProspect, isFalse);
    expect(YakuId.dora.isProspect, isTrue);
    expect(YakuId.tanyao.isProspect, isTrue);
  });

  test('YakuConfidence の並びは確定 → 濃厚 → 狙える → 消える', () {
    expect(YakuConfidence.values, [
      YakuConfidence.certain,
      YakuConfidence.likely,
      YakuConfidence.possible,
      YakuConfidence.lost,
    ]);
  });
}
