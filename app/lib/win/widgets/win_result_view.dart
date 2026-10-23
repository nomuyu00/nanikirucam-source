import 'package:flutter/material.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

/// 点数の見出し（ジェイドの面）: 親子・ツモロン、段階名か翻符、合計点、支払い、内訳、
/// 翻符・待ち・門前/副露。
class WinScoreHero extends StatelessWidget {
  const WinScoreHero({super.key, required this.result, required this.request});

  final WinResult result;
  final WinRequest request;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    final p = result.payment;
    final breakdown = s.breakdown(p);
    final yakuman = result.rank.isYakumanLevel;
    final details = [
      if (result.rank.isLimit && s.hanFuDetail(result).isNotEmpty)
        s.hanFuDetail(result),
      if (result.shape != WinShape.kokushi) s.waitName(result.wait),
      s.closedName(result.closed),
    ];
    const onHero = Colors.white;
    final muted = Colors.white.withValues(alpha: 0.82);
    return Material(
      key: const ValueKey('win-hero'),
      color: Colors.transparent,
      borderRadius: AppRadius.xlAll,
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: yakuman
                ? const [AppColors.vermilion, AppColors.jadeDeep]
                : const [
                    AppColors.jadeBright,
                    AppColors.jade,
                    AppColors.jadeDeep,
                  ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl - AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xl - AppSpacing.xs,
            AppSpacing.lg + AppSpacing.xxs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + AppSpacing.xxs,
                  vertical: AppSpacing.xxs,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: AppRadius.pillAll,
                ),
                child: Text(
                  s.who(request.isDealer, request.winType),
                  key: const ValueKey('win-who'),
                  style: theme.textTheme.labelMedium?.copyWith(color: onHero),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                s.headline(result),
                key: const ValueKey('win-rank'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: AppColors.goldTint,
                  fontWeight: FontWeight.w800,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  s.points(p.total),
                  key: const ValueKey('win-total'),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: onHero,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.paymentText(p),
                key: const ValueKey('win-payment'),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: onHero,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                s.paymentDetail(p),
                key: const ValueKey('win-payment-detail'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              if (breakdown != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  breakdown,
                  key: const ValueKey('win-breakdown'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: onHero,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs + 2,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final d in details)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: Text(
                        d,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: onHero,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 役の一覧（役名と翻）、ドラ・赤ドラ・裏ドラ、合計、役満に吸収された役、符の内訳。
class WinYakuCard extends StatelessWidget {
  const WinYakuCard({super.key, required this.result});

  final WinResult result;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    final r = result;
    final muted = theme.colorScheme.onSurfaceVariant;
    final rows = <Widget>[
      for (final y in orderedYaku(r.yaku))
        _YakuRow(
          name: s.yakuName(y.id),
          value: s.yakuValue(y),
          strong: y.isYakuman,
          rowKey: ValueKey('win-yaku-${y.id.name}'),
        ),
      if (!r.isYakuman) ...[
        if (r.doraCount > 0)
          _YakuRow(
            name: s.dora,
            value: s.han(r.doraCount),
            rowKey: const ValueKey('win-dora'),
          ),
        if (r.akaDoraCount > 0)
          _YakuRow(
            name: s.akaDora,
            value: s.han(r.akaDoraCount),
            rowKey: const ValueKey('win-aka'),
          ),
        if (r.uraDoraCount > 0)
          _YakuRow(
            name: s.uraDora,
            value: s.han(r.uraDoraCount),
            rowKey: const ValueKey('win-ura'),
          ),
      ],
    ];
    final suppressed = [
      for (final y in r.suppressedYaku) s.yakuName(y.id),
    ].join(s.isEnglish ? ', ' : '・');
    return AppCard(
      key: const ValueKey('win-yaku-card'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.yakuHeader, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          ...rows,
          const Divider(height: AppSpacing.lg),
          _YakuRow(
            name: s.total,
            value: r.isYakuman
                ? s.rankName(r.rank)
                : (r.fu > 0 ? s.hanFu(r.han, r.fu) : s.han(r.han)),
            strong: true,
            rowKey: const ValueKey('win-yaku-total'),
          ),
          if (r.isYakuman && r.totalDora > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                s.doraNotCounted(r.totalDora),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (suppressed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                s.suppressed(suppressed),
                key: const ValueKey('win-suppressed'),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
            ),
          if (!r.isYakuman && r.fu > 0) _FuSection(result: r),
          if (r.isYakuman || r.fu <= 0) const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _YakuRow extends StatelessWidget {
  const _YakuRow({
    required this.name,
    required this.value,
    this.strong = false,
    this.rowKey,
  });

  final String name;
  final String value;
  final bool strong;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = strong
        ? theme.textTheme.titleSmall
        : theme.textTheme.bodyLarge;
    return Padding(
      key: rowKey,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(name, style: style)),
          const SizedBox(width: AppSpacing.md),
          Text(
            value,
            style: style?.copyWith(
              fontWeight: FontWeight.w700,
              color: strong ? AppColors.jadeDeep : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 符の内訳（折りたたみ）。
class _FuSection extends StatelessWidget {
  const _FuSection({required this.result});

  final WinResult result;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    final parts = result.fuParts;
    return Theme(
      // ExpansionTile の上下の線を消す（カードの中に置くため）。
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const ValueKey('win-fu'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: AppSpacing.sm),
        title: Text(
          s.fuHeader(result.fu),
          style: theme.textTheme.titleSmall?.copyWith(color: AppColors.jade),
        ),
        children: [
          if (result.shape == WinShape.chiitoitsu)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(s.fuChiitoitsu, style: theme.textTheme.bodyMedium),
            )
          else
            for (final part in parts)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.xxs + 1,
                ),
                child: Row(
                  children: [
                    if (part.tile != null) ...[
                      TileImage(part.tile!, width: 18),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: Text(
                        s.fuReason(part),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      part.reason == FuReason.roundUp
                          ? '+${s.fu(part.fu)}'
                          : s.fu(part.fu),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
