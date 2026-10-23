import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nanikiru_cam/purchase/store_entitlement.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat の権利 ID（`app/functions/API.md` の `revenuecatWebhook` と同じ）。
const String proEntitlementId = 'pro';

/// 商品（設計書 9 章）。
const String monthlyProductId = 'nanikiru_pro_monthly';
const String yearlyProductId = 'nanikiru_pro_yearly';

/// Offering の ID。
const String defaultOfferingId = 'default';

enum PlanKind { monthly, yearly }

/// Paywall に出す 1 つのプラン。RevenueCat の `Package` を包む。
class StorePlan extends Equatable {
  const StorePlan({
    required this.kind,
    required this.productId,
    required this.priceString,
    this.trialDays,
    this.pricePerMonthString,
    this.native,
  });

  final PlanKind kind;
  final String productId;

  /// ストアが返す表示用の価格（通貨・地域込み。例: ¥480）。
  final String priceString;

  /// 無料トライアルの日数（なければ null）。
  final int? trialDays;

  /// 年額の月あたり表示（取れたときだけ）。
  final String? pricePerMonthString;

  /// バックエンドが購入に使う実体（RevenueCat の `Package`）。
  final Object? native;

  bool get hasTrial => trialDays != null && trialDays! > 0;

  @override
  List<Object?> get props => [
    kind,
    productId,
    priceString,
    trialDays,
    pricePerMonthString,
  ];
}

/// ユーザーが購入をキャンセルした。
class PurchaseCancelledException implements Exception {
  const PurchaseCancelledException();
  @override
  String toString() => 'PurchaseCancelledException';
}

/// 決済が保留中（承認待ちなど）。権利はまだ付与されない。
class PurchasePendingException implements Exception {
  const PurchasePendingException();
  @override
  String toString() => 'PurchasePendingException';
}

/// ストアまたは RevenueCat のエラー。[retryable] は通信など再試行で直る可能性があるもの。
class StoreException implements Exception {
  const StoreException(this.message, {this.retryable = false});
  final String message;
  final bool retryable;
  @override
  String toString() => 'StoreException($message)';
}

/// RevenueCat との境界。Pro の判定とテストのため、アプリは [SubscriptionBackend] だけを使う。
abstract class SubscriptionBackend {
  Future<void> configure({required String apiKey, String? appUserId});

  /// 匿名で始めたあと uid が決まったときに紐づける。
  Future<StoreEntitlement> logIn(String appUserId);

  Future<StoreEntitlement> fetchEntitlement();

  /// 権利が変わるたびに流れる（更新・期限切れ・別端末での購入）。
  Stream<StoreEntitlement> get updates;

  /// Offering `default` の月額・年額。
  Future<List<StorePlan>> fetchPlans();

  /// 購入。キャンセルは [PurchaseCancelledException]。
  Future<StoreEntitlement> purchase(StorePlan plan);

  Future<StoreEntitlement> restore();

  Future<void> dispose();
}

/// `CustomerInfo` から Pro の状態を取り出す。
StoreEntitlement entitlementFromCustomerInfo(CustomerInfo info) {
  final entitlement = info.entitlements.active[proEntitlementId];
  if (entitlement == null || !entitlement.isActive) {
    return StoreEntitlement.none;
  }
  return StoreEntitlement(
    pro: true,
    until: entitlement.expirationDate == null
        ? null
        : DateTime.tryParse(entitlement.expirationDate!),
    trial: entitlement.periodType == PeriodType.trial,
    willRenew: entitlement.willRenew,
  );
}

/// プランの種類を決める（パッケージ種別、なければ商品 ID）。
PlanKind? planKindOf(Package package) {
  switch (package.packageType) {
    case PackageType.monthly:
      return PlanKind.monthly;
    case PackageType.annual:
      return PlanKind.yearly;
    default:
      break;
  }
  final id = package.storeProduct.identifier;
  if (id.startsWith(monthlyProductId)) return PlanKind.monthly;
  if (id.startsWith(yearlyProductId)) return PlanKind.yearly;
  return null;
}

/// 無料トライアルの日数。ストアが返す無料期間（Google の `freePhase`、Apple の 0 円の
/// 導入価格）から求める。
int? trialDaysOf(StoreProduct product) {
  int? fromPeriod(PeriodUnit unit, int value) => switch (unit) {
    PeriodUnit.day => value,
    PeriodUnit.week => value * 7,
    PeriodUnit.month => value * 30,
    PeriodUnit.year => value * 365,
    _ => null,
  };
  final free = product.defaultOption?.freePhase?.billingPeriod;
  if (free != null) return fromPeriod(free.unit, free.value);
  final intro = product.introductoryPrice;
  if (intro != null && intro.price == 0) {
    final days = fromPeriod(intro.periodUnit, intro.periodNumberOfUnits);
    return days == null ? null : days * (intro.cycles < 1 ? 1 : intro.cycles);
  }
  return null;
}

