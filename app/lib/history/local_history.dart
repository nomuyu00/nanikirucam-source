import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 解析・クイズの記録 1 件（設計書 5.1 `history_v1`）。
///
/// 手は [HandInput.toJson]（labels = `tiles`、ツモ = `tsumoIndex`、ドラ = `dora`、
/// 見えている牌 = `visible`、副露・風・巡目）で持つ。自分の選択と各軸の正解は牌の
/// ラベル（`1m` など）。画像は持たない（仕様 12 章）。
///
/// 撮るだけモード（仕様 6.5「解析せず保存」）で保存した手は [pending]（JSON は
/// `"pending": true`）。解析していないので [best]・[correct]・[reasonTags]・[shanten] は
/// 空で、[engineVersion] は空文字。履歴から開いて確定すると、同じ [id] の解析済みの
/// 記録に置き換える（[HistoryNotifier.replace]）。
class HistoryEntry extends Equatable {
  HistoryEntry({
    required this.id,
    required this.createdAt,
    required this.input,
    this.userChoice,
    this.axis,
    Map<StrategyAxis, List<String>> best = const {},
    this.correct,
    Iterable<String> reasonTags = const [],
    required this.engineVersion,
    this.problemId,
    this.source,
    this.shanten,
    this.pending = false,
  }) : best = Map.unmodifiable({
         for (final e in best.entries) e.key: List<String>.unmodifiable(e.value),
       }),
       reasonTags = List.unmodifiable(reasonTags);

  final String id;
  final DateTime createdAt;
  final HandInput input;

  /// クイズで選んだ牌のラベル。スキップ・13 枚は null。
  final String? userChoice;

  /// 正誤を判定した軸。
  final StrategyAxis? axis;

  /// 各軸の 1 位（同点はすべて）のラベル。13 枚は空。
  final Map<StrategyAxis, List<String>> best;

  /// [axis] で正解したか。回答していなければ null。
  final bool? correct;

  /// 判定した軸の正解の理由タグ（`ReasonTagCode.code`）。弱点分析に使う。
  final List<String> reasonTags;

  final String engineVersion;
  final String? problemId;

  /// どこから来た手か（`photo` / `manual` / `today` / `problem` など）。
  final String? source;

  /// 手のシャンテン数（14 枚は最良の打牌後、-1 は和了形）。
  final int? shanten;

  /// 撮るだけモードで保存し、まだ解析していない（未解析）。
  final bool pending;

  /// 撮るだけモードの未解析の記録（認識した手だけ。画像は持たない）。
  factory HistoryEntry.captured({
    required HandInput input,
    required DateTime now,
    String source = 'photo',
  }) => HistoryEntry(
    id: '${now.microsecondsSinceEpoch}',
    createdAt: now,
    input: input,
    engineVersion: '',
    source: source,
    pending: true,
  );

  bool get answered => userChoice != null && axis != null;

  /// [userChoice] が 1 位だった軸。
  List<StrategyAxis> get correctAxes => [
    if (userChoice != null)
      for (final axis in StrategyAxis.values)
        if (best[axis]?.contains(userChoice) ?? false) axis,
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'hand': input.toJson(),
    if (userChoice != null) 'userChoice': userChoice,
    if (axis != null) 'axis': axis!.name,
    if (best.isNotEmpty)
      'best': {for (final e in best.entries) e.key.name: e.value},
    if (correct != null) 'correct': correct,
    if (reasonTags.isNotEmpty) 'reasonTags': reasonTags,
    'engineVersion': engineVersion,
    if (problemId != null) 'problemId': problemId,
    if (source != null) 'source': source,
    if (shanten != null) 'shanten': shanten,
    if (pending) 'pending': true,
  };

