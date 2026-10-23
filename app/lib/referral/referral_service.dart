import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/referral/referral_failure.dart';
import 'package:share_plus/share_plus.dart';

export 'package:nanikiru_cam/referral/referral_failure.dart';

class ReferralException implements Exception {
  const ReferralException(this.failure);
  final ReferralFailure failure;
  @override
  String toString() => 'ReferralException(${failure.name})';
}

/// 紹介コードの適用で付与された特典。
class ReferralGrant extends Equatable {
  const ReferralGrant({required this.proUntil, this.referrerRewarded = false});

  final DateTime proUntil;

  /// 紹介した側にも特典が付いたか（10 人まで）。
  final bool referrerRewarded;

  @override
  List<Object?> get props => [proUntil, referrerRewarded];
}

/// 適用の結果。[grant] か [failure] のどちらか。
class ReferralApplyResult {
  const ReferralApplyResult.success(ReferralGrant this.grant) : failure = null;
  const ReferralApplyResult.failure(ReferralFailure this.failure)
    : grant = null;

  final ReferralGrant? grant;
  final ReferralFailure? failure;
  bool get ok => grant != null;
}

/// callable `applyReferral` との境界。
abstract class ReferralBackend {
  /// [code] は形式検査済み（`normalizeReferralCode`）。失敗は [ReferralException]。
  Future<ReferralGrant> apply(String code);
}

/// `BackendClient`（`core/account.dart`）越しに `applyReferral` を呼ぶ。
class CallableReferralBackend implements ReferralBackend {
  const CallableReferralBackend(this._client);

  final BackendClient _client;

  @override
  Future<ReferralGrant> apply(String code) async {
    if (!_client.available) {
      throw const ReferralException(ReferralFailure.unavailable);
    }
    final Map<String, Object?> data;
    try {
      data = await _client.call('applyReferral', {'code': code});
    } on BackendException catch (error) {
      throw ReferralException(referralFailureOf(error));
    }
    final until = DateTime.tryParse('${data['proUntil']}');
    if (data['applied'] != true || until == null) {
      throw const ReferralException(ReferralFailure.unknown);
    }
    return ReferralGrant(
      proUntil: until,
      referrerRewarded: data['referrerRewarded'] == true,
    );
  }
}

/// callable のエラー（`app/functions/API.md` 1.4）を [ReferralFailure] にする。
ReferralFailure referralFailureOf(BackendException error) {
  switch (error.code) {
    case 'invalid-argument':
    case 'not-found':
      return ReferralFailure.invalidCode;
    case 'already-exists':
      return ReferralFailure.alreadyApplied;
    case 'failed-precondition':
      return error.reason == 'self_referral'
          ? ReferralFailure.selfReferral
          : ReferralFailure.noUser;
    case 'unauthenticated':
      return error.reason == 'firebase_disabled'
          ? ReferralFailure.unavailable
          : ReferralFailure.noUser;
    case 'unavailable':
    case 'deadline-exceeded':
      return error.reason == 'firebase_disabled' ||
              error.reason == 'firebase_not_initialized'
          ? ReferralFailure.unavailable
          : ReferralFailure.network;
    default:
      return ReferralFailure.unknown;
  }
}

/// 端末内の紹介の記録（設計書 5.1 `referral_v1`）。
class ReferralState extends Equatable {
  const ReferralState({
    this.myCode,
    this.appliedCode,
    this.appliedAt,
    this.proUntil,
  });

  /// 自分のコード（オフラインでも見せるための控え）。
  final String? myCode;

  /// 使ったコード。
  final String? appliedCode;
  final DateTime? appliedAt;

  /// 使ったことで得た Pro の期限（サーバーの値が届くまでの控え）。
  final DateTime? proUntil;

  ReferralState copyWith({
    String? myCode,
    String? appliedCode,
    DateTime? appliedAt,
    DateTime? proUntil,
  }) => ReferralState(
    myCode: myCode ?? this.myCode,
    appliedCode: appliedCode ?? this.appliedCode,
    appliedAt: appliedAt ?? this.appliedAt,
    proUntil: proUntil ?? this.proUntil,
  );

  Map<String, Object?> toJson() => {
    'myCode': myCode,
    'appliedCode': appliedCode,
    'appliedAt': appliedAt?.toUtc().toIso8601String(),
    'proUntil': proUntil?.toUtc().toIso8601String(),
  };

  static ReferralState fromJson(Object? json) {
    if (json is! Map) return const ReferralState();
    DateTime? date(Object? v) => v == null ? null : DateTime.tryParse('$v');
    return ReferralState(
      myCode: json['myCode'] as String?,
      appliedCode: json['appliedCode'] as String?,
      appliedAt: date(json['appliedAt']),
      proUntil: date(json['proUntil']),
    );
  }

  @override
  List<Object?> get props => [myCode, appliedCode, appliedAt, proUntil];
}

class ReferralNotifier extends Notifier<ReferralState> {
  static const preferenceKey = 'referral_v1';

  bool _disposed = false;

