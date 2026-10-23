import 'package:flutter/material.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';

/// ライブの対局サマリーカード（「今日の成果」。仕様 8.1）。友人戦・練習用と明記する。
class LiveSummaryCard extends StatelessWidget {
  const LiveSummaryCard({
    super.key,
    required this.summary,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.watermark = false,
  });

  final LiveSummaryArgs summary;
  final String qrUrl;
  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final story = format.isStory;
    final bestWin = summary.wins.isEmpty
        ? null
        : summary.wins.reduce((a, b) => a.points >= b.points ? a : b);
    final rows = <String>[
      strings.liveDuration(summary.durationSec),
      strings.liveAdvice(summary.adviceCount),
      strings.liveFollowed(summary.followedCount, summary.adviceCount),
      strings.liveWins(summary.wins.length),
    ];
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      qrCaption: strings.scanToInstall,
      watermark: watermark,
      headerTrailing: strings.liveNote,
      body: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: story ? Alignment.center : Alignment.topCenter,
        child: SizedBox(
          width: 324,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  strings.liveSummaryHeadline,
                  key: const ValueKey('live-summary-headline'),
                  style: TextStyle(
                    fontSize: story ? 40 : 30,
                    fontWeight: FontWeight.w900,
                    color: kCardGold,
                  ),
                ),
              ),
              SizedBox(height: story ? 8 : 4),
              Center(
                child: CardChip(
                  strings.livePlayedWithNavi,
                  key: const ValueKey('live-summary-navi'),
                  filled: true,
                ),
              ),
              SizedBox(height: story ? 26 : 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final row in rows)
                    CardChip(row, key: ValueKey('live-summary-row-$row')),
                ],
              ),
              if (bestWin != null) ...[
                SizedBox(height: story ? 26 : 12),
                Center(
                  child: FittedBox(
                    child: Text(
                      strings.liveBestWin(bestWin.points),
                      key: const ValueKey('live-summary-best'),
                      style: TextStyle(
                        fontSize: story ? 34 : 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                if (bestWin.yaku.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final yaku in bestWin.yaku.take(4)) CardChip(yaku),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
