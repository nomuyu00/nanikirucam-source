import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';
import 'package:nanikiru_cam/notifications/notification_routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// FCM の SDK 側（`firebase_messaging`）。テストでは差し替える。
abstract class MessagingBackend {
  /// Firebase が使えるか。無効・初期化失敗なら false で、以降は何もしない。
  Future<bool> isAvailable();

  Future<NotificationPermission> permission();

  /// OS の許可ダイアログを出す。
  Future<NotificationPermission> requestPermission();

  /// 端末のトークン。まだ取れない（iOS の APNs 待ちなど）ときは null。
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  Future<void> subscribe(String topic);

  Future<void> unsubscribe(String topic);

  /// 通知をタップしてアプリが前面に戻ったときの `data`。
  Stream<Map<String, Object?>> get opened;

  /// 通知のタップでアプリが起動したときの `data`。
  Future<Map<String, Object?>?> initialMessage();
}

class FirebaseMessagingBackend implements MessagingBackend {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> isAvailable() => FirebaseBootstrap.ensureInitialized();

  NotificationPermission _permissionOf(AuthorizationStatus status) =>
      switch (status) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => NotificationPermission.granted,
        AuthorizationStatus.denied => NotificationPermission.denied,
        AuthorizationStatus.notDetermined =>
          NotificationPermission.notDetermined,
      };

  @override
  Future<NotificationPermission> permission() async => _permissionOf(
    (await _messaging.getNotificationSettings()).authorizationStatus,
  );

  @override
  Future<NotificationPermission> requestPermission() async => _permissionOf(
    (await _messaging.requestPermission()).authorizationStatus,
  );

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken();
    } catch (error) {
      // iOS で APNs のトークンがまだ無いときなど。次の同期で取り直す。
      debugPrint('[FCM] getToken failed: $error');
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes async* {
    if (!await isAvailable()) return;
    yield* _messaging.onTokenRefresh;
  }

  @override
  Future<void> subscribe(String topic) => _messaging.subscribeToTopic(topic);

  @override
  Future<void> unsubscribe(String topic) =>
      _messaging.unsubscribeFromTopic(topic);

  @override
  Stream<Map<String, Object?>> get opened async* {
    if (!await isAvailable()) return;
    yield* FirebaseMessaging.onMessageOpenedApp.map(
      (message) => Map<String, Object?>.from(message.data),
    );
  }

  @override
  Future<Map<String, Object?>?> initialMessage() async {
    if (!await isAvailable()) return null;
    final message = await _messaging.getInitialMessage();
    return message == null ? null : Map<String, Object?>.from(message.data);
  }
}

/// `users/{uid}` の端末設定（Firestore ルールで本人が書ける `fcmTokens` と `notify`）。
abstract class DeviceProfileWriter {
  Future<void> write({
    required String uid,
    String? fcmToken,
    Map<String, bool>? notify,
  });
}

class FirestoreDeviceProfileWriter implements DeviceProfileWriter {
  /// `fcmTokens` は 10 個まで（ルール）。
  static const maxTokens = 10;

  @override
  Future<void> write({
    required String uid,
    String? fcmToken,
    Map<String, bool>? notify,
  }) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(uid);
    final data = <String, Object?>{};
    if (fcmToken != null) {
      // 同じトークンは入れ直し、10 個を超えたら古いものから落とす。
      final snapshot = await ref.get();
      final stored = snapshot.data()?['fcmTokens'];
      final tokens = <String>[
        if (stored is List) ...stored.whereType<String>(),
      ]..remove(fcmToken);
      tokens.add(fcmToken);
      data['fcmTokens'] = tokens.length > maxTokens
          ? tokens.sublist(tokens.length - maxTokens)
          : tokens;
    }
    if (notify != null) data['notify'] = notify;
    if (data.isEmpty) return;
    // users/{uid} の作成は ensureUser だけ（ルール）。まだ無ければ失敗し、次の同期で再試行する。
    await ref.update(data);
  }
}

