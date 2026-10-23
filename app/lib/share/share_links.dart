// 流用元: reference/agari_cam/lib/share/share_links.dart（2026-10-21 時点）
// 改修（設計書 2.2・7 章）: storeUrl に pid（問題 ID）と ref（紹介コード）を追加。
// ストア ID・パッケージ名はなにきるカム用（App Store ID は App Store Connect の Apple ID）。
import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/core/app_config.dart';

/// ストアへの導線。共有された画像・文章から見た人がインストールできるようにする。
class ShareLinks {
  /// App Store Connect で取得した数値 ID（docs/store/test-release-operations.md の Apple ID）。
  /// 空にすると iOS は Web の URL に誘導する。
  static const iosAppStoreId = '6825623654';
  static const androidPackageName = 'jp.aile.nanikiru_cam';

  /// App Store Connect の「キャンペーンリンク」用プロバイダトークン（pt）。
  /// 設定すると共有経由のインストールを App Analytics で計測できる。
  static const appStoreProviderToken = '';

  static const appStoreUrl = 'https://apps.apple.com/jp/app/id$iosAppStoreId';
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=$androidPackageName';

  /// 共有の種類ごとにキャンペーン名を付けたストア URL。
  /// Google Play は referrer の utm_* と pid / ref で、App Store は pt/ct で流入元を集計する。
  /// Android は初回起動で Install Referrer から [problemId] と [referralCode] を読んで
  /// その問題を開く（設計書 7 章）。iOS の遅延ディープリンクは v1 では持たない。
  static String storeUrl({
    required String campaign,
    String? problemId,
    String? referralCode,
    TargetPlatform? platform,
  }) {
    final target = platform ?? defaultTargetPlatform;
    if (target == TargetPlatform.android) {
      final referrer = Uri.encodeComponent(
        [
          'utm_source=share',
          'utm_campaign=$campaign',
          if (problemId != null && problemId.isNotEmpty) 'pid=$problemId',
          if (referralCode != null && referralCode.isNotEmpty)
            'ref=$referralCode',
        ].join('&'),
      );
      return '$playStoreUrl&referrer=$referrer';
    }
    if (iosAppStoreId.isEmpty) {
      // ストア未公開の間は Web の問題ページ（なければトップ）に誘導する。
      if (problemId != null && problemId.isNotEmpty) {
        return AppConfig.problemUrl(problemId, referralCode: referralCode);
      }
      return AppConfig.webBaseUrl;
    }
    if (appStoreProviderToken.isEmpty) return appStoreUrl;
    return 'https://apps.apple.com/jp/app/apple-store/id$iosAppStoreId'
        '?pt=$appStoreProviderToken&ct=$campaign&mt=8';
  }

  /// [url] が問題ページの URL（`<webBaseUrl>/p/...`）か。ストアの URL なら false。
  static bool isProblemUrl(String url) =>
      url.startsWith('${AppConfig.webBaseUrl}/p/');

  /// 問題カードの QR・本文に載せる URL（`/p/{problemId}?ref={code}`）。
  static String problemUrl(String problemId, {String? referralCode}) =>
      AppConfig.problemUrl(problemId, referralCode: referralCode);
}
