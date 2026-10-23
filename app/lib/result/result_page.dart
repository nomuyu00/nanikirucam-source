import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mahjong_core/mahjong_core.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/l10n/strings/result_strings.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/report_sheet.dart';
import 'package:nanikiru_cam/result/reason_text.dart';
import 'package:nanikiru_cam/result/result_logic.dart';
import 'package:nanikiru_cam/result/result_providers.dart';
import 'package:nanikiru_cam/result/widgets/candidate_card.dart';
import 'package:nanikiru_cam/result/widgets/hand_view.dart';
import 'package:nanikiru_cam/result/widgets/result_chips.dart';
import 'package:nanikiru_cam/result/widgets/thirteen_view.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/section_header.dart';
import 'package:nanikiru_cam/ui/widgets/state_views.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';
import 'package:nanikiru_cam/win/widgets/win_score_entry.dart';

/// 結果（仕様 4.6・6.8）。
///
/// 14 枚: 3 軸の切り替え（既定はバランス）、一択／軸ごとのバッジ、クイズの答えとの比較、
/// 候補（無料は上位 3 件、Pro は全件）。13 枚: 待ち・役なし判定・リーチ可否（[ThirteenView]）。
/// 和了形なら役と点数。下部に「次の手を撮る」「シェア」「友達に出題」とバナー（無料のみ）。
class ResultPage extends ConsumerStatefulWidget {
  const ResultPage({super.key});

  @override
  ConsumerState<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends ConsumerState<ResultPage> {
  ResultArgs? _args;
  StrategyAxis _axis = kDefaultAxis;
  bool _initialized = false;
  bool _viewed = false;
  final Stopwatch _watch = Stopwatch();

  String get _source =>
      _args?.source ?? (_args?.problemId != null ? 'problem' : 'manual');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final args = context.routeArgs<ResultArgs>();
    _args = args;
    if (args == null) return;
    _axis = args.chosenAxis ?? kDefaultAxis;
    _watch.start();
    if (!args.fromQuiz) {
      unawaited(
        ref
            .read(appAnalyticsProvider)
            .logEvent(
              AnalyticsEvent.analysisStarted,
              parameters: {
                'source': _source,
                'hand_size': args.input.tileCount,
              },
            ),
      );
    }
  }

