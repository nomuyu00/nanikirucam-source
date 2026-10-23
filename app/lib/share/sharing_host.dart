import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/problems/blocked_authors.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// アプリの外側に 1 つだけ置く、共有と成長の常駐処理（`MaterialApp.builder` から使う）。
///
/// - 匿名サインイン → `ensureUser` → `users/{uid}` の購読を起動直後に始める
/// - ディープリンク `/p/{id}`（問題を開く）と `/r/{code}`（紹介コードを保留）を受ける
/// - Android の Install Referrer（`pid` `ref`）を初回起動で 1 回だけ読む
/// - アプリ起動時・復帰時に、公開待ちの問題を再送し、サインインに失敗していればやり直す
class SharingHost extends ConsumerStatefulWidget {
  const SharingHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SharingHost> createState() => _SharingHostState();
}

class _SharingHostState extends ConsumerState<SharingHost>
    with WidgetsBindingObserver {
  static const _installReferrerKey = 'install_referrer_consumed_v1';

  DeepLinkRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
    final router = DeepLinkRouter(
      source: ref.read(deepLinkSourceProvider),
      onProblem: _openProblem,
      onReferral: (code) =>
          ref.read(pendingReferralCodeProvider.notifier).set(code),
    );
    _router = router..start();
    unawaited(_consumeInstallReferrer(router));
    unawaited(_flushQueue());
  }

  Future<void> _consumeInstallReferrer(DeepLinkRouter router) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_installReferrerKey) ?? false) return;
      final referrer = await ref
          .read(installReferrerSourceProvider)
          .readReferrer();
      await prefs.setBool(_installReferrerKey, true);
      if (referrer != null && referrer.isNotEmpty && mounted) {
        await router.handleInstallReferrer(referrer);
      }
    } catch (_) {
      // 読めなくても通常どおり起動する。
    }
  }

  Future<void> _flushQueue() async {
    try {
      final service = ref.read(publishServiceProvider);
      if (service.available) {
        await service.flush();
        if (mounted) ref.invalidate(pendingPublishCountProvider);
      }
    } catch (_) {}
  }

  /// 最初のフレームの前にリンクが届いても、ナビゲータができるまで待つ。
  Future<NavigatorState?> _navigator() async {
    for (var i = 0; i < 180; i++) {
      final navigator = appNavigatorKey.currentState;
      if (navigator != null) return navigator;
      await WidgetsBinding.instance.endOfFrame;
    }
    return null;
  }

  Future<void> _openProblem(ProblemDeepLink link) async {
    final navigator = await _navigator();
    if (navigator == null || !mounted) return;
    // ブロック中の出題者の問題は開かない。保存内容を読み終えてから判定する。
    final blocks = ref.read(blockedAuthorsProvider.notifier);
    await blocks.ensureLoaded();
    if (!mounted) return;
    final result = await openProblemById(
      navigator: navigator,
      repository: ref.read(problemRepositoryProvider),
      problemId: link.problemId,
      analytics: ref.read(appAnalyticsProvider),
      source: 'deeplink',
      isBlocked: ref.read(blockedAuthorsProvider).isBlocked,
      onBlocked: (problem) {
        if (!navigator.mounted) return;
        showBlockedProblemNotice(
          navigator.context,
          problem: problem,
          blocks: blocks,
          navigator: navigator,
        );
      },
    );
    if (result != OpenProblemResult.opened && navigator.mounted) {
      showOpenProblemFailure(navigator.context, result);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // オフラインで起動してサインインできなかった場合は、復帰したときにやり直す。
    if (ref.read(accountServiceProvider).available &&
        ref.read(authUidProvider).valueOrNull == null) {
      ref.invalidate(authUidProvider);
    }
    unawaited(_flushQueue());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // プロフィールの購読を起動直後から始めて、アプリが動いている間は保つ。
    ref.listen(userProfileProvider, (_, _) {});
    return widget.child;
  }
}
