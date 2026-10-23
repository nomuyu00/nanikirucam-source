import 'package:flutter/material.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/hand_panel.dart';
import 'package:nanikiru_cam/share/share_links.dart';

/// 問題カード（答えを隠した出題画像。仕様 6.10・設計書 8 章）。
///
/// 牌パネル（ツモ牌を離す、副露は横向き）、「この手、何切る？」、ドラ・風・巡目、出題者名、
/// 問題ページへの QR、アプリ名とストア誘導、透かし（無料のみ）。答えは載せない。
class ProblemCard extends StatelessWidget {
  const ProblemCard({
    super.key,
    required this.input,
    required this.authorName,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.watermark = false,
    this.answerCount = 0,
  });

  final HandInput input;

  /// 出題者名。空なら「匿名」。
  final String authorName;

  /// `<webBaseUrl>/p/{id}?ref=<紹介コード>`、公開前・失敗時はストアの URL。
  final String qrUrl;

  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  /// 回答数（再共有のときに「N人が回答」と載せる。0 なら載せない）。
  final int answerCount;

  @override
  Widget build(BuildContext context) {
    final story = format.isStory;
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      // 問題ページの URL なら「答える」、ストアの URL なら「アプリを入手」。
      qrCaption: ShareLinks.isProblemUrl(qrUrl)
          ? strings.scanToAnswer
          : strings.scanToInstall,
      watermark: watermark,
      footerLead: strings.author(authorName.trim()),
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
                child: FittedBox(
                  child: Text(
                    strings.problemHeadline,
                    key: const ValueKey('problem-card-headline'),
                    style: TextStyle(
                      fontSize: story ? 40 : 30,
                      fontWeight: FontWeight.w900,
                      color: kCardGold,
                    ),
                  ),
                ),
              ),
              if (story) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    strings.problemSubline,
                    style: const TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ),
              ],
              SizedBox(height: story ? 32 : 10),
              HandPanel(input: input, tileWidth: story ? 24 : 22),
              SizedBox(height: story ? 22 : 8),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Text(
                      strings.conditions(input),
                      key: const ValueKey('problem-card-conditions'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    DoraRow(
                      key: const ValueKey('problem-card-dora'),
                      indicators: input.doraIndicators,
                      label: strings.doraIndicator,
                      tileWidth: story ? 20 : 16,
                    ),
                  ],
                ),
              ),
              if (answerCount > 0) ...[
                SizedBox(height: story ? 18 : 6),
                Center(
                  child: CardChip(
                    strings.answerCount(answerCount),
                    filled: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
