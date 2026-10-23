import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';

/// 写真解析の無料枠（設計書 11 章: 1 日 5 回、動画広告で +3、仕様 5 章: 動画は 1 日 2 回まで）。
///
/// 契約: 画面は [quotaProvider] を watch し、解析の直前に [QuotaNotifier.tryConsume] を呼ぶ。
/// false なら `quota_exhausted` を記録して Paywall か動画広告へ。手入力・クイズ・今日の問題は
/// 消費しない（仕様 5 章）。永続化（`quota_v1`）と日付の切り替えはこのファイルが行う。
/// この API（クラス名・メソッド名・フィールド）は変えない。
class QuotaState {
  const QuotaState({
    required this.date,
    this.used = 0,
    this.rewardedGranted = 0,
    this.dailyLimit = defaultDailyLimit,
    this.rewardedPerGrant = defaultRewardedPerGrant,
    this.maxRewardedGrants = defaultMaxRewardedGrants,
    this.unlimited = false,
  });

  /// 無料の 1 日あたりの回数。
  static const int defaultDailyLimit = 5;

  /// 動画広告 1 回で増える回数。
  static const int defaultRewardedPerGrant = 3;

  /// 動画広告で増やせる 1 日の回数（仕様 5 章・9 章: 1 日 2 回まで）。
  static const int defaultMaxRewardedGrants = 2;

  /// 'YYYY-MM-DD'（端末のローカル日付）。
  final String date;
  final int used;

  /// その日に動画広告で追加された回数（[rewardedPerGrant] ずつ増える）。
  final int rewardedGranted;
  final int dailyLimit;
  final int rewardedPerGrant;

  /// 1 日に動画広告で追加できる回数（追加 1 回で [rewardedPerGrant] 回分）。
  final int maxRewardedGrants;

  /// Pro なら true（数えない）。
  final bool unlimited;

  int get limit => dailyLimit + rewardedGranted;
  int get remaining => unlimited ? 1 << 30 : (limit - used).clamp(0, limit);
  bool get exhausted => !unlimited && remaining == 0;
  bool get canGrantRewarded =>
      !unlimited && rewardedGranted < rewardedPerGrant * maxRewardedGrants;

  QuotaState copyWith({
    String? date,
    int? used,
    int? rewardedGranted,
    bool? unlimited,
  }) => QuotaState(
    date: date ?? this.date,
    used: used ?? this.used,
    rewardedGranted: rewardedGranted ?? this.rewardedGranted,
    dailyLimit: dailyLimit,
    rewardedPerGrant: rewardedPerGrant,
    maxRewardedGrants: maxRewardedGrants,
    unlimited: unlimited ?? this.unlimited,
  );

  /// 端末に保存する形（設計書 5.1 `quota_v1`）。`rewardedUsed` は動画広告で追加した回数の合計。
  Map<String, Object> toJson() => {
    'date': date,
    'used': used,
    'rewardedUsed': rewardedGranted,
  };

  @override
  String toString() =>
      'QuotaState($date, used: $used/$limit, unlimited: $unlimited)';
}

class QuotaNotifier extends Notifier<QuotaState> {
  /// SharedPreferences のキー。
  static const preferenceKey = 'quota_v1';

  Future<void>? _loading;

  // Pro が変わると build が再実行される。数えた回数を失わないよう控えておく。
  QuotaState? _lastKnown;

  @override
  QuotaState build() {
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final now = ref.read(clockProvider)();
    var base = _lastKnown ?? QuotaState(date: localDateKey(now));
    if (base.date != localDateKey(now)) {
      base = QuotaState(date: localDateKey(now));
    }
    _loading ??= _load();
    return base.copyWith(unlimited: pro);
  }

  /// 1 回分を使う。使えたら true。
  Future<bool> tryConsume() async {
    await _loading;
    _rollDate();
    if (state.unlimited) return true;
    if (state.exhausted) return false;
    _set(state.copyWith(used: state.used + 1));
    return true;
  }

  /// 動画広告の視聴完了で [QuotaState.rewardedPerGrant] 回分を足す。
  /// 1 日の上限（[QuotaState.maxRewardedGrants]）を超えては足さない。
  Future<void> grantRewarded() async {
    await _loading;
    _rollDate();
    if (!state.canGrantRewarded) return;
    _set(
      state.copyWith(
        rewardedGranted: state.rewardedGranted + state.rewardedPerGrant,
      ),
    );
  }

  /// 端末のデータ削除のあと、今日の分も含めて消す。
  Future<void> reset() async {
    _lastKnown = null;
    state = QuotaState(
      date: localDateKey(ref.read(clockProvider)()),
      unlimited: state.unlimited,
    );
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.remove(preferenceKey);
    } catch (_) {}
  }

  void _rollDate() {
    final today = localDateKey(ref.read(clockProvider)());
    if (state.date != today) {
      _set(QuotaState(date: today, unlimited: state.unlimited));
    }
  }

  void _set(QuotaState next) {
    state = next;
    _lastKnown = next;
    unawaited(_save(next));
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(preferenceKey);
      if (raw == null) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final today = localDateKey(ref.read(clockProvider)());
      // 別の日の記録は捨てる（日付が変わったら 0 から）。
      if (json['date'] != today) return;
      final stored = QuotaState(
        date: today,
        used: _int(json['used']),
        rewardedGranted: _int(json['rewardedUsed']),
      );
      // 読み込みの間に数えた分は残す（大きい方を採る）。
      final current = state;
      final merged = current.copyWith(
        used: current.used > stored.used ? current.used : stored.used,
        rewardedGranted: current.rewardedGranted > stored.rewardedGranted
            ? current.rewardedGranted
            : stored.rewardedGranted,
      );
      state = merged;
      _lastKnown = merged;
    } catch (error) {
      debugPrint('[Quota] load failed: $error');
    }
  }

  Future<void> _save(QuotaState value) async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.setString(preferenceKey, jsonEncode(value.toJson()));
    } catch (error) {
      debugPrint('[Quota] save failed: $error');
    }
  }

  static int _int(Object? value) =>
      value is int && value >= 0 ? value : 0;
}

final quotaProvider = NotifierProvider<QuotaNotifier, QuotaState>(
  QuotaNotifier.new,
);
