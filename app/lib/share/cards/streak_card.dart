import 'package:flutter/material.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';

/// ストリークカード（7 / 30 / 100 日などの節目。仕様 8.1）。
class StreakCard extends StatelessWidget {
  const StreakCard({
    super.key,
    required this.streak,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.watermark = false,
  });

  final StreakState streak;
  final String qrUrl;
  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final story = format.isStory;
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      qrCaption: strings.scanToInstall,
      watermark: watermark,
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
                  strings.streakHeadline,
                  style: TextStyle(
                    fontSize: story ? 28 : 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                  ),
                ),
              ),
              Center(
                child: FittedBox(
                  child: Text(
                    strings.streakBig(streak.current),
                    key: const ValueKey('streak-card-days'),
                    style: TextStyle(
                      fontSize: story ? 120 : 76,
                      fontWeight: FontWeight.w900,
                      color: kCardGold,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              Center(
                child: Text(
                  strings.streakUnit,
                  style: TextStyle(
                    fontSize: story ? 26 : 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: story ? 24 : 10),
              Center(
                child: CardChip(
                  strings.streakBest(streak.best),
                  key: const ValueKey('streak-card-best'),
                ),
              ),
              SizedBox(height: story ? 16 : 8),
              Center(
                child: Text(
                  strings.streakKeepGoing,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
