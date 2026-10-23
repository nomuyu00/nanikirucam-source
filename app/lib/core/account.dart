import 'dart:async';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';

/// 匿名ユーザーとサーバー上のプロフィール（設計書 5.2 `users/{uid}`、`app/functions/API.md` の
/// `ensureUser`）。
///
/// Firebase が有効なら起動後に匿名サインイン → `ensureUser` → `users/{uid}` の購読を行う。
/// Firebase が無効（`AppConfig.firebaseEnabled` が false）やオフラインなら uid は null のまま
/// で、アプリはオフラインで動き続ける（設計書 1 章）。名前と型は変えない。
class UserProfile extends Equatable {
  const UserProfile({
    required this.uid,
    this.nickname,
    this.referralCode,
    this.referralProUntil,
  });

  /// `users/{uid}` のドキュメント（[normalizeFirestoreValue] を通した形）から作る。
  factory UserProfile.fromData(String uid, Map<String, Object?> data) {
    final pro = data['pro'];
    final referral = pro is Map ? pro['referral'] : null;
    return UserProfile(
      uid: uid,
      nickname: _nonEmptyString(data['nickname']),
      referralCode: _nonEmptyString(data['referralCode']),
      referralProUntil: parseDateTime(
        referral is Map ? referral['until'] : null,
      ),
    );
  }

  /// `ensureUser` のレスポンスから作る（購読の最初の値になる）。
  ///
  /// レスポンスの `pro.until` は紹介由来（`pro.source == "referral"`）のときだけ
  /// [referralProUntil] にする（RevenueCat 由来の期限と混ぜない）。
  factory UserProfile.fromEnsureUser(
    String uid,
    Map<String, Object?> response,
  ) {
    final pro = response['pro'];
    DateTime? referralUntil;
    if (pro is Map && pro['source'] == 'referral') {
      referralUntil = parseDateTime(pro['until']);
    }
    return UserProfile(
      uid: uid,
      nickname: _nonEmptyString(response['nickname']),
      referralCode: _nonEmptyString(response['referralCode']),
      referralProUntil: referralUntil,
    );
  }

  final String uid;

  /// 出題者名（サーバーで検査済みの値）。
  final String? nickname;

  /// 自分の紹介コード。
  final String? referralCode;

  /// 紹介特典の Pro の期限（`users/{uid}.pro.referral.until`）。課金担当が
  /// RevenueCat の権利と OR を取って [entitlementsProvider] に反映する。
  final DateTime? referralProUntil;

  @override
  List<Object?> get props => [uid, nickname, referralCode, referralProUntil];
}

String? _nonEmptyString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Firestore の Timestamp・DateTime・ISO 8601 文字列・エポックミリ秒を [DateTime] にする。
DateTime? parseDateTime(Object? value) {
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) return DateTime.tryParse(value);
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

/// Firestore のドキュメントや callable の戻り値を、`Map<String, Object?>` / `List` /
/// 基本型 / [DateTime] だけの形にそろえる（Timestamp は [DateTime] にする）。
Object? normalizeFirestoreValue(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key.toString(): normalizeFirestoreValue(entry.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) normalizeFirestoreValue(item)];
  }
  return value;
}

/// [normalizeFirestoreValue] の Map 版。Map でなければ空の Map。
Map<String, Object?> normalizeFirestoreMap(Object? value) {
  final normalized = normalizeFirestoreValue(value);
  return normalized is Map<String, Object?> ? normalized : <String, Object?>{};
}

// --- バックエンド（callable） ------------------------------------------------

/// バックエンド（callable・Firestore・HTTPS）の失敗。`FirebaseFunctionsException` /
/// `FirebaseException` / HTTP エラーをこの 1 種類にそろえる（`app/functions/API.md` 1 章）。
class BackendException implements Exception {
  const BackendException({
    required this.code,
    this.reason,
    this.field,
    this.message,
  });

  /// `invalid-argument` `resource-exhausted` `unavailable` `unauthenticated` `not-found` など
  /// （Firebase の code）。
  final String code;

  /// `details.reason`（`daily_limit` `ng_word` `invalid_nickname` …）。
  final String? reason;

  /// `details.field`。
  final String? field;

  final String? message;

