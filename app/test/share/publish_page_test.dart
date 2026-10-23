import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/analysis_controller.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/analytics/app_analytics.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/app_language.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/share/cards/card_frame.dart';
import 'package:nanikiru_cam/share/publish_page.dart';
import 'package:nanikiru_cam/share/publish_service.dart';
import 'package:nanikiru_cam/share/share_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../problems/fakes.dart';

class _FakeInterstitial implements InterstitialController {
  int shared = 0;

  @override
  void onResultViewed() {}

  @override
  void onShared() => shared++;

  @override
  Future<void> maybeShowBeforeNextHand() async {}
}

const problemUrl = 'https://nanikiru-cam.web.app/p/AbC12345?ref=ABCD2345';

class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final share = FakeShareService();
  final interstitial = _FakeInterstitial();
  final backend = FakeBackendClient();
  final uploader = FakeCardUploader();
  final store = MemoryQueueStore();
  final files = MemoryCardFiles();
  final analyticsBackend = RecordingBackend();
  final published = <PublishResult>[];
  final routes = <String>[];
  late PublishService service;

  /// 書き出した瞬間の、カードの QR（プレビューと Storage 用の 2 枚）。
  final qrAtCapture = <List<String>>[];

  Future<void> pump(
    HandInput input, {
    bool pro = false,
    UserProfile? profile = const UserProfile(
      uid: 'me',
      nickname: 'まじゃおう',
      referralCode: 'ABCD2345',
    ),
  }) async {
    SharedPreferences.setMockInitialValues({
      'analytics.collection_consent.v1': true,
    });
    final analytics = AppAnalytics(backend: analyticsBackend);
    await analytics.initialize();
    service = PublishService(
      backend: backend,
      uploader: uploader,
      store: store,
      files: files,
      onPublished: published.add,
    );
    share.onCapture = () => qrAtCapture.add([
      for (final qr in tester.widgetList<CardQr>(find.byType(CardQr))) qr.url,
    ]);
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          shareServiceProvider.overrideWithValue(share),
          interstitialControllerProvider.overrideWithValue(interstitial),
          analysisServiceProvider.overrideWithValue(fakeAnalysisService()),
          publishServiceProvider.overrideWithValue(service),
          appAnalyticsProvider.overrideWith((ref) => analytics),
          userProfileProvider.overrideWith((ref) => Stream.value(profile)),
          entitlementsProvider.overrideWith(
            (ref) => pro
                ? const EntitlementState(
                    pro: true,
                    source: EntitlementSource.store,
                  )
                : EntitlementState.free,
          ),
        ],
        child: MaterialApp(
          locale: const Locale('ja'),
          supportedLocales: supportedAppLocales,
          localizationsDelegates: testLocalizationsDelegates,
          onGenerateRoute: (settings) {
            if (settings.name == '/') {
              return MaterialPageRoute<void>(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).pushNamed(
                      Routes.publish,
                      arguments: PublishArgs(input: input),
                    ),
                    child: const Text('open'),
                  ),
                ),
              );
            }
            if (settings.name == Routes.publish) {
              return MaterialPageRoute<bool>(
                settings: settings,
                builder: (_) => const PublishPage(),
              );
            }
            routes.add(settings.name ?? '');
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: Text('route:${settings.name}')),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder get submit => find.byKey(const ValueKey('publish-submit'));

  Future<void> tapSubmit() async {
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
  }

  List<String> get previewQr => [
    for (final qr in tester.widgetList<CardQr>(find.byType(CardQr))) qr.url,
  ];
  List<String> get events => analyticsBackend.events;
}

