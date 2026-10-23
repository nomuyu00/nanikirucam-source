import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/remote_config.dart';
import 'package:nanikiru_cam/l10n/strings/settings_strings.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/purchase/paywall_page.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/referral/referral_service.dart';

/// 起動時に動かすサービスをまとめて始める。`lib/app.dart` の `NanikiruCamApp` が
/// `ref.watch(appBootstrapProvider)` で 1 回だけ読む。
///
/// - 課金（RevenueCat）: キーが未設定なら何もしない。Pro の判定は [entitlementsProvider]。
/// - 通知: FCM のトピック・トークン、ローカル通知の予約、通知タップの遷移。
/// - Remote Config: モデルの設定を反映（Firebase 有効時のみ）。
/// - 紹介: リンクから届いて保留されたコードを、サインインできたら自動で使う。
/// - アプリに戻ったとき: 課金状態の再確認と通知の予約し直し。
final appBootstrapProvider = Provider<void>((ref) {
  ref.read(entitlementsProvider);
  ref.read(notificationCoordinatorProvider);
  ref.read(remoteConfigStartupProvider);
  ref.read(referralAutoApplyProvider);

  // リンクで届いた招待コードを自動で使った結果を、画面の上に短く知らせる。
  ref.listen(referralAutoApplyResultProvider, (_, result) {
    if (result == null) return;
    scheduleMicrotask(() {
      try {
        ref.read(referralAutoApplyResultProvider.notifier).state = null;
      } catch (_) {}
    });
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final strings = context.settingsStrings;
    final message = result.ok
        ? strings.appliedUntil(formatPaywallDate(result.grant!.proUntil))
        : strings.referralFailure(result.failure!);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  });

  final listener = AppLifecycleListener(
    onResume: () {
      try {
        unawaited(ref.read(subscriptionServiceProvider).refresh());
        unawaited(ref.read(notificationCoordinatorProvider).resync());
        unawaited(ref.read(referralAutoApplyProvider).run());
      } catch (_) {
        // 破棄の途中など。
      }
    },
  );
  ref.onDispose(listener.dispose);
});