  /// 通信できなかった・一時的に使えない失敗か。公開をキューに入れて再試行してよい。
  bool get isRetryable => switch (code) {
    'unavailable' ||
    'deadline-exceeded' ||
    'unauthenticated' ||
    'internal' ||
    'unknown' ||
    'cancelled' ||
    'aborted' => true,
    _ => false,
  };

  @override
  String toString() =>
      'BackendException($code${reason == null ? '' : ', $reason'}'
      '${field == null ? '' : ', $field'}${message == null ? '' : ': $message'})';
}

/// callable `asia-northeast1` の窓口（`ensureUser` 以外はサインイン済みを保証してから呼ぶ）。
abstract class BackendClient {
  /// false なら何も呼べない（Firebase 無効）。
  bool get available;

  /// callable [name] を呼ぶ。失敗は [BackendException]。
  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]);
}

/// Firebase 無効のときの [BackendClient]。
class UnavailableBackendClient implements BackendClient {
  const UnavailableBackendClient();

  @override
  bool get available => false;

  @override
  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) => Future.error(
    const BackendException(code: 'unavailable', reason: 'firebase_disabled'),
  );
}

const backendRegion = 'asia-northeast1';

BackendException _fromFunctionsException(FirebaseFunctionsException error) {
  final details = error.details;
  String? reason;
  String? field;
  if (details is Map) {
    final r = details['reason'];
    final f = details['field'];
    reason = r is String ? r : null;
    field = f is String ? f : null;
  }
  return BackendException(
    code: error.code,
    reason: reason,
    field: field,
    message: error.message,
  );
}

/// Firebase の callable を呼ぶ。初期化に失敗していれば `unavailable`。
Future<Map<String, Object?>> callFirebaseCallable(
  String name,
  Map<String, Object?> data,
) async {
  if (!await FirebaseBootstrap.ensureInitialized()) {
    throw const BackendException(
      code: 'unavailable',
      reason: 'firebase_not_initialized',
    );
  }
  try {
    final callable = FirebaseFunctions.instanceFor(region: backendRegion)
        .httpsCallable(
          name,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        );
    final result = await callable.call<Object?>(data);
    return normalizeFirestoreMap(result.data);
  } on FirebaseFunctionsException catch (error) {
    throw _fromFunctionsException(error);
  } on BackendException {
    rethrow;
  } catch (error) {
    // SocketException・TimeoutException・PlatformException など。生の文面は残さない。
    throw BackendException(
      code: 'unavailable',
      message: error.runtimeType.toString(),
    );
  }
}

class FirebaseBackendClient implements BackendClient {
  FirebaseBackendClient({required this.account});

  final AccountService account;

  @override
  bool get available => true;

  @override
  Future<Map<String, Object?>> call(
    String name, [
    Map<String, Object?> data = const {},
  ]) async {
    // ensureUser はサインイン直後にアカウント側が呼ぶ。それ以外は先に ensureUser まで済ませる。
    if (name != 'ensureUser') {
      final profile = await account.ensureReady();
      if (profile == null) {
        throw const BackendException(
          code: 'unauthenticated',
          reason: 'sign_in_failed',
        );
      }
    }
    return callFirebaseCallable(name, data);
  }
}

// --- アカウント --------------------------------------------------------------

/// 匿名サインインと `ensureUser`、`users/{uid}` の購読。テストでは偽物に差し替える。
abstract class AccountService {
  /// false なら何もしない（Firebase 無効）。
  bool get available;

  /// 匿名サインインして uid を返す。失敗（オフラインなど）は null。
  Future<String?> signIn();

  /// サインイン → `ensureUser` まで済ませ、プロフィールを返す。失敗は null。
  /// 成功した結果は覚えておき、失敗したら次の呼び出しでやり直す。
  /// [locale] を省くと、アプリの表示言語（なければ端末の言語）を使う。
  Future<UserProfile?> ensureReady({String? locale});

  /// `users/{uid}` の購読。ドキュメントがまだ無ければ null を流す。
  Stream<UserProfile?> watchProfile(String uid);

  /// Firebase の ID トークン（`POST /api/answer` の `Authorization: Bearer`）。
  Future<String?> idToken();
}

/// Firebase 無効のときの [AccountService]。何も呼ばず、いつも未サインイン。
class NoopAccountService implements AccountService {
  const NoopAccountService();

