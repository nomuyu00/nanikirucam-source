import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 理由タグ（設計書 4.7、仕様 7.4）と役の名前を、画面に出す文にする。
///
/// エンジン（`explain.dart`）は [Reason] にタグと数字・牌・役だけを入れるので、文は
/// ここで組み立てる。日本語が主、英語は従。
class ReasonText extends FeatureStrings {
  const ReasonText(super.lang);

  // --- 牌・役の名前 --------------------------------------------------------

  /// 牌 id の名前（「1萬」「北」）。
  String tile(int id) => tileDisplayName(tileLabelOfId(id), english: isEnglish);

  /// 牌 id の並びを「4索・7索」にする（重複は 1 つにまとめ、id の順）。
  String tiles(Iterable<int> ids) {
    final unique = ids.toSet().toList()..sort();
    return unique.map(tile).join(isEnglish ? ', ' : '・');
  }

  /// 役の表示名（よく使う呼び方。例: 断么九 → タンヤオ）。
  String yaku(YakuId id) {
    if (isEnglish) return _yakuEn[id] ?? id.name;
    return _yakuJa[id] ?? id.jaName;
  }

  /// 役の並びを「三色同順・一気通貫」にする。
  String yakuList(Iterable<YakuId> ids) =>
      ids.map(yaku).join(isEnglish ? ', ' : '・');

  /// 点数計算の役（`HandScore.yaku`）の表示名。
  String scoredYaku(Yaku y) {
    final id = yakuIdOf(y);
    if (id != null) return yaku(id);
    return y.name;
  }

  // --- 理由タグ ------------------------------------------------------------

  /// 理由タグの短い名前（履歴の弱点分析の一覧に使う）。
  String tagLabel(ReasonTag tag) => switch (tag) {
    ReasonTag.isolatedHonor => tr('孤立した字牌', 'Isolated honor'),
    ReasonTag.isolatedTerminal => tr('端の孤立牌', 'Isolated terminal'),
    ReasonTag.penchanFix => tr('辺張外し', 'Breaking an edge wait'),
    ReasonTag.kanchanVsRyanmen => tr('嵌張と両面の比較', 'Closed vs open wait'),
    ReasonTag.keepDora => tr('ドラを残す', 'Keeping dora'),
    ReasonTag.yakuLoss => tr('役が消える', 'Losing a yaku'),
    ReasonTag.sevenPairsRoute => tr('七対子の見込み', 'Seven pairs route'),
    ReasonTag.floatingMiddle => tr('中張牌の浮き牌', 'Floating middle tile'),
    ReasonTag.yakuGain => tr('役を残す', 'Keeping a yaku'),
    ReasonTag.riichiOnlyYaku => tr('リーチしか役がない', 'Riichi is the only yaku'),
  };

  /// [code]（`ReasonTagCode.code`）の短い名前。知らないコードはそのまま返す。
  String tagLabelOfCode(String code) {
    final tag = reasonTagFromCode(code);
    return tag == null ? code : tagLabel(tag);
  }

