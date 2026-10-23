import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/url_opener.dart';
import 'package:nanikiru_cam/l10n/strings/paywall_strings.dart';
import 'package:nanikiru_cam/live/live_trial_extend_panel.dart';
import 'package:nanikiru_cam/purchase/subscription_backend.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/pro_badge.dart';

/// 計測の `trigger`（`AppAnalytics` の許可リストの値）。
String paywallTriggerParam(PaywallTrigger trigger) => switch (trigger) {
  PaywallTrigger.home => 'home',
  PaywallTrigger.settings => 'settings',
  PaywallTrigger.liveTrialEnded => 'live_trial',
  PaywallTrigger.quotaExhausted => 'quota',
  PaywallTrigger.explanationLocked => 'explanation',
  // 許可リストにまだ無い値。リストに足されるまでは trigger なしで記録される。
  PaywallTrigger.candidateLocked => 'candidate',
  PaywallTrigger.todayLimit => 'today_limit',
  PaywallTrigger.historyLocked => 'history',
  PaywallTrigger.winScore => 'win_score',
};

/// 日付の表示（2026-10-21）。
String formatPaywallDate(DateTime date) {
  final local = date.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

/// 課金画面（仕様 6.11・10 章、設計書 9 章）。購入に成功すると `true` を返して閉じる。
/// 呼び出し側は `final purchased = await Navigator.pushNamed(context, Routes.paywall, ...)` の
/// 結果が `true` かで続きの処理を決める（ルート表のルートは型引数なしで受ける）。
class PaywallPage extends ConsumerStatefulWidget {
  const PaywallPage({super.key});

  @override
  ConsumerState<PaywallPage> createState() => _PaywallPageState();
}

class _PaywallPageState extends ConsumerState<PaywallPage> {
  PlanKind? _selected;
  bool _logged = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_logged) return;
    _logged = true;
    final args = context.routeArgs<PaywallArgs>();
    final trigger = args?.trigger ?? PaywallTrigger.settings;
    // 表示ごとに記録する。すでに Pro なら課金画面を見せたことにならない。
    if (!ref.read(entitlementsProvider).pro) {
      ref.read(analyticsSinkProvider)(AnalyticsEvent.paywallViewed, {
        'trigger': paywallTriggerParam(trigger),
      });
    }
    // プランは先に読み込んでおく（起動時に取れていれば何もしない）。
    final service = ref.read(subscriptionServiceProvider);
    if (service.available && service.plansState != PlansState.ready) {
      unawaited(service.loadPlans());
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.paywallStrings;
    final args = context.routeArgs<PaywallArgs>();
    final trigger = args?.trigger ?? PaywallTrigger.settings;
    final service = ref.watch(subscriptionServiceProvider);
    final entitlement = ref.watch(entitlementsProvider);
    final busy = service.busy != SubscriptionBusy.none;
    final recap = trigger == PaywallTrigger.liveTrialEnded
        ? strings.liveRecap(args?.liveAdviceCount, args?.liveWinCount)
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: SafeArea(
        child: Column(
          children: [
            if (busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  AppSpacing.sm,
                  AppSpacing.gutter,
                  AppSpacing.xl,
                ),
                children: [
                  _Header(
                    headline: strings.headline(trigger),
                    subhead: strings.subhead(trigger),
                    recap: recap,
                  ),
                  const SizedBox(height: AppSpacing.lg + AppSpacing.xs),
                  _Benefits(strings: strings),
                  const SizedBox(height: AppSpacing.xl),
                  if (entitlement.pro)
                    _ProStatus(
                      entitlement: entitlement,
                      onManage: _openManagement,
                    )
                  else if (!service.configured)
                    _NotReady(strings: strings)
                  else
                    _Plans(
                      service: service,
                      selected: _selected,
                      busy: busy,
                      onSelect: (kind) => setState(() => _selected = kind),
                      onPurchase: _purchase,
                    ),
                  // 体験終了のときだけ、購入の下にサブの選択肢として動画での延長を出す。
                  if (trigger == PaywallTrigger.liveTrialEnded &&
                      !entitlement.pro)
                    LiveTrialExtendPanel(
                      analyticsTrigger: paywallTriggerParam(trigger),
                      // 延長できたら、そのままライブへ戻る（ここへは live から置き換えで来ている）。
                      onExtended: (_) => unawaited(
                        Navigator.of(context).pushReplacementNamed(Routes.live),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  _Footer(
                    strings: strings,
                    canRestore: service.configured,
                    busy: busy,
                    onRestore: _restore,
                    onOpen: _open,
                    onManage: _openManagement,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(Uri uri) => ref.read(urlOpenerProvider)(uri);

  Future<void> _openManagement() => _open(subscriptionManagementUri());

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _purchase(StorePlan plan) async {
    final strings = context.paywallStrings;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final outcome = await ref.read(subscriptionServiceProvider).purchase(plan);
    if (!mounted) return;
    switch (outcome) {
      case PurchaseOutcome.success:
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(strings.purchaseSuccess)));
        navigator.pop(true);
      case PurchaseOutcome.cancelled || PurchaseOutcome.busy:
        break;
      case PurchaseOutcome.pending:
        _toast(strings.purchasePending);
      case PurchaseOutcome.unavailable:
        _toast(strings.unavailable);
      case PurchaseOutcome.failed:
        _toast(strings.purchaseFailed);
    }
  }

  Future<void> _restore() async {
    final strings = context.paywallStrings;
    final outcome = await ref.read(subscriptionServiceProvider).restore();
    if (!mounted) return;
    switch (outcome) {
      case RestoreOutcome.restored:
        _toast(strings.restored);
      case RestoreOutcome.nothingToRestore:
        _toast(strings.nothingToRestore);
      case RestoreOutcome.failed:
        _toast(strings.restoreFailed);
      case RestoreOutcome.unavailable:
        _toast(strings.unavailable);
      case RestoreOutcome.busy:
        break;
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.headline, required this.subhead, this.recap});

  final String headline;
  final String subhead;
  final String? recap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.gold, AppColors.goldDeep],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.workspace_premium,
                size: 28,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          headline,
          key: const ValueKey('paywall-headline'),
          style: theme.textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subhead,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (recap != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('paywall-recap'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.videocam_outlined,
                  size: 20,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recap!,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits({required this.strings});

  final PaywallStrings strings;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.videocam_outlined, strings.benefitLive, strings.benefitLiveSub),
      (
        Icons.format_list_numbered,
        strings.benefitCandidates,
        strings.benefitCandidatesSub,
      ),
      (Icons.today_outlined, strings.benefitToday, strings.benefitTodaySub),
      (
        Icons.calculate_outlined,
        strings.benefitWinScore,
        strings.benefitWinScoreSub,
      ),
      (Icons.block, strings.benefitNoAds, strings.benefitNoAdsSub),
    ];
    return AppCard(
      key: const ValueKey('paywall-benefits'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        children: [
          for (final (icon, title, subtitle) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Icon(icon, size: 20, color: AppColors.jadeDeep),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
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

class _NotReady extends StatelessWidget {
  const _NotReady({required this.strings});

  final PaywallStrings strings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('paywall-not-ready'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        children: [
          Text(strings.notReadyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(strings.notReadyBody, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _Plans extends StatelessWidget {
  const _Plans({
    required this.service,
    required this.selected,
    required this.busy,
    required this.onSelect,
    required this.onPurchase,
  });

  final SubscriptionService service;
  final PlanKind? selected;
  final bool busy;
  final ValueChanged<PlanKind> onSelect;
  final ValueChanged<StorePlan> onPurchase;

  @override
  Widget build(BuildContext context) {
    final strings = context.paywallStrings;
    // 初期化に失敗して購入できない状態は、プランを読み込めなかったときと同じ扱い（再試行）。
    final plansState = !service.available && !service.initializing
        ? PlansState.failed
        : service.plansState;
    switch (plansState) {
      case PlansState.idle:
      case PlansState.loading:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Semantics(
              label: strings.loadingPlans,
              child: const CircularProgressIndicator(),
            ),
          ),
        );
      case PlansState.failed:
        return Column(
          key: const ValueKey('paywall-plans-failed'),
          children: [
            Text(strings.plansFailed, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const ValueKey('paywall-retry'),
              onPressed: () => unawaited(service.loadPlans(force: true)),
              child: Text(strings.retry),
            ),
          ],
        );
      case PlansState.ready:
        break;
    }
    final plans = service.plans;
    final defaultPlan =
        plans
            .where((p) => p.kind == PlanKind.monthly && p.hasTrial)
            .firstOrNull ??
        plans.firstOrNull;
    final current =
        plans.where((p) => p.kind == selected).firstOrNull ?? defaultPlan;
    if (current == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final plan in plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PlanCard(
              plan: plan,
              selected: plan.kind == current.kind,
              onTap: busy ? null : () => onSelect(plan.kind),
            ),
          ),
        const SizedBox(height: 6),
        FilledButton(
          key: const ValueKey('paywall-cta'),
          onPressed: busy ? null : () => onPurchase(current),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
            textStyle: Theme.of(context).textTheme.titleMedium,
          ),
          child: Text(
            current.hasTrial
                ? strings.ctaTrial(current.trialDays!)
                : strings.ctaSubscribe,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          strings.disclosure(
            current.priceString,
            yearly: current.kind == PlanKind.yearly,
            trialDays: current.trialDays,
          ),
          key: const ValueKey('paywall-disclosure'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final StorePlan plan;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final strings = context.paywallStrings;
    final theme = Theme.of(context);
    final yearly = plan.kind == PlanKind.yearly;
    final title = yearly ? strings.yearly : strings.monthly;
    final price = yearly
        ? strings.perYear(plan.priceString)
        : strings.perMonth(plan.priceString);
    final sub = <String>[
      if (plan.hasTrial) strings.trialBadge(plan.trialDays!),
      if (yearly && plan.pricePerMonthString != null)
        strings.yearlyPerMonth(plan.pricePerMonthString!),
    ].join('  ');
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? Color.alphaBlend(
                theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
                theme.colorScheme.surfaceContainerLowest,
              )
            : theme.colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          key: ValueKey('paywall-plan-${plan.kind.name}'),
          borderRadius: AppRadius.lgAll,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              borderRadius: AppRadius.lgAll,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 狭い幅・大きな文字でもあふれないよう、入らなければチップを次の行へ回す。
                      Wrap(
                        key: ValueKey('paywall-plan-${plan.kind.name}-title'),
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title, style: theme.textTheme.titleMedium),
                          if (yearly) ProBadge(label: strings.bestValue),
                        ],
                      ),
                      if (sub.isNotEmpty)
                        Text(sub, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  price,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProStatus extends StatelessWidget {
  const _ProStatus({required this.entitlement, required this.onManage});

  final EntitlementState entitlement;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final strings = context.paywallStrings;
    final theme = Theme.of(context);
    final title = entitlement.source == EntitlementSource.review
        ? strings.proReviewTitle
        : entitlement.source == EntitlementSource.referral
        ? strings.proReferralTitle
        : entitlement.trial
        ? strings.proTrialTitle
        : strings.proActiveTitle;
    return Container(
      key: const ValueKey('paywall-pro-active'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.goldTint,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (entitlement.until != null)
            Text(
              strings.proUntil(formatPaywallDate(entitlement.until!)),
              style: theme.textTheme.bodyMedium,
            ),
          if (entitlement.source == EntitlementSource.store)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('paywall-manage'),
                onPressed: onManage,
                child: Text(strings.manageSubscription),
              ),
            ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.strings,
    required this.canRestore,
    required this.busy,
    required this.onRestore,
    required this.onOpen,
    required this.onManage,
  });

  final PaywallStrings strings;
  final bool canRestore;
  final bool busy;
  final VoidCallback onRestore;
  final void Function(Uri uri) onOpen;
  final VoidCallback onManage;

  // 審査で必要な「購入の復元」「解約方法」「規約類」は残し、復元だけをボタンに、
  // 残りは小さな文字のリンクを 1 か所にまとめる。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextButton.styleFrom(
      foregroundColor: theme.colorScheme.onSurfaceVariant,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      textStyle: theme.textTheme.labelMedium?.copyWith(
        decoration: TextDecoration.underline,
      ),
    );
    Widget link(String key, String label, VoidCallback onTap) => TextButton(
      key: ValueKey(key),
      style: linkStyle,
      onPressed: onTap,
      child: Text(label),
    );
    return Column(
      children: [
        if (canRestore)
          TextButton.icon(
            key: const ValueKey('paywall-restore'),
            onPressed: busy ? null : onRestore,
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: Text(strings.restore),
          ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          strings.cancelInfoFor(theme.platform),
          key: const ValueKey('paywall-cancel-info'),
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            if (canRestore)
              link('paywall-manage-link', strings.manageSubscription, onManage),
            link(
              'paywall-terms',
              strings.terms,
              () => onOpen(LegalLinks.terms),
            ),
            link(
              'paywall-privacy',
              strings.privacy,
              () => onOpen(LegalLinks.privacy),
            ),
            link(
              'paywall-tokushoho',
              strings.tokushoho,
              () => onOpen(LegalLinks.tokushoho),
            ),
          ],
        ),
      ],
    );
  }
}