  void _onReport(AnalysisReport report, bool pro) {
    final args = _args!;
    final analytics = ref.read(appAnalyticsProvider);
    final handSize = args.input.tileCount;
    final shanten = report.shanten.shanten < 0 ? 0 : report.shanten.shanten;
    if (!args.fromQuiz) {
      unawaited(
        analytics.logEvent(
          AnalyticsEvent.analysisCompleted,
          parameters: {
            'source': _source,
            'hand_size': handSize,
            'shanten': shanten,
            'duration_ms': _watch.elapsedMilliseconds,
          },
        ),
      );
    }
    unawaited(
      analytics.logEvent(
        AnalyticsEvent.resultViewed,
        parameters: {
          'source': _source,
          'hand_size': handSize,
          'shanten': shanten,
          'gate': pro ? 'pro' : 'free',
        },
      ),
    );
    ref.read(interstitialControllerProvider).onResultViewed();
    if (args.saveToHistory) {
      final history = ref.read(historyProvider.notifier);
      final pendingId = args.historyId;
      final entry = historyEntryFor(
        input: args.input,
        report: report,
        chosenId: args.chosenDiscardId,
        axis: args.chosenAxis,
        problemId: args.problemId,
        source: _source,
        now: ref.read(clockProvider)(),
        id: pendingId,
      );
      // 撮るだけモードの未解析の記録から来たら、その記録を解析済みに置き換える。
      unawaited(
        pendingId == null
            ? history.add(entry)
            : history.replace(pendingId, entry),
      );
    }
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
              'screen': 'result',
            },
          ),
    );
    setState(() => _axis = next);
  }

  void _openCandidate(DiscardCandidate c, bool pro) {
    final args = _args!;
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.candidateOpened,
            parameters: {
              'candidate_rank': c.rankByAxis[_axis] ?? 0,
              'axis': _axis.name,
              'gate': pro ? 'pro' : 'free',
            },
          ),
    );
    Navigator.of(context).pushNamed(
      Routes.candidateDetail,
      arguments: CandidateDetailArgs(
        input: args.input,
        discardId: c.discardId,
        axis: _axis,
      ),
    );
  }

  Future<void> _nextHand() async {
    await ref.read(interstitialControllerProvider).maybeShowBeforeNextHand();
    if (!mounted) return;
    await Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.camera, (route) => route.isFirst);
  }

  void _logShare(String variant) {
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(
            AnalyticsEvent.shareTapped,
            parameters: {'share_variant': variant, 'source': _source},
          ),
    );
  }

  void _openShareCard(ShareCardKind kind) {
    final args = _args!;
    _logShare(kind == ShareCardKind.problem ? 'quiz' : 'result');
    Navigator.of(context).pushNamed(
      Routes.shareCard,
      arguments: ShareCardArgs(
        kind: kind,
        input: args.input,
        chosenDiscardId: kind == ShareCardKind.result
            ? args.chosenDiscardId
            : null,
        // 端末内の今日の問題は公開問題ではない（QR・回答数の取得先が無い）ので渡さない。
        problemId: isLocalDailyProblemId(args.problemId)
            ? null
            : args.problemId,
        outcome: kind == ShareCardKind.result ? args.problemOutcome : null,
      ),
    );
  }

  Future<void> _share() async {
    final args = _args!;
    if (!args.input.isFourteen) {
      _openShareCard(ShareCardKind.result);
      return;
    }
    final s = context.resultStrings;
    final kind = await showModalBottomSheet<ShareCardKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('share-result'),
              leading: const Icon(Icons.emoji_events_outlined),
              title: Text(s.shareResultCard),
              subtitle: Text(s.shareResultCardBody),
              onTap: () => Navigator.of(context).pop(ShareCardKind.result),
            ),
            ListTile(
              key: const ValueKey('share-problem'),
              leading: const Icon(Icons.help_outline),
              title: Text(s.shareProblemCard),
              subtitle: Text(
                ref.read(onlineFeaturesProvider)
                    ? s.shareProblemCardBody
                    : s.shareProblemCardBodyOffline,
              ),
              onTap: () => Navigator.of(context).pop(ShareCardKind.problem),
            ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    _openShareCard(kind);
  }

  void _publish() {
    _logShare('quiz');
    Navigator.of(
      context,
    ).pushNamed(Routes.publish, arguments: PublishArgs(input: _args!.input));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final args = _args;
    if (args == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.title)),
        body: Center(child: Text(s.noHand)),
      );
    }
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    final request = AnalysisRequest(args.input, deep: pro);
    final async = ref.watch(analysisReportProvider(request));
    final report = async.valueOrNull;
    if (report != null && !_viewed) {
      _viewed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onReport(report, pro);
      });
    }

    // 通報は公開問題だけ（端末内の今日の問題には出題者がいない）。
    final problemId = isLocalDailyProblemId(args.problemId)
        ? null
        : args.problemId;
    return Scaffold(
      key: const ValueKey('result-page'),
      appBar: AppBar(
        title: Text(s.title),
        actions: [
          if (problemId != null)
            PopupMenuButton<String>(
              key: const ValueKey('result-menu'),
              onSelected: (_) => showReportProblemSheet(
                context,
                repository: ref.read(problemRepositoryProvider),
                problemId: problemId,
              ),
              itemBuilder: (context) => [
                PopupMenuItem(
                  key: const ValueKey('result-report'),
                  value: 'report',
                  child: Text(s.reportProblem),
                ),
              ],
            ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        data: (report) => _content(context, report, pro),
        loading: () => LoadingState(message: s.analyzing),
        error: (error, _) => EmptyState.error(
          message: s.analysisFailed,
          action: OutlinedButton(
            onPressed: () => ref.invalidate(analysisReportProvider(request)),
            child: Text(s.retry),
          ),
        ),
      ),
      bottomNavigationBar: _bottomBar(context, args, pro),
    );
  }

  Widget _bottomBar(BuildContext context, ResultArgs args, bool pro) {
    final s = context.resultStrings;
    final fourteen = args.input.isFourteen;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(),
          // 主ボタンは「次の手を撮る」（右・塗り）。共有はアイコン、出題は枠線で従に。
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + AppSpacing.xxs,
              AppSpacing.md,
              AppSpacing.sm + AppSpacing.xxs,
            ),
            child: Row(
              children: [
                Tooltip(
                  message: s.share,
                  child: OutlinedButton(
                    key: const ValueKey('result-share'),
                    onPressed: _share,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(52, 52),
                      padding: EdgeInsets.zero,
                    ),
                    child: Semantics(
                      label: s.share,
                      child: const Icon(Icons.ios_share_rounded, size: 22),
                    ),
                  ),
                ),
                if (fourteen) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('result-publish'),
                      onPressed: _publish,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                      ),
                      // オンライン機能が無い版は「公開」ではなく画像の共有。
                      child: _FitLabel(
                        ref.watch(onlineFeaturesProvider)
                            ? s.publish
                            : s.shareProblemCardButton,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: fourteen ? 1 : 2,
                  child: FilledButton.icon(
                    key: const ValueKey('result-next-hand'),
                    onPressed: _nextHand,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 52),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                    ),
                    icon: const Icon(Icons.photo_camera_outlined, size: 20),
                    label: _FitLabel(s.nextHand),
                  ),
                ),
              ],
            ),
          ),
          if (!pro) const AdBannerSlot(placement: AdPlacement.resultBanner),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, AnalysisReport report, bool pro) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final args = _args!;
    final input = args.input.normalized();
    final theme = Theme.of(context);
    final chosen = args.chosenDiscardId;

    // 上から: 手牌（問題）→ クイズの判定 → 結論（いま選んでいる軸のおすすめ）と軸の切り替え
    // → 3 軸の答えの関係 → みんなの回答 → 候補の一覧 → 免責。
    final children = <Widget>[
      HandView(
        input: input,
        highlightIds: {?chosen},
        tileKeyPrefix: 'result-tile',
      ),
      const SizedBox(height: AppSpacing.md),
    ];

    if (report.candidates.isEmpty) {
      if (report.thirteen != null) {
        children.add(ThirteenView(report: report, input: args.input, pro: pro));
      }
    } else {
      if (report.shanten.shanten < 0) {
        // 和了形なら役と点数（ツモ固定の簡易表示）と、その直下に詳細（Pro）への導線。
        children.addAll([
          WinCard(report: report),
          const SizedBox(height: AppSpacing.sm),
          WinScoreEntry(input: args.input, pro: pro),
          const SizedBox(height: AppSpacing.md),
        ]);
      }
      final ordered = orderedCandidates(report, _axis);
      final visible = pro
          ? ordered
          : ordered.take(kFreeCandidateCount).toList();
      final top = ordered.first;
      children.addAll([
        if (chosen != null)
          _VerdictCard(
            report: report,
            chosenId: chosen,
            axis: args.chosenAxis ?? kDefaultAxis,
          )
        else if (args.fromQuiz)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(s.skipped, style: theme.textTheme.bodySmall),
          ),
        _ConclusionCard(
          report: report,
          axis: _axis,
          top: top,
          summary:
              '${common.shanten(report.shanten.shanten)}  ·  '
              '${s.ukeireTotal(top.ukeire.total)}',
          selector: AxisSelector(
            axis: _axis,
            onChanged: _changeAxis,
            keyPrefix: 'result-axis',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _AgreementBanner(
          report: report,
          showAnswers: chosen == null,
          online: ref.watch(onlineFeaturesProvider),
        ),
        if (args.problemOutcome case final outcome?)
          if (outcome.stats.total > 0)
            _CommunityCard(
              outcome: outcome,
              chosenId: chosen,
              answerIds: bestOf(report, StrategyAxis.balance),
            ),
        SectionHeader(
          s.candidatesTitle,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.xs,
          ),
        ),
        for (final c in visible)
          CandidateCard(
            report: report,
            candidate: c,
            axis: _axis,
            pro: pro,
            dealer: args.input.dealer,
            chosen: c.discardId == chosen,
            onTap: () => _openCandidate(c, pro),
          ),
        if (!pro && ordered.length > visible.length)
          Card(
            key: const ValueKey('result-more-locked'),
            color: AppColors.goldTint.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.lgAll,
              side: BorderSide(color: AppColors.gold.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xxs),
              child: ProLock(
                label: s.moreLocked(ordered.length - visible.length),
              ),
            ),
          ),
      ]);
    }

    children.addAll([
      const SizedBox(height: AppSpacing.lg),
      Text(s.disclaimer, style: theme.textTheme.bodySmall),
      const SizedBox(height: AppSpacing.lg),
    ]);

    return ListView(
      key: const ValueKey('result-list'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.sm,
      ),
      children: children,
    );
  }
}

