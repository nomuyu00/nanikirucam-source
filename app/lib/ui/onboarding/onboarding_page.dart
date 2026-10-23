import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/analytics_widgets.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/online_features.dart';
import 'package:nanikiru_cam/l10n/strings/onboarding_strings.dart';
import 'package:nanikiru_cam/referral/referral_section.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_gate.dart';
import 'package:nanikiru_cam/ui/theme/app_colors.dart';
import 'package:nanikiru_cam/ui/theme/app_spacing.dart';
import 'package:nanikiru_cam/ui/widgets/app_card.dart';
import 'package:nanikiru_cam/ui/widgets/primary_button.dart';
import 'package:nanikiru_cam/ui/widgets/tile_fan.dart';
import 'package:nanikiru_cam/ui/widgets/tile_image.dart';

/// Onboarding（仕様 6.1）。初回起動では `HomeGate` が出し、Settings などから開き直すこともある。
///
/// 3 枚（「かざす」「自分で切る」「友達に出す」）のあと、マナーの注意と分析の同意（任意）。
/// 紹介リンクから来ていれば招待コードを入れた入力欄（Pro 7 日の案内）を出す。
/// 「はじめる」で `OnboardingGate.markCompleted` し、`onboarding_completed` を送る。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  static const int _pageCount = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    unawaited(
      ref
          .read(appAnalyticsProvider)
          .logEvent(AnalyticsEvent.onboardingCompleted),
    );
    await OnboardingGate.markCompleted(ref);
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.onboardingStrings;
    final last = _page == _pageCount - 1;
    final online = ref.watch(onlineFeaturesProvider);
    return Scaffold(
      key: const ValueKey('onboarding-page'),
      appBar: AppBar(
        title: Text(strings.title),
        automaticallyImplyLeading: false,
        actions: [
          if (!last)
            TextButton(
              key: const ValueKey('onboarding-skip'),
              onPressed: () => _goTo(_pageCount - 1),
              child: Text(strings.skip),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (page) => setState(() => _page = page),
                children: [
                  _Slide(
                    art: const _LiveArt(),
                    title: strings.slide1Title,
                    body: strings.slide1Body,
                  ),
                  _Slide(
                    art: const _ChooseArt(),
                    title: strings.slide2Title,
                    body: strings.slide2Body,
                  ),
                  _Slide(
                    art: const _ShareArt(),
                    // オンライン機能が無い版は、Web 回答に触れない端末内の説明にする。
                    title: online
                        ? strings.slide3Title
                        : strings.slide3TitleOffline,
                    body: online
                        ? strings.slide3Body
                        : strings.slide3BodyOffline,
                  ),
                  const _MannersPage(),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.pillAll,
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.sm,
                AppSpacing.gutter,
                AppSpacing.lg,
              ),
              child: last
                  ? PrimaryButton(
                      key: const ValueKey('onboarding-start'),
                      label: strings.start,
                      onPressed: _finishing ? null : _finish,
                    )
                  : PrimaryButton(
                      key: const ValueKey('onboarding-next'),
                      label: strings.next,
                      tonal: true,
                      onPressed: () => _goTo(_page + 1),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.art, required this.title, required this.body});

  final Widget art;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        children: [
          art,
          const SizedBox(height: AppSpacing.xl + AppSpacing.sm),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 挿絵の台（淡いジェイドの面）。
class _ArtStage extends StatelessWidget {
  const _ArtStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 248,
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: const BorderRadius.all(Radius.circular(110)),
        ),
        child: child,
      ),
    );
  }
}

/// 1 枚目「かざす」: スマホの画面に牌が並び、切る牌に朱の矢印。
class _LiveArt extends StatelessWidget {
  const _LiveArt();

  @override
  Widget build(BuildContext context) {
    const labels = ['3m', '4m', '6p', '7z', '5s'];
    return _ArtStage(
      child: Container(
        width: 200,
        height: 128,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.jade, AppColors.jadeDeep],
          ),
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.ink, width: 4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            const Icon(
              Icons.arrow_downward_rounded,
              color: AppColors.liveRecommend,
              size: 26,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < labels.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AppColors.tileFace,
                      borderRadius: const BorderRadius.all(Radius.circular(5)),
                      border: Border.all(
                        color: i == 3
                            ? AppColors.vermilion
                            : AppColors.ivoryDeep,
                        width: i == 3 ? 2 : 1,
                      ),
                    ),
                    child: TileImage(labels[i], width: 22),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 2 枚目「自分で切る」: 扇の牌から 1 枚を選ぶ。
class _ChooseArt extends StatelessWidget {
  const _ChooseArt();

  @override
  Widget build(BuildContext context) {
    return const _ArtStage(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          TileFan(
            labels: ['2p', '3p', '9s', '1z', '6m'],
            tileWidth: 36,
            highlight: 2,
          ),
          Positioned(
            right: 30,
            bottom: 6,
            child: Icon(
              Icons.touch_app_rounded,
              size: 44,
              color: AppColors.jadeDeep,
            ),
          ),
        ],
      ),
    );
  }
}

/// 3 枚目「友達に出す」: 問題カード（ジェイドと金）と共有の印。
class _ShareArt extends StatelessWidget {
  const _ShareArt();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _ArtStage(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 170,
            height: 120,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: AppColors.cardGold, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppColors.cardGold,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    for (final label in const [
                      '1m',
                      '2m',
                      '3m',
                      '5p',
                      '5p',
                      '8s',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: TileImage(label, width: 20),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: -14,
            top: -14,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.vermilion,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.ios_share_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// マナーの注意と分析の同意（任意）。紹介リンクから来ていれば招待コードの入力欄。
class _MannersPage extends ConsumerWidget {
  const _MannersPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.onboardingStrings;
    final theme = Theme.of(context);
    // 招待コードはオンライン機能。サーバーなしの版では受け取っても出さない。
    final code = ref.watch(onlineFeaturesProvider)
        ? ref.watch(pendingReferralCodeProvider)
        : null;
    Widget point(IconData icon, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 20, color: AppColors.jadeDeep),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(text, style: theme.textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
    return SingleChildScrollView(
      key: const ValueKey('onboarding-manners'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.lg,
        AppSpacing.gutter,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.mannersTitle, style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Column(
              children: [
                point(Icons.groups_outlined, strings.mannersFriendly),
                point(Icons.lightbulb_outline, strings.mannersCandidate),
                point(Icons.lock_outline, strings.mannersPrivacy),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AnalyticsConsentCard(),
          if (code != null) ...[
            const SizedBox(height: 16),
            Text(strings.referralReceived(code)),
            const ReferralSection(),
          ],
        ],
      ),
    );
  }
}
