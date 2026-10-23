import 'dart:collection';
import 'dart:isolate';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/app_settings.dart';

/// 解析エンジン（mahjong_core の [NanikiruEngine]）を別 Isolate で動かす窓口（設計書 4.8）。
///
/// 写真・手入力・ライブ・問題のどこからでも、解析はここを通す。
/// エンジン内の LRU は Isolate ごとに消えるので、結果の LRU はこちら（メイン Isolate）で持つ。
class AnalysisService {
  /// [ruleset] は設定（赤ドラ・喰いタン）から作る。[runner] を渡したとき（テスト）は
  /// [ruleset] を使わない。
  AnalysisService({
    Future<AnalysisReport> Function(HandState hand, bool deep)? runner,
    this.cacheSize = 50,
    Ruleset? ruleset,
  }) : ruleset = ruleset ?? Rulesets.mLeague(),
       _runner = runner ?? _isolateRunner(ruleset ?? Rulesets.mLeague());

  final Future<AnalysisReport> Function(HandState hand, bool deep) _runner;
  final int cacheSize;
  final Ruleset ruleset;
  final LinkedHashMap<String, Future<AnalysisReport>> _cache = LinkedHashMap();

  /// [input] を解析する。[deep] は Pro（経路列挙の詳細・2 段階先・リーチ助言）。
  ///
  /// [HandInput.validate] に通らない入力は [HandInputException] を投げる。
  Future<AnalysisReport> analyze(HandInput input, {required bool deep}) {
    final hand = input.toHandState();
    final key =
        '${analysisCacheKey(hand)}|$deep|${ruleset.redFives}|${ruleset.kuitan}';
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final future = _runner(hand, deep);
    _cache[key] = future;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
    // 失敗した結果はキャッシュに残さない。
    future.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_cache[key], future)) _cache.remove(key);
      },
    );
    return future;
  }

  /// シャンテン数だけ（ライブの前段・修正画面のプレビュー用。メイン Isolate で十分速い）。
  ShantenResult shanten(HandInput input) => shantenOf(input.toHandState());

  static Future<AnalysisReport> Function(HandState hand, bool deep)
  _isolateRunner(Ruleset ruleset) =>
      (hand, deep) => Isolate.run(
        () => DefaultNanikiruEngine(ruleset: ruleset).analyze(hand, deep: deep),
      );
}

/// mahjong_core のトップレベル関数 `shanten` の別名（同名の getter と区別するため）。
ShantenResult shantenOf(HandState hand) => shanten(hand);

/// 設定のルール（赤ドラの有無・喰いタン）をエンジンの [Ruleset] にする。
/// 赤ドラなしなら赤 5 は普通の 5 として数える（打点の赤ドラ枚数が 0 になる）。
Ruleset rulesetFromSettings({
  required bool redFives,
  required bool openTanyao,
}) =>
    Rulesets.mLeague().copyWith(redFives: redFives ? 3 : 0, kuitan: openTanyao);

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  final rules = ref.watch(
    appSettingsProvider.select((s) => (s.redFives, s.openTanyao)),
  );
  return AnalysisService(
    ruleset: rulesetFromSettings(redFives: rules.$1, openTanyao: rules.$2),
  );
});
