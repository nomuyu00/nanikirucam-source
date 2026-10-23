// 流用元: reference/agari_cam/lib/scoring/ruleset_support.dart（2026-10-21 時点）
import 'package:mahjong_core/src/models.dart';
import 'package:mahjong_core/src/quick_context.dart';
import 'package:mahjong_core/src/scoring/han_yaku.dart';
import 'package:mahjong_core/src/scoring/rulesets.dart';

class RulesetSupport {
  static bool hasRiichi(QuickContext ctx) => ctx.riichi || ctx.doubleRiichi;

  static bool canToggleIppatsu(QuickContext ctx, Ruleset ruleset) {
    return ruleset.ippatsu && !ctx.openMelds && hasRiichi(ctx);
  }

  static bool canInputUraDora(QuickContext ctx, Ruleset ruleset) {
    return ruleset.uraDora && hasRiichi(ctx);
  }

  static bool canInputKanUra(QuickContext ctx, Ruleset ruleset) {
    return canInputUraDora(ctx, ruleset) && ruleset.kanUra;
  }

  static bool canToggleRenhou(QuickContext ctx, Ruleset ruleset) {
    return ruleset.renhou != RenhouValue.none &&
        ctx.winType == WinType.ron &&
        !ctx.isDealer &&
        !ctx.openMelds &&
        !hasRiichi(ctx);
  }

  static bool isTsumo(QuickContext ctx) => ctx.winType == WinType.tsumo;

  // 偶然役は和了の種類で成立が決まる。成立し得ない組み合わせは計算に使わない。
  static bool canToggleHaitei(QuickContext ctx) => isTsumo(ctx) && !ctx.rinshan;
  static bool canToggleRinshan(QuickContext ctx) => isTsumo(ctx);
  static bool canToggleHoutei(QuickContext ctx) =>
      !isTsumo(ctx) && !ctx.chankan;
  static bool canToggleChankan(QuickContext ctx) => !isTsumo(ctx);
  static bool canToggleTenho(QuickContext ctx) =>
      isTsumo(ctx) && ctx.isDealer && !ctx.openMelds && !hasRiichi(ctx);
  static bool canToggleChiho(QuickContext ctx) =>
      isTsumo(ctx) && !ctx.isDealer && !ctx.openMelds && !hasRiichi(ctx);

  static QuickContext effectiveContext(QuickContext ctx, Ruleset ruleset) {
    final canRiichi = !ctx.openMelds;
    final doubleRiichi = canRiichi ? ctx.doubleRiichi : false;
    final riichi = canRiichi ? (ctx.riichi || doubleRiichi) : false;
    final base = ctx.copyWith(riichi: riichi, doubleRiichi: doubleRiichi);
    final rinshan = canToggleRinshan(base) && base.rinshan;
    final chankan = canToggleChankan(base) && base.chankan;
    final situational = base.copyWith(rinshan: rinshan, chankan: chankan);
    return situational.copyWith(
      ippatsu: canToggleIppatsu(situational, ruleset)
          ? situational.ippatsu
          : false,
      renhou: canToggleRenhou(situational, ruleset)
          ? situational.renhou
          : false,
      haitei: canToggleHaitei(situational) && situational.haitei,
      houtei: canToggleHoutei(situational) && situational.houtei,
      tenho: canToggleTenho(situational) && situational.tenho,
      chiho: canToggleChiho(situational) && situational.chiho,
      kanDoraIndicators: ruleset.kanDora ? situational.kanDoraIndicators : 0,
      uraDoraIndicators: canInputUraDora(situational, ruleset)
          ? situational.uraDoraIndicators
          : 0,
      kanUraIndicators: canInputKanUra(situational, ruleset)
          ? situational.kanUraIndicators
          : 0,
      nukiDora: ruleset.mode == MahjongMode.threePlayer
          ? situational.nukiDora
          : 0,
    );
  }

  static List<Yaku> contextYaku(QuickContext ctx, Ruleset ruleset) {
    final y = <Yaku>[];
    if (ctx.doubleRiichi) {
      y.add(YakuCatalog.daburii);
    } else if (ctx.riichi) {
      y.add(YakuCatalog.riichi);
    }
    if (ctx.ippatsu && ruleset.ippatsu) y.add(YakuCatalog.ippatsu);
    if (ctx.renhou && ruleset.renhou != RenhouValue.none) {
      y.add(renhouYaku(ruleset.renhou));
    }
    // 門前清自摸和は門前のときだけ。副露ツモで0翻の役を並べない。
    if (ctx.winType == WinType.tsumo && !ctx.openMelds) {
      y.add(YakuCatalog.tsumo);
    }
    if (ctx.chankan) y.add(YakuCatalog.chankan);
    if (ctx.rinshan) y.add(YakuCatalog.rinshan);
    if (ctx.haitei) y.add(YakuCatalog.haitei);
    if (ctx.houtei) y.add(YakuCatalog.houtei);
    if (ctx.tenho) y.add(YakuCatalog.tenho);
    if (ctx.chiho) y.add(YakuCatalog.chiho);
    return y;
  }

