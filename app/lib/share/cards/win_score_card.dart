import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/hand_panel.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

const _kCardYakuman = [Color(0xFF5A0F1E), Color(0xFF1E0610)];

/// 和了の役と点数のカード（Pro の和了の点数画面から）。牌（和了牌は朱の枠、副露は横向き）、
/// ドラ表示牌、条件の 1 行、段階名と点数、支払い、役と翻。
///
/// [quiz] なら点数クイズ: 点数・役を隠して「この手、何点？」。条件（リーチ・偶然役・本場）と
/// ドラ表示牌は出す（牌からは分からないので）。
class WinScoreCard extends StatelessWidget {
  const WinScoreCard({
    super.key,
    required this.data,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.quiz = false,
    this.watermark = false,
  });

  final WinShareData data;
  final bool quiz;
  final String qrUrl;
  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final w = WinStrings(strings.lang);
    final story = format.isStory;
    final r = data.result;
    final request = data.request;
    final yakuman = r.rank.isYakumanLevel;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WinTilesPanel(hand: data.hand, story: story),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            DoraRow(
              indicators: request.doraIndicators,
              label: strings.doraIndicator,
            ),
            if (request.riichi || request.doubleRiichi)
              DoraRow(indicators: request.uraDoraIndicators, label: w.uraLabel),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          w.conditionLine(request),
          key: const ValueKey('win-card-conditions'),
          textAlign: TextAlign.center,
          maxLines: 2,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        SizedBox(height: story ? 24 : 10),
        if (quiz) ..._quiz(w, story) else ..._answer(w, story),
      ],
    );
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      qrCaption: strings.scanToInstall,
      storeLead: quiz ? w.quizStoreLead : w.storeLead,
      watermark: watermark,
      gradient: !quiz && yakuman ? _kCardYakuman : kCardGreen,
      body: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: story ? Alignment.center : Alignment.topCenter,
        child: SizedBox(width: 324, child: body),
      ),
    );
  }

  List<Widget> _answer(WinStrings w, bool story) {
    final r = data.result;
    final p = r.payment;
    final breakdown = w.breakdown(p);
    final detail = w.hanFuDetail(r);
    return [
      Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                w.headline(r),
                key: const ValueKey('win-card-rank'),
                style: TextStyle(
                  fontSize: story ? 40 : 30,
                  fontWeight: FontWeight.w900,
                  color: kCardGold,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                w.points(p.total),
                key: const ValueKey('win-card-points'),
                style: TextStyle(
                  fontSize: story ? 40 : 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 2),
      Center(
        child: Text(
          [
            w.paymentText(p),
            if (r.rank.isLimit && detail.isNotEmpty) detail,
          ].join('  ·  '),
          key: const ValueKey('win-card-payment'),
          style: const TextStyle(fontSize: 14, color: Colors.white),
        ),
      ),
      if (breakdown != null)
        Center(
          child: Text(
            breakdown,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ),
      SizedBox(height: story ? 20 : 8),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final y in orderedYaku(r.yaku))
            CardChip('${w.yakuName(y.id)} ${w.yakuValue(y)}', fontSize: 11),
          if (!r.isYakuman) ...[
            if (r.doraCount > 0)
              CardChip('${w.dora} ${r.doraCount}', fontSize: 11),
            if (r.akaDoraCount > 0)
              CardChip('${w.akaDora} ${r.akaDoraCount}', fontSize: 11),
            if (r.uraDoraCount > 0)
              CardChip('${w.uraDora} ${r.uraDoraCount}', fontSize: 11),
          ],
        ],
      ),
    ];
  }

  List<Widget> _quiz(WinStrings w, bool story) {
    return [
      // 1 行に収める（英語は長いので縮める）。
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          w.quizHeadline,
          key: const ValueKey('win-card-quiz'),
          maxLines: 1,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: story ? 40 : 30,
            fontWeight: FontWeight.w900,
            color: kCardGold,
          ),
        ),
      ),
      SizedBox(height: story ? 14 : 6),
      Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: kCardGold.withValues(alpha: 0.8)),
            borderRadius: BorderRadius.circular(10),
            color: Colors.black.withValues(alpha: 0.18),
          ),
          child: Text(
            w.quizHidden,
            style: TextStyle(
              fontSize: story ? 30 : 24,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
      SizedBox(height: story ? 14 : 6),
      Center(
        child: Text(
          w.quizSubline,
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
      ),
    ];
  }
}

/// 牌の並び: 門前の牌（理牌）・少し離して和了牌（朱の枠）・副露（鳴いた牌は横向き）。
class _WinTilesPanel extends StatelessWidget {
  const _WinTilesPanel({required this.hand, required this.story});

  final HandInput hand;
  final bool story;

  @override
  Widget build(BuildContext context) {
    final win = hand.tsumoTile;
    final concealed = [...(win == null ? hand.tiles : hand.tilesWithoutTsumo)]
      ..sort(compareTileLabels);
    final count =
        concealed.length +
        (win == null ? 0 : 1) +
        hand.melds.fold<int>(0, (sum, m) => sum + m.tiles.length);
    // 1 列に収まる大きさにする（槓があっても横にはみ出さない）。
    final width = ((324 - 40) / (count + 1)).clamp(14.0, story ? 26.0 : 22.0);
    final gap = width * 0.45;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final t in concealed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0.6),
                child: TileImage(t, width: width),
              ),
            if (win != null) ...[
              SizedBox(width: gap),
              Container(
                key: const ValueKey('win-card-winning'),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.vermilion, width: 2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: TileImage(win, width: width),
              ),
            ],
            for (final meld in hand.melds) ...[
              SizedBox(width: gap),
              for (var i = 0; i < meld.tiles.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 0.6),
                  child: TileImage(
                    meld.tiles[i],
                    width: width,
                    sideways: meld.isOpen && i == 0,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
