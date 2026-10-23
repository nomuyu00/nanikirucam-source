import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/core/di.dart';

/// 設定（設計書 5.1 `settings_v1`、仕様 6.11 Settings）。
///
/// 契約: 画面・ライブ・通知はここを読む。設定画面と永続化は課金・設定担当が実装する。
/// 項目を足すのは設定担当だけ（他の担当は読むだけ）。既存の名前は変えない。
/// 言語は別（`core/app_language.dart` の `appLocaleProvider`、`app_locale_v1`）。
class AppSettings {
  const AppSettings({
    this.redFives = true,
    this.openTanyao = true,
    this.quickCapture = false,
    this.notifyDaily = true,
    this.notifyWeekly = true,
    this.notifyAnswers = true,
    this.notifyStreak = true,
    this.notifyLiveSummary = true,
    this.liveSound = false,
    this.liveDefaultAxis = StrategyAxis.balance,
    this.liveHaptics = true,
    this.liveLockBrightness = false,
  });

  /// 赤ドラあり（各色 1 枚）。
  final bool redFives;

  /// 喰いタンあり。
  final bool openTanyao;

  /// 撮るだけモード（仕様 6.5）: 撮影して認識した手を、解析せずに履歴へ保存する。続けて撮れる。
  /// 写真は保存しない。履歴から確認・解析できる。
  final bool quickCapture;

  /// 今日の問題の通知（FCM トピック `daily`）。
  final bool notifyDaily;

  /// 週間成績・今週の難問の通知（FCM トピック `weekly`）。
  final bool notifyWeekly;

  /// 自分の問題への回答到達の通知。
  final bool notifyAnswers;

  /// ストリークのリマインド（21:00 のローカル通知）。
  final bool notifyStreak;

  /// ライブを使った 24 時間後に「昨日の対局サマリー」を知らせるローカル通知（仕様 11 章）。
  final bool notifyLiveSummary;

  /// ライブで案内が出たときに短い音を鳴らす。
  final bool liveSound;

  /// ライブを始めたときの戦略軸（仕様 6.11。既定はバランス）。
  final StrategyAxis liveDefaultAxis;

  /// ライブで案内が変わったら軽く振動する（仕様 3.1.3 のハプティクス）。
  final bool liveHaptics;

  /// ライブ中は画面の明るさを固定する（始めたときの明るさのまま。自動調整で暗くならない）。
  final bool liveLockBrightness;

  /// どれかの通知が有効か（OS の通知許可を求めるかの判断に使う）。
  bool get anyNotification =>
      notifyDaily ||
      notifyWeekly ||
      notifyAnswers ||
      notifyStreak ||
      notifyLiveSummary;

  AppSettings copyWith({
    bool? redFives,
    bool? openTanyao,
    bool? quickCapture,
    bool? notifyDaily,
    bool? notifyWeekly,
    bool? notifyAnswers,
    bool? notifyStreak,
    bool? notifyLiveSummary,
    bool? liveSound,
    StrategyAxis? liveDefaultAxis,
    bool? liveHaptics,
    bool? liveLockBrightness,
  }) => AppSettings(
    redFives: redFives ?? this.redFives,
    openTanyao: openTanyao ?? this.openTanyao,
    quickCapture: quickCapture ?? this.quickCapture,
    notifyDaily: notifyDaily ?? this.notifyDaily,
    notifyWeekly: notifyWeekly ?? this.notifyWeekly,
    notifyAnswers: notifyAnswers ?? this.notifyAnswers,
    notifyStreak: notifyStreak ?? this.notifyStreak,
    notifyLiveSummary: notifyLiveSummary ?? this.notifyLiveSummary,
    liveSound: liveSound ?? this.liveSound,
    liveDefaultAxis: liveDefaultAxis ?? this.liveDefaultAxis,
    liveHaptics: liveHaptics ?? this.liveHaptics,
    liveLockBrightness: liveLockBrightness ?? this.liveLockBrightness,
  );

  Map<String, Object> toJson() => {
    'redFives': redFives,
    'openTanyao': openTanyao,
    'quickCapture': quickCapture,
    'notifyDaily': notifyDaily,
    'notifyWeekly': notifyWeekly,
    'notifyAnswers': notifyAnswers,
    'notifyStreak': notifyStreak,
    'notifyLiveSummary': notifyLiveSummary,
    'liveSound': liveSound,
    'liveDefaultAxis': liveDefaultAxis.name,
    'liveHaptics': liveHaptics,
    'liveLockBrightness': liveLockBrightness,
  };

  /// 保存された値から復元する。無い・型が違う項目は既定値。
  static AppSettings fromJson(Object? json) {
    if (json is! Map) return const AppSettings();
    const defaults = AppSettings();
    bool read(String key, bool fallback) {
      final value = json[key];
      return value is bool ? value : fallback;
    }

    return AppSettings(
      redFives: read('redFives', defaults.redFives),
      openTanyao: read('openTanyao', defaults.openTanyao),
      quickCapture: read('quickCapture', defaults.quickCapture),
      notifyDaily: read('notifyDaily', defaults.notifyDaily),
      notifyWeekly: read('notifyWeekly', defaults.notifyWeekly),
      notifyAnswers: read('notifyAnswers', defaults.notifyAnswers),
      notifyStreak: read('notifyStreak', defaults.notifyStreak),
      notifyLiveSummary: read('notifyLiveSummary', defaults.notifyLiveSummary),
      liveSound: read('liveSound', defaults.liveSound),
      liveDefaultAxis:
          StrategyAxis.values
              .where((a) => a.name == json['liveDefaultAxis'])
              .firstOrNull ??
          defaults.liveDefaultAxis,
      liveHaptics: read('liveHaptics', defaults.liveHaptics),
      liveLockBrightness: read(
        'liveLockBrightness',
        defaults.liveLockBrightness,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings && mapEquals(other.toJson(), toJson());

  @override
  int get hashCode => Object.hashAll(toJson().values);

  @override
  String toString() => 'AppSettings(${toJson()})';
}

class AppSettingsNotifier extends Notifier<AppSettings> {
  /// SharedPreferences のキー（設計書 5.1）。
  static const preferenceKey = 'settings_v1';

  bool _changed = false;

  @override
  AppSettings build() {
    unawaited(_load());
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final raw = prefs.getString(preferenceKey);
      // 読み込み中に画面から変更されていたら、そちらを優先する。
      if (raw == null || _changed) return;
      state = AppSettings.fromJson(jsonDecode(raw));
    } catch (error) {
      debugPrint('[AppSettings] load failed: $error');
    }
  }

  /// 設定を丸ごと置き換えて保存する。
  void replace(AppSettings next) {
    _changed = true;
    state = next;
    unawaited(_save(next));
  }

  /// 一部だけ変える（`update((s) => s.copyWith(quickCapture: true))`）。
  void update(AppSettings Function(AppSettings current) change) =>
      replace(change(state));

  /// 端末のデータ削除のあと、既定値に戻して保存データも消す。
  Future<void> reset() async {
    _changed = true;
    state = const AppSettings();
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.remove(preferenceKey);
    } catch (_) {}
  }

  Future<void> _save(AppSettings value) async {
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      await prefs.setString(preferenceKey, jsonEncode(value.toJson()));
    } catch (error) {
      debugPrint('[AppSettings] save failed: $error');
    }
  }
}

final appSettingsProvider = NotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
