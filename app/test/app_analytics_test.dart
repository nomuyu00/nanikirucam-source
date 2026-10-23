// 流用元: reference/agari_cam/test/app_analytics_test.dart（2026-10-21 時点）
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AnalyticsBackend backend;
  late AppAnalytics analytics;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    backend = _AnalyticsBackend();
    analytics = AppAnalytics(backend: backend);
  });

  tearDown(() => analytics.dispose());

  test(
    'collection defaults off and events are dropped without explicit consent',
    () async {
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      await analytics.initialize();
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      await analytics.logScreen('/');

      expect(analytics.ready, isTrue);
      expect(analytics.hasChoice, isFalse);
      expect(analytics.enabled, isFalse);
      expect(backend.collectionChanges, [false]);
      expect(backend.events, isEmpty);
      expect(backend.screens, isEmpty);
    },
  );

  test(
    'opt-in permits fixed events and screens and withdrawal stops both',
    () async {
      await analytics.setEnabled(true);
      await analytics.logEvent(
        AnalyticsEvent.captureSucceeded,
        parameters: {'source': 'camera', 'duration_ms': 123},
      );
      await analytics.logScreen('/camera');
      expect(backend.events.single.name, 'capture_succeeded');
      expect(backend.events.single.parameters, {
        'source': 'camera',
        'duration_ms': 123,
      });
      expect(backend.screens, ['camera']);

      await analytics.setEnabled(false);
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      await analytics.logScreen('/settings');
      expect(backend.events, hasLength(1));
      expect(backend.screens, hasLength(1));
      expect(backend.collectionChanges, [false, true, false]);
      expect(analytics.enabled, isFalse);
      expect(analytics.hasChoice, isTrue);
    },
  );

  test('live trial extension: reward live_trial and bonus_s are allowed, camelCase is not', () async {
    await analytics.setEnabled(true);
    await analytics.logEvent(
      AnalyticsEvent.rewardedGranted,
      parameters: {'reward': 'live_trial'},
    );
    await analytics.logEvent(
      AnalyticsEvent.rewardedGranted,
      parameters: {'reward': 'liveTrial'},
    );
    await analytics.logEvent(
      AnalyticsEvent.liveTrialExtended,
      parameters: {'bonus_s': 120, 'trigger': 'live_trial'},
    );
    await analytics.logEvent(
      AnalyticsEvent.liveTrialExtended,
      parameters: {'bonus_s': 99999, 'trigger': 'home'},
    );
    expect(backend.events.map((e) => e.name), [
      'rewarded_granted',
      'rewarded_granted',
      'live_trial_extended',
      'live_trial_extended',
    ]);
    expect(backend.events[0].parameters, {'reward': 'live_trial'});
    expect(backend.events[1].parameters, isEmpty);
    expect(backend.events[2].parameters, {
      'bonus_s': 120,
      'trigger': 'live_trial',
    });
    // 上限を超える値は上限に丸められる。
    expect(backend.events[3].parameters, {'bonus_s': 180, 'trigger': 'home'});
  });

  test(
    'explicit consent and withdrawal persist across service instances',
    () async {
      await analytics.setEnabled(true);
      final nextBackend = _AnalyticsBackend();
      final next = AppAnalytics(backend: nextBackend);
      addTearDown(next.dispose);
      await next.initialize();
      expect(next.hasChoice, isTrue);
      expect(next.enabled, isTrue);
      expect(nextBackend.collectionChanges, [true]);

      await next.setEnabled(false);
      final lastBackend = _AnalyticsBackend();
      final last = AppAnalytics(backend: lastBackend);
      addTearDown(last.dispose);
      await last.initialize();
      expect(last.hasChoice, isTrue);
      expect(last.enabled, isFalse);
      expect(lastBackend.collectionChanges, [false]);
    },
  );

  test(
    'unknown strings, photos, names, receipts and identifiers never reach the backend',
    () async {
      await analytics.setEnabled(true);
      await analytics.logEvent(
        AnalyticsEvent.scoreCalculated,
        parameters: {
          'source': 'Alice',
          'error_code': '/private/photo.jpg',
          'edit_action': 'change',
          'name': 'Alice',
          'player_name': 'Bob',
          'photo': 'base64-image',
          'image_bytes': [1, 2, 3],
          'path': '/private/photo.jpg',
          'receipt': 'receipt-data',
          'product_id': 'secret-product',
          'user_id': 'user-123',
          'exception': 'user-supplied error',
          'tile_count': 14.0,
          'duration_ms': -5,
          'han': 12345,
          'fu': 30,
          'hand_count': 1001,
        },
      );
      expect(backend.events.single.parameters, {
        'edit_action': 'change',
        'duration_ms': 0,
        'han': 100,
        'fu': 30,
        'hand_count': 1000,
      });
      await analytics.logScreen('/players/Alice');
      await analytics.logScreen('/result?name=Alice');
      expect(backend.screens, isEmpty);
    },
  );

  test(
    'concurrent initialization shares one future and initializes the SDK once',
    () async {
      backend.initializationGate = Completer<void>();
      final first = analytics.initialize();
      final second = analytics.initialize();
      expect(identical(first, second), isTrue);
      await _flush();
      expect(backend.initializeCalls, 1);
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      expect(backend.events, isEmpty);
      backend.initializationGate!.complete();
      await Future.wait([first, second]);
      expect(backend.initializeCalls, 1);
    },
  );

  test(
    'SDK initialization failure is contained and play can continue',
    () async {
      backend.failInitialization = true;
      await analytics.initialize();
      await analytics.setEnabled(true);
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      await analytics.logScreen('/');
      expect(analytics.ready, isTrue);
      expect(analytics.available, isFalse);
      expect(backend.events, isEmpty);
      expect(backend.screens, isEmpty);
    },
  );

  test(
    'preference loading failure is contained and events remain blocked',
    () async {
      final unavailable = AppAnalytics(
        backend: backend,
        preferencesLoader: () async =>
            throw StateError('Preferences unavailable'),
      );
      addTearDown(unavailable.dispose);
      await unavailable.initialize();
      await unavailable.setEnabled(true);
      await unavailable.logEvent(AnalyticsEvent.cameraOpened);
      expect(unavailable.ready, isTrue);
      expect(unavailable.available, isTrue);
      expect(unavailable.consentUpdateFailed, isTrue);
      expect(backend.collectionChanges, [false, false]);
      expect(backend.events, isEmpty);
    },
  );

  test(
    'delivery errors do not escape or disable subsequent app actions',
    () async {
      await analytics.setEnabled(true);
      backend.failDelivery = true;
      await analytics.logEvent(AnalyticsEvent.cameraFailed);
      await analytics.logScreen('/camera');
      backend.failDelivery = false;
      await analytics.logEvent(AnalyticsEvent.cameraReady);
      await analytics.logScreen('/result');
      expect(backend.events.map((event) => event.name), ['camera_ready']);
      expect(backend.screens, ['result']);
    },
  );

  test('failed native revocation still stops app events immediately', () async {
    await analytics.setEnabled(true);
    backend.failConsentUpdates = true;
    await analytics.setEnabled(false);
    await analytics.logEvent(AnalyticsEvent.cameraOpened);
    await analytics.logScreen('/');
    expect(analytics.enabled, isFalse);
    expect(backend.events, isEmpty);
    expect(backend.screens, isEmpty);
  });

  for (final throwOnWrite in [true, false]) {
    test(
      'revocation stops native collection when preference writes ${throwOnWrite ? 'throw' : 'return false'}',
      () async {
        final preferences = _Preferences();
        final native = _AnalyticsBackend();
        final subject = AppAnalytics(
          backend: native,
          preferencesLoader: () async => preferences,
        );
        addTearDown(subject.dispose);
        await subject.setEnabled(true);
        preferences.failWrites = true;
        preferences.throwOnWrite = throwOnWrite;

        await subject.setEnabled(false);
        expect(native.collectionChanges, [false, true, false]);
        expect(subject.enabled, isFalse);
        expect(subject.consentUpdateFailed, isTrue);
        await subject.logEvent(AnalyticsEvent.cameraOpened);
        expect(native.events, isEmpty);

        preferences.failWrites = false;
        await subject.setEnabled(false);
        expect(subject.consentUpdateFailed, isFalse);
        expect(preferences.choice, isFalse);
      },
    );
  }

  test(
    'a failed initial preference load stops a previously active SDK and can retry',
    () async {
      final native = _AnalyticsBackend()..nativeCollectionEnabled = true;
      final preferences = _Preferences();
      var failLoading = true;
      final subject = AppAnalytics(
        backend: native,
        preferencesLoader: () async {
          if (failLoading) throw StateError('Storage unavailable');
          return preferences;
        },
      );
      addTearDown(subject.dispose);

      await subject.initialize();
      expect(native.nativeCollectionEnabled, isFalse);
      expect(subject.consentUpdateFailed, isTrue);
      await subject.logEvent(AnalyticsEvent.cameraOpened);
      expect(native.events, isEmpty);

      failLoading = false;
      await subject.setEnabled(false);
      expect(subject.consentUpdateFailed, isFalse);
      expect(preferences.choice, isFalse);
    },
  );

  test('failed opt-in persistence never enables the native SDK', () async {
    final preferences = _Preferences()..failWrites = true;
    final native = _AnalyticsBackend();
    final subject = AppAnalytics(
      backend: native,
      preferencesLoader: () async => preferences,
    );
    addTearDown(subject.dispose);

    await subject.setEnabled(true);
    expect(subject.consentUpdateFailed, isTrue);
    expect(native.collectionChanges, [false, false]);
    await subject.logEvent(AnalyticsEvent.cameraOpened);
    expect(native.events, isEmpty);
  });

  test(
    'native update failure reports failure and keeps app delivery stopped',
    () async {
      await analytics.setEnabled(true);
      backend.failConsentUpdates = true;
      await analytics.setEnabled(false);
      expect(analytics.consentUpdateFailed, isTrue);
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      expect(backend.events, isEmpty);

      backend.failConsentUpdates = false;
      await analytics.setEnabled(false);
      expect(analytics.consentUpdateFailed, isFalse);
    },
  );

  test(
    'saved opt-in with a failed initial SDK consent update cannot send',
    () async {
      final preferences = _Preferences()..choice = true;
      final native = _AnalyticsBackend()..failConsentUpdates = true;
      final subject = AppAnalytics(
        backend: native,
        preferencesLoader: () async => preferences,
      );
      addTearDown(subject.dispose);
      await subject.initialize();
      expect(subject.enabled, isTrue);
      expect(subject.available, isFalse);
      await subject.logEvent(AnalyticsEvent.cameraOpened);
      expect(native.events, isEmpty);
    },
  );

  test('withdrawal wins over an earlier pending opt-in update', () async {
    await analytics.initialize();
    backend.nextConsentGate = Completer<void>();
    final enabling = analytics.setEnabled(true);
    await _flush();
    await analytics.logEvent(AnalyticsEvent.cameraOpened);
    expect(backend.events, isEmpty);
    final revoking = analytics.setEnabled(false);
    await _flush();
    backend.nextConsentGate!.complete();
    await Future.wait([enabling, revoking]);
    await analytics.logEvent(AnalyticsEvent.cameraOpened);
    expect(analytics.enabled, isFalse);
    expect(backend.collectionChanges, [false, true, false]);
    expect(backend.events, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(AppAnalytics.preferenceKey), isFalse);
  });

  test(
    'unsupported platforms retain the choice without invoking the SDK',
    () async {
      backend.isSupported = false;
      await analytics.setEnabled(true);
      await analytics.logEvent(AnalyticsEvent.cameraOpened);
      expect(analytics.supported, isFalse);
      expect(backend.initializeCalls, 0);
      expect(backend.collectionChanges, isEmpty);
      expect(backend.events, isEmpty);
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _AnalyticsBackend implements AnalyticsBackend {
  bool isSupported = true;
  bool failInitialization = false;
  bool failConsentUpdates = false;
  bool failDelivery = false;
  bool nativeCollectionEnabled = false;
  int initializeCalls = 0;
  Completer<void>? initializationGate;
  Completer<void>? nextConsentGate;
  bool _consentGateUsed = false;
  final collectionChanges = <bool>[];
  final events = <({String name, Map<String, Object> parameters})>[];
  final screens = <String>[];

  @override
  bool get supported => isSupported;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (failInitialization) throw StateError('SDK unavailable');
    await initializationGate?.future;
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    if (failConsentUpdates) throw StateError('Consent SDK unavailable');
    collectionChanges.add(enabled);
    nativeCollectionEnabled = enabled;
    final gate = nextConsentGate;
    if (gate != null && !_consentGateUsed) {
      _consentGateUsed = true;
      await gate.future;
    }
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    if (failDelivery) throw StateError('Delivery unavailable');
    events.add((name: name, parameters: Map.of(parameters)));
  }

  @override
  Future<void> logScreen(String name) async {
    if (failDelivery) throw StateError('Delivery unavailable');
    screens.add(name);
  }
}

class _Preferences extends Fake implements SharedPreferences {
  bool? choice;
  bool failWrites = false;
  bool throwOnWrite = false;

  @override
  bool? getBool(String key) => choice;

  @override
  Future<bool> setBool(String key, bool value) async {
    if (failWrites) {
      if (throwOnWrite) throw StateError('Preference storage unavailable');
      return false;
    }
    choice = value;
    return true;
  }
}
