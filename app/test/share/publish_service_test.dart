import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/problems/problem.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../problems/fakes.dart';

PublishRequest sampleRequest({String nickname = 'まじゃおう', HandInput? input}) {
  final hand = (input ?? sampleHand()).normalized();
  return PublishRequest(
    input: hand,
    answer: PublishedAnswer.fromReport(analyzeHand(hand), hand),
    nickname: nickname,
  );
}

final png = Uint8List.fromList([1, 2, 3, 4]);

void main() {
  group('PublishRequest.toJson（API.md 1.2）', () {
    test('HandInput と同じキーに answer などを足し、v / dealer / visible は送らない', () {
      final request = sampleRequest();
      final json = request.toJson();
      expect(
        json.keys,
        containsAll([
          'tiles',
          'tsumoIndex',
          'dora',
          'seatWind',
          'roundWind',
          'turn',
          'nickname',
          'locale',
          'answer',
        ]),
      );
      expect(json.keys, isNot(contains('v')));
      expect(json.keys, isNot(contains('dealer')));
      expect(json.keys, isNot(contains('visible')));
      expect(json['tiles'], request.input.tiles);
      expect(json['tsumoIndex'], 13);
      expect(json['dora'], ['3z']);
      expect(json['seatWind'], 'south');
      expect(json['roundWind'], 'east');
      expect(json['turn'], 6);
      expect(json['nickname'], 'まじゃおう');
      expect(json['locale'], 'ja');
      final answer = json['answer']! as Map<String, Object?>;
      expect((answer['byAxis']! as Map)['balance'], ['5m']);
      expect((answer['byAxis']! as Map)['speed'], ['9p']);
      expect(answer['shanten'], 1);
      expect(answer['ukeire'], {'kinds': 9, 'total': 31});
    });

    test('副露・ツモ牌の位置・見えている牌（送らない）', () {
      final hand = meldHand().copyWith(visibleTiles: ['1s']);
      final request = sampleRequest(input: hand);
      final json = request.toJson();
      expect(json['melds'], [
        {
          'kind': 'pon',
          'tiles': ['5z', '5z', '5z'],
        },
      ]);
      // 副露を除いた 11 枚で、ツモ牌は末尾。
      expect((json['tiles']! as List), hasLength(11));
      expect(json['tsumoIndex'], 10);
      expect(json['dora'], ['3z', '1p']);
      expect(json.containsKey('visible'), isFalse);
    });

    test('牌ラベル列・設定・正解だけを送る（写真や端末の情報は含まれない）', () {
      final json = sampleRequest().toJson();
      expect(json.keys.toSet(), {
        'tiles',
        'tsumoIndex',
        'dora',
        'seatWind',
        'roundWind',
        'turn',
        'nickname',
        'locale',
        'answer',
      });
    });

    test('出題者名は前後の空白を除き、空なら送らない。turn なしなら送らない', () {
      final blank = sampleRequest(nickname: '   ').toJson();
      expect(blank.containsKey('nickname'), isFalse);
      final trimmed = sampleRequest(nickname: ' ぷろ ').toJson();
      expect(trimmed['nickname'], 'ぷろ');
      final noTurn = sampleRequest(input: sampleHand(turn: null)).toJson();
      expect(noTurn.containsKey('turn'), isFalse);
    });

    test('JSON を経由して元に戻る（キューに保存するため）', () {
      final request = sampleRequest();
      final restored = PublishRequest.fromJson(request.toJson());
      expect(restored.input.tiles, request.input.tiles);
      expect(restored.input.tsumoIndex, request.input.tsumoIndex);
      expect(restored.input.doraIndicators, request.input.doraIndicators);
      expect(restored.answer, request.answer);
      expect(restored.nickname, 'まじゃおう');
      expect(restored.locale, 'ja');
    });
  });

  group('PublishResult', () {
    test('publishProblem の返事を読む', () {
      final result = PublishResult.fromJson(publishResponse());
      expect(result.problemId, 'AbC12345');
      expect(result.existing, isFalse);
      expect(result.cardUploadPath, 'cards/AbC12345/1x1.png');
      expect(
        result.qrUrl(referralCode: 'ABCD2345'),
        'https://nanikiru-cam.web.app/p/AbC12345?ref=ABCD2345',
      );
      expect(result.qrUrl(), 'https://nanikiru-cam.web.app/p/AbC12345');
    });

    test('他人の問題（existing）は cardUploadPath が null。url が無ければ AppConfig から作る', () {
      final result = PublishResult.fromJson({
        'problemId': 'ZzZ98765',
        'existing': true,
        'cardUploadPath': null,
      });
      expect(result.existing, isTrue);
      expect(result.cardUploadPath, isNull);
      expect(
        result.qrUrl(referralCode: 'ABCD2345'),
        'https://nanikiru-cam.web.app/p/ZzZ98765?ref=ABCD2345',
      );
    });

    test('problemId がなければ FormatException', () {
      expect(
        () => PublishResult.fromJson({'existing': false}),
        throwsFormatException,
      );
    });
  });

  group('PublishService.publish', () {
    late FakeBackendClient backend;
    late FakeCardUploader uploader;
    late MemoryQueueStore store;
    late MemoryCardFiles files;
    late List<PublishResult> published;
    late DateTime now;

    PublishService service() => PublishService(
      backend: backend,
      uploader: uploader,
      store: store,
      files: files,
      now: () => now,
      onPublished: published.add,
    );

    setUp(() {
      backend = FakeBackendClient();
      uploader = FakeCardUploader();
      store = MemoryQueueStore();
      files = MemoryCardFiles();
      published = [];
      now = DateTime.utc(2026, 10, 21, 9);
    });

    test('成功: publishProblem に API.md の形で送り、結果を返す', () async {
      Map<String, Object?>? sent;
      backend.handlers['publishProblem'] = (data) async {
        sent = data;
        return publishResponse();
      };
      final attempt = await service().publish(sampleRequest());
      expect(attempt, isA<PublishSucceeded>());
      expect((attempt as PublishSucceeded).result.problemId, 'AbC12345');
      expect(sent?['tiles'], hasLength(14));
      expect(sent?['answer'], isA<Map>());
      expect(published, hasLength(1));
    });

    test('既存の問題（existing）は新規公開として数えない', () async {
      backend.handlers['publishProblem'] = (_) async =>
          publishResponse(existing: true, cardUploadPath: null);
      final attempt = await service().publish(sampleRequest());
      expect(attempt, isA<PublishSucceeded>());
      expect(published, isEmpty);
    });

    test('オフライン・一時的な失敗は Deferred（キューに入れてよい）', () async {
      for (final code in const [
        'unavailable',
        'deadline-exceeded',
        'unauthenticated',
      ]) {
        backend.handlers['publishProblem'] = (_) async =>
            throw BackendException(code: code);
        final attempt = await service().publish(sampleRequest());
        expect(attempt, isA<PublishDeferred>(), reason: code);
        expect((attempt as PublishDeferred).queueable, isTrue);
        expect(attempt.cause?.code, code);
      }
      expect(published, isEmpty);
    });

    test('サーバーの拒否は Rejected（NG ワード・上限・入力の誤り）', () async {
      backend.handlers['publishProblem'] = (_) async =>
          throw const BackendException(
            code: 'invalid-argument',
            reason: 'ng_word',
            field: 'nickname',
          );
      final rejected =
          await service().publish(sampleRequest()) as PublishRejected;
      expect(rejected.error.reason, 'ng_word');
      expect(rejected.error.field, 'nickname');

      backend.handlers['publishProblem'] = (_) async =>
          throw const BackendException(
            code: 'resource-exhausted',
            reason: 'daily_limit',
          );
      expect(await service().publish(sampleRequest()), isA<PublishRejected>());
    });

    test('Firebase 無効なら呼ばずに Deferred（キューには入れない）', () async {
      backend.isAvailable = false;
      final attempt = await service().publish(sampleRequest());
      expect(attempt, isA<PublishDeferred>());
      expect((attempt as PublishDeferred).queueable, isFalse);
      expect(backend.calls, isEmpty);
    });

    test('返事の形が壊れていても落ちずに Deferred', () async {
      backend.handlers['publishProblem'] = (_) async => {'existing': false};
      expect(await service().publish(sampleRequest()), isA<PublishDeferred>());
    });

    group('uploadCard', () {
      test('cardUploadPath に PNG を置く', () async {
        final ok = await service().uploadCard(
          PublishResult.fromJson(publishResponse()),
          png,
        );
        expect(ok, isTrue);
        expect(uploader.uploads.single.$1, 'cards/AbC12345/1x1.png');
        expect(uploader.uploads.single.$2, png);
      });

      test('他人の問題（置き場なし）は何もしない', () async {
        final ok = await service().uploadCard(
          PublishResult.fromJson(publishResponse(cardUploadPath: null)),
          png,
        );
        expect(ok, isTrue);
        expect(uploader.uploads, isEmpty);
      });

      test('一時的な失敗ならアップロードだけをキューに入れる', () async {
        uploader.error = const BackendException(code: 'unavailable');
        final ok = await service().uploadCard(
          PublishResult.fromJson(publishResponse()),
          png,
        );
        expect(ok, isFalse);
        final job = store.jobs.single;
        expect(job.problemId, 'AbC12345');
        expect(job.cardUploadPath, 'cards/AbC12345/1x1.png');
        expect(job.request, isNull);
        expect(await files.read(job.cardFilePath!), png);
      });

      test('恒久的な失敗（権限なし）はキューに入れない', () async {
        uploader.error = const BackendException(code: 'permission-denied');
        final ok = await service().uploadCard(
          PublishResult.fromJson(publishResponse()),
          png,
        );
        expect(ok, isFalse);
        expect(store.jobs, isEmpty);
        expect(files.files, isEmpty);
      });
    });

    group('キューと再試行（設計書 8 章）', () {
      test('enqueue: 公開リクエストとカード（QR はストア）を保存する', () async {
        await service().enqueue(sampleRequest(), card: png);
        final job = store.jobs.single;
        expect(job.problemId, isNull);
        expect(job.request?.nickname, 'まじゃおう');
        expect(job.createdAt, now);
        expect(await files.read(job.cardFilePath!), png);
        expect(await service().pendingCount(), 1);
      });

      test('flush: オフラインのままなら残し、復帰したら公開してカードを置く', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);

        // まだオフライン。
        backend.handlers['publishProblem'] = (_) async =>
            throw const BackendException(code: 'unavailable');
        await s.flush();
        expect(store.jobs, hasLength(1));
        expect(store.jobs.single.attempts, 1);
        expect(published, isEmpty);

        // 復帰。
        backend.handlers['publishProblem'] = (_) async => publishResponse();
        await s.flush();
        expect(store.jobs, isEmpty);
        expect(published.single.problemId, 'AbC12345');
        expect(uploader.uploads.single.$1, 'cards/AbC12345/1x1.png');
        expect(uploader.uploads.single.$2, png);
        expect(files.files, isEmpty, reason: '送り終えたカードは消す');
      });

      test('公開は済んだがカードを置けなかった場合、次はアップロードだけやり直す', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        backend.handlers['publishProblem'] = (_) async => publishResponse();
        uploader.error = const BackendException(code: 'unavailable');
        await s.flush();
        final job = store.jobs.single;
        expect(job.problemId, 'AbC12345');
        expect(job.cardUploadPath, 'cards/AbC12345/1x1.png');
        expect(published, hasLength(1));

        uploader.error = null;
        await s.flush();
        expect(store.jobs, isEmpty);
        expect(published, hasLength(1), reason: '二重に公開しない');
        expect(
          backend.calls.where((c) => c.$1 == 'publishProblem'),
          hasLength(1),
        );
        expect(uploader.uploads, hasLength(1));
      });

      test('拒否された公開は捨てる（再試行しても通らない）', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        backend.handlers['publishProblem'] = (_) async =>
            throw const BackendException(
              code: 'resource-exhausted',
              reason: 'daily_limit',
            );
        await s.flush();
        expect(store.jobs, isEmpty);
        expect(files.files, isEmpty);
      });

      test('古い・試行しすぎた公開は捨てる', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        now = now.add(const Duration(days: 15));
        backend.handlers['publishProblem'] = (_) async => publishResponse();
        await s.flush();
        expect(store.jobs, isEmpty);
        expect(published, isEmpty);
        expect(backend.calls, isEmpty);
      });

      test('オフラインを検知したら残りは試さずそのまま残す', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        await s.enqueue(sampleRequest(nickname: 'B'), card: png);
        backend.handlers['publishProblem'] = (_) async =>
            throw const BackendException(code: 'unavailable');
        await s.flush();
        expect(store.jobs, hasLength(2));
        expect(backend.calls, hasLength(1));
      });

      test('再試行している間に入った公開待ちを失わない', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        backend.handlers['publishProblem'] = (_) async {
          // 通信中にもう 1 件入る。
          await s.enqueue(sampleRequest(nickname: 'later'), card: png);
          return publishResponse();
        };
        await s.flush();
        expect(store.jobs, hasLength(1));
        expect(store.jobs.single.request?.nickname, 'later');
      });

      test('flush は同時に 2 回走らない', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        backend.handlers['publishProblem'] = (_) async => publishResponse();
        await Future.wait([s.flush(), s.flush()]);
        expect(
          backend.calls.where((c) => c.$1 == 'publishProblem'),
          hasLength(1),
        );
      });

      test('Firebase 無効なら flush は何もしない', () async {
        final s = service();
        await s.enqueue(sampleRequest(), card: png);
        backend.isAvailable = false;
        await s.flush();
        expect(store.jobs, hasLength(1));
      });
    });
  });

  group('SharedPrefsPublishQueueStore', () {
    test('端末に JSON で保存し、読み戻せる。壊れた 1 件は捨てる', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsPublishQueueStore();
      expect(await store.load(), isEmpty);

      final job = PublishJob(
        id: '1',
        request: sampleRequest(),
        cardFilePath: '/cards/1.png',
        createdAt: DateTime.utc(2026, 10, 21, 9),
        attempts: 2,
      );
      final uploadOnly = PublishJob(
        id: '2',
        problemId: 'AbC12345',
        cardUploadPath: 'cards/AbC12345/1x1.png',
        cardFilePath: '/cards/2.png',
        createdAt: DateTime.utc(2026, 10, 21, 10),
      );
      await store.save([job, uploadOnly]);
      final loaded = await store.load();
      expect(loaded, hasLength(2));
      expect(loaded[0].request?.answer, job.request?.answer);
      expect(loaded[0].attempts, 2);
      expect(loaded[0].createdAt, job.createdAt);
      expect(loaded[1].problemId, 'AbC12345');
      expect(loaded[1].request, isNull);

      await store.save([]);
      expect(await store.load(), isEmpty);
    });

    test('保存内容が壊れていても空として読む', () async {
      SharedPreferences.setMockInitialValues({
        SharedPrefsPublishQueueStore.preferenceKey: '{not json',
      });
      expect(await SharedPrefsPublishQueueStore().load(), isEmpty);
    });
  });
}
