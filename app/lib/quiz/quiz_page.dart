import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/quiz_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/problems/daily_progress.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_menu.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/quiz/widgets/quiz_hand.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/result/result_providers.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// 制限時間つきのクイズ（今日の問題など、[QuizArgs.timed]）の秒数。
const int kQuizTimeLimitSeconds = 30;

/// クイズ「あなたなら何を切る？」（仕様 3.4・6.7）。
///
/// 14 枚を表示して 1 枚選ぶ（ツモ牌は離す、副露は横、ドラ表示）。判定する軸（既定は
/// バランス）を選べる。答えると解析結果と照合して `quiz_answered` を送り、ストリークを
/// 記録して Result へ。「わからない」で答えずに Result へ。解析は画面を開いたときに
/// 始める（Result と同じ結果を使う）。13 枚と和了形の手は Result に直接進む。
/// 広告は出さない（仕様 9 章）。
class QuizPage extends ConsumerStatefulWidget {
  const QuizPage({super.key});

  @override
  ConsumerState<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends ConsumerState<QuizPage> {
  QuizArgs? _args;
  HandInput? _input;
  bool _initialized = false;
  bool _redirecting = false;
  int? _selected;
  StrategyAxis _axis = kDefaultAxis;
  bool _submitting = false;
  bool _completedLogged = false;
  Timer? _timer;
  int _secondsLeft = kQuizTimeLimitSeconds;
  final Stopwatch _watch = Stopwatch();

  String get _source =>
      _args?.source ?? (_args?.problemId != null ? 'problem' : 'manual');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = context.routeArgs<QuizArgs>();
    _args = args;
    if (args == null || !args.input.isAnalyzable) return;
    final input = args.input;
    final complete =
        input.isFourteen &&
        ref.read(analysisServiceProvider).shanten(input).shanten < 0;
    if (!input.isFourteen || complete) {
      // 13 枚（何を切るかが無い）と和了形はクイズにしない。
      _redirecting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          Routes.result,
          arguments: ResultArgs(
            input: input,
            problemId: args.problemId,
            source: _source,
            historyId: args.historyId,
          ),
        );
      });
      return;
    }
    _input = input.normalized();
    _watch.start();
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.analysisStarted,
            parameters: {'source': _source, 'hand_size': input.tileCount},
          ),
    );
    if (args.timed) {
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _secondsLeft--);
        if (_secondsLeft <= 0) {
          timer.cancel();
          _skip();
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  AnalysisRequest _request(bool pro) =>
      AnalysisRequest(_args!.input, deep: pro);

  void _logCompleted(AnalysisReport report) {
    if (_completedLogged) return;
    _completedLogged = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref
            .read(appAnalyticsProvider)
            .logEvent(
              AnalyticsEvent.analysisCompleted,
              parameters: {
                'source': _source,
                'hand_size': _args!.input.tileCount,
                'shanten': report.shanten.shanten < 0
                    ? 0
                    : report.shanten.shanten,
                'duration_ms': _watch.elapsedMilliseconds,
              },
            ),
      );
    });
  }

  void _changeAxis(StrategyAxis next) {
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.axisChanged,
            parameters: {
              'axis_from': _axis.name,
              'axis_to': next.name,
              'screen': 'quiz',
            },
          ),
    );
    setState(() => _axis = next);
  }

  Future<void> _submit() async {
    final input = _input;
    final index = _selected;
    if (input == null || index == null || _submitting) return;
    final chosenId = tileIdFromLabel(input.tiles[index]);
    final pro = ref.read(entitlementsProvider).pro;
    setState(() => _submitting = true);
    final AnalysisReport report;
    try {
      report = await ref.read(analysisReportProvider(_request(pro)).future);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.resultStrings.analysisFailed)),
      );
      return;
    }
    _timer?.cancel();
    final verdict = judgeChoice(report, chosenId, _axis);
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.quizAnswered,
            parameters: {
              'correct_axis': verdict.correctAxisCode,
              'selected_axis': _axis.name,
              'correct': verdict.correct ? 1 : 0,
            },
          ),
    );
    await ref
        .read(streakProvider.notifier)
        .recordAnswer(ref.read(clockProvider)());
    final args = _args!;
    // 公開問題ならサーバーへ回答を送り、分布・正解率を Result に渡す。送れなければ
    // （オフライン・Firebase 無効など）手元のエンジンの結果だけで進む。
    // 端末内の今日の問題は送らず、解答済みとして記録する（Today のチェック）。
    ProblemAnswerOutcome? outcome;
    final problemId = args.problemId;
    if (isLocalDailyProblemId(problemId)) {
      try {
        await ref.read(dailySolvedProvider.notifier).markSolved(problemId!);
      } catch (_) {
        // 記録できなくても結果へは進む。
      }
    } else if (problemId != null) {
      try {
        outcome = await ref
            .read(problemAnswerSubmitterProvider)
            .submitChoice(
              problemId: problemId,
              input: args.input,
              discardId: chosenId,
            )
            .timeout(const Duration(seconds: 6), onTimeout: () => null);
      } catch (_) {
        outcome = null;
      }
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacementNamed(
      Routes.result,
      arguments: ResultArgs(
        input: args.input,
        chosenDiscardId: chosenId,
        chosenAxis: _axis,
        problemId: args.problemId,
        problemOutcome: outcome,
        fromQuiz: true,
        source: _source,
        historyId: args.historyId,
      ),
    );
  }

  void _skip() {
    if (_submitting || !mounted) return;
    _timer?.cancel();
    final args = _args!;
    Navigator.of(context).pushReplacementNamed(
      Routes.result,
      arguments: ResultArgs(
        input: args.input,
        problemId: args.problemId,
        fromQuiz: true,
        source: _source,
        historyId: args.historyId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.quizStrings;
    final common = context.commonStrings;
    final args = _args;
    final input = _input;
    if (_redirecting) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (args == null || input == null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.title)),
        body: Center(child: Text(strings.noHand)),
      );
    }
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    // 開いたときに解析を始め、答えるまでに終わらせておく。
    final async = ref.watch(analysisReportProvider(_request(pro)));
    final report = async.valueOrNull;
    if (report != null) _logCompleted(report);

    final selected = _selected;
    final selectedName = selected == null
        ? null
        : common.tileName(input.tiles[selected]);
    final conditions = [
      strings.roundSeat(
        common.windName(input.roundWind),
        common.windName(input.seatWind),
      ),
      input.dealer ? common.dealer : common.nonDealer,
      if (input.turn != null) strings.turn(input.turn!),
    ];

    return Scaffold(
      key: const ValueKey('quiz-page'),
      appBar: AppBar(
        title: Text(strings.title),
        actions: [
          // 公開問題は通報・出題者のブロックができる（App Store 審査ガイドライン 1.2）。
          // 端末内の今日の問題は出題者がいないので出さない。
          if (args.problemId case final problemId?
              when !isLocalDailyProblemId(problemId))
            ProblemMenuButton(
              key: const ValueKey('quiz-menu'),
              problemId: problemId,
            ),
        ],
      ),
      // 手牌の卓だけは左右の余白を詰めて、狭い端末（幅 375pt）でも牌 1 枚の当たり判定を
      // 44pt 以上にする（他は通常の余白）。
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.xl),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (args.timed) ...[
                  _QuizTimer(secondsLeft: _secondsLeft),
                  const SizedBox(height: AppSpacing.md),
                ],
                _QuizConditions(conditions: conditions, input: input),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  strings.prompt,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: _HandMat(
              child: QuizHand(
                input: input,
                selectedIndex: selected,
                onTapTile: _submitting
                    ? null
                    : (index) => setState(
                        () => _selected = _selected == index ? null : index,
                      ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: _JudgeAxisCard(axis: _axis, onChanged: _changeAxis),
          ),
        ],
      ),
      bottomNavigationBar: _ConfirmBar(
        selectedLabel: selected == null ? null : input.tiles[selected],
        selectedName: selectedName,
        submitting: _submitting,
        onConfirm: selected == null || _submitting ? null : _submit,
        onSkip: _submitting ? null : _skip,
      ),
    );
  }
}

