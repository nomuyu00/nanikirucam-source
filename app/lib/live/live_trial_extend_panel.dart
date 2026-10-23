import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/l10n/strings/live_strings.dart';
import 'package:nanikiru_cam/live/live_providers.dart';
import 'package:nanikiru_cam/live/live_trial.dart';

/// 無料のライブ体験を使い切ったときの「動画を見てライブを延長（+1〜3分）」。
///
/// 動画広告（[RewardKind.liveTrial]）を最後まで見ると、見た時間（広告の長さの目安）に応じて
/// 1〜3 分延長する（[LiveTrial.bonusSecondsFor]）。1 日 [LiveTrial.maxBonusGrantsPerDay] 回まで。
/// **ライブ画面の中では使わない**（ライブ中は広告を出さない）。Paywall（体験終了）と Home（使い切り
/// 表示）に置く。Pro・広告が使えない（同意なし等）・体験が読み込めていないときは何も描かない。
class LiveTrialExtendPanel extends ConsumerStatefulWidget {
  const LiveTrialExtendPanel({
    super.key,
    required this.analyticsTrigger,
    this.onExtended,
    this.onlyWhenExhausted = true,
  });

  /// 計測の `trigger`（`AppAnalytics` の許可リストの値。Paywall は `live_trial`、Home は `home`）。
  final String analyticsTrigger;

  /// 延長できたあと（延長した秒数）。Paywall はここでライブへ戻る。
  final ValueChanged<int>? onExtended;

  /// true なら、体験を使い切っているときだけ出す。
  final bool onlyWhenExhausted;

  @override
  ConsumerState<LiveTrialExtendPanel> createState() =>
      _LiveTrialExtendPanelState();
}

class _LiveTrialExtendPanelState extends ConsumerState<LiveTrialExtendPanel> {
  bool _showingVideo = false;

  Future<void> _watchVideo() async {
    // 動画を見ている間に画面が閉じても付与できるよう、必要なものを先に控える。
    final gate = ref.read(rewardedGateProvider);
    final trialFuture = ref.read(liveTrialProvider.future);
    final pro = ref.read(entitlementsProvider).pro;
    final sink = ref.read(analyticsSinkProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final strings = context.liveStrings;
    setState(() => _showingVideo = true);

    final result = await gate.showTimed(RewardKind.liveTrial);
    if (mounted) setState(() => _showingVideo = false);
    if (!result.earned) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(strings.extendFailed)));
      return;
    }

    // rewarded_granted{reward: live_trial} は RewardedGate が記録する。
    final seconds = LiveTrial.bonusSecondsFor(result.watched);
    final trial = await trialFuture;
    final before = trial.load(pro: pro);
    final after = await trial.grantBonus(seconds, pro: pro);
    container.invalidate(liveTrialStateProvider);
    if (after.bonusGrants == before.bonusGrants) {
      // 上限に達していた（別の経路で先に延長された等）。付与はしていない。
      return;
    }
    sink(AnalyticsEvent.liveTrialExtended, {
      'bonus_s': seconds,
      'trigger': widget.analyticsTrigger,
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(strings.extended(seconds))));
    if (mounted) widget.onExtended?.call(seconds);
  }

  @override
  Widget build(BuildContext context) {
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final adsEnabled = ref.watch(adsEnabledProvider);
    final trial = ref.watch(liveTrialStateProvider).valueOrNull;
    if (pro || !adsEnabled || trial == null) return const SizedBox.shrink();
    if (widget.onlyWhenExhausted && !trial.exhausted) {
      return const SizedBox.shrink();
    }

    final strings = context.liveStrings;
    final theme = Theme.of(context);
    final Widget body;
    if (!trial.canExtend) {
      body = Text(
        strings.extendLimit,
        key: const ValueKey('live-extend-limit'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      );
    } else {
      final gate = ref.watch(rewardedGateProvider);
      final ready = gate.isReady(RewardKind.liveTrial);
      final canTap = ready && !_showingVideo;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('live-extend-button'),
            onPressed: canTap ? _watchVideo : null,
            icon: const Icon(Icons.ondemand_video),
            label: Text(strings.extendButton),
          ),
          const SizedBox(height: 4),
          Text(
            ready
                ? strings.extendHint(
                    LiveTrial.maxBonusGrantsPerDay - trial.bonusGrants,
                  )
                : strings.extendLoading,
            key: ValueKey(
              ready ? 'live-extend-hint' : 'live-extend-loading',
            ),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      );
    }
    return Padding(
      key: const ValueKey('live-extend-panel'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: body,
    );
  }
}
