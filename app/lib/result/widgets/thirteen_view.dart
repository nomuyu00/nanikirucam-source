import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_format.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 13 枚のとき（仕様 4.5・7.2）: シャンテン数、テンパイなら待ち・残り枚数・ロン／ツモの
/// 点数・役なし判定・リーチ可否、テンパイでなければ受け入れ。Pro はリーチ判断の比較。
class ThirteenView extends StatelessWidget {
  const ThirteenView({
    super.key,
    required this.report,
    required this.input,
    required this.pro,
  });

  final AnalysisReport report;
  final HandInput input;
  final bool pro;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final text = ReasonText(context.lang);
    final t = report.thirteen!;
    final tenpai = t.shanten.shanten == 0;
    final closed = !input.isOpen;
    final theme = Theme.of(context);

    final children = <Widget>[
      Text(
        common.shanten(t.shanten.shanten),
        key: const ValueKey('thirteen-shanten'),
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    ];

    if (tenpai) {
      final left = t.waits.fold<int>(0, (n, w) => n + w.remaining);
      children.add(
        Text(
          s.waitsSummary(text.tiles(t.waits.map((w) => w.tileId)), left),
          key: const ValueKey('thirteen-waits'),
          style: theme.textTheme.titleMedium,
        ),
      );
      final messages = <(String, Key, bool)>[];
      if (left == 0) {
        messages.add((s.noWaitsLeft, const ValueKey('msg-no-waits'), true));
      } else if (!t.hasYaku) {
        messages.add(
          closed
              ? (s.closedNoYaku, const ValueKey('msg-closed-no-yaku'), true)
              : (s.openNoYaku, const ValueKey('msg-open-no-yaku'), true),
        );
      } else {
        messages.add(
          closed
              ? (s.riichiPossible, const ValueKey('msg-riichi-possible'), false)
              : (s.openWithYaku, const ValueKey('msg-open-yaku'), false),
        );
      }
      if (left > 0 && left <= 2) {
        messages.add((s.fewWaits, const ValueKey('msg-few-waits'), true));
      }
      for (final (message, key, warn) in messages) {
        children.add(_MessageBox(key: key, text: message, warning: warn));
      }
      children.add(const SizedBox(height: 8));
      children.add(Text(s.waitsTitle, style: theme.textTheme.titleSmall));
      for (final w in t.waits) {
        children.add(_WaitRow(wait: w, closed: closed));
      }
      if (t.riichiPossible) {
        children.add(const SizedBox(height: 8));
        if (pro && t.riichi != null) {
          children.add(RiichiAdviceView(advice: t.riichi!));
        } else if (!pro) {
          children.add(ProLock(label: s.riichiLocked));
        }
      }
    } else {
      children
        ..add(
          Text(
            s.ukeire(t.draws.kinds, t.draws.total),
            key: const ValueKey('thirteen-draws'),
            style: theme.textTheme.titleMedium,
          ),
        )
        ..add(const SizedBox(height: 4))
        ..add(TileCountStrip(counts: t.draws.tiles));
    }
    children
      ..add(const SizedBox(height: 12))
      ..add(Text(s.thirteenHint, style: theme.textTheme.bodySmall));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _MessageBox extends StatelessWidget {
  const _MessageBox({super.key, required this.text, this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.caution : AppColors.success;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.warning_amber : Icons.check_circle_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _WaitRow extends StatelessWidget {
  const _WaitRow({required this.wait, required this.closed});

  final WaitInfo wait;
  final bool closed;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final label = tileLabelOfId(wait.tileId);
    String pts(int? p) => p == null ? s.noYaku : formatPoints(p);
    final riichi = closed && wait.ronRiichiPoints != null;
    return Padding(
      key: ValueKey('wait-${wait.tileId}'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TileImage(label, width: 28, semanticLabel: common.tileName(label)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${common.tileName(label)}  ${s.remaining(wait.remaining)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${s.ron} ${pts(wait.ronPoints)} / '
                  '${s.tsumo} ${pts(wait.tsumoPoints)}',
                ),
                if (riichi)
                  Text(
                    '${s.riichiIncluded}: ${s.ron} '
                    '${formatPoints(wait.ronRiichiPoints!)} / ${s.tsumo} '
                    '${formatPoints(wait.tsumoRiichiPoints ?? 0)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pro のリーチ判断（「リーチ推奨／様子見（ダマ）」と根拠、打点 × 上がりやすさの比較）。
class RiichiAdviceView extends StatelessWidget {
  const RiichiAdviceView({super.key, required this.advice});

  final RiichiAdvice advice;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final color = advice.recommendRiichi
        ? AppColors.success
        : AppColors.inkMuted;
    final ease = formatPercent(advice.winEase);
    return Container(
      key: const ValueKey('riichi-advice'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${s.riichiAdviceTitle}: '
            '${advice.recommendRiichi ? s.riichiRecommend : s.riichiWait}',
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(s.riichiReason(advice.reason)),
          if (advice.reason != RiichiReason.noWaitsLeft) ...[
            const SizedBox(height: 4),
            Text(
              s.riichiCompare(
                formatPoints(advice.riichiPoints),
                ease,
                formatPoints(advice.riichiValue),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              s.damaCompare(
                formatPoints(advice.damaPoints),
                ease,
                formatPoints(advice.damaValue),
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 14 枚が和了形のとき（仕様 7.2「和了形なら役と点数」）。
class WinCard extends StatelessWidget {
  const WinCard({super.key, required this.report});

  final AnalysisReport report;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final text = ReasonText(context.lang);
    final win = report.win;
    const color = AppColors.danger;
    return Card(
      key: const ValueKey('result-win'),
      color: color.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: win == null
            ? Text(s.winNoYaku)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.winTitle,
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      for (final y in win.yaku)
                        Text(
                          '${text.scoredYaku(y)} '
                          '${s.han(win.closed ? y.hanClosed : y.hanOpen)}',
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${s.hanFu(win.han, win.fu)}  '
                    '${s.points(formatPoints(report.winPoints ?? 0))}',
                    key: const ValueKey('result-win-points'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
