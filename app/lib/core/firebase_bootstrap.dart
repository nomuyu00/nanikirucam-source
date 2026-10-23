import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/core/app_config.dart';

/// Firebase の初期化。失敗しても例外を外に出さない（バックエンドが使えなくても
/// ライブ・撮影・解析・共有画像の生成は動く。設計書 1 章）。
///
/// [AppConfig.firebaseEnabled] が false なら何もしない。`firebase_options.dart` を
/// 作る前は、ネイティブの設定ファイル（`google-services.json` / `GoogleService-Info.plist`）で
/// 初期化する。Firebase を使う処理は先に `await FirebaseBootstrap.ensureInitialized()` で
/// 結果を確認する。
abstract final class FirebaseBootstrap {
  static Future<bool>? _initialization;
  static bool _ready = false;

  /// 初期化済み（成功）か。[ensureInitialized] の完了後に確定する。
  static bool get isReady => _ready;

  /// 初期化して成否を返す。何度呼んでも初期化は 1 回だけ。
  static Future<bool> ensureInitialized() => _initialization ??= _initialize();

  static Future<bool> _initialize() async {
    if (!AppConfig.firebaseEnabled) return false;
    try {
      await Firebase.initializeApp();
      _ready = true;
    } catch (error) {
      _ready = false;
      debugPrint('[FirebaseBootstrap] Initialization failed: $error');
    }
    return _ready;
  }

  /// テスト用: 初期化の状態を戻す。
  @visibleForTesting
  static void resetForTest() {
    _initialization = null;
    _ready = false;
  }
}