/// 本物の RevenueCat（`purchases_flutter`）。
class RevenueCatBackend implements SubscriptionBackend {
  final StreamController<StoreEntitlement> _updates =
      StreamController<StoreEntitlement>.broadcast();
  bool _listening = false;
  void Function(CustomerInfo)? _listener;

  @override
  Stream<StoreEntitlement> get updates => _updates.stream;

  @override
  Future<void> configure({required String apiKey, String? appUserId}) async {
    // アプリの状態を作り直した（データ削除のあとなど）ときは、同じプロセスで 2 度目の
    // configure になる。設定済みなら新しい uid でログインし直すだけにする。
    if (await Purchases.isConfigured) {
      if (appUserId != null) await Purchases.logIn(appUserId);
    } else {
      final configuration = PurchasesConfiguration(apiKey)
        ..appUserID = appUserId;
      await Purchases.configure(configuration);
    }
    if (!_listening) {
      _listening = true;
      void listener(CustomerInfo info) {
        if (!_updates.isClosed) _updates.add(entitlementFromCustomerInfo(info));
      }

      _listener = listener;
      Purchases.addCustomerInfoUpdateListener(listener);
    }
  }

  @override
  Future<StoreEntitlement> logIn(String appUserId) async {
    final result = await _guard(() => Purchases.logIn(appUserId));
    return entitlementFromCustomerInfo(result.customerInfo);
  }

  @override
  Future<StoreEntitlement> fetchEntitlement() async {
    final info = await _guard(Purchases.getCustomerInfo);
    return entitlementFromCustomerInfo(info);
  }

  @override
  Future<List<StorePlan>> fetchPlans() async {
    final offerings = await _guard(Purchases.getOfferings);
    final offering =
        offerings.getOffering(defaultOfferingId) ?? offerings.current;
    if (offering == null) return const [];
    final plans = <PlanKind, StorePlan>{};
    for (final package in offering.availablePackages) {
      final kind = planKindOf(package);
      if (kind == null || plans.containsKey(kind)) continue;
      final product = package.storeProduct;
      plans[kind] = StorePlan(
        kind: kind,
        productId: product.identifier,
        priceString: product.priceString,
        trialDays: trialDaysOf(product),
        pricePerMonthString: kind == PlanKind.yearly
            ? product.pricePerMonthString
            : null,
        native: package,
      );
    }
    return [
      if (plans[PlanKind.yearly] != null) plans[PlanKind.yearly]!,
      if (plans[PlanKind.monthly] != null) plans[PlanKind.monthly]!,
    ];
  }

  @override
  Future<StoreEntitlement> purchase(StorePlan plan) async {
    final package = plan.native;
    if (package is! Package) {
      throw const StoreException('plan has no store package');
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      return entitlementFromCustomerInfo(result.customerInfo);
    } on PlatformException catch (error) {
      switch (PurchasesErrorHelper.getErrorCode(error)) {
        case PurchasesErrorCode.purchaseCancelledError:
          throw const PurchaseCancelledException();
        case PurchasesErrorCode.paymentPendingError:
          throw const PurchasePendingException();
        default:
          throw _storeException(error);
      }
    }
  }

  @override
  Future<StoreEntitlement> restore() async {
    final info = await _guard(Purchases.restorePurchases);
    return entitlementFromCustomerInfo(info);
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (error) {
      throw _storeException(error);
    }
  }

  StoreException _storeException(PlatformException error) {
    var retryable = false;
    try {
      final code = PurchasesErrorHelper.getErrorCode(error);
      retryable =
          code == PurchasesErrorCode.networkError ||
          code == PurchasesErrorCode.offlineConnectionError ||
          code == PurchasesErrorCode.storeProblemError;
    } catch (_) {
      // 数値でないコード。再試行しない。
    }
    debugPrint('[RevenueCat] ${error.code} ${error.message}');
    return StoreException(error.message ?? error.code, retryable: retryable);
  }

  @override
  Future<void> dispose() async {
    final listener = _listener;
    if (listener != null) Purchases.removeCustomerInfoUpdateListener(listener);
    _listener = null;
    await _updates.close();
  }
}
