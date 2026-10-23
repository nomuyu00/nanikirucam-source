# nanikiru_cam（なにきるカム）

麻雀の「何切る」をカメラで解く Flutter アプリ。仕様は `../docs/spec.md`、設計は `../docs/design.md`（2.3 に `app/` の骨格の決めごと）。

## 実行

```
flutter pub get
flutter run                       # Firebase なし・AdMob はテスト ID・RevenueCat 未設定で動く
flutter run \
  --dart-define=FIREBASE_ENABLED=true \
  --dart-define=REVENUECAT_API_KEY_ANDROID=goog_xxx \
  --dart-define=ADMOB_HOME_BANNER_ANDROID=ca-app-pub-xxx/yyy
```

`--dart-define` の一覧は `lib/core/app_config.dart`（主なものは下の表）。Firebase を使うには `android/app/google-services.json` と
`ios/Runner/GoogleService-Info.plist` を置く（Git 管理外）。AdMob の App ID は Android が
`--dart-define=ADMOB_APP_ID_ANDROID=...`、iOS が `ios/Flutter/Secrets.xcconfig` の `ADMOB_APP_ID=...`。

### `--dart-define` の主なもの

| 名前 | 内容 | 未指定のとき |
| --- | --- | --- |
| `FIREBASE_ENABLED` | Firebase（Analytics・Auth など）を初期化する。設定ファイルが要る | 使わない |
| `FIREBASE_BACKEND_ENABLED` | Functions・Firestore・Storage を使う（オンライン機能: 公開・回答・通報・紹介・人気問題）。`FIREBASE_ENABLED` も true のときだけ有効 | false = **サーバーなしの版**。今日の問題は端末内で毎日 3 問作る（`../docs/design.md` 4.11） |
| `ADMOB_USE_TEST_ADS` | 本番の広告ユニットを渡してあっても Google のテスト広告を出す | false |
| `ADMOB_APP_ID_ANDROID` | AdMob の App ID（Android。iOS は `ios/Flutter/Secrets.xcconfig`） | テスト ID |
| `ADMOB_{HOME,RESULT,HISTORY}_BANNER_{ANDROID,IOS}` `ADMOB_NEXT_HAND_INTERSTITIAL_{…}` `ADMOB_QUOTA_REWARD_{…}` `ADMOB_EXPLANATION_REWARD_{…}` | 広告ユニット ID | Google のテスト ID |
| `ADMOB_LIVE_TRIAL_REWARD_{ANDROID,IOS}` | 任意。ライブの体験時間を延長する動画（Paywall と Home）の専用リワード。作ると収益を分けて見られる | `ADMOB_QUOTA_REWARD_*` のユニットで出る |
| `REVENUECAT_API_KEY_{ANDROID,IOS}` | RevenueCat の公開 SDK キー（`goog_…` / `appl_…`） | 課金は「準備中」 |
| `REVIEW_ACCESS_CODE_SHA256` / `REVIEW_ACCESS_EXPIRES_AT` | Android審査用コードのSHA-256とUTC期限。平文は渡さない。[運用手順](../docs/store/review-access.md) | 未設定で入口・権利とも無効（iOS/Webは常に無効） |
| `WEB_BASE_URL` | 問題の URL・QR・回答の宛先（サーバーありの版） | `https://nanikiru-cam.web.app` |
| `LEGAL_TOKUSHOHO_URL` | 特定商取引法ページの URL（Paywall・設定のリンク） | テスト版の購入案内ページ `https://aile-net.jp/nanikirucam-test-purchases/` |

本番ビルドで渡す値と Codemagic の環境変数は `../docs/codemagic-setup.md` の 6 章。

## 構成

