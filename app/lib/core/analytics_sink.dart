import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';

/// 計測イベントを送る窓口。同意の判定・許可リストでの絞り込みは [AppAnalytics] が行う。
/// 課金・広告・通知・紹介の各サービスは [AppAnalytics] を直接持たずこれを受け取り、
/// テストでは [analyticsSinkProvider] を記録用の関数に差し替える。
typedef AnalyticsSink =
    void Function(AnalyticsEvent event, [Map<String, Object> parameters]);

final analyticsSinkProvider = Provider<AnalyticsSink>((ref) {
  return (event, [parameters = const {}]) {
    try {
      unawaited(
        ref.read(appAnalyticsProvider).logEvent(event, parameters: parameters),
      );
    } catch (_) {
      // provider の破棄後など。計測の失敗はアプリの動作に影響させない。
    }
  };
});
