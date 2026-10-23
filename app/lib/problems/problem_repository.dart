import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem.dart';

/// 公開問題の読み取り・回答・通報の窓口（`app/functions/API.md`）。
///
/// Firebase を使う部分はすべてこの抽象の向こうにある。画面は
/// [problemRepositoryProvider] 経由で使い、テストでは偽物に差し替える。
/// 失敗は [BackendException]（オフラインは `unavailable`）。
abstract class ProblemRepository {
  /// オンライン機能（公開問題の読み取り・回答の集計・通報・人気）が使えるか。
  /// false（Firebase 無効）なら画面は「準備中」を出す。
  bool get available;

  /// 今日の問題（[fetchDaily]）を出せるか。サーバーなしの版でも端末内で作れる
  /// （[LocalDailyProblemRepository]）ので、[available] とは別に持つ。
  /// 既定は [available] と同じ（`implements` する実装は自分で返す）。
  bool get supportsDaily => available;

  /// `problems/{id}`。存在しない・非表示（通報済み）は null。
  Future<Problem?> fetchProblem(String id);

  /// `daily/{date}`（JST の `YYYY-MM-DD`）と、載っている問題。無ければ空。
  Future<DailyProblems> fetchDaily(String date);

  /// 自分の問題（新しい順、非表示も含む）。
  Future<List<Problem>> fetchMyProblems(String uid, {int limit = 50});

  /// 回答の多い順の問題（Pro の「もっと解く」）。
  Future<List<Problem>> fetchPopular({int limit = 20});

  /// アプリからの回答（`POST /api/answer`）。[tile] は問題の手牌にある牌ラベル。
  Future<ProblemAnswerOutcome> answer({
    required String problemId,
    required String tile,
    int? selfRank,
  });

  /// 問題の通報（`reportProblem`）。
  Future<ProblemReportResult> report(
    String problemId,
    ProblemReportReason reason,
  );
}

/// 何も使えない [ProblemRepository]（今日の問題も出さない。テストなどで使う。
/// Firebase 無効の版の既定は [LocalDailyProblemRepository]）。
class UnavailableProblemRepository implements ProblemRepository {
  const UnavailableProblemRepository();

  static const _error = BackendException(
    code: 'unavailable',
    reason: 'firebase_disabled',
  );

  @override
  bool get available => false;

  @override
  bool get supportsDaily => false;

  @override
  Future<Problem?> fetchProblem(String id) => Future.error(_error);

  @override
  Future<DailyProblems> fetchDaily(String date) => Future.error(_error);

  @override
  Future<List<Problem>> fetchMyProblems(String uid, {int limit = 50}) =>
      Future.error(_error);

  @override
  Future<List<Problem>> fetchPopular({int limit = 20}) => Future.error(_error);

  @override
  Future<ProblemAnswerOutcome> answer({
    required String problemId,
    required String tile,
    int? selfRank,
  }) => Future.error(_error);

  @override
  Future<ProblemReportResult> report(
    String problemId,
    ProblemReportReason reason,
  ) => Future.error(_error);
}

/// JSON を POST する最小の HTTP クライアント（`POST /api/answer` 用。テストで差し替える）。
abstract class JsonHttpClient {
  Future<JsonHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  });
}

class JsonHttpResponse {
  const JsonHttpResponse(this.statusCode, this.body);

  final int statusCode;

  /// JSON オブジェクトとして読めなければ空。
  final Map<String, Object?> body;
}

/// `dart:io` の [HttpClient] による実装。通信できなければ [BackendException]（`unavailable`）。
class IoJsonHttpClient implements JsonHttpClient {
  IoJsonHttpClient({this.timeout = const Duration(seconds: 15)});

  final Duration timeout;

