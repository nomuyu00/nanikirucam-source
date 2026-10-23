import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/referral/referral_service.dart';

/// Pro の権利の由来。
enum EntitlementSource { none, store, referral, review }

/// 課金状態（設計書 9 章）。UI と QuotaService は `ref.watch(entitlementsProvider).pro` で
/// ゲートする。ストア（RevenueCat）の権利と紹介特典の合成は [composeEntitlements]、
/// ストアとの通信は `purchase/subscription_service.dart` が行う。
class EntitlementState {
  const EntitlementState({
    this.pro = false,
    this.source = EntitlementSource.none,
    this.until,
    this.trial = false,
  });

  /// 無料（広告あり・各種制限あり）。
  static const free = EntitlementState();

  final bool pro;
  final EntitlementSource source;

  /// 権利の期限（期限不明は null）。
  final DateTime? until;

  /// 無料トライアル中か。
  final bool trial;

  @override
  bool operator ==(Object other) =>
      other is EntitlementState &&
      other.pro == pro &&
      other.source == source &&
      other.until == until &&
      other.trial == trial;

  @override
  int get hashCode => Object.hash(pro, source, until, trial);

  @override
  String toString() =>
      'EntitlementState(pro: $pro, source: ${source.name}, until: $until, '
      'trial: $trial)';
}

/// 「RevenueCat の pro OR 紹介特典（期限内）」で Pro かを決める（設計書 9 章）。
///
/// ストアの権利があればそれを優先する（トライアル中かどうかを出せるため）。
/// [referralUntil] は `users/{uid}.pro.referral.until` で、[now] より後なら有効。
EntitlementState composeEntitlements({
  required StoreEntitlement store,
  DateTime? referralUntil,
  DateTime? reviewUntil,
  required DateTime now,
}) {
  if (store.pro) {
    return EntitlementState(
      pro: true,
      source: EntitlementSource.store,
      until: store.until,
      trial: store.trial,
    );
  }
  if (referralUntil != null && referralUntil.isAfter(now)) {
    return EntitlementState(
      pro: true,
      source: EntitlementSource.referral,
      until: referralUntil,
    );
  }
  if (reviewUntil != null && reviewUntil.isAfter(now)) {
    return EntitlementState(
      pro: true,
      source: EntitlementSource.review,
      until: reviewUntil,
    );
  }
  return EntitlementState.free;
}

/// 現在の課金状態。ストアの権利（オフライン時は 3 日間のキャッシュ）と紹介特典から決まる。
/// テストでは `overrideWith` か `.notifier` への代入で差し替えられる。
final entitlementsProvider = StateProvider<EntitlementState>((ref) {
  final store = ref.watch(
    subscriptionServiceProvider.select((service) => service.entitlement),
  );
  final referralUntil = ref.watch(referralProUntilProvider);
  final reviewUntil = ref.watch(reviewAccessProvider).until;
  final now = ref.read(clockProvider)();
  final state = composeEntitlements(
    store: store,
    referralUntil: referralUntil,
    reviewUntil: reviewUntil,
    now: now,
  );
  // 紹介特典は期限が来たら自動で無料に戻す。
  if ((state.source == EntitlementSource.referral ||
          state.source == EntitlementSource.review) &&
      state.until != null) {
    var wait = state.until!.difference(now) + const Duration(seconds: 1);
    // 長い待ちは区切る（起きるたびに再計算して、また待つ）。
    if (wait > const Duration(days: 30)) wait = const Duration(days: 30);
    final timer = Timer(wait, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return state;
});
