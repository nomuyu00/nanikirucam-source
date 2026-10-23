import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 無料のライブ体験（1 日 300 秒 + 動画で延長した分）の残り（設計書 5.1 `live_trial_v1`・11 章）。
class LiveTrialState {
  const LiveTrialState({
    required this.date,
    this.usedSeconds = 0,
    this.bonusSeconds = 0,
    this.bonusGrants = 0,
    this.unlimited = false,
  });

  /// 'YYYY-MM-DD'（端末のローカル日付）。
  final String date;
  final int usedSeconds;

  /// 動画広告で延長した秒数の合計（その日）。
  final int bonusSeconds;

  /// 動画広告で延長した回数（その日。上限は [LiveTrial.maxBonusGrantsPerDay]）。
  final int bonusGrants;

  /// Pro（数えない）。
  final bool unlimited;

  /// その日の体験の長さ（基本 300 秒 + 延長分）。
  int get limitSeconds => LiveTrial.dailyLimitSeconds + bonusSeconds;

  int get remainingSeconds => unlimited
      ? limitSeconds
      : (limitSeconds - usedSeconds).clamp(0, limitSeconds);

  /// 今日の体験を使い切った（Pro は常に false）。
  bool get exhausted => !unlimited && usedSeconds >= limitSeconds;

  /// 動画でまだ延長できる（Pro は不要。1 日の回数の上限まで）。
  bool get canExtend =>
      !unlimited && bonusGrants < LiveTrial.maxBonusGrantsPerDay;

  LiveTrialState copyWith({
    int? usedSeconds,
    int? bonusSeconds,
    int? bonusGrants,
  }) => LiveTrialState(
    date: date,
    usedSeconds: usedSeconds ?? this.usedSeconds,
    bonusSeconds: bonusSeconds ?? this.bonusSeconds,
    bonusGrants: bonusGrants ?? this.bonusGrants,
    unlimited: unlimited,
  );

  Map<String, Object> toJson() => {
    'date': date,
    'usedSeconds': usedSeconds,
    'bonusSeconds': bonusSeconds,
    'bonusGrants': bonusGrants,
  };

  @override
  String toString() =>
      'LiveTrialState($date, $usedSeconds/$limitSeconds s, '
      'bonus: $bonusSeconds s x$bonusGrants, unlimited: $unlimited)';
}

/// Live 画面の滞在秒数を日付ごとに数える（stable の累積ではない。設計書 3.3）。
///
/// Pro は数えない。日付が変わると 0 から。保存は SharedPreferences の `live_trial_v1`
/// （`{date, usedSeconds, bonusSeconds, bonusGrants}`。後ろ 2 つは無ければ 0＝旧データ互換）。
/// 動画広告を見ると、広告の長さに応じて 1〜3 分延長できる（[grantBonus]・[bonusSecondsFor]）。
class LiveTrial {
  LiveTrial(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const String preferenceKey = 'live_trial_v1';

  /// 1 日の基本の体験時間（秒）。延長した分は [LiveTrialState.limitSeconds] に入る。
  static const int dailyLimitSeconds = 300;

  /// 動画で延長できる 1 日の回数（最大 +15 分）。
  static const int maxBonusGrantsPerDay = 5;

  /// 広告を見た時間がこれ未満なら短い広告（+1 分）。
  static const Duration shortAdBelow = Duration(seconds: 12);

  /// 広告を見た時間がこれ以上なら長い広告（+3 分）。[shortAdBelow] 以上これ未満は +2 分。
  static const Duration longAdFrom = Duration(seconds: 25);

  /// 広告を見た時間 [watched]（表示から報酬の発生まで）から、延長する秒数を決める。
  /// AdMob は広告の長さを返さないので、見た時間で 3 段階にする。
  /// 12 秒未満は 60、12 秒以上 25 秒未満は 120、25 秒以上は 180。時間が取れなければ 60。
  /// 報酬が発生しなかった（途中で閉じた）ときは呼ばない（0 秒の扱いは呼び出し側）。
  static int bonusSecondsFor(Duration? watched) {
    if (watched == null || watched < shortAdBelow) return 60;
    if (watched < longAdFrom) return 120;
    return 180;
  }

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  /// 今日の状態。
  LiveTrialState load({required bool pro}) {
    final today = localDateKey(_now());
    var used = 0;
    var bonus = 0;
    var grants = 0;
    try {
      final raw = _prefs.getString(preferenceKey);
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is Map && json['date'] == today) {
          used = _nonNegative(json['usedSeconds']);
          bonus = _nonNegative(json['bonusSeconds']);
          grants = _nonNegative(json['bonusGrants']);
        }
      }
    } catch (error) {
      debugPrint('[LiveTrial] load failed: $error');
    }
    return LiveTrialState(
      date: today,
      usedSeconds: used,
      bonusSeconds: bonus,
      bonusGrants: grants,
      unlimited: pro,
    );
  }

  /// [seconds] 秒を足して保存する（Pro は足さない）。日付が変わっていれば今日の分から数える。
  Future<LiveTrialState> addSeconds(int seconds, {required bool pro}) async {
    final current = load(pro: pro);
    if (pro || seconds <= 0) return current;
    return _save(current.copyWith(usedSeconds: current.usedSeconds + seconds));
  }

  /// 動画広告の報酬として体験時間を [seconds] 秒延長して保存する。
  ///
  /// Pro・[seconds] が 0 以下・1 日の上限（[maxBonusGrantsPerDay] 回）に達しているときは
  /// 何もせず今の状態を返す（呼び出し側は `bonusGrants` が増えたかで付与されたかを見る）。
  /// 日付が変わっていれば今日の分から数える。
  Future<LiveTrialState> grantBonus(int seconds, {required bool pro}) async {
    final current = load(pro: pro);
    if (pro || seconds <= 0 || !current.canExtend) return current;
    return _save(
      current.copyWith(
        bonusSeconds: current.bonusSeconds + seconds,
        bonusGrants: current.bonusGrants + 1,
      ),
    );
  }

  Future<LiveTrialState> _save(LiveTrialState next) async {
    try {
      await _prefs.setString(preferenceKey, jsonEncode(next.toJson()));
    } catch (error) {
      debugPrint('[LiveTrial] save failed: $error');
    }
    return next;
  }

  static int _nonNegative(Object? value) =>
      value is int && value > 0 ? value : 0;
}