/// 制限時間（今日の問題）。残り 10 秒を切ったら朱にする。
class _QuizTimer extends StatelessWidget {
  const _QuizTimer({required this.secondsLeft});

  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    final strings = context.quizStrings;
    final theme = Theme.of(context);
    final urgent = secondsLeft <= 10;
    final color = urgent ? AppColors.vermilion : theme.colorScheme.primary;
    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 20, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(
          secondsLeft > 0 ? strings.secondsLeft(secondsLeft) : strings.timeUp,
          key: const ValueKey('quiz-timer'),
          style: theme.textTheme.titleSmall?.copyWith(color: color),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              minHeight: 6,
              color: color,
              value: (secondsLeft / kQuizTimeLimitSeconds).clamp(0.0, 1.0),
            ),
          ),
        ),
      ],
    );
  }
}

/// 局の条件（場風・自風・親子・巡目）とドラ。
class _QuizConditions extends StatelessWidget {
  const _QuizConditions({required this.conditions, required this.input});

  final List<String> conditions;
  final HandInput input;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Wrap(
      spacing: AppSpacing.xs + AppSpacing.xxs,
      runSpacing: AppSpacing.xs + AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final c in conditions)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm + AppSpacing.xxs,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              border: Border.all(color: scheme.outlineVariant),
              borderRadius: AppRadius.pillAll,
            ),
            child: Text(c, style: theme.textTheme.labelMedium),
          ),
        if (input.doraIndicators.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.xs),
            child: DoraView(indicators: input.doraIndicators),
          ),
      ],
    );
  }
}

