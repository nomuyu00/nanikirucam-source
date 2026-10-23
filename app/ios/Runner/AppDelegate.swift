import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// ライブナビの温度警告（設計書 3.3）。lib/live/live_device.dart と同じ名前。
  private var thermalChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // tflite_flutter が dlsym で引く TensorFlowLiteC の C API を、リリースビルドでも見えるようにする
    // （TFLBootstrap.swift / TFLForceLink.m、STRIP_STYLE の 3 点セット。docs/release-checklist.md 参照）。
    TFLBootstrap.forceLoadCAPI()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "jp.aile.nanikiru_cam/device_thermal",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getThermalState":
        let state: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: state = "nominal"
        case .fair: state = "fair"
        case .serious: state = "serious"
        case .critical: state = "critical"
        @unknown default: state = "unknown"
        }
        result(["platform": "ios", "state": state])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    thermalChannel = channel
  }
}
