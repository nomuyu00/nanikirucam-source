// 流用元: reference/agari_cam/lib/core/app_language.dart（2026-10-21 時点）
// 改修: 既定を「端末の言語に従う」（null）にした。設定画面で ja / en を選ぶと保存する。
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const supportedAppLocales = [Locale('ja'), Locale('en')];

/// アプリの表示言語。null は端末の言語に従う（日本語・英語以外は日本語）。
final appLocaleProvider = StateNotifierProvider<AppLocaleController, Locale?>((
  ref,
) {
  final controller = AppLocaleController();
  controller.load();
  return controller;
});

class AppLocaleController extends StateNotifier<Locale?> {
  AppLocaleController() : super(null);

  static const _preferenceKey = 'app_locale_v1';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    state = _localeFromCode(prefs.getString(_preferenceKey));
  }

  /// [locale] が null なら端末の言語に従う設定に戻す。
  Future<void> setLocale(Locale? locale) async {
    final next = _localeFromCode(locale?.languageCode);
    state = next;
    final prefs = await SharedPreferences.getInstance();
    if (next == null) {
      await prefs.remove(_preferenceKey);
    } else {
      await prefs.setString(_preferenceKey, next.languageCode);
    }
  }

  Locale? _localeFromCode(String? code) {
    return switch (code) {
      'en' => const Locale('en'),
      'ja' => const Locale('ja'),
      _ => null,
    };
  }
}
