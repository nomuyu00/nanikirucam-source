import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/win_strings.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/share/share_data.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/notice_card.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';
import 'package:nanikiru_cam/win/widgets/win_conditions_view.dart';
import 'package:nanikiru_cam/win/widgets/win_hand_view.dart';
import 'package:nanikiru_cam/win/widgets/win_result_view.dart';
import 'package:nanikiru_cam/win/win_score_logic.dart';

/// 和了の役と点数（Pro）。
///
/// 上から: 和了の手（和了牌は朱の枠。タップで選び直せる）→ 点数の見出し（段階名・合計点・
/// 支払い・内訳）→ 役と翻・ドラ・符の内訳 → 条件（ツモ/ロン・リーチ・一発・風・ドラ。
/// 偶然役・本場・供託は「その他の条件」）。条件を変えるたびにその場で計算し直す。
/// 下部に「共有」（主）と「点数を隠して出題」。
///
/// 入力の誤り・和了形でない・役なしは [WinError] ごとに直し方を出す。無料のときは
/// Pro の案内だけを出す（Paywall `winScore`）。
class WinScorePage extends ConsumerStatefulWidget {
  const WinScorePage({super.key});

  @override
  ConsumerState<WinScorePage> createState() => _WinScorePageState();
}

class _WinScorePageState extends ConsumerState<WinScorePage> {
  WinScoreArgs? _args;
  WinHand? _hand;
  WinConditions _conditions = WinConditions();
  bool _initialized = false;
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = context.routeArgs<WinScoreArgs>();
    _args = args;
    if (args == null) return;
    final hand = WinHand.fromInput(args.input);
    _hand = hand;
    _conditions = WinConditions.fromInput(args.input).sanitized(hand);
  }

  void _logViewed() {
    if (_logged) return;
    _logged = true;
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.winScoreViewed,
            parameters: {'source': _args?.source ?? 'manual'},
          ),
    );
  }

  void _chooseWinning(int index) {
    final hand = _hand!;
    if (index == hand.winIndex) return;
    setState(() {
      _hand = hand.withWinIndex(index);
      _conditions = _conditions.sanitized(_hand!);
    });
  }

  void _editHand() {
    final args = _args!;
    final navigator = Navigator.of(context);
    if (args.fromEditor && navigator.canPop()) {
      navigator.pop();
      return;
    }
    final hand = _hand!;
    unawaited(
      navigator.pushReplacementNamed(
        Routes.manualInput,
        arguments: RecognitionArgs(
          draft: RecognitionDraft(
            labels: hand.tiles,
            tsumoIndex: hand.winningTile == null ? null : hand.winIndex,
          ),
          base: hand.toHandInput(_conditions),
          mode: HandEntryMode.score,
        ),
      ),
    );
  }

  void _share(WinScored scored, {required bool quiz}) {
    final hand = _hand!;
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.winScoreShared,
            parameters: {
              'kind': quiz ? 'win_quiz' : 'win',
              'rank': winRankParam(scored.best.rank),
            },
          ),
    );
    Navigator.of(context).pushNamed(
      Routes.shareCard,
      arguments: ShareCardArgs(
        kind: quiz ? ShareCardKind.winQuiz : ShareCardKind.win,
        winShare: WinShareData(
          hand: hand.toHandInput(_conditions),
          request: buildWinRequest(hand, _conditions),
          result: scored.best,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final args = _args;
    final hand = _hand;
    if (args == null || hand == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.title)),
        body: EmptyState.error(
          message: s.errorMessage(WinError.wrongTileCount),
        ),
      );
    }
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    if (!pro) {
      return Scaffold(
        key: const ValueKey('win-page'),
        appBar: AppBar(title: Text(s.title)),
        body: const _LockedView(),
      );
    }
    if (!_logged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _logViewed();
      });
    }
    final rules = ref.watch(
      appSettingsProvider.select((x) => (x.redFives, x.openTanyao)),
    );
    final scorer = winScorerFor(redFives: rules.$1, openTanyao: rules.$2);
    final outcome = scoreWin(scorer, hand, _conditions);
    final request = buildWinRequest(hand, _conditions);
    final scored = outcome is WinScored ? outcome : null;

    return Scaffold(
      key: const ValueKey('win-page'),
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          // 狭い画面・大きな文字では見出しを優先して、アイコンだけにする。
          if (_compactAppBar(context))
            IconButton(
              key: const ValueKey('win-edit-hand'),
              tooltip: s.editHand,
              onPressed: _editHand,
              icon: const Icon(Icons.edit_outlined),
            )
          else
            TextButton.icon(
              key: const ValueKey('win-edit-hand'),
              onPressed: _editHand,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(s.editHand),
            ),
        ],
      ),
      body: ListView(
        key: const ValueKey('win-list'),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          _handCard(hand, scored),
          const SizedBox(height: AppSpacing.md),
          switch (outcome) {
            WinScored() => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WinScoreHero(result: outcome.best, request: request),
                const SizedBox(height: AppSpacing.md),
                WinYakuCard(result: outcome.best),
              ],
            ),
            WinRejected(:final error) => _ErrorCard(
              error: error,
              onEditHand: _editHand,
            ),
          },
          const SizedBox(height: AppSpacing.md),
          WinConditionsCard(
            hand: hand,
            conditions: _conditions,
            onChanged: (next) => setState(() => _conditions = next),
          ),
        ],
      ),
      bottomNavigationBar: _bottomBar(scored),
    );
  }

  static bool _compactAppBar(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.size.width / media.textScaler.scale(1) < 340;
  }

  Widget _handCard(WinHand hand, WinScored? scored) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    final alt = scored == null ? null : differentScoreAlternative(scored);
    return AppCard(
      key: const ValueKey('win-hand'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WinHandView(hand: hand, onTapTile: _chooseWinning),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  s.tapToChangeWinning,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (alt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            NoticeCard(
              key: const ValueKey('win-alternative'),
              icon: Icons.info_outline,
              tone: NoticeTone.info,
              message: s.alternativeNote(
                bestWait: scored!.best.wait,
                altWait: alt.wait,
                altTotal: alt.payment.total,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(WinScored? scored) {
    final s = context.winStrings;
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm + AppSpacing.xxs,
            AppSpacing.md,
            AppSpacing.sm + AppSpacing.xxs,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const ValueKey('win-share-quiz'),
                  onPressed: scored == null
                      ? null
                      : () => _share(scored, quiz: true),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                  icon: const Icon(Icons.quiz_outlined, size: 20),
                  label: _FitLabel(s.shareQuiz),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  key: const ValueKey('win-share'),
                  onPressed: scored == null
                      ? null
                      : () => _share(scored, quiz: false),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 20),
                  label: _FitLabel(s.share),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ボタンの文字（2 行まで。収まらなければ縮める）。
class _FitLabel extends StatelessWidget {
  const _FitLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    textAlign: TextAlign.center,
    overflow: TextOverflow.ellipsis,
  );
}

/// 計算できなかったとき（入力の誤り・和了形でない・役なし・状況の矛盾）。
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onEditHand});

  final WinError error;
  final VoidCallback onEditHand;

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final handError = isHandError(error);
    return NoticeCard(
      key: const ValueKey('win-error'),
      tone: error == WinError.noYaku ? NoticeTone.caution : NoticeTone.danger,
      icon: error == WinError.noYaku
          ? Icons.do_not_disturb_alt_outlined
          : Icons.error_outline,
      title: s.errorTitle(error),
      message: s.errorMessage(error),
      messageKey: ValueKey('win-error-${error.name}'),
      action: handError
          ? FilledButton.tonalIcon(
              key: const ValueKey('win-error-edit'),
              onPressed: onEditHand,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(s.editHand),
            )
          : null,
    );
  }
}

/// 無料のとき: Pro の案内と Paywall（`winScore`）。
class _LockedView extends StatelessWidget {
  const _LockedView();

  @override
  Widget build(BuildContext context) {
    final s = context.winStrings;
    final theme = Theme.of(context);
    return ListView(
      padding: AppSpacing.page,
      children: [
        AppCard(
          key: const ValueKey('win-locked'),
          color: AppColors.goldTint.withValues(alpha: 0.5),
          borderColor: AppColors.gold.withValues(alpha: 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ProBadge(),
              const SizedBox(height: AppSpacing.sm),
              Text(s.lockedTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(s.lockedBody, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                key: const ValueKey('win-go-pro'),
                onPressed: () => Navigator.of(context).pushNamed(
                  Routes.paywall,
                  arguments: const PaywallArgs(
                    trigger: PaywallTrigger.winScore,
                  ),
                ),
                icon: const Icon(Icons.workspace_premium),
                label: Text(s.goPro),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
