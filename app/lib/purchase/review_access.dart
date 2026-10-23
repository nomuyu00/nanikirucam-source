import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/clock.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 購入とは別の、明示的に入力する審査用権利。サーバー・分析への送信はしない。
class ReviewAccessConfig {
  ReviewAccessConfig({
    required this.codeSha256,
    required String expiresAt,
    required this.android,
  }) : expiresAt = _parseExpiry(expiresAt);

  static DateTime? _parseExpiry(String value) {
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?Z$',
    ).hasMatch(value)) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    // DateTime.parse は「2月30日」などを翌月へ繰り上げるので、それも拒否する。
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 19) != value.substring(0, 19)) {
      return null;
    }
    return parsed.toUtc();
  }

  final String codeSha256;
  final DateTime? expiresAt;
  final bool android;

  bool availableAt(DateTime now) =>
      android &&
      RegExp(r'^[0-9a-f]{64}$').hasMatch(codeSha256) &&
      expiresAt != null &&
      expiresAt!.isAfter(now);

  String get fingerprint => '$codeSha256/${expiresAt?.toIso8601String()}';
}

final reviewAccessConfigProvider = Provider<ReviewAccessConfig>(
  (ref) => ReviewAccessConfig(
    codeSha256: AppConfig.reviewAccessCodeSha256,
    expiresAt: AppConfig.reviewAccessExpiresAt,
    android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
  ),
);

enum ReviewAccessResult { activated, invalid, unavailable, failed, busy }

/// 保存するのは設定の照合値と有効化日時だけ。平文コードは保持しない。
/// 期限は端末時刻で判定する。サーバー認証ではなく、審査担当への限定配布用。
class ReviewAccessService extends ChangeNotifier with WidgetsBindingObserver {
  ReviewAccessService({
    required this.config,
    required this.now,
    required this.preferences,
  }) {
    if (available) {
      loading = true;
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      ready = _load();
    } else {
      ready = Future.value();
    }
  }

  static const preferenceKey = 'review_access_v1';
  final ReviewAccessConfig config;
  final DateTime Function() now;
  final Future<SharedPreferences> Function() preferences;
  late final Future<void> ready;
  bool loading = false;
  bool busy = false;
  bool _granted = false;
  bool _disposed = false;
  bool _observing = false;
  DateTime? _activatedAt;
  Timer? _expiryTimer;
  Timer? _clockTimer;

  bool get available => config.availableAt(now());
  bool get active =>
      _granted &&
      available &&
      _activatedAt != null &&
      !now().isBefore(_activatedAt!);
  DateTime? get until => active ? config.expiresAt : null;

  Future<void> _load() async {
    try {
      final prefs = await preferences();
      if (_disposed) return;
      final saved = prefs.getString(preferenceKey);
      if (saved != null) {
        final json = jsonDecode(saved) as Map<String, dynamic>;
        _activatedAt = DateTime.tryParse(json['activatedAt'] as String);
        _granted = json['config'] == config.fingerprint;
        if (!active) {
          _granted = false;
          await prefs.remove(preferenceKey);
        }
      }
    } catch (_) {
      _granted = false;
    } finally {
      if (!_disposed) {
        loading = false;
        _schedule();
        notifyListeners();
      }
    }
  }

  Future<ReviewAccessResult> activate(String input) async {
    if (busy || loading) return ReviewAccessResult.busy;
    if (!available) return ReviewAccessResult.unavailable;
    if (input.length > 256 || input.trim().isEmpty) {
      return ReviewAccessResult.invalid;
    }
    final digest = sha256.convert(utf8.encode(input.trim())).toString();
    if (digest != config.codeSha256) return ReviewAccessResult.invalid;
    busy = true;
    notifyListeners();
    try {
      final prefs = await preferences();
      if (_disposed || !available) return ReviewAccessResult.unavailable;
      final activated = now().toUtc();
      final ok = await prefs.setString(
        preferenceKey,
        jsonEncode({
          'config': config.fingerprint,
          'activatedAt': activated.toIso8601String(),
        }),
      );
      // 保存中の期限切れ・削除・破棄でも権利を作らない。
      if (!ok || _disposed || !available) {
        await prefs.remove(preferenceKey);
        return ReviewAccessResult.failed;
      }
      _activatedAt = activated;
      _granted = true;
      _schedule();
      return ReviewAccessResult.activated;
    } catch (_) {
      return ReviewAccessResult.failed;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> disable() async {
    if (busy || loading) return false;
    busy = true;
    _granted = false;
    notifyListeners();
    try {
      return await (await preferences()).remove(preferenceKey);
    } catch (_) {
      return false;
    } finally {
      busy = false;
      _schedule();
      if (!_disposed) notifyListeners();
    }
  }

  void _schedule() {
    _expiryTimer?.cancel();
    _clockTimer?.cancel();
    if (_disposed || !available) return;
    var wait = config.expiresAt!.difference(now());
    if (wait > const Duration(days: 1)) wait = const Duration(days: 1);
    _expiryTimer = Timer(wait, refresh);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
  }

  /// サスペンド復帰・端末時刻変更にも追従する。期限後の保存権利は消す。
  void refresh() {
    if (_disposed) return;
    if (_granted && !active) {
      _granted = false;
      unawaited(_removeExpired());
    }
    _schedule();
    notifyListeners();
  }

  Future<void> _removeExpired() async {
    try {
      await (await preferences()).remove(preferenceKey);
    } catch (_) {
      // 読み込み時も期限・設定一致を確認するため、削除失敗で権利は戻らない。
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _expiryTimer?.cancel();
    _clockTimer?.cancel();
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

final reviewAccessProvider = ChangeNotifierProvider<ReviewAccessService>((ref) {
  return ReviewAccessService(
    config: ref.watch(reviewAccessConfigProvider),
    now: ref.watch(clockProvider),
    preferences: () => ref.read(sharedPreferencesProvider.future),
  );
});
