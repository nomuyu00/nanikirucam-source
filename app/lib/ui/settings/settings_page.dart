import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analytics/analytics_widgets.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/app_restart.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/url_opener.dart';
import 'package:nanikiru_cam/l10n/strings/settings_strings.dart';
import 'package:nanikiru_cam/problems/blocked_authors_section.dart';
import 'package:nanikiru_cam/purchase/paywall_page.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:nanikiru_cam/purchase/review_access_page.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/referral/referral_section.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_gate.dart';
import 'package:nanikiru_cam/ui/settings/data_deletion.dart';
import 'package:nanikiru_cam/ui/settings/settings_subpages.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// アプリのバージョン表示用。テストでは差し替える。
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// 設定（仕様 6.11）。ルール・通知・言語・分析の同意・招待コード・購入の復元と解約・
/// データ削除・規約類・バージョン。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Uri uri) => ref.read(urlOpenerProvider)(uri);

  Future<void> _restore() async {
    final strings = context.settingsStrings;
    setState(() => _busy = true);
    final outcome = await ref.read(subscriptionServiceProvider).restore();
    if (!mounted) return;
    setState(() => _busy = false);
    _toast(switch (outcome) {
      RestoreOutcome.restored => strings.restored,
      RestoreOutcome.nothingToRestore => strings.nothingToRestore,
      RestoreOutcome.failed => strings.restoreFailed,
      RestoreOutcome.unavailable => strings.storeUnavailable,
      RestoreOutcome.busy => strings.restoring,
    });
  }

  Future<void> _deleteData() async {
    final strings = context.settingsStrings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.deleteConfirmTitle),
        content: SingleChildScrollView(
          child: Text(
            ref.read(onlineFeaturesProvider)
                ? strings.deleteConfirmBody
                : strings.deleteConfirmBodyLocal,
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('settings-delete-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            key: const ValueKey('settings-delete-confirm'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.deleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await ref.read(dataDeletionProvider).run();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.ok) {
      _toast(
        ref.read(onlineFeaturesProvider)
            ? strings.deleteFailed
            : strings.deleteFailedLocal,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Text(strings.deleteDone),
        actions: [
          TextButton(
            key: const ValueKey('settings-delete-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(MaterialLocalizations.of(context).okButtonLabel),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // メモリ上の状態ごと作り直して、最初の画面（Onboarding）に戻る。
    if (!AppRestart.restart(context)) {
      ref.invalidate(onboardingCompletedProvider);
      unawaited(
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(Routes.home, (_) => false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.settingsStrings;
    final settings = ref.watch(appSettingsProvider);
    final entitlement = ref.watch(entitlementsProvider);
    final service = ref.watch(subscriptionServiceProvider);
    final locale = ref.watch(appLocaleProvider);
    final consent = ref.watch(consentStateProvider);
    final version = ref.watch(appVersionProvider);
    final online = ref.watch(onlineFeaturesProvider);
    final review = ref.watch(reviewAccessProvider);
    // 通知の行に「n 件オン」を出す（サーバーなしの版は週間・回答到達を数えない）。
    final notificationsOn = [
      settings.notifyDaily,
      if (online) ...[settings.notifyWeekly, settings.notifyAnswers],
      settings.notifyStreak,
      settings.notifyLiveSummary,
    ];

    final planTitle = switch (entitlement) {
      EntitlementState(pro: false) => strings.planFree,
      EntitlementState(source: EntitlementSource.referral) =>
        strings.planProReferral,
      EntitlementState(source: EntitlementSource.review) =>
        strings.planProReview,
      EntitlementState(trial: true) => strings.planProTrial,
      _ => strings.planPro,
    };

    final theme = Theme.of(context);
    final error = theme.colorScheme.error;
    const openIcon = Icon(Icons.open_in_new_rounded, size: 18);

    return Scaffold(
      appBar: AppBar(title: Text(strings.title)),
      body: SafeArea(
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.gutter,
                  0,
                  AppSpacing.gutter,
                  AppSpacing.xxl,
                ),
                children: [
                  // --- プラン ---
                  GroupedSection(
                    title: strings.sectionPlan,
                    children: [
                      ListTile(
                        key: const ValueKey('settings-plan'),
                        leading: _PlanMark(pro: entitlement.pro),
                        title: Text(planTitle),
                        subtitle: entitlement.pro
                            ? (entitlement.until != null
                                  ? Text(
                                      strings.planUntil(
                                        formatPaywallDate(entitlement.until!),
                                      ),
                                    )
                                  : null)
                            : Text(strings.planUpgrade),
                        trailing: entitlement.pro
                            ? null
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: entitlement.pro
                            ? null
                            : () => Navigator.of(context).pushNamed(
                                Routes.paywall,
                                arguments: const PaywallArgs(
                                  trigger: PaywallTrigger.settings,
                                ),
                              ),
                      ),
                      if (service.configured) ...[
                        ListTile(
                          key: const ValueKey('settings-restore'),
                          leading: const Icon(Icons.restore_rounded),
                          title: Text(strings.restorePurchases),
                          enabled: !_busy,
                          onTap: _busy ? null : () => unawaited(_restore()),
                        ),
                        ListTile(
                          key: const ValueKey('settings-manage-subscription'),
                          leading: const Icon(Icons.manage_accounts_outlined),
                          title: Text(strings.manageSubscription),
                          trailing: openIcon,
                          onTap: () =>
                              unawaited(_open(subscriptionManagementUri())),
                        ),
                      ],
                    ],
                  ),

                  // --- アプリの設定（項目の多いものはサブページへ。仕様 6.11） ---
                  GroupedSection(
                    title: strings.sectionPreferences,
                    children: [
                      _NavRow(
                        key: const ValueKey('settings-open-live'),
                        icon: Icons.videocam_outlined,
                        title: strings.sectionLive,
                        subtitle: strings.liveRowSummary(
                          switch (settings.liveDefaultAxis) {
                            StrategyAxis.speed => strings.axisSpeed,
                            StrategyAxis.points => strings.axisPoints,
                            StrategyAxis.balance => strings.axisBalance,
                          },
                          settings.liveHaptics,
                        ),
                        page: const LiveSettingsPage(),
                      ),
                      _NavRow(
                        key: const ValueKey('settings-open-notifications'),
                        icon: Icons.notifications_none_rounded,
                        title: strings.sectionNotifications,
                        subtitle: strings.notificationsRowSummary(
                          notificationsOn.where((on) => on).length,
                          notificationsOn.length,
                        ),
                        page: const NotificationSettingsPage(),
                      ),
                      _NavRow(
                        key: const ValueKey('settings-open-rules'),
                        icon: Icons.rule_rounded,
                        title: strings.sectionRulesCamera,
                        subtitle: strings.rulesRowSummary(
                          redFives: settings.redFives,
                          openTanyao: settings.openTanyao,
                          quickCapture: settings.quickCapture,
                        ),
                        page: const RulesSettingsPage(),
                      ),
                    ],
                  ),

                  // --- 言語 ---
                  GroupedSection(
                    title: strings.sectionLanguage,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SegmentedButton<String>(
                          key: const ValueKey('settings-language'),
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: 'system',
                              label: Text(strings.languageSystem),
                            ),
                            ButtonSegment(
                              value: 'ja',
                              label: Text(strings.languageJapanese),
                            ),
                            ButtonSegment(
                              value: 'en',
                              label: Text(strings.languageEnglish),
                            ),
                          ],
                          selected: {locale?.languageCode ?? 'system'},
                          onSelectionChanged: (selection) {
                            final code = selection.first;
                            unawaited(
                              ref
                                  .read(appLocaleProvider.notifier)
                                  .setLocale(
                                    code == 'system' ? null : Locale(code),
                                  ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  // --- プライバシー ---
                  GroupedSection(
                    title: strings.sectionPrivacy,
                    children: [
                      const AnalyticsSettingsTile(),
                      if (consent.privacyOptionsRequired)
                        ListTile(
                          key: const ValueKey('settings-ad-privacy'),
                          leading: const Icon(Icons.privacy_tip_outlined),
                          title: Text(strings.adPrivacy),
                          subtitle: Text(strings.adPrivacySub),
                          onTap: () => unawaited(
                            ref
                                .read(consentManagerProvider)
                                .showPrivacyOptions(),
                          ),
                        ),
                    ],
                  ),

                  // --- 招待コード（サーバーが要る。サーバーなしの版では出さない） ---
                  if (online) ...[
                    GroupedSection(
                      title: strings.sectionReferral,
                      children: const [ReferralSection()],
                    ),

                    // --- ブロック中の出題者（App Store 審査ガイドライン 1.2）---
                    // 他人の公開問題が出るのはオンライン機能があるときだけ。
                    const BlockedAuthorsSection(),
                  ],

                  // --- データ ---
                  GroupedSection(
                    title: strings.sectionData,
                    children: [
                      ListTile(
                        key: const ValueKey('settings-delete-data'),
                        leading: Icon(
                          Icons.delete_outline_rounded,
                          color: error,
                        ),
                        title: Text(
                          strings.deleteData,
                          style: TextStyle(color: error),
                        ),
                        subtitle: Text(
                          online
                              ? strings.deleteDataSub
                              : strings.deleteDataSubLocal,
                        ),
                        enabled: !_busy,
                        onTap: _busy ? null : () => unawaited(_deleteData()),
                      ),
                    ],
                  ),

                  // --- このアプリについて ---
                  GroupedSection(
                    title: strings.sectionAbout,
                    children: [
                      if (review.available)
                        ListTile(
                          key: const ValueKey('settings-review-access'),
                          title: Text(strings.reviewAccess),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const ReviewAccessPage(),
                            ),
                          ),
                        ),
                      ListTile(
                        key: const ValueKey('settings-terms'),
                        title: Text(strings.terms),
                        trailing: openIcon,
                        onTap: () => unawaited(_open(LegalLinks.terms)),
                      ),
                      ListTile(
                        key: const ValueKey('settings-privacy'),
                        title: Text(strings.privacyPolicy),
                        trailing: openIcon,
                        onTap: () => unawaited(_open(LegalLinks.privacy)),
                      ),
                      ListTile(
                        key: const ValueKey('settings-tokushoho'),
                        title: Text(strings.tokushoho),
                        trailing: openIcon,
                        onTap: () => unawaited(_open(LegalLinks.tokushoho)),
                      ),
                      ListTile(
                        key: const ValueKey('settings-version'),
                        title: Text(strings.version),
                        trailing: Text(version.valueOrNull ?? '-'),
                      ),
                      ListTile(
                        key: const ValueKey('settings-source'),
                        title: Text(strings.sourceCode),
                        trailing: openIcon,
                        onTap: () => unawaited(_open(LegalLinks.source)),
                      ),
                      ListTile(
                        key: const ValueKey('settings-licenses'),
                        title: Text(strings.licenses),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showLicensePage(
                          context: context,
                          applicationName: 'なにきるカム',
                          applicationLegalese: strings.datasetCredit,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// プランの印（Pro はゴールドの塗り、無料はゴールドの淡い面）。
class _PlanMark extends StatelessWidget {
  const _PlanMark({required this.pro});

  final bool pro;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: pro ? AppColors.gold : AppColors.goldTint,
        borderRadius: AppRadius.smAll,
      ),
      child: Icon(
        pro ? Icons.workspace_premium : Icons.workspace_premium_outlined,
        color: pro ? Colors.white : AppColors.goldDeep,
      ),
    );
  }
}

/// サブページへ進む行（左に色つきの印、右に山形）。
class _NavRow extends StatelessWidget {
  const _NavRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget page;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(icon, size: 20, color: scheme.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => page)),
    );
  }
}
