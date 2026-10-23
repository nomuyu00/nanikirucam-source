import 'package:flutter/widgets.dart';

/// 画面の言語。ja が主、en は従。端末の言語（または設定画面で選んだ言語）で切り替わる。
enum AppLang { ja, en }

extension AppLangContext on BuildContext {
  /// 今の言語（英語以外は日本語）。
  AppLang get lang => Localizations.localeOf(this).languageCode == 'en'
      ? AppLang.en
      : AppLang.ja;
}

/// 機能ごとの文言クラスの基底。
///
/// 文言は **機能ごとのファイル**（`lib/l10n/strings/<機能>_strings.dart`）に分け、
/// 1 ファイルに全部入れない（複数人の並行作業でぶつからないため）。書き方:
///
/// ```dart
/// // lib/l10n/strings/quiz_strings.dart
/// class QuizStrings extends FeatureStrings {
///   const QuizStrings(super.lang);
///   String get title => tr('何切る？', 'What to discard?');
///   String remaining(int n) => tr('残り$n枚', '$n left');
/// }
///
/// extension QuizStringsContext on BuildContext {
///   QuizStrings get quizStrings => QuizStrings(lang);
/// }
/// ```
///
/// 画面では `context.quizStrings.title`。テストでは `QuizStrings(AppLang.ja)` を直接作る。
abstract class FeatureStrings {
  const FeatureStrings(this.lang);

  final AppLang lang;

  bool get isEnglish => lang == AppLang.en;

  /// 日本語（主）と英語（従）の組から、今の言語の方を返す。
  String tr(String ja, String en) => isEnglish ? en : ja;
}
