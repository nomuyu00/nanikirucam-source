// 流用元: agari_cam/ios/Runner/TFLBootstrap.swift（2025-09-03）。中身は変えていない。
//
// tflite_flutter 0.12.1 の iOS 側は 0.11.0 と同じで、TensorFlowLiteSwift 2.12.0 の CocoaPods
// （静的フレームワーク）を使い、Dart FFI が DynamicLibrary.process() + dlsym で C API を引く
// （Android だけ LiteRT 1.4.0 に移った）。リリースビルドでシンボルが落ちるのを防ぐ 3 点のうち、
// これは「動的な TensorFlowLiteC が埋め込まれている配布形態のとき、RTLD_GLOBAL で読み込む」保険。
// 静的リンクのとき（今の構成）は候補のパスが無く何もしない。
// 残りの 2 点は TFLForceLink.m（C API のオブジェクトを必ずリンクさせる）と、Runner ターゲットの
// STRIP_STYLE = non-global（project.pbxproj）。docs/release-checklist.md の iOS の節を参照。
import Foundation
import Darwin

@objc class TFLBootstrap: NSObject {
  // Explicitly dlopen TensorFlowLiteC with RTLD_GLOBAL so tflite_flutter's dlsym can find symbols.
  // This avoids cases where the framework is embedded but not globally visible for symbol lookup.
  @objc static func forceLoadCAPI() {
    let fm = FileManager.default
    let bundle = Bundle.main
    var candidates: [String] = []
    if let pf = bundle.privateFrameworksPath {
      candidates.append(pf + "/TensorFlowLiteC.framework/TensorFlowLiteC")
      // Some distributions embed the unified TensorFlowLite framework instead of the C-only one.
      candidates.append(pf + "/TensorFlowLite.framework/TensorFlowLite")
      candidates.append(pf + "/TensorFlowLiteC.xcframework/ios-arm64/TensorFlowLiteC.framework/TensorFlowLiteC")
      candidates.append(pf + "/TensorFlowLiteC.xcframework/ios-arm64_armv7/TensorFlowLiteC.framework/TensorFlowLiteC")
    }
    // Fallback common location
    candidates.append(bundle.bundlePath + "/Frameworks/TensorFlowLiteC.framework/TensorFlowLiteC")
    candidates.append(bundle.bundlePath + "/Frameworks/TensorFlowLite.framework/TensorFlowLite")

    for path in candidates {
      if fm.fileExists(atPath: path) {
        let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL)
        if handle != nil {
          // Successfully loaded; symbols should now be discoverable via RTLD_DEFAULT.
          return
        }
      }
    }
  }
}
