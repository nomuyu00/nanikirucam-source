import 'dart:async';
import 'dart:convert';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 端末内の今日の問題（`daily-YYYY-MM-DD-N`）で、回答した問題の ID。
///
/// Today 画面の「解答済み」のチェックと「3 問クリア」の表示に使う。履歴（`history_v1`）は
/// 消せる・件数の上限があるので、別に軽く持つ。Quiz で牌を選んで回答したときに
/// [DailySolvedNotifier.markSolved] を呼ぶ（時間切れ・スキップは数えない）。
///
/// 永続化: SharedPreferences の `daily_solved_v1` に ID の配列（JSON、新しい順に
/// [DailySolvedNotifier.maxEntries] 件まで）。読み込みが終わるまでは空に見える。
class DailySolvedNotifier extends Notifier<Set<String>> {
  static const preferenceKey = 'daily_solved_v1';

  /// 残す件数（1 日 3 問 × 約 4 か月）。
  static const maxEntries = 400;

  bool _disposed = false;

  @override
  Set<String> build() {
    ref.onDispose(() => _disposed = true);
    final prefs = ref.read(sharedPreferencesProvider).valueOrNull;
    if (prefs != null) return _load(prefs).toSet();
    unawaited(_loadLater());
    return const {};
  }

  Future<void> _loadLater() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      if (!_disposed) state = {...state, ..._load(prefs)};
    } catch (_) {
      // 読めなければ空のまま。
    }
  }

  /// [problemId] を回答済みにする。
  Future<void> markSolved(String problemId) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    // 端末に保存した値を正とする（読み込み前の空で上書きしないため）。
    final saved = _load(prefs)..remove(problemId);
    final next = [problemId, ...saved].take(maxEntries).toList();
    if (!_disposed) state = next.toSet();
    await prefs.setString(preferenceKey, jsonEncode(next));
  }

  static List<String> _load(SharedPreferences prefs) {
    final raw = prefs.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final e in decoded)
            if (e is String) e,
        ];
      }
    } on FormatException {
      // 壊れていたら空から。
    }
    return [];
  }
}

final dailySolvedProvider = NotifierProvider<DailySolvedNotifier, Set<String>>(
  DailySolvedNotifier.new,
);
