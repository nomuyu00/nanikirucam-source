# なにきるカム / Nanikiru Cam

麻雀の手牌を写真・ライブカメラ・手入力から解析するFlutterアプリの対応ソースです。画像処理と麻雀計算は端末内で行います。

## License

Copyright (c) 2026 aile. Application and engine code: **AGPL-3.0-only**; see [LICENSE](LICENSE). Ultralytics YOLO11 recognition models follow their AGPL-3.0 distribution terms. Existing MIT, CC BY 4.0 and other third-party notices remain applicable; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The names and trademarks do not grant endorsement of modified versions.

The source is provided without warranty, subject to the license. Store subscriptions support the official distribution and do not restrict rights granted by the open-source licenses.

## Store candidate source

iOS 1.0.0 (7), submitted for review on 2026-10-23: tag [`ios-1.0.0-7`](https://github.com/nomuyu00/nanikirucam-source/tree/ios-1.0.0-7). The following Android signing fix reads CI environment variables directly and validates the existing key before compiling; it does not change the iOS build.

## Build and test

Use Flutter **3.44.6** / Dart **3.12.2**. Android uses JDK 17 and the official Android SDK; iOS uses Xcode 26.6, CocoaPods and iOS 15+.

```sh
cd app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

Engine checks:

```sh
cd packages/mahjong_core
dart pub get
dart analyze
dart test
```

For iOS, run `flutter build ios --release --no-codesign` from `app`, then use Xcode and your own signing identity to install your build. No signing key or service-account credential is provided or required to modify the source. To distribute a fork, use your own bundle/package identifiers, store accounts, signing identities and service configuration.

Without optional service configuration, Firebase is disabled and AdMob uses Google test IDs. Production configuration is supplied through environment variables / dart defines; [app/README.md](app/README.md) and [codemagic.yaml](codemagic.yaml) describe the variables. Independently operated Firebase server features remain disabled in the official no-server distribution. Firebase client configuration, RevenueCat keys, signing files and review codes are excluded from this source snapshot.

## Recognition models and training

- App-ready TFLite models: `app/assets/models/`; labels: `app/assets/labels/`.
- Editable source checkpoints and run configuration/results: `ml/weights/detect3/` (photo), `ml/weights/live_s/`, `ml/weights/live_n/`, `ml/weights/live_n_480/` (live).
- Training, evaluation, calibration and export procedures: [ml/README_training.md](ml/README_training.md), `ml/environment.yml` and the scripts in `ml/`.
- Training dataset: **majmaster / master-oez61, version 7**, CC BY 4.0, https://universe.roboflow.com/majmaster/master-oez61/dataset/7 . Obtain the dataset from its original provider; retain attribution and its license. It was resized/augmented and independently split for training/evaluation. The README records the split leakage and quality limitations; the dataset author does not endorse this app.
- Display tile images are included with the maintainer's authorization. Original third-party rights remain applicable.

Google/Apple/RevenueCat SDKs are obtained through their normal package managers and retain their own licenses; they are not relicensed by this repository. Do not include credentials, signing keys, tester information or users' photos in contributions.

This repository contains release source snapshots, without the private development repository's history, recovery binaries or operational records. `SOURCE_MANIFEST.json` records the snapshot file hashes.
