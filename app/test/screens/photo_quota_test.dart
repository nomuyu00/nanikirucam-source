import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanikiru_cam/ads/ad_slots.dart';
import 'package:nanikiru_cam/analysis/hand_input.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/quota.dart';
import 'package:nanikiru_cam/core/routes.dart';
import 'package:nanikiru_cam/history/local_history.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';
import 'package:nanikiru_cam/l10n/strings/camera_strings.dart';
import 'package:nanikiru_cam/ml/recognition_draft.dart';
import 'package:nanikiru_cam/ml/tflite_service.dart';
import 'package:nanikiru_cam/ml/tile_selection.dart';

import 'screens_harness.dart';

/// 決まった牌を「認識」する偽の推論。
class FakeTflite extends TfliteService {
  FakeTflite(this.labels);

  final List<String> labels;
  int calls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<RecognitionOutcome?> recognize(
    Uint8List bytes, {
    TileSelectionEngine? engine,
  }) async {
    calls++;
    return RecognitionOutcome(
      selection: SelectedTiles(
        detections: [
          for (var i = 0; i < labels.length; i++)
            TileDetection(
              box: Rect.fromLTWH(0.02 + i * 0.068, 0.4, 0.06, 0.12),
              label: labels[i],
              score: 0.97,
            ),
        ],
        strategy: 'full',
        quality: 1,
      ),
      quarterTurns: 0,
      strategy: 'full',
      inferenceCount: 1,
    );
  }
}

final photo = RecognitionLoadingArgs(imageBytes: Uint8List.fromList([1, 2, 3]));