/// FCM まわりの処理（設計書 12 章）: トークンの保存、トピック `daily` / `weekly` の購読、
/// 通知タップの受け取り。Firebase が無効なら何もしない。
class FcmService {
  FcmService({
    required this._backend,
    required this._writer,
    required this._preferences,
  });

  final MessagingBackend _backend;
  final DeviceProfileWriter _writer;
  final Future<SharedPreferences> Function() _preferences;

  /// 購読中のトピック（端末内）。SDK に問い合わせる手段がないため控えておく。
  static const topicsKey = 'fcm_topics_v1';

  String? _lastPushed;

  Future<bool> get available => _backend.isAvailable();

  Future<NotificationPermission> permission() async {
    if (!await available) return NotificationPermission.notDetermined;
    try {
      return await _backend.permission();
    } catch (error) {
      debugPrint('[FCM] permission failed: $error');
      return NotificationPermission.notDetermined;
    }
  }

  Future<NotificationPermission> requestPermission() async {
    if (!await available) return NotificationPermission.notDetermined;
    try {
      return await _backend.requestPermission();
    } catch (error) {
      debugPrint('[FCM] requestPermission failed: $error');
      return NotificationPermission.denied;
    }
  }

  /// 通知のタップ（前面に戻ったとき）。
  Stream<NotificationTap> get taps => _backend.opened
      .map(notificationTapFromRemote)
      .where((tap) => tap != null)
      .cast<NotificationTap>();

  /// 通知のタップで起動したとき。
  Future<NotificationTap?> initialTap() async {
    try {
      final data = await _backend.initialMessage();
      return data == null ? null : notificationTapFromRemote(data);
    } catch (error) {
      debugPrint('[FCM] initialMessage failed: $error');
      return null;
    }
  }

  Stream<String> get tokenRefreshes => _backend.tokenRefreshes;

  /// 設定とアカウントに合わせて、トピックの購読とトークン・通知設定の保存を揃える。
  /// 通知が許可されていなければ何もしない。
  Future<void> sync({String? uid, required AppSettings settings}) async {
    if (!await available) return;
    try {
      if (await _backend.permission() != NotificationPermission.granted) return;
      await _syncTopics(settings);
      if (uid != null) await _syncProfile(uid, settings);
    } catch (error) {
      debugPrint('[FCM] sync failed: $error');
    }
  }

  /// トークンの更新（再インストールなど）に備えて、次の同期で必ず書き直す。
  void forgetPushedState() => _lastPushed = null;

  Future<void> _syncTopics(AppSettings settings) async {
    final prefs = await _preferences();
    final applied = {...?prefs.getStringList(topicsKey)};
    final desired = <String>{
      if (settings.notifyDaily) 'daily',
      if (settings.notifyWeekly) 'weekly',
    };
    for (final topic in desired.difference(applied)) {
      try {
        await _backend.subscribe(topic);
        applied.add(topic);
      } catch (error) {
        debugPrint('[FCM] subscribe($topic) failed: $error');
      }
    }
    for (final topic in applied.difference(desired).toList()) {
      try {
        await _backend.unsubscribe(topic);
        applied.remove(topic);
      } catch (error) {
        debugPrint('[FCM] unsubscribe($topic) failed: $error');
      }
    }
    await prefs.setStringList(topicsKey, applied.toList()..sort());
  }

  Future<void> _syncProfile(String uid, AppSettings settings) async {
    final token = await _backend.token();
    if (token == null) return;
    final notify = <String, bool>{
      'daily': settings.notifyDaily,
      'weekly': settings.notifyWeekly,
      'milestone': settings.notifyAnswers,
    };
    final key = '$uid|$token|${notify.entries.map((e) => '${e.key}=${e.value}').join(',')}';
    if (key == _lastPushed) return;
    await _writer.write(uid: uid, fcmToken: token, notify: notify);
    _lastPushed = key;
  }

  /// データ削除のあと、購読の控えを消す。
  Future<void> clearLocal() async {
    _lastPushed = null;
    try {
      final prefs = await _preferences();
      await prefs.remove(topicsKey);
    } catch (_) {}
  }
}