- `lib/core/routes.dart` — ルート名と画面の引数。`lib/app.dart` に登録。
- `lib/analysis/hand_input.dart` — 画面間の契約 `HandInput`（→ `mahjong_core` の `HandState`）。
- `lib/ml/` — 推論（`TfliteService`）、牌の選択（`tile_selection.dart`）、ツモ牌・副露の推定（`tile_arrangement.dart`）、認識結果 `RecognitionDraft`、モデル設定 `ModelConfig`。
- `lib/l10n/strings/<機能>_strings.dart` — 機能ごとの文言（ja が主、en は従）。
- `lib/ui/theme/` — ブランドのテーマ（`app_colors`・`app_theme`・`app_spacing`）。色・角丸・余白は画面で直書きせず、ここの定数か `Theme.of(context).colorScheme` を使う。共通部品は `lib/ui/widgets/`。ダークモードは未対応（ライト固定）。設計書 2.5。
- `lib/win/` — Pro の「和了の役と点数」（ルート `/win`）。採点は `../packages/mahjong_core` の `WinScorer`（設計書 4.12）。
- `../packages/mahjong_core` — 麻雀ロジック（純 Dart。ここからは編集しない）。

## テスト

```
flutter analyze
flutter test
flutter build apk --debug
```

Windows 上の WSL では `/mnt/d` が遅いので、WSL のホーム配下にコピーして実行すると速い（`docs/handoff.md` 参照）。

### 画面の見た目の確認（ストア素材ではない）

`tool/capture_screens_test.dart`（UI の刷新 第 1 弾: Home・Result・Recognition・Paywall・Onboarding・Today・和了の点数画面など）と `tool/capture_screens_wave2_test.dart`（第 2 弾: Quiz・Live（偽のカメラと偽の検出）・候補の詳細・解説・対局サマリー・設定・履歴・公開・出題した問題）は、実際の画面（ルート表 `appRoutes`）を偽の課金・解析・今日の問題で描き、iPhone 相当（390×844）と縦長（390×2000）の PNG に、日本語・英語・大きな文字（`textScaler` 1.3）の 3 通りで書き出す。レイアウトのあふれ（`RenderFlex overflowed` など）は出力先の `errors.txt` に書く。

```
flutter test tool/capture_screens_test.dart \n  --dart-define=CAPTURE_OUTPUT_DIR=/mnt/c/temp/screens/after \n  --dart-define=CAPTURE_ONLY=home,result          # 省略すると全画面
flutter test tool/capture_screens_wave2_test.dart \n  --dart-define=CAPTURE_OUTPUT_DIR=/mnt/c/temp/screens/wave2/after \n  --dart-define=CAPTURE_ONLY=quiz,live_advice --dart-define=CAPTURE_VARIANTS=ja,en,ja_large
```

- 日本語フォントは Windows のメイリオを読む（WSL では `/mnt/c/Windows/Fonts/meiryo.ttc`）。
- カメラ映像は偽物なので、**Live のカメラ映像の上の文字の読みやすさは実機でしか確かめられない**（`docs/release-checklist.md` 14 章 B）。
- 画像は `CAPTURE_OUTPUT_DIR` に出る。Git に入れない。審査・ストアの素材には使わない（`docs/store/screenshots_plan.md` は実機で撮る）。

## リリース準備（ストア提出まで）

提出までの手順は `../docs/release-checklist.md`、ストア掲載文・プライバシー申告・スクリーンショットの計画は `../docs/store/`。ここにはビルドと素材に関する決めごとだけを書く。

### アイコンと素材

