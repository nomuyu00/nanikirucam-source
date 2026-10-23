import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';

/// オンライン機能（問題の公開・Web での回答・回答の集計・招待コード・FCM の
/// 週間／回答到達通知）が使えるか。
///
/// サーバーなしの構成（`AppConfig.firebaseBackendEnabled` が false）では false。
/// 画面はこれが false のとき、オンライン前提の説明・ボタン・スイッチを出さない。
/// 今日の問題（端末内で作る）やローカル通知は、これと無関係に使える。
/// テストでは `onlineFeaturesProvider.overrideWithValue(true)` で差し替える。
final onlineFeaturesProvider = Provider<bool>(
  (ref) => ref.watch(backendClientProvider).available,
);
