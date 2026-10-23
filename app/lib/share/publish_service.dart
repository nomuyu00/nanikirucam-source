import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_config.dart';
import 'package:nanikiru_cam/core/firebase_bootstrap.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 問題の公開（`publishProblem` → カード PNG のアップロード。設計書 6・8 章、API.md 1.2・4）。
///
/// Firebase を使う部分はすべて抽象（[BackendClient] / [CardUploader] / [PublishQueueStore] /
/// [CardFileStore]）越し。オフライン・一時的な失敗のときは公開をキューに入れ、
/// アプリ復帰後に [PublishService.flush] で再試行する。

/// `publishProblem` に渡すもの（アプリのエンジンで計算した正解つき）。
class PublishRequest extends Equatable {
  const PublishRequest({
    required this.input,
    required this.answer,
    this.nickname = '',
    this.locale = 'ja',
  });

  factory PublishRequest.fromJson(Map<String, Object?> json) {
    final nickname = json['nickname'];
    final locale = json['locale'];
    return PublishRequest(
      input: HandInput.fromJson(json),
      answer: PublishedAnswer.fromJson(json['answer']),
      nickname: nickname is String ? nickname : '',
      locale: locale == 'en' ? 'en' : 'ja',
    );
  }

  /// 14 枚の手。ツモ牌の位置を含む。
  final HandInput input;

  /// アプリのエンジンの結果（`HandInput` の牌のラベルで表す）。
  final PublishedAnswer answer;

  /// 出題者名。20 文字以内、空なら送らない（サーバーは前回の値を使う）。
  final String nickname;

  final String locale;

  /// API.md 1.2 のリクエスト。`HandInput.toJson()` と同じキーに `answer` などを足したもの。
  /// サーバーに送るのは牌ラベルの列と設定だけ（`v` `dealer` `visible` は送らない）。
  Map<String, Object?> toJson() {
    final json = Map<String, Object?>.of(input.toJson())
      ..remove('v')
      ..remove('dealer')
      ..remove('visible');
    final name = nickname.trim();
    if (name.isNotEmpty) json['nickname'] = name;
    json['locale'] = locale;
    json['answer'] = answer.toJson();
    return json;
  }

  @override
  List<Object?> get props => [input, answer, nickname, locale];
}

/// `publishProblem` の戻り値。
class PublishResult extends Equatable {
  const PublishResult({
    required this.problemId,
    this.existing = false,
    this.url,
    this.cardUploadPath,
  });

  factory PublishResult.fromJson(Map<String, Object?> json) {
    final id = json['problemId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('publishProblem: problemId がない');
    }
    final url = json['url'];
    final path = json['cardUploadPath'];
    return PublishResult(
      problemId: id,
      existing: json['existing'] == true,
      url: url is String && url.isNotEmpty ? url : null,
      cardUploadPath: path is String && path.isNotEmpty ? path : null,
    );
  }

  final String problemId;

  /// 同じ手の公開済みの問題が既にあった（新規作成していない）。
  final bool existing;

  /// サーバーが返した問題ページの URL（`?ref=` は付いていない）。
  final String? url;

  /// カード PNG の置き場。他人の問題（[existing]）なら null。
  final String? cardUploadPath;

  /// カードの QR に入れる URL（`/p/{id}?ref=<紹介コード>`）。
  String qrUrl({String? referralCode}) {
    final base = url;
    if (base == null) {
      return AppConfig.problemUrl(problemId, referralCode: referralCode);
    }
    if (referralCode == null || referralCode.isEmpty) return base;
    final separator = base.contains('?') ? '&' : '?';
    return '$base${separator}ref=${Uri.encodeQueryComponent(referralCode)}';
  }

  @override
  List<Object?> get props => [problemId, existing, url, cardUploadPath];
}

/// 公開を試みた結果。
sealed class PublishAttempt {
  const PublishAttempt();
}

class PublishSucceeded extends PublishAttempt {
  const PublishSucceeded(this.result);

  final PublishResult result;
}

/// オフラインなど一時的な失敗（または Firebase 無効）。カードはストアの URL で共有し、
/// [queueable] なら [PublishService.enqueue] で後から公開する。
class PublishDeferred extends PublishAttempt {
  const PublishDeferred({this.cause, this.queueable = true});

  final BackendException? cause;
  final bool queueable;
}

/// サーバーが拒否した（入力の誤り・上限・NG ワード）。再試行しても通らない。
class PublishRejected extends PublishAttempt {
  const PublishRejected(this.error);

  final BackendException error;
}

// --- キュー ----------------------------------------------------------------

/// 再試行待ちの公開 1 件。
///
/// [problemId] が決まっていれば公開は済んでいて、カードのアップロードだけが残っている。
class PublishJob extends Equatable {
  const PublishJob({
    required this.id,
    this.request,
    this.problemId,
    this.cardUploadPath,
    this.cardFilePath,
    required this.createdAt,
    this.attempts = 0,
  });

