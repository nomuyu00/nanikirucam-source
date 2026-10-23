import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ライブで和了した 1 回（保存用）。
class LiveWinRecord {
  const LiveWinRecord({
    required this.han,
    required this.fu,
    required this.points,
    this.yaku = const [],
    this.winType = 'tsumo',
    this.rank = 'none',
    this.hand,
  });

  final int han;
  final int fu;
  final int points;

  /// 役の名前（日本語。表示は文言側で訳す）。
  final List<String> yaku;

  /// `tsumo` / `ron`。
  final String winType;

  /// `none` / `mangan` / `haneman` / `baiman` / `sanbaiman` / `yakuman`。
  final String rank;

  /// 和了した手（共有カードに渡す）。
  final HandInput? hand;

  LiveWinSummary toSummary() =>
      LiveWinSummary(han: han, fu: fu, points: points, yaku: yaku);

  Map<String, Object?> toJson() => {
    'han': han,
    'fu': fu,
    'points': points,
    'yaku': yaku,
    'winType': winType,
    'rank': rank,
    if (hand != null) 'hand': hand!.toJson(),
  };

  static LiveWinRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    int i(Object? v) => v is int ? v : 0;
    HandInput? hand;
    final h = json['hand'];
    if (h is Map) {
      try {
        hand = HandInput.fromJson(h.cast<String, Object?>());
      } catch (_) {}
    }
    final yaku = json['yaku'];
    return LiveWinRecord(
      han: i(json['han']),
      fu: i(json['fu']),
      points: i(json['points']),
      yaku: yaku is List ? [for (final y in yaku) '$y'] : const [],
      winType: json['winType'] == 'ron' ? 'ron' : 'tsumo',
      rank: json['rank'] is String ? json['rank'] as String : 'none',
      hand: hand,
    );
  }
}

/// ライブの 1 回（設計書 5.1 `live_sessions_v1` の `LiveSession`）。
class LiveSession {
  const LiveSession({
    required this.startedAt,
    required this.durationSec,
    this.adviceCount = 0,
    this.followedCount = 0,
    this.followChecks = 0,
    this.wins = const [],
    this.endedBy = 'user',
  });

  final DateTime startedAt;
  final int durationSec;

  /// 案内を出した回数（13 枚・14 枚の両方。同じ手は 1 回）。
  final int adviceCount;

  /// 14 枚の案内のあと、次の 13 枚で案内した牌が切られていた回数。
  final int followedCount;

  /// 採用を判定できた回数（採用率の分母）。
  final int followChecks;

  final List<LiveWinRecord> wins;

  /// `user` / `trial_limit` / `battery` / `thermal` / `background`。
  final String endedBy;

  /// 採用率（判定できなければ null）。
  double? get followRate =>
      followChecks == 0 ? null : followedCount / followChecks;

  LiveSummaryArgs toSummaryArgs() => LiveSummaryArgs(
    startedAt: startedAt,
    durationSec: durationSec,
    adviceCount: adviceCount,
    followedCount: followedCount,
    followChecks: followChecks,
    wins: [for (final w in wins) w.toSummary()],
    endedBy: endedBy,
  );

  Map<String, Object?> toJson() => {
    'startedAt': startedAt.toIso8601String(),
    'durationSec': durationSec,
    'adviceCount': adviceCount,
    'followedCount': followedCount,
    'followChecks': followChecks,
    'wins': [for (final w in wins) w.toJson()],
    'endedBy': endedBy,
  };

  static LiveSession? fromJson(Object? json) {
    if (json is! Map) return null;
    final started = DateTime.tryParse('${json['startedAt']}');
    if (started == null) return null;
    int i(Object? v) => v is int && v >= 0 ? v : 0;
    final wins = json['wins'];
    return LiveSession(
      startedAt: started,
      durationSec: i(json['durationSec']),
      adviceCount: i(json['adviceCount']),
      followedCount: i(json['followedCount']),
      followChecks: i(json['followChecks']),
      wins: [
        if (wins is List)
          for (final w in wins) ?LiveWinRecord.fromJson(w),
      ],
      endedBy: json['endedBy'] is String ? json['endedBy'] as String : 'user',
    );
  }
}

/// `live_sessions_v1` の読み書き（新しい順に最大 [maxSessions] 件）。
class LiveSessionStore {
  LiveSessionStore(this._prefs);

  static const String preferenceKey = 'live_sessions_v1';
  static const int maxSessions = 200;

  final SharedPreferences _prefs;

  /// 保存したセッション（新しい順）。
  List<LiveSession> load() {
    try {
      final raw = _prefs.getString(preferenceKey);
      if (raw == null) return const [];
      final json = jsonDecode(raw);
      if (json is! List) return const [];
      return [for (final s in json) ?LiveSession.fromJson(s)];
    } catch (error) {
      debugPrint('[LiveSessionStore] load failed: $error');
      return const [];
    }
  }

  Future<void> add(LiveSession session) async {
    final sessions = [session, ...load()].take(maxSessions).toList();
    try {
      await _prefs.setString(
        preferenceKey,
        jsonEncode([for (final s in sessions) s.toJson()]),
      );
    } catch (error) {
      debugPrint('[LiveSessionStore] save failed: $error');
    }
  }

  /// [startedAt] のセッション（サマリー画面で採用率の分母などを引く）。
  LiveSession? find(DateTime startedAt) {
    for (final s in load()) {
      if (s.startedAt == startedAt) return s;
    }
    return null;
  }

  /// 端末のデータ削除。
  Future<void> clear() async {
    try {
      await _prefs.remove(preferenceKey);
    } catch (_) {}
  }
}
