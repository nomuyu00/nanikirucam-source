// 流用元: reference/agari_cam/lib/ads/interstitial_pacing.dart（2026-10-21 時点）
// 改修: 間隔を仕様 9 章に合わせた（最初の 3 回は出さない、結果 3 回につき最大 1 回）。
import 'package:shared_preferences/shared_preferences.dart';

/// 全画面広告の間隔をアプリの再起動をまたいで管理する。
/// - 最初の3回の結果では出さない
/// - 結果3回につき最大1回、かつ前回から4分以上
/// - 共有した直後は出さない
class InterstitialPacing {
  InterstitialPacing(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const _totalKey = 'ads.results_total';
  static const _sinceKey = 'ads.results_since_interstitial';
  static const _lastKey = 'ads.last_interstitial_ms';
  static const graceResults = 3;
  static const resultsPerAd = 3;
  static const minimumGap = Duration(minutes: 4);

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  Future<void> recordResult() async {
    await _prefs.setInt(_totalKey, (_prefs.getInt(_totalKey) ?? 0) + 1);
    await _prefs.setInt(_sinceKey, (_prefs.getInt(_sinceKey) ?? 0) + 1);
  }

  bool shouldShow({bool sharedJustNow = false}) {
    if (sharedJustNow) return false;
    if ((_prefs.getInt(_totalKey) ?? 0) <= graceResults) return false;
    if ((_prefs.getInt(_sinceKey) ?? 0) < resultsPerAd) return false;
    final last = DateTime.fromMillisecondsSinceEpoch(
      _prefs.getInt(_lastKey) ?? 0,
    );
    return _now().difference(last) >= minimumGap;
  }

  Future<void> markShown() async {
    await _prefs.setInt(_sinceKey, 0);
    await _prefs.setInt(_lastKey, _now().millisecondsSinceEpoch);
  }
}