  static Yaku renhouYaku(RenhouValue value) {
    switch (value) {
      case RenhouValue.none:
        return const Yaku(name: '人和', hanClosed: 0, hanOpen: 0);
      case RenhouValue.mangan:
        return const Yaku(name: '人和', hanClosed: 5, hanOpen: 5);
      case RenhouValue.yakuman:
        return singleYakuman('人和');
    }
  }

  static Yaku singleYakuman(String name, {bool openAllowed = true}) {
    return Yaku(name: name, hanClosed: 13, hanOpen: openAllowed ? 13 : 0);
  }

  static Yaku doubleYakuman(String name, {bool openAllowed = true}) {
    return Yaku(name: name, hanClosed: 26, hanOpen: openAllowed ? 26 : 0);
  }

  static int redDoraCount(Iterable<String> labels, Ruleset ruleset) {
    if (ruleset.redFives <= 0) return 0;
    var redCount = 0;
    for (final label in labels) {
      if (label.startsWith('0')) redCount += 1;
    }
    return redCount > ruleset.redFives ? ruleset.redFives : redCount;
  }

  static int totalDoraCount(
    QuickContext ctx,
    Ruleset ruleset, {
    required Iterable<String> labels,
  }) {
    return doraYaku(
      ctx,
      ruleset,
      labels: labels,
    ).fold(0, (sum, yaku) => sum + yaku.hanClosed);
  }

  /// ドラを種類ごとの「役」として返す（表示・共有で内訳を見せるため）。
  static List<Yaku> doraYaku(
    QuickContext ctx,
    Ruleset ruleset, {
    required Iterable<String> labels,
  }) {
    final effective = effectiveContext(ctx, ruleset);
    final result = <Yaku>[];
    void add(String name, int count) {
      if (count > 0) {
        result.add(Yaku(name: name, hanClosed: count, hanOpen: count));
      }
    }

    add(
      YakuCatalog.doraName,
      effective.doraIndicators + effective.kanDoraIndicators,
    );
    add(YakuCatalog.redDoraName, redDoraCount(labels, ruleset));
    add(
      YakuCatalog.uraDoraName,
      effective.uraDoraIndicators + effective.kanUraIndicators,
    );
    add(YakuCatalog.nukiDoraName, effective.nukiDora);
    return result;
  }

  static bool isYakuman(Yaku yaku, bool open) =>
      !YakuCatalog.isDora(yaku.name) && _hanValue(yaku, open) >= 13;

  static List<Yaku> normalizeYakuList(
    List<Yaku> yaku, {
    required bool open,
    required Ruleset ruleset,
  }) {
    final yakuman = <Yaku>[];
    for (final value in yaku) {
      if (isYakuman(value, open)) {
        yakuman.add(value);
      }
    }
    if (yakuman.isEmpty) {
      return _applyRenhouMangan(yaku, open);
    }
    if (ruleset.yakumanMultiple) {
      return yakuman;
    }
    Yaku? highest;
    var highestHan = -1;
    for (final value in yakuman) {
      final han = _hanValue(value, open);
      if (han > highestHan) {
        highest = value;
        highestHan = han;
      }
    }
    return highest == null ? <Yaku>[] : <Yaku>[highest];
  }

  // 人和（満貫扱い）は他の役と複合しない。他の役だけで満貫以上なら
  // そちらを、届かなければ人和の満貫を採る。
  static List<Yaku> _applyRenhouMangan(List<Yaku> yaku, bool open) {
    final index = yaku.indexWhere(
      (value) => value.name == '人和' && _hanValue(value, open) == 5,
    );
    if (index == -1) return List<Yaku>.from(yaku);
    final others = [...yaku]..removeAt(index);
    final othersHan = others.fold<int>(
      0,
      (sum, value) => sum + _hanValue(value, open),
    );
    return othersHan >= 5 ? others : <Yaku>[yaku[index]];
  }

  static int totalHanForRuleset(
    List<Yaku> yaku, {
    required bool open,
    required Ruleset ruleset,
  }) {
    final normalized = normalizeYakuList(yaku, open: open, ruleset: ruleset);
    var han = 0;
    for (final value in normalized) {
      han += _hanValue(value, open);
    }
    return han;
  }

  static int _hanValue(Yaku yaku, bool open) {
    return open ? yaku.hanOpen : yaku.hanClosed;
  }
}