  @override
  Future<JsonHttpResponse> postJson(
    Uri url,
    Map<String, Object?> body, {
    Map<String, String> headers = const {},
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(url).timeout(timeout);
      request.headers.contentType = ContentType.json;
      headers.forEach(request.headers.set);
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      Map<String, Object?> parsed = {};
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) parsed = normalizeFirestoreMap(decoded);
      } catch (_) {}
      return JsonHttpResponse(response.statusCode, parsed);
    } on BackendException {
      rethrow;
    } catch (error) {
      throw BackendException(
        code: 'unavailable',
        message: error.runtimeType.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Firestore + `reportProblem` + `POST /api/answer` による本番実装。
class FirebaseProblemRepository implements ProblemRepository {
  FirebaseProblemRepository({
    required this.account,
    required this.backend,
    JsonHttpClient? http,
    Uri? answerUrl,
  }) : _http = http ?? IoJsonHttpClient(),
       _answerUrl =
           answerUrl ?? Uri.parse('${AppConfig.webBaseUrl}/api/answer');

  final AccountService account;
  final BackendClient backend;
  final JsonHttpClient _http;
  final Uri _answerUrl;

  @override
  bool get available => true;

  @override
  bool get supportsDaily => true;

  Future<FirebaseFirestore> _firestore() async {
    if (!await FirebaseBootstrap.ensureInitialized()) {
      throw const BackendException(
        code: 'unavailable',
        reason: 'firebase_not_initialized',
      );
    }
    return FirebaseFirestore.instance;
  }

  BackendException _wrap(Object error) {
    if (error is BackendException) return error;
    if (error is FirebaseException) {
      return BackendException(code: error.code, message: error.message);
    }
    return BackendException(
      code: 'unavailable',
      message: error.runtimeType.toString(),
    );
  }

  Problem? _problemFrom(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    try {
      return Problem.fromData(snapshot.id, normalizeFirestoreMap(data));
    } on FormatException catch (error) {
      // 壊れたドキュメントは無いものとして扱う（手牌の形が読めない）。
      debugPrint('[Problems] Skipped ${snapshot.id}: ${error.message}');
      return null;
    }
  }

  @override
  Future<Problem?> fetchProblem(String id) async {
    try {
      final db = await _firestore();
      final snapshot = await db.collection('problems').doc(id).get();
      final problem = _problemFrom(snapshot);
      if (problem == null || problem.hidden) return null;
      return problem;
    } on FirebaseException catch (error) {
      // 非表示の他人の問題はルールで読めない（permission-denied）= 見つからない扱い。
      if (error.code == 'permission-denied' || error.code == 'not-found') {
        return null;
      }
      throw _wrap(error);
    } catch (error) {
      throw _wrap(error);
    }
  }

  @override
  Future<DailyProblems> fetchDaily(String date) async {
    try {
      final db = await _firestore();
      final snapshot = await db.collection('daily').doc(date).get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) return DailyProblems.empty(date);
      final normalized = normalizeFirestoreMap(data);
      final officialId = normalized['official'];
      final picks = normalized['picks'];
      final ids = <String>[
        if (officialId is String && officialId.isNotEmpty) officialId,
        if (picks is List)
          for (final id in picks)
            if (id is String && id.isNotEmpty) id,
      ];
      final problems = await Future.wait([
        for (final id in ids) fetchProblem(id),
      ]);
      final byId = {
        for (var i = 0; i < ids.length; i++)
          if (problems[i] != null) ids[i]: problems[i]!,
      };
      return DailyProblems(
        date: date,
        official: officialId is String ? byId[officialId] : null,
        picks: [
          if (picks is List)
            for (final id in picks)
              if (id is String && byId[id] != null) byId[id]!,
        ],
      );
    } catch (error) {
      throw _wrap(error);
    }
  }

  @override
  Future<List<Problem>> fetchMyProblems(String uid, {int limit = 50}) async {
    try {
      final db = await _firestore();
      final snapshot = await db
          .collection('problems')
          .where('authorUid', isEqualTo: uid)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return [for (final doc in snapshot.docs) ?_problemFrom(doc)];
    } catch (error) {
      throw _wrap(error);
    }
  }

  @override
  Future<List<Problem>> fetchPopular({int limit = 20}) async {
    try {
      final db = await _firestore();
      final snapshot = await db
          .collection('problems')
          .where('hidden', isEqualTo: false)
          .orderBy('stats.total', descending: true)
          .limit(limit)
          .get();
      return [for (final doc in snapshot.docs) ?_problemFrom(doc)];
    } catch (error) {
      throw _wrap(error);
    }
  }

  @override
  Future<ProblemAnswerOutcome> answer({
    required String problemId,
    required String tile,
    int? selfRank,
  }) async {
    final profile = await account.ensureReady();
    final token = await account.idToken();
    if (profile == null || token == null) {
      throw const BackendException(
        code: 'unauthenticated',
        reason: 'sign_in_failed',
      );
    }
    final response = await _http.postJson(
      _answerUrl,
      {
        'problemId': problemId,
        'tile': tile,
        'source': 'app',
        if (selfRank != null) 'selfRank': selfRank.clamp(1, 14),
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200 && response.body['ok'] == true) {
      try {
        return ProblemAnswerOutcome.fromJson(response.body);
      } on FormatException {
        throw const BackendException(code: 'internal', reason: 'bad_response');
      }
    }
    throw _answerError(response);
  }

  /// `POST /api/answer` の失敗（API.md 2.1 の表）を [BackendException] にする。
  static BackendException _answerError(JsonHttpResponse response) {
    final error = response.body['error'];
    final reason = error is Map ? error['code']?.toString() : null;
    final code = switch (response.statusCode) {
      400 => 'invalid-argument',
      401 => 'unauthenticated',
      404 => 'not-found',
      405 => 'invalid-argument',
      _ => 'internal',
    };
    return BackendException(code: code, reason: reason);
  }

  @override
  Future<ProblemReportResult> report(
    String problemId,
    ProblemReportReason reason,
  ) async {
    final response = await backend.call('reportProblem', {
      'problemId': problemId,
      'reason': reason.wireValue,
    });
    return ProblemReportResult.fromJson(response);
  }
}

/// バックエンド無効（テスト配信版の既定）では、今日の問題だけを端末内で作る
/// [LocalDailyProblemRepository]。バックエンド有効なら Firebase の実装。
final problemRepositoryProvider = Provider<ProblemRepository>((ref) {
  if (!AppConfig.firebaseBackendEnabled) {
    return LocalDailyProblemRepository();
  }
  return FirebaseProblemRepository(
    account: ref.watch(accountServiceProvider),
    backend: ref.watch(backendClientProvider),
  );
});
