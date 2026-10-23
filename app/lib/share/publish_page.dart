import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/cards/problem_card.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:nanikiru_cam/share/share_links.dart';
import 'package:nanikiru_cam/share/share_service.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/notice_card.dart';

/// 問題の公開（仕様 6.10・設計書 8 章）。
///
/// 出題者名を入れて「公開して共有」→ 正解をアプリのエンジンで計算 → `publishProblem` →
/// 問題 ID の QR を差し込んだカードを描く → カード PNG を Storage に置く → 共有シート。
/// オフラインなど一時的に公開できないときは、QR をストアの URL にしてカードだけ共有し、
/// 公開はキューに入れて通信が戻ってから自動で行う。
class PublishPage extends ConsumerStatefulWidget {
  const PublishPage({super.key});

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

enum _Phase { idle, analyzing, publishing, card, sharing }

class _PublishPageState extends ConsumerState<PublishPage> {
  /// 共有する形式のカード（プレビューと同じもの）。
  final GlobalKey _shareKey = GlobalKey();

  /// Storage に置く 1:1 のカード（画面の外に描く）。
  final GlobalKey _uploadKey = GlobalKey();
  final TextEditingController _nickname = TextEditingController();

  PublishArgs? _args;
  HandInput? _input;
  ShareCardFormat _format = ShareCardFormat.square;

  /// 「問題として公開する」のスイッチ。オンライン機能が無いとき（[_online] が false）は
  /// スイッチ自体を出さず、公開は行わない（[_publishing]）。
  bool _public = true;
  _Phase _phase = _Phase.idle;
  String? _qrOverride;
  String? _error;
  String? _note;
  bool _shared = false;
  bool _nicknameEdited = false;

  @override
  void initState() {
    super.initState();
    _nickname.addListener(() {
      if (_nickname.text != _prefill) _nicknameEdited = true;
    });
  }

