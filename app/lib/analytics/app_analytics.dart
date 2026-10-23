// 流用元: reference/agari_cam/lib/analytics/app_analytics.dart（2026-10-21 時点）
// 改修: AppConfig.firebaseEnabled が false なら Firebase を初期化せず、イベントも送らない。
// イベント列挙とパラメータ許可リストは、設計書 13 章に合わせて後で差し替える（今は流用元のまま）。
import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AnalyticsEvent {
  cameraOpened,
  cameraReady,
  cameraFailed,
  captureStarted,
  captureSucceeded,
  captureFailed,
  recognitionStarted,
  recognitionSucceeded,
  recognitionFailed,
  tileEdited,
  scoreCalculated,
  scoreFailed,
  resultShared,
  matchStarted,
  matchHandRecorded,
  matchFinished,
  rankingShared,
  purchaseStarted,
  purchaseCompleted,
  purchaseFailed,
  purchaseRestored,
  premiumViewed,
  resultViewed,
  shareTapped,
  shareCardSaved,
  historyOpened,
  appLinkShown,
  // なにきるカム（仕様 13 章・設計書 13 章のファネル）。名前は snake_case で送られる。
  onboardingCompleted,
  analysisStarted,
  analysisCompleted,
  quizAnswered,
  axisChanged,
  candidateOpened,
  explanationOpened,
  quotaExhausted,
  rewardedGranted,
  liveTrialExtended,
  paywallViewed,
  trialStarted,
  subscriptionActive,
  liveStarted,
  liveEnded,
  liveAdviceShown,
  liveAdviceFollowed,
  liveState,
  liveWinDetected,
  problemPublished,
  problemOpened,
  problemAnswered,
  dailyOpened,
  referralApplied,
  notificationOpened,
  // 和了の役と点数（Pro）。
  winScoreViewed,
  winScoreShared,
}

abstract class AnalyticsBackend {
  bool get supported;
  Future<void> initialize();
  Future<void> setCollectionEnabled(bool enabled);
  Future<void> logEvent(String name, Map<String, Object> parameters);
  Future<void> logScreen(String name);
}

class FirebaseAnalyticsBackend implements AnalyticsBackend {
  FirebaseAnalytics? _analytics;

  @override
  bool get supported =>
      AppConfig.firebaseEnabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  @override
  Future<void> initialize() async {
    if (!await FirebaseBootstrap.ensureInitialized()) {
      throw StateError('Firebase is not initialized');
    }
    _analytics = FirebaseAnalytics.instance;
  }

  @override
  Future<void> setCollectionEnabled(bool enabled) async {
    final analytics = _analytics!;
    // Product analytics never opts the user into advertising or remarketing.
    if (!enabled) await analytics.setAnalyticsCollectionEnabled(false);
    await analytics.setConsent(
      analyticsStorageConsentGranted: enabled,
      adStorageConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
      adUserDataConsentGranted: false,
    );
    await analytics.setAnalyticsCollectionEnabled(enabled);
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) =>
      _analytics!.logEvent(name: name, parameters: parameters);

  @override
  Future<void> logScreen(String name) =>
      _analytics!.logScreenView(screenName: name, screenClass: 'Flutter');
}

final appAnalyticsProvider = ChangeNotifierProvider<AppAnalytics>((ref) {
  final analytics = AppAnalytics();
  unawaited(analytics.initialize());
  return analytics;
});