  /// 理由 1 つを文にする（設計書 4.7 の文言に数字・牌・役を入れる）。
  String sentence(Reason r) {
    switch (r.tag) {
      case ReasonTag.isolatedHonor:
        return tr(
          '孤立した字牌。受け入れに関係しない',
          'An isolated honor. It does not help your draws',
        );
      case ReasonTag.isolatedTerminal:
        return tr(
          '端の孤立牌。くっついても良形になりにくい',
          'An isolated terminal. Even with a neighbor it rarely becomes a good wait',
        );
      case ReasonTag.penchanFix:
        final n = r.count ?? 0;
        final shape = r.tileIds.isEmpty ? '' : '（${tiles(r.tileIds)}）';
        final shapeEn = r.tileIds.isEmpty ? '' : ' (${tiles(r.tileIds)})';
        return tr(
          '辺張$shapeを外すと受け入れが $n 枚増える',
          'Breaking the edge wait$shapeEn gives $n more tiles to draw',
        );
      case ReasonTag.kanchanVsRyanmen:
        final n = r.count ?? 0;
        final shape = r.tileIds.isEmpty ? '' : '（${tiles(r.tileIds)}）';
        final shapeEn = r.tileIds.isEmpty ? '' : ' (${tiles(r.tileIds)})';
        return tr(
          '両面を残し嵌張$shapeを外す。両面を崩すより受け入れが $n 枚多い',
          'Keep the open wait and break the closed wait$shapeEn: $n more tiles than breaking the open wait',
        );
      case ReasonTag.keepDora:
        final n = r.count;
        final lost = n == null || n <= 0 ? '' : '（ドラが $n 枚減る）';
        final lostEn = n == null || n <= 0 ? '' : ' ($n fewer dora)';
        return tr(
          'ドラを切る打牌。ドラを残す方が打点が高い$lost',
          'This discards a dora. Keeping dora scores more$lostEn',
        );
      case ReasonTag.yakuLoss:
        return tr(
          'この打牌だと${yakuList(r.yaku)}がなくなる',
          'This discard loses ${yakuList(r.yaku)}',
        );
      case ReasonTag.sevenPairsRoute:
        final n = r.count;
        final pairs = n == null ? '' : '対子が $n 組。';
        final pairsEn = n == null ? '' : '$n pairs. ';
        return tr('$pairs七対子も見える', '${pairsEn}Seven pairs is also possible');
      case ReasonTag.floatingMiddle:
        final kept = r.tileIds.isEmpty ? '' : '（${tiles(r.tileIds)}）';
        final keptEn = r.tileIds.isEmpty ? '' : ' (${tiles(r.tileIds)})';
        return tr(
          '中張牌の浮き牌$keptを残す。くっつきで両面になる',
          'Keep the floating middle tile$keptEn. It can grow into an open wait',
        );
      case ReasonTag.yakuGain:
        return tr(
          '${yakuList(r.yaku)}を残す',
          'Keeps ${yakuList(r.yaku)} alive',
        );
      case ReasonTag.riichiOnlyYaku:
        return tr(
          'リーチしか役がない（ダマではロンであがれない）',
          'Riichi is the only yaku (no ron without riichi)',
        );
    }
  }

  /// 候補の「理由」1 行（仕様 4.6 の「理由: 端の孤立牌。…」）。
  ///
  /// 選ぶ理由のタグ（注意点でないもの）を優先し、無ければ注意点のタグ。速さの 1 位で
  /// ない候補には「1萬より受け入れが 4 枚少ない」などの比較を足す。タグが 1 つも
  /// 無ければ比較だけ（速さの 1 位なら「受け入れが最も多い」）。
  String oneLine(DiscardCandidate c, List<DiscardCandidate> all) {
    final primary =
        c.reasons.where((r) => !r.tag.isCaution).firstOrNull ??
        c.reasons.firstOrNull;
    final parts = <String>[
      if (primary != null) sentence(primary),
      ?comparison(c, all, standalone: primary == null),
    ];
    if (parts.isEmpty) return '';
    return parts.join(isEnglish ? '. ' : '。');
  }

  /// 速さの 1 位との比較（「1萬より受け入れが 4 枚少ない」）。比べる相手が無い・
  /// 差が無いときは null（[standalone] なら「受け入れが最も多い」）。
  String? comparison(
    DiscardCandidate c,
    List<DiscardCandidate> all, {
    bool standalone = false,
  }) {
    final best = all
        .where((x) => x.rankByAxis[StrategyAxis.speed] == 1)
        .firstOrNull;
    if (best == null) return null;
    if (c.rankByAxis[StrategyAxis.speed] == 1) {
      return standalone
          ? tr('受け入れが最も多い', 'The most tiles to draw')
          : null;
    }
    if (c.shantenAfter > best.shantenAfter) {
      return tr(
        'シャンテン数が 1 つ戻る（${tile(best.discardId)}なら戻らない）',
        'Goes back one step (${tile(best.discardId)} does not)',
      );
    }
    final diff = best.ukeire.total - c.ukeire.total;
    if (diff <= 0) {
      return standalone
          ? tr('受け入れは最も多い候補と同じ', 'As many tiles to draw as the best')
          : null;
    }
    return tr(
      '${tile(best.discardId)}より受け入れが $diff 枚少ない',
      '$diff fewer tiles to draw than ${tile(best.discardId)}',
    );
  }
}