/// 手牌を置く卓（ジェイドの面）。
class _HandMat extends StatelessWidget {
  const _HandMat({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.md),
      decoration: const BoxDecoration(
        borderRadius: AppRadius.lgAll,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.jadeBright, AppColors.jade],
        ),
      ),
      child: child,
    );
  }
}

/// 判定の方針（軸）。初めての人にも意味が伝わるよう、短い説明と既定（バランス）を添える。
class _JudgeAxisCard extends StatelessWidget {
  const _JudgeAxisCard({required this.axis, required this.onChanged});

  final StrategyAxis axis;
  final ValueChanged<StrategyAxis> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = context.quizStrings;
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  strings.judgeAxis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(strings.judgeAxisHelp, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          AxisSelector(
            axis: axis,
            onChanged: onChanged,
            keyPrefix: 'quiz-axis',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.resultStrings.axisHint(axis),
            key: const ValueKey('quiz-axis-hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 下部の確定ボタン（主）と「わからない」（従）。
class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.selectedLabel,
    required this.selectedName,
    required this.submitting,
    required this.onConfirm,
    required this.onSkip,
  });

  final String? selectedLabel;
  final String? selectedName;
  final bool submitting;
  final VoidCallback? onConfirm;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final strings = context.quizStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = selectedLabel;
    final name = selectedName;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            AppSpacing.md,
            AppSpacing.gutter,
            AppSpacing.xs,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                key: const ValueKey('quiz-confirm'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.lgAll,
                  ),
                  textStyle: theme.textTheme.titleMedium,
                ),
                onPressed: onConfirm,
                child: submitting
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (label != null) ...[
                            Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                color: AppColors.tileFace,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: TileImage(label, width: 20),
                            ),
                            const SizedBox(
                              width: AppSpacing.sm + AppSpacing.xxs,
                            ),
                          ],
                          Flexible(
                            child: Text(
                              name == null
                                  ? strings.confirmDisabled
                                  : strings.confirm(name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
              ),
              TextButton(
                key: const ValueKey('quiz-skip'),
                onPressed: onSkip,
                child: Text(strings.skip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