  String _prefill = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null) return;
    _args = context.routeArgs<PublishArgs>();
    _input = _args?.input.normalized();
    _fillNickname(ref.read(userProfileProvider).valueOrNull?.nickname);
  }

  void _fillNickname(String? nickname) {
    if (_nicknameEdited || nickname == null || nickname.isEmpty) return;
    _prefill = nickname;
    _nickname.text = nickname;
  }

  @override
  void dispose() {
    _nickname.dispose();
    super.dispose();
  }

  bool get _busy => _phase != _Phase.idle;

  /// サーバーに問題を公開できるか（Firebase バックエンド有効）。
  bool get _online => ref.read(publishServiceProvider).available;

  /// 今回の実行で公開まで行うか。オンライン機能が無ければ、カード画像の共有だけ。
  bool get _publishing => _online && _public;

  String get _storeUrl => ShareLinks.storeUrl(
    campaign: 'problem',
    referralCode: ref.read(userProfileProvider).valueOrNull?.referralCode,
  );

  String get _cardQrUrl => _qrOverride ?? _storeUrl;

  Map<String, Object> _params({String? target}) => {
    'share_format': _format.analyticsValue,
    'share_variant': 'quiz',
    'share_target': ?target,
  };

  Widget _card(ShareCardFormat format, {required bool watermark}) {
    final strings = context.shareStrings;
    return ProblemCard(
      input: _input!,
      authorName: _nickname.text.trim(),
      qrUrl: _cardQrUrl,
      format: format,
      strings: strings,
      watermark: watermark,
    );
  }

  Future<void> _run(BuildContext anchor) async {
    final strings = context.shareStrings;
    final input = _input;
    if (input == null || _busy) return;
    if (!input.isFourteen) {
      setState(() => _error = strings.needFourteen);
      return;
    }
    if (!input.isAnalyzable) {
      setState(() => _error = strings.cannotAnalyze);
      return;
    }
    final analytics = ref.read(appAnalyticsProvider);
    final shareService = ref.read(shareServiceProvider);
    final publishService = ref.read(publishServiceProvider);
    final origin = ShareService.originFrom(anchor);
    final language = context.lang == AppLang.en ? 'en' : 'ja';
    final referralCode = ref
        .read(userProfileProvider)
        .valueOrNull
        ?.referralCode;
    unawaited(
      analytics.logEvent(AnalyticsEvent.shareTapped, parameters: _params()),
    );
    setState(() {
      _error = null;
      _note = null;
      _qrOverride = null;
      _phase = _Phase.analyzing;
    });
    try {
      PublishAttempt attempt = const PublishDeferred(queueable: false);
      PublishRequest? request;
      if (_publishing) {
        final report = await ref
            .read(analysisServiceProvider)
            .analyze(input, deep: false);
        request = PublishRequest(
          input: input,
          answer: PublishedAnswer.fromReport(report, input),
          nickname: _nickname.text,
          locale: language,
        );
        if (!mounted) return;
        setState(() => _phase = _Phase.publishing);
        attempt = await publishService.publish(request);
      }
      if (!mounted) return;
      final rejected = attempt;
      if (rejected is PublishRejected) {
        setState(() {
          _phase = _Phase.idle;
          _error = strings.publishError(
            code: rejected.error.code,
            reason: rejected.error.reason,
          );
        });
        return;
      }
      final published = attempt is PublishSucceeded ? attempt.result : null;
      setState(() {
        _qrOverride = published?.qrUrl(referralCode: referralCode);
        _phase = _Phase.card;
      });

      // QR を差し込んだカードを描き直してから書き出す。
      final sharePng = await shareService.captureWithinLimit(
        _shareKey,
        pixelRatio: _format.pixelRatio,
      );
      Future<bool>? upload;
      if (published != null && published.cardUploadPath != null) {
        final cardPng = await shareService.captureWithinLimit(
          _uploadKey,
          pixelRatio: ShareCardFormat.square.pixelRatio,
        );
        upload = publishService.uploadCard(published, cardPng);
      } else if (attempt is PublishDeferred &&
          attempt.queueable &&
          request != null) {
        // 公開待ちに入れる。公開できたらこのカード（QR はストア）を問題の画像にする。
        final cardPng = await shareService.captureWithinLimit(
          _uploadKey,
          pixelRatio: ShareCardFormat.square.pixelRatio,
        );
        await publishService.enqueue(request, card: cardPng);
      }

      if (!mounted) return;
      setState(() => _phase = _Phase.sharing);
      final file = await shareService.writeTemp(sharePng);
      final url = published?.qrUrl(referralCode: referralCode) ?? _storeUrl;
      final outcome = await shareService.shareFiles(
        [file],
        text: strings.problemShareText(url),
        subject: strings.appName,
        origin: origin,
      );
      if (upload != null) {
        try {
          await upload;
        } catch (_) {}
      }
      if (outcome.completed) {
        _shared = true;
        unawaited(
          analytics.logEvent(
            AnalyticsEvent.resultShared,
            parameters: _params(target: outcome.target),
          ),
        );
        // 共有直後はレビュー依頼・広告を出さない（広告側の間隔制御に伝えるだけ）。
        ref.read(interstitialControllerProvider).onShared();
      }
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _note = switch (attempt) {
          PublishSucceeded() => strings.publishedNote,
          PublishDeferred(queueable: true) => strings.queuedNote,
          _ => _publishing ? strings.unavailableNote : null,
        };
      });
      ref.invalidate(pendingPublishCountProvider);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.idle;
        _error = strings.shareFailed;
      });
    }
  }

  String _phaseLabel(ShareStrings strings) => switch (_phase) {
    _Phase.analyzing => strings.phaseAnalyzing,
    _Phase.publishing => strings.phasePublishing,
    _Phase.card => strings.phaseCard,
    _Phase.sharing => strings.phaseSharing,
    _Phase.idle => '',
  };

  @override
  Widget build(BuildContext context) {
    final strings = context.shareStrings;
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    ref.listen(userProfileProvider, (_, next) {
      _fillNickname(next.valueOrNull?.nickname);
      setState(() {});
    });
    final input = _input;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_shared);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _online ? strings.publishTitle : strings.shareProblemCardTitle,
          ),
        ),
        body: SafeArea(
          child: input == null
              ? Center(child: Text(strings.cardUnavailable))
              : ListView(
                  padding: AppSpacing.page,
                  children: [
                    _preview(pro),
                    const SizedBox(height: AppSpacing.lg),
                    SegmentedButton<ShareCardFormat>(
                      key: const ValueKey('publish-format'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: ShareCardFormat.square,
                          icon: const Icon(Icons.crop_square_rounded),
                          label: Text(strings.formatSquare),
                        ),
                        ButtonSegment(
                          value: ShareCardFormat.story,
                          icon: const Icon(Icons.crop_portrait_rounded),
                          label: Text(strings.formatStory),
                        ),
                      ],
                      selected: {_format},
                      onSelectionChanged: _busy
                          ? null
                          : (value) => setState(() => _format = value.first),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    TextField(
                      key: const ValueKey('publish-nickname'),
                      controller: _nickname,
                      enabled: !_busy,
                      maxLength: 20,
                      decoration: InputDecoration(
                        labelText: strings.nicknameLabel,
                        hintText: strings.nicknameHint,
                        prefixIcon: const Icon(Icons.person_outline_rounded),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    // オンライン機能が無い版では、公開のスイッチと説明を出さない。
                    if (_online) ...[
                      const SizedBox(height: AppSpacing.xs),
                      GroupedSection(
                        children: [
                          SwitchListTile(
                            key: const ValueKey('publish-public'),
                            secondary: const Icon(Icons.public_rounded),
                            title: Text(strings.publicToggle),
                            subtitle: Text(strings.publicToggleHelp),
                            value: _public,
                            onChanged: _busy
                                ? null
                                : (value) => setState(() => _public = value),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Builder(
                      builder: (anchor) => FilledButton.icon(
                        key: const ValueKey('publish-submit'),
                        onPressed: _busy ? null : () => _run(anchor),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.ios_share),
                        label: Text(
                          _busy
                              ? _phaseLabel(strings)
                              : !_online
                              ? strings.shareButton
                              : _publishing
                              ? strings.publishAndShareButton
                              : strings.shareOnlyButton,
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                          shape: const RoundedRectangleBorder(
                            borderRadius: AppRadius.lgAll,
                          ),
                          textStyle: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      NoticeCard(
                        tone: NoticeTone.danger,
                        icon: Icons.error_outline_rounded,
                        message: _error!,
                        messageKey: const ValueKey('publish-error'),
                      ),
                    ],
                    if (_note != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      NoticeCard(
                        tone: NoticeTone.success,
                        icon: Icons.check_circle_outline_rounded,
                        message: _note!,
                        messageKey: const ValueKey('publish-note'),
                      ),
                    ],
                    if (_online && (_shared || _note != null))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('publish-view-mine'),
                          onPressed: () => Navigator.of(
                            context,
                          ).pushNamed(Routes.myProblems),
                          icon: const Icon(Icons.chevron_right_rounded),
                          label: Text(strings.viewMyProblems),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            strings.cardPrivacyNote,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _preview(bool pro) {
    final preview = FittedBox(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.mdAll,
          boxShadow: [
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: AppRadius.mdAll,
          child: RepaintBoundary(
            key: _shareKey,
            child: _card(_format, watermark: !pro),
          ),
        ),
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: AppRadius.xlAll,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 380),
            child: Center(child: preview),
          ),
        ),
        // Storage に置く 1:1 のカード。画面の外で描いて書き出す。
        Positioned(
          left: -4000,
          top: 0,
          width: ShareCardFormat.square.logicalSize.width,
          height: ShareCardFormat.square.logicalSize.height,
          child: RepaintBoundary(
            key: _uploadKey,
            child: _card(ShareCardFormat.square, watermark: !pro),
          ),
        ),
      ],
    );
  }
}