- **アプリアイコン「ファインダーの何」**: ジェイドの卓（上から下へのグラデーション）に、アイボリーの牌（下に山吹色の背の層が見える立体）と太い「何」、牌の上に朱の▼（切る牌のカーソル）、四隅にゴールドの L 字（カメラのファインダー）。アイコン・スプラッシュ・ストア素材・Web の画像は、すべて `tool/make_icons.py`（Pillow + numpy）が同じ部品から描く。意匠や色を変えるときはこのスクリプトを直して再生成する（画像を手で直さない）。
  - ブランド色: ジェイド `#188664`（上）→ `#0D624A`（主色）→ `#063A2D`（下）、アイボリー `#FCF7EA`、朱 `#E6452C`、ゴールド `#E6BE62`、インク `#1C2824`。値はスクリプトの先頭にまとめてある。
  - `assets/branding/app_mark.png`（144×144。Home の見出しと共有カードの左上に出すアイコン。pubspec に同梱している branding のうちこれだけ）は `make_icons.py` が作らない。`icon_1024.png` を 144px に縮めたものなので、**アイコンを変えたら縮め直す**。
  - 原画 `assets/branding/icon_1024.png`（全面を塗った正方形、アルファなし）、Google Play 用 `play_store_icon_512.png`（32 ビット）、フィーチャー グラフィック `feature_graphic_1024x500.png`。
  - Android: `mipmap-*dpi/ic_launcher.png`（旧形式）、アダプティブアイコン（`mipmap-anydpi-v26/ic_launcher.xml`。前景 `ic_launcher_foreground.png` は意匠全体を中央 66dp の safe zone に収めてある。背景は `drawable/ic_launcher_gradient.xml` のグラデーション）、Android 13 のテーマアイコン `ic_launcher_monochrome.png`（「何」を抜いたシルエット）。minSdk が 26 なのでアダプティブが使われる。`values/ic_launcher_background.xml` の `ic_launcher_background`（`#0D624A`）は FCM の通知の色、`splash_background` はスプラッシュの背景。
  - iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` は 1024 の 1 枚と `Contents.json`（Xcode 14 以降のシングルサイズ。残りの大きさは Xcode が作る）。
  - スプラッシュ: ジェイド `#0D624A` の地の中央に意匠（L 字・牌・▼）。iOS は `LaunchImage.imageset/LaunchImage*.png` と `LaunchScreen.storyboard` の背景色・画像の大きさ（スクリプトが書き換える）。Android 11 以下は `drawable{,-v21}/launch_background.xml` と `drawable-*dpi/launch_logo.png`、Android 12 以降は `values{,-night}-v31/styles.xml` の `windowSplashScreenBackground` / `windowSplashScreenAnimatedIcon`（アダプティブの前景を使う）。
  - Web（Hosting）: `hosting/public/assets/` の `icon-512.png` `icon-192.png` `favicon-48.png`（角丸・外は透明）、`apple-touch-icon.png`（全面を塗った正方形）、`og-default.png`（1200×630）。
  - 再生成: `py -3.12 -m pip install pillow numpy` → `py -3.12 tool/make_icons.py`（全部を上書きする）。日本語フォントは Windows の `NotoSansJP-VF.ttf` などを探す（なければ環境変数 `ICON_FONT`）。pubspec に依存は増えない。
- **通知の小アイコン**: 白一色の透過 PNG `android/app/src/main/res/drawable-*dpi/ic_stat_notify.png`（同じスクリプトが作る。24dp でも潰れないよう、牌のシルエット・▼・太い L 字だけで「何」は入れない）。`AndroidManifest.xml` の FCM 既定アイコン（`default_notification_icon`）と `lib/notifications/local_scheduler.dart` の `AndroidInitializationSettings('ic_stat_notify')` が同じ名前。リソースの縮小で消えないよう `res/raw/keep.xml` で守っている（flutter_local_notifications の README の指示）。

### Android のリリースビルド

```
flutter build appbundle --release   # Play に上げる AAB
flutter build apk --release         # 実機で入れて確かめる APK（全 ABI 入り）
flutter build apk --release --split-per-abi   # ABI ごとの APK（配布サイズの目安）
```

