import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 端末の温度の状態（設計書 3.3: 温度警告で 1 fps）。
class ThermalStatus {
  const ThermalStatus({this.warning = false, this.critical = false});

  static const ThermalStatus normal = ThermalStatus();

  /// iOS `thermalState` が serious 以上、Android `getThermalHeadroom` が端末の MODERATE の
  /// しきい値以上（しきい値が取れない端末は 0.8 以上）、または `currentThermalStatus` が
  /// SEVERE 以上。
  final bool warning;

  /// iOS critical、Android CRITICAL 以上か headroom が端末の SEVERE のしきい値（取れなければ
  /// 1.0）以上。ライブを終える。
  final bool critical;

  /// しきい値が取れない Android での警告の headroom。
  static const double fallbackWarningHeadroom = 0.8;

  /// ネイティブの返り値（`jp.aile.nanikiru_cam/device_thermal` の `getThermalState`）を読む。
  ///
  /// iOS: `{platform: ios, state: nominal|fair|serious|critical}`。
  /// Android: `{platform: android, status: 0..6 | null, headroom: double | null,
  /// moderateHeadroom: double | null, severeHeadroom: double | null}`。
  static ThermalStatus fromPlatform(Object? value) {
    if (value is! Map) return normal;
    final state = value['state'];
    if (state is String) {
      return ThermalStatus(
        warning: state == 'serious' || state == 'critical',
        critical: state == 'critical',
      );
    }
    final status = value['status'];
    final headroom = value['headroom'];
    double? finite(Object? v) => v is num && v.isFinite ? v.toDouble() : null;
    final h = finite(headroom);
    final warnAt = finite(value['moderateHeadroom']) ?? fallbackWarningHeadroom;
    final endAt = finite(value['severeHeadroom']) ?? 1.0;
    // PowerManager.THERMAL_STATUS_SEVERE = 3, CRITICAL = 4。
    final s = status is int ? status : null;
    return ThermalStatus(
      warning: (h != null && h >= warnAt) || (s != null && s >= 3),
      critical: (h != null && h >= endAt) || (s != null && s >= 4),
    );
  }
}

/// 電池の状態。
class BatteryStatus {
  const BatteryStatus({this.level, this.charging = false});

  static const BatteryStatus unknown = BatteryStatus();

  /// 残量（%）。取れなければ null。
  final int? level;
  final bool charging;

  /// 残量 15% 未満で警告（充電中は出さない）。
  bool get low => !charging && level != null && level! < 15;

  /// 残量 5% 以下でライブを終える（充電中は続ける）。
  bool get critical => !charging && level != null && level! <= 5;
}

/// 画面の点灯・温度・電池（ネイティブ）。テストでは偽物に差し替える。
abstract class LiveDevice {
  Future<void> keepScreenOn(bool on);

  /// 画面の明るさを今の明るさで固定する（true）／アプリの明るさを端末の設定に戻す（false）。
  Future<void> lockBrightness(bool lock);

  Future<ThermalStatus> thermal();
  Future<BatteryStatus> battery();
}

/// 実機の実装。どれも失敗したら「わからない（警告なし）」として続ける。
class PlatformLiveDevice implements LiveDevice {
  PlatformLiveDevice({MethodChannel? channel, this._battery})
    : _channel = channel ?? thermalChannel;

  /// `MainActivity.kt` / `AppDelegate.swift` と同じ名前。
  static const MethodChannel thermalChannel = MethodChannel(
    'jp.aile.nanikiru_cam/device_thermal',
  );

  final MethodChannel _channel;
  Battery? _battery;

  @override
  Future<void> keepScreenOn(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (error) {
      debugPrint('[LiveDevice] wakelock unavailable: $error');
    }
  }

  @override
  Future<void> lockBrightness(bool lock) async {
    try {
      final brightness = ScreenBrightness.instance;
      if (lock) {
        // 今見えている明るさのまま、アプリの明るさとして固定する（自動調整で暗くならない）。
        final current = await brightness.application;
        await brightness.setApplicationScreenBrightness(current);
      } else {
        await brightness.resetApplicationScreenBrightness();
      }
    } catch (error) {
      debugPrint('[LiveDevice] brightness unavailable: $error');
    }
  }

  @override
  Future<ThermalStatus> thermal() async {
    try {
      return ThermalStatus.fromPlatform(
        await _channel.invokeMethod<Object?>('getThermalState'),
      );
    } catch (error) {
      debugPrint('[LiveDevice] thermal unavailable: $error');
      return ThermalStatus.normal;
    }
  }

  @override
  Future<BatteryStatus> battery() async {
    try {
      final battery = _battery ??= Battery();
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      return BatteryStatus(
        level: level,
        charging: state == BatteryState.charging || state == BatteryState.full,
      );
    } catch (error) {
      debugPrint('[LiveDevice] battery unavailable: $error');
      return BatteryStatus.unknown;
    }
  }
}
