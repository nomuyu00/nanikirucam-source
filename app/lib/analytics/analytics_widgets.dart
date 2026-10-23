// 流用元: reference/agari_cam/lib/analytics/analytics_widgets.dart（2026-10-21 時点）
// 改修: アプリ名・文言をなにきるカム用に差し替え（言語は CommonStrings.isEnglish で判定）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';

class AnalyticsConsentCard extends ConsumerWidget {
  const AnalyticsConsentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(appAnalyticsProvider);
    if (!analytics.available ||
        (analytics.hasChoice && !analytics.consentUpdateFailed)) {
      return const SizedBox.shrink();
    }
    final english = context.commonStrings.isEnglish;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              english
                  ? 'Help improve ${context.commonStrings.appName}'
                  : '${context.commonStrings.appName}の改善に協力',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              english
                  ? 'May we use Google Analytics to measure feature use and failures? Photos and tile arrangements are never sent. Optional; you can change this in Settings.'
                  : 'Google Analyticsで機能の利用状況や失敗を分析してもよいですか？写真・牌の並びは送信しません。任意で、設定からいつでも変更できます。',
            ),
            if (analytics.consentUpdateFailed)
              _AnalyticsRetry(analytics: analytics, english: english),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () => unawaited(analytics.setEnabled(false)),
                  child: Text(english ? 'Do not allow' : '許可しない'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final route = ModalRoute.of(context);
                    await analytics.setEnabled(true);
                    // Consent can finish after the user has left this page.
                    if (!context.mounted || route?.isCurrent != true) return;
                    await analytics.logScreen(Routes.home);
                  },
                  child: Text(english ? 'Allow analytics' : '分析を許可'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AnalyticsSettingsTile extends ConsumerWidget {
  const AnalyticsSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analytics = ref.watch(appAnalyticsProvider);
    final english = context.commonStrings.isEnglish;
    return Column(
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.insights_outlined),
          title: Text(english ? 'Help improve the app' : '利用状況の分析に協力'),
          subtitle: Text(
            english
                ? 'Allow Google Analytics to measure usage and failures. Photos and tile arrangements are never sent. Turning this off stops future analytics collection.'
                : 'Google Analyticsで利用状況や失敗を分析します。写真・牌の並びは送信しません。オフにすると以後の分析データ収集を停止します。',
          ),
          value: analytics.enabled,
          onChanged: analytics.ready && analytics.available
              ? (enabled) => unawaited(analytics.setEnabled(enabled))
              : null,
        ),
        if (analytics.consentUpdateFailed)
          _AnalyticsRetry(analytics: analytics, english: english),
      ],
    );
  }
}

class _AnalyticsRetry extends StatelessWidget {
  const _AnalyticsRetry({required this.analytics, required this.english});
  final AppAnalytics analytics;
  final bool english;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          english
              ? 'Could not finish changing analytics settings. Please retry.'
              : '分析設定の変更を完了できませんでした。再試行してください。',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: () => unawaited(analytics.setEnabled(analytics.enabled)),
          child: Text(english ? 'Retry' : '再試行'),
        ),
      ],
    ),
  );
}