- **署名**: `android/key.properties`（`storePassword` `keyPassword` `keyAlias` `storeFile`。Git 管理外。Codemagic が作る）があれば release 署名、**無ければ debug 署名で通る**（`flutter run --release` 用。この AAB は Play には上げられない）。鍵の作り方は `../docs/release-checklist.md` の「署名鍵」。
- **R8 / 縮小**: Flutter の Gradle プラグインが release で minify と shrinkResources を有効にする。追加の規則は `android/app/proguard-rules.pro`（自動で読まれる）。Firebase・AdMob・RevenueCat・CameraX・Play Core は各 AAR の consumer rules で足りる。`tflite_flutter` は FFI で C API を呼ぶので Java 側は使わないが、端末での通しテストが済むまでの保険として LiteRT のクラスを残している。
- **マニフェストの権限**: 使わない権限を `AndroidManifest.xml` の `tools:node="remove"` で外している。`RECORD_AUDIO`（`camera_android_camerax` が足す。音声は録らない）、`READ_PHONE_STATE`（`litert-gpu-api` の manifest に targetSdkVersion が無いためマージャが暗黙で足していた）、`READ_EXTERNAL_STORAGE`（`camera_android_camerax` の `WRITE_EXTERNAL_STORAGE` の暗黙の組）。`READ_EXTERNAL_STORAGE` は aapt2 が `WRITE_EXTERNAL_STORAGE`（`maxSdkVersion=28`、Android 9 以前の共有カード保存用）の組として `maxSdkVersion=28` 付きで足し直すので、Android 10 以降では要求されない。写真の取り込み（`image_picker`）は Photo Picker / `ACTION_GET_CONTENT` で、保存読み取り権限は要らない。出どころは `build/app/outputs/logs/manifest-merger-release-report.txt` の `IMPLIED ... reason:` で分かる。リリース APK の権限は `aapt2 dump badging app-release.apk` で確かめる。
- **16 KB ページ**（Android 15 以降の要件）: 2026-10-22 のビルドで `zipalign -c -P 16 -v 4` が成功し、`.so` の `LOAD` セグメントはすべて 16 KB 以上のアラインメントだった。
- **サイズ**（2026-10-22、WSL、`assets/models/` は写真用の fp32 80 MB + int8 20 MB のみ。ライブ用モデルを足すと増える）: AAB 177.9 MB（うち端末に配られないデバッグ記号・マッピングの `BUNDLE-METADATA` が圧縮後 47 MB）、全 ABI 入り APK 192.6 MB、分割 APK は arm64-v8a 139.0 MB、armeabi-v7a 134.4 MB、x86_64 142.5 MB。Play が端末ごとに配る配布サイズは圧縮されるのでこれより小さい見込み（`bundletool get-size total` で確かめる）。**約 85 MB（圧縮後）が写真用の 2 モデル**。Play の上限（基本モジュール 500 MB）には余裕があるが、200 MB を超えるとモバイル通信のインストールで確認ダイアログが出る。

#### Dart コードの難読化（任意）

`--obfuscate` は Dart のクラス名・関数名を潰す（機能は変わらない）。**必ず `--split-debug-info` と一緒に使い、出力ディレクトリのシンボルをビルドごとに保管する**（ないとクラッシュのスタックトレースを読めない）。

```
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
# build/symbols/app.android-arm.symbols / -arm64 / -x64 が出る。アプリの版（versionCode）ごとに保管する。
flutter symbolize -i crash_stack.txt -d build/symbols/      # スタックトレースを読めるようにする
```

- 2026-10-22 に WSL で成功を確認（AAB 173.5 MB。非難読化より約 4 MB 小さい）。`libapp.so` に `TileTracker` `LiveController` などのクラス名が残っていないことも確かめた。`flutter build` が出す「ELF library contains unobfuscated DWARF debugging information」の警告は、Android では AGP が配布用の `.so` から記号を外すので実害がない（`.debug_*` セクションは無かった）。
- このアプリのコードは難読化で壊れない: `Enum.toString()` と `.name` は難読化されない（実験で確認）ので、`tensor.type.toString().contains('float32')`（`lib/ml/`）は動く。`runtimeType.toString()` はログ用の `message` にだけ使っていて、難読化された名前になるだけ。
- iOS で使うときは、`codemagic.yaml` の `flutter build ipa` に同じ `--obfuscate --split-debug-info=...` を渡す。`build/symbols` は成果物（`artifacts`）に足して保管する。
- ルートの `codemagic.yaml` は今のところ難読化しない。使うと決めたら `flutter build appbundle` と `flutter build ipa` の行に足す。

### iOS のリリースビルド

