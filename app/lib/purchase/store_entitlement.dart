import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ストア（RevenueCat の権利 `pro`）から見た Pro の状態。紹介特典は含めない
/// （合成は `core/entitlements.dart` の [composeEntitlements]）。
class StoreEntitlement extends Equatable {
  const StoreEntitlement({
    this.pro = false,
    this.until,
    this.trial = false,
    this.willRenew = true,
  });

  /// 無料。
  static const none = StoreEntitlement();

  final bool pro;

  /// 現在の期間の終わり（期限なしは null）。
  final DateTime? until;

  /// 無料トライアル中か。
  final bool trial;

  /// 自動更新が続くか（解約済みなら false）。
  final bool willRenew;

  @override
  List<Object?> get props => [pro, until, trial, willRenew];
}

/// 直近の [StoreEntitlement] の端末内キャッシュ（設計書 5.1 `entitlement_cache_v1`）。
///
/// オフラインで RevenueCat に問い合わせられないときのための猶予で、最後に確認してから
/// [offlineGrace]（3 日）以内なら Pro を維持する（設計書 9 章、仕様 10 章）。
class EntitlementCache {
  const EntitlementCache(this._load);

  /// テストでは差し替える。
  final Future<SharedPreferences> Function() _load;

  static const preferenceKey = 'entitlement_cache_v1';
  static const offlineGrace = Duration(days: 3);

  /// 最後に確認した状態。オフラインの猶予を過ぎていたら無料。読めない・壊れているときも無料。
  Future<StoreEntitlement> read(DateTime now) async {
    try {
      final prefs = await _load();
      final raw = prefs.getString(preferenceKey);
      if (raw == null) return StoreEntitlement.none;
      final json = jsonDecode(raw);
      if (json is! Map) return StoreEntitlement.none;
      if (json['pro'] != true) return StoreEntitlement.none;
      final fetchedAt = DateTime.tryParse('${json['fetchedAt']}');
      if (fetchedAt == null) return StoreEntitlement.none;
      final age = now.difference(fetchedAt);
      // 時計を巻き戻して猶予を延ばされないよう、未来の fetchedAt は無効にする。
      if (age.isNegative || age > offlineGrace) return StoreEntitlement.none;
      final expires = json['expiresAt'];
      return StoreEntitlement(
        pro: true,
        until: expires == null ? null : DateTime.tryParse('$expires'),
        trial: json['trial'] == true,
        willRenew: json['willRenew'] != false,
      );
    } catch (error) {
      debugPrint('[EntitlementCache] read failed: $error');
      return StoreEntitlement.none;
    }
  }

  Future<void> write(StoreEntitlement entitlement, DateTime fetchedAt) async {
    try {
      final prefs = await _load();
      await prefs.setString(
        preferenceKey,
        jsonEncode({
          'pro': entitlement.pro,
          'expiresAt': entitlement.until?.toUtc().toIso8601String(),
          'fetchedAt': fetchedAt.toUtc().toIso8601String(),
          'trial': entitlement.trial,
          'willRenew': entitlement.willRenew,
        }),
      );
    } catch (error) {
      debugPrint('[EntitlementCache] write failed: $error');
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await _load();
      await prefs.remove(preferenceKey);
    } catch (error) {
      debugPrint('[EntitlementCache] clear failed: $error');
    }
  }
}