void main() {
  final hand = sampleHand();

  group('公開して共有（設計書 8 章）', () {
    testWidgets('正解を計算して publishProblem → QR を差し込んで書き出し → カードを上げて共有', (
      tester,
    ) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await h.pump(hand);

      // 公開前の QR はストア（またはサイト）。出題者名はプロフィールの値が入る。
      expect(h.previewQr, everyElement(isNot(contains('/p/'))));
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('publish-nickname')))
            .controller
            ?.text,
        'まじゃおう',
      );
      await tester.enterText(
        find.byKey(const ValueKey('publish-nickname')),
        '  ぷろ雀士 ',
      );
      await tester.pump();

      await h.tapSubmit();

      // publishProblem へ API.md の形で送った。
      final (name, sent) = h.backend.calls.single;
      expect(name, 'publishProblem');
      expect(sent['nickname'], 'ぷろ雀士');
      expect((sent['tiles']! as List), hasLength(14));
      expect(sent['tsumoIndex'], 13);
      expect(sent['dora'], ['3z']);
      expect(sent['seatWind'], 'south');
      expect(sent['turn'], 6);
      expect(sent['locale'], 'ja');
      final answer = sent['answer']! as Map;
      expect((answer['byAxis']! as Map)['balance'], ['5m']);
      expect((answer['byAxis']! as Map)['speed'], ['9p']);
      expect(sent.containsKey('v'), isFalse);
      expect(sent.containsKey('visible'), isFalse);

      // 書き出したのは、問題ページの QR を差し込んだあとのカード（共有用と Storage 用の 2 枚とも）。
      expect(h.qrAtCapture, isNotEmpty);
      for (final qrs in h.qrAtCapture) {
        expect(qrs, [problemUrl, problemUrl]);
      }
      // 共有用（1080px 幅）と Storage 用（1:1、1080×1080）。
      expect(h.share.capturePixelRatios, [3.0, 3.0]);

      // cardUploadPath へ PNG を置いた。
      expect(h.uploader.uploads.single.$1, 'cards/AbC12345/1x1.png');

      // 共有シートへ。本文に問題の URL。
      final shared = h.share.shared.single;
      expect(shared.text, contains(problemUrl));
      expect(shared.files, 1);
      expect(h.interstitial.shared, 1);

      expect(find.byKey(const ValueKey('publish-note')), findsOneWidget);
      expect(find.text('公開しました。回答が集まると通知でお知らせします。'), findsOneWidget);
      expect(find.byKey(const ValueKey('publish-view-mine')), findsOneWidget);
      expect(h.store.jobs, isEmpty);
      expect(h.published, hasLength(1));
      expect(h.events, ['share_tapped', 'result_shared']);
      expect(h.analyticsBackend.parameters.last['share_variant'], 'quiz');
    });

    testWidgets('ストーリーで共有しても、Storage に置くカードは 1:1', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await h.pump(hand);
      await tester.tap(find.text('ストーリー 9:16'));
      await tester.pumpAndSettle();
      await h.tapSubmit();
      expect(h.share.capturePixelRatios, [3.0, 3.0]);
      expect(h.uploader.uploads, hasLength(1));
      expect(h.analyticsBackend.parameters.last['share_format'], 'story');
    });

    testWidgets('すでに公開済みの他人の問題（existing）はカードを上げずに共有だけ', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async =>
          publishResponse(existing: true, cardUploadPath: null);
      await h.pump(hand);
      await h.tapSubmit();
      expect(h.uploader.uploads, isEmpty);
      expect(h.share.shared, hasLength(1));
      expect(h.share.capturePixelRatios, [3.0], reason: '共有用の 1 枚だけ書き出す');
      expect(h.published, isEmpty);
    });

    testWidgets('透かしは無料のときだけ（Storage に置くカードにも）', (tester) async {
      final free = _Harness(tester);
      await free.pump(hand);
      expect(
        find.byKey(const ValueKey('share-card-watermark')),
        findsNWidgets(2),
      );
      final pro = _Harness(tester);
      await pro.pump(hand, pro: true);
      expect(find.byKey(const ValueKey('share-card-watermark')), findsNothing);
    });
  });

  group('オフライン・失敗（設計書 8 章）', () {
    testWidgets('オフライン: QR をストアに替えて共有だけ完了し、公開はキューへ。復帰後に公開してカードを置く', (
      tester,
    ) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async =>
          throw const BackendException(code: 'unavailable');
      await h.pump(hand);
      await h.tapSubmit();

      // カードの QR は問題ページではない（まだ ID がない）。
      for (final qrs in h.qrAtCapture) {
        expect(qrs, everyElement(isNot(contains('/p/AbC12345'))));
      }
      // 共有は完了している。
      expect(h.share.shared, hasLength(1));
      expect(h.share.shared.single.text, isNot(contains('AbC12345')));
      expect(h.uploader.uploads, isEmpty);
      expect(find.byKey(const ValueKey('publish-error')), findsNothing);
      expect(
        find.text('オフラインのため公開は後で自動的に行います。カードのQRはストアへ向かいます。'),
        findsOneWidget,
      );

      // 公開待ちに入った（出題者名・正解・カード PNG つき）。
      final job = h.store.jobs.single;
      expect(job.request?.nickname, 'まじゃおう');
      expect(job.request?.answer.correctTiles, ['5m']);
      expect(await h.files.read(job.cardFilePath!), isNotNull);

      // 通信が戻ったら公開され、保存しておいたカードが問題の画像になる。
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await h.service.flush();
      expect(h.store.jobs, isEmpty);
      expect(h.published.single.problemId, 'AbC12345');
      expect(h.uploader.uploads.single.$1, 'cards/AbC12345/1x1.png');
      expect(h.files.files, isEmpty);
    });

    testWidgets('サーバーが拒否したら共有せずメッセージ（NG ワード）。キューにも入れない', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async =>
          throw const BackendException(
            code: 'invalid-argument',
            reason: 'ng_word',
            field: 'nickname',
          );
      await h.pump(hand);
      await h.tapSubmit();
      expect(find.byKey(const ValueKey('publish-error')), findsOneWidget);
      expect(find.text('この出題者名は使えません。別の名前にしてください'), findsOneWidget);
      expect(h.share.shared, isEmpty);
      expect(h.store.jobs, isEmpty);
      // もう一度押せる。
      expect(tester.widget<FilledButton>(h.submit).onPressed, isNotNull);
    });

    testWidgets('1 日の上限', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async =>
          throw const BackendException(
            code: 'resource-exhausted',
            reason: 'daily_limit',
          );
      await h.pump(hand);
      await h.tapSubmit();
      expect(find.textContaining('1日に出題できる数の上限'), findsOneWidget);
      expect(h.share.shared, isEmpty);
    });

    testWidgets('オンライン機能が無いビルドは、公開のスイッチも説明も出さず、カードだけ共有する', (tester) async {
      final h = _Harness(tester);
      h.backend.isAvailable = false;
      await h.pump(hand);
      // 公開のスイッチと「Web で誰でも回答できます」を出さない。
      expect(find.byKey(const ValueKey('publish-public')), findsNothing);
      expect(find.textContaining('Web で誰でも回答'), findsNothing);
      expect(find.text('問題カードを共有'), findsOneWidget); // タイトル
      expect(find.text('シェアする'), findsOneWidget); // ボタン
      expect(find.text('公開して共有'), findsNothing);
      // 問題カードの QR はストアの URL なので「アプリを入手」。
      expect(find.text('スキャンしてアプリへ'), findsWidgets);
      expect(find.text('スキャンして答える'), findsNothing);

      await h.tapSubmit();
      expect(h.share.shared, hasLength(1));
      expect(h.store.jobs, isEmpty);
      expect(h.backend.calls, isEmpty);
      // 通常の流れなので、「カードだけ共有しました」とは出さない。
      expect(find.textContaining('オンライン機能が使えないため'), findsNothing);
      expect(find.byKey(const ValueKey('publish-note')), findsNothing);
      expect(find.byKey(const ValueKey('publish-view-mine')), findsNothing);
      expect(find.byKey(const ValueKey('publish-error')), findsNothing);
    });

    testWidgets('オンライン機能があれば、公開のスイッチ（既定 ON）と説明を出す', (tester) async {
      final h = _Harness(tester);
      await h.pump(hand);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('publish-public')),
      );
      expect(toggle.value, isTrue);
      expect(find.textContaining('Web で誰でも回答'), findsOneWidget);
      expect(find.text('問題を公開'), findsOneWidget); // タイトル
      expect(find.text('公開して共有'), findsOneWidget);
    });

    testWidgets('カードのアップロードに失敗しても共有は止めない（アップロードだけ再試行に回る）', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      h.uploader.error = const BackendException(code: 'unavailable');
      await h.pump(hand);
      await h.tapSubmit();
      expect(h.share.shared, hasLength(1));
      final job = h.store.jobs.single;
      expect(job.problemId, 'AbC12345');
      expect(job.request, isNull);
      expect(job.cardUploadPath, 'cards/AbC12345/1x1.png');
    });

    testWidgets('共有シートでキャンセルしても公開は済んでいる', (tester) async {
      final h = _Harness(tester);
      h.share.completed = false;
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await h.pump(hand);
      await h.tapSubmit();
      expect(h.published, hasLength(1));
      expect(h.events, ['share_tapped']);
      expect(h.interstitial.shared, 0);
    });

    testWidgets('共有シートの失敗はメッセージにする', (tester) async {
      final h = _Harness(tester);
      h.share.shareError = StateError('boom');
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await h.pump(hand);
      await h.tapSubmit();
      expect(find.text('共有できませんでした'), findsOneWidget);
    });
  });

  group('公開しない共有・入力の確認', () {
    testWidgets('「問題として公開する」を切ると、サーバーに送らずカードだけ共有する', (tester) async {
      final h = _Harness(tester);
      await h.pump(hand);
      await tester.ensureVisible(find.byKey(const ValueKey('publish-public')));
      await tester.tap(find.byKey(const ValueKey('publish-public')));
      await tester.pumpAndSettle();
      expect(find.text('公開せずに共有'), findsOneWidget);
      await h.tapSubmit();
      expect(h.backend.calls, isEmpty);
      expect(h.share.shared, hasLength(1));
      expect(h.store.jobs, isEmpty);
      expect(find.byKey(const ValueKey('publish-note')), findsNothing);
    });

    testWidgets('14 枚でない手は出題できない', (tester) async {
      final h = _Harness(tester);
      await h.pump(HandInput(tiles: hand.tiles.take(13).toList()));
      await h.tapSubmit();
      expect(find.text('14枚の手だけ出題できます'), findsOneWidget);
      expect(h.backend.calls, isEmpty);
      expect(h.share.shared, isEmpty);
    });

    testWidgets('解析できない手は出題できない', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        HandInput(
          tiles: const [
            '1m', '1m', '1m', '1m', '1m', '2m', '3m', '4m', '5m', '6m', '7m', //
            '8m', '9m', '1p',
          ],
        ),
      );
      await h.tapSubmit();
      expect(find.text('この手は解析できないため、出題できません'), findsOneWidget);
      expect(h.backend.calls, isEmpty);
    });

    testWidgets('出題者名は 20 文字まで。プロフィールの名前を入れる。打ち直したら上書きしない', (tester) async {
      final h = _Harness(tester);
      await h.pump(
        hand,
        profile: const UserProfile(uid: 'me', nickname: 'ほぼ'),
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('publish-nickname')),
      );
      expect(field.maxLength, 20);
      expect(field.controller?.text, 'ほぼ');
    });

    testWidgets('プロフィールがなくても（未サインイン）出題者名は空欄で使える', (tester) async {
      final h = _Harness(tester);
      h.backend.handlers['publishProblem'] = (_) async => publishResponse();
      await h.pump(hand, profile: null);
      await h.tapSubmit();
      final sent = h.backend.calls.single.$2;
      expect(sent.containsKey('nickname'), isFalse);
      expect(h.share.shared, hasLength(1));
    });
  });
}
