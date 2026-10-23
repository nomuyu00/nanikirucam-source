import 'package:flutter/material.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';

const _kCardYakuman = [Color(0xFF5A0F1E), Color(0xFF1E0610)];

/// ライブ節目カード（初めての和了・満貫。仕様 8.1）。役・点数・「ナビで打った」表記。
/// ライブは友人戦・練習用と明記する（仕様 8.4）。
class LiveMilestoneCard extends StatelessWidget {
  const LiveMilestoneCard({
    super.key,
    required this.win,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.firstWin = false,
    this.watermark = false,
  });

  final LiveWinSummary win;

  /// 「ナビ付きで初和了！」にする。
  final bool firstWin;

  final String qrUrl;
  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final story = format.isStory;
    final rank = strings.winRank(win.han, win.fu);
    final headline = firstWin
        ? strings.liveFirstWin
        : rank == '満貫' || rank == 'Mangan'
        ? strings.liveManganWin
        : strings.liveWin;
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      qrCaption: strings.scanToInstall,
      watermark: watermark,
      headerTrailing: strings.liveNote,
      gradient: rank.isNotEmpty && win.han >= 13 ? _kCardYakuman : kCardGreen,
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
                child: CardChip(
                  strings.livePlayedWithNavi,
                  key: const ValueKey('live-milestone-navi'),
                  filled: true,
                ),
              ),
              SizedBox(height: story ? 22 : 8),
              Center(
                child: FittedBox(
                  child: Text(
                    headline,
                    key: const ValueKey('live-milestone-headline'),
                    style: TextStyle(
                      fontSize: story ? 38 : 28,
                      fontWeight: FontWeight.w900,
                      color: kCardGold,
                    ),
                  ),
                ),
              ),
              if (rank.isNotEmpty) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    rank,
                    key: const ValueKey('live-milestone-rank'),
                    style: TextStyle(
                      fontSize: story ? 56 : 40,
                      fontWeight: FontWeight.w900,
                      color: kCardGold,
                      letterSpacing: 8,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Center(
                child: Text(
                  strings.hanFu(win.han, win.fu),
                  key: const ValueKey('live-milestone-hanfu'),
                  style: const TextStyle(fontSize: 15, color: Colors.white70),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: FittedBox(
                  child: Text(
                    strings.points(win.points),
                    key: const ValueKey('live-milestone-points'),
                    style: TextStyle(
                      fontSize: story ? 44 : 34,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (win.yaku.isNotEmpty) ...[
                SizedBox(height: story ? 22 : 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final yaku in win.yaku.take(6)) CardChip(yaku),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