  @override
  bool get available => false;

  @override
  Future<String?> signIn() async => null;

  @override
  Future<UserProfile?> ensureReady({String? locale}) async => null;

  @override
  Stream<UserProfile?> watchProfile(String uid) => Stream.value(null);

  @override
  Future<String?> idToken() async => null;
}

class FirebaseAccountService implements AccountService {
  FirebaseAccountService({String Function()? language})
    : _language = language ?? deviceLanguageCode;

  final String Function() _language;
  Future<UserProfile?>? _ready;
  String? _readyUid;

  @override
  bool get available => true;

  @override
  Future<String?> signIn() async {
    if (!await FirebaseBootstrap.ensureInitialized()) return null;
    try {
      final auth = FirebaseAuth.instance;
      final user = auth.currentUser ?? (await auth.signInAnonymously()).user;
      return user?.uid;
    } catch (error) {
      debugPrint(
        '[Account] Anonymous sign-in unavailable: ${error.runtimeType}',
      );
      return null;
    }
  }

  @override
  Future<UserProfile?> ensureReady({String? locale}) async {
    final uid = await signIn();
    if (uid == null) return null;
    // 別のアカウントに替わった（データ削除後など）らやり直す。
    if (_readyUid != uid) {
      _ready = null;
      _readyUid = uid;
    }
    final pending = _ready ??= _ensureUser(uid, locale ?? _language());
    final profile = await pending;
    if (profile == null && identical(_ready, pending)) _ready = null;
    return profile;
  }

  Future<UserProfile?> _ensureUser(String uid, String locale) async {
    try {
      final response = await callFirebaseCallable('ensureUser', {
        'locale': locale == 'en' ? 'en' : 'ja',
      });
      return UserProfile.fromEnsureUser(uid, response);
    } catch (error) {
      debugPrint('[Account] ensureUser unavailable: ${error.runtimeType}');
      return null;
    }
  }

  @override
  Stream<UserProfile?> watchProfile(String uid) {
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
          final data = snapshot.data();
          if (!snapshot.exists || data == null) return null;
          return UserProfile.fromData(uid, normalizeFirestoreMap(data));
        });
  }

  @override
  Future<String?> idToken() async {
    if (!await FirebaseBootstrap.ensureInitialized()) return null;
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }
}

/// 端末の言語から `ja` / `en`（それ以外は `ja`）。
String deviceLanguageCode() =>
    ui.PlatformDispatcher.instance.locale.languageCode == 'en' ? 'en' : 'ja';

final accountServiceProvider = Provider<AccountService>(
  (ref) => AppConfig.firebaseBackendEnabled
      ? FirebaseAccountService(
          language: () {
            final chosen = ref.read(appLocaleProvider)?.languageCode;
            return chosen == 'en' || chosen == 'ja'
                ? chosen!
                : deviceLanguageCode();
          },
        )
      : const NoopAccountService(),
);

final backendClientProvider = Provider<BackendClient>(
  (ref) => AppConfig.firebaseBackendEnabled
      ? FirebaseBackendClient(account: ref.watch(accountServiceProvider))
      : const UnavailableBackendClient(),
);

/// 現在の uid。未サインイン・Firebase 無効なら null。
///
/// サインインに失敗した（オフラインだった）ときは null になる。復帰したら
/// `ref.invalidate(authUidProvider)` でやり直す（アプリ復帰時に共有側の
/// `SharingHost` が呼ぶ）。
final authUidProvider = FutureProvider<String?>(
  (ref) => ref.watch(accountServiceProvider).signIn(),
);

/// `users/{uid}` の購読。未サインインなら null。
final userProfileProvider = StreamProvider<UserProfile?>((ref) async* {
  final service = ref.watch(accountServiceProvider);
  final uid = await ref.watch(authUidProvider.future);
  if (uid == null) {
    yield null;
    return;
  }
  // ensureUser の結果を最初の値にする。失敗しても購読は続ける（後で届く）。
  final seeded = await service.ensureReady();
  if (seeded != null) yield seeded;
  yield* service.watchProfile(uid).handleError((Object error) {
    debugPrint('[Account] Profile stream unavailable: ${error.runtimeType}');
  });
});