  /// [toJson] の逆。壊れた記録は [FormatException]。
  factory HistoryEntry.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final createdAt = DateTime.tryParse('${json['createdAt']}');
    final hand = json['hand'];
    if (id is! String || createdAt == null || hand is! Map) {
      throw FormatException('HistoryEntry: 必須項目がない', json);
    }
    StrategyAxis? axisOf(Object? name) =>
        StrategyAxis.values.where((a) => a.name == name).firstOrNull;
    final bestJson = json['best'];
    final best = <StrategyAxis, List<String>>{};
    if (bestJson is Map) {
      for (final e in bestJson.entries) {
        final axis = axisOf(e.key);
        final value = e.value;
        if (axis != null && value is List) {
          best[axis] = [for (final v in value) '$v'];
        }
      }
    }
    final tags = json['reasonTags'];
    final correct = json['correct'];
    final shanten = json['shanten'];
    final userChoice = json['userChoice'];
    final problemId = json['problemId'];
    final source = json['source'];
    return HistoryEntry(
      id: id,
      createdAt: createdAt,
      input: HandInput.fromJson(hand.cast<String, Object?>()),
      userChoice: userChoice is String ? userChoice : null,
      axis: axisOf(json['axis']),
      best: best,
      correct: correct is bool ? correct : null,
      reasonTags: tags is List ? [for (final t in tags) '$t'] : const [],
      engineVersion: '${json['engineVersion'] ?? ''}',
      problemId: problemId is String ? problemId : null,
      source: source is String ? source : null,
      shanten: shanten is int ? shanten : null,
      pending: json['pending'] == true,
    );
  }

  @override
  List<Object?> get props => [
    id,
    createdAt,
    input,
    userChoice,
    axis,
    best,
    correct,
    reasonTags,
    engineVersion,
    problemId,
    source,
    shanten,
    pending,
  ];
}

/// `history_v1` の読み書き（SharedPreferences の 1 つの JSON 配列、新しい順）。
class LocalHistory {
  LocalHistory(this.prefs);

  static const preferenceKey = 'history_v1';

  /// 端末に残す最大件数。無料で見られるのは [kFreeHistoryCount] 件だが、Pro に
  /// なったときに過去分も見られるよう多めに残す。
  static const maxEntries = 500;

  final SharedPreferences prefs;

  /// 新しい順。壊れた記録は読み飛ばす。
  List<HistoryEntry> load() {
    final raw = prefs.getString(preferenceKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final entries = <HistoryEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          entries.add(HistoryEntry.fromJson(item.cast<String, Object?>()));
        } on FormatException {
          // 壊れた 1 件は捨てる。
        }
      }
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return entries;
    } on FormatException {
      debugPrint('[LocalHistory] history_v1 を読めませんでした');
      return const [];
    }
  }

  Future<void> save(List<HistoryEntry> entries) => prefs.setString(
    preferenceKey,
    jsonEncode([for (final e in entries.take(maxEntries)) e.toJson()]),
  );
}

/// 無料で見られる履歴の件数（仕様 5 章: 直近 20 件）。
const int kFreeHistoryCount = 20;

/// 履歴（新しい順）。Result が記録し、History と Home が読む。
class HistoryNotifier extends AsyncNotifier<List<HistoryEntry>> {
  @override
  Future<List<HistoryEntry>> build() async {
    final prefs = await ref.watch(sharedPreferencesProvider.future);
    return LocalHistory(prefs).load();
  }

  /// 1 件を先頭に足して保存する。
  Future<void> add(HistoryEntry entry) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final current = await future;
    final next = [
      entry,
      ...current,
    ].take(LocalHistory.maxEntries).toList();
    state = AsyncData(next);
    await LocalHistory(prefs).save(next);
  }

  /// [id] の記録を [entry] に置き換え、先頭に移して保存する（未解析の記録を解析済みに
  /// するとき。二重に数えない）。[id] が無ければ（消された後など）先頭に足す。
  Future<void> replace(String id, HistoryEntry entry) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final current = await future;
    final next = [
      entry,
      for (final e in current)
        if (e.id != id) e,
    ].take(LocalHistory.maxEntries).toList();
    state = AsyncData(next);
    await LocalHistory(prefs).save(next);
  }

  /// すべて消す。
  Future<void> clear() async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    state = const AsyncData([]);
    await prefs.remove(LocalHistory.preferenceKey);
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryNotifier, List<HistoryEntry>>(
      HistoryNotifier.new,
    );

