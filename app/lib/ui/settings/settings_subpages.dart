import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/l10n/strings/settings_strings.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';

// 設定のサブページ（仕様 6.11）。トップ（SettingsPage）は見つけやすさを優先して
// 行の一覧にし、項目の多いライブナビ・通知・ルールと撮影をここに分ける。
// 各スイッチのキー（`settings-live-haptics` など）はトップにあったときと同じ。

/// 短いお知らせ（SnackBar）。
void showSettingsToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// サブページの骨組み（見出しと、余白をとった一覧）。
class _SubpageScaffold extends StatelessWidget {
  const _SubpageScaffold({
    required this.pageKey,
    required this.title,
    required this.children,
  });

  final Key pageKey;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: pageKey,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.xxl,
          ),
          children: children,
        ),
      ),
    );
  }
}

/// ライブナビ: 最初に表示する軸・振動・案内音・明るさ固定・置き方の案内の再表示。
class LiveSettingsPage extends ConsumerWidget {
  const LiveSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.settingsStrings;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final theme = Theme.of(context);
    return _SubpageScaffold(
      pageKey: const ValueKey('settings-live-page'),
      title: strings.sectionLive,
      children: [
        GroupedSection(
          title: strings.liveDefaultAxis,
          footer: strings.liveDefaultAxisSub,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: SegmentedButton<StrategyAxis>(
                key: const ValueKey('settings-live-axis'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: StrategyAxis.speed,
                    label: Text(strings.axisSpeed),
                  ),
                  ButtonSegment(
                    value: StrategyAxis.points,
                    label: Text(strings.axisPoints),
                  ),
                  ButtonSegment(
                    value: StrategyAxis.balance,
                    label: Text(strings.axisBalance),
                  ),
                ],
                selected: {settings.liveDefaultAxis},
                onSelectionChanged: (selection) => notifier.update(
                  (s) => s.copyWith(liveDefaultAxis: selection.first),
                ),
              ),
            ),
          ],
        ),
        GroupedSection(
          title: strings.sectionLiveFeedback,
          children: [
            SwitchListTile(
              key: const ValueKey('settings-live-haptics'),
              secondary: const Icon(Icons.vibration_rounded),
              title: Text(strings.liveHaptics),
              subtitle: Text(strings.liveHapticsSub),
              value: settings.liveHaptics,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(liveHaptics: value)),
            ),
            SwitchListTile(
              key: const ValueKey('settings-live-sound'),
              secondary: const Icon(Icons.volume_up_outlined),
              title: Text(strings.liveSound),
              subtitle: Text(strings.liveSoundSub),
              value: settings.liveSound,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(liveSound: value)),
            ),
            SwitchListTile(
              key: const ValueKey('settings-live-brightness'),
              secondary: const Icon(Icons.brightness_high_outlined),
              title: Text(strings.liveLockBrightness),
              subtitle: Text(strings.liveLockBrightnessSub),
              value: settings.liveLockBrightness,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(liveLockBrightness: value)),
            ),
          ],
        ),
        GroupedSection(
          title: strings.sectionLiveGuide,
          children: [
            ListTile(
              key: const ValueKey('settings-live-guide'),
              leading: const Icon(Icons.help_outline_rounded),
              title: Text(strings.liveGuide),
              subtitle: Text(strings.liveGuideSub),
              trailing: Icon(
                Icons.replay_rounded,
                color: theme.colorScheme.primary,
              ),
              onTap: () async {
                await resetLiveGuide(ref);
                if (context.mounted) {
                  showSettingsToast(context, strings.liveGuideReset);
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// 通知の設定を変える。オンにしたときは OS の許可を求め、拒否されたら案内する。
Future<void> setNotificationSetting(
  BuildContext context,
  WidgetRef ref,
  AppSettings Function(AppSettings current) change, {
  required bool enabled,
}) async {
  final strings = context.settingsStrings;
  ref.read(appSettingsProvider.notifier).update(change);
  if (!enabled) return;
  final coordinator = ref.read(notificationCoordinatorProvider);
  if (await coordinator.permission() == NotificationPermission.granted) {
    return;
  }
  final result = await coordinator.requestPermission();
  if (context.mounted && result != NotificationPermission.granted) {
    showSettingsToast(context, strings.notificationsDenied);
  }
}

/// 通知: 今日の問題・（サーバーありの版のみ）週間と回答到達・ストリーク・対局サマリー。
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.settingsStrings;
    final settings = ref.watch(appSettingsProvider);
    final online = ref.watch(onlineFeaturesProvider);

    SwitchListTile tile({
      required String key,
      required IconData icon,
      required String title,
      required String subtitle,
      required bool value,
      required AppSettings Function(AppSettings s, bool v) change,
    }) => SwitchListTile(
      key: ValueKey(key),
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => unawaited(
        setNotificationSetting(context, ref, (s) => change(s, v), enabled: v),
      ),
    );

    return _SubpageScaffold(
      pageKey: const ValueKey('settings-notifications-page'),
      title: strings.sectionNotifications,
      children: [
        GroupedSection(
          title: strings.sectionNotificationsProblems,
          children: [
            tile(
              key: 'settings-notify-daily',
              icon: Icons.today_outlined,
              title: strings.notifyDaily,
              subtitle: strings.notifyDailySub,
              value: settings.notifyDaily,
              change: (s, v) => s.copyWith(notifyDaily: v),
            ),
            // 週間・回答到達の通知はサーバー（FCM）から届く。サーバーなしの版では出さない。
            if (online) ...[
              tile(
                key: 'settings-notify-weekly',
                icon: Icons.date_range_outlined,
                title: strings.notifyWeekly,
                subtitle: strings.notifyWeeklySub,
                value: settings.notifyWeekly,
                change: (s, v) => s.copyWith(notifyWeekly: v),
              ),
              tile(
                key: 'settings-notify-answers',
                icon: Icons.forum_outlined,
                title: strings.notifyAnswers,
                subtitle: strings.notifyAnswersSub,
                value: settings.notifyAnswers,
                change: (s, v) => s.copyWith(notifyAnswers: v),
              ),
            ],
            tile(
              key: 'settings-notify-streak',
              icon: Icons.local_fire_department_outlined,
              title: strings.notifyStreak,
              subtitle: strings.notifyStreakSub,
              value: settings.notifyStreak,
              change: (s, v) => s.copyWith(notifyStreak: v),
            ),
          ],
        ),
        GroupedSection(
          title: strings.sectionLive,
          children: [
            tile(
              key: 'settings-notify-live-summary',
              icon: Icons.insights_outlined,
              title: strings.notifyLiveSummary,
              subtitle: strings.notifyLiveSummarySub,
              value: settings.notifyLiveSummary,
              change: (s, v) => s.copyWith(notifyLiveSummary: v),
            ),
          ],
        ),
      ],
    );
  }
}

/// ルールと撮影: 赤ドラ・喰いタン・撮るだけモード。
class RulesSettingsPage extends ConsumerWidget {
  const RulesSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.settingsStrings;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    return _SubpageScaffold(
      pageKey: const ValueKey('settings-rules-page'),
      title: strings.sectionRulesCamera,
      children: [
        GroupedSection(
          title: strings.sectionRules,
          children: [
            SwitchListTile(
              key: const ValueKey('settings-red-fives'),
              secondary: const Icon(Icons.filter_5_outlined),
              title: Text(strings.redFives),
              subtitle: Text(strings.redFivesSub),
              value: settings.redFives,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(redFives: value)),
            ),
            SwitchListTile(
              key: const ValueKey('settings-open-tanyao'),
              secondary: const Icon(Icons.call_split_rounded),
              title: Text(strings.openTanyao),
              subtitle: Text(strings.openTanyaoSub),
              value: settings.openTanyao,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(openTanyao: value)),
            ),
          ],
        ),
        GroupedSection(
          title: strings.sectionCamera,
          children: [
            SwitchListTile(
              key: const ValueKey('settings-quick-capture'),
              secondary: const Icon(Icons.burst_mode_outlined),
              title: Text(strings.quickCapture),
              subtitle: Text(strings.quickCaptureSub),
              value: settings.quickCapture,
              onChanged: (value) =>
                  notifier.update((s) => s.copyWith(quickCapture: value)),
            ),
          ],
        ),
      ],
    );
  }
}
