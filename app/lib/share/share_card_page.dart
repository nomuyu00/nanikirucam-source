import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/core/streak.dart';
import 'package:nanikiru_cam/l10n/strings/share_strings.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/share_card_model.dart';
import 'package:nanikiru_cam/share/share_service.dart';

/// 共有カードの画面（仕様 6.10・設計書 8 章）。カード 5 種（問題・結果・ライブ・ストリーク・
/// 週間）を 1:1 とストーリー（9:16）で見せ、幅 1080px の PNG にして共有シートへ渡す。
///
/// 問題カードで [ShareCardArgs.problemId] がなければ、公開画面（[Routes.publish]）へ進む。
/// 戻り値は「1 回以上共有したか」。
class ShareCardPage extends ConsumerStatefulWidget {
  const ShareCardPage({super.key});

  @override
  ConsumerState<ShareCardPage> createState() => _ShareCardPageState();
}

class _ShareCardPageState extends ConsumerState<ShareCardPage> {
  final GlobalKey _cardKey = GlobalKey();
  ShareCardArgs? _args;
  Future<ShareCardModel?>? _model;
  ShareCardFormat _format = ShareCardFormat.square;
  bool _busy = false;
  bool _shared = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_args != null || _model != null) return;
    final args = context.routeArgs<ShareCardArgs>();
    _args = args;
    if (args == null) {
      _model = Future.value();
      return;
    }
    final input = args.input;
    if (args.kind == ShareCardKind.problem &&
        args.problemId == null &&
        input != null) {
      // 未公開の問題は、公開画面で出題者名を決めて公開してから共有する。
      _model = Completer<ShareCardModel?>().future;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          Routes.publish,
          arguments: PublishArgs(input: input),
        );
      });
      return;
    }
    _model = _resolve(args);
  }

  /// プロフィール（出題者名）を少しだけ待つ。届かなければ名前なしで作る。
  Future<UserProfile?> _profile() async {
    try {
      return await ref
          .read(userProfileProvider.future)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return ref.read(userProfileProvider).valueOrNull;
    }
  }

  Future<ShareCardModel?> _resolve(ShareCardArgs args) async {
    final profile = await _profile();
    final repository = ref.read(problemRepositoryProvider);
    return resolveShareCardModel(
      args,
      ShareCardSources(
        analyze: (input) =>
            ref.read(analysisServiceProvider).analyze(input, deep: false),
        fetchStats: (id) async {
          if (!repository.available) return null;
          try {
            return (await repository.fetchProblem(id))?.stats;
          } on BackendException {
            return null;
          }
        },
        streak: ref.read(streakProvider),
        nickname: profile?.nickname ?? '',
      ),
    );
  }

  Map<String, Object> _params(ShareCardModel model, {String? target}) => {
    'share_format': _format.analyticsValue,
    'share_variant': model.analyticsVariant,
    'share_target': ?target,
  };

  String _qrUrl(ShareCardModel model) => qrUrlFor(
    model,
    referralCode: ref.read(userProfileProvider).valueOrNull?.referralCode,
  );

  Future<void> _share(BuildContext anchor, ShareCardModel model) async {
    final strings = context.shareStrings;
    final analytics = ref.read(appAnalyticsProvider);
    final service = ref.read(shareServiceProvider);
    final origin = ShareService.originFrom(anchor);
    unawaited(
      analytics.logEvent(
        AnalyticsEvent.shareTapped,
        parameters: _params(model),
      ),
    );
    setState(() => _busy = true);
    try {
      final png = await service.capture(
        _cardKey,
        pixelRatio: _format.pixelRatio,
      );
      final file = await service.writeTemp(png);
      final outcome = await service.shareFiles(
        [file],
        text: shareTextFor(model, strings, url: _qrUrl(model)),
        subject: strings.appName,
        origin: origin,
      );
      if (outcome.completed) {
        _shared = true;
        unawaited(
          analytics.logEvent(
            AnalyticsEvent.resultShared,
            parameters: _params(model, target: outcome.target),
          ),
        );
        // 共有直後はレビュー依頼・広告を出さない（広告側の間隔制御に伝えるだけ）。
        ref.read(interstitialControllerProvider).onShared();
      }
    } catch (_) {
      if (mounted) _snack(strings.shareFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(ShareCardModel model) async {
    final strings = context.shareStrings;
    final service = ref.read(shareServiceProvider);
    setState(() => _busy = true);
    try {
      final png = await service.capture(
        _cardKey,
        pixelRatio: _format.pixelRatio,
      );
      final saved = await service.saveToPhotos(png, album: strings.appName);
      if (saved) {
        unawaited(
          ref
              .read(appAnalyticsProvider)
              .logEvent(
                AnalyticsEvent.shareCardSaved,
                parameters: _params(model),
              ),
        );
      }
      if (mounted) _snack(saved ? strings.savedToPhotos : strings.saveDenied);
    } catch (_) {
      if (mounted) _snack(strings.saveFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.shareStrings;
    final pro = ref.watch(entitlementsProvider.select((e) => e.pro));
    // 紹介コードが届いたら QR を作り直す。
    ref.watch(userProfileProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_shared);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(strings.cardTitle)),
        body: SafeArea(
          child: FutureBuilder<ShareCardModel?>(
            future: _model,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(strings.preparing),
                    ],
                  ),
                );
              }
              final model = snapshot.data;
              if (snapshot.hasError || model == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      strings.cardUnavailable,
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return _content(context, model, watermark: !pro);
            },
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ShareCardModel model, {
    required bool watermark,
  }) {
    final strings = context.shareStrings;
    final card = RepaintBoundary(
      key: _cardKey,
      child: buildShareCard(
        model,
        format: _format,
        strings: strings,
        qrUrl: _qrUrl(model),
        watermark: watermark,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > constraints.maxHeight;
        final preview = Padding(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: FittedBox(
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                clipBehavior: Clip.antiAlias,
                child: card,
              ),
            ),
          ),
        );
        final controls = _controls(context, model);
        if (wide) {
          return Row(
            children: [
              Expanded(flex: 5, child: preview),
              Expanded(flex: 6, child: controls),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: preview),
            SizedBox(height: constraints.maxHeight * 0.4, child: controls),
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, ShareCardModel model) {
    final strings = context.shareStrings;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Text(
          strings.sizeLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SegmentedButton<ShareCardFormat>(
          key: const ValueKey('share-card-format'),
          segments: [
            ButtonSegment(
              value: ShareCardFormat.square,
              label: Text(strings.formatSquare),
            ),
            ButtonSegment(
              value: ShareCardFormat.story,
              label: Text(strings.formatStory),
            ),
          ],
          selected: {_format},
          onSelectionChanged: _busy
              ? null
              : (value) => setState(() => _format = value.first),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (anchor) => FilledButton.icon(
            key: const ValueKey('share-card-share'),
            onPressed: _busy ? null : () => _share(anchor, model),
            icon: const Icon(Icons.ios_share),
            label: Text(strings.shareButton),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('share-card-save'),
          onPressed: _busy ? null : () => _save(model),
          icon: const Icon(Icons.download_outlined),
          label: Text(strings.saveButton),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          strings.cardPrivacyNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
