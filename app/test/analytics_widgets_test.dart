// 流用元: reference/agari_cam/test/analytics_widgets_test.dart（2026-10-21 時点）
// 改修: 課金・設定画面に依存するテストを除いた（同意カードと画面名の記録だけ）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/analytics_route_observer.dart';
import 'package:nanikiru_cam/analytics/analytics_widgets.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Backend implements AnalyticsBackend {
  final screens = <String>[];
  final events = <String>[];
  @override
  bool get supported => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> setCollectionEnabled(bool enabled) async {}
  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    events.add(name);
  }

  @override
  Future<void> logScreen(String name) async {
    screens.add(name);
  }
}

class _DelayedBackend extends _Backend {
  final initialized = Completer<void>();
  @override
  Future<void> initialize() => initialized.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppAnalytics> create(_Backend backend) async {
    SharedPreferences.setMockInitialValues({});
    final analytics = AppAnalytics(backend: backend);
    await analytics.initialize();
    return analytics;
  }

  testWidgets('analytics requires a choice and opt-in records home once', (
    tester,
  ) async {
    final backend = _Backend();
    final analytics = await create(backend);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAnalyticsProvider.overrideWith((ref) => analytics)],
        child: const MaterialApp(home: Scaffold(body: AnalyticsConsentCard())),
      ),
    );
    expect(analytics.enabled, isFalse);
    expect(backend.screens, isEmpty);
    await tester.tap(find.text('Allow analytics'));
    await tester.pumpAndSettle();
    expect(analytics.enabled, isTrue);
    expect(backend.screens, ['home']);
    expect(find.byType(Card), findsNothing);
  });

  for (final replaceHome in [false, true]) {
    testWidgets(
      'delayed consent never reports home after ${replaceHome ? 'replacing' : 'covering'} its route',
      (tester) async {
        final backend = _ConsentBackend()..enableGate = Completer<void>();
        final analytics = await create(backend);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appAnalyticsProvider.overrideWith((ref) => analytics)],
            child: MaterialApp(
              navigatorKey: navigator,
              navigatorObservers: [AnalyticsRouteObserver(analytics)],
              routes: {
                '/': (_) => const Scaffold(body: AnalyticsConsentCard()),
                '/camera': (_) => const Scaffold(body: Text('Camera page')),
                '/settings': (_) => const Scaffold(body: Text('Settings page')),
              },
            ),
          ),
        );
        await tester.tap(find.text('Allow analytics'));
        await tester.pump();

        if (replaceHome) {
          navigator.currentState!.pushReplacementNamed('/camera');
        } else {
          navigator.currentState!.pushNamed('/camera');
        }
        await tester.pumpAndSettle();
        expect(find.text('Camera page'), findsOneWidget);
        expect(backend.screens, isEmpty);

        backend.enableGate!.complete();
        await tester.pumpAndSettle();
        expect(analytics.enabled, isTrue);
        expect(backend.screens, isEmpty);
        expect(tester.takeException(), isNull);

        navigator.currentState!.pushNamed('/settings');
        await tester.pumpAndSettle();
        expect(backend.screens, ['settings']);
      },
    );
  }

  testWidgets(
    'settings shows failed revocation and retry stops native collection',
    (tester) async {
      final backend = _ConsentBackend();
      final analytics = await create(backend);
      await analytics.setEnabled(true);
      backend.failConsentChanges = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appAnalyticsProvider.overrideWith((ref) => analytics)],
          child: const MaterialApp(
            home: Scaffold(body: AnalyticsSettingsTile()),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(analytics.enabled, isFalse);
      expect(analytics.consentUpdateFailed, isTrue);
      expect(backend.nativeCollectionEnabled, isTrue);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Could not finish changing'), findsOneWidget);
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      expect(backend.events, isEmpty);

      backend.failConsentChanges = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(analytics.consentUpdateFailed, isFalse);
      expect(backend.nativeCollectionEnabled, isFalse);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('Could not finish changing'), findsNothing);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AppAnalytics.preferenceKey,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'consent card remains actionable after a failed save and can retry opt-in',
    (tester) async {
      final backend = _ConsentBackend();
      final preferences = _FailingPreferences();
      final analytics = AppAnalytics(
        backend: backend,
        preferencesLoader: () async => preferences,
      );
      await analytics.initialize();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appAnalyticsProvider.overrideWith((ref) => analytics)],
          child: const MaterialApp(
            home: Scaffold(body: AnalyticsConsentCard()),
          ),
        ),
      );

      await tester.tap(find.text('Allow analytics'));
      await tester.pumpAndSettle();
      expect(analytics.consentUpdateFailed, isTrue);
      expect(backend.nativeCollectionEnabled, isFalse);
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Do not allow'), findsOneWidget);
      expect(backend.screens, isEmpty);

      preferences.failWrites = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(analytics.consentUpdateFailed, isFalse);
      expect(analytics.enabled, isTrue);
      expect(backend.nativeCollectionEnabled, isTrue);
      expect(preferences.choice, isTrue);
      expect(find.byType(Card), findsNothing);
      expect(find.text('Retry'), findsNothing);
    },
  );

  testWidgets('declining analytics persists a choice without events', (
    tester,
  ) async {
    final backend = _Backend();
    final analytics = await create(backend);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAnalyticsProvider.overrideWith((ref) => analytics)],
        child: const MaterialApp(home: Scaffold(body: AnalyticsConsentCard())),
      ),
    );
    await tester.tap(find.text('Do not allow'));
    await tester.pumpAndSettle();
    expect(analytics.hasChoice, isTrue);
    expect(analytics.enabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        AppAnalytics.preferenceKey,
      ),
      isFalse,
    );
    expect(backend.screens, isEmpty);
  });

  testWidgets('settings opt-out stops subsequent analytics events', (
    tester,
  ) async {
    final backend = _Backend();
    final analytics = await create(backend);
    await analytics.setEnabled(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appAnalyticsProvider.overrideWith((ref) => analytics)],
        child: const MaterialApp(home: Scaffold(body: AnalyticsSettingsTile())),
      ),
    );
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await analytics.logEvent(AnalyticsEvent.cameraOpened);
    expect(analytics.enabled, isFalse);
    expect(backend.events, isEmpty);
  });

  testWidgets('only named app pages are logged, without route arguments', (
    tester,
  ) async {
    final backend = _Backend();
    final analytics = await create(backend);
    await analytics.setEnabled(true);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [AnalyticsRouteObserver(analytics)],
        routes: {
          '/': (_) => const Scaffold(body: Text('home')),
          '/camera': (_) => const Scaffold(body: Text('camera')),
          '/unknown': (_) => const Scaffold(body: Text('other')),
        },
      ),
    );
    key.currentState!.pushNamed(
      '/camera',
      arguments: {'playerName': 'private'},
    );
    await tester.pumpAndSettle();
    key.currentState!.pushNamed(
      '/unknown',
      arguments: {'imagePath': '/private.jpg'},
    );
    await tester.pumpAndSettle();
    expect(backend.screens, ['home', 'camera']);
    analytics.dispose();
  });

  testWidgets('returning users get the first screen after SDK initialization', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({AppAnalytics.preferenceKey: true});
    final backend = _DelayedBackend();
    final analytics = AppAnalytics(backend: backend);
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [AnalyticsRouteObserver(analytics)],
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pump();
    expect(backend.screens, isEmpty);
    backend.initialized.complete();
    await tester.pumpAndSettle();
    expect(backend.screens, ['home']);
    analytics.dispose();
  });

  testWidgets('closing a dialog does not count the same screen twice', (
    tester,
  ) async {
    final backend = _Backend();
    final analytics = await create(backend);
    await analytics.setEnabled(true);
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [AnalyticsRouteObserver(analytics)],
        home: const Scaffold(body: Text('home')),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      showDialog<void>(
        context: key.currentContext!,
        builder: (_) => const AlertDialog(content: Text('private details')),
      ),
    );
    await tester.pumpAndSettle();
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(backend.screens, ['home']);
    analytics.dispose();
  });
}

class _ConsentBackend extends _Backend {
  Completer<void>? enableGate;
  bool failConsentChanges = false;
  bool nativeCollectionEnabled = false;

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    if (failConsentChanges) {
      throw StateError('Native consent update unavailable');
    }
    if (enabled) await enableGate?.future;
    nativeCollectionEnabled = enabled;
  }
}

class _FailingPreferences extends Fake implements SharedPreferences {
  bool? choice;
  bool failWrites = true;

  @override
  bool? getBool(String key) => choice;

  @override
  Future<bool> setBool(String key, bool value) async {
    if (failWrites) return false;
    choice = value;
    return true;
  }
}
