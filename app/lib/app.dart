// 流用元: reference/agari_cam/lib/app.dart（2026-10-21 時点）
// 改修: 名前付きルートで仕様 6.0 の全画面を登録（ルート名は core/routes.dart）。
// 言語は端末に従う（設定で変更可）。
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/analytics_route_observer.dart';
import 'package:nanikiru_cam/camera/camera_page.dart';
import 'package:nanikiru_cam/core/app_bootstrap.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/deep_links.dart';
import 'package:nanikiru_cam/core/route_observer.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/history_page.dart';
import 'package:nanikiru_cam/l10n/strings/common_strings.dart';
import 'package:nanikiru_cam/live/live_page.dart';
import 'package:nanikiru_cam/live/live_summary_page.dart';
import 'package:nanikiru_cam/problems/my_problems_page.dart';
import 'package:nanikiru_cam/problems/today_page.dart';
import 'package:nanikiru_cam/purchase/paywall_page.dart';
import 'package:nanikiru_cam/quiz/quiz_page.dart';
import 'package:nanikiru_cam/result/candidate_detail_page.dart';
import 'package:nanikiru_cam/result/explanation_page.dart';
import 'package:nanikiru_cam/result/result_page.dart';
import 'package:nanikiru_cam/share/publish_page.dart';
import 'package:nanikiru_cam/share/share_card_page.dart';
import 'package:nanikiru_cam/share/sharing_host.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_gate.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_page.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_loading_page.dart';
import 'package:nanikiru_cam/ui/recognition/recognition_page.dart';
import 'package:nanikiru_cam/ui/settings/settings_page.dart';
import 'package:nanikiru_cam/ui/theme/app_theme.dart';
import 'package:nanikiru_cam/win/win_score_page.dart';

class NanikiruCamApp extends ConsumerWidget {
  const NanikiruCamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    // 課金・通知・Remote Config・紹介コードの自動適用を起動する（課金・設定担当）。
    ref.watch(appBootstrapProvider);
    return MaterialApp(
      onGenerateTitle: (context) => context.commonStrings.appName,
      debugShowCheckedModeBanner: false,
      // ブランドのテーマ（ライト固定。色・文字・角丸・余白は ui/theme/）。
      theme: AppTheme.light(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: supportedAppLocales,
      locale: locale,
      // ディープリンク（/p/{id}, /r/{code}）・匿名サインイン・公開待ちの再送（共有と成長）。
      navigatorKey: appNavigatorKey,
      builder: (context, child) =>
          SharingHost(child: child ?? const SizedBox.shrink()),
      navigatorObservers: [
        appRouteObserver,
        ref.watch(analyticsRouteObserverProvider),
      ],
      routes: appRoutes,
    );
  }
}

/// 全画面のルート表。新しい画面は `core/routes.dart` に名前を足してここへ登録する。
final Map<String, WidgetBuilder> appRoutes = {
  Routes.home: (context) => const HomeGate(),
  Routes.onboarding: (context) => const OnboardingPage(),
  Routes.live: (context) => const LivePage(),
  Routes.liveSummary: (context) => const LiveSummaryPage(),
  Routes.camera: (context) => const CameraPage(),
  Routes.recognitionLoading: (context) => const RecognitionLoadingPage(),
  Routes.recognition: (context) => const RecognitionPage(),
  Routes.manualInput: (context) => const RecognitionPage(manual: true),
  Routes.quiz: (context) => const QuizPage(),
  Routes.result: (context) => const ResultPage(),
  Routes.candidateDetail: (context) => const CandidateDetailPage(),
  Routes.explanation: (context) => const ExplanationPage(),
  Routes.shareCard: (context) => const ShareCardPage(),
  Routes.publish: (context) => const PublishPage(),
  Routes.today: (context) => const TodayPage(),
  Routes.myProblems: (context) => const MyProblemsPage(),
  Routes.history: (context) => const HistoryPage(),
  Routes.paywall: (context) => const PaywallPage(),
  Routes.settings: (context) => const SettingsPage(),
  Routes.winScore: (context) => const WinScorePage(),
};
