// 審査用の画面プレビュー生成。ストアとの接続・購入成功の証跡には使わない。
// flutter test tool/capture_paywall_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/account.dart';
import 'package:nanikiru_cam/core/analytics_sink.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:nanikiru_cam/core/entitlements.dart';
import 'package:nanikiru_cam/purchase/paywall_page.dart';
import 'package:nanikiru_cam/purchase/subscription_backend.dart';
import 'package:nanikiru_cam/purchase/subscription_service.dart';
import 'package:nanikiru_cam/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/billing_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    const fontPath = String.fromEnvironment(
      'JAPANESE_FONT_PATH',
      defaultValue: '/mnt/c/Windows/Fonts/meiryo.ttc',
    );
    final japanese = FontLoader('ReviewJapanese')
      ..addFont(File(fontPath).readAsBytes().then(ByteData.sublistView));
    await japanese.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  testWidgets('render the actual paywall with registered test prices', (
    tester,
  ) async {
    // test/ 外に置いた、flutter test で起動する画像生成ツール。
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionBackendProvider.overrideWithValue(
            FakeSubscriptionBackend(),
          ),
          revenueCatApiKeyProvider.overrideWithValue('review-preview-only'),
          sharedPreferencesProvider.overrideWith(
            (ref) => SharedPreferences.getInstance(),
          ),
          authUidProvider.overrideWith((ref) async => null),
          entitlementsProvider.overrideWith((ref) => EntitlementState.free),
          analyticsSinkProvider.overrideWithValue(
            (event, [parameters = const {}]) {},
          ),
        ],
        child: RepaintBoundary(
          key: captureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ja'),
            supportedLocales: const [Locale('ja'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // アプリと同じテーマ（ui/theme/）。
            theme: AppTheme.light(
              fontFamily: 'ReviewJapanese',
            ).copyWith(platform: TargetPlatform.iOS),
            home: const PaywallPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final kind in [PlanKind.monthly, PlanKind.yearly]) {
      final card = find.byKey(ValueKey('paywall-plan-${kind.name}'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('paywall-tokushoho')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 3);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        const outputDir = String.fromEnvironment(
          'REVIEW_OUTPUT_DIR',
          defaultValue:
              '/mnt/d/ProgramFiles/IdeaProjects/nanikirucam/docs/release-evidence',
        );
        await Directory(outputDir).create(recursive: true);
        await File(
          '$outputDir/paywall-${kind.name}-review-preview.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
