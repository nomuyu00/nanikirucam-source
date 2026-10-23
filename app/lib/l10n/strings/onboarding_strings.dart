import 'package:flutter/widgets.dart';
import 'package:nanikiru_cam/l10n/app_strings.dart';

/// Onboarding（初回のみ）の文言。
class OnboardingStrings extends FeatureStrings {
  const OnboardingStrings(super.lang);

  String get title => tr('はじめに', 'Welcome');
  String get start => tr('はじめる', 'Get started');
  String get next => tr('次へ', 'Next');
  String get skip => tr('スキップ', 'Skip');

  // 3 枚のスライド（仕様 6.1「かざす」「自分で切る」「友達に出す」）。
  String get slide1Title => tr('かざす', 'Point');
  String get slide1Body => tr(
    '手牌にカメラを向けるだけで、どの牌を切ればよいかを案内します（ライブナビ）。写真を撮って解析することもできます。',
    'Point the camera at your hand and Live Navi suggests what to discard. You can also analyze a photo.',
  );
  String get slide2Title => tr('自分で切る', 'Decide first');
  String get slide2Body => tr(
    '答えを見る前に「あなたなら何を切る？」。速さ・打点・バランスの 3 つの答えと、狙える役・想定打点を比べられます。',
    'Before the answer, pick your own discard. Then compare it with the speed, points and balance answers, plus the yaku and value in reach.',
  );
  String get slide3Title => tr('友達に出す', 'Quiz friends');
  String get slide3Body => tr(
    '解いた手は、答えを隠した問題カードにして SNS で出題できます。リンクから誰でもアプリなしで回答できます。',
    'Turn any hand into a problem card with the answer hidden. Anyone can answer from the link, no app needed.',
  );

  // サーバーなしの版（Web での回答がない）の 3 枚目。端末内で完結する説明にする。
  String get slide3TitleOffline => tr('毎日3問', 'Daily problems');
  String get slide3BodyOffline => tr(
    '毎日、今日の問題を3問出します。解いた手は、答えを隠した問題カードの画像にして共有することもできます。',
    'Get three problems every day. You can also turn any hand into a problem card image with the answer hidden and share it.',
  );

  // マナーとお約束（仕様 6.1・8.4・15 章）。
  String get mannersTitle => tr('使う前に', 'Before you start');
  String get mannersFriendly => tr(
    'ライブナビは友人戦・練習用です。雀荘や大会では、お店や大会のルールに従ってください。',
    'Live Navi is for friendly games and practice. Follow the rules of any parlor or tournament.',
  );
  String get mannersCandidate => tr(
    '案内は受け入れ枚数と役・打点の計算に基づく「候補」です。最後に決めるのはあなたです。',
    'Suggestions are candidates based on tile counts, yaku and points. The final call is yours.',
  );
  String get mannersPrivacy => tr(
    '写真・カメラの映像は端末の外に送りません。',
    'Photos and camera video never leave your device.',
  );
  String referralReceived(String code) => tr(
    '招待コード $code を受け取りました。使うとあなたと友だちに Pro 7 日がつきます。',
    'You received invite code $code. Use it and you both get 7 days of Pro.',
  );
}

extension OnboardingStringsContext on BuildContext {
  OnboardingStrings get onboardingStrings => OnboardingStrings(lang);
}
