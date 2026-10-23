// 流用元: reference/agari_cam/lib/main.dart（2026-10-21 時点）
// 改修: Firebase は AppConfig.firebaseEnabled のときだけ、初回フレームの後に初期化する
// （失敗してもアプリは落ちない）。広告・同意（UMP → ATT）の初期化は流用元の作法のまま。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/app.dart';
import 'package:nanikiru_cam/consent/consent_manager.dart';
import 'package:nanikiru_cam/core/app_restart.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/core/third_party_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerThirdPartyLicenses();
  // 端末デフォルト（縦横）許容。各画面（カメラ・ライブは縦固定）で個別に制御します。
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  // AppRestart: 設定の「データを削除」のあと、メモリ上の状態ごと作り直すため。
  runApp(const AppRestart(child: ProviderScope(child: NanikiruCamApp())));

  // ATT/UMP と Firebase は初回フレーム後に起動する（起動を待たせない。iOS で ATT が
  // 表示される確率も上がる）。Firebase が使えなくても撮影・解析・共有は動く。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(ConsentManager.instance.initAndRequestIfNeeded());
    unawaited(FirebaseBootstrap.ensureInitialized());
  });
}
