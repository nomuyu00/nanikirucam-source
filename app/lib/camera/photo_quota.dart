import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/strings/camera_strings.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';

/// 写真解析の無料枠（仕様 3.2・5 章、設計書 11 章）の画面部品。
///
/// 消費の位置: 認識（`RecognitionLoadingPage`）の前に尽きていないかを確かめ、認識に
/// 成功したら `tryConsume()` で 1 回使う（認識に失敗したときは使わない）。手入力・
/// クイズ・今日の問題は使わない。尽きていたら [QuotaExhaustedPanel] を出す。

/// 撮影画面に出す「今日の写真解析 残り n / 5 回」。Pro は「無制限」。
class QuotaRemainingChip extends ConsumerWidget {
  const QuotaRemainingChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(quotaProvider);
    final strings = context.cameraStrings;
    final text = quota.unlimited
        ? strings.quotaUnlimited
        : strings.quotaRemaining(quota.remaining, quota.limit);
    return Container(
      key: const ValueKey('camera-quota'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.liveScrim,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

/// 無料枠を使い切ったとき（`quota_exhausted`）: 動画で +3 回、Pro（Paywall
/// `quotaExhausted`）、手入力で続ける。
///
/// 枠が戻った（動画の報酬・Pro になった・日付が変わった）ら [onUnlocked] を呼ぶ。
class QuotaExhaustedPanel extends ConsumerStatefulWidget {
  const QuotaExhaustedPanel({
    super.key,
    required this.onUnlocked,
    this.onManualInput,
  });

  final VoidCallback onUnlocked;
  final VoidCallback? onManualInput;

  @override
  ConsumerState<QuotaExhaustedPanel> createState() =>
      _QuotaExhaustedPanelState();
}

class _QuotaExhaustedPanelState extends ConsumerState<QuotaExhaustedPanel> {
  bool _showingVideo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(appAnalyticsProvider)
            .logEvent(
              AnalyticsEvent.quotaExhausted,
              parameters: {'source': 'photo'},
            ),
      );
    });
  }

  Future<void> _watchVideo() async {
    final gate = ref.read(rewardedGateProvider);
    setState(() => _showingVideo = true);
    final rewarded = await gate.show(RewardKind.quota);
    if (!mounted) return;
    setState(() => _showingVideo = false);
    if (!rewarded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.cameraStrings.quotaVideoFailed)),
      );
      return;
    }
    // rewarded_granted は RewardedGate が記録する。付与で exhausted が false になると、下の listen が onUnlocked を呼ぶ。
    await ref.read(quotaProvider.notifier).grantRewarded();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(quotaProvider.select((q) => q.exhausted), (prev, next) {
      if (prev == true && !next) widget.onUnlocked();
    });
    final strings = context.cameraStrings;
    final quota = ref.watch(quotaProvider);
    final gate = ref.watch(rewardedGateProvider);
    final canReward =
        quota.canGrantRewarded &&
        gate.isReady(RewardKind.quota) &&
        !_showingVideo;
    return Padding(
      key: const ValueKey('quota-exhausted'),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            strings.quotaExhaustedTitle(quota.dailyLimit),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(strings.quotaExhaustedBody, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            key: const ValueKey('quota-reward'),
            onPressed: canReward ? _watchVideo : null,
            icon: const Icon(Icons.ondemand_video),
            label: Text(strings.quotaWatchVideo),
          ),
          if (!quota.canGrantRewarded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                strings.quotaRewardUsed,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const ValueKey('quota-paywall'),
            onPressed: () => Navigator.of(context).pushNamed(
              Routes.paywall,
              arguments: const PaywallArgs(
                trigger: PaywallTrigger.quotaExhausted,
              ),
            ),
            child: Text(strings.quotaGoPro),
          ),
          if (widget.onManualInput != null)
            TextButton(
              key: const ValueKey('quota-manual'),
              onPressed: widget.onManualInput,
              child: Text(strings.quotaManual),
            ),
        ],
      ),
    );
  }
}
