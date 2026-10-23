import 'package:equatable/equatable.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';

/// 解析の依頼（手と、Pro の詳しい解析か）。
class AnalysisRequest extends Equatable {
  const AnalysisRequest(this.input, {required this.deep});

  final HandInput input;

  /// Pro（または解説を 1 回だけ開けたとき）の詳しい解析。
  final bool deep;

  @override
  List<Object?> get props => [input, deep];
}

/// Quiz・Result・CandidateDetail・Explanation が共有する解析結果。
///
/// 中身は [analysisServiceProvider]（別 Isolate、結果は LRU で保持）。画面を閉じると
/// provider は破棄されるが、同じ手をもう一度開いたときはサービスのキャッシュから返る。
final analysisReportProvider = FutureProvider.autoDispose
    .family<AnalysisReport, AnalysisRequest>((ref, request) {
      return ref
          .watch(analysisServiceProvider)
          .analyze(request.input, deep: request.deep);
    });

/// 解説を動画広告で 1 回だけ開けた手（設計書 10 章 `ExplanationUnlock.once`）。
///
/// キーは手の解析キー（`analysisCacheKey`）。アプリを閉じるまで有効（端末には保存しない）。
class ExplanationUnlocks extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  static String keyOf(HandInput input) =>
      analysisCacheKey(input.toHandState());

  bool isUnlocked(HandInput input) => state.contains(keyOf(input));

  void unlock(HandInput input) => state = {...state, keyOf(input)};
}

final explanationUnlocksProvider =
    NotifierProvider<ExplanationUnlocks, Set<String>>(ExplanationUnlocks.new);
