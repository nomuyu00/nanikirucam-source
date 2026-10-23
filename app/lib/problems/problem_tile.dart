import 'package:flutter/material.dart';
import 'package:nanikiru_cam/l10n/strings/problems_strings.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/hand_panel.dart';

/// 問題の一覧の 1 件（Today・出題した問題）。手牌・出題者・回答数と正解率を見せる。
class ProblemListTile extends StatelessWidget {
  const ProblemListTile({
    super.key,
    required this.problem,
    this.badges = const [],
    this.onTap,
    this.trailing,
    this.footer,
    this.showAuthor = true,
    this.showStats = true,
  });

  final Problem problem;

  /// 手牌の上に並べるバッジ（「公式」「非表示」など）。
  final List<String> badges;
  final VoidCallback? onTap;

  /// 右上のボタン（通報メニューなど）。
  final Widget? trailing;

  /// 一番下に足す行（共有ボタン・回答到達の表示など）。
  final Widget? footer;

  final bool showAuthor;

  /// 回答数・正解率の行を出す（端末内の今日の問題は集計が無いので出さない）。
  final bool showStats;

  @override
  Widget build(BuildContext context) {
    final problems = context.problemsStrings;
    final share = context.shareStrings;
    final stats = problem.stats;
    final percent = stats.correctPercent;
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  for (final badge in badges)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Chip(
                        label: Text(badge),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  if (showAuthor)
                    Expanded(
                      child: Text(
                        problems.author(problem.authorNickname),
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: kCardGreen),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: HandPanel(
                  input: problem.input,
                  tileWidth: 22,
                  background: false,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                share.conditions(problem.input),
                style: theme.textTheme.bodySmall,
              ),
              if (showStats) ...[
                const SizedBox(height: 2),
                Text(
                  stats.total == 0
                      ? problems.noAnswersYet
                      : [
                          problems.answers(stats.total),
                          if (percent != null) problems.correctRate(percent),
                        ].join(' ・ '),
                  key: ValueKey('problem-stats-${problem.id}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              ?footer,
            ],
          ),
        ),
      ),
    );
  }
}
