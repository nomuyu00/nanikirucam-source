import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/notifications/local_scheduler.dart';

/// 通知をタップしたときの行き先。[topic] は計測の `notification_opened{topic}`
/// （`daily` / `weekly` / `answers` / `streak` / `trial`）。
class NotificationTap {
  const NotificationTap({
    required this.topic,
    required this.route,
    this.arguments,
    this.liveSessionStartedAt,
  });

  final String topic;
  final String route;

  /// 遷移先に渡す引数（[liveSessionStartedAt] から作ったものなど）。
  final Object? arguments;

  /// ライブの対局サマリーの通知で、開くセッションの開始時刻。保存済みのセッションを探して
  /// [Routes.liveSummary] の引数にする。見つからなければ Live の入口へ行く。
  final DateTime? liveSessionStartedAt;

  @override
  bool operator ==(Object other) =>
      other is NotificationTap && other.topic == topic && other.route == route;

  @override
  int get hashCode => Object.hash(topic, route);

  @override
  String toString() => 'NotificationTap($topic -> $route)';
}

/// サーバーからの通知（FCM の `data`。`app/functions/src/core/notify.ts`）。
NotificationTap? notificationTapFromRemote(Map<String, Object?> data) {
  switch (data['type']) {
    case 'daily':
      return const NotificationTap(topic: 'daily', route: Routes.today);
    case 'weekly':
      // 週間の難問は「今日の問題」の画面から探せる。
      return const NotificationTap(topic: 'weekly', route: Routes.today);
    case 'answer_milestone':
      return const NotificationTap(topic: 'answers', route: Routes.myProblems);
  }
  return null;
}

/// 端末で予約した通知（[LocalScheduler] のペイロード）。
NotificationTap? notificationTapFromLocal(String? payload) {
  final liveStartedAt = LocalScheduler.liveSummaryStartedAt(payload);
  if (liveStartedAt != null) {
    return NotificationTap(
      topic: 'live_summary',
      route: Routes.liveSummary,
      liveSessionStartedAt: liveStartedAt,
    );
  }
  switch (payload) {
    case LocalScheduler.streakPayload:
      return const NotificationTap(topic: 'streak', route: Routes.today);
    case LocalScheduler.dailyPayload:
      return const NotificationTap(topic: 'daily', route: Routes.today);
    case LocalScheduler.trialPayload:
      return const NotificationTap(topic: 'trial', route: Routes.settings);
  }
  return null;
}