/// 3 軸の答えの関係（仕様 4.1: 同じなら「一択」、違えば軸ごとの答え）。
class _AgreementBanner extends StatelessWidget {
  const _AgreementBanner({
    required this.report,
    required this.showAnswers,
    required this.online,
  });

  final AnalysisReport report;

  /// オンライン機能があるか（なければ「出題すると…」の誘いを付けない）。
  final bool online;

  /// 軸ごとの答えの一覧も出す（クイズの比較カードが無いとき）。
  final bool showAnswers;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (agreementOf(report)) {
      case AnswerAgreement.none:
        return const SizedBox.shrink();
      case AnswerAgreement.single:
        return Container(
          key: const ValueKey('result-one-choice'),
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.6),
            borderRadius: AppRadius.mdAll,
          ),
          child: Row(
            children: [
              Text(
                s.oneChoice,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppColors.jadeDeep,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(s.oneChoiceBody, style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
        );
      case AnswerAgreement.sameTie:
        return Text(
          s.sameTie(bestOf(report, StrategyAxis.balance).length),
          key: const ValueKey('result-same-tie'),
          style: theme.textTheme.titleSmall,
        );
      case AnswerAgreement.split:
        final speed = bestOf(report, StrategyAxis.speed).toSet();
        final points = bestOf(report, StrategyAxis.points).toSet();
        final speedVsPoints =
            !(speed.length == points.length && speed.containsAll(points));
        return Container(
          key: const ValueKey('result-split'),
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.md + AppSpacing.xxs),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: AppRadius.lgAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.alt_route_rounded,
                    size: 20,
                    color: AppColors.caution,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      s.splitTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                s.splitBody(speedVsPoints: speedVsPoints, online: online),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (showAnswers) ...[
                const SizedBox(height: AppSpacing.sm),
                for (final axis in kAxisOrder)
                  _AxisAnswerRow(report: report, axis: axis),
              ],
            ],
          ),
        );
    }
  }
}

