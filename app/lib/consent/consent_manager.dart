// 流用元: reference/agari_cam/lib/consent/consent_manager.dart（2026-10-21 時点）
import 'dart:async';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

typedef ConsentState = ({
  bool canRequestAds,
  bool canRequestPersonalizedAds,
  bool privacyOptionsRequired,
});

typedef ConsentFormPresenter =
    Future<void> Function(OnConsentFormDismissedListener onDismissed);

/// Handles UMP consent and ATT without blocking the app's first frame.
class ConsentManager extends ChangeNotifier {
  ConsentManager({
    ConsentInformation? consentInformation,
    ConsentFormPresenter? loadAndShowConsentForm,
    ConsentFormPresenter? showPrivacyOptionsForm,
  }) : _consentInformation = consentInformation ?? ConsentInformation.instance,
       _loadAndShowConsentForm =
           loadAndShowConsentForm ??
           ConsentForm.loadAndShowConsentFormIfRequired,
       _showPrivacyOptionsForm =
           showPrivacyOptionsForm ?? ConsentForm.showPrivacyOptionsForm;

  static final instance = ConsentManager();

  final ConsentInformation _consentInformation;
  final ConsentFormPresenter _loadAndShowConsentForm;
  final ConsentFormPresenter _showPrivacyOptionsForm;
  Future<void>? _initialization;
  bool _canRequestAds = false;
  bool _privacyOptionsRequired = false;
  bool _privacyFormOpen = false;
  bool _disposed = false;
  int _refreshGeneration = 0;
  TrackingStatus _trackingStatus = TrackingStatus.notDetermined;

  bool get canRequestAds => _canRequestAds && !_privacyFormOpen;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  TrackingStatus get trackingStatus => _trackingStatus;

  /// ATT controls IDFA use; UMP separately controls whether ads may be requested.
  bool get canRequestPersonalizedAds {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }
    return _trackingStatus == TrackingStatus.authorized;
  }

  ConsentState get state => (
    canRequestAds: canRequestAds,
    canRequestPersonalizedAds: canRequestPersonalizedAds,
    privacyOptionsRequired: privacyOptionsRequired,
  );

  Future<void> initAndRequestIfNeeded() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      await _requestUmpConsent();
      if (_disposed) return;
      final previousState = state;
      await _requestTrackingAuthorizationIfNeeded();
      if (!_disposed && previousState != state) notifyListeners();
    } catch (error) {
      debugPrint('[ConsentManager] Initialization failed: $error');
      await _refreshConsentState();
    }
  }

  Future<void> _requestUmpConsent() async {
    final completer = Completer<void>();
    _consentInformation.requestConsentInfoUpdate(
      ConsentRequestParameters(tagForUnderAgeOfConsent: false),
      () async {
        try {
          await _loadAndShowConsentForm((formError) {
            if (formError != null) {
              debugPrint(
                '[ConsentManager] Consent form failed: '
                '${formError.errorCode} ${formError.message}',
              );
            }
          });
        } catch (error) {
          debugPrint('[ConsentManager] UMP flow failed: $error');
        } finally {
          await _refreshConsentState();
          if (!completer.isCompleted) completer.complete();
        }
      },
      (formError) async {
        debugPrint(
          '[ConsentManager] Consent update failed: '
          '${formError.errorCode} ${formError.message}',
        );
        // A failed update may still leave valid consent from a prior session.
        await _refreshConsentState();
        if (!completer.isCompleted) completer.complete();
      },
    );

    // UMP may already have valid consent from an earlier app session.
    unawaited(_refreshConsentState());
    // This runs after runApp. Waiting for dismissal keeps ATT from appearing
    // over an open UMP form; a missing callback never enables ads by timeout.
    await completer.future;
  }

  Future<void> _refreshConsentState() async {
    final generation = ++_refreshGeneration;
    var allowed = false;
    var privacyRequired = _privacyOptionsRequired;
    try {
      allowed = await _consentInformation.canRequestAds();
    } catch (error) {
      debugPrint('[ConsentManager] Consent availability failed: $error');
    }
    try {
      privacyRequired =
          await _consentInformation.getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required;
    } catch (error) {
      debugPrint('[ConsentManager] Privacy options status failed: $error');
    }
    if (_disposed || generation != _refreshGeneration) return;
    final previousState = state;
    _canRequestAds = allowed;
    _privacyOptionsRequired = privacyRequired;
    if (previousState != state) notifyListeners();
  }

  Future<void> _requestTrackingAuthorizationIfNeeded() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      _trackingStatus =
          await AppTrackingTransparency.trackingAuthorizationStatus;
      if (_trackingStatus != TrackingStatus.notDetermined) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (_disposed) return;
      _trackingStatus =
          await AppTrackingTransparency.requestTrackingAuthorization();
    } catch (error) {
      debugPrint('[ConsentManager] ATT request failed: $error');
    }
  }

  Future<void> showPrivacyOptions() async {
    if (_disposed || _privacyFormOpen) return;
    await _refreshConsentState();
    if (_disposed || !_privacyOptionsRequired || _privacyFormOpen) return;
    // Drop cached ads before choices can change, including personalized ads.
    _privacyFormOpen = true;
    notifyListeners();
    try {
      await _showPrivacyOptionsForm((formError) {
        if (formError != null) {
          debugPrint(
            '[ConsentManager] Privacy options failed: '
            '${formError.errorCode} ${formError.message}',
          );
        }
      });
    } catch (error) {
      debugPrint('[ConsentManager] Privacy options failed: $error');
    } finally {
      await _refreshConsentState();
      _privacyFormOpen = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