/// 履歴の集計（Home の今週の正解率、History の弱点分析。仕様 6.2・6.11）。
class HistoryStats {
  const HistoryStats({
    required this.answered,
    required this.correct,
    required this.byAxis,
    required this.missedTags,
  });

  /// 回答した件数と正解した件数。
  final int answered;
  final int correct;

  /// 軸ごとの (回答, 正解)。回答の無い軸は入らない。
  final Map<StrategyAxis, ({int answered, int correct})> byAxis;

  /// 間違えた問題に多い理由タグ（コード, 件数）。多い順。
  final List<({String code, int count})> missedTags;

  double? get rate => answered == 0 ? null : correct / answered;

  factory HistoryStats.of(Iterable<HistoryEntry> entries) {
    var answered = 0;
    var correct = 0;
    final byAxis = <StrategyAxis, ({int answered, int correct})>{};
    final missed = <String, int>{};
    for (final e in entries) {
      final axis = e.axis;
      if (!e.answered || axis == null || e.correct == null) continue;
      answered++;
      final ok = e.correct!;
      if (ok) correct++;
      final prev = byAxis[axis] ?? (answered: 0, correct: 0);
      byAxis[axis] = (
        answered: prev.answered + 1,
        correct: prev.correct + (ok ? 1 : 0),
      );
      if (!ok) {
        for (final tag in e.reasonTags.toSet()) {
          missed.update(tag, (n) => n + 1, ifAbsent: () => 1);
        }
      }
    }
    final tags = [
      for (final e in missed.entries) (code: e.key, count: e.value),
    ]..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.code.compareTo(b.code);
      });
    return HistoryStats(
      answered: answered,
      correct: correct,
      byAxis: byAxis,
      missedTags: tags,
    );
  }

  /// [now] から 7 日以内の記録の集計（Home の「今週の正解率」）。
  factory HistoryStats.lastWeek(Iterable<HistoryEntry> entries, DateTime now) {
    final since = now.subtract(const Duration(days: 7));
    return HistoryStats.of(entries.where((e) => e.createdAt.isAfter(since)));
  }
}

/// 解析結果から履歴の 1 件を作る（Result が表示したときに記録する）。
///
/// [chosenId] はクイズで選んだ牌（スキップ・13 枚は null）、[axis] は判定した軸
/// （省略時はバランス）。理由タグは判定した軸の 1 位（同点はすべて）のタグ。
/// [id] は未解析の記録を置き換えるときにその ID を渡す（省略時は [now] から作る）。
HistoryEntry historyEntryFor({
  required HandInput input,
  required AnalysisReport report,
  int? chosenId,
  StrategyAxis? axis,
  String? problemId,
  String? source,
  required DateTime now,
  String? id,
}) {
  final judged = axis ?? StrategyAxis.balance;
  final best = <StrategyAxis, List<String>>{
    if (report.candidates.isNotEmpty)
      for (final a in StrategyAxis.values)
        a: [for (final id in report.bestByAxis[a] ?? const <int>[]) tileLabelOfId(id)],
  };
  final tags = <String>{
    for (final c in report.candidates)
      if ((report.bestByAxis[judged] ?? const <int>[]).contains(c.discardId))
        for (final tag in c.reasonTags) tag.code,
  };
  return HistoryEntry(
    id: id ?? '${now.microsecondsSinceEpoch}',
    createdAt: now,
    input: input,
    userChoice: chosenId == null ? null : tileLabelOfId(chosenId),
    axis: chosenId == null ? null : judged,
    best: best,
    correct: chosenId == null
        ? null
        : (report.bestByAxis[judged] ?? const <int>[]).contains(chosenId),
    reasonTags: tags,
    engineVersion: report.engineVersion,
    problemId: problemId,
    source: source,
    shanten: report.shanten.shanten,
  );
}
