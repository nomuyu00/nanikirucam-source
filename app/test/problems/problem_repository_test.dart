import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/problems/local_daily.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/problems/problem_repository.dart';
import 'package:nanikiru_cam/problems/problems_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  group('FirebaseProblemRepository.answer（POST /api/answer）', () {
    late FakeAccountService account;
    late FakeBackendClient backend;

    setUp(() {
      account = FakeAccountService(
        uid: 'u1',
        profile: const UserProfile(uid: 'u1'),
        token: 'ID-TOKEN',
      );
      backend = FakeBackendClient();
    });

    FirebaseProblemRepository repo(FakeJsonHttpClient http) =>
        FirebaseProblemRepository(
          account: account,
          backend: backend,
          http: http,
          answerUrl: Uri.parse('https://nanikiru-cam.web.app/api/answer'),
        );

    test('ID トークンを Bearer で付け、source=app と selfRank を送る', () async {
      final http = FakeJsonHttpClient(
        (_, _) => JsonHttpResponse(200, answerResponseJson()),
      );
      final outcome = await repo(
        http,
      ).answer(problemId: 'AbC12345', tile: '9p', selfRank: 3);
      final (url, body, headers) = http.requests.single;
      expect(url.toString(), 'https://nanikiru-cam.web.app/api/answer');
      expect(body, {
        'problemId': 'AbC12345',
        'tile': '9p',
        'source': 'app',
        'selfRank': 3,
      });
      expect(headers['Authorization'], 'Bearer ID-TOKEN');
      expect(outcome.correct, isTrue);
      expect(outcome.stats.total, 12);
    });

    test('selfRank は 1〜14 に収め、省略もできる', () async {
      final http = FakeJsonHttpClient(
        (_, _) => JsonHttpResponse(200, answerResponseJson()),
      );
      final repository = repo(http);
      await repository.answer(problemId: 'AbC12345', tile: '9p', selfRank: 40);
      await repository.answer(problemId: 'AbC12345', tile: '9p');
      expect(http.requests[0].$2['selfRank'], 14);
      expect(http.requests[1].$2.containsKey('selfRank'), isFalse);
    });

    test('サーバーのエラーを BackendException にそろえる', () async {
      Future<BackendException> failWith(int status, String code) async {
        final http = FakeJsonHttpClient(
          (_, _) => JsonHttpResponse(status, {
            'error': {'code': code, 'message': 'x'},
          }),
        );
        try {
          await repo(http).answer(problemId: 'AbC12345', tile: '9p');
        } on BackendException catch (e) {
          return e;
        }
        fail('例外にならなかった');
      }

      final notFound = await failWith(404, 'not_found');
      expect(notFound.code, 'not-found');
      expect(notFound.reason, 'not_found');
      expect((await failWith(400, 'invalid_tile')).code, 'invalid-argument');
      expect((await failWith(401, 'unauthenticated')).code, 'unauthenticated');
      final internal = await failWith(500, 'internal');
      expect(internal.code, 'internal');
      expect(internal.isRetryable, isTrue);
    });

    test('ID トークンがない（サインインできない）なら送らず unauthenticated', () async {
      account.token = null;
      final http = FakeJsonHttpClient(
        (_, _) => JsonHttpResponse(200, answerResponseJson()),
      );
      await expectLater(
        repo(http).answer(problemId: 'AbC12345', tile: '9p'),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            'unauthenticated',
          ),
        ),
      );
      expect(http.requests, isEmpty);
    });

    test('通報は reportProblem を呼ぶ', () async {
      backend.handlers['reportProblem'] = (data) async => {
        'reported': true,
        'alreadyReported': false,
        'hidden': true,
      };
      final result = await repo(
        FakeJsonHttpClient((_, _) => JsonHttpResponse(200, {})),
      ).report('AbC12345', ProblemReportReason.wrongAnswer);
      expect(backend.calls.single.$1, 'reportProblem');
      expect(backend.calls.single.$2, {
        'problemId': 'AbC12345',
        'reason': 'wrong_answer',
      });
      expect(result.reported, isTrue);
      expect(result.hidden, isTrue);
    });
  });

  group('IoJsonHttpClient（実際の HTTP）', () {
    late HttpServer server;
    late Map<String, Object?> received;
    late Map<String, String> receivedHeaders;

    setUp(() async {
      HttpOverrides.global = null;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      received = {};
      receivedHeaders = {};
      server.listen((request) async {
        receivedHeaders = {
          'authorization': request.headers.value('authorization') ?? '',
          'content-type': request.headers.contentType?.mimeType ?? '',
        };
        received =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, Object?>;
        if (request.uri.path == '/missing') {
          request.response
            ..statusCode = 404
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'error': {'code': 'not_found'},
              }),
            );
        } else if (request.uri.path == '/html') {
          request.response
            ..statusCode = 502
            ..write('<html>bad gateway</html>');
        } else {
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(answerResponseJson()));
        }
        await request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');

    test('JSON を POST して本文を読む', () async {
      final response = await IoJsonHttpClient().postJson(
        url('/api/answer'),
        {'problemId': 'AbC12345', 'tile': '9p'},
        headers: {'Authorization': 'Bearer T'},
      );
      expect(response.statusCode, 200);
      expect(response.body['ok'], isTrue);
      expect(received, {'problemId': 'AbC12345', 'tile': '9p'});
      expect(receivedHeaders['authorization'], 'Bearer T');
      expect(receivedHeaders['content-type'], 'application/json');
    });

    test('エラー本文が JSON でなくても落ちない', () async {
      final missing = await IoJsonHttpClient().postJson(url('/missing'), {});
      expect(missing.statusCode, 404);
      expect((missing.body['error']! as Map)['code'], 'not_found');
      final html = await IoJsonHttpClient().postJson(url('/html'), {});
      expect(html.statusCode, 502);
      expect(html.body, isEmpty);
    });

    test('つながらないときは unavailable（再試行してよい）', () async {
      final port = server.port;
      await server.close(force: true);
      await expectLater(
        IoJsonHttpClient(
          timeout: const Duration(seconds: 2),
        ).postJson(Uri.parse('http://127.0.0.1:$port/api/answer'), {}),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'unavailable')
              .having((e) => e.isRetryable, 'retryable', isTrue),
        ),
      );
    });
  });

  group('ProblemAnswerSubmitter', () {
    late FakeProblemRepository repository;
    late RecordingBackend backend;
    late AppAnalytics analytics;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'analytics.collection_consent.v1': true,
      });
      repository = FakeProblemRepository();
      backend = RecordingBackend();
      analytics = AppAnalytics(backend: backend);
      await analytics.initialize();
    });

    test('選んだ牌の id を手牌のラベルにして送り、結果を返す', () async {
      repository.answerOutcome = ProblemAnswerOutcome.fromJson(
        answerResponseJson(),
      );
      final submitter = ProblemAnswerSubmitter(
        repository: repository,
        analytics: analytics,
      );
      final input = sampleHand();
      final outcome = await submitter.submitChoice(
        problemId: 'AbC12345',
        input: input,
        discardId: 17, // 9p
        selfRank: 1,
      );
      expect(outcome?.correct, isTrue);
      expect(repository.answers.single, ('AbC12345', '9p', 1));
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, ['problem_answered']);
      expect(backend.parameters.single, {'correct': 1});
    });

    test('2 回目の回答は集計されないのでイベントを送らない', () async {
      final json = answerResponseJson()..['alreadyAnswered'] = true;
      repository.answerOutcome = ProblemAnswerOutcome.fromJson(json);
      final submitter = ProblemAnswerSubmitter(
        repository: repository,
        analytics: analytics,
      );
      await submitter.submit(problemId: 'AbC12345', tile: '9p');
      await Future<void>.delayed(Duration.zero);
      expect(backend.events, isEmpty);
    });

    test('手牌にない牌・送れなかったときは null（手元のエンジンで続けられる）', () async {
      repository.answerOutcome = ProblemAnswerOutcome.fromJson(
        answerResponseJson(),
      );
      final submitter = ProblemAnswerSubmitter(
        repository: repository,
        analytics: analytics,
      );
      // 4z は手牌にない。
      expect(
        await submitter.submitChoice(
          problemId: 'AbC12345',
          input: sampleHand(),
          discardId: 30, // 4z
        ),
        isNull,
      );
      expect(repository.answers, isEmpty);

      repository.error = const BackendException(code: 'unavailable');
      expect(await submitter.submit(problemId: 'AbC12345', tile: '9p'), isNull);

      repository.isAvailable = false;
      repository.answers.clear();
      expect(await submitter.submit(problemId: 'AbC12345', tile: '9p'), isNull);
      expect(repository.answers, isEmpty);
    });
  });

  group('providers', () {
    test('Firebase が無効なら端末内の今日の問題だけ（オンライン機能は呼べない）', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final repository = container.read(problemRepositoryProvider);
      expect(repository, isA<LocalDailyProblemRepository>());
      expect(repository.available, isFalse);
      expect(repository.supportsDaily, isTrue);
      await expectLater(
        repository.fetchProblem('x'),
        throwsA(isA<BackendException>()),
      );
      final daily = await repository.fetchDaily('2026-10-21');
      expect(daily.all, hasLength(3));
      await expectLater(
        repository.answer(problemId: 'daily-2026-10-21-1', tile: '1m'),
        throwsA(isA<BackendException>()),
      );
    });

    test('dailyProblemsProvider は日付ごとに repository から読む', () async {
      final repository = FakeProblemRepository();
      repository.daily['2026-10-21'] = DailyProblems(
        date: '2026-10-21',
        official: sampleProblem(),
      );
      final container = ProviderContainer(
        overrides: [problemRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final daily = await container.read(
        dailyProblemsProvider('2026-10-21').future,
      );
      expect(daily.official?.id, 'AbC12345');
      final other = await container.read(
        dailyProblemsProvider('2026-10-20').future,
      );
      expect(other.isEmpty, isTrue);
      expect(repository.fetchedDates, ['2026-10-21', '2026-10-20']);
    });
  });
}
