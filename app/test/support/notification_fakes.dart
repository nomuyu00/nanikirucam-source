import 'package:nanikiru_cam/notifications/fcm_service.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';

/// 予約された 1 件のローカル通知。
class ScheduledNotification {
  const ScheduledNotification(
    this.id,
    this.at,
    this.title,
    this.body,
    this.payload,
  );
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final String payload;
}

/// ローカル通知の偽物（同じ id の予約は置き換わる）。
class FakeLocalNotifications implements LocalNotificationBackend {
  NotificationPermission current = NotificationPermission.granted;
  NotificationPermission onRequest = NotificationPermission.granted;
  int requests = 0;
  String? launch;
  void Function(String? payload)? onTap;
  final Map<int, ScheduledNotification> scheduled = {};
  final List<int> cancelled = [];
  int scheduleCalls = 0;

  @override
  Future<void> initialize({
    required void Function(String? payload) onTap,
  }) async {
    this.onTap = onTap;
  }

  @override
  Future<NotificationPermission> permission() async => current;

  @override
  Future<NotificationPermission> requestPermission() async {
    requests++;
    current = onRequest;
    return onRequest;
  }

  @override
  Future<void> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String payload,
    required String channelName,
    required String channelDescription,
  }) async {
    scheduleCalls++;
    scheduled[id] = ScheduledNotification(id, at, title, body, payload);
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }

  @override
  Future<String?> launchPayload() async => launch;
}

/// FCM を使わない（Firebase 無効のビルド）。
class UnavailableMessaging implements MessagingBackend {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<NotificationPermission> permission() async =>
      NotificationPermission.notDetermined;
  @override
  Future<NotificationPermission> requestPermission() async =>
      NotificationPermission.notDetermined;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get tokenRefreshes => const Stream.empty();
  @override
  Future<void> subscribe(String topic) async {}
  @override
  Future<void> unsubscribe(String topic) async {}
  @override
  Stream<Map<String, Object?>> get opened => const Stream.empty();
  @override
  Future<Map<String, Object?>?> initialMessage() async => null;
}
