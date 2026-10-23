// 流用元: reference/agari_cam/lib/analytics/analytics_route_observer.dart（2026-10-21 時点）
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';

final analyticsRouteObserverProvider = Provider<AnalyticsRouteObserver>((ref) {
  return AnalyticsRouteObserver(ref.read(appAnalyticsProvider));
});

class AnalyticsRouteObserver extends NavigatorObserver {
  AnalyticsRouteObserver(this.analytics);
  final AppAnalytics analytics;
  int _navigationGeneration = 0;

  void _record(Route<dynamic>? route) {
    // Dialogs and route arguments may contain user-entered text; never log them.
    if (route is! PageRoute) return;
    final generation = ++_navigationGeneration;
    final name = route.settings.name;
    if (name != null) unawaited(_recordWhenReady(name, generation));
  }

  Future<void> _recordWhenReady(String name, int generation) async {
    await analytics.initialize();
    // Keep the returning user's first screen, but discard a screen already left.
    if (generation == _navigationGeneration) await analytics.logScreen(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _record(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _record(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _record(newRoute);
}
