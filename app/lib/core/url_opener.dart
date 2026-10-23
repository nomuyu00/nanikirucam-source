import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// 外部のブラウザ・ストアのページを開く。テストでは差し替える。開けたら true。
final urlOpenerProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      debugPrint('[UrlOpener] $uri failed: $error');
      return false;
    }
  },
);

/// aile の WordPress 固定ページ。問題共有用の URL とは独立して管理する。
abstract final class LegalLinks {
  /// 本番の特定商取引法の表記ページ。`--dart-define=LEGAL_TOKUSHOHO_URL=...` で渡す。
  /// 空ならテスト版の購入案内ページ（一般販売前の表記）を開く。
  static const _tokushohoOverride = String.fromEnvironment(
    'LEGAL_TOKUSHOHO_URL',
  );
  static const _testPurchasesUrl =
      'https://aile-net.jp/nanikirucam-test-purchases/';

  static Uri get terms => Uri.parse('https://aile-net.jp/nanikirucam-terms/');
  static Uri get privacy =>
      Uri.parse('https://aile-net.jp/nanikirucam-privacy-policy/');
  static Uri get source =>
      Uri.parse('https://github.com/nomuyu00/nanikirucam-source');
  static Uri get tokushoho => Uri.parse(
    _tokushohoOverride.isNotEmpty ? _tokushohoOverride : _testPurchasesUrl,
  );
}

/// ストアの購読管理ページ（解約はここで行う。設計書 9 章）。
Uri subscriptionManagementUri({TargetPlatform? platform}) {
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => Uri.parse(
      'https://apps.apple.com/account/subscriptions',
    ),
    _ => Uri.parse('https://play.google.com/store/account/subscriptions'),
  };
}
