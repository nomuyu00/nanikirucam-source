import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/share_data.dart';

/// 週間カード（今週の成績と、今週の難問の結果。仕様 6.10）。
class WeeklyCard extends StatelessWidget {
  const WeeklyCard({
    super.key,
    required this.summary,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.watermark = false,
  });

  final WeeklySummary summary;
  final String qrUrl;
  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final story = format.isStory;
    final accuracy = summary.accuracy;
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      qrCaption: strings.scanToInstall,
      watermark: watermark,
      headerTrailing: strings.weeklyPeriod(summary.weekStart),
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
                  strings.weeklyHeadline,
                  key: const ValueKey('weekly-card-headline'),
                  style: TextStyle(
                    fontSize: story ? 40 : 30,
                    fontWeight: FontWeight.w900,
                    color: kCardGold,
                  ),
                ),
              ),
              SizedBox(height: story ? 22 : 8),
              Center(
                child: FittedBox(
                  child: Text(
                    accuracy == null
                        ? strings.weeklyAnswered(summary.answered)
                        : strings.weeklyAccuracy((accuracy * 100).round()),
                    key: const ValueKey('weekly-card-accuracy'),
                    style: TextStyle(
                      fontSize: story ? 52 : 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              SizedBox(height: story ? 14 : 6),
              Center(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    CardChip(strings.weeklyAnswered(summary.answered)),
                    CardChip(strings.weeklyCorrect(summary.correct)),
                  ],
                ),
              ),
              if (summary.hardProblems.isNotEmpty) ...[
                SizedBox(height: story ? 26 : 10),
                Text(
                  strings.weeklyHard,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                for (final result in summary.hardProblems.take(3)) _row(result),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(WeeklyProblemResult result) {
    final rate = result.communityRate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          CardChip(
            result.correct ? strings.weeklySolved : strings.weeklyMissed,
            filled: result.correct,
            fontSize: 11,
          ),
          const SizedBox(width: 10),
          if (rate != null)
            Text(
              strings.communityRate((rate * 100).round()),
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}