  @override
  ReferralState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    // サーバーの自分のコードが届いたら控える。
    ref.listen<AsyncValue<UserProfile?>>(userProfileProvider, (_, next) {
      final code = next.valueOrNull?.referralCode;
      if (code != null && code.isNotEmpty && code != state.myCode) {
        state = state.copyWith(myCode: code);
        unawaited(_save());
      }
    });
    unawaited(_load());
    return const ReferralState();
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(preferenceKey);
      if (raw == null || _disposed) return;
      final loaded = ReferralState.fromJson(jsonDecode(raw));
      // 読み込み中に届いた値は残す。
      state = ReferralState(
        myCode: state.myCode ?? loaded.myCode,
        appliedCode: state.appliedCode ?? loaded.appliedCode,
        appliedAt: state.appliedAt ?? loaded.appliedAt,
        proUntil: state.proUntil ?? loaded.proUntil,
      );
    } catch (error) {
      debugPrint('[Referral] load failed: $error');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.setString(preferenceKey, jsonEncode(state.toJson()));
    } catch (error) {
      debugPrint('[Referral] save failed: $error');
    }
  }

  /// 招待コードを使う。成功したら保留中のコード（リンクから届いたもの）も消す。
  Future<ReferralApplyResult> apply(String raw) async {
    final code = normalizeReferralCode(raw);
    if (code == null) {
      return const ReferralApplyResult.failure(ReferralFailure.invalidCode);
    }
    if (state.appliedCode != null) {
      return const ReferralApplyResult.failure(ReferralFailure.alreadyApplied);
    }
    // myReferralCodeProvider はこの notifier を見ているので、ここでは直接読む。
    final mine = ref.read(userProfileProvider).valueOrNull?.referralCode ?? state.myCode;
    if (mine != null && mine == code) {
      return const ReferralApplyResult.failure(ReferralFailure.selfReferral);
    }
    try {
      final grant = await ref.read(referralBackendProvider).apply(code);
      if (_disposed) return ReferralApplyResult.success(grant);
      state = state.copyWith(
        appliedCode: code,
        appliedAt: ref.read(clockProvider)(),
        proUntil: grant.proUntil,
      );
      await _save();
      ref.read(analyticsSinkProvider)(AnalyticsEvent.referralApplied);
      // リンクから届いて保留していたコードなら、使い終わったので消す。
      if (ref.read(pendingReferralCodeProvider) == code) {
        ref.read(pendingReferralCodeProvider.notifier).clear();
      }
      return ReferralApplyResult.success(grant);
    } on ReferralException catch (error) {
      return ReferralApplyResult.failure(error.failure);
    } catch (error) {
      debugPrint('[Referral] apply failed: $error');
      return const ReferralApplyResult.failure(ReferralFailure.unknown);
    }
  }

  /// データ削除のあと、端末内の記録を消す。
  Future<void> clearLocal() async {
    state = const ReferralState();
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.remove(preferenceKey);
    } catch (_) {}
  }
}

final referralBackendProvider = Provider<ReferralBackend>(
  (ref) => CallableReferralBackend(ref.watch(backendClientProvider)),
);

final referralProvider = NotifierProvider<ReferralNotifier, ReferralState>(
  ReferralNotifier.new,
);

/// 自分の紹介コード（サーバーの値、なければ端末内の控え）。
final myReferralCodeProvider = Provider<String?>((ref) {
  final fromServer = ref.watch(
    userProfileProvider.select((value) => value.valueOrNull?.referralCode),
  );
  if (fromServer != null && fromServer.isNotEmpty) return fromServer;
  return ref.watch(referralProvider.select((s) => s.myCode));
});

/// 紹介特典の Pro の期限（サーバーの値と、使った直後の端末内の控えの遅い方）。
final referralProUntilProvider = Provider<DateTime?>((ref) {
  final server = ref.watch(
    userProfileProvider.select((value) => value.valueOrNull?.referralProUntil),
  );
  final local = ref.watch(referralProvider.select((s) => s.proUntil));
  if (server == null) return local;
  if (local == null) return server;
  return server.isAfter(local) ? server : local;
});

/// 共有シートを開く。テストでは差し替える。
final referralShareProvider = Provider<Future<void> Function(String text)>(
  (ref) =>
      (text) => Share.share(text),
);

/// リンク（`/r/{code}`、`/p/{id}?ref=`、Install Referrer）から届いて保留されたコードを、
/// サインインできた時点で自動的に使う。
///
/// - 使えた・すでに使用済み・自分のコード・存在しないコード: 保留を消す。
/// - 通信できないなど一時的な失敗: 保留を残し、次の起動・復帰で再試行する。
/// 結果は [onResult] に渡す（画面側がトーストを出す）。
class ReferralAutoApplier {
  ReferralAutoApplier(this._ref, {this.onResult});

  final Ref _ref;
  final void Function(ReferralApplyResult result)? onResult;
  bool _running = false;

  Future<void> run() async {
    if (_running) return;
    final code = _ref.read(pendingReferralCodeProvider);
    if (code == null) return;
    // サインイン前は何もしない（Firebase 無効のビルドでも同じ）。
    if (_ref.read(authUidProvider).valueOrNull == null) return;
    _running = true;
    try {
      final result = await _ref.read(referralProvider.notifier).apply(code);
      final failure = result.failure;
      final transient =
          failure == ReferralFailure.network ||
          failure == ReferralFailure.noUser ||
          failure == ReferralFailure.unavailable ||
          failure == ReferralFailure.unknown;
      if (!transient) {
        _ref.read(pendingReferralCodeProvider.notifier).clear();
        onResult?.call(result);
      }
    } finally {
      _running = false;
    }
  }
}

/// 保留中のコードの自動適用の起動。結果の通知は [referralAutoApplyResultProvider] に出る。
final referralAutoApplyProvider = Provider<ReferralAutoApplier>((ref) {
  final applier = ReferralAutoApplier(
    ref,
    onResult: (result) =>
        ref.read(referralAutoApplyResultProvider.notifier).state = result,
  );
  ref.listen(pendingReferralCodeProvider, (_, next) {
    if (next != null) unawaited(applier.run());
  });
  ref.listen(authUidProvider, (_, next) {
    if (next.valueOrNull != null) unawaited(applier.run());
  });
  unawaited(applier.run());
  return applier;
});

/// 自動適用の直近の結果（画面が見てトーストを出したら null に戻す）。
final referralAutoApplyResultProvider = StateProvider<ReferralApplyResult?>(
  (ref) => null,
);
