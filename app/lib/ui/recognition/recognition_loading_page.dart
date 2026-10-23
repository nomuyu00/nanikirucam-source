// 流用元: reference/agari_cam/lib/ui/recognition/recognition_loading_page.dart（2026-10-21 時点）
// 改修: 認識結果を RecognitionDraft（ツモ牌・副露候補つき）にして RecognitionArgs で渡す。
// 写真解析の無料枠（仕様 3.2）: 認識の前に尽きていないかを確かめ、認識に成功したら 1 回使う
// （失敗したときは使わない）。尽きていたら QuotaExhaustedPanel（動画で +3 / Pro / 手入力）。
// 撮るだけモード（AppSettings.quickCapture、仕様 6.5「解析せず保存」）: 認識できた手（13/14 枚）
// を解析も修正もせずに履歴へ「未解析」として保存し（画像は保存しない）、カメラに戻る。
// 認識が不完全・副露の候補があるときは保存せずに修正画面へ。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/camera/photo_quota.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/strings/camera_strings.dart';
import 'package:nanikiru_cam/l10n/strings/recognition_strings.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_editor.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';

class RecognitionLoadingPage extends ConsumerStatefulWidget {
  const RecognitionLoadingPage({super.key});

  @override
  ConsumerState<RecognitionLoadingPage> createState() =>
      _RecognitionLoadingPageState();
}

