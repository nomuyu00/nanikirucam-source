# R8 / ProGuard の追加規則（Flutter の Gradle プラグインが、このファイルがあれば release に自動で足す）。
# release は Flutter が minify・shrinkResources を有効にする（android/app/build.gradle.kts には書かない）。
#
# 調べた結果（2026-10-22、flutter build appbundle/apk --release が成功、usage.txt と configuration.txt を確認）:
# - Firebase / AdMob（play-services-ads）/ RevenueCat（purchases）/ CameraX / Play Core（in_app_review）は、
#   各 AAR が consumer rules を持つので、追加の keep は要らない。
# - flutter_local_notifications 19 以降の Gson 用の規則は Gson の jar が持つ（README の ProGuard 節）。
#   通知アイコンは res/raw/keep.xml で縮小から守る（README の「Release build configuration」）。
# - tflite_flutter 0.12.1 は Dart FFI で libtensorflowlite_jni.so の C API を直接呼ぶ。
#   Java の org.tensorflow.lite.* は使わず、R8 に消されても動く（ネイティブ側は dlopen で、JNI_OnLoad も走らない）。
#   ただし端末では確かめていないので、将来の変更（Java 経由の GPU デリゲートなど）で落ちないよう、
#   安い保険として LiteRT の Java クラスを残し、警告を抑える（数十 KB）。
#   端末で通しテストして問題がなければ、この 2 行は消してよい。
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
