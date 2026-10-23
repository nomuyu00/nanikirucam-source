import 'package:equatable/equatable.dart';
import 'package:mahjong_core/src/engine/yaku.dart';

/// 候補の理由タグ（設計書 4.7、仕様 7.4）。履歴に保存し、弱点分析で集計する。
///
/// 付け方は `explain.dart`（`explainCandidates`）。日本語の文はエンジンでは作らず、
/// UI が [Reason] の数字・牌・役から組み立てる。保存には [ReasonTagCode.code]
/// （仕様 7.4 の snake_case）を使う（enum の添字は並べ替えで変わるので保存しない）。
///
/// [isCaution] が true のタグ（[keepDora]・[yakuLoss]・[riichiOnlyYaku]）は
/// 「この打牌の注意点」、それ以外は「この打牌を選ぶ理由」。
enum ReasonTag {
  /// 孤立した字牌で役牌でもない（「孤立した字牌。受け入れに関係しない」）。
  isolatedHonor,

  /// 孤立した 1・9（「端の孤立牌。くっついても良形になりにくい」）。
  isolatedTerminal,

  /// 辺張を外すと受け入れが増える（「辺張を外すと受け入れが n 枚増える」）。
  /// [Reason.count] = n、[Reason.tileIds] = 辺張の 2 枚。
  penchanFix,

  /// 両面を残し嵌張を外す。[Reason.count] = 両面を崩す打牌より多い受け入れ枚数、
  /// [Reason.tileIds] = 嵌張の 2 枚。
  kanchanVsRyanmen,

  /// ドラを切る候補（「ドラを残す方が打点が高い」）。[Reason.count] = 減るドラの枚数。
  keepDora,

  /// この打牌で、他の候補では確定・濃厚の役が成立しなくなる。[Reason.yaku] = その役。
  yakuLoss,

  /// 対子が 4 組以上（「七対子も見える」）。[Reason.count] = 打牌後の対子の数、
  /// [Reason.tileIds] = 対子の牌。
  sevenPairsRoute,

  /// 浮き牌の比較で、中張牌の浮き牌を残す（「中張牌の浮き牌はくっつきで両面になる」）。
  /// [Reason.tileIds] = 残す浮き牌。
  floatingMiddle,

  /// 最速の候補では成立しない役を残す（「三色を残す」など）。[Reason.yaku] = その役。
  /// 設計書 4.7 の 8 個に追加（仕様 7.4 の `yaku_gain`。`sanshoku_keep`・`ittsu_keep` も
  /// これで表す）。
  yakuGain,

  /// 門前テンパイで、ダマで和了できる役が無い（リーチしか役がない）。
  /// 設計書 4.7 の 8 個に追加（仕様 7.4 の `riichi_only_yaku`）。
  riichiOnlyYaku,
}

extension ReasonTagCode on ReasonTag {
  /// 保存・集計に使う名前（仕様 7.4 の snake_case）。
  String get code => switch (this) {
    ReasonTag.isolatedHonor => 'isolated_honor',
    ReasonTag.isolatedTerminal => 'isolated_terminal',
    ReasonTag.penchanFix => 'penchan_fix',
    ReasonTag.kanchanVsRyanmen => 'kanchan_vs_ryanmen',
    ReasonTag.keepDora => 'keep_dora',
    ReasonTag.yakuLoss => 'yaku_loss',
    ReasonTag.sevenPairsRoute => 'seven_pairs_route',
    ReasonTag.floatingMiddle => 'floating_middle',
    ReasonTag.yakuGain => 'yaku_gain',
    ReasonTag.riichiOnlyYaku => 'riichi_only_yaku',
  };

  /// 「この打牌の注意点」のタグか（false は「この打牌を選ぶ理由」）。
  bool get isCaution =>
      this == ReasonTag.keepDora ||
      this == ReasonTag.yakuLoss ||
      this == ReasonTag.riichiOnlyYaku;
}

/// [ReasonTagCode.code] から [ReasonTag] に戻す。知らない名前は null。
ReasonTag? reasonTagFromCode(String code) {
  for (final tag in ReasonTag.values) {
    if (tag.code == code) return tag;
  }
  return null;
}

/// 候補 1 つの理由 1 つ（タグと、UI が文を作るための数字・牌・役）。
class Reason extends Equatable {
  final ReasonTag tag;

  /// タグごとの数字（[ReasonTag] の説明を参照）。無ければ null。
  final int? count;

  /// 関係する牌 id（昇順、重複あり）。
  final List<int> tileIds;

  /// 関係する役（[ReasonTag.yakuLoss]・[ReasonTag.yakuGain]）。[YakuId] の順。
  final List<YakuId> yaku;

  Reason(
    this.tag, {
    this.count,
    List<int> tileIds = const [],
    List<YakuId> yaku = const [],
  }) : tileIds = List.unmodifiable(tileIds),
       yaku = List.unmodifiable(yaku);

  @override
  List<Object?> get props => [tag, count, tileIds, yaku];

  @override
  String toString() {
    final parts = <String>[tag.code];
    if (count != null) parts.add('$count');
    if (tileIds.isNotEmpty) parts.add(tileIds.join(','));
    if (yaku.isNotEmpty) parts.add(yaku.map((y) => y.name).join(','));
    return 'Reason(${parts.join(' ')})';
  }
}