/// 「最速: [1萬]」の 1 行。[chosenId] があれば一致した軸に印を付ける。
class _AxisAnswerRow extends StatelessWidget {
  const _AxisAnswerRow({
    required this.report,
    required this.axis,
    this.chosenId,
  });

  final AnalysisReport report;
  final StrategyAxis axis;
  final int? chosenId;

  @override
  Widget build(BuildContext context) {
    final text = ReasonText(context.lang);
    final ids = bestOf(report, axis);
    final match = chosenId != null && ids.contains(chosenId);
    return Padding(
      key: ValueKey('answer-${axis.name}'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Align(
              alignment: Alignment.centerLeft,
              child: AxisBadge(axis: axis),
            ),
          ),
          for (final id in ids)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: TileImage(tileLabelOfId(id), width: 22),
            ),
          const SizedBox(width: 6),
          Expanded(child: Text(text.tiles(ids))),
          if (chosenId != null)
            Icon(
              match ? Icons.check_circle : Icons.remove_circle_outline,
              size: 18,
              color: match
                  ? AppColors.success
                  : Theme.of(context).colorScheme.outline,
            ),
        ],
      ),
    );
  }
}

/// クイズの答えと 3 軸の解の比較（仕様 3.4: 選んだ軸で判定し、別の軸の解なら
/// 「打点重視なら正解」）。
class _VerdictCard extends StatelessWidget {
  const _VerdictCard({
    required this.report,
    required this.chosenId,
    required this.axis,
  });

