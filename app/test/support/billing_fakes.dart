import 'dart:async';

import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:nanikiru_cam/purchase/subscription_backend.dart';

/// 課金・広告・通知・紹介のテストで使う偽物。

/// RevenueCat の代わり。
class FakeSubscriptionBackend implements SubscriptionBackend {
  FakeSubscriptionBackend({
    this.entitlement = StoreEntitlement.none,
    List<StorePlan>? plans,
  }) : plans = plans ?? defaultPlans;

  static const monthly = StorePlan(
    kind: PlanKind.monthly,
    productId: monthlyProductId,
    priceString: '¥480',
    trialDays: 7,
  );
  static const yearly = StorePlan(
    kind: PlanKind.yearly,
    productId: yearlyProductId,
    priceString: '¥3,200',
    pricePerMonthString: '¥267',
  );
  static const defaultPlans = [yearly, monthly];

  final StreamController<StoreEntitlement> controller =
      StreamController<StoreEntitlement>.broadcast();

  StoreEntitlement entitlement;
  List<StorePlan> plans;

  /// 次の呼び出しで投げる例外（投げたら null に戻る）。
  Object? configureError;
  Object? fetchError;
  Object? purchaseError;
  Object? plansError;

  /// restore の呼び出しごとに投げる例外（先頭から使う）。空なら成功。
  final List<Object> restoreErrors = [];

  /// purchase が成功したときに返す権利。
  StoreEntitlement? purchaseResult;

  /// restore が成功したときに返す権利。
  StoreEntitlement? restoreResult;

  Completer<void>? purchaseGate;

  int configureCalls = 0;
  String? configuredApiKey;
  String? configuredUser;
  final List<String> loggedIn = [];
  int fetchCalls = 0;
  int plansCalls = 0;
  int restoreCalls = 0;
  final List<StorePlan> purchased = [];
  bool disposed = false;

  @override
  Stream<StoreEntitlement> get updates => controller.stream;

  @override
  Future<void> configure({required String apiKey, String? appUserId}) async {
    configureCalls++;
    final error = configureError;
    if (error != null) {
      configureError = null;
      throw error;
    }
    configuredApiKey = apiKey;
    configuredUser = appUserId;
  }

  @override
  Future<StoreEntitlement> logIn(String appUserId) async {
    loggedIn.add(appUserId);
    return entitlement;
  }

  @override
  Future<StoreEntitlement> fetchEntitlement() async {
    fetchCalls++;
    final error = fetchError;
    if (error != null) {
      fetchError = null;
      throw error;
    }
    return entitlement;
  }

  @override
  Future<List<StorePlan>> fetchPlans() async {
    plansCalls++;
    final error = plansError;
    if (error != null) {
      plansError = null;
      throw error;
    }
    return plans;
  }

  @override
  Future<StoreEntitlement> purchase(StorePlan plan) async {
    purchased.add(plan);
    final gate = purchaseGate;
    if (gate != null) await gate.future;
    final error = purchaseError;
    if (error != null) {
      purchaseError = null;
      throw error;
    }
    entitlement =
        purchaseResult ??
        StoreEntitlement(
          pro: true,
          until: DateTime.utc(2026, 11, 1),
          trial: plan.hasTrial,
        );
    return entitlement;
  }

  @override
  Future<StoreEntitlement> restore() async {
    restoreCalls++;
    if (restoreErrors.isNotEmpty) throw restoreErrors.removeAt(0);
    entitlement = restoreResult ?? entitlement;
    return entitlement;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await controller.close();
  }
}

/// 計測イベントの記録。
class RecordedEvent {
  const RecordedEvent(this.event, this.parameters);
  final AnalyticsEvent event;
  final Map<String, Object> parameters;

  @override
  String toString() => '${event.name}$parameters';
}

class RecordingAnalytics {
  final List<RecordedEvent> events = [];

  void call(AnalyticsEvent event, [Map<String, Object> parameters = const {}]) {
    events.add(RecordedEvent(event, parameters));
  }

  List<AnalyticsEvent> get names => [for (final e in events) e.event];

  RecordedEvent? last(AnalyticsEvent event) {
    for (final e in events.reversed) {
      if (e.event == event) return e;
    }
    return null;
  }

  int count(AnalyticsEvent event) => events.where((e) => e.event == event).length;
}

/// テストで動かせる時計。
class FakeClock {
  FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
}