class _RecognitionLoadingPageState
    extends ConsumerState<RecognitionLoadingPage> {
  Uint8List? _imageBytes;
  bool _started = false;
  String? _error;

  /// 無料枠が尽きていて認識していない。
  bool _quotaBlocked = false;

  /// この写真で無料枠を 1 回使った（再試行では使わない）。
  bool _quotaConsumed = false;

  /// 修正画面に引き継ぐモード（点数計算なら撮るだけモードでも保存しない）。
  HandEntryMode _mode = HandEntryMode.solve;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    final loadingArgs = context.routeArgs<RecognitionLoadingArgs>();
    _mode = loadingArgs?.mode ?? HandEntryMode.solve;
    final imageBytes = loadingArgs?.imageBytes;
    if (imageBytes == null) {
      _error = context.recognitionStrings.imageLoadFailed;
      return;
    }

    _imageBytes = imageBytes;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recognize(imageBytes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.recognitionStrings;
    return Scaffold(
      appBar: AppBar(title: Text(strings.loadingTitle)),
      body: SafeArea(
        child: Center(
          child: _quotaBlocked
              ? SingleChildScrollView(
                  child: QuotaExhaustedPanel(
                    onUnlocked: () {
                      final bytes = _imageBytes;
                      if (!mounted || bytes == null) return;
                      setState(() => _quotaBlocked = false);
                      _recognize(bytes);
                    },
                    onManualInput: () => _openRecognition(
                      RecognitionArgs(
                        draft: RecognitionDraft.empty,
                        imageBytes: _imageBytes,
                        mode: _mode,
                      ),
                    ),
                  ),
                )
              : _error == null
              ? _loadingView(strings)
              : _errorView(strings),
        ),
      ),
    );
  }

  Widget _loadingView(RecognitionStrings strings) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 20),
          Text(
            strings.loadingMessage,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            strings.loadingHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorView(RecognitionStrings strings) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(strings.retake),
              ),
              OutlinedButton.icon(
                onPressed: () => _openRecognition(
                  RecognitionArgs(
                    draft: RecognitionDraft.empty,
                    imageBytes: _imageBytes,
                    mode: _mode,
                  ),
                ),
                icon: const Icon(Icons.keyboard_alt_outlined),
                label: Text(strings.manualInput),
              ),
              ElevatedButton.icon(
                onPressed: _imageBytes == null
                    ? null
                    : () {
                        setState(() => _error = null);
                        _recognize(_imageBytes!);
                      },
                icon: const Icon(Icons.refresh),
                label: Text(strings.reanalyze),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _recognize(Uint8List imageBytes) async {
    if (!_quotaConsumed && ref.read(quotaProvider).exhausted) {
      setState(() => _quotaBlocked = true);
      return;
    }
    final tflite = ref.read(tfliteServiceProvider);
    final strings = context.recognitionStrings;
    final analytics = ref.read(appAnalyticsProvider);
    const source = 'camera';
    final watch = Stopwatch()..start();
    var failureCode = 'model_initialization_failed';
    var recognitionCompleted = false;
    unawaited(
      analytics.logEvent(
        AnalyticsEvent.recognitionStarted,
        parameters: {'source': source},
      ),
    );
    try {
      await tflite.ensureInitialized();
      if (!tflite.isAvailable) {
        throw Exception(strings.modelFailed);
      }
      failureCode = 'inference_failed';
      final outcome = await tflite.recognize(imageBytes);
      final selection = outcome?.selection;
      if (outcome == null ||
          selection == null ||
          selection.detections.isEmpty) {
        failureCode = 'no_tiles';
        throw Exception(strings.noTiles);
      }

      recognitionCompleted = true;
      final draft = outcome.toDraft();
      final lowConfidence = draft.lowConfidenceIndices().length;
      unawaited(
        analytics.logEvent(
          AnalyticsEvent.recognitionSucceeded,
          parameters: {
            'source': source,
            'duration_ms': watch.elapsedMilliseconds,
            'tile_count': selection.detections.length,
            'valid_hand': selection.isComplete ? 1 : 0,
            'low_confidence_tiles': lowConfidence,
            'avg_confidence_pct': (selection.averageScore * 100).round(),
            'recognition_strategy': outcome.strategy,
            'model_version': TfliteService.modelVersion,
          },
        ),
      );
      debugPrint(
        '[RecognitionLoadingPage] ${outcome.strategy} q=${outcome.quarterTurns} '
        '(${outcome.inferenceCount} runs, ${watch.elapsedMilliseconds}ms): '
        '${draft.labels.join(', ')}'
        '${draft.tsumoIndex == null ? '' : ' tsumo=${draft.tsumoIndex}'}'
        '${draft.melds.isEmpty ? '' : ' melds=${draft.melds.length}'}',
      );

      if (!_quotaConsumed) {
        final consumed = await ref.read(quotaProvider.notifier).tryConsume();
        if (!mounted) return;
        if (!consumed) {
          setState(() => _quotaBlocked = true);
          return;
        }
        _quotaConsumed = true;
      }
      if (!mounted) return;
      final args = RecognitionArgs(
        draft: draft,
        imageBytes: imageBytes,
        imageQuarterTurns: outcome.quarterTurns,
        notice: selection.isComplete ? null : strings.incompleteNotice,
        mode: _mode,
      );
      if (await _saveQuickCapture(args, complete: selection.isComplete)) {
        return;
      }
      if (!mounted) return;
      await _openRecognition(args);
    } catch (error) {
      if (!recognitionCompleted) {
        unawaited(
          analytics.logEvent(
            AnalyticsEvent.recognitionFailed,
            parameters: {
              'source': source,
              'duration_ms': watch.elapsedMilliseconds,
              'error_code': failureCode,
            },
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// 撮るだけモード: 認識した手を履歴に「未解析」として保存し、「保存しました」を出して
  /// カメラに戻る（続けて撮れる）。保存したら true。
  ///
  /// 認識が不完全（13/14 枚でない・同じ牌が 5 枚以上など）か、副露の候補がある（鳴きの
  /// 確認が要る）ときは保存せず false（修正画面へ進む）。確度の低い牌はそのまま保存し、
  /// 履歴から開いたときに修正画面で直せる。
  Future<bool> _saveQuickCapture(
    RecognitionArgs args, {
    required bool complete,
  }) async {
    if (!ref.read(appSettingsProvider).quickCapture) return false;
    // 点数計算（Pro）は和了牌や条件を確かめてから計算するので、保存せず修正画面へ。
    if (args.mode == HandEntryMode.score) return false;
    final draft = args.draft;
    if (!complete || draft.melds.isNotEmpty) return false;
    final editor = RecognitionEditor.fromArgs(args);
    final input = editor.input.normalized();
    editor.dispose();
    if (!input.isAnalyzable) return false;
    await ref
        .read(historyProvider.notifier)
        .add(
          HistoryEntry.captured(input: input, now: ref.read(clockProvider)()),
        );
    if (!mounted) return true;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        key: const ValueKey('quick-capture-saved'),
        content: Text(context.cameraStrings.quickCaptureSaved),
      ),
    );
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      await navigator.pushReplacementNamed(Routes.camera);
    }
    return true;
  }

  Future<void> _openRecognition(RecognitionArgs args) async {
    await Navigator.of(
      context,
    ).pushReplacementNamed(Routes.recognition, arguments: args);
  }
}
