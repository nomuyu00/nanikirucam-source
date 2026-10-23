import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:nanikiru_cam/core/app_settings.dart';
import 'package:nanikiru_cam/core/di.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ProviderContainer> container([Map<String, Object> prefs = const {}]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWith(
          (ref) => SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('既定値: 赤ドラ・喰いタン・通知は ON、撮るだけモードは OFF', () {
    const s = AppSettings();
    expect(s.redFives, isTrue);
    expect(s.openTanyao, isTrue);
    expect(s.quickCapture, isFalse);
    expect(s.notifyDaily && s.notifyWeekly && s.notifyAnswers && s.notifyStreak, isTrue);
    expect(s.liveSound, isFalse);
    expect(s.anyNotification, isTrue);
  });

  test('変更は settings_v1 に保存され、起動し直しても残る', () async {
    final c = await container();
    final notifier = c.read(appSettingsProvider.notifier);
    notifier.update((s) => s.copyWith(redFives: false, quickCapture: true));
    notifier.update((s) => s.copyWith(notifyDaily: false));
    await pumpEventQueue();

    final prefs = await SharedPreferences.getInstance();
    final json = jsonDecode(prefs.getString(AppSettingsNotifier.preferenceKey)!)
        as Map<String, Object?>;
    expect(json['redFives'], false);
    expect(json['quickCapture'], true);
    expect(json['notifyDaily'], false);
    expect(json['openTanyao'], true);

    final again = await container({
      AppSettingsNotifier.preferenceKey: prefs.getString(
        AppSettingsNotifier.preferenceKey,
      )!,
    });
    again.read(appSettingsProvider);
    await pumpEventQueue();
    final loaded = again.read(appSettingsProvider);
    expect(loaded.redFives, isFalse);
    expect(loaded.quickCapture, isTrue);
    expect(loaded.notifyDaily, isFalse);
    expect(loaded.openTanyao, isTrue);
  });

  test('replace で丸ごと置き換えられる（他担当の契約）', () async {
    final c = await container();
    c.read(appSettingsProvider.notifier).replace(
      const AppSettings(openTanyao: false, liveSound: true),
    );
    expect(c.read(appSettingsProvider).openTanyao, isFalse);
    expect(c.read(appSettingsProvider).liveSound, isTrue);
  });

  test('壊れた・古い保存データでも既定値で読める（未知の項目は無視）', () async {
    final c = await container({AppSettingsNotifier.preferenceKey: '{nope'});
    c.read(appSettingsProvider);
    await pumpEventQueue();
    expect(c.read(appSettingsProvider), const AppSettings());

    expect(
      AppSettings.fromJson({'redFives': false, 'future': 1, 'liveSound': 'x'}),
      const AppSettings(redFives: false),
    );
  });

  test('読み込み中に画面で変えた値は、保存された値で上書きしない', () async {
    final c = await container({
      AppSettingsNotifier.preferenceKey: jsonEncode({'redFives': false}),
    });
    final notifier = c.read(appSettingsProvider.notifier);
    notifier.update((s) => s.copyWith(openTanyao: false));
    await pumpEventQueue();
    expect(c.read(appSettingsProvider).openTanyao, isFalse);
  });

  test('reset で既定値に戻り、保存データも消える', () async {
    final c = await container();
    final notifier = c.read(appSettingsProvider.notifier);
    notifier.update((s) => s.copyWith(redFives: false));
    await pumpEventQueue();
    await notifier.reset();
    expect(c.read(appSettingsProvider), const AppSettings());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(AppSettingsNotifier.preferenceKey), isFalse);
  });
}
