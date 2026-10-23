import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/ui/home/home_page.dart';
import 'package:nanikiru_cam/ui/onboarding/onboarding_page.dart';

/// Onboarding を見終えたか（初回のみ表示。仕様 6.1）。
final onboardingCompletedProvider = FutureProvider<bool>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return prefs.getBool(OnboardingGate.preferenceKey) ?? false;
});

abstract final class OnboardingGate {
  static const preferenceKey = 'onboarding.completed.v1';

  /// 見終えたことを保存し、起動直後の画面（[HomeGate]）を Home に切り替える。
  static Future<void> markCompleted(WidgetRef ref) async {
    final prefs = await ref.read(sharedPreferencesProvider.future);
    await prefs.setBool(preferenceKey, true);
    ref.invalidate(onboardingCompletedProvider);
  }
}

/// 起動直後の画面（`Routes.home`）。初回は Onboarding、以降は Home。
/// 保存された状態を読めなかったときは Home を出す。
class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = ref.watch(onboardingCompletedProvider);
    return completed.when(
      data: (done) => done ? const HomePage() : const OnboardingPage(),
      loading: () => const Scaffold(body: SizedBox.shrink()),
      error: (_, _) => const HomePage(),
    );
  }
}