  factory PublishJob.fromJson(Map<String, Object?> json) {
    final request = json['request'];
    return PublishJob(
      id: json['id']?.toString() ?? '',
      request: request is Map
          ? PublishRequest.fromJson(normalizeFirestoreMap(request))
          : null,
      problemId: json['problemId'] as String?,
      cardUploadPath: json['cardUploadPath'] as String?,
      cardFilePath: json['cardFilePath'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;

  /// 公開前のとき必須。
  final PublishRequest? request;
  final String? problemId;
  final String? cardUploadPath;

  /// QR をストアの URL にして書き出したカード PNG の置き場。
  final String? cardFilePath;
  final DateTime createdAt;
  final int attempts;

  PublishJob copyWith({
    String? problemId,
    String? cardUploadPath,
    int? attempts,
  }) => PublishJob(
    id: id,
    request: request,
    problemId: problemId ?? this.problemId,
    cardUploadPath: cardUploadPath ?? this.cardUploadPath,
    cardFilePath: cardFilePath,
    createdAt: createdAt,
    attempts: attempts ?? this.attempts,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    if (request != null) 'request': request!.toJson(),
    if (problemId != null) 'problemId': problemId,
    if (cardUploadPath != null) 'cardUploadPath': cardUploadPath,
    if (cardFilePath != null) 'cardFilePath': cardFilePath,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'attempts': attempts,
  };

  @override
  List<Object?> get props => [
    id,
    request,
    problemId,
    cardUploadPath,
    cardFilePath,
    createdAt,
    attempts,
  ];
}

abstract class PublishQueueStore {
  Future<List<PublishJob>> load();
  Future<void> save(List<PublishJob> jobs);
}

/// `SharedPreferences` に JSON で保存する（件数は数件）。
class SharedPrefsPublishQueueStore implements PublishQueueStore {
  static const preferenceKey = 'publish_queue_v1';

  @override
  Future<List<PublishJob>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(preferenceKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final jobs = <PublishJob>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          jobs.add(PublishJob.fromJson(normalizeFirestoreMap(item)));
        } on FormatException {
          // 壊れた 1 件は捨てる。
        }
      }
      return jobs;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> save(List<PublishJob> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    if (jobs.isEmpty) {
      await prefs.remove(preferenceKey);
    } else {
      await prefs.setString(
        preferenceKey,
        jsonEncode([for (final job in jobs) job.toJson()]),
      );
    }
  }
}

/// キューに入れたカード PNG の保管（SharedPreferences には大きすぎる）。
abstract class CardFileStore {
  /// [id] のカードを書いて、置き場（後で [read] に渡す文字列）を返す。
  Future<String> write(String id, Uint8List png);
  Future<Uint8List?> read(String path);
  Future<void> delete(String path);
}

class DiskCardFileStore implements CardFileStore {
  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/publish_cards');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  @override
  Future<String> write(String id, Uint8List png) async {
    final dir = await _dir();
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final file = File(path);
      return await file.exists() ? await file.readAsBytes() : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

/// カード PNG を Storage の [path] へ置く（API.md 4）。
abstract class CardUploader {
  /// 失敗は [BackendException]（`permission-denied` などは再試行しても通らない）。
  Future<void> upload(String path, Uint8List png);
}

class FirebaseCardUploader implements CardUploader {
  @override
  Future<void> upload(String path, Uint8List png) async {
    if (!await FirebaseBootstrap.ensureInitialized()) {
      throw const BackendException(code: 'unavailable');
    }
    try {
      await FirebaseStorage.instance
          .ref(path)
          .putData(png, SettableMetadata(contentType: 'image/png'));
    } on FirebaseException catch (error) {
      // Storage の code: unauthorized / retry-limit-exceeded / canceled など。
      final permanent =
          error.code == 'unauthorized' ||
          error.code == 'unauthenticated' ||
          error.code == 'object-not-found' ||
          error.code == 'bucket-not-found' ||
          error.code == 'invalid-argument';
      throw BackendException(
        code: permanent ? 'permission-denied' : 'unavailable',
        message: error.code,
      );
    } catch (error) {
      throw BackendException(
        code: 'unavailable',
        message: error.runtimeType.toString(),
      );
    }
  }
}

// --- サービス ---------------------------------------------------------------

class PublishService {
  PublishService({
    required this.backend,
    required this.uploader,
    required this.store,
    required this.files,
    DateTime Function()? now,
    this.onPublished,
    this.maxAttempts = 20,
    this.maxAge = const Duration(days: 14),
  }) : _now = now ?? DateTime.now;

  final BackendClient backend;
  final CardUploader uploader;
  final PublishQueueStore store;
  final CardFileStore files;
  final DateTime Function() _now;

  /// 新しい問題を公開できたとき（キューからの再試行でも）。
  final void Function(PublishResult result)? onPublished;

  final int maxAttempts;
  final Duration maxAge;

  Future<void>? _flushing;

  /// サーバーに公開できる状態か（Firebase 有効）。
  bool get available => backend.available;

  /// `publishProblem` を呼ぶ。
  Future<PublishAttempt> publish(PublishRequest request) async {
    if (!backend.available) {
      return const PublishDeferred(queueable: false);
    }
    try {
      final result = await _create(request);
      return PublishSucceeded(result);
    } on BackendException catch (error) {
      return error.isRetryable
          ? PublishDeferred(cause: error)
          : PublishRejected(error);
    } on FormatException {
      return const PublishDeferred(
        cause: BackendException(code: 'internal', reason: 'bad_response'),
      );
    }
  }

  Future<PublishResult> _create(PublishRequest request) async {
    final response = await backend.call('publishProblem', request.toJson());
    final result = PublishResult.fromJson(response);
    if (!result.existing) onPublished?.call(result);
    return result;
  }

  /// 公開できたあとにカード PNG を [PublishResult.cardUploadPath] へ置く。
  /// 一時的な失敗なら、アップロードだけをキューに入れて false を返す。
  /// 置き場がない（他人の問題）・恒久的な失敗は何もせず true / false。
  Future<bool> uploadCard(PublishResult result, Uint8List png) async {
    final path = result.cardUploadPath;
    if (path == null) return true;
    try {
      await uploader.upload(path, png);
      return true;
    } on BackendException catch (error) {
      if (error.isRetryable) {
        final id = _newId();
        final cardPath = await files.write(id, png);
        await _add(
          PublishJob(
            id: id,
            problemId: result.problemId,
            cardUploadPath: path,
            cardFilePath: cardPath,
            createdAt: _now(),
          ),
        );
      }
      return false;
    }
  }

  /// 公開をキューに入れる。[card] はストアの URL の QR で書き出したカード
  /// （公開できたら問題の OGP 画像として置く）。
  Future<void> enqueue(PublishRequest request, {Uint8List? card}) async {
    final id = _newId();
    final cardPath = card == null ? null : await files.write(id, card);
    await _add(
      PublishJob(
        id: id,
        request: request,
        cardFilePath: cardPath,
        createdAt: _now(),
      ),
    );
  }

  Future<void> _add(PublishJob job) async {
    final jobs = await store.load();
    await store.save([...jobs, job]);
  }

  /// 再試行待ちの件数。
  Future<int> pendingCount() async => (await store.load()).length;

  Future<List<PublishJob>> pending() => store.load();

  /// キューの再試行。同時に 2 回は走らない。
  Future<void> flush() => _flushing ??= _flush().whenComplete(() {
    _flushing = null;
  });

  Future<void> _flush() async {
    if (!backend.available) return;
    final jobs = await store.load();
    if (jobs.isEmpty) return;
    final remaining = <PublishJob>[];
    var offline = false;
    for (final original in jobs) {
      if (offline) {
        remaining.add(original);
        continue;
      }
      var job = original;
      final expired =
          _now().difference(job.createdAt) > maxAge ||
          job.attempts >= maxAttempts;
      if (expired) {
        await _dropFile(job);
        continue;
      }
      try {
        if (job.problemId == null) {
          final request = job.request;
          if (request == null) {
            await _dropFile(job);
            continue;
          }
          final result = await _create(request);
          job = job.copyWith(
            problemId: result.problemId,
            cardUploadPath: result.cardUploadPath,
          );
        }
        final path = job.cardUploadPath;
        final cardFile = job.cardFilePath;
        if (path != null && cardFile != null) {
          final png = await files.read(cardFile);
          if (png != null) await uploader.upload(path, png);
        }
        await _dropFile(job);
      } on BackendException catch (error) {
        if (error.isRetryable) {
          remaining.add(job.copyWith(attempts: job.attempts + 1));
          offline = true;
        } else {
          // 拒否された公開・置けないカードは、これ以上やり直さない。
          await _dropFile(job);
        }
      } on FormatException {
        remaining.add(job.copyWith(attempts: job.attempts + 1));
      }
    }
    // 再試行中に新しく入った分を落とさない。
    final startedIds = {for (final job in jobs) job.id};
    final added = [
      for (final job in await store.load())
        if (!startedIds.contains(job.id)) job,
    ];
    await store.save([...remaining, ...added]);
  }

  Future<void> _dropFile(PublishJob job) async {
    final path = job.cardFilePath;
    if (path != null) await files.delete(path);
  }

  int _counter = 0;
  String _newId() => '${_now().millisecondsSinceEpoch}-${_counter++}';
}

final publishServiceProvider = Provider<PublishService>((ref) {
  return PublishService(
    backend: ref.watch(backendClientProvider),
    uploader: FirebaseCardUploader(),
    store: SharedPrefsPublishQueueStore(),
    files: DiskCardFileStore(),
    onPublished: (_) {
      unawaited(
        ref
            .read(appAnalyticsProvider)
            .logEvent(AnalyticsEvent.problemPublished),
      );
    },
  );
});

/// 公開待ちの件数（出題した問題の画面で「公開待ち N 件」を出す）。
final pendingPublishCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(publishServiceProvider).pendingCount(),
);
