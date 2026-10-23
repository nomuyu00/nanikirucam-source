// 流用元: reference/agari_cam/test/consent_manager_test.dart（2026-10-21 時点）
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/consent/consent_manager.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';

void main() {
  late _ConsentInformation information;
  late Completer<void> consentDismissed;
  late Completer<void> privacyDismissed;
  late ConsentManager manager;
  late int consentForms;
  late int privacyForms;

  setUp(() {
    information = _ConsentInformation();
    consentDismissed = Completer<void>();
    privacyDismissed = Completer<void>();
    consentForms = 0;
    privacyForms = 0;
    manager = ConsentManager(
      consentInformation: information,
      loadAndShowConsentForm: (onDismissed) async {
        consentForms++;
        await consentDismissed.future;
        onDismissed(null);
      },
      showPrivacyOptionsForm: (onDismissed) async {
        privacyForms++;
        await privacyDismissed.future;
        onDismissed(null);
      },
    );
  });

  tearDown(() => manager.dispose());

  test(
    'first-launch ads stay blocked until UMP permits them after dismissal',
    () async {
      final initialization = manager.initAndRequestIfNeeded();
      expect(manager.canRequestAds, isFalse);
      await _flush();
      information.succeed!();
      await _flush();
      expect(consentForms, 1);
      information.allowed = true;
      expect(manager.canRequestAds, isFalse);

      consentDismissed.complete();
      await initialization;
      expect(manager.canRequestAds, isTrue);
      await manager.initAndRequestIfNeeded();
      expect(information.updateCalls, 1);
    },
  );

  test('previous-session consent remains usable if the update fails', () async {
    information.allowed = true;
    final initialization = manager.initAndRequestIfNeeded();
    await _flush();
    expect(manager.canRequestAds, isTrue);

    information.fail!(FormError(errorCode: 1, message: 'Network unavailable'));
    await initialization;
    expect(manager.canRequestAds, isTrue);
    expect(consentForms, 0);
  });

  test('a failed update without prior consent never enables ads', () async {
    final initialization = manager.initAndRequestIfNeeded();
    information.fail!(FormError(errorCode: 1, message: 'Network unavailable'));
    await initialization;
    expect(manager.canRequestAds, isFalse);
  });

  test(
    'a dismissed form cannot enable ads when UMP still disallows requests',
    () async {
      final initialization = manager.initAndRequestIfNeeded();
      information.succeed!();
      consentDismissed.complete();
      await initialization;
      expect(manager.canRequestAds, isFalse);
    },
  );

  test(
    'privacy changes block requests while open and publish withdrawn consent',
    () async {
      information.allowed = true;
      information.privacyRequired = true;
      final initialization = manager.initAndRequestIfNeeded();
      information.succeed!();
      consentDismissed.complete();
      await initialization;

      final container = ProviderContainer(
        overrides: [consentManagerProvider.overrideWithValue(manager)],
      );
      addTearDown(container.dispose);
      final enabled = <bool>[];
      final subscription = container.listen(
        adsEnabledProvider,
        (previous, next) => enabled.add(next),
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      expect(
        container.read(consentStateProvider).privacyOptionsRequired,
        isTrue,
      );
      expect(container.read(adsEnabledProvider), isTrue);

      final privacyFlow = manager.showPrivacyOptions();
      await _flush();
      expect(privacyForms, 1);
      expect(container.read(adsEnabledProvider), isFalse);
      information.allowed = false;
      privacyDismissed.complete();
      await privacyFlow;
      expect(container.read(adsEnabledProvider), isFalse);
      expect(enabled, [true, false]);
    },
  );

  test(
    'closing privacy options resumes allowed ads and no-op entry stays hidden',
    () async {
      information.allowed = true;
      information.privacyRequired = true;
      final initialization = manager.initAndRequestIfNeeded();
      information.fail!(
        FormError(errorCode: 1, message: 'Network unavailable'),
      );
      await initialization;
      final states = <bool>[];
      manager.addListener(() => states.add(manager.canRequestAds));
      final privacyFlow = manager.showPrivacyOptions();
      await _flush();
      expect(manager.canRequestAds, isFalse);
      privacyDismissed.complete();
      await privacyFlow;
      expect(states, [false, true]);

      information.privacyRequired = false;
      await manager.showPrivacyOptions();
      expect(privacyForms, 1);
      expect(manager.privacyOptionsRequired, isFalse);
    },
  );

  test('Pro never shows ads even when UMP permits them', () async {
    information.allowed = true;
    final initialization = manager.initAndRequestIfNeeded();
    information.succeed!();
    consentDismissed.complete();
    await initialization;

    final container = ProviderContainer(
      overrides: [consentManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);
    expect(container.read(adsEnabledProvider), isTrue);

    container.read(entitlementsProvider.notifier).state =
        const EntitlementState(pro: true, source: EntitlementSource.store);
    expect(container.read(adsEnabledProvider), isFalse);
  });

  test('an unreadable UMP permission fails closed', () async {
    information.allowed = true;
    information.failPermissionRead = true;
    final initialization = manager.initAndRequestIfNeeded();
    information.fail!(FormError(errorCode: 1, message: 'Network unavailable'));
    await initialization;
    expect(manager.canRequestAds, isFalse);
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

class _ConsentInformation extends Fake implements ConsentInformation {
  bool allowed = false;
  bool privacyRequired = false;
  bool failPermissionRead = false;
  int updateCalls = 0;
  OnConsentInfoUpdateSuccessListener? succeed;
  OnConsentInfoUpdateFailureListener? fail;

  @override
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    OnConsentInfoUpdateSuccessListener successListener,
    OnConsentInfoUpdateFailureListener failureListener,
  ) {
    updateCalls++;
    succeed = successListener;
    fail = failureListener;
  }

  @override
  Future<bool> canRequestAds() async {
    if (failPermissionRead) throw StateError('Permission unavailable');
    return allowed;
  }

  @override
  Future<PrivacyOptionsRequirementStatus>
  getPrivacyOptionsRequirementStatus() async => privacyRequired
      ? PrivacyOptionsRequirementStatus.required
      : PrivacyOptionsRequirementStatus.notRequired;
}
