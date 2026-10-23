import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/ml/model_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ライブのモデルの自動切り替えの設定。
///
/// ライブを始めたあと、最初の [warmupFrames] フレームを捨て、続く [sampleFrames] フレームの
/// 「前処理 + 推論」の時間の中央値が [slowThresholdMs] を超えたら、そのセッション中に
/// [tiers] の 1 つ右（より速いモデル）へ切り替える。切り替えたらまた同じ手順で測り直し、
/// 超えていればもう 1 段。右端の n 480 より先はなく、戻すこともしない。
///
/// **閾値を変えるのはここ**（[defaultSlowThresholdMs] / [defaultWarmupFrames] /
/// [defaultSampleFrames]）。Remote Config の `live_model_variant` で明示されたときは
/// この仕組みを使わない（`liveModelTieringProvider` が null）。
class LiveModelTiering {
  const LiveModelTiering({
    this.tiers = ModelConfig.liveTiers,
    this.slowThresholdMs = defaultSlowThresholdMs,
    this.warmupFrames = defaultWarmupFrames,
    this.sampleFrames = defaultSampleFrames,
    this.onSwitched,
  });

  /// 1 フレームの「前処理 + 推論」がこれを超えたら遅いと見る（中央値、ミリ秒）。5 fps = 200 ms に
  /// 少し余裕を持たせた値。
  static const double defaultSlowThresholdMs = 180;

  /// 測り始めに捨てるフレーム数（モデルの読み込み直後は遅い）。
  static const int defaultWarmupFrames = 10;

  /// 中央値を取るフレーム数。
  static const int defaultSampleFrames = 20;

  /// 速い順ではなく、精度が高い順（= 遅い順）。切り替えは右へ 1 段ずつ。
  final List<String> tiers;
  final double slowThresholdMs;
  final int warmupFrames;
  final int sampleFrames;

  /// 切り替えに成功したとき（端末に保存する）。引数は新しいモデルのアセット。
  final void Function(String asset)? onSwitched;

  /// [active] の 1 つ右の段。無い（右端・段にないモデル）なら null。
  String? nextTier(String? active) {
    final i = tiers.indexOf(active ?? '');
    if (i < 0 || i + 1 >= tiers.length) return null;
    return tiers[i + 1];
  }
}

/// 最初の [warmupFrames] を捨てて [sampleFrames] 個の時間を集め、中央値を出す。
class LiveSpeedWindow {
  LiveSpeedWindow({required this.warmupFrames, required this.sampleFrames});

  final int warmupFrames;
  final int sampleFrames;
  int _seen = 0;
  final List<int> _micros = [];

  /// [sampleFrames] 個そろった。
  bool get complete => _micros.length >= sampleFrames;

  /// 集めた分の中央値（ミリ秒）。まだ 1 つもなければ null。
  double? get medianMs {
    if (_micros.isEmpty) return null;
    final sorted = List<int>.of(_micros)..sort();
    final mid = sorted.length ~/ 2;
    final micros = sorted.length.isOdd
        ? sorted[mid].toDouble()
        : (sorted[mid - 1] + sorted[mid]) / 2;
    return micros / 1000;
  }

  /// 1 フレームぶんの時間（マイクロ秒）を入れる。ちょうど [sampleFrames] 個そろったとき true。
  bool add(int micros) {
    if (complete) return false;
    if (_seen < warmupFrames) {
      _seen++;
      return false;
    }
    _micros.add(micros);
    return complete;
  }

  void reset() {
    _seen = 0;
    _micros.clear();
  }
}

/// 自動切り替えで落ちた段の保存先（SharedPreferences の `live_model_tier_v1`）。
///
/// `{tier: アセット, app: アプリのバージョン}`。次回からはその段で始める。アプリが更新されたとき、
/// Remote Config で variant が明示されたときは捨てて、既定の段から測り直す。
class LiveModelTierStore {
  LiveModelTierStore(this._prefs);

  static const String preferenceKey = 'live_model_tier_v1';

  final SharedPreferences _prefs;

  /// 今回の開始の段。保存がない・古い・壊れている・variant が明示されている、なら null。
  /// 捨てるべき保存は消す。
  Future<String?> resolveStart({
    required bool explicit,
    required String appVersion,
  }) async {
    if (explicit) {
      await clear();
      return null;
    }
    try {
      final raw = _prefs.getString(preferenceKey);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is Map &&
          json['app'] == appVersion &&
          ModelConfig.liveTiers.contains(json['tier'])) {
        return json['tier'] as String;
      }
    } catch (error) {
      debugPrint('[LiveModelTier] load failed: $error');
    }
    await clear();
    return null;
  }

  Future<void> save(String tier, {required String appVersion}) async {
    try {
      await _prefs.setString(
        preferenceKey,
        jsonEncode({'tier': tier, 'app': appVersion}),
      );
    } catch (error) {
      debugPrint('[LiveModelTier] save failed: $error');
    }
  }

  Future<void> clear() async {
    try {
      await _prefs.remove(preferenceKey);
    } catch (error) {
      debugPrint('[LiveModelTier] clear failed: $error');
    }
  }
}