  final AnalysisReport report;
  final int chosenId;
  final StrategyAxis axis;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final verdict = judgeChoice(report, chosenId, axis);
    final label = tileLabelOfId(chosenId);
    final Color color;
    final String headline;
    final IconData icon;
    if (verdict.correct) {
      color = AppColors.success;
      icon = Icons.check_circle_rounded;
      headline = '${s.correct}（${s.axis(axis)}）';
    } else if (verdict.otherCorrectAxes.isNotEmpty) {
      color = AppColors.caution;
      icon = Icons.change_circle_rounded;
      headline = verdict.otherCorrectAxes.map(s.correctFor).join(' / ');
    } else {
      color = AppColors.danger;
      icon = Icons.cancel_rounded;
      final rank = verdict.rank;
      headline =
          '${s.incorrect}${rank == null ? '' : '（${s.rankOn(axis, rank)}）'}';
    }
    final theme = Theme.of(context);
    return Card(
      key: const ValueKey('result-verdict'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      color: Color.alphaBlend(
        color.withValues(alpha: 0.06),
        theme.colorScheme.surfaceContainerLowest,
      ),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: color.withValues(alpha: 0.7), width: 1.6),
        borderRadius: AppRadius.lgAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 28),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    headline,
                    key: const ValueKey('result-verdict-headline'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(s.yourChoice, style: theme.textTheme.bodySmall),
                const SizedBox(width: AppSpacing.sm),
                TileImage(
                  label,
                  width: 24,
                  semanticLabel: common.tileName(label),
                ),
                const SizedBox(width: AppSpacing.xs + 2),
                Text(common.tileName(label), style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final a in kAxisOrder)
              _AxisAnswerRow(report: report, axis: a, chosenId: chosenId),
          ],
        ),
      ),
    );
  }
}

/// 公開問題の「みんなの回答」の分布（サーバーの集計。多い順に最大 5 件）。
class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.outcome,
    required this.chosenId,
    required this.answerIds,
  });

  final ProblemAnswerOutcome outcome;
  final int? chosenId;

  /// バランス軸の 1 位（正解として印を付ける）。
  final List<int> answerIds;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final scheme = Theme.of(context).colorScheme;
    final stats = outcome.stats;
    final rows = stats.byTile.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : compareTileLabels(a.key, b.key);
      });
    return Card(
      key: const ValueKey('result-community'),
      margin: const EdgeInsets.only(top: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.communityTitle(stats.total),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (stats.correctPercent != null)
              Text(
                s.communityRate(stats.correctPercent!, stats.total),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            for (final e in rows.take(5))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    TileImage(e.key, width: 20),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 52,
                      child: Text(
                        common.tileName(e.key),
                        style: TextStyle(
                          fontWeight: tileIdFromLabel(e.key) == chosenId
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: e.value / stats.total,
                        minHeight: 8,
                        borderRadius: AppRadius.pillAll,
                        color: answerIds.contains(tileIdFromLabel(e.key))
                            ? AppColors.success
                            : scheme.primary.withValues(alpha: 0.45),
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${(e.value * 100 / stats.total).round()}%',
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 結論（いま選んでいる軸のおすすめの打牌）。画面でいちばん大きく見せる。
///
/// 切る牌（同点なら複数）・理由の 1 行・シャンテン数と受け入れ枚数（キー `result-summary`）・
/// 軸の切り替え。
class _ConclusionCard extends StatelessWidget {
  const _ConclusionCard({
    required this.report,
    required this.axis,
    required this.top,
    required this.summary,
    required this.selector,
  });

  final AnalysisReport report;
  final StrategyAxis axis;
  final DiscardCandidate top;
  final String summary;
  final Widget selector;

  @override
  Widget build(BuildContext context) {
    final s = context.resultStrings;
    final common = context.commonStrings;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final best = bestOf(report, axis);
    final ids = best.isEmpty ? [top.discardId] : best;
    final reason = ReasonText(context.lang).oneLine(top, report.candidates);
    final names = ids.map((id) => common.tileName(tileLabelOfId(id)));
    return Container(
      key: const ValueKey('result-conclusion'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg + AppSpacing.xxs,
        AppSpacing.lg,
        AppSpacing.lg + AppSpacing.xxs,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.jadeDeep.withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.conclusionTitle(axis),
            style: theme.textTheme.labelLarge?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              for (final id in ids.take(3))
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.tileFace,
                      borderRadius: AppRadius.smAll,
                      border: Border.all(color: AppColors.vermilion, width: 2),
                    ),
                    child: TileImage(
                      tileLabelOfId(id),
                      width: ids.length > 1 ? 36 : 44,
                      semanticLabel: common.tileName(tileLabelOfId(id)),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.discard,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.vermilion,
                      ),
                    ),
                    Text(
                      names.join('・'),
                      style: theme.textTheme.headlineMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(reason, style: theme.textTheme.bodyLarge),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            summary,
            key: const ValueKey('result-summary'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          selector,
          const SizedBox(height: AppSpacing.sm),
          Text(s.axisHint(axis), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 下部のボタンの文字。幅が足りないとき（英語・大きな文字）は省略せずに縮める。
class _FitLabel extends StatelessWidget {
  const _FitLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1));
}
