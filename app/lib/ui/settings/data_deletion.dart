import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/notifications/notification_coordinator.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/purchase/review_access.dart';
import 'package:nanikiru_cam/referral/referral_service.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_gate.dart';

/// サーバー上のアカウントの削除（callable `deleteMyData`。`app/functions/API.md` 1.5）。
abstract class AccountEraser {
  /// false なら削除するサーバーデータがない（Firebase 無効）。
  bool get available;

  /// 本人のデータを削除する。失敗は例外。
  Future<void> deleteRemote();

  /// サインアウトする（サーバー側で Auth アカウントは削除済み）。
  Future<void> signOut();
}

class BackendAccountEraser implements AccountEraser {
  const BackendAccountEraser(this._client);

  final BackendClient _client;

  @override
  bool get available => _client.available;

  @override
  Future<void> deleteRemote() async {
    await _client.call('deleteMyData');
  }

  @override
  Future<void> signOut() async {
    if (!FirebaseBootstrap.isReady) return;
    try {
      await FirebaseAuth.instance.signOut();
    } catch (error) {
      debugPrint('[DataDeletion] signOut failed: $error');
    }
  }
}

final accountEraserProvider = Provider<AccountEraser>(
  (ref) => BackendAccountEraser(ref.watch(backendClientProvider)),
);

/// データ削除の結果。
class DataDeletionResult {
  const DataDeletionResult({required this.ok});
  final bool ok;
}

/// 「データを削除」（設計書 14 章）: サーバーのデータ（`deleteMyData`）を消し、成功したら
/// 端末のデータも消す。サーバーの削除に失敗したら端末のデータは消さない（やり直せるように）。
class DataDeletion {
  DataDeletion(this._ref);

  final Ref _ref;

  /// 削除しない端末内の記録。個人の情報ではなく、無料枠を消去で取り戻せてしまわないよう残す
  /// （`quota_v1` `live_trial_v1`）と、Install Referrer を読み直して招待特典を二重に受けない
  /// ための印（`install_referrer_consumed_v1`）。
  static const keptPreferenceKeys = <String>{
    'quota_v1',
    'live_trial_v1',
    'install_referrer_consumed_v1',
  };

  Future<DataDeletionResult> run() async {
    final eraser = _ref.read(accountEraserProvider);
    if (eraser.available) {
      try {
        await eraser.deleteRemote();
      } catch (error) {
        debugPrint('[DataDeletion] remote failed: ${error.runtimeType}');
        return const DataDeletionResult(ok: false);
      }
      await eraser.signOut();
    }
    try {
      await _ref.read(notificationCoordinatorProvider).clearAll();
    } catch (error) {
      debugPrint('[DataDeletion] notifications failed: $error');
    }
    try {
      final prefs = await _ref.read(sharedPreferencesProvider.future);
      for (final key in prefs.getKeys().toList()) {
        if (!keptPreferenceKeys.contains(key)) await prefs.remove(key);
      }
    } catch (error) {
      debugPrint('[DataDeletion] local failed: $error');
      return const DataDeletionResult(ok: false);
    }
    // アプリ全体を作り直せない場合に備えて、この担当の状態も初期化しておく。
    await _ref.read(appSettingsProvider.notifier).reset();
    await _ref.read(referralProvider.notifier).clearLocal();
    // ブロック中の出題者（`blocked_authors_v1`）は上で消えている。メモリ上の一覧も空に戻す。
    _ref.invalidate(blockedAuthorsProvider);
    _ref.invalidate(reviewAccessProvider);
    _ref.invalidate(onboardingCompletedProvider);
    return const DataDeletionResult(ok: true);
  }
}

final dataDeletionProvider = Provider<DataDeletion>((ref) => DataDeletion(ref));