const Map<YakuId, String> _yakuJa = {
  YakuId.kokushi13: '国士無双十三面',
  YakuId.junchan: '純チャン',
  YakuId.chanta: 'チャンタ',
  YakuId.doubleWind: 'ダブ風',
  YakuId.yakuhaiHaku: '役牌（白）',
  YakuId.yakuhaiHatsu: '役牌（發）',
  YakuId.yakuhaiChun: '役牌（中）',
  YakuId.yakuhaiSeatWind: '役牌（自風）',
  YakuId.yakuhaiRoundWind: '役牌（場風）',
  YakuId.tanyao: 'タンヤオ',
  YakuId.riichi: 'リーチ',
  YakuId.doubleRiichi: 'ダブルリーチ',
  YakuId.menzenTsumo: '門前ツモ',
};

const Map<YakuId, String> _yakuEn = {
  YakuId.kokushi: 'Thirteen orphans',
  YakuId.kokushi13: 'Thirteen orphans (13-sided)',
  YakuId.suuankou: 'Four concealed triplets',
  YakuId.suuankouTanki: 'Four concealed triplets (single wait)',
  YakuId.daisangen: 'Big three dragons',
  YakuId.shousuushii: 'Little four winds',
  YakuId.daisuushii: 'Big four winds',
  YakuId.tsuuiisou: 'All honors',
  YakuId.ryuuiisou: 'All green',
  YakuId.chinroutou: 'All terminals',
  YakuId.chuuren: 'Nine gates',
  YakuId.junseiChuuren: 'Pure nine gates',
  YakuId.suukantsu: 'Four kans',
  YakuId.tenhou: 'Blessing of heaven',
  YakuId.chiihou: 'Blessing of earth',
  YakuId.chinitsu: 'Full flush',
  YakuId.honitsu: 'Half flush',
  YakuId.junchan: 'Pure outside hand',
  YakuId.ryanpeikou: 'Twice pure double sequence',
  YakuId.chanta: 'Outside hand',
  YakuId.sanshoku: 'Mixed triple sequence',
  YakuId.ittsu: 'Pure straight',
  YakuId.toitoi: 'All triplets',
  YakuId.sanankou: 'Three concealed triplets',
  YakuId.shousangen: 'Little three dragons',
  YakuId.sanshokuDoukou: 'Triple triplets',
  YakuId.sankantsu: 'Three kans',
  YakuId.honroutou: 'All terminals and honors',
  YakuId.chiitoitsu: 'Seven pairs',
  YakuId.doubleWind: 'Double wind',
  YakuId.yakuhaiHaku: 'Dragon (white)',
  YakuId.yakuhaiHatsu: 'Dragon (green)',
  YakuId.yakuhaiChun: 'Dragon (red)',
  YakuId.yakuhaiSeatWind: 'Seat wind',
  YakuId.yakuhaiRoundWind: 'Round wind',
  YakuId.tanyao: 'All simples',
  YakuId.pinfu: 'Pinfu',
  YakuId.iipeikou: 'Pure double sequence',
  YakuId.riichi: 'Riichi',
  YakuId.doubleRiichi: 'Double riichi',
  YakuId.ippatsu: 'Ippatsu',
  YakuId.menzenTsumo: 'Self-draw',
  YakuId.haitei: 'Last tile draw',
  YakuId.houtei: 'Last tile discard',
  YakuId.rinshan: 'After a kan',
  YakuId.chankan: 'Robbing a kan',
  YakuId.renhou: 'Blessing of man',
  YakuId.dora: 'Dora',
  YakuId.akaDora: 'Red five',
  YakuId.uraDora: 'Ura dora',
  YakuId.kitaDora: 'North dora',
};
