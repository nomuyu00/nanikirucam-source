import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/hand_panel.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 結果カードに載せる内容（「あなた: 3p ／ 正解: 7s（受け入れ 24枚 vs 16枚）」、正解率、
/// ストリーク。設計書 8 章）。
class ResultCardData extends Equatable {
  const ResultCardData({
    required this.input,
    this.chosen,
    this.correctTiles = const [],
    this.chosenUkeire,
    this.correctUkeire,
    this.matchedAxis,
    this.communityPercent,
    this.streak = 0,
  });

  /// 解析結果と選んだ牌から作る。
  ///
  /// [chosenDiscardId] が null（スキップ・選んでいない）なら正解だけを載せる。
  /// 正解は **バランス軸の 1 位**。選んだ牌が別の軸の 1 位なら [matchedAxis] に入る。
  factory ResultCardData.fromReport({
    required HandInput input,
    required AnalysisReport report,
    int? chosenDiscardId,
    int? communityPercent,
    int streak = 0,
  }) {
    final balance = report.bestByAxis[StrategyAxis.balance] ?? const <int>[];
    int? ukeireOf(int id) {
      for (final c in report.candidates) {
        if (c.discardId == id) return c.ukeire.total;
      }
      return null;
    }

    final correctLabels = <String>[
      for (final id in balance) ?tileLabelInHand(input, id),
    ];
    final chosenLabel = chosenDiscardId == null
        ? null
        : tileLabelInHand(input, chosenDiscardId);
    StrategyAxis? matched;
    if (chosenDiscardId != null && !balance.contains(chosenDiscardId)) {
      for (final axis in const [StrategyAxis.speed, StrategyAxis.points]) {
        if ((report.bestByAxis[axis] ?? const <int>[]).contains(
          chosenDiscardId,
        )) {
          matched = axis;
          break;
        }
      }
    }
    return ResultCardData(
      input: input,
      chosen: chosenLabel,
      correctTiles: correctLabels,
      chosenUkeire: chosenDiscardId == null ? null : ukeireOf(chosenDiscardId),
      correctUkeire: balance.isEmpty ? null : ukeireOf(balance.first),
      matchedAxis: matched,
      communityPercent: communityPercent,
      streak: streak,
    );
  }

  final HandInput input;

  /// 選んだ牌のラベル（選んでいなければ null）。
  final String? chosen;

  /// 正解の牌（バランス軸の 1 位。同順位は複数）。
  final List<String> correctTiles;

  /// 選んだ牌・正解を切った後の受け入れ枚数。
  final int? chosenUkeire;
  final int? correctUkeire;

  /// 正解ではないが、この軸の 1 位だった（「打点重視なら正解」）。
  final StrategyAxis? matchedAxis;

  /// みんなの正解率（％）。公開問題のときだけ。
  final int? communityPercent;

  /// 連続回答日数。
  final int streak;

  /// 選んだ牌が正解か。選んでいなければ null。
  bool? get isCorrect {
    final c = chosen;
    if (c == null) return null;
    return correctTiles.any((t) => _sameTile(t, c));
  }

  @override
  List<Object?> get props => [
    input,
    chosen,
    correctTiles,
    chosenUkeire,
    correctUkeire,
    matchedAxis,
    communityPercent,
    streak,
  ];
}

bool _sameTile(String a, String b) {
  final ia = tileIdFromLabel(a);
  return ia >= 0 && ia == tileIdFromLabel(b);
}

/// 結果カード。「あなた」と「正解」を並べ、受け入れの差・正解率・ストリークを添える。
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.data,
    required this.qrUrl,
    required this.format,
    required this.strings,
    this.watermark = false,
  });

  final ResultCardData data;
  final String qrUrl;
  final ShareCardFormat format;
  final ShareStrings strings;
  final bool watermark;

  @override
  Widget build(BuildContext context) {
    final story = format.isStory;
    final correct = data.isCorrect;
    final headline = correct == null
        ? strings.resultNoChoice
        : correct
        ? strings.resultCorrect
        : strings.resultWrong;
    final tileWidth = story ? 44.0 : 34.0;
    return ShareCardFrame(
      format: format,
      strings: strings,
      qrUrl: qrUrl,
      qrCaption: strings.scanToInstall,
      watermark: watermark,
      headerTrailing: strings.conditions(data.input),
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
                  headline,
                  key: const ValueKey('result-card-headline'),
                  style: TextStyle(
                    fontSize: story ? 44 : 32,
                    fontWeight: FontWeight.w900,
                    color: correct == false ? Colors.white : kCardGold,
                  ),
                ),
              ),
              SizedBox(height: story ? 22 : 8),
              HandPanel(
                input: data.input,
                tileWidth: story ? 24 : 20,
                highlightTsumo: false,
              ),
              SizedBox(height: story ? 24 : 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.chosen != null)
                    Expanded(
                      child: _pick(
                        key: const ValueKey('result-card-you'),
                        label: strings.youLabel,
                        tiles: [data.chosen!],
                        tileWidth: tileWidth,
                        highlight: correct == true,
                      ),
                    ),
                  Expanded(
                    child: _pick(
                      key: const ValueKey('result-card-answer'),
                      label: strings.answerLabel,
                      tiles: data.correctTiles,
                      tileWidth: tileWidth,
                      highlight: true,
                    ),
                  ),
                ],
              ),
              if (data.chosenUkeire != null && data.correctUkeire != null) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    strings.ukeireVs(data.chosenUkeire!, data.correctUkeire!),
                    key: const ValueKey('result-card-ukeire'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ] else if (data.correctUkeire != null) ...[
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    strings.ukeireOnly(data.correctUkeire!),
                    key: const ValueKey('result-card-ukeire'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
              if (data.matchedAxis != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: CardChip(
                    strings.correctForAxis(data.matchedAxis!),
                    key: const ValueKey('result-card-axis'),
                    filled: true,
                  ),
                ),
              ],
              SizedBox(height: story ? 22 : 10),
              Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (data.communityPercent != null)
                      CardChip(
                        strings.communityRate(data.communityPercent!),
                        key: const ValueKey('result-card-community'),
                      ),
                    if (data.streak > 0)
                      CardChip(
                        strings.streakDays(data.streak),
                        key: const ValueKey('result-card-streak'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pick({
    required Key key,
    required String label,
    required List<String> tiles,
    required double tileWidth,
    required bool highlight,
  }) {
    return Column(
      key: key,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            for (final tile in tiles)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: highlight ? kCardGold : Colors.white24,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: TileImage(tile, width: tileWidth),
              ),
          ],
        ),
      ],
    );
  }
}