/// A consent-controlled, non-blocking boundary around the native SDK.
/// Only fixed event names and allowlisted aggregate parameters can leave the app.
class AppAnalytics extends ChangeNotifier {
  AppAnalytics({
    AnalyticsBackend? backend,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _backend = backend ?? FirebaseAnalyticsBackend(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const preferenceKey = 'analytics.collection_consent.v1';
  final AnalyticsBackend _backend;
  final Future<SharedPreferences> Function() _preferencesLoader;
  SharedPreferences? _preferences;
  Future<void>? _initialization;
  Future<void> _consentUpdates = Future<void>.value();
  bool? _choice;
  bool _ready = false;
  bool _available = false;
  bool _collectionActive = false;
  bool _consentUpdateFailed = false;
  bool _disposed = false;
  int _consentRevision = 0;

  bool get hasChoice => _choice != null;
  bool get enabled => _choice == true;
  bool get supported => _backend.supported;
  bool get available => _available;
  bool get ready => _ready;
  bool get consentUpdateFailed => _consentUpdateFailed;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    var preferencesLoaded = false;
    try {
      _preferences = await _preferencesLoader();
      _choice = _preferences!.getBool(preferenceKey);
      preferencesLoaded = true;
    } catch (_) {
      _consentUpdateFailed = true;
      debugPrint('[Analytics] Consent preferences unavailable.');
    }

    try {
      if (_backend.supported) {
        await _backend.initialize();
        // Native collection settings can survive app restarts. Even when the
        // app preference cannot be read, explicitly attempt to stop collection.
        final allowCollection = preferencesLoaded && enabled;
        await _backend.setCollectionEnabled(allowCollection);
        _available = true;
        _collectionActive = allowCollection;
      }
    } catch (_) {
      _available = false;
      _collectionActive = false;
      _consentUpdateFailed = true;
      // Initialization can fail after the native SDK has already started.
      try {
        await _backend.setCollectionEnabled(false);
      } catch (_) {
        debugPrint('[Analytics] Collection shutdown unavailable.');
      }
      debugPrint('[Analytics] Initialization unavailable.');
    } finally {
      _ready = true;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await initialize();
    if (_disposed) return;
    final revision = ++_consentRevision;
    _choice = enabled;
    // Stop app events immediately, including while a native consent update waits.
    _collectionActive = false;
    _consentUpdateFailed = false;
    notifyListeners();
    _consentUpdates = _consentUpdates.then((_) async {
      var persisted = false;
      var failed = false;
      try {
        _preferences ??= await _preferencesLoader();
        persisted = await _preferences!.setBool(preferenceKey, enabled);
        if (!persisted) {
          failed = true;
          debugPrint('[Analytics] Consent persistence unavailable.');
        }
      } catch (_) {
        failed = true;
        debugPrint('[Analytics] Consent persistence unavailable.');
      }

      // Revocation must reach the SDK even if local storage is unavailable.
      // Opt-in fails closed unless its choice has been persisted.
      final nativeEnabled = enabled && persisted;
      if (_available) {
        try {
          await _backend.setCollectionEnabled(nativeEnabled);
        } catch (_) {
          failed = true;
          debugPrint('[Analytics] Consent update unavailable.');
          if (nativeEnabled) {
            // A failed enable call can leave its native outcome uncertain.
            try {
              await _backend.setCollectionEnabled(false);
            } catch (_) {
              debugPrint('[Analytics] Collection shutdown unavailable.');
            }
          }
        }
      }

      if (!_disposed && revision == _consentRevision) {
        _consentUpdateFailed = failed;
        _collectionActive = !failed && _available && nativeEnabled;
      }
    });
    await _consentUpdates;
    if (!_disposed) notifyListeners();
  }

  Future<void> logEvent(
    AnalyticsEvent event, {
    Map<String, Object> parameters = const {},
  }) async {
    if (!_canSend) return;
    final name = event.name.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '_${match[0]!.toLowerCase()}',
    );
    try {
      await _backend.logEvent(name, sanitizeParameters(parameters));
    } catch (_) {
      // Never forward raw errors, paths, identifiers or image data.
      debugPrint('[Analytics] Event delivery unavailable.');
    }
  }

  Future<void> logScreen(String routeName) async {
    if (!_canSend) return;
    final name = screenNames[routeName];
    if (name == null) return;
    try {
      await _backend.logScreen(name);
    } catch (_) {
      debugPrint('[Analytics] Screen delivery unavailable.');
    }
  }

  bool get _canSend => !_disposed && _available && enabled && _collectionActive;

  /// 画面名（GA4 の screen_view）。ルートを足したらここにも足す。
  static const screenNames = <String, String>{
    Routes.home: 'home',
    Routes.onboarding: 'onboarding',
    Routes.live: 'live',
    Routes.liveSummary: 'live_summary',
    Routes.camera: 'camera',
    Routes.recognitionLoading: 'recognition_loading',
    Routes.recognition: 'recognition',
    Routes.manualInput: 'manual_input',
    Routes.quiz: 'quiz',
    Routes.result: 'result',
    Routes.candidateDetail: 'candidate_detail',
    Routes.explanation: 'explanation',
    Routes.shareCard: 'share_card',
    Routes.publish: 'publish',
    Routes.today: 'today',
    Routes.myProblems: 'my_problems',
    Routes.history: 'history',
    Routes.paywall: 'paywall',
    Routes.settings: 'settings',
    Routes.winScore: 'win_score',
  };

  static const _axisValues = {'speed', 'points', 'balance'};
  static const _textValues = <String, Set<String>>{
    'purchase_source': {'home', 'settings', 'scorebook'},
    'source': {
      'camera',
      'scorebook',
      'history',
      'manual',
      'photo',
      'screenshot',
      'live',
      'problem',
      'today',
      'web',
      'deeplink',
      'notification',
      // 和了の点数画面の入口（Result の「役と点数を詳しく見る」）。
      'result',
    },
    // なにきるカム
    'gate': {'free', 'free_trial', 'pro'},
    'ended_by': {'user', 'trial_limit', 'battery', 'thermal', 'background'},
    'axis': _axisValues,
    'axis_from': _axisValues,
    'axis_to': _axisValues,
    'screen': {'quiz', 'result', 'candidate_detail', 'explanation', 'live'},
    'state': {'searching', 'stable', 'moving', 'dark', 'far', 'count_mismatch'},
    'correct_axis': {'speed', 'points', 'balance', 'none'},
    'selected_axis': {'speed', 'points', 'balance', 'none'},
    'trigger': {
      'quota',
      'live_trial',
      'live_summary',
      'explanation',
      'two_step',
      'riichi',
      'home',
      'settings',
      'onboarding',
      'candidate',
      'today_limit',
      'history',
      'win_score',
    },
    'plan': {'monthly', 'yearly'},
    'reward': {'quota', 'explanation', 'live_trial'},
    'topic': {'daily', 'weekly', 'answers', 'streak', 'trial', 'live_summary'},
    'edit_action': {'add', 'change', 'delete', 'undo'},
    'share_format': {'feed', 'story'},
    'share_variant': {
      'result',
      'quiz',
      'collection',
      'ranking',
      'app',
      'win',
      'win_quiz',
    },
    // 和了の点数画面の共有（win_score_shared{kind}）。
    'kind': {'win', 'win_quiz'},
    'share_target': {
      'x',
      'instagram',
      'line',
      'facebook',
      'discord',
      'messages',
      'mail',
      'save',
      'copy',
      'other',
    },
    'rank': {'none', 'mangan', 'haneman', 'baiman', 'sanbaiman', 'yakuman'},
    'milestone': {'none', 'first_yaku', 'first_rank', 'personal_best'},
    'tile_from': _tileLabels,
    'tile_to': _tileLabels,
    'recognition_strategy': {'full', 'tiled'},
    'model_version': {'v1', 'v2'},
    'mode': {'three_player', 'four_player'},
    'win_type': {'ron', 'tsumo'},
    'match_length': {'east_only', 'east_south'},
    'hand_type': {'ron', 'tsumo', 'draw'},
    'error_code': {
      'permission_denied',
      'camera_unavailable',
      'camera_start_failed',
      'capture_failed',
      'model_initialization_failed',
      'inference_failed',
      'no_tiles',
      'invalid_hand',
      'no_yaku',
      'unknown',
      'store_unavailable',
      'purchase_failed',
      'purchase_canceled',
      'completion_failed',
    },
  };
  static const _tileLabels = {
    '1m',
    '2m',
    '3m',
    '4m',
    '5m',
    '6m',
    '7m',
    '8m',
    '9m',
    '0m',
    '1p',
    '2p',
    '3p',
    '4p',
    '5p',
    '6p',
    '7p',
    '8p',
    '9p',
    '0p',
    '1s',
    '2s',
    '3s',
    '4s',
    '5s',
    '6s',
    '7s',
    '8s',
    '9s',
    '0s',
    '1z',
    '2z',
    '3z',
    '4z',
    '5z',
    '6z',
    '7z',
    'none',
  };
  static const _integerMaximums = <String, int>{
    'valid_hand': 1,
    'low_confidence_tiles': 60,
    'avg_confidence_pct': 100,
    'with_photo': 1,
    'tile_count': 60,
    'duration_ms': 3600000,
    'han': 100,
    'fu': 200,
    'hand_count': 1000,
    // なにきるカム
    'hand_size': 14,
    'stable_ms': 60000,
    'duration_s': 86400,
    // ライブ体験の延長で足した秒数（1 回で最大 180）。
    'bonus_s': 180,
    'ratio_pct': 100,
    'candidate_rank': 34,
    'followed': 1,
    'correct': 1,
    'shanten': 8,
    'ukeire': 136,
    'count': 1000,
  };

  @visibleForTesting
  static Map<String, Object> sanitizeParameters(Map<String, Object> input) {
    final output = <String, Object>{};
    for (final entry in input.entries) {
      final allowed = _textValues[entry.key];
      if (allowed != null &&
          entry.value is String &&
          allowed.contains(entry.value)) {
        output[entry.key] = entry.value;
      }
      final maximum = _integerMaximums[entry.key];
      if (maximum != null && entry.value is int) {
        output[entry.key] = (entry.value as int).clamp(0, maximum);
      }
    }
    return output;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