- **tflite の 3 点セット**（`tflite_flutter` 0.12.1 の iOS 側は 0.11.0 と同じ: TensorFlowLiteSwift 2.12.0 の CocoaPods を静的に取り込み、Dart FFI が `DynamicLibrary.process()` で C API を引く。0.12 で LiteRT に移ったのは Android だけ）。リリース（アーカイブ）ビルドでシンボルが落ちて「Failed to lookup symbol」になるのを防ぐ:
  1. `ios/Runner/TFLForceLink.m` — 起動時に `TfLiteVersion` を参照して C API のオブジェクトをリンクさせる。
  2. `ios/Runner/TFLBootstrap.swift` — 動的な TensorFlowLiteC があれば `RTLD_GLOBAL` で読む保険（静的リンクの今は何もしない）。`AppDelegate.swift` の `didFinishLaunchingWithOptions` から呼ぶ。
  3. Runner ターゲットの `STRIP_STYLE = non-global`（Release / Profile）。`tflite_flutter` の README が指示する「Strip Style を Non-Global Symbols に」。
  4. `ios/Podfile` の `post_install` の `-ObjC` と `-Wl,-u,_TfLite*`、`Release.xcconfig` の `STRIP_INSTALLED_PRODUCT = NO`（あがりかむと同じ）。`codemagic.yaml` の `ios-release` は、IPA に TfLite の C API のシンボルが残っているかを検査して、無ければ止まる。
- **Firebase の設定ファイル**: `ios/Runner/GoogleService-Info.plist`（Git 管理外）がある場合だけ、Runner の「Copy Firebase config (if present)」ビルドフェーズがアプリの直下へ入れる（`project.pbxproj`）。無い場合は `FIREBASE_ENABLED=false` で動く。
- **`project.pbxproj` を手で直したら**、macOS の `plutil` が無い環境でも `py -3.12 tool/check_pbxproj.py` で構文・ID の重複・参照の解決・グループへの所属を確かめられる。
- `ios/Podfile` はリポジトリに固定している（iOS 15、静的リンク、`TensorFlowLiteSwift/CoreML 2.12.0`、TFLite のリンカ設定。あがりかむで Codemagic のビルドが通っている設定）。
- **`codemagic.yaml` はリポジトリのルート**（Codemagic の決まり。`app/` には置かない）。`working_directory: app` でこのアプリをビルドし、`artifacts` はクローン先（ルート）からの相対（`app/build/...`）。`ml/`・`datasets/` は使わず、Git にも入れない（ルートの `.gitignore`）ので、クローンもキャッシュもされない。Codemagic の画面で行う設定（証明書・鍵・環境変数・初回アップロード）は [`../docs/codemagic-setup.md`](../docs/codemagic-setup.md)。
- **iPhone 専用**: `TARGETED_DEVICE_FAMILY = 1`（Debug / Release / Profile）で、`Info.plist` の iPad 用の向き（`UISupportedInterfaceOrientations~ipad`）は無い。iPad 13 インチのスクリーンショットは要らない。
- **プライバシー マニフェスト**: `ios/Runner/PrivacyInfo.xcprivacy`（追跡あり・追跡ドメインなし、収集データ 9 種、required-reason API は `FileTimestamp` `C617.1` と `SystemBootTime` `35F9.1`）。`project.pbxproj` の Runner の Resources に登録済み。根拠と確認方法は `../docs/store/privacy_labels.md` の 2.3。変えたら `py -3.12 tool/check_privacy_manifest.py`（構文・Apple の許可リスト・Resources への登録・`privacy_labels.md` 2.2 との一致を検査）と `tool/check_pbxproj.py` を回す。
## ライセンスと対応ソース

なにきるカムのアプリ・エンジンはAGPL-3.0。全文はルートの`LICENSE`、第三者の表示は`THIRD_PARTY_NOTICES.md`。対応ソース: https://github.com/nomuyu00/nanikirucam-source 。モデルの変更用重み・学習／変換手順も公開用ソースへ含める。秘密鍵・認証JSON・審査コード・Git履歴は公開しない。
