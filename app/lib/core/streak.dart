import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 連続回答日数（設計書 5.1 `streak_v1`）。
///
/// 契約: クイズ・今日の問題で回答したら [StreakNotifier.recordAnswer] を呼ぶ。共有カード
/// （ストリークカード）と Home、通知（21:00 のリマインド）が読む。永続化は画面担当（quiz/ と
/// history/）が実装する。名前と型は変えない。
///
/// 永続化: SharedPreferences の `streak_v1` に `{current, best, lastAnsweredDate}` の JSON。
/// 読み込みが終わるまでは 0 日として見える。
class StreakState {
  const StreakState({this.current = 0, this.best = 0, this.lastAnsweredDate});

  final int current;
  final int best;

  /// 'YYYY-MM-DD'。
  final String? lastAnsweredDate;

  /// 今日すでに回答したか。
  bool answeredOn(String date) => lastAnsweredDate == date;

  /// [now] の時点で続いている日数。最後の回答が今日か昨日なら [current]、それより前なら
  /// 途切れているので 0（[current] は次に回答したときに 1 からやり直す）。
  int currentAsOf(DateTime now) {
    final last = lastAnsweredDate;
    if (last == null) return 0;
    final today = StreakNotifier.dateKey(now);
    final yesterday = StreakNotifier.dateKey(
      now.subtract(const Duration(days: 1)),
    );
    return last == today || last == yesterday ? current : 0;
  }

  Map<String, Object?> toJson() => {
    'current': current,
    'best': best,
    if (lastAnsweredDate != null) 'lastAnsweredDate': lastAnsweredDate,
  };

  /// [toJson] の逆。読めない値は 0 / null にする。
  factory StreakState.fromJson(Map<String, Object?> json) {
    int intOf(Object? v) => v is int && v >= 0 ? v : 0;
    final last = json['lastAnsweredDate'];
    return StreakState(
      current: intOf(json['current']),
      best: intOf(json['best']),
      lastAnsweredDate: last is String ? last : null,
    );
  }
}

class StreakNotifier extends Notifier<StreakState> {
  static const preferenceKey = 'streak_v1';

  bool _disposed = false;

  @override
  StreakState build() {
    ref.onDispose(() => _disposed = true);
    // watch すると、読み込みの完了で作り直しになる前に recordAnswer が呼ばれたとき
    // ref を使えないので、read して読み込み後に state を入れる。
    final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
    if (prefs != null) return _load(prefs);
    unawaited(_loadLater());
    return const StreakState();
  }

  Future<void> _loadLater() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      if (!_disposed) state = _load(prefs);
    } catch (_) {
      // 読めなければ 0 日のまま。
    }
  }

  /// 回答を記録する（同じ日の 2 回目以降は変わらない）。
  Future<void> recordAnswer(DateTime at) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    // 端末に保存した値を正とする（読み込み前の 0 日で上書きしないため）。
    final saved = _load(prefs);
    final date = dateKey(at);
    if (saved.lastAnsweredDate == date) {
      state = saved;
      return;
    }
    final yesterday = dateKey(at.subtract(const Duration(days: 1)));
    final current = saved.lastAnsweredDate == yesterday ? saved.current + 1 : 1;
    final next = StreakState(
      current: current,
      best: current > saved.best ? current : saved.best,
      lastAnsweredDate: date,
    );
    state = next;
    await prefs.setString(preferenceKey, jsonEncode(next.toJson()));
  }

  /// 'YYYY-MM-DD'（端末のローカル日付）。
  static String dateKey(DateTime t) => localDateKey(t);

  static StreakState _load(SharedPreferences prefs) {
    final raw = prefs.getString(preferenceKey);
    if (raw == null) return const StreakState();
    try {
      final json = jsonDecode(raw);
      if (json is Map) return StreakState.fromJson(json.cast<String, Object?>());
    } on FormatException {
      // 壊れていたら 0 日から。
    }
    return const StreakState();
  }
}

final streakProvider = NotifierProvider<StreakNotifier, StreakState>(
  StreakNotifier.new,
);