void main() {
  Future<ScreenHarness> pump(
    WidgetTester tester,
    FakeTflite tflite, {
    RecordingAnalyticsBackend? analytics,
    FakeRewardedGate? rewarded,
  }) => pumpScreens(
    tester,
    analytics: analytics,
    rewarded: rewarded,
    overrides: [tfliteServiceProvider.overrideWith((ref) => tflite)],
  );

  Future<void> useUp(ScreenHarness h) async {
    final notifier = h.container.read(quotaProvider.notifier);
    for (var i = 0; i < 5; i++) {
      expect(await notifier.tryConsume(), isTrue);
    }
    expect(h.container.read(quotaProvider).exhausted, isTrue);
  }

  testWidgets('写真は認識に成功したら 1 回使う（修正画面へ進む）', (tester) async {
    final tflite = FakeTflite(closedYakuHand.tiles);
    final h = await pump(tester, tflite);
    expect(h.container.read(quotaProvider).used, 0);
    await h.push(Routes.recognitionLoading, photo);
    expect(tflite.calls, 1);
    expect(h.container.read(quotaProvider).used, 1);
    final args = h.routes.lastArgs(Routes.recognition) as RecognitionArgs;
    expect(args.draft.labels, closedYakuHand.normalized().tiles);
  });

  testWidgets('尽きていたら認識せず、quota_exhausted と動画 +3 / Pro / 手入力', (tester) async {
    final tflite = FakeTflite(closedYakuHand.tiles);
    final analytics = RecordingAnalyticsBackend();
    final rewarded = FakeRewardedGate(ready: true, result: true);
    final h = await pump(tester, tflite, analytics: analytics, rewarded: rewarded);
    await useUp(h);

    await h.push(Routes.recognitionLoading, photo);
    expect(find.byKey(const ValueKey('quota-exhausted')), findsOneWidget);
    expect(tflite.calls, 0);
    expect(analytics.named('quota_exhausted').single, {'source': 'photo'});

    // Pro の案内。
    await tester.tap(find.byKey(const ValueKey('quota-paywall')));
    await tester.pumpAndSettle();
    expect(
      (h.routes.lastArgs(Routes.paywall) as PaywallArgs).trigger,
      PaywallTrigger.quotaExhausted,
    );
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();

    // 動画を最後まで見ると +3 回になり、そのまま認識する。
    await tester.tap(find.byKey(const ValueKey('quota-reward')));
    await tester.pumpAndSettle();
    expect(rewarded.shown, [RewardKind.quota]);
    final quota = h.container.read(quotaProvider);
    expect(quota.rewardedGranted, 3);
    expect(quota.used, 6);
    expect(tflite.calls, 1);
    expect(h.routes.contains(Routes.recognition), isTrue);
  });

  testWidgets('尽きていても手入力は使える（回数を使わない）', (tester) async {
    final tflite = FakeTflite(closedYakuHand.tiles);
    final h = await pump(tester, tflite);
    await useUp(h);
    await h.push(Routes.recognitionLoading, photo);
    await tester.tap(find.byKey(const ValueKey('quota-manual')));
    await tester.pumpAndSettle();
    final args = h.routes.lastArgs(Routes.recognition) as RecognitionArgs;
    expect(args.draft.length, 0);
    expect(h.container.read(quotaProvider).used, 5);
  });

  testWidgets('手入力・クイズ・結果では回数を使わない', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(Routes.quiz, QuizArgs(input: splitHand, source: 'manual'));
    await tester.tap(find.byKey(const ValueKey('quiz-tile-13')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quiz-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('result-page')), findsOneWidget);
    await h.push(Routes.result, ResultArgs(input: closedYakuHand));
    expect(h.container.read(quotaProvider).used, 0);
  });

  testWidgets('手入力画面から進むと Quiz（source は manual、回数は使わない）', (tester) async {
    final h = await pumpScreens(tester);
    await h.push(
      Routes.manualInput,
      RecognitionArgs(
        draft: RecognitionDraft(labels: splitHand.tiles, tsumoIndex: 13),
      ),
    );
    final next = find.byKey(const ValueKey('recognition-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    final args = h.routes.lastArgs(Routes.quiz) as QuizArgs;
    expect(args.source, 'manual');
    expect(find.byKey(const ValueKey('quiz-page')), findsOneWidget);
    expect(h.container.read(quotaProvider).used, 0);
  });

  testWidgets('撮るだけモード: 解析も修正画面も出さずに「未解析」で履歴に保存してカメラに戻る', (
    tester,
  ) async {
    final tflite = FakeTflite(splitHand.tiles);
    final h = await pump(tester, tflite);
    h.container
        .read(appSettingsProvider.notifier)
        .replace(const AppSettings(quickCapture: true));
    await h.push(Routes.recognitionLoading, photo);

    // 修正画面・Quiz・Result には進まず、呼び出し元（カメラ）に戻る。
    expect(h.routes.contains(Routes.recognition), isFalse);
    expect(h.routes.contains(Routes.quiz), isFalse);
    expect(h.routes.contains(Routes.result), isFalse);
    expect(find.text('home'), findsOneWidget);
    expect(find.text(const CameraStrings(AppLang.ja).quickCaptureSaved), findsOneWidget);

    // 無料枠は認識で 1 回使う。
    expect(h.container.read(quotaProvider).used, 1);

    // 認識した手だけを「未解析」で保存（画像は持たない）。
    final history = await h.container.read(historyProvider.future);
    final entry = history.single;
    expect(entry.pending, isTrue);
    expect(entry.input.tileCount, HandInput.maxTileCount);
    expect(entry.input.tiles.toSet(), splitHand.tiles.toSet());
    expect(entry.best, isEmpty);
    expect(entry.correct, isNull);
    expect(entry.source, 'photo');
    final json = entry.toJson();
    expect(json['pending'], isTrue);
    expect(json.keys, isNot(contains('image')));
    expect(h.container.read(quotaProvider).used, 1);
  });

  testWidgets('撮るだけモードでも認識が不完全なら保存せず修正画面へ', (tester) async {
    final tflite = FakeTflite(splitHand.tiles.take(12).toList());
    final h = await pump(tester, tflite);
    h.container
        .read(appSettingsProvider.notifier)
        .replace(const AppSettings(quickCapture: true));
    await h.push(Routes.recognitionLoading, photo);
    expect(h.routes.contains(Routes.recognition), isTrue);
    expect(await h.container.read(historyProvider.future), isEmpty);
  });

  testWidgets('撮るだけモードが OFF なら修正画面へ（保存しない）', (tester) async {
    final tflite = FakeTflite(splitHand.tiles);
    final h = await pump(tester, tflite);
    await h.push(Routes.recognitionLoading, photo);
    expect(h.routes.contains(Routes.recognition), isTrue);
    expect(h.routes.contains(Routes.quiz), isFalse);
    expect(await h.container.read(historyProvider.future), isEmpty);
  });
}
